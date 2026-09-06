# workload — cluster add-ons and the handover to Argo CD

The second and last Terraform layer. It reads `foundation`'s outputs through
`terraform_remote_state` and is the only layer with the `kubernetes` and `helm`
providers (ARCHITECTURE.md §2).

What it installs, in the order the modules imply:

| Module | What it is for |
|---|---|
| `aws-load-balancer-controller` | Registers pod IPs into target groups and writes the security-group rules that reach them. It no longer creates load balancers — nothing here asks it to. |
| `platform-ingress` | The AWS edge itself: an internal ALB, target group, listener and security group, plus the `TargetGroupBinding` the cluster attaches through. Owned here so `terraform destroy` can remove it in dependency order. |
| `storage` | A default `gp3` StorageClass. The EBS CSI driver is a `foundation` add-on; without a class it provisions nothing. |
| `argocd` | Argo CD itself, installed bare — no repository wired up, no ingress, no exposed UI. |
| `argocd-bootstrap` | The handover: the two `AppProject`s that form the privilege boundary, and the single root `Application`. Everything after this arrives from Git. |

## Where Terraform stops

`argocd-bootstrap` is the last thing this layer does. From there the platform is
extended by committing to the GitOps repository, not by editing Terraform.

The `AppProject`s stay in Terraform on purpose: they are the boundary between what
the platform repository may do and what an application repository may do, and a
boundary stored in the repository it governs can be widened by anyone who can commit
to that repository.

## The one contract pointing outward

`gateway_namespace` and `gateway_service_name` name a Service that `platform-gitops`
causes to exist — istiod generates it from the `Gateway` manifest. Every other
cross-layer reference in this codebase points the other way, from a consumer to a
producer's declared output.

It is checked by nothing: `scripts/check-layer-contract.sh` compares names within
this repository and says so about its own limits. A mismatch is silent — the target
group registers nothing and the load balancer answers 503. See
`modules/platform-ingress/README.md`.

## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | ~> 1.10 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.40.0 |
| <a name="requirement_helm"></a> [helm](#requirement\_helm) | 2.12.1 |
| <a name="requirement_kubernetes"></a> [kubernetes](#requirement\_kubernetes) | 2.25.2 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_argocd"></a> [argocd](#module\_argocd) | ./modules/argocd | n/a |
| <a name="module_argocd_bootstrap"></a> [argocd\_bootstrap](#module\_argocd\_bootstrap) | ./modules/argocd-bootstrap | n/a |
| <a name="module_eks_aws_load_balancer_controller"></a> [eks\_aws\_load\_balancer\_controller](#module\_eks\_aws\_load\_balancer\_controller) | ./modules/aws-load-balancer-controller | n/a |
| <a name="module_platform_ingress"></a> [platform\_ingress](#module\_platform\_ingress) | ./modules/platform-ingress | n/a |
| <a name="module_storage"></a> [storage](#module\_storage) | ./modules/storage | n/a |

## Resources

| Name | Type |
| ---- | ---- |
| [terraform_remote_state.foundation](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/data-sources/remote_state) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apps_namespaces"></a> [apps\_namespaces](#input\_apps\_namespaces) | Namespace patterns the apps project may deploy into. A prefix glob such as ["app-*"] avoids a Terraform change per application while keeping kube-system, istio-system, argocd and cert-manager unreachable. | `list(string)` | n/a | yes |
| <a name="input_apps_repo_url"></a> [apps\_repo\_url](#input\_apps\_repo\_url) | Git repository that will hold applications. Declared before the repository exists so the privilege boundary is reviewed before there is pressure to bend it. | `string` | n/a | yes |
| <a name="input_apps_source_repos"></a> [apps\_source\_repos](#input\_apps\_source\_repos) | Repositories the apps project may source from, chart repositories included. | `list(string)` | n/a | yes |
| <a name="input_argocd_chart_version"></a> [argocd\_chart\_version](#input\_argocd\_chart\_version) | argo-cd Helm chart version. Chart 10.4.0 ships Argo CD v3.5.1. | `string` | n/a | yes |
| <a name="input_foundation_state_bucket"></a> [foundation\_state\_bucket](#input\_foundation\_state\_bucket) | S3 bucket holding the foundation layer state | `string` | n/a | yes |
| <a name="input_foundation_state_key"></a> [foundation\_state\_key](#input\_foundation\_state\_key) | Foundation layer state key (e.g. foundation/hml/terraform.tfstate) | `string` | n/a | yes |
| <a name="input_gateway_namespace"></a> [gateway\_namespace](#input\_gateway\_namespace) | Namespace of the Service istiod generates for the platform Gateway. Must match the Gateway's namespace in the platform GitOps repository. | `string` | n/a | yes |
| <a name="input_gateway_service_name"></a> [gateway\_service\_name](#input\_gateway\_service\_name) | Name of that Service. Istio derives it from the Gateway's name, so renaming the Gateway in Git requires changing this value in the same change. | `string` | n/a | yes |
| <a name="input_ingress_listener_port"></a> [ingress\_listener\_port](#input\_ingress\_listener\_port) | Port the platform ingress load balancer listens on, and the Gateway Service port it forwards to. | `number` | n/a | yes |
| <a name="input_platform_repo_revision"></a> [platform\_repo\_revision](#input\_platform\_repo\_revision) | Branch or tag the root Application tracks. A branch follows every commit; a tag makes promotion explicit. | `string` | n/a | yes |
| <a name="input_platform_repo_url"></a> [platform\_repo\_url](#input\_platform\_repo\_url) | Git repository holding platform components. The platform AppProject accepts sources only from here. | `string` | n/a | yes |
| <a name="input_platform_source_repos"></a> [platform\_source\_repos](#input\_platform\_source\_repos) | Repositories the platform project may source from, chart repositories included. Enumerated rather than "*" so a component cannot be installed from an arbitrary registry. | `list(string)` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region (must match the foundation layer region) | `string` | n/a | yes |
| <a name="input_storage_reclaim_policy"></a> [storage\_reclaim\_policy](#input\_storage\_reclaim\_policy) | Reclaim policy for the default StorageClass. Retain protects data; Delete prevents orphaned volumes accruing cost in an environment that is rebuilt often. | `string` | n/a | yes |

## Outputs

No outputs.
