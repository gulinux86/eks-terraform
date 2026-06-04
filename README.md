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
| `foundation` | VPC, subnets, NAT/IGW, EKS, KMS, OIDC, managed node group, bastion, VPC endpoints | `foundation/<env>/terraform.tfstate` |
| `workload`   | Cluster add-ons — today the AWS Load Balancer Controller (IRSA + Helm)            | `workload/<env>/terraform.tfstate`   |

The `workload` layer reads `foundation` outputs through `terraform_remote_state`,
so **`foundation` is always applied first**.

## Prerequisites

- Terraform `~> 1.10`
- AWS CLI configured
- An S3 bucket for state (see `environments/<env>/backend.hcl`)

## Usage

Each layer uses a partial backend: `bucket`/`key`/`region` come from
`environments/<env>/backend.hcl`.

```bash
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

```bash
aws ssm start-session --target <bastion_instance_id>
# inside the session: kubectl/helm are already configured via user_data
kubectl get nodes
```

## CI/CD (GitHub Actions)

| Workflow               | Trigger                                        | What it does                                                                       |
|------------------------|------------------------------------------------|------------------------------------------------------------------------------------|
| `terraform-plan.yml`   | PR to `develop`/`main`, plus `workflow_dispatch` | `fmt` + `validate` + `plan` (matrix over `foundation`/`workload`); comments the plan on the PR |
| `terraform-deploy.yml` | `workflow_dispatch` (choose env and layer)     | `plan -out` + `apply` of the saved plan; `prod` requires reviewer approval         |

- AWS authentication via **OIDC** (no static keys).
- Environment inferred from the base branch (`main` → prod, otherwise → hml) or chosen on dispatch.
- `prod` is protected by a GitHub Environment (required reviewer).

## Repository layout

```
foundation/
  main.tf  provider.tf  variables.tf  backend.tf  outputs.tf  README.md
  environments/{hml,prod}/{terraform.tfvars,backend.hcl}
  modules/{network,cluster,managed-node-group,bastion,vpc-endpoints}/
workload/
  main.tf  provider.tf  variables.tf  backend.tf  README.md
  environments/{hml,prod}/{terraform.tfvars,backend.hcl}
  modules/aws-load-balancer-controller/
ARCHITECTURE.md
```
