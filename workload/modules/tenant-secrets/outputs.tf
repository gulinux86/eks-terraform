output "role_names" {
  description = "Secrets role per tenant, by tenant name."
  value       = { for t, r in aws_iam_role.secrets : t => r.name }
}
