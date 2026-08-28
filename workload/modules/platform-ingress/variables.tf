variable "project_name" {
  type        = string
  description = "Project name used to name the resources"
}

variable "vpc_id" {
  type        = string
  description = "VPC the load balancer and its target group live in"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Subnets the load balancer is placed in. Private only: an internal load balancer in a public subnet is still internal, but offering public subnets here is the first half of accidentally becoming internet-facing."
}

variable "vpc_cidr" {
  type        = string
  description = "Scopes the load balancer's security group while it stays internal. Widening this is not how external access is enabled — see the `internal` argument in lb.tf."
}

variable "gateway_namespace" {
  type        = string
  description = "Namespace of the Service istiod generates for the platform Gateway. Defined in the GitOps repository, which makes this the one contract that points from Terraform out to Git rather than the other way round."
}

variable "gateway_service_name" {
  type        = string
  description = "Name of that Service. Istio names it after the Gateway. A mismatch is not an error anywhere — the target group simply registers nothing and the load balancer answers 503, so check target health first when traffic does not arrive."
}

variable "listener_port" {
  type        = number
  description = "Port the load balancer listens on, and the Service port it forwards to."
  default     = 80
}

variable "health_check_port" {
  type        = number
  description = "Istio's gateway readiness port. Deliberately not the traffic port: a gateway with no routes attached still serves traffic ports without being ready, so health-checking 80 reports healthy too early and unhealthy for the wrong reasons."
  default     = 15021
}

variable "health_check_path" {
  type        = string
  description = "Readiness path on health_check_port"
  default     = "/healthz/ready"
}

variable "tags" {
  type        = map(string)
  description = "Tags to be added to AWS resources"
}
