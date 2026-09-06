# argocd-bootstrap — the handover

The point where Terraform stops and Argo CD takes over: two `AppProject`s and one
root `Application`. Everything after this reaches the cluster from Git.

## Why the projects stay in Terraform

They are the privilege boundary between the platform repository and the application
repository. A boundary stored in the repository it governs can be widened by anyone
who can commit there.

| | `platform` project | `apps` project |
|---|---|---|
| Sources | the platform repository + chart registries | the application repository |
| Cluster-scoped resources | allowed | **denied** |
| Destinations | any namespace | a namespace prefix (`app-*`) |

The `apps` project is created before its repository exists, so the boundary is
written and reviewed before there is pressure to bend it.

## Two things that are easy to get wrong

**Chart repositories count as sources.** A multi-source Application takes its chart
from one repository and its values from another, and Argo CD checks both. Listing
only the Git repository fails every chart-based component with `repo is not
permitted` — including OCI registries, which must appear with their `oci://` scheme.

**Delivered as a local Helm chart, not `kubernetes_manifest`.** That provider needs a
CRD's schema at *plan* time, and on a first apply Argo CD's CRDs do not exist yet —
the plan fails before anything can create them. Helm hands manifests to the cluster
at apply time and never asks Terraform to understand them.

## The root Application's finalizer

`resources-finalizer.argocd.argoproj.io` makes deletion cascade: removing the root
tells Argo CD to delete every child and the resources they own. The teardown depends
on that ordering — see ARCHITECTURE.md §11.

## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_helm"></a> [helm](#provider\_helm) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [helm_release.bootstrap](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_apps_namespaces"></a> [apps\_namespaces](#input\_apps\_namespaces) | Namespace patterns the apps project may deploy into. A prefix glob such as ["app-*"] avoids a Terraform change per application while keeping kube-system, istio-system, argocd and cert-manager out of reach — they do not match the prefix. | `list(string)` | n/a | yes |
| <a name="input_apps_repo_url"></a> [apps\_repo\_url](#input\_apps\_repo\_url) | Git repository that will hold applications. The apps AppProject is created ahead of the repository existing, so the privilege boundary is written and reviewed before there is pressure to bend it. | `string` | n/a | yes |
| <a name="input_apps_source_repos"></a> [apps\_source\_repos](#input\_apps\_source\_repos) | Every repository the apps project may pull from. Same rule: chart repositories count. | `list(string)` | n/a | yes |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace Argo CD runs in. The projects and the root Application are created here. | `string` | n/a | yes |
| <a name="input_platform_repo_revision"></a> [platform\_repo\_revision](#input\_platform\_repo\_revision) | Branch or tag the root Application tracks. A branch means Argo follows every commit; a tag means promotions are explicit. | `string` | n/a | yes |
| <a name="input_platform_repo_url"></a> [platform\_repo\_url](#input\_platform\_repo\_url) | Git repository holding platform components. The platform AppProject accepts sources only from here. | `string` | n/a | yes |
| <a name="input_platform_source_repos"></a> [platform\_source\_repos](#input\_platform\_source\_repos) | Every repository the platform project may pull from, Helm chart repositories included. A multi-source Application takes its chart from one repo and its values from another, and Argo CD checks both — listing only the Git repository fails every chart-based component. | `list(string)` | n/a | yes |

## Outputs

No outputs.
