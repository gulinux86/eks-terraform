# Architecture

This document describes the design of the EKS platform provisioned by this
repository and, more importantly, the **trade-offs** behind each decision. The
goal is a production-shaped, security-conscious cluster that still fits a
portfolio/demo budget.

## 1. High-level topology

```
                              AWS Account / Region (us-east-1)
┌──────────────────────────────────────────────────────────────────────────────┐
│  VPC  10.0.0.0/16 (hml)  /  10.1.0.0/16 (prod)                                 │
│                                                                                │
│   ┌── Public subnets (1a, 1b) ──────────┐   ┌── Private subnets (1a, 1b) ───┐  │
│   │  Internet Gateway                   │   │  EKS control-plane ENIs       │  │
│   │  NAT GW 1a   NAT GW 1b   (1 EIP ea) │   │  Managed node group (AL2023)  │  │
│   │  role: host NAT only (no role/elb)  │   │  Bastion (no public IP)       │  │
│   └─────────────────────────────────────┘   │  VPC interface endpoints       │  │
│            │ egress                          │  S3 gateway endpoint           │  │
│            ▼                                 └────────────────────────────────┘  │
│        Internet                                       ▲                          │
│                                          private DNS  │ 443                       │
│   EKS API endpoint: private + public (CIDR-restrictable)                          │
└──────────────────────────────────────────────────────────────────────────────┘

State (S3, native locking):
  foundation/<env>/terraform.tfstate   ──remote_state──▶   workload/<env>/terraform.tfstate
```

## 2. Two-layer split (`foundation` + `workload`)

`foundation` owns long-lived infrastructure (VPC, EKS, KMS, OIDC, nodes,
bastion, endpoints). `workload` owns in-cluster add-ons (today: the AWS Load
Balancer Controller via Helm + IRSA). `workload` reads `foundation` outputs
through `terraform_remote_state`.

**Why split:**
- **Blast radius / state size.** Add-ons change often; the network and control
  plane rarely do. Separate states mean a bad `workload` apply can never corrupt
  or lock the `foundation` state.
- **Provider boundary.** The `kubernetes`/`helm` providers only exist in
  `workload`. Keeping them out of `foundation` avoids the classic
  "provider configured from a resource created in the same apply" chicken-and-egg
  problem.
- **Lifecycle independence.** You can re-run add-ons without planning the whole
  platform.

**Trade-offs / cost:**
- Cross-layer values travel via `terraform_remote_state`, which couples
  `workload` to `foundation`'s output contract and to its state location.
- Ordering is manual: `foundation` must apply before `workload` (encoded in the
  deploy workflow's `both` path).
- **Alternative considered:** a single state. Simpler wiring, but reintroduces
  the provider bootstrap problem and a larger blast radius. Rejected.

## 3. Networking

- **2 AZs, public + private subnets.** Public subnets host only NAT and the IGW
  route; all compute is private.
- **One NAT Gateway per AZ.** AZ-resilient egress.
  - **Trade-off:** two NAT GWs ≈ 2× the hourly + data cost of a single shared
    NAT. A single NAT is cheaper but becomes an AZ-level SPOF for egress. For a
    portfolio that wants to *show* HA intent, per-AZ NAT is the honest choice;
    for pure cost demos, collapse to one.
- **Subnet tagging.** Private subnets carry `kubernetes.io/role/internal-elb`.
  Public subnets deliberately **omit** `kubernetes.io/role/elb`, so the ALB
  controller cannot accidentally place internet-facing LBs there — load balancers
  are internal by default.
- **VPC endpoints (PrivateLink + S3 gateway).** ECR, STS, EC2, EKS, KMS, ELB,
  autoscaling, logs and the SSM trio resolve to private IPs.
  - **Trade-off / redundancy:** NAT already provides full egress, so the
    interface endpoints overlap with it and add per-hour + per-GB PrivateLink
    cost. They are kept because (a) they keep AWS-API traffic on the AWS backbone
    and off the NAT, and (b) they are the migration path toward removing NAT
    entirely. If you drop NAT later, the endpoint list must be completed (e.g.
    nothing here covers arbitrary public registries).

## 4. EKS control plane

- **Private + public API endpoint.** Private access serves nodes and the bastion;
  public access (`endpoint_public_access`, default `true`, gated by
  `public_access_cidrs`) lets Terraform run from GitHub-hosted runners.
  - **Trade-off:** a fully private endpoint is more secure but unreachable from
    public CI runners — you'd need self-hosted runners in the VPC or a
    bastion/VPN apply path. Exposing the endpoint with a CIDR allowlist trades a
    little surface area for a dramatically simpler pipeline. Tighten
    `public_access_cidrs` in `prod`.
- **Secrets envelope encryption with KMS.** Customer-managed key with rotation;
  the cluster role gets a scoped `kms:*` policy on that key only.
- **Control-plane logging** enabled for all five log types (api, audit,
  authenticator, controllerManager, scheduler).
  - **Trade-off:** full audit logging has a CloudWatch cost; it's on because
    observability/forensics is a Senior+ expectation.
- **Authentication mode `API_AND_CONFIG_MAP`** so we can use modern **Access
  Entries** while remaining compatible with anything still reading the aws-auth
  ConfigMap.
- **Core add-ons managed as code (`vpc-cni`, `coredns`, `kube-proxy`).** Declared
  via `aws_eks_addon` (module `eks-addons`) with the version resolved for the
  cluster's Kubernetes version and `resolve_conflicts = OVERWRITE`.
  - **Why this matters (not cosmetic):** left self-managed, these add-ons stay at
    whatever version EKS shipped at cluster creation and are **invisible to the
    IaC**. During a control-plane upgrade they silently fall out of supported
    version skew — e.g. a `1.34`-era `kube-proxy`/`coredns` running under a `1.35`
    API server, surfacing as intermittent DNS/routing failures whose root cause is
    hard to trace. Managing them makes the version a reviewed part of the upgrade
    (the `1.34 → 1.35` bump in this repo updates them in the same change).
  - **Deferred (production-hardening, intentionally not built for a 1–2 node
    demo):** dedicated VPC-CNI IRSA role, native network policy
    (`ENABLE_NETWORK_POLICY`), prefix delegation, and the EBS-CSI / metrics-server
    add-ons — added when a workload actually needs them (see §11).

## 5. Compute — managed node group

- **EKS-managed node group on AL2023.** AL2 is end-of-life; AL2023 is the current
  default and gets the security baseline for free.
- Sizing via variables (`desired/min/max`, `instance_types`), default
  `t3.medium`, 1–4 nodes.
  - **Trade-off:** managed node groups are simpler and AWS-maintained but less
    flexible than self-managed ASGs or Karpenter. For a platform baseline,
    simplicity wins; Karpenter would be the next step for real workload scaling.

## 6. Access — bastion + SSM

- **Bastion in a private subnet, no public IP, no inbound SSH.** Access is only
  through **SSM Session Manager**; IMDSv2 is required and the root volume is
  encrypted.
- **Least-privilege egress (no `0.0.0.0/0`).** The SG allows only: HTTPS to the
  VPC CIDR (the `ssm`/`ssmmessages`/`ec2messages` interface endpoints and the
  private EKS API resolve to in-VPC IPs), DNS to the VPC resolver, and HTTPS to
  the **S3 managed prefix list** (the S3 gateway endpoint). SSM works entirely
  over PrivateLink — the bastion never needs internet.
- **Tooling without internet.** `kubectl` is fetched from the Amazon-EKS S3
  bucket through the gateway endpoint (build date auto-discovered, no `curl`).
  Helm is intentionally absent — Helm releases are managed by the `workload`
  layer's provider (see §7), not imperatively on a host.
- **Dual authorization model, deliberately separated:**
  - `eks:DescribeCluster` (IAM) so `aws eks update-kubeconfig` works — this is an
    AWS-API permission.
  - An **EKS Access Entry** + `AmazonEKSClusterAdminPolicy` for in-cluster RBAC.
  - These are two different planes; granting one without the other is a common
    mistake (RBAC without `DescribeCluster` silently breaks kubeconfig setup).
- **Trade-off:** the bastion is an extra always-on `t3.micro` and an operational
  hop. The benefit is zero inbound exposure, no internet egress, and full Session
  Manager audit logging vs. an SSH bastion with a public IP and key management.

## 7. Add-ons — AWS Load Balancer Controller (IRSA)

- **IRSA, not node-role permissions.** A dedicated IAM role trusts the cluster
  OIDC provider for exactly
  `system:serviceaccount:kube-system:aws-load-balancer-controller`. The pod gets
  only the controller's policy — least privilege, no shared node credentials.
- Helm installs the chart against a **pre-created** service account (so the IRSA
  annotation is guaranteed present before the controller starts), with `region`
  and `vpcId` set explicitly rather than relying on IMDS auto-discovery.
  - **Trade-off:** pinning chart `1.6.2` and provider versions favors
    reproducibility over always-latest; bump deliberately.

## 8. State & backend

- **S3 backend with native locking** (`use_lockfile`, Terraform ≥ 1.10) — no
  DynamoDB table to manage.
- **State bucket encrypted with a customer-managed KMS key** (rotated, created in
  `bootstrap`), not the AWS-managed SSE-S3 key. State can hold sensitive values,
  so we want key-policy control and an audit trail on decryption.
  - **Operational note:** every principal that runs Terraform (the CI deploy
    roles and any human) needs `kms:Decrypt` / `kms:GenerateDataKey` on this key,
    otherwise state reads/writes fail.
- **Partial backend config**: `bucket/key/region` come from
  `environments/<env>/backend.hcl`, so the same code serves `hml` and `prod`.
- `.terraform.lock.hcl` is committed for reproducible provider resolution; the
  non-sensitive per-environment `*.tfvars` are committed (others remain ignored).

## 9. CI/CD (GitHub Actions)

- **OIDC to AWS** — no long-lived access keys in GitHub. All actions are pinned
  to a commit SHA and run on Node 24 runtimes.
- `terraform-plan`: `fmt` + `validate` + `plan` on PRs (matrix over both layers),
  posting the plan as a PR comment. The `workload` plan is skipped when
  `foundation` has no outputs yet (greenfield/torn-down).
- `terraform-test`: native `terraform test` on the critical modules. Mocked
  providers + `command = plan` mean **no AWS credentials and no real infra** —
  so it runs on PRs from any branch/fork. Guards security-critical invariants
  (subnet LB tagging, private endpoint, auth mode, secrets encryption, admin
  access entries).
- `security-scan`: **Trivy** IaC scan in `config` mode. Uploads SARIF to the
  Security tab and fails the build on HIGH/CRITICAL; reviewed exceptions live in
  `.trivyignore`.
- `terraform-deploy`: manual `workflow_dispatch`. **Gated** — the `terraform test`
  and Trivy jobs must pass before the apply job runs (and, for prod, before the
  reviewer is even asked). Then applies a **saved plan** (`plan -out` then
  `apply tfplan`) so apply never re-plans; `both` applies `foundation` before
  `workload`.
- `terraform-destroy`: manual `workflow_dispatch` with a typed confirmation;
  destroys `workload` **before** `foundation` for `both` (reverse of apply).

**Defense in depth.** The test + scan gates run twice on purpose: as a **PR gate**
(reported on the merge) and again as a **pre-apply gate** inside `terraform-deploy`
(blocking the apply). Both are environment-agnostic, so `hml` and `prod` get the
identical checks. The PR checks can optionally be promoted to **required status
checks** on `master` (branch protection) to hard-block merges on failure.

- **Trade-off:** deploys are intentionally manual rather than auto-apply-on-merge
  — safer for infra, at the cost of one human action per release.

## 10. Environments

`hml` and `prod` are isolated by distinct VPC CIDRs (`10.0/16` vs `10.1/16`),
distinct state keys, and distinct AWS roles selected in CI. Production should
additionally narrow `public_access_cidrs` from the default `0.0.0.0/0`.

## 11. Known trade-offs to revisit for true production

| Area | Current (portfolio) | Production-hardening step |
|------|---------------------|---------------------------|
| API endpoint | Public + CIDR allowlist | Private-only + in-VPC runners / VPN |
| `public_access_cidrs` | `0.0.0.0/0` default | Office/CI egress ranges only |
| Egress | NAT + overlapping endpoints | Drop NAT, complete endpoint set |
| Scaling | Fixed managed node group | Karpenter (+ small system node group) |
| Core add-ons | vpc-cni/coredns/kube-proxy managed + pinned | + dedicated VPC-CNI IRSA, network policy, prefix delegation |
| Cluster add-ons | ALB controller (IRSA + Helm) | + External Secrets, cert-manager, ExternalDNS, EBS-CSI, metrics-server, policy agents |
| State bucket | Single shared bucket (KMS CMK) | Per-account/per-env buckets + bucket policies |
```
