---
status: draft
date: 2026-06-18
---

# DMF AWX On-Demand Scale-to-Zero Plan (v0.2)

> **Milestone: v0.2.** Status `draft` = design captured, not yet scheduled. When this work
> is picked up, the first step is to open the umbrella tracking issue, flip `status: active`
> and add `tracking_issue:`, then run Step 1 (the Phase 0 feasibility spike) before any
> other code. This doc is self-contained: a freshly-cleared agent should be able to resume
> from it alone (see **Resume guide** at the end).

## Context

An 8 GB Raspberry Pi 4B (USB3 SSD) sits on the documented floor for the full DMF sandbox
stack (`dmf-env/bin/init-wizard.sh` `apply_posture_profile`: `test` = 8 GB min, `sandbox` =
10 GB recommended). **AWX** is the biggest, cleanest RAM lever: ~2.5–3 GiB resident and the
documented OOM source (`bootstrap-sandbox-profile.yml` records an `awx-web` OOMKill at a
1Gi limit), yet it is a *bursty* workload — it runs catalog/workflow jobs then idles.
Scaling AWX to zero when idle and waking it on demand reclaims more RAM than every other
sandbox trim combined, which makes the proof surface runnable on cheap hardware.

**Envisioned UX:** dmf-cms behaviour stays 100% intact. Triggering a catalog item or
workflow auto-wakes AWX in the background, runs the job(s), then sleeps it again after a
grace period — transparent and demand-driven.

**Two hard constraints that shape the whole design:**
1. **Asleep AWX = AWX REST API down**, so a wake must precede the launch and block until
   `awx-web` answers (~1–3 min cold start on the Pi). Wake is on the critical path.
2. **dmf-cms has no Kubernetes access** (deps are only fastapi/uvicorn/pyyaml/itsdangerous),
   so it cannot scale AWX itself — a component with cluster RBAC must do it.

**Strategic framing (decided).** AWX wake/sleep is **not** the deferred media-elasticity
framework — it is the *actuator scaling itself* (AWX can't wake AWX → an out-of-band helper
is required). v0.1 froze elasticity (`docs/decisions/architectural-commitments-v1.md`:
"AWX is the v0.1 actuator… do not build a hybrid framework"). Frame wake/sleep as an
**operational self-preservation primitive for the actuator in constrained single-node
sandboxes** — explicitly **not** media autoscaling, cloud elasticity, or a controller
framework. A thin **taxonomy ADR** (≈`0043`) will record this boundary and cross-link the
deferred *Elastic Media Nodes & Cloud Cost Controller Plan (2026-06-01)*.

## Step 1 (first test step) — Phase 0 feasibility spike ⚠️

This is **the first thing to actually do/test** when implementation starts — a throwaway
spike that gates everything after it.

Confirmed via upstream source (cross-check, 2026-06-18): chart `3.2.1` → operator
appVersion `2.19.1`. The CRD exposes `web_replicas` / `task_replicas` /
`web_manage_replicas` / `task_manage_replicas` (the `manage_*` flags default `true`), and
the web/task Deployments render `spec.replicas` from them — so **patching the AWX CR is the
right control plane.** BUT `roles/installer/tasks/resources_configuration.yml` waits for a
running web pod whenever the applied deployment resources change, and DMF's own
`roles/stack/operator/awx/tasks/main.yml` waits for `awx-web` `readyReplicas >= 1` then
`kubectl exec`s into it to sync the admin password. **A naive born-asleep CR fails both
paths.**

**Spike, on a disposable AWX, before any code change** — patch the CR web/task replicas → 0
and prove:
- (a) both Deployments settle at 0 and **stay** there;
- (b) the AWX CR conditions stay healthy (the operator is not looping on a web-pod wait
  timeout);
- (c) operator logs show no failing reconcile.

Decide the correct steady-state knob (replicas `0` with `*_manage_replicas: true`, vs.
toggling `manage_replicas`). **Do not set born-asleep in the sandbox profile until this
passes.** Fallback if it cannot hold a clean zero: scale the Deployments directly (accept
the operator may re-sync on its reconcile interval), or descope to manual sleep only.

## Approach

### A. Thin taxonomy ADR (umbrella, RFC → ADR ≈0043)
Names *workload scale-to-zero* (this work, out-of-band) vs *node elasticity* (AWX-actuated,
deferred) vs *cost guardrail* (deferred); holds the narrow boundary above; defines the
reusable seam — *"scale a named workload to/from zero on demand"* — **without** building an
actuator. Cross-links the deferred Elastic Media Nodes plan and the committed NetBox + AWX
control loop (ADR-0013/0025/0037/0038).

### B. `awx-autoscale` helper (dmf-infra) — the cluster-scaling authority
- **`POST /ensure-awake`:** idempotently patch the AWX CR (per the Phase 0 knob), wait for
  `awx-web` Ready + API 200. Record `min_awake_until` (a wake lease).
- **Idle-reaper loop:** query active work with the **proven DMF pattern**
  `status__in=new,pending,waiting,running` (NOT `status=running,pending,waiting`, which
  drops `new` and uses the wrong separator); include project updates / all active work, not
  just `/api/v2/jobs/`. Sleep only when there is no active work **and** `now >
  min_awake_until` **and** idle > `grace_period`.
- **Image:** `python:3-slim` lacks FastAPI/uvicorn/the k8s client → either **stdlib-only**
  (`http.server` + raw Kubernetes REST via the mounted SA token over `urllib`; AWX calls via
  `urllib`) or a tiny **owned image** built through the GHCR→Zot pipeline. Either way: pin
  the base **digest**, ensure **arm64**, and **preseed into local Zot** for offline.
- **RBAC / trust boundary:** namespaced Role in `awx` only — `awx.ansible.com/awx`
  get+patch, `apps/deployments` + `pods` get/list/watch. **No `secrets` verbs**; mount the
  AWX token via Secret/ExternalSecret. Add a **NetworkPolicy** restricting callers to the
  dmf-cms SA/labels + an internal **bearer token** on `/ensure-awake`. **Audit-log** every
  wake/sleep. Requires a Security & Secrets review pass.

### C. AWX CR knobs + bootstrap-aware sleep (dmf-infra)
- `roles/stack/operator/awx/defaults/main.yml`: add `awx_web_replicas` / `awx_task_replicas`
  (default `1`) + the `*_manage_replicas` decision from Phase 0.
- `roles/stack/operator/awx/templates/awx-instance.yml.j2`: render them as **explicit
  scalar fields** (NOT via the `to_nice_yaml` resource-requirements dict pattern).
- **Bootstrap vs steady-state:** the sandbox order is `640-awx → 650-dmf-cms →
  693-awx-integration → 697-cms-awx-token → 699-cms-smoke-test` — all AWX API consumers.
  AWX must stay **awake through bootstrap**; sleep happens only at the very end, after the
  wiring and the helper are deployed. Born-asleep is a *steady-state* property, not a
  *bootstrap* one.
- `bootstrap-sandbox-profile.yml`: opt-in `dmf_awx_autoscale_enabled`; cloud/lab lanes keep
  replicas `1` and deploy no helper (no behaviour change).

### D. dmf-cms integration (dmf-cms)
- **Wake placement:** ensure-awake must run **before the first AWX read** in each flow —
  wrap the whole `resolve job template → find-active → launch` transaction, not just
  `launch_job()`. Call sites: `/api/workflows/{name}/launch` (calls
  `lookup_job_template_by_name` first; note this endpoint launches **job templates**, not
  workflow JTs) and catalog deploy/teardown (`lookup_*` + `find_active_job_for_template`
  before launch).
- **Cold-start UX:** **block-until-ready for v1.** The async "provisioning" pre-state is a
  backend-contract change (provisional operation id, server-side state, TTL, new status
  endpoints, duplicate-click concurrency) and is deferred. v1 blocks the launch request
  inside ensure-awake up to `max_startup_wait`; **raise the route timeout scoped to the
  dmf-cms launch path only** (a per-route Traefik middleware/annotation — **not** a broad
  ingress timeout change); the UI reuses the existing disabled/spinner states.
- **Settings:** dmf-cms gets `enabled` / `helper_url` / `max_startup_wait` only;
  **`grace_period` lives in the helper.** `DMF_CONSOLE_AWX_AUTOSCALE_*` env, following the
  frozen-dataclass pattern in `settings.py`. Helm values + `deployment.yaml` env injection.

## Repo procedure for the future implementation

Issue-first (one `component:*` + one `workstream:*` label, milestone **v0.2**) → flip this
doc to `status: active` + add `tracking_issue` → RFC → ADR for the taxonomy → **Step 1:
Phase 0 feasibility spike (first test)** → implement on feature branches (DCO `-s`,
conventional commits, **no `Co-Authored-By`**; component-repo PRs reference the umbrella
issue **fully qualified** `Closes dmfdeploy/dmfdeploy#N`) → the final coordinating PR closes
the issue **and** flips this doc to `status: executed` in the same change.

## Verification (for the future implementation)

- Phase 0 holds a clean zero (Deployments stay at 0, operator healthy).
- Helper wake is idempotent and lease-respecting; returns 200 only after `awx-web` answers.
- Reaper never sleeps mid-job or inside the wake lease (checks `new` + project updates +
  all active work).
- Bootstrap completes with AWX awake through `693/697/699`, then sleeps.
- **`699-cms-smoke-test` rescoped** to exercise helper-wake — it currently asserts the
  console can reach AWX to list workflows, which fails on a cold/asleep sandbox.
- dmf-cms cold trigger blocks ~1–3 min (per-route timeout raised) → wakes → runs → succeeds
  → sleeps after grace; duplicate-click idempotency preserved (existing
  `find_active_job_for_template`).
- Lane isolation: cloud/lab (flag off) renders replicas `1`, no helper.
- CI green: `bin/check-docs.sh`, commitlint/DCO, fully-qualified closes.

## Open decisions (carry forward)

- **Cold-start UX:** committed to block-until-ready for v1; async pre-state deferred.
- **Phase 0 outcome** may force a fallback (direct Deployment scaling / manual sleep) that
  changes the dmf-cms integration shape — resolve before building section D.
- **Image:** stdlib-only vs. a tiny owned image — decide at build time.

## Resume guide for a freshly-cleared agent

- **Start here:** read this doc top-to-bottom; it is self-contained. Then skim
  `docs/decisions/architectural-commitments-v1.md` (the v0.1 freeze this framing respects)
  and `docs/plans/DMF Elastic Media Nodes and Cloud Cost Controller Plan 2026-06-01.md` (the
  deferred elasticity track this is explicitly **not**).
- **Status as of 2026-06-18:** design captured; cross-checked by codex (gpt-5.5) via the
  agent-bridge skill against awx-operator 2.19.1 source + DMF code — verdict CHANGES-NEEDED,
  with all P1/P2/P3 findings folded into this doc. Component repos were clean. Nothing
  implemented; no issue/RFC opened yet.
- **Key code touchpoints to re-read before building:** dmf-infra
  `roles/stack/operator/awx/{defaults/main.yml,templates/awx-instance.yml.j2,tasks/main.yml}`,
  `bootstrap-sandbox-profile.yml`,
  `playbooks/{640-awx,693-awx-integration,697-cms-awx-token,699-cms-smoke-test}.yml`;
  dmf-cms `src/dmf_cms/{awx.py,main.py,settings.py}`, `charts/dmf-cms/`.
- **First real step when scheduling:** open the umbrella issue, flip frontmatter to
  `status: active` + `tracking_issue`, then **Step 1 = the Phase 0 feasibility spike (the
  first test)** before any other code.
- **Re-review:** re-run codex on the implementation diffs before the coordinating PR. Its
  stated impl-review focus: Phase 0 evidence, bootstrap/steady-state sequencing, the
  pre-read wake wrapper, reaper lease semantics, and whether the helper auth/NetworkPolicy
  are actually *rendered and verified* (not just specced). Drive it via the operator-local
  agent-bridge binary (`~/.claude/skills/agent-bridge/bin/agent-bridge`); note the role→pane
  map drifts — verify the live `codex` pane before sending.
