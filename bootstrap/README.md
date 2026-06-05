# bootstrap — GitHub Actions OIDC role (one-time, per account)



## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.40.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | >= 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.40.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | >= 4.0.0 |

## Resources

| Name | Type |
|------|------|
| [aws_iam_openid_connect_provider.github_actions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.github_actions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy_attachment.ci](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_bucket.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_public_access_block.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [tls_certificate.github_actions](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_github_repository"></a> [github\_repository](#input\_github\_repository) | GitHub repository allowed to assume the role, as owner/name | `string` | `"gulinux86/eks-terraform"` | no |
| <a name="input_policy_arn"></a> [policy\_arn](#input\_policy\_arn) | Managed policy attached to the CI role. AdministratorAccess is a deliberate bootstrap simplification — scope it down with a custom policy / permission boundary for real production. | `string` | `"arn:aws:iam::aws:policy/AdministratorAccess"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region (IAM is global, but the provider needs a region) | `string` | `"us-east-1"` | no |
| <a name="input_role_name"></a> [role\_name](#input\_role\_name) | Name of the IAM role GitHub Actions will assume via OIDC | `string` | `"github-actions-eks-terraform"` | no |
| <a name="input_state_bucket_name"></a> [state\_bucket\_name](#input\_state\_bucket\_name) | S3 bucket that stores the foundation/workload remote state. Must match the bucket in environments/<env>/backend.hcl. | `string` | `"eks-development-tfstate-889384902110"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the created IAM resources | `map(any)` | <pre>{<br/>  "Layer": "bootstrap",<br/>  "ManagedBy": "terraform",<br/>  "Project": "eks"<br/>}</pre> | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the GitHub Actions OIDC identity provider |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of the CI role. Set this as the *\_AWS\_ROLE\_ARN GitHub secret for this account/environment. |
| <a name="output_state_bucket"></a> [state\_bucket](#output\_state\_bucket) | S3 bucket holding the foundation/workload remote state |
