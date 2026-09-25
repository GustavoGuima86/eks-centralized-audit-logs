output "eks_control_plane_log_group_name" {
  description = "Name of the EKS control plane CloudWatch Log Group this module streams from."
  value       = local.eks_control_plane_log_group_name
}

output "subscription_filter_name" {
  description = "Name of the CloudWatch Logs subscription filter forwarding audit logs to the Audit Account."
  value       = aws_cloudwatch_log_subscription_filter.eks_audit_logs.name
}

output "alarm_arn" {
  description = "ARN of the log-forwarding inactivity CloudWatch alarm, if enabled."
  value       = try(aws_cloudwatch_metric_alarm.log_forwarding_inactivity[0].arn, null)
}
