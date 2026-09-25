resource "aws_cloudwatch_metric_alarm" "firehose_delivery_failure" {
  count = var.alarm_enabled ? 1 : 0

  alarm_name          = "${local.base_name}-firehose-delivery-failure"
  alarm_description   = "Firehose is failing to deliver ${var.cluster_name} audit logs to S3 (DeliveryToS3.Success < 1). Check IAM permissions and Object Lock policy on the destination bucket."
  namespace           = "AWS/Firehose"
  metric_name         = "DeliveryToS3.Success"
  statistic           = "Average"
  period              = var.delivery_failure_evaluation_period_seconds
  evaluation_periods  = 1
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching"

  dimensions = {
    DeliveryStreamName = aws_kinesis_firehose_delivery_stream.audit_logs.name
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = var.tags
}

resource "aws_cloudwatch_metric_alarm" "firehose_data_freshness" {
  count = var.alarm_enabled ? 1 : 0

  alarm_name          = "${local.base_name}-firehose-data-freshness"
  alarm_description   = "Records for ${var.cluster_name} have been sitting unwritten in the Firehose buffer for over ${var.data_freshness_threshold_seconds}s (DeliveryToS3.DataFreshness)."
  namespace           = "AWS/Firehose"
  metric_name         = "DeliveryToS3.DataFreshness"
  statistic           = "Maximum"
  period              = var.data_freshness_evaluation_period_seconds
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.data_freshness_threshold_seconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    DeliveryStreamName = aws_kinesis_firehose_delivery_stream.audit_logs.name
  }

  alarm_actions = [var.sns_topic_arn]
  ok_actions    = [var.sns_topic_arn]

  tags = var.tags
}
