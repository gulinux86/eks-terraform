output "cluster_name" {
  value = aws_eks_cluster.eks_cluster.id
}

output "oidc" {
  value = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer
}

output "certificate_authority" {
  value     = aws_eks_cluster.eks_cluster.certificate_authority[0].data
  sensitive = true
}

output "endpoint" {
  value     = aws_eks_cluster.eks_cluster.endpoint
  sensitive = true
}
output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.eks_oidc.arn
  description = "ARN of the cluster's IAM OIDC provider. Distinct from `oidc`, which is the issuer URL: IRSA trust policies need the ARN as the federated principal, and the URL (minus scheme) as the condition key."
}
