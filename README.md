# eks-terraform

A private Amazon EKS platform in Terraform, handed over to Argo CD.

Terraform builds the network, the cluster and the AWS-side plumbing, then stops at a
deliberate boundary: two Argo CD `AppProject`s and one root `Application`. Everything
above that comes from
[`platform-gitops`](https://github.com/gulinux86/platform-gitops) — Gateway API,
cert-manager, Istio in ambient mode, Karpenter.

Design decisions and their trade-offs are in **`ARCHITECTURE.md`**. Read the relevant
section before changing a security-shaped default.

```
bootstrap/   state bucket (KMS) + OIDC roles + Spot SLR   run once per account
foundation/  VPC · EKS · KMS · system nodes · bastion    ─┐
             VPC endpoints · core add-ons · Karpenter IAM │ terraform_remote_state
workload/    ALB controller · ingress ALB · storage      ←┘
             Argo CD + the handover
                      └──▶ platform-gitops
```

- **Nothing is internet-facing.** Compute is private, the ingress ALB is `internal`,
  the bastion has no public IP — SSM Session Manager only.
- **The ingress edge belongs to Terraform**, not to a controller reacting to a
  manifest. That is what makes the teardown ordered (§3, §11).
- **Capacity is on demand.** A fixed node group hosts the controllers; Karpenter
  provisions the rest and consolidates it away when idle.
- **Two IAM roles, split on read/write.** A pull-request plan cannot mutate AWS.

## Layers

| Layer | Owns | State |
|---|---|---|
| `bootstrap` | State bucket, OIDC roles, EC2 Spot service-linked role | local, not committed |
| `foundation` | VPC, EKS, KMS, system node group, bastion, endpoints, core add-ons, Karpenter's AWS prerequisites | `foundation/<env>/terraform.tfstate` |
| `workload` | ALB controller, ingress ALB, StorageClass, Argo CD, the handover | `workload/<env>/terraform.tfstate` |

Everything above the handover arrives from `platform-gitops`: Gateway API,
cert-manager, Istio ambient, Karpenter, and the metrics stack (Prometheus, Grafana,
Kiali).

`workload` reads `foundation` outputs, so **`foundation` applies first**.
`foundation/outputs.tf` is that contract — `scripts/check-layer-contract.sh` guards it
in CI. Kubernetes version and add-on pins live in
`environments/<env>/terraform.tfvars`; **bump them together**.

## Usage

Terraform `~> 1.10`. Each layer uses a partial backend from
`environments/<env>/backend.hcl`.

```bash
terraform -chdir=bootstrap init && terraform -chdir=bootstrap apply -var environment=hml   # once per account

terraform -chdir=foundation init  -backend-config=environments/hml/backend.hcl
terraform -chdir=foundation apply -var-file=environments/hml/terraform.tfvars

terraform -chdir=workload   init  -backend-config=environments/hml/backend.hcl
terraform -chdir=workload   apply -var-file=environments/hml/terraform.tfvars
```

Credential-free checks, the same ones CI runs:

```bash
terraform fmt -check -recursive
terraform -chdir=foundation init -backend=false && terraform -chdir=foundation validate
terraform -chdir=workload   init -backend=false && terraform -chdir=workload   validate
./scripts/check-layer-contract.sh
trivy config --severity HIGH,CRITICAL --ignorefile .trivyignore .

terraform -chdir=foundation/modules/network init -backend=false   # mocked providers,
terraform -chdir=foundation/modules/network test                  # no AWS, no infra
```

**Tearing down: use `terraform-destroy.yml`, not a local `terraform destroy`.**
Controllers create AWS resources Terraform never records, and those hold subnets after
the cluster is gone. The workflow freezes Argo CD, drains Karpenter while its
controller is alive, terminates what survives, checks the VPC, then destroys in three
passes with a sweep between each. A local destroy does none of that — see §11.

**Cluster access.** The `hml` API endpoint is public and CIDR-gated:

```bash
aws eks update-kubeconfig --region us-east-1 --name eks-hml-cluster
```

Or through the bastion, which already has `kubectl`:

```bash
aws ssm start-session --target "$(terraform -chdir=foundation output -raw bastion_instance_id)"
```

Nothing in the platform is exposed; reach the UIs by port-forward:

```bash
kubectl -n argocd        port-forward svc/argocd-server 8080:443              # :8080  admin
kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80   # :3000  admin
kubectl -n observability port-forward svc/kiali 20001:20001                   # :20001 no login
```

Argo CD's and Grafana's passwords are in `argocd-initial-admin-secret` and
`kube-prometheus-stack-grafana` — both chart-generated, and regenerated on every
deploy. Kiali is read-only and unauthenticated, because the only way to reach it is a
port-forward from a machine that already has cluster credentials.

**Kiali needs traffic before it shows anything.** Its graph is drawn from
`istio_requests_total`, which only accumulates while requests flow — a quiet cluster
renders an empty topology that looks like a mesh problem.

## CI/CD

| Workflow | Trigger | What it does |
|---|---|---|
| `terraform-plan` | PR, dispatch | `validate` first (credential-free), then `plan` per layer; comments on the PR |
| `terraform-test` | PR, dispatch | `terraform test` on every module with a `tests/` directory — mocked, no credentials |
| `security-scan` | PR, dispatch | Trivy IaC scan; fails on HIGH/CRITICAL |
| `terraform-docs` | PR, dispatch | Fails when a README between the `BEGIN_TF_DOCS` markers is out of date |
| `terraform-deploy` | dispatch (env + layer) | Gated on tests, validate and Trivy, then `plan -out` → `apply tfplan` |
| `terraform-destroy` | dispatch (env + layer + typed confirm) | Ordered teardown (§11) |
| `eks-upgrade-pr` | dispatch (target minor) | Bumps the Kubernetes version and the six add-on pins in hml and prod, checks Karpenter, Istio, cert-manager and Argo CD support it; pushes a branch and opens it as a draft PR — mark it *Ready for review* to run the checks (§13) |
| `eks-upgrade` | dispatch (env) | Upgrades a live cluster: preflight, component compatibility, control plane, system nodes, add-ons, Karpenter nodes, verify (§13) |

Files prefixed `_` are reusable (`on: workflow_call`) and are not dispatched directly.
The deploy's gates call the same workflows the pull-request checks call, so a gate
cannot drift from the check it mirrors. AWS auth comes from a composite action in
[`ci-templates`](https://github.com/gulinux86/ci-templates), pinned by commit SHA.

**Adding a test suite needs no workflow edit** — the module list is derived from
whichever directories contain `tests/`.

Six of twelve modules have suites: `network`, `cluster`, `eks-addons`, `karpenter`,
`managed-node-group`, `platform-ingress` — 15 run blocks, 54 assertions, all with
mocked providers. They assert security invariants, not resource counts: that public
subnets carry no `role/elb` tag, that the ingress load balancer is `internal`, that
Karpenter can only terminate what carries both of its tags, that the system nodes
follow the cluster's version. `bastion` is the gap that matters (§12).

Deploys are never automatic on merge. `master` is the single deploy source;
pull-request plans always resolve to `hml`.

Pull-request checks are **advisory**: there is no branch protection, so they report
but do not block a merge. Deliberate for a single-maintainer portfolio, and the first
thing to turn on if that changes (§12).

Two roles: the plan role is read-only and trusted for `:pull_request`; the deploy role
is write and trusted **only** for `:environment:<env>`. GitHub stamps that claim only
for a job declaring an Environment, and the Environment's branch policy (`master`
only) is what stops a branch minting it for itself. See §9.

Secrets per account: `<ENV>_PLAN_ROLE_ARN`, `<ENV>_DEPLOY_ROLE_ARN`.

## Layout

```
bootstrap/     state bucket + OIDC roles + Spot service-linked role
foundation/    main.tf outputs.tf variables.tf backend.tf provider.tf
               environments/{hml,prod}/{terraform.tfvars,backend.hcl}
               modules/{network,cluster,managed-node-group,bastion,
                        vpc-endpoints,eks-addons,karpenter}/
workload/      same shape
               modules/{aws-load-balancer-controller,platform-ingress,
                        storage,argocd,argocd-bootstrap}/
scripts/       check-layer-contract.sh · eks-upgrade.sh
.github/       plan · test · security-scan · docs · deploy · destroy · eks-upgrade
.trivyignore   accepted exceptions — each needs a written reason
```

Module `README.md`s are terraform-docs output under a handwritten title; regenerate
with `terraform-docs -c .terraform-docs.yml <dir>` rather than hand-editing — CI
fails the pull request otherwise. Adding a test suite needs no workflow edit (see CI/CD).
