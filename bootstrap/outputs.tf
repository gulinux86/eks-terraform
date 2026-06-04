output "role_arn" {
  value       = aws_iam_role.github_actions.arn
  description = "ARN of the CI role. Set this as the *_AWS_ROLE_ARN GitHub secret for this account/environment."
}

output "oidc_provider_arn" {
  value       = aws_iam_openid_connect_provider.github_actions.arn
  description = "ARN of the GitHub Actions OIDC identity provider"
}

output "state_bucket" {
  value       = aws_s3_bucket.state.id
  description = "S3 bucket holding the foundation/workload remote state"
}
