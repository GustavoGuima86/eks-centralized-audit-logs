output "database_name" {
  description = "Name of the Glue Catalog database holding the audit log table definitions."
  value       = aws_glue_catalog_database.audit_logs.name
}

output "workgroup_name" {
  description = "Name of the Athena workgroup used to query audit logs."
  value       = aws_athena_workgroup.audit_logs.name
}

output "athena_results_bucket_name" {
  description = "Name of the S3 bucket used to store Athena query results."
  value       = aws_s3_bucket.athena_results.bucket
}
