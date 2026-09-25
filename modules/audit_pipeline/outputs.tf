output "bucket_name" {
  description = "Name of this cluster's dedicated audit log S3 bucket."
  value       = aws_s3_bucket.audit_logs.bucket
}

output "bucket_arn" {
  description = "ARN of this cluster's dedicated audit log S3 bucket."
  value       = aws_s3_bucket.audit_logs.arn
}

output "raw_bucket_name" {
  description = "Name of this cluster's ephemeral raw delivery S3 bucket (purged after raw_retention_days)."
  value       = aws_s3_bucket.raw.bucket
}

output "raw_bucket_arn" {
  description = "ARN of this cluster's ephemeral raw delivery S3 bucket."
  value       = aws_s3_bucket.raw.arn
}

output "log_destination_name" {
  description = "Name of the CloudWatch Logs destination the spoke account subscribes to."
  value       = aws_cloudwatch_log_destination.this.name
}

output "log_destination_arn" {
  description = "ARN of the CloudWatch Logs destination the spoke account subscribes to (this is the value the spoke account's audits_logs_aws module needs as destination_arn)."
  value       = aws_cloudwatch_log_destination.this.arn
}

output "firehose_delivery_stream_name" {
  description = "Name of this cluster's Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.audit_logs.name
}

output "firehose_delivery_stream_arn" {
  description = "ARN of this cluster's Firehose delivery stream."
  value       = aws_kinesis_firehose_delivery_stream.audit_logs.arn
}

output "glue_table_name" {
  description = "Name of this cluster's Glue Catalog table."
  value       = aws_glue_catalog_table.audit_logs.name
}
