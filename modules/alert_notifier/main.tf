locals {
  function_name = "audit-pipeline-alert-notifier"
}

resource "aws_secretsmanager_secret" "target" {
  name        = var.secret_name
  description = "Credentials for the selected audit pipeline alert target (${var.target}). Populate out-of-band."
  tags        = var.tags
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "notifier" {
  name               = "${local.function_name}-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.notifier.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "secret_read" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.target.arn]
  }
}

resource "aws_iam_role_policy" "secret_read" {
  name   = "${local.function_name}-secret-read"
  role   = aws_iam_role.notifier.id
  policy = data.aws_iam_policy_document.secret_read.json
}

resource "aws_cloudwatch_log_group" "notifier" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_in_days
  tags              = var.tags
}

data "archive_file" "notifier" {
  type        = "zip"
  source_file = "${path.module}/src/alert_notifier.py"
  output_path = "${path.module}/alert_notifier.zip"
}

resource "aws_lambda_function" "notifier" {
  filename         = data.archive_file.notifier.output_path
  function_name    = local.function_name
  role             = aws_iam_role.notifier.arn
  handler          = "alert_notifier.lambda_handler"
  runtime          = "python3.13"
  source_code_hash = data.archive_file.notifier.output_base64sha256
  timeout          = 20
  memory_size      = 128

  environment {
    variables = {
      ALERT_TARGET       = var.target
      TARGET_SECRET_NAME = aws_secretsmanager_secret.target.name
    }
  }

  logging_config {
    log_format = "JSON"
    log_group  = aws_cloudwatch_log_group.notifier.name
  }

  tags = var.tags
}

resource "aws_lambda_permission" "sns_invoke" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notifier.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.sns_topic_arn
}

resource "aws_sns_topic_subscription" "notifier" {
  topic_arn = var.sns_topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.notifier.arn
}
