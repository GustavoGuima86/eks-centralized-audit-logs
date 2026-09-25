resource "aws_cloudwatch_log_destination" "this" {
  name       = local.base_name
  role_arn   = var.cloudwatch_destination_role_arn
  target_arn = aws_kinesis_firehose_delivery_stream.audit_logs.arn
}

data "aws_iam_policy_document" "destination_access" {
  statement {
    sid    = "AllowSpokeAccountSubscription"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [var.spoke_account_id]
    }

    actions   = ["logs:PutSubscriptionFilter"]
    resources = [aws_cloudwatch_log_destination.this.arn]
  }
}

resource "aws_cloudwatch_log_destination_policy" "this" {
  destination_name = aws_cloudwatch_log_destination.this.name
  access_policy    = data.aws_iam_policy_document.destination_access.json
}
