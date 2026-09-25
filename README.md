# Reusable EKS audit log pipeline

Terraform modules to collect EKS control-plane audit logs in an AWS account,
store and query them, and route health alarms to one selected notification
destination. The configuration has no account-specific state backend,
account allow-list, client names, or pre-filled cluster/account identifiers.

## Architecture

```text
Spoke EKS accounts                         Audit account
EKS audit log group -> subscription filter -> CloudWatch Logs destination
                                             -> Firehose -> temporary S3 bucket
                                             -> processor Lambda -> audit S3 bucket
                                             -> Glue catalog + Athena

CloudWatch alarms -> SNS topic -> selected alert_target
```

The pipeline keeps raw delivery records temporarily for replay, stores
processed Kubernetes audit events as partitioned NDJSON, and uses per-cluster
retention settings. Production retention can use S3 Object Lock Compliance
Mode; non-production retention can use lifecycle expiration.

## Layout

```text
environments/                 Reusable deployment root; local state by default
remote_module_audits_logs_aws/ Spoke-side module published for remote Git use
modules/
  alerting/                    SNS topic, target selection, cross-account policy
  alert_notifier/              Shared webhook/API notifier for Slack, Chat, Teams, Asana
  audit_pipeline/              Per-cluster destination, Firehose, S3, Glue, alarms
  cloudwatch_destination_role/ CloudWatch Logs delivery role
  glue_catalog/                Glue database and Athena workgroup
  jira_notifier/               Optional Jira incident ticket integration
  kms/                         Encryption key
  processor_lambda/            Raw delivery to queryable audit records
```

There is no remote backend configured. Terraform uses local state unless you
provide backend configuration at initialization (for example with
`terraform init -backend-config=...`). AWS credentials are resolved through
the standard AWS provider chain. The region defaults to `us-east-1` and can be
changed via `aws_region`.

Local state files can contain sensitive infrastructure metadata. Keep them
private and switch to an organization-managed remote backend when collaborating.

## Quick start

1. Configure AWS credentials for the account that will receive the logs.
2. Edit `environments/terraform.tfvars`: set `aws_region`, add cluster entries
   to `spoke_clusters`, and choose an `alert_target`.
3. From `environments/`, run:

   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

4. Configure the spoke-side module with the `log_destination_arns` and
   `sns_topic_arn` outputs from this deployment.
5. For a webhook/API target, populate the output Secrets Manager secret with
   its credentials after apply. For email, confirm the SNS subscription sent
   to the configured recipient.

The default `terraform.tfvars` is intentionally empty of account and cluster
details and uses `alert_target = "none"`.

## Alert destination selector

Set exactly one `alert_target` value in `environments/terraform.tfvars`:

| Value | Delivery | Configuration |
| --- | --- | --- |
| `none` | No SNS subscription/notifier | Default |
| `email` | SNS email subscription | Set `alert_email`; confirm its subscription |
| `slack` | Slack incoming webhook | Secret JSON: `{"webhook_url":"https://..."}` |
| `google_chat` | Google Chat incoming webhook | Secret JSON: `{"webhook_url":"https://..."}` |
| `teams` | Teams incoming webhook | Secret JSON: `{"webhook_url":"https://..."}` |
| `asana` | Creates an Asana task for each notification | Secret JSON: `{"access_token":"...","project_gid":"..."}` |
| `jira` | Opens a ticket on ALARM and closes it on OK | Jira credential JSON described below |

For example:

```hcl
alert_target = "google_chat"
# Optional override; defaults to audit-pipeline-alert-target.
alert_secret_name = "audit-alert-destination"
```

Webhook/API secrets are created empty by Terraform and must be populated
out-of-band in AWS Secrets Manager. Do not put tokens or webhook URLs in
Terraform files or source control. Only the selected target is provisioned.
Email is native SNS delivery. Jira retains its incident deduplication and
recovery handling; the generic webhook/API notifier forwards each SNS
notification as received.

## Cluster configuration

`spoke_clusters` is a map keyed by a unique cluster label. Each entry requires
the spoke account ID and accepts optional retention/buffering overrides:

```hcl
spoke_clusters = {
  example_cluster = {
    spoke_account_id   = "123456789012"
    enable_object_lock = false
    expiration_days    = 180
  }
}
```

The label is used in resource names and Glue tables. Keep it lowercase and
use only characters allowed in S3 bucket names. For immutable production
retention, set `enable_object_lock = true` and configure the retention period.

## Spoke account setup

Each spoke calls the `remote_module_audits_logs_aws` module from the Git
repository in the same Terraform configuration as its EKS cluster. The
cluster must have control-plane audit logging enabled. This module creates a
subscription filter and forwarding-inactivity alarm; the EKS module remains
responsible for its CloudWatch log group.

```hcl
module "audit_log_forwarding" {
  source = "git::https://github.com/GustavoGuima86/eks-centralized-audit-logs.git//remote_module_audits_logs_aws?ref=main"

  cluster_name            = var.cluster_name
  destination_arn         = var.audit_log_destination_arn
  central_alert_topic_arn = var.audit_alert_topic_arn
}
```

Supply `destination_arn` from `log_destination_arns["<cluster-label>"]` and
`central_alert_topic_arn` from `sns_topic_arn`. Apply the receiving account
first so its destination policy allows the spoke account to subscribe and its
SNS topic policy allows the spoke alarm to publish. The Git repository must
be accessible to the spoke account's Terraform runner. Pin `ref` to a release
tag or commit SHA for reproducible deployments instead of tracking `main`.

## Querying

Use the output `athena_workgroup_name`, the Glue database output, and the
cluster table name `audit_logs_<cluster>_<account-id>`. Filter by the
projected `year`, `month`, `day`, and `hour` partitions to limit scanned data.
For example:

```sql
SELECT verb, requesturi, count(*) AS events
FROM "<database>"."audit_logs_<cluster>_<account-id>"
WHERE year = '2026' AND month = '09' AND day = '25'
GROUP BY verb, requesturi
ORDER BY events DESC
LIMIT 25;
```

## Validation and operations

From `environments/`:

```bash
terraform fmt -recursive
terraform validate
terraform plan
```

The Firehose raw bucket is lifecycle-cleaned after `raw_retention_days`; the
processor's SQS dead-letter queue and CloudWatch alarms support troubleshooting.
Subscription filters forward new events only; historical log backfill is a
separate CloudWatch Logs export operation.
