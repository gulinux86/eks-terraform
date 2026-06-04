output "bastion_instance_id" {
  value       = aws_instance.bastion.id
  description = "Bastion instance ID (use with: aws ssm start-session --target <id>)"
}

output "bastion_role_arn" {
  value       = aws_iam_role.bastion_role.arn
  description = "ARN of the bastion IAM role with access to the EKS cluster"
}
