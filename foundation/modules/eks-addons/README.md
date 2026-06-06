# eks-addons module — EKS managed core add-ons (vpc-cni, coredns, kube-proxy)



## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_eks_addon.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_eks_addon_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_addon_version) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster name to attach the core add-ons to | `string` | n/a | yes |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Cluster Kubernetes version, used to resolve a compatible add-on version | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the add-ons | `map(any)` | n/a | yes |
| <a name="input_coredns_version"></a> [coredns\_version](#input\_coredns\_version) | Pin the coredns add-on version. Null resolves the latest compatible with kubernetes\_version. | `string` | `null` | no |
| <a name="input_kube_proxy_version"></a> [kube\_proxy\_version](#input\_kube\_proxy\_version) | Pin the kube-proxy add-on version. Null resolves the latest compatible with kubernetes\_version. | `string` | `null` | no |
| <a name="input_vpc_cni_version"></a> [vpc\_cni\_version](#input\_vpc\_cni\_version) | Pin the vpc-cni add-on version. Null resolves the latest compatible with kubernetes\_version. | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_addon_versions"></a> [addon\_versions](#output\_addon\_versions) | Resolved version of each managed core add-on |
