# Architecture

Design decisions and what each one costs. Section numbers are referenced from code
comments (`see ARCHITECTURE.md §N`) and are stable.

## 1. Topology

```
                     AWS account · us-east-1
┌──────────────────────────────────────────────────────────┐
│ VPC  10.0.0.0/16 (hml) · 10.1.0.0/16 (prod)              │
│                                                          │
│  public 1a/1b               private 1a/1b                │
│  ├ Internet Gateway         ├ EKS control-plane ENIs     │
│  └ NAT per AZ ──egress──▶   ├ System node group          │
│                             ├ Karpenter nodes            │
│                             ├ Bastion (SSM only)         │
│                             ├ Platform ALB (internal)    │
│                             └ VPC endpoints + S3 gateway │
└──────────────────────────────────────────────────────────┘

bootstrap → state bucket + OIDC roles          local state
foundation → network, cluster, nodes, bastion  ─┐ remote_state
workload   → add-ons, ingress ALB, Argo CD     ←┘
                    └─ handover ─▶ platform-gitops
```

## 2. Two-layer split

`foundation` owns long-lived infrastructure; `workload` owns in-cluster add-ons and
hands the cluster to Argo CD.

- **Provider boundary.** `kubernetes` and `helm` exist only in `workload`. One state
  would configure them from a resource created in the same apply — a bootstrap
  deadlock.
- **Blast radius.** A bad `workload` apply cannot corrupt or lock `foundation` state.
- **Cost.** `foundation/outputs.tf` is an API: renaming an output passes every static
  check and fails at run time in the other layer. `scripts/check-layer-contract.sh`
  compares the two lists in CI. Ordering is manual.

## 3. Networking

- **2 AZs, all compute private.** Public subnets host only NAT and the IGW route.
- **NAT per AZ** — ~2× the cost of a shared NAT, against an AZ-level egress SPOF.
- **VPC endpoints** keep AWS-API traffic off NAT and are the path to removing it.
  They overlap with NAT today, so they are redundant cost until that happens.
- **The ingress ALB belongs to Terraform** (`workload/modules/platform-ingress`); the
  cluster attaches via a `TargetGroupBinding` that registers pod IPs and owns nothing.
  - A load balancer created from inside the cluster never enters state, so `destroy`
    has no edge from it to the subnets it occupies (§11).
  - The internet-facing guard is now the absence of `internal = false` in reviewed
    HCL, not the absence of a subnet tag anyone could add.
  - **Cost:** a new edge is a Terraform change. Right for one shared gateway, wrong
    for per-team edges.
  - **Coupling:** `workload` must know the Service name istiod generates for the
    `Gateway` — the one contract pointing outward. A mismatch is silent: empty target
    group, ALB answers 503.

## 4. EKS control plane

- **Private + public API endpoint**, CIDR-gated. A private-only endpoint needs
  self-hosted runners; the allowlist buys a far simpler pipeline. Tighten in prod.
- **Secrets encrypted** with a rotated customer-managed KMS key.
- **All five log types**, to a Terraform-managed group with 90-day retention. Declared
  explicitly because EKS otherwise creates it with **no expiry** and Terraform cannot
  set retention on a group it does not own.
  - **Hazard:** a group outliving a previous cluster fails the apply. Remedy is
    `terraform import`; deleting it discards audit history.
- **`API_AND_CONFIG_MAP` auth**, so Access Entries work alongside aws-auth readers.
- **Core add-ons as code**, versions pinned per environment. Left self-managed they
  fall out of supported version skew during an upgrade — intermittent DNS and routing
  failures that are hard to trace. **Bump the cluster version and the pins together.**
  - `metrics-server` and the EBS CSI driver close gaps that fail *silently*: no HPA
    without one, every PVC `Pending` forever without the other.

## 5. Compute — system pool + Karpenter

- **A managed node group is the system pool and stays.** Karpenter runs in pods and
  cannot host itself. Its size was chosen for Argo CD's pod count against the VPC
  CNI's ENI ceiling, never re-measured (§12).
- **Karpenter provisions the rest**, delivered by Argo CD. Terraform provides only
  what Kubernetes cannot create for itself:

  | Piece | Why it is not optional |
  |---|---|
  | Access Entry of type **`EC2_LINUX`** | A role gets an instance into the account; joining the cluster needs this, and `STANDARD` does not work. Without it nodes boot, look healthy in EC2, and never register — with no error. |
  | `karpenter.sh/discovery` tags on subnets and the cluster SG | Karpenter finds where to launch by tag. An unmatched selector provisions nothing and says only that nothing matched. |
  | SQS interruption queue + EventBridge | Karpenter works without it — the gap appears only during a Spot reclaim, when the node vanishes instead of draining. |
  | Pod Identity, not IRSA | The chart comes from a public repository; IRSA would need the role ARN in a values file. Requires the `eks-pod-identity-agent` add-on, or the association silently delivers no credentials. |

- **Blast radius is bounded in IAM, not in configuration.** `iam:PassRole` names one
  role and is conditioned on `iam:PassedToService`; `TerminateInstances` requires
  **both** `kubernetes.io/cluster/<name>=owned` and `karpenter.sh/nodepool` — the
  first alone would reach the system pool, which carries the same tag.
- **`karpenter.sh/` is a reserved tag prefix.** Keys under it are dropped from an
  `EC2NodeClass`'s `tags` silently, so an instance never carries them. Guarded by
  `foundation/modules/karpenter/tests`.

## 6. Access — bastion + SSM

- **Private subnet, no public IP, no inbound SSH.** SSM Session Manager only; IMDSv2
  required, root volume encrypted.
- **Least-privilege egress, no `0.0.0.0/0`:** HTTPS to the VPC CIDR, DNS to the VPC
  resolver, HTTPS to the **in-region** S3 prefix list.
  - A gateway endpoint only routes to S3 in its own region. AWS's public `amazon-eks`
    bucket is in us-west-2, so that request matched no egress rule and **hung
    silently**. `kubectl` is copied to an in-region bucket by the pipeline instead.
- **A session needs no setup**, which required two mechanisms:
  - `/etc/kubeconfig` world-readable (it holds no secret — auth is `aws eks get-token`
    under the instance role). A user's home was impossible: `ssm-user` is created on
    *first session*.
  - `/etc/profile.d` is read only by **login** shells; Session Manager starts a plain
    `sh`. An `SSM-SessionManagerRunShell` document with `shellProfile = "bash -l"`
    fixes it. That document is **account-wide**.
- **Cluster access is an Access Entry, not an IAM permission.** `hml` grants
  cluster-admin to the CI deploy role, an IAM user and the account **root** — the last
  is the console identity, cannot be scoped or attributed, and is a prod gap (§12).

## 7. Add-ons — the workload layer

- **AWS Load Balancer Controller (IRSA + Helm).** It now only registers pod IPs and
  writes the security-group rules that reach them; it no longer creates load
  balancers (§3). Its policy is wider than that job (§12).
- **The `TargetGroupBinding` is applied by Terraform**, not Argo CD — its ARN and
  security-group id are account-specific and the GitOps repository is public.
- **A default `gp3` StorageClass.** Without one the CSI driver provisions nothing, and
  EKS's built-in `gp2` uses the in-tree provisioner removed in 1.27. `Delete` reclaim
  in hml, where a retained volume outlives `destroy` and bills silently.
- **Argo CD, installed and then left alone.** Terraform installs it and stops; from
  there custom resources arrive from Git, avoiding the plan-time CRD-schema problem.
- **The handover: two `AppProject`s and one root `Application`.** The projects are the
  privilege boundary and live in Terraform, because a boundary stored in the
  repository it governs can be widened by anyone who can commit there.
  - Chart repositories count as sources — listing only the Git repository fails every
    chart-based component.
  - **Sharp edge:** Helm 3 does not upgrade CRDs. `crds.keep = true` so uninstalling
    never cascade-deletes live `Application` objects.

## 8. State & backend

- **S3 with native locking** (`use_lockfile`, Terraform ≥ 1.10) — no DynamoDB table.
- **Rotated customer-managed KMS key**, not SSE-S3, for key-policy control and an
  audit trail. Every principal running Terraform needs `kms:Decrypt` and
  `kms:GenerateDataKey` on it.
- **Partial backend config**, so one codebase serves both environments.
- `bootstrap` keeps local state — a durability risk, and also why a broken trust
  policy is always recoverable.

## 9. CI/CD

- **OIDC, no static keys.** Actions pinned to commit SHAs.
- **Two roles, split on read/write.** A pull request runs the workflow file from its
  own branch, so the job that only reads must never hold a credential that writes.

  | Role | Trusted claim | Used by |
  |---|---|---|
  | plan (read-only) | `:pull_request`, `:ref:refs/heads/*` | `terraform-plan` |
  | deploy (write) | `:environment:<env>` only | `terraform-deploy`, `terraform-destroy` |

  GitHub stamps `environment:<name>` only for a job declaring an Environment. **The
  Environment's branch policy is load-bearing:** without it a pull request could
  declare the Environment and mint the deploy claim itself.
- **Deploys are never automatic on merge.** `workflow_dispatch`, gated on tests and
  Trivy, applying a saved plan.
- **The plan role holds no write permission at all**, including the state lock — hence
  `-lock=false`, and `-refresh=false` for `workload`, whose in-cluster resources would
  need an Access Entry it deliberately lacks.
- **Gates:** `fmt`, `validate`, the layer-contract check, module tests with mocked
  providers, and Trivy. Every `.trivyignore` entry needs a written reason and a
  pointer to the section that accepts the trade-off.

## 10. Environments

`hml` and `prod` are isolated by distinct VPC CIDRs, state keys and AWS roles. `hml`
is destroyed between sessions, which shapes several defaults — `Delete` reclaim, 24h
node expiry, a permissive API CIDR. Each is marked where it differs from prod.

## 11. Teardown

**Destroying this platform is not the reverse of applying it.** Controllers create AWS
resources Terraform never records, so `destroy` has no edge from them to the subnets
they occupy. The error names the subnet, never what holds it — after most of the
platform is gone.

Giving the ingress ALB to Terraform removed one source (§3). What remains cannot be:
**debris that does not exist until Terraform creates it.**

```
Terraform destroys      AWS leaves behind      which holds
──────────────────      ──────────────────     ───────────
system node group   →   VPC CNI interfaces →   the subnets
EKS cluster         →   eks-cluster-sg     →   the VPC
```

`terraform-destroy.yml` is ordered, not merely sequential:

| Step | Why here |
|---|---|
| Drain cluster-owned state | Freezes `syncPolicy.automated` first — `selfHeal` reads a deletion as an instruction to recreate. Deletes Karpenter `NodePool`s **before** the Applications, since deleting one is a request to Karpenter. Strips finalizers, which would hang the Helm uninstall. |
| Terminate Karpenter instances | Its own step, **not** gated on a live cluster — it works from AWS tags, and the case that matters is the one where the cluster is gone. On the normal path it finds nothing, which is the signal the ordering is right. |
| Destroy workload | Removes the ALB, which is why the preflight follows it. |
| Preflight | Fails in seconds on anything unowned, rather than as a `DependencyViolation` forty minutes in. |
| Destroy foundation | Three passes with a sweep between each: node group → interfaces → cluster → security groups → the rest. |

**Rules, each learned the expensive way:**

- Identify leftovers by **ownership** (tags), never by name prefix or a count.
- Read the **state**, not the outputs — `terraform output` returned a warning *as the
  value* once, and nothing at all after `-target` rewrote it.
- The teardown may depend only on **what survives a partial destroy**: AWS tags and
  Terraform state. Everything Kubernetes-side is optional.
- **Release lags termination.** A sweep that breaks on its first empty result reports
  success seconds after terminating something.
- **Do not cancel a deploy or destroy once it has left the queue.** GitHub reports
  `queued` after a job is really running; cancelling one left resources in AWS but not
  in state. `terraform import` is the way back.
- A local `terraform destroy` runs none of this.

## 12. Known trade-offs to revisit for production

| Area | Current | Hardening step |
|---|---|---|
| API endpoint | Public + CIDR allowlist | Private-only + in-VPC runners |
| `public_access_cidrs` | `0.0.0.0/0` | Office/CI ranges only |
| Egress | NAT + overlapping endpoints | Drop NAT, complete the endpoint set |
| System node group | Sized for Argo CD, never re-measured | Measure and shrink |
| Node instance types | Two explicit types — the account is on the **AWS Free Plan** and EC2 refuses anything else | Categories and generations, which is what Spot needs |
| Node AMIs | `al2023@latest` — unattended patches, non-reproducible | Pin and bump deliberately |
| Consolidation | On | Requires `requests=limits` for non-CPU resources on workloads |
| Ingress edge | Internal ALB, one gateway | `internet-facing` + ACM + WAF |
| ALB controller policy | Wider than the job it now does | Size it to registration |
| VPC CNI | Defaults | Dedicated IRSA, network policy, prefix delegation |
| State bucket | Single shared bucket | Per-account buckets + policies |
| CI deploy role | `AdministratorAccess` | Sized policy + permission boundary |
| Human cluster access | hml lists an IAM user and the account **root** | Per-session role, MFA, no standing cluster-admin |
| Prod approval | Reviewer approves before the job starts | plan → approve-with-plan → apply |
| Teardown | Ordered, with sweeps | Exercise the sweeps' delete paths |
