# S3-event-triggered processor that turns the raw CloudWatch Logs deliveries
# (raw/cluster=... objects written by the per-cluster Firehose streams) into
# the queryable gzip-compressed NDJSON partition layout read by the Glue
# table. Replaces the old inline Firehose data-transformation Lambda, whose
# synchronous ~6 MB response limit overflowed on busy clusters - here the
# work is asynchronous per S3 object and can scale freely.

locals {
  function_name = "audit-logs-processor"
  dlq_name      = "audit-logs-processor-dlq"
}

data "archive_file" "processor" {
  type        = "zip"
  source_file = "${path.module}/src/audit_logs_processor.py"
  output_path = "${path.module}/audit_logs_processor.zip"
}

data "aws_iam_policy_document" "processor_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "processor" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.processor_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "processor_basic_execution" {
  role       = aws_iam_role.processor.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "processor_permissions" {
  statement {
    sid    = "ReadRawObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = ["arn:aws:s3:::audit-logs-raw-*/raw/*"]
  }

  statement {
    sid    = "WriteProcessedObjects"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload",
    ]
    resources = ["arn:aws:s3:::audit-logs-*/cluster=*"]
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

  statement {
    sid       = "SendToDlq"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.processor_dlq.arn]
  }
}

resource "aws_iam_role_policy" "processor_permissions" {
  name   = "audit-logs-processor-permissions"
  role   = aws_iam_role.processor.id
  policy = data.aws_iam_policy_document.processor_permissions.json
}

resource "aws_cloudwatch_log_group" "processor" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_in_days

  tags = var.tags
}

resource "aws_sqs_queue" "processor_dlq" {
  name                      = local.dlq_name
  message_retention_seconds = 1209600 # 14 days, keeps failed raw batches replayable

  tags = var.tags
}

resource "aws_lambda_function" "processor" {
  filename         = data.archive_file.processor.output_path
  function_name    = local.function_name
  role             = aws_iam_role.processor.arn
  handler          = "audit_logs_processor.lambda_handler"
  runtime          = "python3.13"
  source_code_hash = data.archive_file.processor.output_base64sha256

  timeout     = var.timeout
  memory_size = var.memory_size

  dead_letter_config {
    target_arn = aws_sqs_queue.processor_dlq.arn
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.processor.name
  }

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "processor_dlq_messages" {
  alarm_name          = "audit-logs-processor-dlq"
  alarm_description   = "Raw audit log objects are failing processing and landing in the dead-letter queue; replay or inspect them (the raw objects remain in the raw bucket under raw/ until their lifecycle expires them)."
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    QueueName = aws_sqs_queue.processor_dlq.name
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = var.tags
}
