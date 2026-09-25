locals {
  function_name = "audit-pipeline-alerts-jira-notifier"
  table_name    = "audit-pipeline-alerts-jira-tickets"
}

resource "aws_secretsmanager_secret" "jira" {
  name        = var.secret_name
  description = "Jira Cloud credentials for audit pipeline alert ticketing. Populate out-of-band with JSON: {\"jira_url\": \"https://<workspace>.atlassian.net\", \"email\": \"...\", \"api_token\": \"...\", \"project_key\": \"...\", \"issue_type\": \"Task\", \"close_transition\": \"Done\"}."

  tags = var.tags
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_dynamodb_table" "tickets" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "alarm_name"

  attribute {
    name = "alarm_name"
    type = "S"
  }

  # Maps alarm -> Jira ticket so an ALARM never opens a second ticket
  # while one is already open; closed mappings expire via TTL.
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }

  tags = var.tags
}

data "aws_iam_policy_document" "notifier_assume_role" {
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
  assume_role_policy = data.aws_iam_policy_document.notifier_assume_role.json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "notifier_basic_execution" {
  role       = aws_iam_role.notifier.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "notifier_permissions" {
  statement {
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.jira.arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:UpdateItem",
    ]
    resources = [
      aws_dynamodb_table.tickets.arn,
      "${aws_dynamodb_table.tickets.arn}/index/*",
    ]
  }

  statement {
    effect    = "Allow"
    actions   = ["cloudwatch:DescribeAlarms"]
    resources = ["arn:aws:cloudwatch:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:alarm:*"]
  }
}

resource "aws_iam_role_policy" "notifier_permissions" {
  name   = "jira-notifier-permissions"
  role   = aws_iam_role.notifier.id
  policy = data.aws_iam_policy_document.notifier_permissions.json
}

resource "aws_cloudwatch_log_group" "notifier" {
  name              = "/aws/lambda/${local.function_name}"
  retention_in_days = var.log_retention_in_days

  tags = var.tags
}

data "archive_file" "notifier" {
  type        = "zip"
  source_file = "${path.module}/src/jira_notifier.py"
  output_path = "${path.module}/jira_notifier.zip"
}

resource "aws_lambda_function" "notifier" {
  filename         = data.archive_file.notifier.output_path
  function_name    = local.function_name
  role             = aws_iam_role.notifier.arn
  handler          = "jira_notifier.lambda_handler"
  runtime          = "python3.13"
  source_code_hash = data.archive_file.notifier.output_base64sha256

  timeout     = var.timeout
  memory_size = var.memory_size

  environment {
    variables = {
      JIRA_SECRET_NAME   = aws_secretsmanager_secret.jira.name
      TICKETS_TABLE_NAME = aws_dynamodb_table.tickets.name
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
