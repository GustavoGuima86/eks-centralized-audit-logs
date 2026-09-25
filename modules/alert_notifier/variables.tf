variable "sns_topic_arn" {
  description = "SNS topic ARN carrying alarm notifications."
  type        = string
}

variable "target" {
  description = "Selected notification target: slack, google_chat, asana, or teams."
  type        = string
}

variable "secret_name" {
  description = "Secrets Manager secret name for target credentials. Populate it out-of-band after deployment."
  type        = string
}

variable "log_retention_in_days" {
  description = "CloudWatch Logs retention for the notification Lambda."
  type        = number
  default     = 14
}

variable "tags" {
  description = "Tags applied to resources created by this module."
  type        = map(string)
  default     = {}
}
