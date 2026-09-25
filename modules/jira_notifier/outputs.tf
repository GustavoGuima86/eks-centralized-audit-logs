output "function_name" {
  description = "Name of the Jira notifier Lambda function."
  value       = aws_lambda_function.notifier.function_name
}

output "function_arn" {
  description = "ARN of the Jira notifier Lambda function."
  value       = aws_lambda_function.notifier.arn
}

output "secret_arn" {
  description = "ARN of the Secrets Manager secret to populate with Jira credentials."
  value       = aws_secretsmanager_secret.jira.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret to populate with Jira credentials."
  value       = aws_secretsmanager_secret.jira.name
}

output "tickets_table_name" {
  description = "Name of the DynamoDB table mapping alarms to their open Jira ticket (one ticket per alarm incident)."
  value       = aws_dynamodb_table.tickets.name
}
