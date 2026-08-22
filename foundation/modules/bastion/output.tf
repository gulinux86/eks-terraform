output "bastion_instance_id" {
  value       = aws_instance.bastion.id
  description = "Bastion instance ID (use with: aws ssm start-session --target <id>)"
}

output "bastion_role_arn" {
  value       = aws_iam_role.bastion_role.arn
  description = "ARN of the bastion IAM role with access to the EKS cluster"
}

output "tooling_bucket" {
  value       = aws_s3_bucket.tooling.id
  description = "In-region bucket the bastion installs kubectl from. Seeded by the pipeline after a foundation apply."
}

output "kubectl_version" {
  value       = var.kubectl_version
  description = "kubectl version the bastion expects in the tooling bucket. Single-sourced so the pipeline seeds exactly what the boot script asks for."
}
