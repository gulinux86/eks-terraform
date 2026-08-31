# Plan-mode unit tests for the platform ingress edge. Mocked providers, so the
# suite runs in CI with no credentials and creates nothing.
#
# What it guards is the reason this module exists. The load balancer is declared
# in Terraform rather than created by a controller, and three properties of that
# declaration are load-bearing:
#
#   - `internal = true` IS the internet-facing guard. It replaced a softer one —
#     the absence of a subnet tag — precisely so that exposing the platform takes
#     a reviewed edit. Without a test, flipping it passes fmt, validate and Trivy.
#   - the load balancer is placed only in subnets the caller declares private.
#   - the health check targets Istio's readiness port, not the traffic port.
#
# See ARCHITECTURE.md §3 and the module README.

mock_provider "aws" {}
mock_provider "helm" {}

variables {
  project_name         = "eks-test"
  vpc_id               = "vpc-0123456789abcdef0"
  vpc_cidr             = "10.0.0.0/16"
  private_subnet_ids   = ["subnet-0aaa", "subnet-0bbb"]
  gateway_namespace    = "istio-ingress"
  gateway_service_name = "platform-gateway-istio"
  tags = {
    Project     = "eks"
    Environment = "test"
  }
}

run "edge_is_internal_and_private" {
  command = plan

  # The whole internet-facing guard. Not a preference.
  assert {
    condition     = aws_lb.platform.internal == true
    error_message = "the platform load balancer must be internal; making it internet-facing is a deliberate change, not a default"
  }

  # Placed only where the caller said private. A public subnet here is the first
  # half of accidental exposure, even while `internal` still holds.
  assert {
    condition     = alltrue([for s in aws_lb.platform.subnets : contains(var.private_subnet_ids, s)])
    error_message = "the load balancer must sit only in the private subnets passed in"
  }

  # Terraform has to be able to delete it. Deletion protection would fail the
  # teardown on the load balancer itself — the failure class this module removes.
  assert {
    condition     = aws_lb.platform.enable_deletion_protection == false
    error_message = "deletion protection would break `terraform destroy`, which is what this module exists to make work"
  }

  # An ALB, not an NLB: ACM and WAF attach to a listener natively, which is what
  # the external path will need (ARCHITECTURE.md §3).
  assert {
    condition     = aws_lb.platform.load_balancer_type == "application"
    error_message = "expected an application load balancer"
  }
}

run "health_check_targets_istio_readiness" {
  command = plan

  # A gateway proxy accepts connections on the traffic port before its
  # configuration is programmed, so checking 80 reports healthy too early.
  assert {
    condition     = one(aws_lb_target_group.gateway.health_check).port == tostring(var.health_check_port)
    error_message = "health check must target Istio's readiness port (15021), not the traffic port"
  }
  assert {
    condition     = one(aws_lb_target_group.gateway.health_check).path == var.health_check_path
    error_message = "health check path must be Istio's readiness path"
  }

  # Pod IPs, not node ports: the VPC CNI gives every pod a routable VPC address,
  # so the load balancer reaches the gateway pod in one hop.
  assert {
    condition     = aws_lb_target_group.gateway.target_type == "ip"
    error_message = "target type must be ip so the load balancer registers pod addresses"
  }

  # The AWS default of 300s is dead time on every teardown.
  assert {
    condition     = aws_lb_target_group.gateway.deregistration_delay < "300"
    error_message = "deregistration delay should be shortened from the AWS default; it is waited out on every destroy"
  }
}

run "security_group_admits_only_the_vpc" {
  command = plan

  # This is not what keeps the platform off the internet — `internal` is — but a
  # wider CIDR here would let anything routable reach the gateway.
  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_vpc.cidr_ipv4 == var.vpc_cidr
    error_message = "ingress to the load balancer must be scoped to the VPC CIDR"
  }
  assert {
    condition     = aws_vpc_security_group_ingress_rule.from_vpc.from_port == var.listener_port
    error_message = "ingress must open the listener port only"
  }

  # The load balancer talks to pods on two ports and nothing else.
  assert {
    condition     = aws_vpc_security_group_egress_rule.to_targets_health.from_port == var.health_check_port
    error_message = "egress must reach the readiness port, or every target reports unhealthy for the wrong reason"
  }
}

run "listener_forwards_to_the_gateway_target_group" {
  command = plan

  assert {
    condition     = aws_lb_listener.platform.port == var.listener_port
    error_message = "listener port must match the configured ingress port"
  }
  assert {
    condition     = one(aws_lb_listener.platform.default_action).type == "forward"
    error_message = "listener must forward to the gateway target group"
  }
}
