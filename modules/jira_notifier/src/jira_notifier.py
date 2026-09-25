"""SNS -> Jira ticketing notifier for the audit log pipeline alarms.

Subscribed to an SNS topic carrying CloudWatch alarm state-change
notifications, both the audit account's own alarms and the spoke
accounts' forwarding inactivity alarms published cross-account. For each
alarm this Lambda:

  * ALARM  -> opens a Jira ticket. At most ONE ticket exists per alarm
              incident: while that ticket is open, repeated ALARM
              notifications (re-evaluations, flapping) never create
              duplicates.
  * OK     -> closes (transitions) the ticket opened for that alarm.
  * INSUFFICIENT_DATA -> ignored; ticket state is left untouched.

The alarm -> ticket mapping is tracked in a DynamoDB table keyed by
alarm name, using conditional writes so exactly one ticket per incident
survives even concurrent or duplicate SNS deliveries. For alarms owned
by the audit account itself the live alarm state is checked via
DescribeAlarms before acting, so stale/flapped notifications act on the
real state rather than the state carried by the message; spoke-account
alarms cannot be queried cross-account and act on the notification
state. Closed mappings expire via DynamoDB TTL.

Jira credentials are read from Secrets Manager (JSON):
  {"jira_url": "https://<workspace>.atlassian.net",
   "email": "<jira user email>",
   "api_token": "<api token from id.atlassian.net>",
   "project_key": "AUD",
   "issue_type": "Task",
   "close_transition": "Done"}
Only close_transition and issue_type are optional.
"""

import base64
import json
import logging
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request

import boto3
from botocore.exceptions import ClientError

logging.getLogger().setLevel(logging.INFO)
logger = logging.getLogger()

JIRA_SECRET_NAME = os.environ["JIRA_SECRET_NAME"]

ACCOUNT_ID_RE = re.compile(r"(?:^|-)(?P<account>\d{12})(?:-|$)")

FALLBACK_CLOSE_TRANSITIONS = ("done", "close", "closed", "resolve", "resolved")
CLOSED_STATUSES = ("done", "closed", "resolved")
STALE_CREATING_SECONDS = 300
CLOSED_RETENTION_SECONDS = 30 * 24 * 60 * 60

_dynamodb = boto3.resource("dynamodb")
_table = _dynamodb.Table(os.environ["TICKETS_TABLE_NAME"])
_cloudwatch = boto3.client("cloudwatch")
_secretsmanager = boto3.client("secretsmanager")

_jira_config = None


def _get_jira_config() -> dict:
    global _jira_config
    if _jira_config is None:
        secret = _secretsmanager.get_secret_value(SecretId=JIRA_SECRET_NAME)
        _jira_config = json.loads(secret["SecretString"])
    return _jira_config


def _jira_request(config: dict, method: str, path: str, body: dict | None = None):
    url = config["jira_url"].rstrip("/") + path
    credentials = f"{config['email']}:{config['api_token']}".encode("utf-8")
    headers = {
        "Authorization": "Basic " + base64.b64encode(credentials).decode("ascii"),
        "Accept": "application/json",
    }
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode("utf-8")

    request = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=15) as response:
            raw = response.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")[:500]
        raise RuntimeError(f"Jira API {method} {path} returned {exc.code}: {detail}") from exc


def _adf_doc(lines) -> dict:
    return {
        "type": "doc",
        "version": 1,
        "content": [
            {"type": "paragraph", "content": [{"type": "text", "text": line}]}
            for line in lines
            if line
        ],
    }


def _parse_alarm(sns_message: str) -> dict:
    try:
        return json.loads(sns_message)
    except (TypeError, ValueError):
        return {}


def _account_from_arn(arn: str) -> str:
    parts = arn.split(":")
    return parts[4] if len(parts) > 4 else ""


def _region_from_arn(arn: str) -> str:
    parts = arn.split(":")
    return parts[3] if len(parts) > 3 else ""


def _origin_account(alarm_name: str) -> str:
    match = ACCOUNT_ID_RE.search(alarm_name)
    return match.group("account") if match else ""


def _alarm_url(alarm: dict) -> str:
    region = _region_from_arn(alarm.get("AlarmArn", ""))
    return (
        "https://console.aws.amazon.com/cloudwatch/home"
        f"?region={region}#alarmsV2:alarm/"
        + urllib.parse.quote(alarm.get("AlarmName", ""), safe="")
    )


def _current_state(alarm_name: str):
    response = _cloudwatch.describe_alarms(AlarmNames=[alarm_name])
    alarms = response.get("MetricAlarms", []) + response.get("CompositeAlarms", [])
    return alarms[0]["StateValue"] if alarms else None


def _create_issue(config: dict, alarm: dict, source: str) -> str:
    alarm_name = alarm.get("AlarmName", "")
    region = _region_from_arn(alarm.get("AlarmArn", ""))
    account = _origin_account(alarm_name)

    body = {
        "fields": {
            "project": {"key": config["project_key"]},
            "issuetype": {"name": config.get("issue_type", "Task")},
            "summary": f"ALARM: {alarm_name}"[:250],
            "description": _adf_doc(
                [
                    f"Status: {alarm.get('NewStateValue', 'ALARM')}",
                    f"Alarm: {alarm_name}",
                    f"Source: {source}",
                    f"Origin account: {account}",
                    f"Region: {region}",
                    f"Reason: {alarm.get('NewStateReason', '')}",
                    f"State change time: {alarm.get('StateChangeTime', '')}",
                    _alarm_url(alarm),
                    alarm.get("AlarmDescription") or "",
                ]
            ),
        }
    }
    response = _jira_request(config, "POST", "/rest/api/3/issue", body)
    return response["key"]


def _close_issue(config: dict, issue_key: str) -> None:
    issue = _jira_request(config, "GET", f"/rest/api/3/issue/{issue_key}?fields=status")
    status = issue.get("fields", {}).get("status", {}).get("name", "").lower()
    if status in CLOSED_STATUSES:
        logger.info("%s is already closed (status %s)", issue_key, status)
        return

    data = _jira_request(config, "GET", f"/rest/api/3/issue/{issue_key}/transitions")
    transitions = data.get("transitions", [])
    wanted = {config.get("close_transition", "").strip().lower()}
    wanted.update(FALLBACK_CLOSE_TRANSITIONS)
    wanted.discard("")
    match = next((t for t in transitions if t.get("name", "").strip().lower() in wanted), None)
    if match is None:
        names = [t.get("name") for t in transitions]
        raise RuntimeError(f"No closing transition for {issue_key}; available: {names}")

    _jira_request(
        config,
        "POST",
        f"/rest/api/3/issue/{issue_key}/transitions",
        {"transition": {"id": match["id"]}},
    )
    logger.info("Closed %s via transition %r", issue_key, match.get("name"))


def _ensure_ticket(alarm: dict, source: str) -> None:
    alarm_name = alarm["AlarmName"]
    now = int(time.time())

    try:
        _table.put_item(
            Item={
                "alarm_name": alarm_name,
                "ticket_status": "creating",
                "creating_at": now,
                "opened_at": alarm.get("StateChangeTime", ""),
            },
            ConditionExpression=(
                "attribute_not_exists(ticket_status) "
                "OR ticket_status IN (:closed, :failed) "
                "OR (ticket_status = :creating AND creating_at < :stale)"
            ),
            ExpressionAttributeValues={
                ":closed": "closed",
                ":failed": "failed",
                ":creating": "creating",
                ":stale": now - STALE_CREATING_SECONDS,
            },
        )
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            logger.info("Ticket already open or being created for %s; not creating another", alarm_name)
            return
        raise

    config = _get_jira_config()
    try:
        issue_key = _create_issue(config, alarm, source)
    except Exception:
        _table.update_item(
            Key={"alarm_name": alarm_name},
            UpdateExpression="SET ticket_status = :failed",
            ExpressionAttributeValues={":failed": "failed"},
        )
        raise

    _table.update_item(
        Key={"alarm_name": alarm_name},
        UpdateExpression=(
            "SET ticket_status = :open, jira_issue_key = :key, last_state_change = :ts"
        ),
        ExpressionAttributeValues={
            ":open": "open",
            ":key": issue_key,
            ":ts": alarm.get("StateChangeTime", ""),
        },
    )
    logger.info("Opened %s for alarm %s", issue_key, alarm_name)


def _close_ticket(alarm: dict) -> None:
    alarm_name = alarm["AlarmName"]

    try:
        item = _table.update_item(
            Key={"alarm_name": alarm_name},
            UpdateExpression="SET ticket_status = :closing",
            ConditionExpression="ticket_status = :open",
            ExpressionAttributeValues={":closing": "closing", ":open": "open"},
            ReturnValues="ALL_NEW",
        )["Attributes"]
    except ClientError as exc:
        if exc.response["Error"]["Code"] == "ConditionalCheckFailedException":
            logger.info("No open ticket for %s; nothing to close", alarm_name)
            return
        raise

    issue_key = item.get("jira_issue_key", "")
    if not issue_key:
        logger.warning("Open ticket record for %s has no Jira issue key; marking closed", alarm_name)
        issue_key = None

    config = _get_jira_config()
    try:
        if issue_key:
            _close_issue(config, issue_key)
    except Exception:
        _table.update_item(
            Key={"alarm_name": alarm_name},
            UpdateExpression="SET ticket_status = :open",
            ExpressionAttributeValues={":open": "open"},
        )
        raise

    _table.update_item(
        Key={"alarm_name": alarm_name},
        UpdateExpression="SET ticket_status = :closed, closed_at = :ts, expires_at = :exp",
        ExpressionAttributeValues={
            ":closed": "closed",
            ":ts": alarm.get("StateChangeTime", ""),
            ":exp": int(time.time()) + CLOSED_RETENTION_SECONDS,
        },
    )
    logger.info("Closed ticket for alarm %s", alarm_name)


def _handle_alarm(alarm: dict, topic_arn: str) -> None:
    alarm_name = alarm["AlarmName"]
    central_account = _account_from_arn(topic_arn)
    alarm_account = _account_from_arn(alarm.get("AlarmArn", ""))
    source = "Audit account" if alarm_account == central_account else "Spoke account"

    state = alarm.get("NewStateValue", "")
    if alarm_account and alarm_account == central_account:
        live = _current_state(alarm_name)
        if live and live != state:
            logger.info(
                "Notification says %s but %s is currently %s; acting on live state",
                state,
                alarm_name,
                live,
            )
            state = live
    else:
        logger.info(
            "Cross-account alarm from %s; acting on notification state %s",
            alarm_account or "unknown",
            state,
        )

    if state == "ALARM":
        _ensure_ticket(alarm, source)
    elif state == "OK":
        _close_ticket(alarm)
    else:
        logger.info("State %s for %s: nothing to do", state, alarm_name)


def lambda_handler(event, context):
    for record in event.get("Records", []):
        sns = record.get("Sns", {})
        message = sns.get("Message", "")
        alarm = _parse_alarm(message)

        if not alarm or not alarm.get("AlarmName"):
            logger.warning("Skipping non-alarm SNS message: %.200s", message)
            continue

        _handle_alarm(alarm, sns.get("TopicArn", ""))
