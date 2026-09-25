"""S3-triggered processor for raw EKS audit log deliveries.

The per-cluster Firehose delivery streams write the raw CloudWatch Logs
subscription records into each cluster's ephemeral raw bucket
(audit-logs-raw-<cluster>-<account>) under raw/cluster=<cluster>/year=.../
with no Firehose-side compression or transformation (the records are
already gzip-compressed by CloudWatch Logs). The raw buckets are purged
after a few days (they are only the reprocessing/replay security net);
the durable, compliance-protected copies live in the per-cluster
audit-logs-<cluster>-<account> bucket. This function is invoked by an S3
event notification for every new raw object and:

  1. Reads the raw object.
  2. Decodes each CloudWatch Logs envelope. Several byte layouts are
     handled:
     - concatenated raw gzip members (the documented CloudWatch Logs ->
       Firehose record format, detected via the gzip magic bytes). Raw
       objects can be tens of MB compressed (hundreds of MB decompressed),
       so this layout is processed STREAMING: the gzip stream is
       decompressed chunk by chunk, JSON envelopes are parsed
       incrementally, and the output is written as a single gzip stream
       via an S3 multipart upload. Memory stays bounded regardless of
       object size.
     - a single base64 blob (possibly of gzip data), covering synthetic
       records put through `firehose put-record` with base64 payloads, and
     - newline-separated records, each either base64(gzip) or plain JSON
       (synthetic/test objects).
     These non-gzip layouts are only produced by small synthetic tests and
     are handled in memory.
  3. Drops CONTROL_MESSAGE health checks and every record not originating
     from a kube-apiserver-audit-* log stream (all other EKS control plane
     log types are filtered out here instead of at the Firehose layer, so
     the delivery path has no size constraints at all).
  4. Writes the surviving audit event messages as gzip-compressed
     newline-delimited JSON into the cluster's compliance bucket
     (the raw bucket name minus the "raw-" element) under the queryable
     partition layout cluster=<cluster>/year=.../hour=.../<raw object
     name>.gz that the Glue table reads. The target key is derived from
     the raw object key, so reprocessing the same raw object overwrites
     the same target (idempotent).

The raw objects themselves are never modified or deleted: they are the
replay source until their bucket's lifecycle expires them. If this
function fails after Lambda's asynchronous retries, the event is routed
to the SQS dead-letter queue and the raw object simply stays in place
for manual reprocessing.
"""

import base64
import binascii
import codecs
import gzip
import io
import json
import logging
import re
import urllib.parse
import zlib

import boto3

logging.getLogger().setLevel(logging.INFO)
logger = logging.getLogger()

AUDIT_LOG_STREAM_PREFIX = "kube-apiserver-audit"
RAW_PREFIX = "raw/"
RAW_ERRORS_INFIX = "/errors/"

# Raw deliveries land in audit-logs-raw-<cluster>-<account>; the durable
# queryable copies are written to audit-logs-<cluster>-<account>.
RAW_BUCKET_PREFIX = "audit-logs-raw-"
PROCESSED_BUCKET_PREFIX = "audit-logs-"

GZIP_MAGIC = b"\x1f\x8b"

# One padded base64 payload: a run of alphabet characters plus up to two
# trailing '=' (see _split_base64_chunks).
_BASE64_CHUNK_RE = re.compile(rb"[A-Za-z0-9+/]+={0,2}")

# Decompressed bytes pulled from the gzip stream per step.
STREAM_CHUNK_BYTES = 1024 * 1024
# Compressed output bytes buffered before flushing one multipart-upload
# part (S3 requires >= 5 MB per part, except for the last one).
OUTPUT_PART_BYTES = 8 * 1024 * 1024


def _decompress_all_members(compressed: bytes) -> bytes:
    # A raw object is a concatenation of gzip members (one per CloudWatch
    # Logs batch). Read them all; a truncated/corrupt stream raises and
    # fails the invocation loudly (Lambda retries, then DLQ). Only used by
    # the in-memory path for small synthetic objects.
    result = io.BytesIO()
    stream = io.BytesIO(compressed)
    while stream.tell() < len(compressed):
        with gzip.GzipFile(fileobj=stream) as gz:
            result.write(gz.read())
    return result.getvalue()


def _iter_json_objects(text: str):
    # The decompressed members are concatenated JSON documents, possibly
    # with no separator between them.
    decoder = json.JSONDecoder()
    index = 0
    length = len(text)
    while index < length:
        while index < length and text[index] in " \t\r\n":
            index += 1
        if index >= length:
            break
        obj, index = decoder.raw_decode(text, index)
        yield obj


def _try_base64(data: bytes):
    # Strict decode: returns None unless data is a single well-formed
    # base64 blob.
    try:
        return base64.b64decode(data, validate=True)
    except (binascii.Error, ValueError):
        return None


def _split_base64_chunks(data: bytes):
    # Firehose concatenates record bytes without separators, so an object
    # can hold several padded base64 payloads back to back. Padding '='
    # characters only ever terminate a payload, so splitting the runs of
    # alphabet characters at the padding boundaries yields individually
    # decodable chunks. Returns None if the data is not purely base64.
    chunks = []
    pos = 0
    for match in _BASE64_CHUNK_RE.finditer(data):
        if match.start() != pos:
            return None
        chunks.append(match.group())
        pos = match.end()
    if pos != len(data) or not chunks:
        return None
    return chunks


def _decode_base64_payloads(raw_bytes: bytes):
    # Decode a whole-object base64 payload, or several concatenated ones.
    decoded = _try_base64(raw_bytes)
    if decoded is not None:
        return decoded
    chunks = _split_base64_chunks(raw_bytes)
    if chunks is None:
        return None
    try:
        return b"".join(base64.b64decode(chunk) for chunk in chunks)
    except (binascii.Error, ValueError):
        return None


def _iter_envelopes(raw_bytes: bytes):
    if not raw_bytes.strip():
        return

    # 1. Concatenated gzip members.
    if raw_bytes.startswith(GZIP_MAGIC):
        decompressed = _decompress_all_members(raw_bytes)
        yield from _iter_json_objects(decompressed.decode("utf-8"))
        return

    # 2. The whole object is base64 (possibly of gzip data).
    decoded = _decode_base64_payloads(raw_bytes.strip())
    if decoded is not None:
        if decoded.startswith(GZIP_MAGIC):
            decompressed = _decompress_all_members(decoded)
            yield from _iter_json_objects(decompressed.decode("utf-8"))
            return
        yield from _iter_json_objects(decoded.decode("utf-8"))
        return

    # 3. Line-oriented fallbacks (synthetic/test objects): one
    #    base64(gzip) envelope or one plain JSON envelope per line.
    for line in raw_bytes.splitlines():
        line = line.strip()
        if not line:
            continue
        decoded = _try_base64(line)
        if decoded is not None and decoded.startswith(GZIP_MAGIC):
            yield json.loads(_decompress_all_members(decoded))
            continue
        yield json.loads(line)


def _is_audit_log_stream(log_stream_name: str) -> bool:
    return log_stream_name.startswith(AUDIT_LOG_STREAM_PREFIX)


def _record_origin(envelope: dict) -> str:
    owner = envelope.get("owner", "")
    log_group = envelope.get("logGroup", "")
    if owner and log_group:
        return f"account={owner} log_group={log_group}"
    return owner or log_group or "unknown"


def _tally(stats: dict, origin: str, key: str) -> None:
    counts = stats.setdefault(origin, {"kept": 0, "dropped": 0, "control": 0})
    counts[key] += 1


def _target_key(raw_key: str) -> str:
    # raw/cluster=<c>/year=<y>/.../<name> -> cluster=<c>/year=<y>/.../<name>.gz
    return raw_key[len(RAW_PREFIX):] + ".gz"


def _processed_bucket(raw_bucket: str) -> str:
    # audit-logs-raw-<cluster>-<account> -> audit-logs-<cluster>-<account>
    if not raw_bucket.startswith(RAW_BUCKET_PREFIX):
        raise ValueError(f"Unexpected raw bucket name: {raw_bucket!r}")
    return PROCESSED_BUCKET_PREFIX + raw_bucket[len(RAW_BUCKET_PREFIX):]


def _origin_summary(origin_stats: dict) -> str:
    if not origin_stats:
        return "none"
    return "; ".join(
        f"{origin}: {counts['kept']} kept, {counts['dropped']} dropped, "
        f"{counts['control']} control"
        for origin, counts in origin_stats.items()
    )


def _handle_envelope(envelope: dict, origin_stats: dict, emit) -> None:
    # Applies the keep/drop rules to one CloudWatch Logs envelope and calls
    # emit(message) for every kept audit log event message.
    origin = _record_origin(envelope)
    message_type = envelope.get("messageType")

    if message_type == "CONTROL_MESSAGE":
        # CloudWatch Logs periodic health-check message.
        _tally(origin_stats, origin, "control")
        return

    if message_type != "DATA_MESSAGE":
        logger.warning(
            "Unexpected messageType '%s' (origin %s), dropping",
            message_type,
            origin,
        )
        _tally(origin_stats, origin, "dropped")
        return

    if not _is_audit_log_stream(envelope.get("logStream", "")):
        _tally(origin_stats, origin, "dropped")
        return

    kept = 0
    for log_event in envelope.get("logEvents", []):
        message = log_event.get("message")
        if message:
            emit(message)
            kept += 1

    _tally(origin_stats, origin, "kept" if kept else "dropped")


def _iter_json_from_stream(read_chunk):
    # Incrementally yields JSON objects from a text stream of concatenated
    # (possibly unseparated) JSON documents, keeping the look-ahead buffer
    # bounded by trimming consumed input.
    decoder = json.JSONDecoder()
    buffer = ""
    index = 0
    eof = False

    while True:
        while True:
            length = len(buffer)
            while index < length and buffer[index] in " \t\r\n":
                index += 1
            if index >= length:
                break
            try:
                obj, index = decoder.raw_decode(buffer, index)
            except json.JSONDecodeError:
                if eof:
                    raise
                break  # object likely incomplete; pull more data
            yield obj

        if index:
            buffer = buffer[index:]
            index = 0

        if eof:
            if buffer.strip():
                raise ValueError("Trailing unparsable JSON in raw object")
            return

        chunk = read_chunk()
        if not chunk:
            eof = True
        else:
            buffer += chunk


class _S3GzipWriter:
    # Streams gzip-compressed output to S3. Compressed bytes are buffered
    # and flushed as multipart-upload parts once they reach OUTPUT_PART_BYTES,
    # so the output size is unbounded while memory stays flat. Objects that
    # end up smaller than one part are written with a plain PutObject.
    # The final object is a single continuous gzip stream.

    def __init__(self, s3, bucket: str, key: str):
        self._s3 = s3
        self._bucket = bucket
        self._key = key
        self._compressor = zlib.compressobj(level=6, wbits=31)  # gzip wrapper
        self._buffer = bytearray()
        self._upload_id = None
        self._parts = []
        self._part_number = 1
        self.total_bytes = 0

    def write(self, data: bytes) -> None:
        compressed = self._compressor.compress(data)
        if compressed:
            self._buffer.extend(compressed)
            self._flush_full_parts()

    def _flush_full_parts(self) -> None:
        while len(self._buffer) >= OUTPUT_PART_BYTES:
            self._upload_part(bytes(self._buffer[:OUTPUT_PART_BYTES]))
            del self._buffer[:OUTPUT_PART_BYTES]

    def _upload_part(self, body: bytes) -> None:
        if self._upload_id is None:
            response = self._s3.create_multipart_upload(
                Bucket=self._bucket, Key=self._key
            )
            self._upload_id = response["UploadId"]
        response = self._s3.upload_part(
            Bucket=self._bucket,
            Key=self._key,
            UploadId=self._upload_id,
            PartNumber=self._part_number,
            Body=body,
        )
        self._parts.append({"ETag": response["ETag"], "PartNumber": self._part_number})
        self._part_number += 1
        self.total_bytes += len(body)

    def close(self) -> int:
        tail = self._compressor.flush(zlib.Z_FINISH)
        if tail:
            self._buffer.extend(tail)

        if self._upload_id is None:
            body = bytes(self._buffer)
            self._s3.put_object(Bucket=self._bucket, Key=self._key, Body=body)
            self.total_bytes = len(body)
            return self.total_bytes

        if self._buffer:
            self._upload_part(bytes(self._buffer))
            self._buffer.clear()
        self._s3.complete_multipart_upload(
            Bucket=self._bucket,
            Key=self._key,
            UploadId=self._upload_id,
            MultipartUpload={"Parts": self._parts},
        )
        return self.total_bytes

    def abort(self) -> None:
        if self._upload_id is not None:
            try:
                self._s3.abort_multipart_upload(
                    Bucket=self._bucket, Key=self._key, UploadId=self._upload_id
                )
            except Exception:
                logger.warning(
                    "Failed to abort multipart upload for s3://%s/%s",
                    self._bucket,
                    self._key,
                )
            self._upload_id = None


def _process_gzip_stream(s3, target_bucket, target_key, compressed_stream, origin_stats):
    # Streaming path for the documented CloudWatch Logs -> Firehose layout:
    # decompress chunk by chunk, parse envelopes incrementally, stream the
    # kept messages to the target object. Returns (event_count, total_bytes).
    gz = gzip.GzipFile(fileobj=compressed_stream)
    utf8 = codecs.getincrementaldecoder("utf-8")()
    writer = _S3GzipWriter(s3, target_bucket, target_key)
    event_count = 0

    def read_text_chunk():
        raw = gz.read(STREAM_CHUNK_BYTES)
        if not raw:
            return utf8.decode(b"", True)
        return utf8.decode(raw)

    def emit(message):
        nonlocal event_count
        writer.write(message.encode("utf-8") + b"\n")
        event_count += 1

    try:
        for envelope in _iter_json_from_stream(read_text_chunk):
            _handle_envelope(envelope, origin_stats, emit)
    except Exception:
        writer.abort()
        raise

    if event_count == 0:
        writer.abort()  # nothing written; nothing to finalize
        return 0, 0

    return event_count, writer.close()


def _extract_audit_events(raw_bytes: bytes, origin_stats: dict) -> str:
    # In-memory path, only used for the small synthetic (non-gzip) objects.
    messages = []
    for envelope in _iter_envelopes(raw_bytes):
        _handle_envelope(envelope, origin_stats, messages.append)
    return "\n".join(messages) + "\n" if messages else ""


def _process_object(s3, bucket: str, raw_key: str) -> None:
    logger.info("Processing s3://%s/%s", bucket, raw_key)

    target_bucket = _processed_bucket(bucket)
    target_key = _target_key(raw_key)

    response = s3.get_object(Bucket=bucket, Key=raw_key)
    raw_bytes = response["Body"].read()

    origin_stats = {}

    if raw_bytes.startswith(GZIP_MAGIC):
        try:
            event_count, total_bytes = _process_gzip_stream(
                s3, target_bucket, target_key, io.BytesIO(raw_bytes), origin_stats
            )
        except Exception as exc:
            # Make failures self-diagnosing: the DLQ only carries the S3
            # event, so log exactly what was being processed.
            logger.error(
                "Failed to process s3://%s/%s (%d bytes): %s",
                bucket,
                raw_key,
                len(raw_bytes),
                exc,
            )
            raise

        if event_count:
            logger.info(
                "Wrote s3://%s/%s (%d events, %d bytes) from s3://%s/%s by origin: %s",
                target_bucket,
                target_key,
                event_count,
                total_bytes,
                bucket,
                raw_key,
                _origin_summary(origin_stats),
            )
        else:
            logger.info(
                "No audit events in s3://%s/%s (%d bytes) by origin: %s",
                bucket,
                raw_key,
                len(raw_bytes),
                _origin_summary(origin_stats),
            )
        return

    # Small synthetic object (base64 / plain JSON test payloads).
    try:
        ndjson = _extract_audit_events(raw_bytes, origin_stats)
    except Exception as exc:
        logger.error(
            "Failed to process s3://%s/%s (%d bytes, first bytes %r): %s",
            bucket,
            raw_key,
            len(raw_bytes),
            raw_bytes[:64],
            exc,
        )
        raise

    if not ndjson:
        logger.info(
            "No audit events in s3://%s/%s (%d bytes) by origin: %s",
            bucket,
            raw_key,
            len(raw_bytes),
            _origin_summary(origin_stats),
        )
        return

    compressed = io.BytesIO()
    with gzip.GzipFile(fileobj=compressed, mode="wb") as gz:
        gz.write(ndjson.encode("utf-8"))

    s3.put_object(Bucket=target_bucket, Key=target_key, Body=compressed.getvalue())

    logger.info(
        "Wrote s3://%s/%s (%d events, %d bytes) from s3://%s/%s by origin: %s",
        target_bucket,
        target_key,
        ndjson.count("\n"),
        len(compressed.getvalue()),
        bucket,
        raw_key,
        _origin_summary(origin_stats),
    )


def lambda_handler(event, context):
    s3 = boto3.client("s3")

    for record in event.get("Records", []):
        s3_record = record.get("s3", {})
        bucket = s3_record.get("bucket", {}).get("name", "")
        key = urllib.parse.unquote_plus(s3_record.get("object", {}).get("key", ""))

        if not bucket or not key:
            logger.warning("Skipping malformed S3 event record")
            continue

        # Firehose error output objects are not raw delivery batches.
        if not key.startswith(RAW_PREFIX) or RAW_ERRORS_INFIX in key:
            logger.info("Skipping non-raw object s3://%s/%s", bucket, key)
            continue

        _process_object(s3, bucket, key)
