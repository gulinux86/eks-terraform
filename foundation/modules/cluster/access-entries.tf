# Grant cluster-admin to additional IAM principals (e.g. the CI/CD deploy role)
# via EKS Access Entries. AWS provider v6 no longer bootstraps the cluster
# creator as admin by default (bootstrap_cluster_creator_admin_permissions
# defaults to false), so the IAM role that runs Terraform must be granted access
# explicitly — otherwise the kubernetes/helm providers get "Unauthorized" when
# managing in-cluster resources (e.g. the controller's ServiceAccount).
resource "aws_eks_access_entry" "admin" {
  for_each      = toset(var.admin_role_arns)
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = each.value
  type          = "STANDARD"
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "admin" {
  for_each      = toset(var.admin_role_arns)
  cluster_name  = aws_eks_cluster.eks_cluster.name
  principal_arn = each.value
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }

  depends_on = [aws_eks_access_entry.admin]
}
