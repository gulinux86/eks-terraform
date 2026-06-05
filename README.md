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
                         │  └────────────────────────────────┘         │
                         └─────────────────────────────────────────────┘

  foundation/  ──(terraform_remote_state)──▶  workload/
  network, EKS, KMS, OIDC, nodes, bastion       AWS Load Balancer Controller (IRSA + Helm)
```

## Layers

| Layer        | Responsibility                                                                   | State                                |
|--------------|----------------------------------------------------------------------------------|--------------------------------------|
| `bootstrap`  | One-time per account: KMS-encrypted S3 **state bucket** + GitHub Actions **OIDC role** | local state (committed `terraform.tfstate`) |
| `foundation` | VPC, subnets, NAT/IGW, EKS, KMS, OIDC, managed node group, bastion, VPC endpoints | `foundation/<env>/terraform.tfstate` |
| `workload`   | Cluster add-ons — today the AWS Load Balancer Controller (IRSA + Helm)            | `workload/<env>/terraform.tfstate`   |

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
| `terraform-destroy.yml` | `workflow_dispatch` (env + layer, typed confirm) | `destroy` (`workload` before `foundation` for `both`); `prod` requires reviewer approval |

- AWS authentication via **OIDC** (no static keys).
- Environment inferred from the base branch (`main` → prod, otherwise → hml) or chosen on dispatch.
- `prod` is protected by a GitHub Environment (required reviewer).
- The PR checks above can optionally be promoted to **required status checks** on
  `master` (branch protection) to block merging when they fail — not enforced by
  default.

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
```

To add coverage for another module, drop a `tests/<name>.tftest.hcl` with a
`mock_provider "aws" {}` block and `command = plan` assertions, then add the
module path to the matrix in `terraform-test.yml`.

Run the IaC security scan locally the same way CI does:

```bash
trivy config --severity HIGH,CRITICAL --ignorefile .trivyignore .
```

Accepted, documented exceptions live in `.trivyignore` (each with a reason).
Tighten them for `prod` — see `ARCHITECTURE.md` §11.

## Repository layout

```
bootstrap/                # one-time: KMS-encrypted state bucket + OIDC role (local state)
  main.tf  s3-state.tf  outputs.tf  provider.tf  variables.tf  README.md
foundation/
  main.tf  provider.tf  variables.tf  backend.tf  outputs.tf  README.md
  environments/{hml,prod}/{terraform.tfvars,backend.hcl}
  modules/{network,cluster,managed-node-group,bastion,vpc-endpoints}/
    tests/*.tftest.hcl    # native terraform test (network, cluster)
workload/
  main.tf  provider.tf  variables.tf  backend.tf  README.md
  environments/{hml,prod}/{terraform.tfvars,backend.hcl}
  modules/aws-load-balancer-controller/
.github/workflows/        # plan, test, security-scan, deploy, destroy
.trivyignore              # documented, accepted Trivy exceptions
ARCHITECTURE.md
```
