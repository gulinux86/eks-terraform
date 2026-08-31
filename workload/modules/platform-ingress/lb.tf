# The platform's ingress load balancer, owned by Terraform.
#
# This is the whole point of the module. Until now the load balancer was created by
# a controller reacting to a Gateway in Git: it never entered Terraform state, so
# `terraform destroy` did not know it existed, and its ENIs held the private
# subnets while the subnets held the VPC. Four consecutive destroys failed that way
# on 2026-08-24.
#
# Declared here, the load balancer is a node in the dependency graph. Terraform
# holds the lb -> subnet edge and tears them down in order, by construction rather
# than by a drain script that has to out-guess two operators (design §1).
resource "aws_lb" "platform" {
  name               = "${var.project_name}-platform-ingress"
  load_balancer_type = "application"
  subnets            = var.private_subnet_ids
  security_groups    = [aws_security_group.lb.id]

  # The internet-facing guard.
  #
  # It used to be the *absence* of a `kubernetes.io/role/elb` tag on the public
  # subnets — a soft guard, since anyone who could tag a subnet or annotate a
  # Service could defeat it. Now exposure requires editing this line and merging a
  # pull request. Same intent, enforced by code review instead of by a tag
  # (ARCHITECTURE.md §3).
  internal = true

  # Terraform must be able to delete this. Left enabled, a destroy fails on the
  # load balancer itself — the exact class of failure this module exists to remove.
  enable_deletion_protection = false

  # Requests carrying malformed headers are dropped at the load balancer instead of
  # being normalised and passed on. Header handling differs between the ALB and
  # Envoy behind it, and a request the two parse differently is how request
  # smuggling starts.
  drop_invalid_header_fields = true

  # Drops from the AWS default of 300s. This is how long a destroy waits for
  # in-flight requests before the load balancer can go, and the environment is torn
  # down and rebuilt between sessions. Raise it when real traffic depends on
  # graceful connection draining.
  idle_timeout = 60

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-platform-ingress"
    }
  )
}

# Plain HTTP while the load balancer is internal and reachable only from inside the
# VPC. When the external path arrives (`enable-external-app-access`) this is where
# an ACM certificate and a redirect from 80 attach — one of the reasons decision §2
# chose an ALB over an NLB.
resource "aws_lb_listener" "platform" {
  load_balancer_arn = aws_lb.platform.arn
  port              = var.listener_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.gateway.arn
  }

  tags = var.tags
}
