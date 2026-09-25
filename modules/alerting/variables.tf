variable "alert_target" {
  description = "Single destination selected for SNS alarm notifications."
  type        = string
}

variable "alert_email" {
  description = "Email destination used when alert_target is email."
  type        = string
  default     = null
}

variable "alert_secret_name" {
  description = "Secrets Manager secret name used by the selected API/webhook destination."
  type        = string
}

variable "spoke_account_ids" {
  description = "Spoke AWS account IDs allowed to publish to the central audit pipeline alerts SNS topic (cross-account alarm notifications for audit-log forwarding inactivity alarms)."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to resources created by this module."
  type        = map(string)
  default     = {}
}
