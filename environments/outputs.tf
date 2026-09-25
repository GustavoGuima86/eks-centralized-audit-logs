output "sns_topic_arn" {
  description = "ARN of the central audit pipeline health SNS topic."
  value       = module.alerting.sns_topic_arn
}

output "alert_target_secret_arn" {
  description = "ARN of the selected non-email alert destination secret, if applicable."
  value       = module.alerting.alert_target_secret_arn
}

output "glue_database_name" {
  description = "Name of the shared Glue Catalog database."
  value       = module.glue_catalog.database_name
}

output "athena_workgroup_name" {
  description = "Name of the Athena workgroup used to query audit logs."
  value       = module.glue_catalog.workgroup_name
}

output "cloudwatch_destination_role_arn" {
  description = "ARN of the shared IAM role CloudWatch Logs assumes to write into Firehose."
  value       = module.cloudwatch_destination_role.role_arn
}

output "log_destination_arns" {
  description = "Map of cluster_name => CloudWatch Logs destination ARN. Set the remote_module_audits_logs_aws module's `destination_arn` to the value corresponding to its cluster."
  value       = { for name, pipeline in module.audit_pipeline : name => pipeline.log_destination_arn }
}

output "bucket_names" {
  description = "Map of cluster_name => dedicated S3 bucket name."
  value       = { for name, pipeline in module.audit_pipeline : name => pipeline.bucket_name }
}

output "firehose_delivery_stream_names" {
  description = "Map of cluster_name => Firehose delivery stream name."
  value       = { for name, pipeline in module.audit_pipeline : name => pipeline.firehose_delivery_stream_name }
}
