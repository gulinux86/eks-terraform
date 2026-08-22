output "controller_role_arn" {
  value       = aws_iam_role.controller.arn
  description = "Karpenter controller role. Bound to the ServiceAccount by Pod Identity, so the Helm values in Git never need it."
}

output "node_role_name" {
  value       = aws_iam_role.node.name
  description = "Role Karpenter-provisioned nodes assume. The EC2NodeClass in the GitOps repo references it by NAME, not ARN."
}

output "interruption_queue_name" {
  value       = aws_sqs_queue.interruption.name
  description = "Queue the controller polls for interruption events; goes into the Helm values as settings.interruptionQueue."
}

output "discovery_tag_value" {
  value       = var.cluster_name
  description = "Value of the karpenter.sh/discovery tag on subnets and security groups. The EC2NodeClass selectors must match it."
}
