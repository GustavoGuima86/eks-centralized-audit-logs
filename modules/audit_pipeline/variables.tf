variable "cluster_name" {
  description = "Name of the spoke EKS cluster this pipeline ingests audit logs for. Combined with spoke_account_id into the audit-logs-{cluster}-{spoke_account_id} base name shared by the S3 bucket, CloudWatch Logs destination, Firehose delivery stream, Glue table and alarms."
  type        = string
}

variable "spoke_account_id" {
  description = "AWS Account ID of the spoke account that owns the EKS cluster and is allowed to attach a subscription filter to this pipeline's CloudWatch Logs destination."
  type        = string
}

variable "kms_key_arn" {
  description = "ARN of the shared KMS key used to encrypt the S3 bucket and Firehose delivery stream."
  type        = string
}

variable "kms_key_id" {
  description = "Key ID (not ARN) of the shared KMS key, used for the S3 bucket's default encryption configuration."
  type        = string
}

variable "cloudwatch_destination_role_arn" {
  description = "ARN of the shared IAM role that CloudWatch Logs assumes to write into this account's Firehose delivery streams."
  type        = string
}

variable "processor_lambda_function_name" {
  description = "Name of the shared S3-event-triggered processor Lambda function invoked when this pipeline's bucket receives raw deliveries."
  type        = string
}

variable "processor_lambda_function_arn" {
  description = "ARN of the shared S3-event-triggered processor Lambda function, referenced by this pipeline's bucket notification configuration."
  type        = string
}

variable "glue_database_name" {
  description = "Name of the shared Glue Catalog database this cluster's audit log table should be registered in."
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the central audit pipeline health SNS topic that Firehose delivery alarms should notify."
  type        = string
}

variable "buffering_size_mb" {
  description = "Firehose buffering hint, in MB, before flushing a batch to S3."
  type        = number
  default     = 64
}

variable "buffering_interval_seconds" {
  description = "Firehose buffering hint, in seconds, before flushing a batch to S3 (e.g. 900 = 15 minutes)."
  type        = number
  default     = 900
}

variable "enable_object_lock" {
  description = "Whether to protect this cluster's S3 bucket with S3 Object Lock in Compliance Mode (prod) instead of a plain lifecycle expiration rule (dev)."
  type        = bool
  default     = false
}

variable "object_lock_retention_days" {
  description = "Object Lock Compliance Mode default retention, in days, for prod buckets (enable_object_lock = true). Defaults to 3650 days (10 years)."
  type        = number
  default     = 3650
}

variable "deep_archive_transition_days" {
  description = "Number of days after object creation before transitioning to Glacier Deep Archive (only applied when enable_object_lock = true)."
  type        = number
  default     = 90
}

variable "expiration_days" {
  description = "Number of days after which objects are purged (only applied when enable_object_lock = false, i.e. dev buckets). Defaults to 180 days (6 months)."
  type        = number
  default     = 180
}

variable "raw_retention_days" {
  description = "Number of days raw Firehose deliveries are kept in the ephemeral raw bucket before being purged (reprocessing/replay window)."
  type        = number
  default     = 7
}

variable "delivery_failure_evaluation_period_seconds" {
  description = "Window, in seconds, over which the DeliveryToS3.Success alarm is evaluated."
  type        = number
  default     = 900
}

variable "data_freshness_threshold_seconds" {
  description = "Threshold, in seconds, above which the DeliveryToS3.DataFreshness alarm triggers (records sitting unwritten in the Firehose buffer)."
  type        = number
  default     = 3600
}

variable "data_freshness_evaluation_period_seconds" {
  description = "Window, in seconds, over which the DeliveryToS3.DataFreshness alarm is evaluated."
  type        = number
  default     = 900
}

variable "alarm_enabled" {
  description = "Whether to create the Firehose delivery failure and data freshness alarms for this pipeline."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to resources created by this module."
  type        = map(string)
  default     = {}
}
