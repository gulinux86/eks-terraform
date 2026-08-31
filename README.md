# eks-terraform

Provisioning of a **private Amazon EKS** cluster with Terraform, organized into
two independent state layers (`foundation` and `workload`) and shipped with a
GitHub Actions CI/CD pipeline.

> **Design & trade-offs:** see [ARCHITECTURE.md](./ARCHITECTURE.md).
> Per-module/per-layer inputs and outputs are documented in each directory's
> `README.md` (generated with [terraform-docs](https://terraform-docs.io)).

## Architecture at a glance

```
                         ┌─────────────────────────────────────────────┐
                         │                    VPC                       │
                         │   10.0.0.0/16 (hml)  /  10.1.0.0/16 (prod)   │
                         │                                              │
   ┌──────────┐  IGW     │  ┌─────────── public ─────────────┐         │
   │ Internet │──────────┼─▶│  NAT-1a        NAT-1b           │         │
   └──────────┘          │  └────────────────────────────────┘         │
                         │  ┌─────────── private ────────────┐         │
                         │  │  EKS API (private ENIs)         │         │
                         │  │  Managed node group (AL2023)    │         │
                         │  │  Bastion (access via SSM)       │         │
                         │  │  VPC interface/gateway endpoints│         │
                         │  │  Platform ALB (internal)        │         │
                         │  └────────────────────────────────┘         │
                         └─────────────────────────────────────────────┘

  foundation/  ──(terraform_remote_state)──▶  workload/
  network, EKS, KMS, OIDC, nodes, bastion       ALB Controller, platform ingress,
                                                storage, Argo CD + the handover
```

The ingress edge is **owned by Terraform**, not created by a controller reacting to
a manifest: an internal ALB and its target group live in the `workload` layer, and
the cluster attaches through a `TargetGroupBinding`. That is what makes
`terraform destroy` able to remove it in dependency order — see
[ARCHITECTURE.md §3](ARCHITECTURE.md) and the teardown notes in §11.

```
  platform-gitops (Argo CD)          eks-terraform (Terraform)
  ─────────────────────────          ─────────────────────────
  Gateway  ──istiod──▶ Service       aws_lb (internal)
                       ClusterIP     aws_lb_target_group
                          ▲          aws_lb_listener
                          └──────────  TargetGroupBinding
                             registers pod IPs; owns nothing
```

## Layers

| Layer        | Responsibility                                                                   | State                                |
|--------------|----------------------------------------------------------------------------------|--------------------------------------|
| `bootstrap`  | One-time per account: KMS-encrypted S3 **state bucket** + GitHub Actions **OIDC roles** | local state — **not** committed (`*.tfstate` is gitignored) |
| `foundation` | VPC, subnets, NAT/IGW, EKS, KMS, OIDC, managed node group, bastion, VPC endpoints, core add-ons (vpc-cni/coredns/kube-proxy) | `foundation/<env>/terraform.tfstate` |
| `workload`   | Cluster add-ons — AWS Load Balancer Controller (IRSA + Helm), the platform ingress ALB, the default StorageClass, and Argo CD with the AppProjects and root Application that hand the cluster over | `workload/<env>/terraform.tfstate`   |

`bootstrap` runs once to create the backend the other layers use. The `workload`
layer reads `foundation` outputs through `terraform_remote_state`, so
**`foundation` is always applied before `workload`**. Cluster Kubernetes version
is **1.35** (set per environment in `environments/<env>/terraform.tfvars`).

## Prerequisites

- Terraform `~> 1.10`
- AWS CLI configured
- An S3 bucket for state (see `environments/<env>/backend.hcl`)

## Usage

Each layer uses a partial backend: `bucket`/`key`/`region` come from
`environments/<env>/backend.hcl`.

```bash
# 0) bootstrap (one-time per account): creates the KMS-encrypted state bucket
#    and the GitHub Actions OIDC role. Every principal that runs Terraform needs
#    kms:Decrypt / kms:GenerateDataKey on the state CMK created here.
terraform -chdir=bootstrap init
terraform -chdir=bootstrap apply

# 1) foundation
terraform -chdir=foundation init  -backend-config=environments/hml/backend.hcl
terraform -chdir=foundation plan  -var-file=environments/hml/terraform.tfvars
terraform -chdir=foundation apply -var-file=environments/hml/terraform.tfvars

# 2) workload (after foundation exists)
terraform -chdir=workload init  -backend-config=environments/hml/backend.hcl
terraform -chdir=workload plan  -var-file=environments/hml/terraform.tfvars
terraform -chdir=workload apply -var-file=environments/hml/terraform.tfvars
```

Swap `hml` for `prod` for the production environment.

### Tearing down

**Use `terraform-destroy.yml`, not a local `terraform destroy`.** Removing this
platform is not the reverse of applying it: controllers inside the cluster create
AWS resources Terraform never records, and those hold subnets after the cluster is
gone. The workflow handles that in order — it freezes Argo CD's automation before
deleting anything, strips finalizers that would hang the Helm uninstall, checks the
VPC before the destructive part starts, and sweeps the network interfaces a
terminated node group leaves behind.

A local destroy runs none of those steps. It works when nothing was stranded, and
fails with an opaque `DependencyViolation` after most of the platform is gone when
something was. ARCHITECTURE.md §11 has the details and the failures that produced
them.

### Cluster access via the bastion

The bastion is a private, SSM-only jump host (no public IP, no inbound rules).
`kubectl` is installed at boot from the Amazon-EKS S3 bucket via the S3 gateway
endpoint (no internet egress). Helm is **not** on the bastion — Helm releases run
in the `workload` layer.

```bash
aws ssm start-session --target <bastion_instance_id>
# set up kubeconfig for your shell session, then use kubectl:
aws eks update-kubeconfig --region <region> --name <project_name>-cluster
kubectl get nodes
```

## CI/CD (GitHub Actions)

| Workflow                | Trigger                                          | What it does                                                                       |
|-------------------------|--------------------------------------------------|------------------------------------------------------------------------------------|
| `terraform-plan.yml`    | PR to `master`/`develop`/`main`, `workflow_dispatch` | `fmt` + `validate` + `plan` (matrix over `foundation`/`workload`); comments the plan on the PR |
| `terraform-test.yml`    | PR (`**.tf`/`**.tftest.hcl`), `workflow_dispatch` | Native `terraform test` on critical modules; mocked providers → no AWS creds, no infra |
| `security-scan.yml`     | PR (Terraform paths), `workflow_dispatch`        | Trivy IaC scan (`config` mode); fails on HIGH/CRITICAL; uploads SARIF to the Security tab |
| `terraform-deploy.yml`  | `workflow_dispatch` (env + layer)                | **Gated** by `terraform test` + Trivy, then `plan -out` + `apply` of the saved plan (`foundation`→`workload`); `prod` requires reviewer approval |
| `terraform-destroy.yml` | `workflow_dispatch` (env + layer, typed confirm) | Ordered teardown: drain the cluster → destroy `workload` → preflight the VPC → destroy the node group → sweep orphaned ENIs → destroy the rest of `foundation`; `prod` requires reviewer approval |

- AWS authentication via **OIDC** (no static keys), through **two roles split by
  what the job does** — see [Pipeline access](#pipeline-access-two-roles) below.
- `master` is the single deploy source. The environment is chosen on dispatch;
  pull-request plans always resolve to `hml`. There is no branch per environment.
- `prod` is protected by a GitHub Environment (required reviewer).
- The PR checks above can optionally be promoted to **required status checks** on
  `master` (branch protection) to block merging when they fail — not enforced by
  default.

### Pipeline access — two roles

The workflows do very different things, so they get different credentials. A pull
request runs the workflow file **from its own branch**, so the job that only needs
to read must never hold a credential that can write.

| Role | Trusted `sub` claim | Permission | Used by |
|------|---------------------|------------|---------|
| `github-actions-eks-plan` | `:pull_request`, `:ref:refs/heads/*` | read-only (+ `kms:Decrypt` on the state key) | `terraform-plan` |
| `github-actions-eks-deploy` | `:environment:<env>` **only** | write | `terraform-deploy`, `terraform-destroy` |

GitHub stamps the `environment:<name>` claim **only** for a job that declares an
Environment — which the two write workflows do and the plan workflow does not.

**The Environment's deployment-branch policy is load-bearing.** Restricted to
`master`, GitHub refuses any other branch's job *before it starts*, so no token is
ever issued. Without it, a pull request could add `environment: hml` to any job and
mint the deploy claim itself, defeating the split. Required setup:

| Environment | Deployment branches | Required reviewer |
|---|---|---|
| `hml` | `master` only | no — hml stays fast |
| `prod` | `master` only | yes (`gulinux86`), **self-review allowed** |

**Why self-review is allowed on `prod`:** the repository has a single maintainer.
Disabling self-review with a one-person reviewer list would make production deploys
impossible — the dispatcher would be the only reviewer and would be refused. What
remains is a deliberate pause and an attributable approval, not four-eyes. Add a
second reviewer and disable self-review the moment there is one.

Authorization deliberately lives **outside** the pipeline. An allowlist checked as
a workflow step would run after the credential was issued, and could be deleted by
anyone able to edit the workflow — the same people it is meant to constrain.

Required secrets, per account:

```
HML_PLAN_ROLE_ARN     HML_DEPLOY_ROLE_ARN
PROD_PLAN_ROLE_ARN    PROD_DEPLOY_ROLE_ARN   (once the prod account exists)
```

Both come from `bootstrap` outputs (`plan_role_arn`, `deploy_role_arn`). Bootstrap
is applied **once per account** with `-var environment=hml|prod`, from a
workstation with administrator credentials — never through the pipeline. The deploy
role must also appear in that environment's `cluster_admin_role_arns`, or
`workload` applies lose in-cluster authorization.

### Quality gates — defense in depth

The same tests run as a **PR gate** (block the merge) and again as a **pre-apply
gate** in `terraform-deploy.yml` (block the apply). Both are env-agnostic, so hml
and prod get the identical checks.

```
PR opened ─▶ terraform-plan + terraform-test + security-scan   ← block MERGE
   │ merge
   ▼
deploy (dispatch) ─▶ test ┐
                          ├─▶ apply  foundation ─▶ workload     ← block APPLY
                     trivy ┘   (init → plan -out → apply tfplan)
                                  └ prod: reviewer approval after the gates pass
```

### Tests & security scanning

Critical modules are guarded by native `terraform test` suites (plan-mode,
mocked providers — they run with no AWS credentials and create no resources):

```bash
terraform -chdir=foundation/modules/network init -backend=false
terraform -chdir=foundation/modules/network test
terraform -chdir=foundation/modules/cluster init -backend=false
terraform -chdir=foundation/modules/cluster test
terraform -chdir=foundation/modules/eks-addons init -backend=false
terraform -chdir=foundation/modules/eks-addons test
```

To add coverage for another module, drop a `tests/<name>.tftest.hcl` with a
`mock_provider "aws" {}` block and `command = plan` assertions, then add the
module path to the matrix in `terraform-test.yml`.

Run the IaC security scan locally the same way CI does:

```bash
trivy config --severity HIGH,CRITICAL --ignorefile .trivyignore .
```

Accepted, documented exceptions live in `.trivyignore` (each with a reason).
Tighten them for `prod` — see `ARCHITECTURE.md` §12.

## Repository layout

```
bootstrap/                # one-time: KMS-encrypted state bucket + OIDC role (local state)
  main.tf  s3-state.tf  outputs.tf  provider.tf  variables.tf  README.md
foundation/
  main.tf  provider.tf  variables.tf  backend.tf  outputs.tf  README.md
  environments/{hml,prod}/{terraform.tfvars,backend.hcl}
  modules/{network,cluster,managed-node-group,bastion,vpc-endpoints,eks-addons,karpenter}/
    tests/*.tftest.hcl    # native terraform test (network, cluster, eks-addons)
workload/
  main.tf  provider.tf  variables.tf  backend.tf  README.md
  environments/{hml,prod}/{terraform.tfvars,backend.hcl}
  modules/{aws-load-balancer-controller,platform-ingress,storage,argocd,argocd-bootstrap}/
scripts/check-layer-contract.sh   # foundation outputs vs. what workload consumes
.github/workflows/        # plan, test, security-scan, deploy, destroy
.trivyignore              # documented, accepted Trivy exceptions
ARCHITECTURE.md
```
