# workload — cluster add-ons layer (AWS Load Balancer Controller)

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.40.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | 2.12.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | 2.25.2 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_eks_aws_load_balancer_controller"></a> [eks\_aws\_load\_balancer\_controller](#module\_eks\_aws\_load\_balancer\_controller) | ./modules/aws-load-balancer-controller | n/a |

## Resources

| Name | Type |
|------|------|
| [terraform_remote_state.foundation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_foundation_state_bucket"></a> [foundation\_state\_bucket](#input\_foundation\_state\_bucket) | S3 bucket holding the foundation layer state | `string` | n/a | yes |
| <a name="input_foundation_state_key"></a> [foundation\_state\_key](#input\_foundation\_state\_key) | Foundation layer state key (e.g. foundation/hml/terraform.tfstate) | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region (must match the foundation layer region) | `string` | n/a | yes |
