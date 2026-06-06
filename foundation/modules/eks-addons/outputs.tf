output "addon_versions" {
  value       = { for k, a in aws_eks_addon.this : k => a.addon_version }
  description = "Resolved version of each managed core add-on"
}
