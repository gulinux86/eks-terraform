# foundation — EKS platform layer (network, cluster, nodes, bastion, endpoints)

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.40.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | >= 4.0.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_bastion"></a> [bastion](#module\_bastion) | ./modules/bastion | n/a |
| <a name="module_eks_cluster"></a> [eks\_cluster](#module\_eks\_cluster) | ./modules/cluster | n/a |
| <a name="module_eks_managed-node-group"></a> [eks\_managed-node-group](#module\_eks\_managed-node-group) | ./modules/managed-node-group | n/a |
| <a name="module_eks_network"></a> [eks\_network](#module\_eks\_network) | ./modules/network | n/a |
| <a name="module_vpc_endpoints"></a> [vpc\_endpoints](#module\_vpc\_endpoints) | ./modules/vpc-endpoints | n/a |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cidr_block"></a> [cidr\_block](#input\_cidr\_block) | Networking CIDR block to be used for the VPC | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name to be used to name the resources (Name tag) | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region to create the resources | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to add to all AWS resources | `map(any)` | n/a | yes |
| <a name="input_desired_size"></a> [desired\_size](#input\_desired\_size) | Desired number of nodes | `number` | `1` | no |
| <a name="input_endpoint_public_access"></a> [endpoint\_public\_access](#input\_endpoint\_public\_access) | Expose the EKS API server publicly so Terraform (GitHub-hosted runners) and operators can reach it. Private access remains enabled. | `bool` | `true` | no |
| <a name="input_instance_types"></a> [instance\_types](#input\_instance\_types) | EC2 instance types for the managed node group. On a new AWS account under the Free Plan, only free-tier-eligible types launch (e.g. t3.small, t3.micro, c7i-flex.large, m7i-flex.large). | `list(string)` | <pre>[<br/>  "t3.small"<br/>]</pre> | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Kubernetes version for the EKS cluster. Pin a version in standard support (avoid extended-support versions). | `string` | `"1.34"` | no |
| <a name="input_max_size"></a> [max\_size](#input\_max\_size) | Maximum number of nodes | `number` | `2` | no |
| <a name="input_min_size"></a> [min\_size](#input\_min\_size) | Minimum number of nodes | `number` | `1` | no |
| <a name="input_public_access_cidrs"></a> [public\_access\_cidrs](#input\_public\_access\_cidrs) | CIDRs allowed to reach the public API endpoint. Tighten this per environment (e.g. office/CI egress ranges). | `list(string)` | <pre>[<br/>  "0.0.0.0/0"<br/>]</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_bastion_instance_id"></a> [bastion\_instance\_id](#output\_bastion\_instance\_id) | Connect with: aws ssm start-session --target <id> |
| <a name="output_certificate_authority"></a> [certificate\_authority](#output\_certificate\_authority) | Cluster CA (base64) for k8s/helm provider authentication |
| <a name="output_cluster_name"></a> [cluster\_name](#output\_cluster\_name) | EKS cluster name |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | Cluster API server endpoint |
| <a name="output_oidc"></a> [oidc](#output\_oidc) | Cluster OIDC provider issuer URL (used for IRSA) |
| <a name="output_project_name"></a> [project\_name](#output\_project\_name) | Project name, reused by the workload layer |
| <a name="output_region"></a> [region](#output\_region) | AWS region, reused by the workload layer |
| <a name="output_subnet_pub_1a"></a> [subnet\_pub\_1a](#output\_subnet\_pub\_1a) | Public subnet 1a |
| <a name="output_tags"></a> [tags](#output\_tags) | Project tags, reused by the workload layer |
| <a name="output_vpc_id"></a> [vpc\_id](#output\_vpc\_id) | VPC ID, used by the AWS Load Balancer Controller in the workload layer |
