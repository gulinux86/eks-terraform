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
bootstrap/   state bucket (KMS) + GitHub OIDC roles       run once per account
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
| `bootstrap` | State bucket, OIDC roles | local, not committed |
| `foundation` | VPC, EKS, KMS, system node group, bastion, endpoints, core add-ons, Karpenter's AWS prerequisites | `foundation/<env>/terraform.tfstate` |
| `workload` | ALB controller, ingress ALB, StorageClass, Argo CD, the handover | `workload/<env>/terraform.tfstate` |

`workload` reads `foundation` outputs, so **`foundation` applies first**.
`foundation/outputs.tf` is that contract — `scripts/check-layer-contract.sh` guards it
in CI. Kubernetes version and add-on pins live in
`environments/<env>/terraform.tfvars`; **bump them together**.

## Usage

Terraform `~> 1.10`. Each layer uses a partial backend from
`environments/<env>/backend.hcl`.

```bash
terraform -chdir=bootstrap init && terraform -chdir=bootstrap apply   # once per account

terraform -chdir=foundation init  -backend-config=environments/hml/backend.hcl
terraform -chdir=foundation apply -var-file=environments/hml/terraform.tfvars

terraform -chdir=workload   init  -backend-config=environments/hml/backend.hcl
terraform -chdir=workload   apply -var-file=environments/hml/terraform.tfvars
```

Credential-free checks, the same ones CI runs:

```bash
terraform -chdir=foundation fmt -recursive
terraform -chdir=foundation init -backend=false && terraform -chdir=foundation validate
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

Argo CD is not exposed — `kubectl -n argocd port-forward svc/argocd-server 8080:443`,
password in the `argocd-initial-admin-secret`.

## CI/CD

| Workflow | Trigger | What it does |
|---|---|---|
| `terraform-plan` | PR, dispatch | `fmt`, `validate`, `plan` per layer; comments on the PR |
| `terraform-test` | PR, dispatch | `terraform test` on critical modules — mocked, no credentials |
| `security-scan` | PR, dispatch | Trivy IaC scan; fails on HIGH/CRITICAL |
| `terraform-deploy` | dispatch (env + layer) | Gated on tests + Trivy, then `plan -out` → `apply tfplan` |
| `terraform-destroy` | dispatch (env + layer + typed confirm) | Ordered teardown (§11) |

Deploys are never automatic on merge. `master` is the single deploy source;
pull-request plans always resolve to `hml`.

Two roles: the plan role is read-only and trusted for `:pull_request`; the deploy role
is write and trusted **only** for `:environment:<env>`. GitHub stamps that claim only
for a job declaring an Environment, and the Environment's branch policy (`master`
only) is what stops a branch minting it for itself. See §9.

Secrets per account: `<ENV>_PLAN_ROLE_ARN`, `<ENV>_DEPLOY_ROLE_ARN`.

## Layout

```
bootstrap/     state bucket + OIDC roles
foundation/    main.tf outputs.tf variables.tf backend.tf provider.tf
               environments/{hml,prod}/{terraform.tfvars,backend.hcl}
               modules/{network,cluster,managed-node-group,bastion,
                        vpc-endpoints,eks-addons,karpenter}/
workload/      same shape
               modules/{aws-load-balancer-controller,platform-ingress,
                        storage,argocd,argocd-bootstrap}/
scripts/       check-layer-contract.sh
.github/       plan · test · security-scan · deploy · destroy
.trivyignore   accepted exceptions — each needs a written reason
```

Module `README.md`s are terraform-docs output under a handwritten title; regenerate
rather than hand-editing. Adding a test suite means adding the module path to the
matrix in **both** `terraform-test.yml` and the `test` job of `terraform-deploy.yml`.
