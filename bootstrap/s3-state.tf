# Remote state bucket for the foundation/workload layers. Created here in the
# bootstrap (local state) because a backend bucket cannot store the state that
# manages itself. Locking is handled by S3 natively (use_lockfile, no DynamoDB).
resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name
}

# Versioning lets you recover a previous state if an apply goes wrong.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Customer-managed KMS key for the state bucket. State can contain sensitive
# values, so we encrypt at rest with a CMK (rotated) rather than the AWS-managed
# SSE-S3 key — this gives us key policy control and an audit trail on key use.
resource "aws_kms_key" "state" {
  description             = "${var.state_bucket_name} terraform state encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

resource "aws_kms_alias" "state" {
  name          = "alias/${var.state_bucket_name}-state"
  target_key_id = aws_kms_key.state.key_id
}

# Encrypt state at rest with the CMK. bucket_key_enabled lowers KMS request cost
# by using an S3 bucket key for the data-key operations.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = aws_kms_key.state.arn
    }
    bucket_key_enabled = true
  }
}

# State must never be public.
resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
