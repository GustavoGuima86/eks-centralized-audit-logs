output "function_name" {
  description = "Name of the S3-event-triggered processor Lambda function."
  value       = aws_lambda_function.processor.function_name
}

output "function_arn" {
  description = "ARN of the S3-event-triggered processor Lambda function (unqualified)."
  value       = aws_lambda_function.processor.arn
}

output "dlq_arn" {
  description = "ARN of the SQS dead-letter queue receiving failed processor invocations."
  value       = aws_sqs_queue.processor_dlq.arn
}

output "dlq_url" {
  description = "URL of the SQS dead-letter queue receiving failed processor invocations."
  value       = aws_sqs_queue.processor_dlq.url
}
