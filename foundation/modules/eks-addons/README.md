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
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_addon.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_addon) | resource |
| [aws_iam_role.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ebs_csi](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_eks_addon_version.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/eks_addon_version) | data source |
| [aws_iam_policy_document.ebs_csi_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster name to attach the core add-ons to | `string` | n/a | yes |
| <a name="input_coredns_version"></a> [coredns\_version](#input\_coredns\_version) | Pin the coredns add-on version. Null resolves the latest compatible with kubernetes\_version. | `string` | `null` | no |
| <a name="input_ebs_csi_version"></a> [ebs\_csi\_version](#input\_ebs\_csi\_version) | Pin the aws-ebs-csi-driver add-on version. Null resolves the latest compatible with kubernetes\_version. | `string` | `null` | no |
| <a name="input_enable_ebs_csi"></a> [enable\_ebs\_csi](#input\_enable\_ebs\_csi) | Create the EBS CSI driver add-on and its IAM role. On by default: without it no PersistentVolumeClaim can ever bind. | `bool` | `true` | no |
| <a name="input_kube_proxy_version"></a> [kube\_proxy\_version](#input\_kube\_proxy\_version) | Pin the kube-proxy add-on version. Null resolves the latest compatible with kubernetes\_version. | `string` | `null` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | Cluster Kubernetes version, used to resolve a compatible add-on version | `string` | n/a | yes |
| <a name="input_metrics_server_version"></a> [metrics\_server\_version](#input\_metrics\_server\_version) | Pin the metrics-server add-on version. Null resolves the latest compatible with kubernetes\_version. | `string` | `null` | no |
| <a name="input_oidc_provider_arn"></a> [oidc\_provider\_arn](#input\_oidc\_provider\_arn) | Cluster OIDC provider ARN, used to build the EBS CSI driver's IRSA trust policy. | `string` | n/a | yes |
| <a name="input_pod_identity_agent_version"></a> [pod\_identity\_agent\_version](#input\_pod\_identity\_agent\_version) | Pin the eks-pod-identity-agent add-on version. Null resolves the latest compatible with kubernetes\_version. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the add-ons | `map(string)` | n/a | yes |
| <a name="input_vpc_cni_version"></a> [vpc\_cni\_version](#input\_vpc\_cni\_version) | Pin the vpc-cni add-on version. Null resolves the latest compatible with kubernetes\_version. | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_addon_versions"></a> [addon\_versions](#output\_addon\_versions) | Resolved version of each managed core add-on |
