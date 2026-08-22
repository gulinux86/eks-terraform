# In-region bucket holding the tooling the bastion installs at boot.
#
# Why this exists rather than pulling straight from AWS's public `amazon-eks`
# bucket: that bucket lives in **us-west-2**. An S3 *gateway* endpoint only routes
# to S3 in its own region, and the bastion's security group only allows egress to
# the in-region S3 prefix list — so a request for a us-west-2 object matched no
# egress rule and was dropped silently. Not AccessDenied, not a timeout with a
# cause: a hang. The design promised "no internet egress" and a cross-region
# bucket, which cannot both be true.
#
# Copying the binary into a bucket in the VPC's own region makes the gateway
# endpoint the correct path again, and keeps the bastion with zero internet.
resource "aws_s3_bucket" "tooling" {
  bucket = "${var.project_name}-tooling-${data.aws_caller_identity.current.account_id}"

  # S3 refuses to delete a non-empty bucket, so without this a `terraform destroy`
  # fails with BucketNotEmpty and leaves the environment half torn down. Safe here
  # and only here: the contents are a binary the pipeline re-downloads and re-seeds
  # on every deploy. Never set this on the state bucket.
  force_destroy = true

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-tooling"
    }
  )
}

# SSE-S3 rather than a CMK, deliberately. The only contents are binaries AWS
# publishes publicly, so a customer-managed key would buy no confidentiality — it
# would only add a key to rotate and a kms:Decrypt grant on the bastion role.
#
# The exception is scoped to this resource rather than added to .trivyignore: that
# file suppresses a rule repository-wide, which would also silence it for the state
# bucket, where a CMK genuinely matters. If this bucket ever holds anything that is
# not public, delete this line and give it a key.
#trivy:ignore:AVD-AWS-0132
resource "aws_s3_bucket_server_side_encryption_configuration" "tooling" {
  bucket = aws_s3_bucket.tooling.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tooling" {
  bucket                  = aws_s3_bucket.tooling.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# The binary itself is seeded by the pipeline, not by Terraform: `aws_s3_object`
# would need the ~50 MB file present on disk at plan time, which breaks every local
# plan and makes the file a build input. The pipeline downloads it once (it has
# internet) and copies it here. See the bastion README for the one-liner to do the
# same by hand.
