"""Deliver SNS alarm notifications to Slack, Google Chat, Teams, or Asana."""

import json
import logging
import os
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

TARGET = os.environ["ALERT_TARGET"]
SECRET_NAME = os.environ["TARGET_SECRET_NAME"]
_secrets = boto3.client("secretsmanager")
_config = None


def _target_config():
    global _config
    if _config is None:
        response = _secrets.get_secret_value(SecretId=SECRET_NAME)
        _config = json.loads(response["SecretString"])
    return _config


def _alarm_message(message):
    try:
        alarm = json.loads(message)
    except (TypeError, json.JSONDecodeError):
        alarm = {"NewStateValue": "ALARM", "NewStateReason": str(message)}

    name = alarm.get("AlarmName", "CloudWatch alarm")
    state = alarm.get("NewStateValue", "ALARM")
    reason = alarm.get("NewStateReason", "No state reason provided")
    return name, state, reason, f"{name} is {state}: {reason}"


def _post(url, body, headers=None):
    request_headers = {"Content-Type": "application/json"}
    request_headers.update(headers or {})
    request = Request(
        url,
        data=json.dumps(body).encode("utf-8"),
        headers=request_headers,
        method="POST",
    )
    try:
        with urlopen(request, timeout=10) as response:
            if response.status >= 300:
                raise RuntimeError(f"Target returned HTTP {response.status}")
    except HTTPError as exc:
        raise RuntimeError(f"Target returned HTTP {exc.code}: {exc.read(1024)!r}") from exc
    except URLError as exc:
        raise RuntimeError(f"Could not reach alert target: {exc.reason}") from exc


def _deliver(message):
    name, state, reason, text = _alarm_message(message)
    config = _target_config()

    if TARGET in ("slack", "google_chat"):
        _post(config["webhook_url"], {"text": text})
    elif TARGET == "teams":
        card = {
            "@type": "MessageCard",
            "@context": "http://schema.org/extensions",
            "summary": text[:200],
            "text": text,
        }
        _post(config["webhook_url"], card)
    elif TARGET == "asana":
        if state != "ALARM":
            logger.info("Skipping Asana task creation for alarm state %s", state)
            return
        headers = {"Authorization": f"Bearer {config['access_token']}"}
        task = {
            "data": {
                "name": f"[{state}] {name}"[:255],
                "notes": f"{text}\n\nAlarm: {name}\nState: {state}\nReason: {reason}",
                "projects": [config["project_gid"]],
            }
        }
        _post("https://app.asana.com/api/1.0/tasks", task, headers)
    else:
        raise ValueError(f"Unsupported alert target: {TARGET}")


def lambda_handler(event, context):
    for record in event.get("Records", []):
        if record.get("EventSource") == "aws:sns":
            _deliver(record["Sns"]["Message"])
    return {"statusCode": 200}
