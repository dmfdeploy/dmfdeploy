---
status: historical
date: 2026-06-01
---
# DMF Elastic Media Nodes & Cloud Cost Controller Plan

**Date:** 2026-06-01
**Status:** Plan — split out of the MXL spike as a general (non-MXL) platform workstream
**Owner:** operator (with Claude; informed by a codex adversarial review, session `019e81f6`)
**Branch:** `main` (this is general platform infrastructure, not spike work)

**Related:**
- `docs/plans/DMF MXL On-Demand Media Function Cycle Plan 2026-06-01.md` (on `feat/mxl-spike`) — the **first consumer** / motivating use case; depends on Phase 1 here
- ADR-0025 — catalog launcher = in-cluster Helm / EE-as-runtime (ansible runtime; **not** a provisioner)
- ADR-0024 / ADR-0033 — identity / scoped-writer model (privilege surface for cloud-spending actions)
- `docs/plans/DMF In-Cluster Ansible Runner Pod Implementation Plan 2026-05-14.md` — states provision-stage stays on the SSH path
- `dmf-env/bin/tf-apply.sh`, `dmf-infra/k3s-lab-bootstrap/ee/execution-environment.yml` — current provisioning + EE reality

---

## 0. Why this exists (split from the MXL spike)

A codex adversarial review of the MXL spike found that "deploy a media function →
the platform spins up a cloud node → runs it → tears it down on idle" is a
**cloud-cost-controller** project, not an MXL concern. It was split out so the MXL
spike stays focused. This plan owns the **general** capability: provision media
compute on demand and **guarantee it is never orphaned or billed beyond need** —
independent of which media function (MXL, NMOS, transcode, …) consumes it.

## 1. The hard constraint (why this is non-trivial)

**OpenTofu is not available in-cluster, by design.**
- The in-cluster execution environment (`dmf-infra/k3s-lab-bootstrap/ee/execution-environment.yml`)
  is `quay.io/ansible/awx-ee` + ansible collections only — **no tofu** in the build
  context or any EE commit. Its consumers are the in-cluster ansible runner and AWX
  `media-*` launchers — both **configure-stage**, neither provisions.
- `dmf-env/bin/tf-apply.sh` is **operator-laptop** only: Aliyun creds at
  `~/.secure/aliyun/...`, **JuiceFS single-operator** state (locking disabled), `tofu`
  assumed on `$PATH`.
- The in-cluster runner plan states it outright: *"Provision-stage (Layers 1–3:
  OpenTofu, base, k3s) stays on the SSH path — the cluster doesn't exist yet during
  those layers."*

So neither **provisioning** nor a tofu-based **teardown** can run in the cluster
today. Any "in-cluster autoscaling" requires building new substrate first.

## 2. Phases

| Phase | Deliverable | Why |
|---|---|---|
| **P1 — Cost fail-safe (must-have; MXL spike depends on this)** | Tag convention + **out-of-cluster cloud-tag TTL sweeper** that destroys media instances past TTL, independent of k8s and TF state | The honest guardrail; lets us run billable fixed pools safely. Build this **first**. |
| **P2 — Provisioning substrate** | A runtime that can actually run `tofu apply/destroy` for media nodes off the operator laptop | Prereq for any automation; pick one of the two designs in §4 |
| **P3 — Scale-from-zero** | Controller watches unschedulable media pods → provisions via P2 → labels/schedules; idle teardown; P1 as backstop | The "magic"; only after P1+P2 are proven against forced failures |

## 3. P1 — cloud-tag TTL sweeper (detail)

**Tag every media instance at create time** (in the terraform/user-data):
`dmf-owned=true`, `env=<env>`, `purpose=mxl-media` (or general `dmf-media`),
`created-at=<iso8601>`, `ttl=<duration>`.

**An out-of-cluster sweeper** (operator host / a tiny always-on VM / an Aliyun-native
lifecycle rule) lists instances by tag and **destroys any past `ttl`**. It must be
independent of both Kubernetes and Terraform state, because the orphan vectors a k8s
reaper misses are exactly the dangerous ones (codex):
- instance created **before** k3s join; node that never labels correctly
- Terraform **state drift**; failed join; AWX job cancellation
- cluster outage; expired cloud credentials
- Node object deleted while the ECS instance is still alive

**Fail-safe posture:** teardown **defaults to destroy**; survives the cluster *and*
the operator laptop being offline (the precise scenario that leaks billable
instances). Add a hard **instance cap** and an **alert** on create/destroy.

## 4. P2 — provisioning substrate (two designs)

| Option | Sketch | Cost |
|---|---|---|
| **A. Out-of-cluster provisioner agent** | A small always-on agent (operator host / tiny VM) watches a cluster signal (queue / CRD / annotation) and runs `tofu apply` + join + `tofu destroy` | Reuses today's laptop tooling; but reintroduces a host dependency, and the agent's availability becomes load-bearing for teardown |
| **B. Provisioner execution environment** | Bake `tofu` into a new EE; inject cloud creds via **OpenBao**; move TF state to a **network backend** (OSS/S3/PG, not laptop-JuiceFS); grant cloud-API **egress** | Fully in-cluster, but a real new attack surface (cloud creds in-cluster — ADR-0024/0033) + cross-cloud egress (Hetzner cluster → Aliyun API) + a state-backend migration |

Either way, **P1's sweeper remains the backstop** — P2 must never be the *only* thing
preventing orphaned spend.

## 5. P3 — scale-from-zero (detail)

A controller watches for **pending/unschedulable media pods** (nodeSelector+taint, no
matching node) → triggers provisioning through P2 → labels the node → pod schedules.
On the last media pod leaving a node, start an idle timer → teardown via P2. Edges to
handle: partial provision (booted, join failed → orphan), **concurrency** (two deploys
racing a node-role), NotReady backpressure, honest "provisioning…" UX.

## 6. Security / privilege (codex finding)

Any control that **spends cloud money** is a privilege + cost-attack surface. Today the
CMS catalog deploy endpoint only checks "is authenticated" (`dmf-cms/src/dmf_cms/main.py`).
Before a cloud-provisioning trigger ships: **role-gated** deploy, **audit event**,
explicit **confirmation**, **rate limit**, and **instance cap**. Ties to ADR-0024 (two
identities) / ADR-0033 (scoped writers).

## 7. Risks

- **Runaway cost** — the dominant risk; P1 exists to bound it; P2/P3 add surface, so P1
  must precede them.
- **Cross-cloud egress** — a Hetzner-hosted control plane calling the Aliyun API.
- **State-backend migration** — moving TF state off laptop-JuiceFS to a network backend
  is a prerequisite for any non-laptop provisioning; do it carefully (import, lock).
- **New ADR likely** — making provisioning runnable off the SSH/laptop path reverses a
  standing decision (runner plan §); record it when P2's design is chosen.
