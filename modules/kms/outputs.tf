output "key_arn" {
  description = "ARN of the shared audit pipeline KMS key."
  value       = aws_kms_key.audit.arn
}

output "key_id" {
  description = "ID of the shared audit pipeline KMS key."
  value       = aws_kms_key.audit.key_id
}

output "alias_name" {
  description = "Alias name of the shared audit pipeline KMS key."
  value       = aws_kms_alias.audit.name
}
