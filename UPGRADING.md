# Upgrading a cluster

How to move an environment's EKS cluster up one Kubernetes minor, what each step
does, how to read the result, and what to do when a run stops. The design and its
reasons are in `ARCHITECTURE.md` §13; this is the procedure.

```
eks-upgrade-pr (target minor)           eks-upgrade (env)              eks-upgrade (prod)
  bump pins in hml + prod                 checks → probe → hold          same, through the
  check components          ──merge──▶    4 phases + health gates  ──▶   Environment's
  open the pull request                   verify → report                 reviewer
  writes nothing to AWS                   writes: deploy role
```

Two rules hold throughout:

- **Never upgrade with `terraform-deploy` or from outside Terraform.** A deploy would
  apply the same changes in one pass with none of the checks between them; an
  `aws eks update-cluster-version` would leave tfvars a minor behind, and EKS refuses
  the downgrade the next plan would then attempt.
- **One minor at a time, hml before prod.** EKS does not skip minors, and nothing
  across accounts enforces the order — it is this procedure.

## Before starting

| Check | Why |
|---|---|
| The environment is deployed and healthy — every Argo CD Application `Synced/Healthy` | The run refuses to start otherwise: an Application out of sync means the versions checked are not the ones running |
| No `upgrade/eks-<minor>` branch left from a previous run (`git ls-remote --heads origin 'upgrade/*'`) | `eks-upgrade-pr` will not overwrite one; delete it once its pull request is merged |
| The bastion is running, and the probe path answers through the ingress ALB | The probe runs from the bastion; a path that does not answer before the upgrade stops the run at its baseline |
| Repository setting *Allow GitHub Actions to create and approve pull requests* is on | Without it `eks-upgrade-pr` leaves a compare link instead of a pull request |

## 1. `eks-upgrade-pr` — prepare the change

Dispatch it from `master` with **target-version** set to the next minor (`1.36`).
It uses the read-only plan role and writes nothing to AWS.

| Step | Does |
|---|---|
| Rewrite the version pins | `kubernetes_version` and the six add-on pins in **hml and prod**, each add-on at the version EKS marks default for the target — never below the current pin, since EKS does not downgrade add-ons. An environment already on the target is left as it is |
| Every component supports the target | Karpenter, Istio, cert-manager and Argo CD against their own published matrices; blocks before anything is pushed |
| Upgrade insights | EKS's readiness scan of the live hml cluster — advisory here, blocking in `eks-upgrade` |
| Push and open the pull request | Branch `upgrade/eks-<minor>`, pull request with the three outputs above in its body |

**Before merging, read the body:**

- *Version pins* — every pin moved, or a note saying why it was kept.
- *Component compatibility* — `unverified` means the component publishes no
  Kubernetes matrix (Gateway API, kube-prometheus-stack, Kiali, the AWS Load Balancer
  Controller). Read their release notes for the target before merging.
- *Upgrade insights* — any `WARNING` or `ERROR` (a removed API still in use, an add-on
  EKS cannot carry). `eks-upgrade` will block on an `ERROR`.

The pull request's checks start on their own. If none has started a minute after it
opened, close and reopen it. Merge once they pass.

## 2. `eks-upgrade` — move the cluster

Dispatch it from `master`:

| Input | Use |
|---|---|
| `environment` | `hml` first; `prod` only after hml is verified |
| `strict` | Off the first time: single-replica or PDB-less *applications* and failed probe requests are warnings. On, they fail the run. The traffic path blocks either way |
| `probe-path` | The path requested through the ingress ALB for the whole run. Default `/sim/`, the disruption-test application; empty disables the probe |

### What it does, in order

Durations are from the hml 1.35 → 1.36 run (about 25 minutes after the gates).

| # | Step | Takes | Stops the run when |
|---|---|---|---|
| 1 | Gates — tests, validate, Trivy | 1–2 min | any fails |
| 2 | Preflight — one minor up, cluster `ACTIVE`, upgrade insights | seconds | an insight reports `ERROR` |
| 3 | Components support the target, against what runs | seconds | a component is unsupported or cannot be verified; an Application is not Synced/Healthy |
| 4 | Workload readiness | seconds | a PDB allows no disruption (single replicas and PDB-less workloads only with `strict`) |
| 5 | Start the availability probe | ~30 s | the baseline is not all `200` |
| 6 | Traffic path — `platform --settle` | seconds, minutes if it restarts something | gateway, CoreDNS, istiod, the Load Balancer Controller or Karpenter is below two Ready replicas on two nodes under a PDB, or the node data plane is incomplete — after restarting what a fresh cluster's bootstrap leaves behind |
| 7 | Hold Karpenter's nodes | seconds | — |
| 8 | **1/4 Control plane** + health gate | ~8 min | the version is not the target; the gate does not pass in 10 min |
| 9 | **2/4 System node group** + health gate | ~9 min | a node does not reach the target in 15 min; the gate does not pass |
| 10 | **3/4 Add-ons** + health gate | ~1–2 min | an add-on is not `ACTIVE`; the gate does not pass |
| 11 | **4/4 Karpenter nodes** — once every EC2NodeClass resolved an image for the target, released; drift replaces them one at a time | ~5 min for three nodes | no image for the target in 15 min; a node does not reach the target in 60 min; the gate does not pass |
| 12 | Verify | seconds | a node, Deployment, StatefulSet or Application has not settled in 15 min |
| 13 | Availability report | seconds | requests failed, with `strict` |
| 14 | Residual changes | seconds | never — it reports what `terraform-deploy` would still change |

The **health gate** after each phase waits until every node is Ready and schedulable,
the per-node data plane (CNI, kube-proxy, ztunnel, istio-cni) is complete, the traffic
path is redundant again, every Application is Synced/Healthy, and the probe's last
fifty requests answered. The next phase never starts on top of the last one's damage.

**Applications move last.** The control plane's new minor makes every Karpenter node
drifted at once. Step 7 marks them `karpenter.sh/do-not-disrupt` (and labels them
`eks-upgrade/held`), so they stay where they are through phases 1–3 and move only in
phase 4. Expiry and Spot reclaims are not blocked by it.

### Watching it

```bash
aws eks update-kubeconfig --region us-east-1 --name eks-hml-cluster

kubectl get nodes -L karpenter.sh/nodepool,karpenter.sh/capacity-type,eks-upgrade/held -w
kubectl -n app-sim logs deploy/loadgen -f | grep -E 'ok=|FAIL'     # the in-cluster view
kubectl -n argocd get applications
```

The loadgen restarts when the system node group rolls (it runs there); the probe on the
bastion does not, which is why it is the measurement of record.

### Reading the result

The run summary carries, in order: the component table, workload findings, the traffic
path (and anything `--settle` restarted), and **Availability through the upgrade** —
requests and failures per phase, with the first failure's time:

```
| Phase                  | Requests OK | Failed | First failure (UTC) |
| before the first phase |         112 |      0 | —                   |
| traffic path settle    |          52 |      0 | —                   |
| 1/4 control plane      |        2120 |      0 | —                   |
| 2/4 system node group  |        2624 |      0 | —                   |
| 3/4 add-ons            |         380 |      0 | —                   |
| 4/4 Karpenter nodes    |        1504 |      0 | —                   |
| verify                 |          34 |      0 | —                   |
| total                  |        6826 |      0 |                     |
```

A failure count is attributed to the phase that was running; the first failure's time
lines up with the step log to find what moved then.

## When a run stops

| Where | Message | What to do |
|---|---|---|
| Before any job | `startup_failure`, no log | The workflow file is invalid — a context used where it is unavailable, or a permission the caller lacks (`ARCHITECTURE.md` §9). Fix the file; nothing ran |
| Compat | `does not support Kubernetes <minor>` / `cannot verify` | Upgrade that component first (platform-gitops or the workload layer), let it roll out, rerun |
| Compat | `Applications not Synced/Healthy` | Fix or wait for the Application; the run checks what runs, not what is declared |
| Workloads | `PDB allows no disruption` | That PDB would hang a drain: scale the workload up, or fix its PDB |
| Probe start | `baseline: N of N requests … failed` | The path does not answer through the ALB. All `000`: no connection — the bastion's egress or the ALB's security group. `404`: wrong `probe-path`. `503`: no healthy gateway target |
| Traffic path | `<component> — 1 replica` / `no PodDisruptionBudget` / `every Ready replica on one node` | Bring it to two replicas, a PDB and a hard hostname spread — platform-gitops for the gateway, istiod and Karpenter; this repository for CoreDNS and the Load Balancer Controller |
| A phase | `control plane reports X, expected Y` | Read the phase's plan output; rerun — a saved, empty plan is a no-op |
| System node group | the node group update failed | Usually a PDB that would not let a pod go for 15 minutes. Find it (`kubectl get pdb -A`), fix it, rerun |
| Health gate | `the cluster did not recover within 600s` | Its last lines list what was still wrong. Fix it, rerun |
| Karpenter nodes | `Karpenter did not resolve a <minor> image` | The nodes are still held, nothing moved. `kubectl describe ec2nodeclass`: `AMIsReady False` with `AMISelector did not match any AMIs` means the alias has no image for the minor — a pinned `al2023@v<release>` older than it; move the pin in platform-gitops, let Argo CD sync, rerun. An image still named for the old minor means Karpenter had not re-resolved yet; rerun |
| After any failure | `Karpenter node(s) still marked do-not-disrupt` | Expected — rerunning finishes the upgrade and releases them. To abandon instead: `./scripts/eks-upgrade.sh karpenter release` |

**Resuming is running it again.** Each phase applies a saved plan, a no-op when
there is nothing left to do, and the preflight accepts a control plane already on the
target. The probe restarts with an empty log, so a resumed run's report covers that
run only.

## Running the steps by hand

Every step is a subcommand of `scripts/eks-upgrade.sh`; all of them work against a
live cluster with a kubeconfig and AWS credentials:

```bash
./scripts/eks-upgrade.sh bump 1.37                # rewrite the pins (what eks-upgrade-pr runs)
./scripts/eks-upgrade.sh compat hml 1.37 --live   # component matrices
./scripts/eks-upgrade.sh workloads                # PDBs and replicas
./scripts/eks-upgrade.sh platform                 # traffic path — read-only
./scripts/eks-upgrade.sh platform --settle        # … restarting bootstrap leftovers
./scripts/eks-upgrade.sh health hml 60            # the between-phases gate, once
./scripts/eks-upgrade.sh probe start hml /sim/    # start the bastion probe
./scripts/eks-upgrade.sh probe report hml marks   # stop it; marks: "<epoch> <label>" per line
./scripts/eks-upgrade.sh karpenter hold|release
./scripts/eks-upgrade.sh ami 1.37 0               # Karpenter's NodeClasses resolve a 1.37 image — once
```

`platform`, `health`, `ami`, `compat` and `workloads` only read. `probe start` leaves a
systemd unit (`eks-upgrade-probe`) running on the bastion until `probe report` stops
it, or four hours pass.

## Rehearsing in hml

hml is destroyed between sessions, so a rehearsal starts from a cluster one minor
behind the target:

1. On a branch, set hml's `kubernetes_version` and six pins back to the previous
   minor's values (git history has them) and merge it.
2. `terraform-destroy` for hml, then `terraform-deploy` hml/both.
3. Delete `upgrade/eks-<target>` if it exists.
4. `eks-upgrade-pr` with the target, merge, then `eks-upgrade` for hml.

## Prod

The same `eks-upgrade`, after hml is verified at the same versions. Prod's
Environment requires a reviewer before the job starts, and prod's tfvars may already
be on the target — `eks-upgrade-pr` leaves an environment already there untouched.
