# EKS writes control-plane logs to /aws/eks/<cluster>/cluster. If the group does not
# exist, EKS creates it with NO expiry — and Terraform cannot set retention on a group
# it does not own. Creating it first, with the exact name, means EKS adopts this one.
#
# The cluster does not reference this resource, so Terraform has no ordering to infer:
# the dependency below is explicit on purpose.
resource "aws_cloudwatch_log_group" "cluster" {
  name              = "/aws/eks/${var.project_name}-cluster/cluster"
  retention_in_days = var.log_retention_days

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-cluster-logs"
    }
  )
}

resource "aws_eks_cluster" "eks_cluster" {
  name     = "${var.project_name}-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn
  version  = var.kubernetes_version

  enabled_cluster_log_types = var.cluster_log_types

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  encryption_config {
    resources = ["secrets"]
    provider {
      key_arn = aws_kms_key.eks_secrets.arn
    }
  }

  vpc_config {
    subnet_ids = [
      var.private_subnet_1a,
      var.private_subnet_1b
    ]
    endpoint_private_access = true
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
  }

  # Ensure that IAM Role permissions are created before and deleted after EKS Cluster handling.
  # Otherwise, EKS will not be able to properly delete EKS managed EC2 infrastructure such as Security Groups.
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_role_attachment,
    aws_iam_role_policy.eks_kms,
    # Must exist before the cluster enables logging, or EKS creates its own
    # never-expiring group and this one is left unused.
    aws_cloudwatch_log_group.cluster
  ]

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-cluster"
    }
  )
}

