# external-secrets-identity module — the External Secrets Operator's AWS role

One IAM role, bound through EKS Pod Identity to the operator's ServiceAccount
(`external-secrets/external-secrets`), reading `apps/*` in Secrets Manager. Every
application's `ExternalSecret` is served with it, so admitting an application needs no
Terraform.

Isolation between applications is therefore not in IAM: platform-gitops'
`components/policies/tenant-secrets.yaml` admits an `ExternalSecret` in `app-<name>`
only for keys under `apps/<name>/`, and refuses the objects that would use this role's credentials on their own
(`SecretStore`, `PushSecret`, generators). See `iam.tf`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.40.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.40.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_eks_pod_identity_association.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.read_app_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster the Pod Identity association is created in. | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace the External Secrets Operator runs in. Must match the Application's destination in platform-gitops (apps/01-external-secrets.yaml). | `string` | `"external-secrets"` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Prefix of the role name. | `string` | n/a | yes |
| <a name="input_service_account"></a> [service\_account](#input\_service\_account) | The controller's ServiceAccount. Must match serviceAccount.name in platform-gitops (components/external-secrets/values.yaml). | `string` | `"external-secrets"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to be added to AWS resources | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_role_name"></a> [role\_name](#output\_role\_name) | The External Secrets Operator controller's role. |
<!-- END_TF_DOCS -->
