# Architecture

A private EKS platform, production-shaped on a portfolio budget. This document
records the decisions and what each one costs. Section numbers are referenced from
code comments (`see ARCHITECTURE.md §N`) and are stable.

## 1. High-level topology

```
                        AWS account · us-east-1
┌────────────────────────────────────────────────────────────────────┐
│ VPC   10.0.0.0/16 (hml)  ·  10.1.0.0/16 (prod)                     │
│                                                                    │
│  public 1a/1b                    private 1a/1b                     │
│  ├ Internet Gateway              ├ EKS control-plane ENIs          │
│  └ NAT GW per AZ ────egress──▶   ├ Managed node group (system)     │
│                                  ├ Karpenter nodes (on demand)     │
│                                  ├ Bastion (SSM only)              │
│                                  ├ Platform ALB (internal)         │
│                                  └ VPC endpoints + S3 gateway      │
└────────────────────────────────────────────────────────────────────┘

bootstrap/  → S3 state bucket (KMS) + OIDC roles        local state
foundation/ → VPC, EKS, KMS, nodes, bastion, endpoints  ─┐
                                                          │ terraform_remote_state
workload/   → ALB, ingress edge, storage, Argo CD        ←┘
                        │
                        └─ handover ─▶ platform-gitops (Argo CD owns the rest)
```

## 2. Two-layer split (`foundation` + `workload`)

`foundation` owns long-lived infrastructure; `workload` owns in-cluster add-ons and
hands the cluster to Argo CD. `workload` reads `foundation` outputs through
`terraform_remote_state`.

**Why:**
- **Provider boundary.** `kubernetes` and `helm` exist only in `workload`. In one
  state they would be configured from a resource created in the same apply — the
  classic bootstrap deadlock.
- **Blast radius.** Add-ons change often, the network rarely. A bad `workload` apply
  cannot corrupt or lock `foundation` state.

**Cost:** `foundation/outputs.tf` becomes an API. Renaming an output passes `fmt`,
`validate` and every test, and fails at run time in the other layer —
`scripts/check-layer-contract.sh` compares the two lists in CI. Ordering is manual;
the deploy workflow encodes it.

## 3. Networking

- **2 AZs, public + private.** Public subnets host only NAT and the IGW route; all
  compute is private.
- **One NAT Gateway per AZ.** Trade-off: ~2× the cost of a shared NAT, against an
  AZ-level SPOF for egress. Collapse to one for a pure cost demo.
- **VPC endpoints (PrivateLink + S3 gateway)** for ECR, STS, EC2, EKS, KMS, ELB,
  autoscaling, logs and the SSM trio. They overlap with NAT and add cost; they are
  kept because they keep AWS-API traffic off the NAT and are the migration path
  toward removing it. Dropping NAT later requires completing the endpoint list.
- **The ingress load balancer belongs to Terraform**, not to a controller.
  `workload/modules/platform-ingress` declares an internal ALB, target group,
  listener and security group; the cluster attaches through a `TargetGroupBinding`
  that registers pod IPs and owns nothing.
  - **Why:** a load balancer created from inside the cluster never enters Terraform
    state, so `destroy` has no edge from it to the subnets it occupies. Its ENIs
    hold the subnets, the subnets hold the VPC, and the teardown fails after most of
    the platform is gone. Owning the resource makes teardown ordering a property of
    the dependency graph (§11).
  - **The internet-facing guard moved with it.** It was the *absence* of a
    `kubernetes.io/role/elb` tag on the public subnets — defeatable by anyone who
    could tag a subnet. It is now the absence of `internal = false` in reviewed HCL.
  - **Cost:** a new edge is a Terraform change, not a manifest. Right for one shared
    gateway; wrong for a platform giving each team its own.
  - **Coupling:** `workload` must know the namespace and name of the Service istiod
    generates for the platform `Gateway` — the one contract pointing from Terraform
    outward. Declared as a variable with no default. A mismatch is silent: the target
    group registers nothing and the ALB answers 503, so read target health first.

## 4. EKS control plane

- **Private + public API endpoint**, gated by `public_access_cidrs`. Trade-off: a
  fully private endpoint needs self-hosted runners in the VPC. The allowlist buys a
  dramatically simpler pipeline; tighten it in prod.
- **Secrets envelope encryption** with a rotated customer-managed KMS key, scoped to
  the cluster role.
- **All five control-plane log types**, to a Terraform-managed log group with 90-day
  retention. Declared explicitly because EKS creates the group itself, with **no
  expiry**, and Terraform cannot set retention on a group it does not own. The real
  alternative was not another number — it was an accidental infinity.
  - **Hazard:** a log group outliving a previous cluster fails the apply with
    `ResourceAlreadyExistsException`. Remedy is `terraform import`; deleting it would
    discard audit history.
- **`API_AND_CONFIG_MAP` auth**, so Access Entries work while anything still reading
  aws-auth keeps working.
- **Core add-ons as code** (`vpc-cni`, `coredns`, `kube-proxy`, `metrics-server`,
  `aws-ebs-csi-driver`, `eks-pod-identity-agent`) with versions pinned per
  environment. Left self-managed they stay at whatever EKS shipped and fall out of
  supported version skew during an upgrade — surfacing as intermittent DNS or
  routing failures that are hard to trace. **Bump the cluster version and the add-on
  pins in the same change.**
  - `metrics-server` and the EBS CSI driver close gaps that fail *silently*: no HPA
    and no `kubectl top` without the first; every PVC `Pending` forever without the
    second.
  - The CSI driver is the only add-on calling the AWS API, so it alone gets a role —
    IRSA scoped to its ServiceAccount, carrying the AWS-managed policy rather than a
    hand-written one that would drift on every upgrade.

## 5. Compute — system pool + Karpenter

- **A managed node group on AL2023 is the system pool, and stays.** Karpenter runs in
  pods and cannot host itself; AWS states it directly — *"do not run Karpenter on a
  node that is managed by Karpenter"*. Its current size was chosen for Argo CD's pod
  count against the VPC CNI's ENI-derived ceiling, never re-measured; whether it can
  shrink is open (§12).
- **Karpenter provisions everything else.** The controller, `NodePool` and
  `EC2NodeClass` are delivered by Argo CD; Terraform provides only what Kubernetes
  cannot create for itself:
  - **An Access Entry of type `EC2_LINUX`** for the node role. A role gets an instance
    into the *account*; joining the *cluster* needs this, and it is a different type
    from the `STANDARD` entries used for humans and CI. Without it the instances boot,
    look healthy in EC2, and never become nodes — with no error to follow.
  - **`karpenter.sh/discovery` tags** on the private subnets and cluster security
    group. Karpenter finds where to launch by tag; an unmatched selector provisions
    nothing and reports only that nothing matched.
  - **An SQS interruption queue** fed by EventBridge. Karpenter works without it,
    which is the trap: the gap only appears during a Spot reclaim, when the node
    vanishes instead of draining.
  - **Pod Identity, not IRSA**, for the controller. The chart comes from a public Git
    repository, and IRSA would require the role ARN in a values file, hardcoded per
    account. Pod Identity binds role to ServiceAccount from the AWS side. It needs the
    `eks-pod-identity-agent` add-on; without it the association exists and silently
    delivers no credentials.
  - **The controller's blast radius is bounded in IAM, not in configuration.**
    `iam:PassRole` names one role and is conditioned on `iam:PassedToService`;
    `TerminateInstances` requires **both** `kubernetes.io/cluster/<name>=owned` and
    `karpenter.sh/nodepool` — the first alone would reach the managed node group,
    which carries the same tag.
    - **`karpenter.sh/` is a reserved tag prefix.** Keys under it are dropped from an
      `EC2NodeClass`'s `tags` silently — no error, warning or event, while a custom
      tag beside them applies normally. A condition naming `karpenter.sh/discovery`
      on an *instance* can never match. Guarded by
      `foundation/modules/karpenter/tests`.
- **Instance `Name` tags come from a launch template.** `tags` on the node group land
  on the group, and an `aws_autoscaling_group_tag` can only exist after EKS has
  already launched the nodes. The template omits `image_id`, so EKS keeps supplying
  the AMI and bootstrap data. Sharp edge: changing it rolls the nodes.

## 6. Access — bastion + SSM

- **Private subnet, no public IP, no inbound SSH.** Access only through SSM Session
  Manager; IMDSv2 required, root volume encrypted.
- **Least-privilege egress, no `0.0.0.0/0`:** HTTPS to the VPC CIDR (the SSM endpoints
  and private EKS API resolve in-VPC), DNS to the VPC resolver, and HTTPS to the
  **in-region S3 prefix list**. The bastion never needs internet.
- **Tooling from an in-region bucket.** AWS's public `amazon-eks` bucket is in
  us-west-2; a gateway endpoint only routes to S3 in its own region, so a
  cross-region request matched no egress rule and **hung silently** — not
  `AccessDenied`, not a refused connection. "No internet egress" and "a bucket in
  another region" cannot both hold.
  - The pipeline seeds the bucket after applying `foundation`; the runner has
    internet, the bastion deliberately does not. Terraform owns the bucket, not the
    binary — `aws_s3_object` would need a 50 MB file on disk at plan time.
  - The bastion is created *during* the apply and the bucket seeded *after*, so a
    systemd unit retries until the object appears. The host converges on its own.
- **A session needs no setup**, which took two mechanisms:
  - A world-readable `/etc/kubeconfig` (it holds no secret; auth is an exec call to
    `aws eks get-token` under the instance role) plus `/etc/profile.d/kube.sh`. A
    user's home was not an option — `ssm-user` is created on *first session*.
  - `/etc/profile.d` is read only by **login** shells, and Session Manager starts a
    plain `sh`. An `SSM-SessionManagerRunShell` document with `shellProfile =
    "bash -l"` fixes the cause rather than the symptom. That document is
    **account-wide**; a flag exists for accounts holding several environments.
  - `k` is a script on PATH, not an alias, so it works in non-interactive shells and
    `ssm send-command`.
- **Cluster access is an Access Entry, not an IAM permission.** `hml` grants
  cluster-admin to the CI deploy role, an IAM user, and the account root — the last
  because that is the console identity. Root cannot be scoped or attributed to a
  person; acceptable in an environment destroyed between sessions, not in prod (§12).

## 7. Add-ons — the workload layer

- **AWS Load Balancer Controller (IRSA + Helm).** Its job is now narrower: it
  registers pod IPs into the Terraform-owned target group and writes the
  security-group rules that reach them. It no longer creates load balancers, because
  nothing asks it to (§3). Its IAM policy is unchanged and therefore wider than the
  job — narrowing it is a separate change (§12).
- **The `TargetGroupBinding` is applied by Terraform, not Argo CD.** It needs the
  target-group ARN and a security-group id, both account-specific, and the GitOps
  repository is public. Same reasoning as Pod Identity in §5.
- **A default `gp3` StorageClass.** The CSI driver is a `foundation` add-on; without
  a class it provisions nothing, and EKS's built-in `gp2` uses the in-tree
  provisioner removed in 1.27. Reclaim policy is per environment: `Delete` in hml,
  where a retained volume outlives `destroy` and bills silently.
- **Argo CD, installed and then left alone.** Terraform installs it — bringing the
  CRDs and controllers — and stops. From there custom resources arrive from Git,
  which is what avoids the plan-time CRD-schema problem `kubernetes_manifest` has.
- **The handover: two `AppProject`s and one root `Application`.** The projects are the
  privilege boundary between the platform repository and the application repository;
  they live in Terraform because a boundary stored in the repository it governs can
  be widened by anyone who can commit there.
  - Helm chart repositories count as sources. A multi-source Application takes its
    chart from one and its values from another, and Argo CD checks both — listing
    only the Git repository fails every chart-based component.
  - **Sizing is a hard constraint.** The VPC CNI caps pods per node by ENI capacity.
    Argo CD needs seven pods; HA mode adds three more for redis alone.
  - **Sharp edge:** Helm 3 does not upgrade CRDs. `crds.keep = true` so uninstalling
    never cascade-deletes live `Application` objects.

## 8. State & backend

- **S3 with native locking** (`use_lockfile`, Terraform ≥ 1.10) — no DynamoDB table.
- **Encrypted with a rotated customer-managed KMS key**, not SSE-S3, for key-policy
  control and an audit trail on decryption. Every principal running Terraform needs
  `kms:Decrypt` and `kms:GenerateDataKey` on it.
- **Partial backend config**, so the same code serves both environments.
- `.terraform.lock.hcl` is committed; the non-sensitive per-environment `*.tfvars`
  are committed because CI depends on them.
- **`bootstrap` keeps local state**, which is a durability risk worth naming: it
  exists only on the operator's workstation. It is also why a broken trust policy is
  always recoverable.

## 9. CI/CD (GitHub Actions)

- **OIDC, no static keys.** All actions pinned to a commit SHA.
- **Two roles, split on read/write.** GitHub stamps a `sub` claim describing how a run
  was triggered, and the trust policies split on it:

  | Claim | Role | Used by |
  |---|---|---|
  | `pull_request`, `ref:refs/heads/*` | plan (read-only) | `terraform-plan` |
  | `environment:<env>` | deploy (write) | `terraform-deploy`, `terraform-destroy` |

  A pull request runs the workflow file **from its own branch**, so without this split
  anyone able to push a branch could run arbitrary AWS commands with the deploy role
  before review. The `environment:` declaration is what mints the claim, and the
  Environment's branch policy is what stops a branch minting it for itself.
- **Deploys are never automatic on merge.** `workflow_dispatch`, gated on tests and
  Trivy, applying a saved plan (`plan -out` → `apply tfplan`).
- **The plan role holds no write permission at all**, including the state lock —
  hence `-lock=false` on plan. It also skips refresh for `workload`, whose in-cluster
  resources would require an Access Entry the plan role deliberately lacks. Drift in
  those two resources shows up on the deploy path instead.
- **Quality gates:** `fmt`, `validate`, the layer-contract check, module tests with
  mocked providers (no credentials, no infrastructure), and a Trivy IaC scan.
  Suppressions in `.trivyignore` require a written reason and a pointer to the section
  that accepts the trade-off.

## 10. Environments

`hml` and `prod` are isolated by distinct VPC CIDRs, state keys and AWS roles. `hml`
is destroyed between sessions, which shapes several defaults: `Delete` reclaim policy,
a 24h node expiry, a permissive API CIDR. Each is stated where it differs from what
production should do.

## 11. Teardown

**Destroying this platform is not the reverse of applying it.** Controllers inside the
cluster create AWS resources Terraform never records, and Terraform then has no
dependency edge from those resources to the subnets they occupy. The error names the
subnet and never names what holds it — after most of the platform is already gone.

The ingress load balancer was removed as a source by giving it to Terraform (§3). What
remains cannot be: **debris that does not exist until Terraform creates it**.

```
Terraform destroys      AWS leaves behind        which holds
──────────────────      ──────────────────       ───────────
managed node group  →   VPC CNI interfaces   →   the subnets
EKS cluster         →   eks-cluster-sg-<id>  →   the VPC
```

`terraform-destroy.yml` is therefore ordered, not merely sequential:

| Step | Why here |
|---|---|
| Drain cluster-owned state | Clears `syncPolicy.automated` first — `selfHeal` treats a deletion as an instruction to recreate. Then deletes Karpenter `NodePool`s **before** the Applications, because deleting a NodePool is a request to Karpenter and the Application installing Karpenter goes moments later. Then strips finalizers, which would otherwise hang the Helm uninstall. |
| Terminate Karpenter instances | Its own step, **not** gated on a live cluster: it identifies instances by AWS tags that outlive every Kubernetes object, and the case that matters is the one where the cluster is already gone. On the normal path it finds nothing — which is the signal the ordering above is right. |
| Destroy workload | Removes the platform ALB, which is why the preflight runs after it. |
| Preflight | Asserts the VPC holds nothing unowned, in seconds, rather than as a `DependencyViolation` forty minutes in. |
| Destroy foundation | Three passes, each opening a window between "Terraform removed X" and "Terraform needs what X's debris is holding": node group → sweep interfaces → cluster → sweep security groups → everything else. |

### Rules this cost a week to learn

- **Identify leftovers by ownership, never by name.** Prefix matches (`k8s-`,
  `aws-K8S-`) and non-zero counts were all wrong in a state nobody had seen. Tags
  answer what a prefix only guesses at.
- **Read the state, not the outputs.** `terraform output` is a projection and failed
  twice: once returning `Warning: No outputs found` *as the value*, once returning
  nothing because `-target` had rewritten the outputs while the resource sat in state
  undeleted. Identifiers now come from `terraform show -json`, and every one is
  checked for shape rather than for emptiness.
- **The teardown may depend only on what survives a partial destroy** — AWS tags and
  Terraform state — and must treat everything Kubernetes-side as optional. Six guards
  in a row were written for the healthy case and met in the recovery case: a name
  prefix, an output count, a reserved tag, the presence of a CRD, a live cluster, a
  cluster name in state.
- **Release lags termination.** A sweep that breaks on its first empty result will
  report success seconds after terminating something. Require two consecutive empty
  passes.
- **Do not cancel a deploy or destroy once it has left the queue.** GitHub reports
  `queued` for some time after a job is really running, so a run that looks stuck may
  be mid-apply. Cancelling one left an EKS cluster, a VPC endpoint and a route table
  in AWS but not in state; `terraform import` is the way back.
- **A local `terraform destroy` runs none of this.** The drain, the preflight and the
  sweeps live in the workflow.

## 12. Known trade-offs to revisit for production

| Area | Current (portfolio) | Hardening step |
|---|---|---|
| API endpoint | Public + CIDR allowlist | Private-only + in-VPC runners or VPN |
| `public_access_cidrs` | `0.0.0.0/0` | Office/CI egress ranges only |
| Egress | NAT + overlapping endpoints | Drop NAT, complete the endpoint set |
| System node group | Sized for Argo CD, never re-measured | Measure and shrink; it now hosts only controllers |
| Node instance types | An explicit two-type list — the account is on the **AWS Free Plan** and EC2 refuses anything not free-tier eligible | Categories and generations, which is what Spot needs to draw from a wide pool |
| Node AMIs | `al2023@latest`: patches arrive unattended, and two syncs months apart give different nodes with no diff in Git | Pin the alias, bump deliberately |
| Consolidation | On | Requires `requests=limits` for non-CPU resources on hosted workloads |
| Ingress edge | Internal ALB, one shared gateway | `internet-facing` + ACM on the listener + WAF |
| ALB controller policy | Wider than the `TargetGroupBinding`-only role it now plays | Size it to registration and security-group rules |
| VPC CNI | Defaults | Dedicated IRSA role, network policy, prefix delegation |
| Cluster add-ons | ALB controller, storage, Argo CD | + External Secrets, ExternalDNS, policy agents |
| State bucket | Single shared bucket | Per-account buckets + bucket policies |
| CI deploy role | Split from plan; `AdministratorAccess` | Sized custom policy + permission boundary |
| Human cluster access | hml lists an IAM user and the account **root** as cluster-admin | A role assumed per session, MFA, no standing cluster-admin |
| Prod approval | Reviewer approves before the job starts | Split into plan → approve-with-plan → apply |
| Teardown | Ordered, with sweeps | Exercise the sweeps' delete paths; make a local destroy run the same checks |
