output "plan_role_arn" {
  value       = aws_iam_role.plan.arn
  description = "ARN of the read-only plan role. Set as the <ENV>_PLAN_ROLE_ARN GitHub secret."
}

output "deploy_role_arn" {
  value       = aws_iam_role.deploy.arn
  description = "ARN of the write-capable deploy role. Set as the <ENV>_DEPLOY_ROLE_ARN GitHub secret, and list it in cluster_admin_role_arns so workload applies are authorized inside the cluster."
}

output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.github_actions.arn
  description = "ARN of the GitHub Actions OIDC identity provider"
}

output "state_bucket" {
  value       = aws_s3_bucket.state.id
  description = "S3 bucket holding the foundation/workload remote state"
}
