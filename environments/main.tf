locals {
  spoke_account_ids = [for cluster in var.spoke_clusters : cluster.spoke_account_id]

  tags = merge(var.tags, { ManagedBy = "terraform" })
}

module "kms" {
  source = "../modules/kms"

  tags = local.tags
}

# Account-wide S3 Block Public Access (Security Hub control S3.1). Every
# bucket in this account (per-cluster audit log buckets, Athena results
# bucket) already blocks public access at the bucket level; this is the
# safety net that keeps any future bucket private by default as well.
resource "aws_s3_account_public_access_block" "this" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

module "alerting" {
  source = "../modules/alerting"

  alert_target      = var.alert_target
  alert_email       = var.alert_email
  alert_secret_name = var.alert_secret_name
  spoke_account_ids = local.spoke_account_ids

  tags = local.tags
}

module "glue_catalog" {
  source = "../modules/glue_catalog"

  kms_key_arn = module.kms.key_arn

  tags = local.tags
}

module "cloudwatch_destination_role" {
  source = "../modules/cloudwatch_destination_role"

  spoke_account_ids = local.spoke_account_ids

  tags = local.tags
}

module "processor_lambda" {
  source = "../modules/processor_lambda"

  kms_key_arn   = module.kms.key_arn
  sns_topic_arn = module.alerting.sns_topic_arn

  tags = local.tags
}

module "audit_pipeline" {
  source   = "../modules/audit_pipeline"
  for_each = var.spoke_clusters

  cluster_name     = each.key
  spoke_account_id = each.value.spoke_account_id

  kms_key_arn = module.kms.key_arn
  kms_key_id  = module.kms.key_id

  cloudwatch_destination_role_arn = module.cloudwatch_destination_role.role_arn

  processor_lambda_function_name = module.processor_lambda.function_name
  processor_lambda_function_arn  = module.processor_lambda.function_arn

  glue_database_name = module.glue_catalog.database_name

  sns_topic_arn = module.alerting.sns_topic_arn

  buffering_size_mb          = each.value.buffering_size_mb
  buffering_interval_seconds = each.value.buffering_interval_seconds

  enable_object_lock           = each.value.enable_object_lock
  expiration_days              = each.value.expiration_days
  raw_retention_days           = each.value.raw_retention_days
  object_lock_retention_days   = each.value.object_lock_retention_days
  deep_archive_transition_days = each.value.deep_archive_transition_days

  delivery_failure_evaluation_period_seconds = each.value.delivery_failure_evaluation_period_seconds
  data_freshness_threshold_seconds           = each.value.data_freshness_threshold_seconds
  data_freshness_evaluation_period_seconds   = each.value.data_freshness_evaluation_period_seconds

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "processor_lambda_errors" {
  alarm_name          = "audit-logs-processor-lambda-errors"
  alarm_description   = "The S3-event-triggered audit-log processor Lambda (${module.processor_lambda.function_name}) is erroring out, likely a decompression or JSON parsing failure. Failed events land in its dead-letter queue; the raw objects remain replayable in the raw buckets."
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = module.processor_lambda.function_name
  }

  alarm_actions = [module.alerting.sns_topic_arn]
  ok_actions    = [module.alerting.sns_topic_arn]

  tags = local.tags
}
