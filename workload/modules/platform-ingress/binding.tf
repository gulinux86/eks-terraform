# Delivered as a local Helm chart, not as kubernetes_manifest.
#
# Same reason argocd-bootstrap is: kubernetes_manifest needs a CRD's schema at
# *plan* time, and on a first apply the AWS Load Balancer Controller's CRDs do not
# exist yet — the plan fails before anything can create them. Helm hands manifests
# to the cluster at apply time and never asks Terraform to understand them.
#
# And it is Terraform that applies it, not Argo CD, because the values below name
# resources in one AWS account and the platform repository is public (design §4).
resource "helm_release" "target_group_binding" {
  name      = "platform-ingress"
  chart     = "${path.module}/chart"
  namespace = var.gateway_namespace

  # The Gateway's namespace is created by Argo CD, which runs after this layer. The
  # binding is namespaced and cannot be created before its namespace exists.
  create_namespace = true

  set {
    name  = "name"
    value = var.gateway_service_name
  }
  set {
    name  = "namespace"
    value = var.gateway_namespace
  }
  set {
    name  = "serviceName"
    value = var.gateway_service_name
  }
  set {
    name  = "servicePort"
    value = var.listener_port
  }
  set {
    name  = "healthCheckPort"
    value = var.health_check_port
  }
  set {
    name  = "targetGroupArn"
    value = aws_lb_target_group.gateway.arn
  }
  set {
    name  = "loadBalancerSecurityGroupId"
    value = aws_security_group.lb.id
  }

  # Deliberately not waiting. The binding is accepted the moment the CRD exists, but
  # it has nothing to register until Argo CD has synced the Gateway and istiod has
  # produced its Service — which happens after this layer finishes. Waiting here
  # would block on work that is ordered to come later.
  wait = false
}
