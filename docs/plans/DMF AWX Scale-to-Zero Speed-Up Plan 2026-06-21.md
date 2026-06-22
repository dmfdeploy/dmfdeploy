---
status: executed
date: 2026-06-21
executed: 2026-06-22
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/110
---
# DMF AWX Scale-to-Zero Speed-Up Plan (2026-06-21)

> **EXECUTED 2026-06-22 — WS1 + WS2 (direct Deployment scaling), live-verified.**
> Shipped in `dmf-infra` [PR #24](https://github.com/dmfdeploy/dmf-infra/pull/24):
> the `awx-autoscale` helper (`/ensure-awake` + reaper) and the `awx-presence`
> bootstrap role now scale the `awx-web`/`awx-task` Deployments **directly**,
> alongside the authoritative CR patch (`manage_replicas=true` → operator reconcile
> is a no-op since values match); RBAC widened `deployments: get→get,patch`.
> **Live result on the Pi 4:** cold wake `readyReplicas>=1` in **18s** (was ~6–10 min
> operator reconcile), **no replica bounce-back** across a full reconcile window, sleep
> to pods-gone in **22s**. codex-reviewed (APPROVE) + CODEOWNERS-approved.
> **WS3** (probe hardening) deferred — overlaps the #106 Tier-3 probe item.

**Status:** Draft (proposed, not started).
**Tracking:** [dmfdeploy/dmfdeploy#110](https://github.com/dmfdeploy/dmfdeploy/issues/110)
**Component:** `dmf-infra` (`awx-presence` role, `awx-autoscale` helper).
**Design authority:** within [ADR-0043](../decisions/0043-workload-scale-to-zero-availability.md)
(AWX-scoped scale-to-zero). Follow-up to [#106](https://github.com/dmfdeploy/dmfdeploy/issues/106).

---

## 1. Problem — the operator is the bottleneck

AWX scale-to-zero today changes replicas by **patching the AWX Custom Resource**
(`web_replicas`/`task_replicas`) with `manage_replicas: true`, so the **AWX operator owns
the replica count** and every change waits for the operator to reconcile.

| Cost | Magnitude | Notes |
|---|---|---|
| **Operator reconcile** | **~6–10 min** | The AWX operator is an Ansible-operator: each reconcile re-runs a full playbook re-applying the entire AWX spec. Minutes on Pi-class CPU; **worse under load** (the operator is CPU-starved by the very awake AWX it's trying to scale — observed CR `replicas=0` while Deployments `1/1`). Hits **both** directions. |
| **Pod startup** | **~70 s** | Wake only. `awx-web` then `awx-task` (the long pole, +~70 s) become Ready; the `pg_isready`/`ak healthcheck` exec probes are CPU-heavy on a Pi. |

A cold "click catalog deploy → job starts" ≈ **6–10 min (operator) + ~70 s (pods)** — the
operator is ~90% of it.

**Confirmed in code (2026-06-21):**
- `awx-presence` (`tasks/main.yml`) patches the CR with `web/task_manage_replicas: true`.
- `awx-autoscale` helper (`files/awx_autoscale_helper.py`) `/ensure-awake` **PATCHes the CR**
  (L327/346) and only **reads** the Deployments (L371/382); RBAC is `deployments: [get]`
  (read-only, `tasks/main.yml` L81–82) — it cannot scale Deployments today.

## 2. Fix — take the operator off the critical path

**Scale the Deployments directly, alongside the CR patch.** A direct `Deployment` replica
change is acted on by the kube scheduler in **seconds**. Keeping the CR patched to the
*same* target means the operator stays authoritative and its later reconcile is a
confirming **no-op**, not the bottleneck.

> Manually verified this exact effect during #106: `kubectl scale deploy awx-web awx-task
> --replicas=0` freed ~4 GB **instantly**, where the CR patch alone had not reconciled.

Effect: **scale-down ≈ instant**, **scale-up ≈ 70 s** (pod-startup-bound, down from 6–10 min).

### Work items

- **WS1 — `awx-presence` sleep/wake:** after the existing CR patch, also patch the
  `awx-web` + `awx-task` Deployment `spec.replicas` directly (to 0 asleep / desired awake).
  The await-asleep gate (#106) then passes in seconds instead of minutes.
- **WS2 — `awx-autoscale` helper `/ensure-awake`:** scale the Deployments directly in
  addition to the CR patch; widen the helper Role from `deployments: [get]` to
  `deployments: [get, patch]` (or the `scale` subresource). This is what makes the
  on-demand catalog-deploy wake feel responsive (the helper is the path dmf-cms calls).
- **WS3 — residual ~70 s wake (pod startup):** cheaper/looser readiness probes on the
  constrained profile (HTTP/TCP or relaxed `timeoutSeconds`/`initialDelaySeconds` — also
  the Tier-3 probe item in #106); wake `awx-task` concurrently with `awx-web` rather than
  strictly sequentially. Postgres (StatefulSet) and the operator already stay warm; the
  AWX image is already warm in Zot (630 mirror).

## 3. Design decision — keep the operator authoritative

Two ways to direct-scale:

| Option | What | Trade-off |
|---|---|---|
| **A (recommended)** — direct-scale **+** keep CR patched to same value, `manage_replicas: true` | Operator stays the owner; its reconcile confirms the value we already set (no-op). | Tiny window where CR/Deployment could disagree mid-op; converges since both target the same value. |
| B — set `manage_replicas: false`, own replicas entirely | Simplest direct-scale (no operator involvement). | Operator no longer corrects replica drift or manages replicas across AWX upgrades/reconfig; larger behavioral change to the operator contract. |

Recommend **A**: smallest change, preserves the operator's ownership (consistent with the
ADR-0043 framing that scale-to-zero is an availability action layered *over* the operator,
not a replacement for it).

## 4. Verification

- Time a sleep and a wake before/after on the constrained node: scale-down drops from
  minutes to seconds; cold wake drops from ~6–10 min to ~70 s.
- The on-demand path: launch an NMOS catalog job from the Console against an asleep AWX →
  AWX is serving within ~70 s and the job runs (vs the current minutes-long stall).
- No operator fight: after a direct scale, the AWX CR and Deployments stay consistent
  across a full operator reconcile cycle (Deployments not bounced back).

## 5. Scope / sequencing

- **WS1 + WS2 first** (the direct-scale change is the ~90% win); WS3 (probe/concurrency
  polish) second.
- `v0.2`. Within ADR-0043; no new ADR unless review wants the `manage_replicas` decision
  recorded formally.
