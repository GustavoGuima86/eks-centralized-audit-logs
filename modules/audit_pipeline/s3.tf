locals {
  base_name       = "audit-logs-${var.cluster_name}-${var.spoke_account_id}"
  raw_bucket_name = "audit-logs-raw-${var.cluster_name}-${var.spoke_account_id}"
}

resource "aws_s3_bucket" "audit_logs" {
  bucket = local.base_name

  object_lock_enabled = var.enable_object_lock

  tags = merge(var.tags, {
    Cluster = var.cluster_name
  })
}

resource "aws_s3_bucket_versioning" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

# Prod: Object Lock Compliance Mode, default retention of `object_lock_retention_days`.
resource "aws_s3_bucket_object_lock_configuration" "audit_logs" {
  count = var.enable_object_lock ? 1 : 0

  bucket = aws_s3_bucket.audit_logs.id

  rule {
    default_retention {
      mode = "COMPLIANCE"
      days = var.object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.audit_logs]
}

resource "aws_s3_bucket_lifecycle_configuration" "audit_logs" {
  bucket = aws_s3_bucket.audit_logs.id

  dynamic "rule" {
    for_each = var.enable_object_lock ? [1] : []
    content {
      id     = "transition-to-deep-archive"
      status = "Enabled"

      filter {}

      transition {
        days          = var.deep_archive_transition_days
        storage_class = "DEEP_ARCHIVE"
      }

      noncurrent_version_transition {
        noncurrent_days = var.deep_archive_transition_days
        storage_class   = "DEEP_ARCHIVE"
      }
    }
  }

  dynamic "rule" {
    for_each = var.enable_object_lock ? [] : [1]
    content {
      id     = "expire-audit-logs"
      status = "Enabled"

      filter {}

      expiration {
        days = var.expiration_days
      }

      noncurrent_version_expiration {
        noncurrent_days = var.expiration_days
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.audit_logs]
}

# Ephemeral raw bucket: Firehose lands the verbatim CloudWatch Logs
# deliveries here and the processor Lambda turns them into the queryable
# objects in the compliance bucket above. Kept SEPARATE from the compliance
# bucket on purpose: prod compliance buckets carry S3 Object Lock, which
# would retain the raw deliveries for the full retention period, while the
# raw data only needs to stick around as a short reprocessing/replay
# security net (default 7 days). No Object Lock, no versioning.
resource "aws_s3_bucket" "raw" {
  bucket = local.raw_bucket_name

  tags = merge(var.tags, {
    Cluster = var.cluster_name
  })
}

resource "aws_s3_bucket_public_access_block" "raw" {
  bucket = aws_s3_bucket.raw.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "raw" {
  bucket = aws_s3_bucket.raw.id

  rule {
    id     = "expire-raw-deliveries"
    status = "Enabled"

    filter {}

    expiration {
      days = var.raw_retention_days
    }
  }
}
