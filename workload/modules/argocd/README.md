# argocd — GitOps controller (Helm, workload layer)

Installs Argo CD and nothing else. The chart brings its CRDs (`Application`,
`ApplicationSet`, `AppProject`) and the controllers that reconcile them.

## Why Terraform installs this one thing

Terraform is a poor tool for applying *custom resources*: `kubernetes_manifest`
needs a CRD's schema at **plan** time, and on a first apply the CRD does not exist
yet. Installing Argo CD through the Helm provider sidesteps that — Helm hands
manifests to the cluster at apply time and never asks Terraform to understand them.

From here the boundary is meant to be:

```
  Terraform  → the cluster, its add-ons, and Argo CD itself
  Argo CD    → every custom resource after that (NodePools, Rollouts, apps)
```

## Deliberately not included

- **No root Application / app-of-apps.** Nothing is wired to a Git repository yet.
- **No repository credentials.** A private config repo would need a secret, which
  needs a source (a Terraform-managed Secret, or External Secrets).
- **No ingress, no TLS, no exposed UI.** The Service is `ClusterIP`.
- **The AWS Load Balancer Controller was not migrated.** It remains a
  `helm_release` owned by Terraform. Two owners for one resource is the anti-pattern
  to avoid, so migrating it is its own reviewed change — not a side effect of this
  one.

## Sizing — why the node group is two nodes

The VPC CNI caps pods per node by ENI capacity, not by CPU or memory:

```
  t3.small allocatable pods   11        (measured on the running cluster)
  already in use               6        coredns ×2, kube-proxy, aws-node, ALB ×2
  free                         5

  Argo CD (non-HA)             7        server, repo-server, application-controller,
                                        applicationset-controller,
                                        notifications-controller, redis, dex
```

Seven into five does not go: two pods would stay `Pending` indefinitely. Hence
`desired_size = 2` in `hml`. `ha_enabled` stays **false** — HA adds a three-pod
redis-ha cluster plus extra replicas and does not fit this node group at all.

## Access

Nothing is exposed. Port-forward, then open `https://localhost:8080`:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d
```

That secret is a bootstrap credential. Change the admin password and delete it.

## Upgrading the chart

`chart_version` is pinned to an exact version and validated as such — a range or
`latest` would mean a rebuild could install a different Argo CD than the one
reviewed.

One sharp edge when bumping: **Helm 3 does not upgrade CRDs** on `helm upgrade`. If
a new chart version changes a CRD, that CRD must be applied out of band. Check the
chart's release notes rather than assuming the upgrade carried it.

`crds.keep = true` means uninstalling the release leaves the CRDs in place —
removing them would cascade-delete every `Application` in the cluster.


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
| [helm_release.argocd](https://registry.terraform.io/providers/hashicorp/helm/latest/docs/resources/release) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_chart_version"></a> [chart\_version](#input\_chart\_version) | argo-cd Helm chart version. Pinned deliberately: an unpinned chart means a rebuild can silently install a different Argo CD than the one that was reviewed. Chart 10.4.0 ships Argo CD v3.5.1. | `string` | `"10.4.0"` | no |
| <a name="input_ha_enabled"></a> [ha\_enabled](#input\_ha\_enabled) | Run Argo CD in high-availability mode. Off by default: HA adds a redis-ha cluster (3 pods) plus extra replicas, which does not fit a two-node t3.small cluster. Turn on when the node group can carry it. | `bool` | `false` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | Namespace Argo CD is installed into. Kept separate from kube-system so its RBAC and resource footprint are isolated from the cluster's own components. | `string` | `"argocd"` | no |
| <a name="input_server_service_type"></a> [server\_service\_type](#input\_server\_service\_type) | Kubernetes Service type for the Argo CD API/UI server. ClusterIP by default — nothing is exposed and access is via `kubectl port-forward`. Exposing the UI is a separate, deliberate change: it needs an ingress, TLS and an authentication story. | `string` | `"ClusterIP"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to be added to AWS resources | `map(string)` | n/a | yes |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_chart_version"></a> [chart\_version](#output\_chart\_version) | Installed argo-cd chart version |
| <a name="output_initial_password_command"></a> [initial\_password\_command](#output\_initial\_password\_command) | Retrieves the generated admin password. Change it and delete the secret; it is a bootstrap credential, not a permanent one. |
| <a name="output_namespace"></a> [namespace](#output\_namespace) | Namespace Argo CD runs in |
| <a name="output_port_forward_command"></a> [port\_forward\_command](#output\_port\_forward\_command) | Nothing is exposed; reach the UI through this port-forward, then https://localhost:8080 |
