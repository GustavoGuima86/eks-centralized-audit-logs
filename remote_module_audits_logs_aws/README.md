# Remote EKS audit log forwarding module

Spoke-side Terraform module that forwards one EKS cluster's Kubernetes
control-plane audit events to a receiving AWS account and raises an alarm if
forwarding stops. It does not create the EKS-owned CloudWatch log group,
central storage, or central alert destination.

## Resources

| Resource | Purpose |
| --- | --- |
| CloudWatch Logs subscription filter | Selects Kubernetes audit events and sends them to the configured destination |
| CloudWatch metric alarm | Detects a period without forwarded events and publishes to the configured SNS topic |

Enable the EKS `audit` control-plane log type and set a short retention on
the source log group if desired. The receiving account must first create the
CloudWatch Logs destination and allow this account to subscribe, and its SNS
topic policy must permit this account to publish.

## Usage

```hcl
module "audit_log_forwarding" {
  source = "git::https://github.com/GustavoGuima86/eks-centralized-audit-logs.git//remote_module_audits_logs_aws?ref=main"

  cluster_name            = var.cluster_name
  destination_arn         = var.audit_log_destination_arn
  central_alert_topic_arn = var.audit_alert_topic_arn
}
```

Obtain the two ARNs from the receiving deployment's `log_destination_arns`
and `sns_topic_arn` outputs. Apply the receiving deployment first.

## Inputs

| Variable | Required | Purpose |
| --- | --- | --- |
| `cluster_name` | Yes | EKS cluster name; derives `/aws/eks/<cluster_name>/cluster` |
| `destination_arn` | Yes | CloudWatch Logs destination ARN |
| `central_alert_topic_arn` | When alarm enabled | SNS topic ARN for inactivity alarm notifications |
| `filter_pattern` | No | Audit-event filter; defaults to Kubernetes audit event fields |
| `alarm_enabled` | No | Create forwarding inactivity alarm (default `true`) |
| `alarm_evaluation_period_seconds` | No | Inactivity window (default `3600`) |
| `alarm_treat_missing_data` | No | Alarm missing-data behavior (default `breaching`) |
| `tags` | No | Resource tags |

## Outputs

`eks_control_plane_log_group_name`, `subscription_filter_name`, and `alarm_arn`.
