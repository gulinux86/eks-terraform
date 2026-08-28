# The target group the cluster registers into.
#
# Terraform creates it and never populates it. Registration is the cluster's job,
# through a TargetGroupBinding (binding.tf) — and that split is what makes the
# teardown safe: the binding can vanish with the cluster, mid-flight, leaving stale
# target IPs behind, and nothing is stranded. Stale targets are entries in a table,
# not ENIs; the table is destroyed by Terraform along with everything else.
resource "aws_lb_target_group" "gateway" {
  name     = "${var.project_name}-platform-gateway"
  vpc_id   = var.vpc_id
  port     = var.listener_port
  protocol = "HTTP"

  # Pod IPs, not node ports. The VPC CNI gives every pod a routable address in the
  # VPC, so the load balancer reaches the gateway pod directly — one hop instead of
  # landing on an arbitrary node and being forwarded again.
  target_type = "ip"

  # Istio's gateway readiness endpoint, deliberately not the traffic port.
  #
  # A gateway proxy accepts connections on 80 before its configuration is
  # programmed, so health-checking the traffic port reports healthy too early. 15021
  # answers only once the proxy is actually ready to route.
  health_check {
    enabled             = true
    port                = tostring(var.health_check_port)
    protocol            = "HTTP"
    path                = var.health_check_path
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
    timeout             = 5
    matcher             = "200"
  }

  # Down from the AWS default of 300s. This is dead time on every teardown: the
  # target group refuses to deregister a target until it elapses, and a destroy
  # waits it out. Thirty seconds is ample for an environment with no long-lived
  # connections, and it is the difference between a teardown that finishes and one
  # that looks hung.
  deregistration_delay = 30

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-platform-gateway"
    }
  )

  # The listener references this target group, so a replacement has to exist before
  # the old one can go.
  lifecycle {
    create_before_destroy = true
  }
}
