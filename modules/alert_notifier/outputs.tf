output "secret_arn" {
  description = "ARN of the Secrets Manager secret to populate with the selected target credentials."
  value       = aws_secretsmanager_secret.target.arn
}

output "secret_name" {
  description = "Name of the Secrets Manager secret to populate with the selected target credentials."
  value       = aws_secretsmanager_secret.target.name
}

output "function_name" {
  description = "Name of the selected-target notification Lambda function."
  value       = aws_lambda_function.notifier.function_name
}
