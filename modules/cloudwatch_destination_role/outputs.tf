output "role_arn" {
  description = "ARN of the IAM role that CloudWatch Logs destinations assume to write into Firehose."
  value       = aws_iam_role.cloudwatch_to_firehose.arn
}
