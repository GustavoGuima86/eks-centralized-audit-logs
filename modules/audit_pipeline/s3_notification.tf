# Triggers the shared processor Lambda whenever Firehose lands a new raw
# delivery object in this cluster's raw bucket. The notification is scoped
# to raw/ objects only, so errors/ objects written by Firehose never
# re-trigger it, and the processed objects the Lambda writes to the
# compliance bucket are in a different bucket altogether.

resource "aws_lambda_permission" "processor_s3_invoke" {
  statement_id  = "AllowS3Invoke-${local.base_name}"
  action        = "lambda:InvokeFunction"
  function_name = var.processor_lambda_function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.raw.arn
}

resource "aws_s3_bucket_notification" "raw_delivery" {
  bucket = aws_s3_bucket.raw.id

  lambda_function {
    lambda_function_arn = var.processor_lambda_function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "raw/"
  }

  depends_on = [aws_lambda_permission.processor_s3_invoke]
}
