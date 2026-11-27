# bootstrap — GitHub Actions OIDC roles + KMS-encrypted state bucket (one-time, per account)

Also the ECR roles application pipelines use (`ecr.tf`): `github-actions-ecr-push` for
ci-templates' `service-release` workflow (from `main` only, `apps/*` only) and
`github-actions-ecr-read` for app-gitops' CI. Images outlive the cluster, which is why
they are here and not in `foundation` or `workload`.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.40.0 |
| <a name="requirement_tls"></a> [tls](#requirement\_tls) | >= 4.0.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.40.0 |
| <a name="provider_tls"></a> [tls](#provider\_tls) | >= 4.0.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_openid_connect_provider.github_actions](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_openid_connect_provider) | resource |
| [aws_iam_role.deploy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecr_push](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.ecr_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.ecr_push](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.ecr_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.plan_state_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.deploy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_role_policy_attachment.plan](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_iam_service_linked_role.spot](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_service_linked_role) | resource |
| [aws_kms_alias.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_s3_bucket.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_public_access_block.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.state](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.ecr_push](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ecr_push_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ecr_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.ecr_read_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.github_actions_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.plan_state_read](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [tls_certificate.github_actions](https://registry.terraform.io/providers/hashicorp/tls/latest/docs/data-sources/certificate) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_deploy_policy_arn"></a> [deploy\_policy\_arn](#input\_deploy\_policy\_arn) | Managed policy attached to the deploy role. AdministratorAccess remains a known gap (ARCHITECTURE.md §12): sizing a custom policy for EKS is iterative and was deliberately deferred, since the role split already removes this credential from pull-request reach. | `string` | `"arn:aws:iam::aws:policy/AdministratorAccess"` | no |
| <a name="input_deploy_role_name"></a> [deploy\_role\_name](#input\_deploy\_role\_name) | Name of the write-capable IAM role assumed by terraform-deploy and terraform-destroy | `string` | `"github-actions-eks-deploy"` | no |
| <a name="input_ecr_push_repositories"></a> [ecr\_push\_repositories](#input\_ecr\_push\_repositories) | Repositories whose default-branch release workflow may push images to apps/* in ECR, as owner/name. A trailing * matches every repository of the owner. Pull requests never get the push role. | `list(string)` | <pre>[<br/>  "gulinux86/*"<br/>]</pre> | no |
| <a name="input_ecr_push_role_name"></a> [ecr\_push\_role\_name](#input\_ecr\_push\_role\_name) | Name of the role application release workflows push to ECR with | `string` | `"github-actions-ecr-push"` | no |
| <a name="input_ecr_read_role_name"></a> [ecr\_read\_role\_name](#input\_ecr\_read\_role\_name) | Name of the read-only role app-gitops' CI reads images with | `string` | `"github-actions-ecr-read"` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment this AWS account serves (hml or prod). The deploy role trusts only this environment's GitHub Environment claim, so bootstrapping an account is a deliberate choice — there is no default. | `string` | n/a | yes |
| <a name="input_github_repository"></a> [github\_repository](#input\_github\_repository) | GitHub repository allowed to assume the role, as owner/name | `string` | `"gulinux86/eks-terraform"` | no |
| <a name="input_gitops_repository"></a> [gitops\_repository](#input\_gitops\_repository) | The application GitOps repository, as owner/name. Its CI reads the images its values files pin. | `string` | `"gulinux86/app-gitops"` | no |
| <a name="input_plan_policy_arn"></a> [plan\_policy\_arn](#input\_plan\_policy\_arn) | Managed policy attached to the plan role. Read-only by design; the role additionally gets an inline kms:Decrypt grant on the state key, which ReadOnlyAccess does not cover. | `string` | `"arn:aws:iam::aws:policy/ReadOnlyAccess"` | no |
| <a name="input_plan_role_name"></a> [plan\_role\_name](#input\_plan\_role\_name) | Name of the read-only IAM role assumed by terraform-plan | `string` | `"github-actions-eks-plan"` | no |
| <a name="input_region"></a> [region](#input\_region) | AWS region (IAM is global, but the provider needs a region) | `string` | `"us-east-1"` | no |
| <a name="input_state_bucket_name"></a> [state\_bucket\_name](#input\_state\_bucket\_name) | S3 bucket that stores the foundation/workload remote state. Must match the bucket in environments/<env>/backend.hcl. | `string` | `"eks-development-tfstate-889384902110"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to the created IAM resources | `map(string)` | <pre>{<br/>  "Layer": "bootstrap",<br/>  "ManagedBy": "terraform",<br/>  "Project": "eks"<br/>}</pre> | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_deploy_role_arn"></a> [deploy\_role\_arn](#output\_deploy\_role\_arn) | ARN of the write-capable deploy role. Set as the <ENV>\_DEPLOY\_ROLE\_ARN GitHub secret, and list it in cluster\_admin\_role\_arns so workload applies are authorized inside the cluster. |
| <a name="output_ecr_push_role_arn"></a> [ecr\_push\_role\_arn](#output\_ecr\_push\_role\_arn) | ARN of the ECR push role. Set as the ECR\_PUSH\_ROLE\_ARN secret in each application repository that uses ci-templates' service-release workflow. |
| <a name="output_ecr_read_role_arn"></a> [ecr\_read\_role\_arn](#output\_ecr\_read\_role\_arn) | ARN of the ECR read role. Set as the ECR\_READ\_ROLE\_ARN secret in app-gitops. |
| <a name="output_ecr_registry"></a> [ecr\_registry](#output\_ecr\_registry) | The account's ECR registry. Images are <registry>/apps/<app>[/<service>]. |
| <a name="output_oidc_provider_arn"></a> [oidc\_provider\_arn](#output\_oidc\_provider\_arn) | ARN of the GitHub Actions OIDC identity provider |
| <a name="output_plan_role_arn"></a> [plan\_role\_arn](#output\_plan\_role\_arn) | ARN of the read-only plan role. Set as the <ENV>\_PLAN\_ROLE\_ARN GitHub secret. |
| <a name="output_state_bucket"></a> [state\_bucket](#output\_state\_bucket) | S3 bucket holding the foundation/workload remote state |
<!-- END_TF_DOCS -->
