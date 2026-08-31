output "target_group_arn" {
  value       = aws_lb_target_group.gateway.arn
  description = "Target group the cluster registers gateway pods into. Consumed by the TargetGroupBinding in this module, never published to Git — it names an AWS account."
}

output "security_group_id" {
  value       = aws_security_group.lb.id
  description = "The load balancer's security group. The TargetGroupBinding's networking rules allow ingress to the pods from this group."
}

output "dns_name" {
  value       = aws_lb.platform.dns_name
  description = "Internal DNS name of the platform ingress load balancer. Resolvable from inside the VPC only — reach it from the bastion."
}

output "lb_arn" {
  value       = aws_lb.platform.arn
  description = "Load balancer ARN, for operators inspecting target health"
}
