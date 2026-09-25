data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "aws:SourceArn"
      values = concat(
        [for account_id in var.spoke_account_ids : "arn:aws:logs:${data.aws_region.current.region}:${account_id}:*"],
        ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:*"],
      )
    }
  }
}

resource "aws_iam_role" "cloudwatch_to_firehose" {
  name               = "cwl-to-firehose-audit-logs"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = var.tags
}

data "aws_iam_policy_document" "firehose_put" {
  statement {
    effect = "Allow"
    actions = [
      "firehose:PutRecord",
      "firehose:PutRecordBatch",
      "firehose:DescribeDeliveryStream",
    ]
    resources = [
      "arn:aws:firehose:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:deliverystream/${var.firehose_delivery_stream_name_prefix}*",
    ]
  }
}

resource "aws_iam_role_policy" "firehose_put" {
  name   = "firehose-put"
  role   = aws_iam_role.cloudwatch_to_firehose.id
  policy = data.aws_iam_policy_document.firehose_put.json
}
