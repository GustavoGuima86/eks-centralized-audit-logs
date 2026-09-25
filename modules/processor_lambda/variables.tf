variable "kms_key_arn" {
  description = "ARN of the shared KMS key encrypting the audit log buckets; grants the processor decrypt/data-key permissions."
  type        = string
}

variable "sns_topic_arn" {
  description = "ARN of the central audit pipeline health SNS topic that the processor dead-letter queue alarm notifies."
  type        = string
}

variable "log_retention_in_days" {
  description = "Retention, in days, for the processor Lambda's CloudWatch Logs log group."
  type        = number
  default     = 14
}

variable "memory_size" {
  description = "Memory size, in MB, for the processor Lambda (Lambda CPU scales with memory; raw objects can be tens of MB compressed / hundreds of MB decompressed)."
  type        = number
  default     = 2048
}

variable "timeout" {
  description = "Timeout, in seconds, for the processor Lambda."
  type        = number
  default     = 900
}

variable "tags" {
  description = "Tags applied to resources created by this module."
  type        = map(string)
  default     = {}
}
