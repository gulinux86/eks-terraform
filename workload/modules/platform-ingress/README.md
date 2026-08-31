# platform-ingress — the AWS edge, owned by Terraform

An internal ALB, its target group, its listener and its security group, plus the
`TargetGroupBinding` that lets the cluster register into them.

The point is who owns the load balancer. Created from inside the cluster — by a
controller reacting to a `Gateway` or an `Ingress` — it never enters Terraform
state, so `terraform destroy` holds no edge from it to the subnets it occupies.
Its ENIs then hold the subnets, the subnets hold the VPC, and the destroy fails
after most of the platform is already gone. That happened four times in a row
before this module existed (ARCHITECTURE.md §11).

Declared here, the load balancer is a node in the dependency graph. Teardown
ordering follows from that rather than from a script that has to out-guess how
Argo CD and istiod sequence their own deletions.

## How the cluster attaches

`TargetGroupBinding` is a CRD from the AWS Load Balancer Controller. It registers
and deregisters pod IPs in a target group that already exists, and never creates
or deletes that target group. That sentence is the whole teardown guarantee: losing
the cluster mid-flight leaves stale entries in a table, not an AWS resource holding
a subnet.

It is applied by Terraform rather than committed to the GitOps repository, because
the target-group ARN and the security-group id name one AWS account and that
repository is public — the same reasoning that put Karpenter's controller on Pod
Identity rather than IRSA. It ships as a local Helm chart for the same reason
`argocd-bootstrap` does: `kubernetes_manifest` needs a CRD's schema at *plan* time,
and on a first apply the controller's CRDs do not exist yet.

## The contract with the GitOps repository

`gateway_namespace` and `gateway_service_name` name a Service this repository does
not create — istiod generates it from the `Gateway` manifest in `platform-gitops`,
naming it after the Gateway (`<gateway>-istio`). This is the one contract pointing
from Terraform outward; every other cross-layer reference goes the other way.

Both are variables without defaults, because **a mismatch is silent**: the binding
resolves to nothing, the target group stays empty, and the load balancer answers
503. Nothing errors. When traffic does not arrive, read target health before reading
logs.

## Internal, deliberately

`internal = true`, and the security group admits only the VPC CIDR. Exposing the
platform to the internet means editing that argument and merging a pull request —
which replaced a softer guard, the *absence* of a `kubernetes.io/role/elb` tag on
the public subnets, defeatable by anyone who could tag a subnet.

The listener serves plain HTTP, which is why `AVD-AWS-0054` is suppressed with a
written removal condition in `.trivyignore`. TLS terminates here when the external
path lands, since ACM attaches natively to an ALB listener — one of the reasons this
is an ALB rather than an NLB.

## Sharp edges

- **The health check targets port 15021**, Istio's gateway readiness endpoint, not
  the traffic port. A gateway proxy accepts connections on 80 before its
  configuration is programmed, so health-checking the traffic port reports healthy
  too early.
- **`deregistration_delay` is 30s**, down from the AWS default of 300. That default
  is dead time on every teardown. Raise it when real traffic depends on graceful
  connection draining.
- **`spec.networking` on the binding mutates a security group Terraform manages**,
  which shows as drift on the next plan. Drift, not a destroy failure.
## Requirements

No requirements.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_lb.platform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.platform](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_target_group.gateway](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_security_group.lb](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/security_group) | resource |
| [aws_vpc_security_group_egress_rule.to_targets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_egress_rule.to_targets_health](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_egress_rule) | resource |
| [aws_vpc_security_group_ingress_rule.from_vpc](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/vpc_security_group_ingress_rule) | resource |
| [helm_release.target_group_binding](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_gateway_namespace"></a> [gateway\_namespace](#input\_gateway\_namespace) | Namespace of the Service istiod generates for the platform Gateway. Defined in the GitOps repository, which makes this the one contract that points from Terraform out to Git rather than the other way round. | `string` | n/a | yes |
| <a name="input_gateway_service_name"></a> [gateway\_service\_name](#input\_gateway\_service\_name) | Name of that Service. Istio names it after the Gateway. A mismatch is not an error anywhere — the target group simply registers nothing and the load balancer answers 503, so check target health first when traffic does not arrive. | `string` | n/a | yes |
| <a name="input_health_check_path"></a> [health\_check\_path](#input\_health\_check\_path) | Readiness path on health\_check\_port | `string` | `"/healthz/ready"` | no |
| <a name="input_health_check_port"></a> [health\_check\_port](#input\_health\_check\_port) | Istio's gateway readiness port. Deliberately not the traffic port: a gateway with no routes attached still serves traffic ports without being ready, so health-checking 80 reports healthy too early and unhealthy for the wrong reasons. | `number` | `15021` | no |
| <a name="input_listener_port"></a> [listener\_port](#input\_listener\_port) | Port the load balancer listens on, and the Service port it forwards to. | `number` | `80` | no |
| <a name="input_private_subnet_ids"></a> [private\_subnet\_ids](#input\_private\_subnet\_ids) | Subnets the load balancer is placed in. Private only: an internal load balancer in a public subnet is still internal, but offering public subnets here is the first half of accidentally becoming internet-facing. | `list(string)` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name used to name the resources | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to be added to AWS resources | `map(string)` | n/a | yes |
| <a name="input_vpc_cidr"></a> [vpc\_cidr](#input\_vpc\_cidr) | Scopes the load balancer's security group while it stays internal. Widening this is not how external access is enabled — see the `internal` argument in lb.tf. | `string` | n/a | yes |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC the load balancer and its target group live in | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_dns_name"></a> [dns\_name](#output\_dns\_name) | Internal DNS name of the platform ingress load balancer. Resolvable from inside the VPC only — reach it from the bastion. |
| <a name="output_lb_arn"></a> [lb\_arn](#output\_lb\_arn) | Load balancer ARN, for operators inspecting target health |
| <a name="output_security_group_id"></a> [security\_group\_id](#output\_security\_group\_id) | The load balancer's security group. The TargetGroupBinding's networking rules allow ingress to the pods from this group. |
| <a name="output_target_group_arn"></a> [target\_group\_arn](#output\_target\_group\_arn) | Target group the cluster registers gateway pods into. Consumed by the TargetGroupBinding in this module, never published to Git — it names an AWS account. |
