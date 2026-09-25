data "aws_iam_policy_document" "firehose_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["firehose.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "firehose" {
  name               = "firehose-${local.base_name}"
  assume_role_policy = data.aws_iam_policy_document.firehose_assume_role.json

  tags = var.tags
}

data "aws_iam_policy_document" "firehose_permissions" {
  statement {
    sid    = "S3Delivery"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetBucketLocation",
      "s3:GetObject",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:PutObject",
    ]
    resources = [
      aws_s3_bucket.raw.arn,
      "${aws_s3_bucket.raw.arn}/*",
    ]
  }

  statement {
    sid    = "OwnLogging"
    effect = "Allow"
    actions = [
      "logs:PutLogEvents",
    ]
    resources = [
      "${aws_cloudwatch_log_group.firehose.arn}:*",
    ]
  }

  statement {
    sid    = "KmsUse"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]
    resources = [var.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "firehose_permissions" {
  name   = "firehose-permissions"
  role   = aws_iam_role.firehose.id
  policy = data.aws_iam_policy_document.firehose_permissions.json
}

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/kinesisfirehose/${local.base_name}"
  retention_in_days = 30

  tags = var.tags
}

resource "aws_cloudwatch_log_stream" "firehose_s3_delivery" {
  name           = "S3Delivery"
  log_group_name = aws_cloudwatch_log_group.firehose.name
}

resource "aws_kinesis_firehose_delivery_stream" "audit_logs" {
  name        = local.base_name
  destination = "extended_s3"

  extended_s3_configuration {
    role_arn   = aws_iam_role.firehose.arn
    bucket_arn = aws_s3_bucket.raw.arn

    # Firehose delivers the raw CloudWatch Logs subscription records
    # verbatim under raw/. There is deliberately NO data transformation in
    # the delivery path (the old inline filter Lambda overflowed its ~6 MB
    # synchronous response limit on busy clusters); the asynchronous
    # processor Lambda (see the processor_lambda module and the bucket
    # notification in s3_notification.tf) turns each raw object into the
    # queryable cluster=.../year=.../hour=... NDJSON layout afterwards.
    prefix              = "raw/cluster=${var.cluster_name}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/"
    error_output_prefix = "errors/cluster=${var.cluster_name}/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/!{firehose:error-output-type}/"

    buffering_size     = var.buffering_size_mb
    buffering_interval = var.buffering_interval_seconds
    # Each record is already gzip-compressed by CloudWatch Logs; adding
    # Firehose-side GZIP would wrap them in a second gzip layer that the
    # processor Lambda should not have to unwrap on replay.
    compression_format = "UNCOMPRESSED"

    kms_key_arn = var.kms_key_arn

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = aws_cloudwatch_log_stream.firehose_s3_delivery.name
    }

    # S3 backup is intentionally disabled: with no data transformation in
    # the delivery path there are no ProcessingFailed records to back up
    # (the only mode that would make sense, FailedDataOnly, is not
    # exposed by the AWS provider, and Enabled would duplicate every
    # record). Failed S3 deliveries are retried by Firehose for 24 hours
    # and surfaced by the DeliveryToS3.Success / DataFreshness alarms.
    s3_backup_mode = "Disabled"
  }

  tags = var.tags
}
