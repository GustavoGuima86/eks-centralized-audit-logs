output "sns_topic_arn" {
  description = "ARN of the audit pipeline health SNS topic."
  value       = aws_sns_topic.audit_pipeline_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the audit pipeline health SNS topic."
  value       = aws_sns_topic.audit_pipeline_alerts.name
}

output "alert_target_secret_arn" {
  description = "ARN of the selected non-email notification target secret, if one is created."
  value       = try(module.alert_notifier[0].secret_arn, try(module.jira_notifier[0].secret_arn, null))
}
