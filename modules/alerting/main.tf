resource "aws_sns_topic" "audit_pipeline_alerts" {
  name = "audit-pipeline-alerts"
  tags = var.tags
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "audit_pipeline_alerts" {
  statement {
    sid    = "__default_statement_ID"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "SNS:GetTopicAttributes",
      "SNS:SetTopicAttributes",
      "SNS:AddPermission",
      "SNS:RemovePermission",
      "SNS:DeleteTopic",
      "SNS:Subscribe",
      "SNS:ListSubscriptionsByTopic",
      "SNS:Publish",
    ]

    resources = [aws_sns_topic.audit_pipeline_alerts.arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceOwner"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AllowSpokeAccountsPublish"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [for id in var.spoke_account_ids : "arn:aws:iam::${id}:root"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.audit_pipeline_alerts.arn]
  }
}

resource "aws_sns_topic_policy" "audit_pipeline_alerts" {
  count = length(var.spoke_account_ids) > 0 ? 1 : 0

  arn    = aws_sns_topic.audit_pipeline_alerts.arn
  policy = data.aws_iam_policy_document.audit_pipeline_alerts.json
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_target == "email" ? 1 : 0
  topic_arn = aws_sns_topic.audit_pipeline_alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

module "alert_notifier" {
  count  = contains(["slack", "google_chat", "asana", "teams"], var.alert_target) ? 1 : 0
  source = "../alert_notifier"

  sns_topic_arn = aws_sns_topic.audit_pipeline_alerts.arn
  target        = var.alert_target
  secret_name   = var.alert_secret_name

  tags = var.tags
}

module "jira_notifier" {
  count  = var.alert_target == "jira" ? 1 : 0
  source = "../jira_notifier"

  sns_topic_arn = aws_sns_topic.audit_pipeline_alerts.arn
  secret_name   = var.alert_secret_name

  tags = var.tags
}
