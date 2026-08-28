# The load balancer's own security group.
#
# Terraform owns it, which is the difference that matters at teardown: a security
# group created by a controller in the cluster outlives that controller and holds
# the VPC, and Terraform cannot delete what it does not know about. Two of those
# blocked a destroy on 2026-08-24 (`DependencyViolation`, sg-0fee0f72… and
# sg-020019b8…). This one is a node in the graph like any other.
resource "aws_security_group" "lb" {
  name        = "${var.project_name}-platform-ingress"
  description = "Platform ingress load balancer"
  vpc_id      = var.vpc_id

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-platform-ingress"
    }
  )

  # Replaced before the old one is removed. The load balancer holds a reference to
  # it, so deleting first would fail.
  lifecycle {
    create_before_destroy = true
  }
}

# Ingress from inside the VPC only.
#
# This is not what keeps the platform off the internet — `internal = true` on the
# load balancer is. Widening this CIDR does not expose anything; it only decides
# who inside the VPC may reach the gateway.
resource "aws_vpc_security_group_ingress_rule" "from_vpc" {
  security_group_id = aws_security_group.lb.id
  description       = "Platform traffic from within the VPC"

  cidr_ipv4   = var.vpc_cidr
  ip_protocol = "tcp"
  from_port   = var.listener_port
  to_port     = var.listener_port
}

# Egress to the targets. Not "all traffic": the load balancer talks to gateway pod
# IPs on two ports and nothing else. The pod side of these rules is managed by the
# controller through the TargetGroupBinding, not written here.
resource "aws_vpc_security_group_egress_rule" "to_targets" {
  security_group_id = aws_security_group.lb.id
  description       = "Forwarded traffic to the gateway pods"

  cidr_ipv4   = var.vpc_cidr
  ip_protocol = "tcp"
  from_port   = var.listener_port
  to_port     = var.listener_port
}

resource "aws_vpc_security_group_egress_rule" "to_targets_health" {
  security_group_id = aws_security_group.lb.id
  description       = "Health checks to the gateway pods"

  cidr_ipv4   = var.vpc_cidr
  ip_protocol = "tcp"
  from_port   = var.health_check_port
  to_port     = var.health_check_port
}
