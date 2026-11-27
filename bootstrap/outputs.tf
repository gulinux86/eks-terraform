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

output "ecr_push_role_arn" {
  value       = aws_iam_role.ecr_push.arn
  description = "ARN of the ECR push role. Set as the ECR_PUSH_ROLE_ARN secret in each application repository that uses ci-templates' service-release workflow."
}

output "ecr_read_role_arn" {
  value       = aws_iam_role.ecr_read.arn
  description = "ARN of the ECR read role. Set as the ECR_READ_ROLE_ARN secret in app-gitops."
}

output "ecr_registry" {
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.region}.amazonaws.com"
  description = "The account's ECR registry. Images are <registry>/apps/<app>[/<service>]."
}
