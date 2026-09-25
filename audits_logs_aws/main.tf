# Spoke-account EKS audit log forwarding.
#
#  [EKS Control Plane]
#           |
#           v
#  [CloudWatch Log Group] (/aws/eks/<cluster-name>/cluster)
#   - On the `k8s_cluster/aws` module - the log group itself is owned and
#     created there, this module only references it by name)
#           |
#           v
#  [Subscription Filter] --(Cross-Account Stream)--> Audit Account Destination
#
# This module intentionally does NOT create the CloudWatch Log Group: EKS
# automatically creates `/aws/eks/<cluster_name>/cluster` and the
# `k8s_cluster/aws` module already owns/manages that resource (including its
# retention). Managing it twice would cause a Terraform resource conflict.

locals {
  eks_control_plane_log_group_name = "/aws/eks/${var.cluster_name}/cluster"
}

data "aws_caller_identity" "current" {}

resource "aws_cloudwatch_log_subscription_filter" "eks_audit_logs" {
  name            = "${var.cluster_name}-eks-audit-logs-to-audit-account"
  log_group_name  = local.eks_control_plane_log_group_name
  filter_pattern  = var.filter_pattern
  destination_arn = var.destination_arn
  distribution    = var.distribution
}

resource "aws_cloudwatch_metric_alarm" "log_forwarding_inactivity" {
  count = var.alarm_enabled ? 1 : 0

  alarm_name          = "${var.cluster_name}-${data.aws_caller_identity.current.account_id}-eks-audit-log-forwarding-inactivity"
  alarm_description   = "Alerts when EKS control plane audit log forwarding to the Audit Account has stopped (ForwardedLogEvents dropped to 0)."
  namespace           = "AWS/Logs"
  metric_name         = "ForwardedLogEvents"
  statistic           = "Sum"
  period              = var.alarm_evaluation_period_seconds
  evaluation_periods  = 1
  comparison_operator = "LessThanOrEqualToThreshold"
  threshold           = 0
  treat_missing_data  = var.alarm_treat_missing_data

  dimensions = {
    LogGroupName = local.eks_control_plane_log_group_name
    FilterName   = aws_cloudwatch_log_subscription_filter.eks_audit_logs.name
  }

  alarm_actions = [var.central_alert_topic_arn]
  ok_actions    = [var.central_alert_topic_arn]

  tags = var.tags
}
