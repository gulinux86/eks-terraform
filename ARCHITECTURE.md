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
  authenticator, controllerManager, scheduler), written to a **Terraform-managed
  log group with a 90-day retention**.
  - **Trade-off:** full audit logging has a CloudWatch cost; it's on because
    observability/forensics is a Senior+ expectation.
  - **Why the log group is declared here.** EKS writes to
    `/aws/eks/<cluster>/cluster` and, if that group does not exist, creates it
    itself with **no expiry** — and Terraform cannot set retention on a group it
    does not own. So the group is created first, with the exact name, and the
    cluster depends on it explicitly (the cluster resource does not reference it,
    so there is no ordering for Terraform to infer). The choice is 90 days: a
    forensic window that still bounds cost. The real alternative was never "some
    other number", it was an accidental infinity.
  - **Hazard:** if a cluster previously existed in the account, the log group
    outlived it and the apply fails with `ResourceAlreadyExistsException`. Remedy
    is `terraform import` — deleting the group would discard audit history.
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
  - **Instance `Name` tags come from the ASG, not the node group.** Tags set on
    `aws_eks_node_group` land on the node group; EKS tags the instances only with
    `eks:cluster-name` / `eks:nodegroup-name`, so they appear unnamed in the
    console. An `aws_autoscaling_group_tag` with `propagate_at_launch` supplies the
    name. The alternative — a custom launch template with `tag_specifications` —
    tags instances immediately instead of on next launch, but means owning a launch
    template whose version changes can cascade into node replacement. Not worth
    that for a console label; revisit if a launch template is ever needed on its
    own merits (custom kubelet args, a private AMI). Consequence: nodes already
    running stay unnamed until replaced.

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
  The role carries a read grant scoped to that one bucket — it was missing
  originally, so the boot script failed with `AccessDenied` and, because the
  failure was swallowed by a bare `if`, kubectl was simply absent with nothing in
  the log explaining why. The script now logs every failure path, and
  `user_data_replace_on_change` forces a new instance whenever the script changes:
  boot scripts only run once, so without it the code and the running host drift
  apart silently.
  Helm is intentionally absent — Helm releases are managed by the `workload`
  layer's provider (see §7), not imperatively on a host.
- **Dual authorization model, deliberately separated:**
  - `eks:DescribeCluster` (IAM) so `aws eks update-kubeconfig` works — this is an
    AWS-API permission.
  - An **EKS Access Entry** + `AmazonEKSClusterAdminPolicy` for in-cluster RBAC.
  - These are two different planes; granting one without the other is a common
    mistake (RBAC without `DescribeCluster` silently breaks kubeconfig setup).
  - **The same split explains the console.** An account administrator sees the
    cluster in the EKS console but gets `Unauthorized` on the **Resources** tab,
    because listing Kubernetes objects goes through RBAC, not IAM. Provider v6 does
    not bootstrap the creator either (`bootstrap_cluster_creator_admin_permissions`
    defaults to false), so *nobody* has in-cluster access unless an Access Entry
    says so. In `hml` the operator's console identity is listed in
    `cluster_admin_role_arns` to make that tab usable. It grants no capability the
    principal lacked — it already holds `AdministratorAccess` and could add the
    entry by hand — but it records the grant in code instead of a click that
    disappears on the next rebuild.
  - **The account root is also listed in hml**, because that is the identity
    actually signed into the console: `terra-admin` holds access keys but has no
    console login. EKS **does** accept `arn:aws:iam::<account>:root` as an
    access-entry principal — verified against the API rather than assumed, after an
    earlier reading of the docs suggested otherwise. The input validation was
    widened to match reality.
  - **Not for prod — neither of them.** A human IAM user with standing
    cluster-admin is an audit finding waiting to happen, and root is worse: it
    cannot be scoped, cannot be restricted by IAM policy, and cannot be attributed
    to a person, so every action it takes is logged as "the account". In hml that
    trade is acceptable — the environment is destroyed between sessions and holds
    nothing real. Production should grant a **role assumed for a session** and give
    the operator a console login of their own with MFA. See §11.
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

- **Argo CD (chart `10.4.0`, Argo CD `v3.5.1`)** — installed by the Helm provider,
  last in the `workload` layer.
  - **Why Terraform installs this one thing and then stops.** Terraform is a poor
    tool for *custom resources*: `kubernetes_manifest` needs a CRD's schema at
    **plan** time, and on a first apply the CRD does not exist yet. Helm hands
    manifests to the cluster at apply time and never asks Terraform to understand
    them. So Terraform installs Argo CD — which brings the three CRDs and their
    controllers — and from there custom resources are delivered through Argo CD
    rather than through Terraform. That is what unblocks Karpenter `NodePool`s and
    Argo Rollouts later, without fighting the plan-time schema problem.
  - **Installed bare, on purpose.** No root `Application`, no app-of-apps, no
    repository wired up, no ingress, no exposed UI (`ClusterIP` + port-forward).
    Each of those is a decision with its own consequences — repository credentials
    need a source, an exposed UI needs TLS and an auth story.
  - **The ALB Controller was not migrated.** It stays a Terraform-owned
    `helm_release`. Two owners for one resource is the anti-pattern; moving it to
    Argo CD is its own reviewed change, not a side effect of this one.
  - **Sizing is a hard constraint, not a preference.** The VPC CNI caps pods per
    node by ENI capacity: a `t3.small` allows **11**. Six are already taken by the
    cluster's own components and the ALB Controller, and Argo CD needs **7**
    (verified by rendering the chart, not estimated). Hence `desired_size = 2` in
    hml. HA mode stays off — `redis-ha` alone is three more pods.
  - **Sharp edge on upgrades:** Helm 3 does not upgrade CRDs on `helm upgrade`. A
    chart bump that changes a CRD needs it applied out of band. `crds.keep = true`
    so uninstalling the release never cascade-deletes live `Application` objects.

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
- **Two roles, split on the read/write boundary.** GitHub stamps a `sub` claim
  describing how a run was triggered; the trust policies split on it:

  | Claim | Role | Permission |
  |---|---|---|
  | `:pull_request`, `:ref:refs/heads/*` | `…-eks-plan` | read-only + `kms:Decrypt` on the state key |
  | `:environment:<env>` | `…-eks-deploy` | write |

  - **Why it matters.** A pull request runs the workflow file *from its own
    branch*. With one shared role — the previous design, trusting `repo:<repo>:*`
    — the plan job carried a credential that could delete the account, reachable
    without passing the deploy approval at all. The split removes the strong
    credential from that path.
  - **The Environment branch policy is part of the mechanism, not hygiene.** The
    `environment:<name>` claim is minted for any job that declares an Environment,
    and a pull request can add that line. Restricting each Environment to `master`
    makes GitHub refuse such a job before it starts, so the claim is never issued.
    This control lives in repository settings, so no `terraform test` or Trivy rule
    can assert it — it is verified by an explicit negative test at cutover.
  - **Authorization sits outside the pipeline.** An actor allowlist or token check
    written as a workflow step runs *after* the credential exists, and is editable
    by exactly the people it constrains. The gate must sit outside the thing it
    guards.
  - **The plan role holds no cluster access.** Reaching the Kubernetes API is
    granted by an EKS Access Entry, separately from IAM. The plan role has none, so
    the `workload` plan runs with `-refresh=false` and never contacts the cluster.
    Trade-off: drift in the two in-cluster resources (`helm_release`,
    `kubernetes_service_account`) does not surface in a PR plan; the deploy path's
    own refresh catches it before anything is applied. Registering the plan role
    read-only was rejected — Kubernetes' `view` role excludes Secrets, where Helm
    keeps release metadata, and the next policy up permits mutation.
  - **Known gap:** the deploy role still carries `AdministratorAccess`. Sizing a
    custom policy for EKS is iterative, and was deferred rather than stall the part
    that removes the exposure. See §11.
  - **Known gap:** a `prod` reviewer approves *before* the job starts, so they
    approve without seeing the plan. Splitting deploy into plan → approve → apply
    would fix it; not done here.
- `terraform-plan`: `fmt` + `validate` + `plan` on PRs (matrix over both layers),
  posting the plan as a PR comment. The `workload` plan is skipped when
  `foundation` has no outputs yet (greenfield/torn-down).
- `terraform-test`: native `terraform test` on the critical modules. Mocked
  providers + `command = plan` mean **no AWS credentials and no real infra** —
  so it runs on PRs from any branch/fork. Guards security-critical invariants
  (subnet LB tagging, private endpoint, auth mode, secrets encryption, admin
  access entries).
- `contract`: guards the **`foundation` → `workload` output contract**. The workload
  layer reads seven foundation outputs through `terraform_remote_state`, a link that
  exists only at run time — renaming or deleting one passes `fmt`, `validate`, every
  module suite and Trivy, and fails during a `workload` apply. The check compares the
  outputs referenced under `workload/` against those declared in
  `foundation/outputs.tf`; no credentials, no providers, no state
  (`scripts/check-layer-contract.sh`, also a pre-apply gate in `terraform-deploy`).
  - **What it does not catch:** names only. An output that keeps its name and
    changes meaning or type still passes. Guarding that would mean a typed interface
    between the layers, not a name check — stated so the guard is not mistaken for
    more than it is.
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
| CI deploy role | Split from the plan role; `AdministratorAccess` | Custom policy sized to the managed services + permission boundary |
| Human cluster access | hml lists an IAM **user** and the **account root** as cluster-admin so the console works | A role assumed for a session; operator console login with MFA; no root in daily use and no standing cluster-admin on a long-lived principal |
| Prod approval | Reviewer approves before the job starts | Split deploy into plan → approve-with-plan → apply |
```
