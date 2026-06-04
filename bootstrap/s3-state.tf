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

# Encrypt state at rest (state can contain sensitive values).
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
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
