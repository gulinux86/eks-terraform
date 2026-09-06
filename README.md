# eks-terraform

A private Amazon EKS platform built with Terraform, handed over to Argo CD.

Terraform provisions the network, the cluster and the AWS-side plumbing, then stops
at a deliberate boundary: two Argo CD `AppProject`s and a single root `Application`.
Everything above that arrives from
[`platform-gitops`](https://github.com/gulinux86/platform-gitops) — Istio in ambient
mode, cert-manager, Gateway API, Karpenter.

`ARCHITECTURE.md` records every design decision and what it costs. Read the relevant
section before changing a security-shaped default.

## At a glance

```
bootstrap/    S3 state bucket (KMS) + GitHub OIDC roles          local state, run once
foundation/   VPC · EKS · KMS · system node group · bastion      ─┐
              VPC endpoints · core add-ons · Karpenter IAM        │ remote_state
workload/     ALB controller · platform ingress ALB · storage    ←┘
              Argo CD + the handover
                        │
                        ▼
platform-gitops         Gateway API · cert-manager · Istio ambient · Karpenter
```

**Properties worth knowing:**

- **Nothing is internet-facing.** Compute is private, the ingress ALB is `internal`,
  and the bastion has no public IP — access is SSM Session Manager only.
- **The ingress edge belongs to Terraform**, not to a controller reacting to a
  manifest. That is what makes the teardown ordered rather than hopeful
  (ARCHITECTURE.md §3, §11).
- **Capacity is on demand.** A managed node group hosts the controllers; Karpenter
  provisions everything else and consolidates it away when idle.
- **Two IAM roles**, split on read/write. A pull-request plan cannot mutate AWS.

## Layers

| Layer | Responsibility | State |
|---|---|---|
| `bootstrap` | Once per account: KMS-encrypted state bucket + OIDC roles | local, **not** committed |
| `foundation` | VPC, subnets, NAT/IGW, EKS, KMS, OIDC, system node group, bastion, VPC endpoints, core add-ons, Karpenter's AWS prerequisites | `foundation/<env>/terraform.tfstate` |
| `workload` | ALB controller, the platform ingress ALB, default StorageClass, Argo CD and the handover | `workload/<env>/terraform.tfstate` |

`workload` reads `foundation` outputs through `terraform_remote_state`, so
**`foundation` always applies first**. `foundation/outputs.tf` is that contract;
`scripts/check-layer-contract.sh` guards it in CI. Kubernetes version and the add-on
pins are set per environment in `environments/<env>/terraform.tfvars` — **bump them
together**.

## Usage

Requires Terraform `~> 1.10` and AWS credentials. Each layer uses a partial backend:
`bucket`/`key`/`region` come from `environments/<env>/backend.hcl`.

```bash
# once per account — creates the state bucket the other layers use
terraform -chdir=bootstrap init && terraform -chdir=bootstrap apply

# then, per environment
terraform -chdir=foundation init  -backend-config=environments/hml/backend.hcl
terraform -chdir=foundation apply -var-file=environments/hml/terraform.tfvars

terraform -chdir=workload   init  -backend-config=environments/hml/backend.hcl
terraform -chdir=workload   apply -var-file=environments/hml/terraform.tfvars
```

Credential-free checks — what CI runs on pull requests:

```bash
terraform -chdir=foundation fmt -recursive
terraform -chdir=foundation init -backend=false && terraform -chdir=foundation validate
./scripts/check-layer-contract.sh
trivy config --severity HIGH,CRITICAL --ignorefile .trivyignore .

# module tests: mocked providers, command = plan — no AWS, no infrastructure
terraform -chdir=foundation/modules/network init -backend=false
terraform -chdir=foundation/modules/network test
```

### Tearing down

**Use `terraform-destroy.yml`, not a local `terraform destroy`.** Controllers inside
the cluster create AWS resources Terraform never records, and those hold subnets
after the cluster is gone. The workflow handles it in order: it freezes Argo CD's
automation, drains Karpenter's NodePools while the controller is still alive,
terminates anything that survives, checks the VPC, and then destroys in three passes
with a sweep between each. A local destroy runs none of that. ARCHITECTURE.md §11 has
the reasoning and the failures that produced it.

### Cluster access

The `hml` API endpoint is public (CIDR-gated), so from a machine with an Access
Entry:

```bash
aws eks update-kubeconfig --region us-east-1 --name eks-hml-cluster
```

Otherwise, through the bastion — no SSH, no public IP, `kubectl` already installed:

```bash
aws ssm start-session --target "$(terraform -chdir=foundation output -raw bastion_instance_id)"
```

Argo CD is not exposed:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d          # then https://localhost:8080
```

## CI/CD

| Workflow | Trigger | What it does |
|---|---|---|
| `terraform-plan` | PR, dispatch | `fmt`, `validate`, `plan` per layer; comments the plan on the PR |
| `terraform-test` | PR, dispatch | `terraform test` on critical modules — mocked providers, no credentials |
| `security-scan` | PR, dispatch | Trivy IaC scan; fails on HIGH/CRITICAL, uploads SARIF |
| `terraform-deploy` | dispatch (env + layer) | Gated on tests + Trivy, then `plan -out` → `apply tfplan` |
| `terraform-destroy` | dispatch (env + layer + typed confirm) | Ordered teardown — see §11 |

Deploys are never automatic on merge. `master` is the single deploy source; the
environment is chosen at dispatch and pull-request plans always resolve to `hml`.

**Two roles, split on what the job does.** A pull request runs the workflow file from
its own branch, so the job that only reads must never hold a credential that writes:

| Role | Trusted claim | Permission |
|---|---|---|
| `…-eks-plan` | `:pull_request`, `:ref:refs/heads/*` | read-only (+ `kms:Decrypt` on the state key) |
| `…-eks-deploy` | `:environment:<env>` only | write |

GitHub stamps `environment:<name>` only for a job declaring an Environment — which
the two write workflows do and the plan workflow does not. **The Environment's
deployment-branch policy is load-bearing:** restricted to `master`, GitHub refuses
any other branch's job before a token is issued. Without it a pull request could
declare `environment: hml` and mint the deploy claim itself.

| Environment | Branches | Reviewer |
|---|---|---|
| `hml` | `master` | none |
| `prod` | `master` | required, self-review allowed (single maintainer — see §9) |

Required secrets per account: `<ENV>_PLAN_ROLE_ARN`, `<ENV>_DEPLOY_ROLE_ARN`.

## Repository layout

```
bootstrap/     main.tf  s3-state.tf  outputs.tf  variables.tf
foundation/    main.tf  outputs.tf  variables.tf  backend.tf  provider.tf
               environments/{hml,prod}/{terraform.tfvars,backend.hcl}
               modules/{network,cluster,managed-node-group,bastion,
                        vpc-endpoints,eks-addons,karpenter}/
workload/      same shape
               modules/{aws-load-balancer-controller,platform-ingress,
                        storage,argocd,argocd-bootstrap}/
scripts/       check-layer-contract.sh
.github/       plan · test · security-scan · deploy · destroy
.trivyignore   documented, accepted exceptions — each needs a written reason
ARCHITECTURE.md
```

Module `README.md`s are terraform-docs output under a handwritten title —
regenerate rather than hand-editing the tables. Test suites live in
`<module>/tests/*.tftest.hcl`; adding one means adding the module path to the matrix
in **both** `terraform-test.yml` and the `test` job of `terraform-deploy.yml`.
