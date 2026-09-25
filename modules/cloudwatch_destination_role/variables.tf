variable "spoke_account_ids" {
  description = "List of spoke AWS account IDs allowed to send log events to CloudWatch Logs destinations in this account (used in the role's trust policy confused-deputy condition, alongside this account's own ID)."
  type        = list(string)
}

variable "firehose_delivery_stream_name_prefix" {
  description = "Name prefix shared by all audit-log Firehose delivery streams in this account/environment. Used to scope the role's firehose:PutRecord* permissions."
  type        = string
  default     = "audit-logs-"
}

variable "tags" {
  description = "Tags applied to resources created by this module."
  type        = map(string)
  default     = {}
}
