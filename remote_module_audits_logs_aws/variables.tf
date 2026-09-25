variable "cluster_name" {
  description = "Name of the EKS cluster whose control plane audit logs should be forwarded. The module derives the source log group name (`/aws/eks/<cluster_name>/cluster`) from this value, so it should typically be passed from the `k8s_cluster/aws` module, e.g. `module.cluster.cluster_name` or the same `var.cluster_name` used to create it."
  type        = string
}

variable "destination_arn" {
  description = "ARN of the cross-account CloudWatch Logs destination in the receiving account. This destination (and its resource policy granting this account access) is managed in the receiving Terraform deployment."
  type        = string
}

variable "filter_pattern" {
  description = "CloudWatch Logs subscription filter pattern used to select only Kubernetes API server audit events (`kube-apiserver-audit-*` log streams) before they are forwarded to the Audit Account. Defaults to a JSON pattern that matches the structure of Kubernetes audit events (`kind: \"Event\"`, `apiVersion` starting with `audit.k8s.io/`)."
  type        = string
  default     = "{ ($.kind = \"Event\") && ($.apiVersion = \"audit.k8s.io/*\") }"
}

variable "distribution" {
  description = "Method used to distribute log data to the destination. Only relevant when the destination is a Kinesis stream."
  type        = string
  default     = "ByLogStream"
}

variable "alarm_enabled" {
  description = "Whether to create the log-forwarding inactivity alarm."
  type        = bool
  default     = true
}

variable "alarm_evaluation_period_seconds" {
  description = "Window, in seconds, over which the `ForwardedLogEvents` metric is evaluated for the inactivity alarm."
  type        = number
  default     = 3600
}

variable "alarm_treat_missing_data" {
  description = "How the inactivity alarm should treat missing data points for the `ForwardedLogEvents` metric."
  type        = string
  default     = "breaching"
}

variable "central_alert_topic_arn" {
  description = "ARN of the receiving account SNS topic (audit-pipeline-alerts) this alarm notifies via CloudWatch's cross-account alarm actions. The topic policy must grant this spoke account sns:Publish. Required when alarm_enabled is true."
  type        = string
  default     = null

  validation {
    condition     = !var.alarm_enabled || var.central_alert_topic_arn != null
    error_message = "central_alert_topic_arn is required when alarm_enabled is true."
  }
}

variable "tags" {
  description = "Tags applied to resources created by this module."
  type        = map(string)
  default     = {}
}
