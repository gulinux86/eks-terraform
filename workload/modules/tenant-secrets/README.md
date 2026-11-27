# tenant-secrets module — one IAM role per tenant for External Secrets

Each tenant with `secrets: true` in platform-gitops gets a role that trusts only
its own ServiceAccount (`app-<name>/external-secrets`) and reads only
`apps/<name>/*` in Secrets Manager. See `iam.tf` for why both conditions matter.

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
| [aws_iam_role.secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.read_own_secrets](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_oidc"></a> [oidc](#input\_oidc) | The cluster's OIDC issuer URL (foundation output `oidc`), which the roles' trust policies federate with. | `string` | n/a | yes |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Prefix of every role name. platform-gitops builds the same name (tenants/values.yaml, secretsRolePrefix) to reference the role from the tenant's ServiceAccount. | `string` | n/a | yes |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to be added to AWS resources | `map(string)` | n/a | yes |
| <a name="input_tenants"></a> [tenants](#input\_tenants) | Names of the tenants with `secrets: true` in platform-gitops (tenants/registry/<name>.yaml). One role each. | `list(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_role_names"></a> [role\_names](#output\_role\_names) | Secrets role per tenant, by tenant name. |
<!-- END_TF_DOCS -->
