# foundation — EKS platform layer (network, cluster, nodes, bastion, endpoints, core add-ons)

Applied first, and consumed by `workload` through `terraform_remote_state`.
`outputs.tf` is that contract: renaming or removing an output there breaks the
other layer at run time, which `scripts/check-layer-contract.sh` guards against.

Some outputs exist for consumers that are not Terraform at all. The `karpenter_*`
values are read by the platform GitOps repository's manifests — they are the handful
of AWS names an in-cluster object has to match, and none of them are secrets.

## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.40.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | >= 4.0.0 |

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_bastion"></a> [bastion](#module\_bastion) | ./modules/bastion | n/a |
| <a name="module_eks_addons"></a> [eks\_addons](#module\_eks\_addons) | ./modules/eks-addons | n/a |
| <a name="module_eks_cluster"></a> [eks\_cluster](#module\_eks\_cluster) | ./modules/cluster | n/a |
| <a name="module_eks_managed-node-group"></a> [eks\_managed-node-group](#module\_eks\_managed-node-group) | ./modules/managed-node-group | n/a |
| <a name="module_eks_network"></a> [eks\_network](#module\_eks\_network) | ./modules/network | n/a |
| <a name="module_karpenter"></a> [karpenter](#module\_karpenter) | ./modules/karpenter | n/a |
| <a name="module_vpc_endpoints"></a> [vpc\_endpoints](#module\_vpc\_endpoints) | ./modules/vpc-endpoints | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cidr_block"></a> [cidr\_block](#input\_cidr\_block) | Networking CIDR block to be used for the VPC | `string` | n/a | yes |
| <a name="input_cluster_admin_role_arns"></a> [cluster\_admin\_role\_arns](#input\_cluster\_admin\_role\_arns) | IAM principals granted EKS cluster-admin (typically the CI/CD deploy role that runs Terraform). Needed so the workload layer's kubernetes/helm providers are authorized. Required — see the validation below. | `list(string)` | n/a | yes |
| <a name="input_coredns_version"></a> [coredns\_version](#input\_coredns\_version) | Pin the coredns add-on version. Null resolves the latest compatible with kubernetes\_version. | `string` | n/a | yes |
| <a name="input_desired_size"></a> [desired\_size](#input\_desired\_size) | Desired number of nodes | `number` | n/a | yes |
| <a name="input_ebs_csi_version"></a> [ebs\_csi\_version](#input\_ebs\_csi\_version) | aws-ebs-csi-driver add-on version. Required for the same reason. | `string` | n/a | yes |
| <a name="input_endpoint_public_access"></a> [endpoint\_public\_access](#input\_endpoint\_public\_access) | Expose the EKS API server publicly so Terraform (GitHub-hosted runners) and operators can reach it. Private access remains enabled. | `bool` | n/a | yes |
| <a name="input_instance_types"></a> [instance\_types](#input\_instance\_types) | EC2 instance types for the managed node group. On a new AWS account under the Free Plan, only free-tier-eligible types launch (e.g. t3.small, t3.micro, c7i-flex.large, m7i-flex.large). | `list(string)` | n/a | yes |
| <a name="input_kube_proxy_version"></a> [kube\_proxy\_version](#input\_kube\_proxy\_version) | Pin the kube-proxy add-on version. Null resolves the latest compatible with kubernetes\_version. | `string` | n/a | yes |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version for the EKS cluster. Pin a version in standard support (avoid extended-support versions). | `string` | n/a | yes |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Retention for the EKS control-plane log group. Unmanaged, EKS creates it with no expiry and audit logs accumulate forever. | `number` | n/a | yes |
| <a name="input_max_size"></a> [max\_size](#input\_max\_size) | Maximum number of nodes | `number` | n/a | yes |
| <a name="input_metrics_server_version"></a> [metrics\_server\_version](#input\_metrics\_server\_version) | metrics-server add-on version. Required, like every other add-on version: an unpinned add-on resolves to whatever is latest at apply time, so two applies months apart install different software with no diff in the code. | `string` | n/a | yes |
| <a name="input_min_size"></a> [min\_size](#input\_min\_size) | Minimum number of nodes | `number` | n/a | yes |
| <a name="input_pod_identity_agent_version"></a> [pod\_identity\_agent\_version](#input\_pod\_identity\_agent\_version) | eks-pod-identity-agent add-on version. Required for the same reason. | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name to be used to name the resources (Name tag) | `string` | n/a | yes |
| <a name="input_public_access_cidrs"></a> [public\_access\_cidrs](#input\_public\_access\_cidrs) | CIDRs allowed to reach the public API endpoint. Tighten this per environment (e.g. office/CI egress ranges). | `list(string)` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region to create the resources | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all AWS resources | `map(string)` | n/a | yes |
| <a name="input_vpc_cni_version"></a> [vpc\_cni\_version](#input\_vpc\_cni\_version) | Pin the vpc-cni add-on version. Null resolves the latest compatible with kubernetes\_version. | `string` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_bastion_instance_id"></a> [bastion\_instance\_id](#output\_bastion\_instance\_id) | Connect with: aws ssm start-session --target <id> |
| <a name="output_certificate_authority"></a> [certificate\_authority](#output\_certificate\_authority) | Cluster CA (base64) for k8s/helm provider authentication |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | EKS cluster name |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Cluster API server endpoint |
| <a name="output_karpenter_discovery_tag_value"></a> [karpenter\_discovery\_tag\_value](#output\_karpenter\_discovery\_tag\_value) | Value the EC2NodeClass subnet and security-group selectors must match on karpenter.sh/discovery |
| <a name="output_karpenter_interruption_queue"></a> [karpenter\_interruption\_queue](#output\_karpenter\_interruption\_queue) | Queue name for the Helm chart's settings.interruptionQueue |
| <a name="output_karpenter_node_role_name"></a> [karpenter\_node\_role\_name](#output\_karpenter\_node\_role\_name) | Role name for the EC2NodeClass's `role` field |
| <a name="output_kubectl_version"></a> [kubectl\_version](#output\_kubectl\_version) | kubectl version the bastion expects; the deploy workflow seeds this exact build. |
| <a name="output_oidc"></a> [oidc](#output\_oidc) | Cluster OIDC provider issuer URL (used for IRSA) |
| <a name="output_private_subnet_ids"></a> [private\_subnet\_ids](#output\_private\_subnet\_ids) | Private subnets the platform ingress load balancer is placed in. Internal-only: the public subnets are deliberately not offered here. |
| <a name="output_project_name"></a> [project\_name](#output\_project\_name) | Project name, reused by the workload layer |
| <a name="output_region"></a> [region](#output\_region) | AWS region, reused by the workload layer |
| <a name="output_subnet_pub_1a"></a> [subnet\_pub\_1a](#output\_subnet\_pub\_1a) | Public subnet 1a |
| <a name="output_tags"></a> [tags](#output\_tags) | Project tags, reused by the workload layer |
| <a name="output_tooling_bucket"></a> [tooling\_bucket](#output\_tooling\_bucket) | Bucket the bastion pulls kubectl from. The deploy workflow seeds it after applying the foundation layer. |
| <a name="output_vpc_cidr"></a> [vpc\_cidr](#output\_vpc\_cidr) | VPC CIDR, scoping the ingress load balancer's security group while it stays internal |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID, used by the AWS Load Balancer Controller in the workload layer |
