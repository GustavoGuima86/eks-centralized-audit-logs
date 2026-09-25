variable "spoke_clusters" {
  description = <<EOT
    Map of every spoke EKS cluster that streams audit logs into this account.
    Key is a cluster name, value is an
    object with the owning spoke AWS account ID, whether that cluster's
    bucket should be protected with S3 Object Lock Compliance Mode (true for
    production-tier clusters, false for dev/stage-tier clusters which use a
    plain expiration lifecycle rule instead), and optional per-cluster
    overrides for buffering/retention.
  EOT
  type = map(object({
    spoke_account_id                           = string
    enable_object_lock                         = optional(bool, true)
    buffering_size_mb                          = optional(number, 64)
    buffering_interval_seconds                 = optional(number, 900)
    expiration_days                            = optional(number, 180)
    raw_retention_days                         = optional(number, 7)
    object_lock_retention_days                 = optional(number, 3650)
    deep_archive_transition_days               = optional(number, 90)
    delivery_failure_evaluation_period_seconds = optional(number, 900)
    data_freshness_threshold_seconds           = optional(number, 3600)
    data_freshness_evaluation_period_seconds   = optional(number, 900)
  }))
  default = {}
}

variable "alert_target" {
  description = "Single alert destination for pipeline alarms. Use none to disable delivery."
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "email", "slack", "google_chat", "asana", "teams", "jira"], var.alert_target)
    error_message = "alert_target must be one of: none, email, slack, google_chat, asana, teams, jira."
  }
}

variable "alert_email" {
  description = "Email address subscribed to alarm notifications when alert_target is email. Confirm the SNS subscription after deployment."
  type        = string
  default     = null

  validation {
    condition     = var.alert_target != "email" || (var.alert_email != null && can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.alert_email)))
    error_message = "Set alert_email to a valid address when alert_target is email."
  }
}

variable "alert_secret_name" {
  description = "Secrets Manager secret name for the selected Slack, Google Chat, Teams, Asana, or Jira target. Populate the secret out-of-band."
  type        = string
  default     = "audit-pipeline-alert-target"
}

variable "aws_region" {
  description = "AWS region in which to deploy the audit pipeline."
  type        = string
  default     = "us-east-1"
}

variable "allowed_account_ids" {
  description = "Optional AWS account ID allow-list for the Terraform provider. Leave empty for a portable configuration."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to all resources created by this environment."
  type        = map(string)
  default     = {}
}
