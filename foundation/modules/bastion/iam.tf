resource "aws_iam_role" "bastion_role" {
  name = "${var.project_name}-bastion-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-bastion-role"
    }
  )
}

# Enables access via SSM Session Manager (no open SSH port).
resource "aws_iam_role_policy_attachment" "bastion_ssm" {
  role       = aws_iam_role.bastion_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# `aws eks update-kubeconfig` calls eks:DescribeCluster on the AWS management
# API. This is separate from the Access Entry (which governs in-cluster RBAC):
# without this permission update-kubeconfig fails with AccessDenied.
resource "aws_iam_role_policy" "bastion_eks_describe" {
  name = "${var.project_name}-bastion-eks-describe"
  role = aws_iam_role.bastion_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${var.cluster_name}"
      }
    ]
  })
}

# Read access to the public Amazon-EKS bucket, which is where the boot script gets
# kubectl from (via the S3 gateway endpoint — the bastion has no internet egress).
#
# This was missing: the role carried only SSM and eks:DescribeCluster, so the boot
# script's `aws s3 ls` returned AccessDenied, the guard around it swallowed the
# failure, and kubectl was silently never installed. The documented behaviour in
# ARCHITECTURE.md §6 had therefore never actually worked.
#
# Scoped to that one bucket. `amazon-eks` is public and read-only to everyone, so
# this grants no meaningful reach — but scoping it keeps the role's intent legible.
resource "aws_iam_role_policy" "bastion_kubectl_download" {
  name = "${var.project_name}-bastion-kubectl-download"
  role = aws_iam_role.bastion_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListToolingBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = aws_s3_bucket.tooling.arn
      },
      {
        Sid      = "DownloadTooling"
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.tooling.arn}/*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "bastion_profile" {
  name = "${var.project_name}-bastion-profile"
  role = aws_iam_role.bastion_role.name

  tags = var.tags
}
