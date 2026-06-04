# KMS key for envelope encryption of EKS secrets (etcd).
resource "aws_kms_key" "eks_secrets" {
  description             = "${var.project_name} EKS secrets envelope encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-eks-secrets"
    }
  )
}

resource "aws_kms_alias" "eks_secrets" {
  name          = "alias/${var.project_name}-eks-secrets"
  target_key_id = aws_kms_key.eks_secrets.key_id
}

# Allows the cluster IAM role to use the key to encrypt/decrypt secrets.
resource "aws_iam_role_policy" "eks_kms" {
  name = "${var.project_name}-eks-kms"
  role = aws_iam_role.eks_cluster_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:CreateGrant",
          "kms:ListGrants",
          "kms:RevokeGrant"
        ]
        Resource = aws_kms_key.eks_secrets.arn
      }
    ]
  })
}
