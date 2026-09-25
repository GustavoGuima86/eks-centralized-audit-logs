variable "sns_topic_arn" {
  description = "ARN of the SNS topic carrying the CloudWatch alarm notifications for the audit pipeline."
  type        = string
}

variable "secret_name" {
  description = "Name of the Secrets Manager secret holding the Jira Cloud credentials (JSON: {\"jira_url\": \"https://<workspace>.atlassian.net\", \"email\": \"...\", \"api_token\": \"...\", \"project_key\": \"...\", \"issue_type\": \"Task\", \"close_transition\": \"Done\"}). Created as an empty container by this module; its value must be populated out-of-band."
  type        = string
}

variable "log_retention_in_days" {
  description = "Retention, in days, for the notifier Lambda's CloudWatch Logs log group."
  type        = number
  default     = 14
}

variable "memory_size" {
  description = "Memory size, in MB, for the notifier Lambda."
  type        = number
  default     = 128
}

variable "timeout" {
  description = "Timeout, in seconds, for the notifier Lambda."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to resources created by this module."
  type        = map(string)
  default     = {}
}
