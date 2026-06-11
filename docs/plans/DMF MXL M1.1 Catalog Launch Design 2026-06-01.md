---
status: executed
date: 2026-06-01
executed: 2026-06-05
---
# DMF MXL M1.1 — Catalog Launch Design (minimal, two independent functions)

**Date:** 2026-06-01
**Status:** Design proposal for M1.1 (the critical path) — pre-implementation, for review
**Owner:** operator (with Claude)
**Branch:** `feat/mxl-spike`
**Parent:** `docs/plans/DMF MXL On-Demand Media Function Cycle Plan 2026-06-01.md` §3.1–3.2

---

## 1. Problem & constraints (from code, 2026-06-01)

- `dmf-cms` `/api/catalog/{key}/deploy` → `launch_job(template_id)` posts **`body={}`** —
  **no extra_vars** ever pass from the console (`dmf-cms/src/dmf_cms/awx.py`,
  `main.py`). So per-deploy parameterization must live in the **AWX job template /
  playbook / chart values**, not in a CMS payload.
- Today there is **one** `mxl-fabrics-demo` chart (`target.yaml` always +
  `initiator.yaml` gated by `initiator.enabled`) deployed as **one release**, wired by
  a **manual** two-phase handshake (`helm upgrade --set initiator.targetInfo="<blob>"`
  copied from target logs).
- The MXL launch/teardown playbooks + JTs the catalog entry already names
  (`media-launch-mxl-fabrics-demo`, `launch-mxl-fabrics-demo.yml`) **do not exist**;
  only `launch-nmos-cpp.yml` does — that is the pattern to copy.
- **ADR-0027** prescribes a `MediaFunctionInstance` CRD + Catalog Operator; the MXL
  spike is its *named trigger*. We deliberately take the **minimal interim** and leave
  the reconciler deferred (codex blessed this).

## 2. The user goal that picks the shape

The demo must show **0 → 1 → 2 nodes**: deploy the source → one node with the source
pod → deploy the view → a second node with the view pod. That requires the two
functions to be **independently deployable** — one button each — not a single button
that brings up both (which is 0 → 2). So: **two catalog entries, two releases.**

## 3. Design — role-parameterized chart, two entries, four JTs, no CMS deploy-path change

1. **Chart: add a `role: source|view` value** (small refactor of the existing chart).
   Render the **target** Deployment when `role=view`, the **initiator + test-pattern
   writer** Deployment when `role=source`. Reuse `target.yaml` / `initiator.yaml`,
   gate by `role` instead of `initiator.enabled`. **Keep the status sidecar on BOTH
   roles** (preview only on `view`) — otherwise source-first can't show the "1 node"
   state. **Make resource names two-release-safe:** today `_helpers.tpl`, the
   `…-flow` ConfigMap, and the emitted Namespace are fixed (`mxl-fabrics-demo*`), so
   two releases of one chart **collide**. Release-scope the names (include
   `.Release.Name`) or pre-create the shared `mxl` namespace + flow ConfigMap outside
   Helm ownership. One chart → **two releases** (`mxl-videotestsrc` = source,
   `mxl-videotest-view` = view). Reuse, not two charts.
2. **Two catalog entries** (`dmf-media/catalog/mxl-videotestsrc.yaml`,
   `mxl-videotest-view.yaml`), each with its own `configure.awx_job_template` +
   `finalise`. **Placement by label selector** (`dmf.io/mxl-demo-role=source|view`
   on the fixed nodes), **not** hardcoded `nodeName` — survives node reprovision.
   (Retire / supersede the single `mxl-fabrics-demo.yaml`.)
3. **One generic launch + one generic teardown playbook** in `dmf-runbooks` (copied
   from `launch-nmos-cpp.yml`): `helm pull` the mxl chart from Zot →
   `kubernetes.core.helm` install with `role` + placement in `release_values` →
   `k8s_info` readiness gate. **Four JTs** (`media-launch/finalise-mxl-videotestsrc`,
   `…-view`) supply the fixed `role`/release/selector as **JT default vars** — do
   **not** copy four near-identical playbooks.
4. **No CMS deploy-path change.** `/api/catalog/{key}/deploy` already launches the
   named JT per entry → two buttons → two independent deploys. **One small view
   tweak is needed though:** `mxl.py` renders every configured endpoint as a node
   even when unreachable, so two static endpoints show as two offline cards at "0".
   For a true 0→1→2, hide unreachable endpoints (small backend change) or use a
   fixed-pool registry route. Not the deploy path — the view only.
5. **No ADR-0027 reconciler.** Placement is per-JT default var; the
   `MediaFunctionInstance` CRD stays deferred. Record this interim decision
   (one-line ADR-0027 note).

## 4. Handshake (M1.3, designed here so step 1 doesn't bake in the manual paste)

Replace `initiator.targetInfo` paste with a **coordinator + a source-side supervisor**
(NOT an init-container — init-containers block all app containers incl. the source
status sidecar, and would hang the AWX readiness gate when source is deployed first):
- The **launch playbook pre-creates** the coordinator **ConfigMap** in the `mxl`
  namespace. RBAC: the **view SA** may `get/create/patch/update` that one ConfigMap;
  the **source SA** may `get/list/watch` it.
- `view` (target) **patches** the ConfigMap with its `target-info`, keyed by flow id +
  an **epoch** = target **pod UID + start-timestamp/resourceVersion** (not just flow id).
- `source` runs a **supervisor sidecar/process-manager**: the pod starts immediately
  (status sidecar reports "waiting for view"), the supervisor **watches** the ConfigMap
  and **(re)starts the `mxl-fabrics-demo --target-info <blob>` process** when target-info
  first appears and **whenever the epoch changes** (target restart → new target-info).
  `--target-info` is read once at process start, so re-attach = **restart the process**,
  done by the supervisor — not by editing a ConfigMap under a running process.
- **Tolerates either deploy order** (source-first: supervisor waits; view-first:
  target-info already present). The epoch guards against stale target-info colliding
  across retries/redeploys.

## 5. Cleanups folded into M1.1

- Fix stale **`eth1` → `eth0`** in the catalog summary.
- **MXL flow-domain GC** (`mxlGarbageCollectFlows()`, ADR-0017) in the teardown playbook.
- **MXL Flows view:** discover the two fixed-pool sidecars via env wiring (no secrets in
  git); Prometheus optional/deferred. **Plus** the small `mxl.py` tweak to hide
  unreachable endpoints (§3.4) so the page shows true 0→1→2, not 2 offline cards.
- **Status sidecar on both roles** (preview only on `view`) so the source node appears
  in MXL Flows from the moment it deploys.

## 6. Why this is minimal

- One chart (parameterized), not two; **no `dmf-cms` deploy-path change** (one small
  MXL Flows view tweak only); **no** catalog operator. The genuinely new surface is
  **one** generic launch + **one** generic teardown playbook (copied from nmos-cpp)
  + four JTs (default vars) + two catalog YAMLs + a `role` switch + the
  coordinator-ConfigMap and source supervisor.
- It still delivers the user's 0→1→2 independent-deploy story and a restart-safe flow.

## 7. codex review folded in (2026-06-01)

Codex (session `019e81f6`) verdict: *"core shape is sound… no ADR-0027 reconciler
required."* Corrections applied: supervisor sidecar, not init-container (§4); restart
the source process on epoch change — `--target-info` is read-once (§4); two-release-safe
Helm names (§3.1); status sidecar on both roles (§3.1, §5); small `mxl.py` hide-unreachable
tweak for true 0→1→2 (§3.4); explicit coordinator RBAC + richer epoch (§4); one generic
launch/teardown playbook + four JT-default-var sets, not four playbooks (§3.3); placement
by label selector, not nodeName (§3.2).

## 8. Open questions — resolved + remaining

Resolved by the review:
- Two entries (not one combined release) — the 0→1→2 goal wins; surface kept low via
  one generic playbook + four JT default-var sets.
- Coordinator = ConfigMap (playbook pre-creates; view patches) + source supervisor.
- Placement = label selector `dmf.io/mxl-demo-role`, not nodeName.

Remaining (decide at implementation):
- **Supervisor mechanism:** a small shell wrapper watching the ConfigMap (`kubectl get
  -w` / poll) that exec-restarts `mxl-fabrics-demo`, vs a tiny purpose-built process
  manager. Lean: shell wrapper in the same image.
- **`mxl.py` hide-unreachable tweak** scope — confirm it's an acceptable small view
  change (it is not the deploy path).

## 9. Implementation status (2026-06-01) — handshake PROVEN on the local cluster

Built + verified on the local 2-node Lima k3s cluster (`dmf-media/dev/lima/`),
**image-rebuild-free** (scripts shipped via chart ConfigMap mounts; off-the-shelf
`alpine/k8s` kubectl sidecar). Commits on `feat/mxl-spike` (dmf-media):
`3c6c6bc` chart role-param + two-release-safe · `b081fcd` view publisher + RBAC ·
`a3a2664` source supervisor.

**As-built handshake** (matches §4 with the no-rebuild refinement):
- **view**: target writes its `Target info:` line to a shared scratch file; a
  **kubectl sidecar** patches coordinator ConfigMap `mxl-coordinator` with
  `target-info` + `epoch` (`<pod-uid>:<timestamp>`). RBAC: SA `mxl-view`, Role scoped
  `resourceNames:[mxl-coordinator] verbs:[get,patch]`. All `eq .Values.role "view"`.
- **source**: mounts `mxl-coordinator` read-only + **`optional: true`** (so source-first
  works); a supervisor script waits for `target-info`, launches
  `mxl-fabrics-demo -i … --target-info "$(cat /coordinator/target-info)"`, and
  **relaunches on epoch change** (`--target-info` is read-once). All `eq .Values.role "source"`.

**Verified:** source 5/5 Running (no crashloop), view 4/4; flow `Active: true`, head
index advancing (`53356226853 → …227158` in 8 s) → real cross-host tcp grains over
`lima0`; **restart-safe** (deleted view pod → new epoch → source relaunched → flow
resumed). Coordinator CM pre-created manually for the test (launch playbook owns it
in the catalog version).

## 10. M1.1 COMPLETE (2026-06-01) — authored end-to-end, core proven live

The full console-deploy chain is built and validated to the extent possible without
a live cluster's AWX:

- **chart** (dmf-media) — role-parameterized, two-release-safe, restart-safe coordinator
  handshake, host/k3s/zone status sidecar. **Proven GREEN on the local 2-node k3s**:
  cross-host fabrics tcp flow, head advancing, restart-safe.
- **two catalog entries** (`mxl-videotestsrc`, `mxl-videotest-view`, `eth0`) — `8cf793c`;
  load as `CatalogEntry`.
- **generic launch + teardown playbooks** (dmf-runbooks `feat/mxl-spike` worktree) —
  `7d9e8b9`; **run clean against the live cluster** (idempotent re-deploy, pods Ready,
  flow uninterrupted). Pre-create shared coordinator CM; teardown removes it only when
  last release. (Local Helm 4.x → playbooks use raw `helm upgrade --install` CLI; works
  in the AWX EE too.)
- **four AWX job templates** (dmf-infra awx-integration) — `cfad127`; role/release/iface
  defaults; syntax-checked.
- **view** (dmf-cms) — true 0→1→2, real Alibaba Cloud icon, full DMF 6-layer teaching
  grid backed by live data.

**The ONE remaining gap (needs a real cluster):** the `CMS deploy button → AWX JT →
playbook` trigger — no AWX locally. First thing to verify when a cluster is next stood
up. Everything up to and including the playbooks is locally proven.

Branches: all on `feat/mxl-spike` (dmf-media, dmf-cms, dmf-infra, dmf-runbooks,
dmf-platform).
