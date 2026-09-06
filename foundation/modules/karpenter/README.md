# karpenter — the AWS side of node provisioning

Everything Karpenter needs that Kubernetes cannot create for itself. The controller,
`NodePool` and `EC2NodeClass` are delivered by Argo CD from the platform GitOps
repository; this module is what they attach to.

Nothing here is a secret, and nothing here is an ARN the GitOps repository has to
know. The outputs are names and tag values — see ARCHITECTURE.md §5.

## What it provides, and why each piece is not optional

| Piece | Without it |
|---|---|
| **Access Entry of type `EC2_LINUX`** | Instances boot, look healthy in EC2, and never register as Kubernetes nodes. A role gets an instance into the *account*; joining the *cluster* needs this, and `STANDARD` — the type used for humans and CI — does not work. |
| **SQS interruption queue + EventBridge rules** | Karpenter runs fine. The gap appears only during a Spot reclaim, when the node vanishes instead of draining. |
| **Pod Identity association** | The controller has no credentials, and says so only in its own logs. Requires the `eks-pod-identity-agent` add-on. |
| **Node role + the four managed policies** | Instances launch and cannot pull images, join the CNI, or be reached over SSM. |

## Two things to read before changing the policy

**`TerminateInstances` is conditioned on two tags**, and neither is sufficient alone:
`kubernetes.io/cluster/<name>=owned` says the instance belongs to this cluster — but
EKS puts that on managed node group instances too, so on its own it would put the
system pool in reach. `karpenter.sh/nodepool` is what excludes the node group and the
bastion.

**`karpenter.sh/` is a reserved tag prefix.** Keys under it are dropped from an
`EC2NodeClass`'s `tags` silently — no error, no warning, no event, while a custom tag
beside them applies normally. A condition naming `karpenter.sh/discovery` on an
*instance* can therefore never match. That tag belongs on the subnets and security
groups Karpenter *selects*, which is a different thing.

`tests/karpenter.tftest.hcl` guards both, plus the access entry type and the Pod
Identity binding.

## Why Pod Identity rather than IRSA

IRSA puts the role ARN on the Kubernetes ServiceAccount as an annotation. The chart
comes from a public Git repository, so that ARN would be committed, per account. Pod
Identity binds role to namespace and ServiceAccount from the AWS side, and the
manifest needs to know nothing.

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
| [aws_cloudwatch_event_rule.interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_rule) | resource |
| [aws_cloudwatch_event_target.interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_event_target) | resource |
| [aws_eks_access_entry.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_access_entry) | resource |
| [aws_eks_pod_identity_association.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_pod_identity_association) | resource |
| [aws_iam_role.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.node](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_sqs_queue.interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue) | resource |
| [aws_sqs_queue_policy.interruption](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sqs_queue_policy) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.controller](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.interruption_queue](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_arn"></a> [cluster\_arn](#input\_cluster\_arn) | Cluster ARN, so the controller's eks:DescribeCluster grant is scoped to this cluster only | `string` | n/a | yes |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | EKS cluster Karpenter provisions nodes for | `string` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace the Karpenter controller runs in. Karpenter v1 charts default to kube-system. | `string` | `"kube-system"` | no |
| <a name="input_project_name"></a> [project\_name](#input\_project\_name) | Project name used to name the resources | `string` | n/a | yes |
| <a name="input_service_account"></a> [service\_account](#input\_service\_account) | Karpenter's ServiceAccount name. The Pod Identity association binds the role to this namespace/name pair, so it must match what the chart creates — a mismatch fails silently, with the controller simply unable to call AWS. | `string` | `"karpenter"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to be added to AWS resources | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_controller_role_arn"></a> [controller\_role\_arn](#output\_controller\_role\_arn) | Karpenter controller role. Bound to the ServiceAccount by Pod Identity, so the Helm values in Git never need it. |
| <a name="output_discovery_tag_value"></a> [discovery\_tag\_value](#output\_discovery\_tag\_value) | Value of the karpenter.sh/discovery tag on subnets and security groups. The EC2NodeClass selectors must match it. |
| <a name="output_interruption_queue_name"></a> [interruption\_queue\_name](#output\_interruption\_queue\_name) | Queue the controller polls for interruption events; goes into the Helm values as settings.interruptionQueue. |
| <a name="output_node_role_name"></a> [node\_role\_name](#output\_node\_role\_name) | Role Karpenter-provisioned nodes assume. The EC2NodeClass in the GitOps repo references it by NAME, not ARN. |
