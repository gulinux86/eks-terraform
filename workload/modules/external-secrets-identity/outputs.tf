output "role_name" {
  description = "The External Secrets Operator controller's role."
  value       = aws_iam_role.controller.name
}
