variable "kms_key_arn" {
  description = "ARN of the KMS key used to encrypt Athena query results."
  type        = string
}

variable "query_results_bucket_name" {
  description = "Name of an existing S3 bucket to use for Athena query results (created by this module if not provided via a separate mechanism)."
  type        = string
  default     = null
}

variable "bytes_scanned_cutoff_per_query" {
  description = "Upper data usage limit (in bytes) for a single Athena query in this workgroup. Set to null to disable."
  type        = number
  default     = null
}

variable "tags" {
  description = "Tags applied to resources created by this module."
  type        = map(string)
  default     = {}
}
