---
status: active
date: 2026-06-18
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/97
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

**Spike, on a disposable AWX, before any code change** — patch the CR web/task replicas → 0.
**Hardened acceptance (codex 2026-06-19): it is not enough to see the Deployments hit 0
once.** Prove all of:
- (a) both web+task Deployments settle at 0 and **stay** there;
- (b) the AWX CR `.status.conditions` stay healthy across **more than one reconcile
  interval** (operator not looping on a web-pod wait timeout);
- (c) operator logs stay quiet across that window — no failing reconcile;
- (d) an **operator restart** does not wake AWX or start a loop;
- (e) `0 → 1` returns web/task/API cleanly;
- (f) `1 → 0` **after an unrelated no-op CR apply** does not trip the
  `roles/installer/tasks/resources_configuration.yml` web-pod wait loop;
- (g) the normal DMF AWX role never reapplies resource changes while desired replicas are 0.

**Record the evidence concretely** (in this doc or the PR description, not as a recap) so a
future agent can tell operator-native-by-design from a lucky live workaround: exact
operator/chart version (`appVersion 2.19.1` / chart `3.2.1`), the literal CR patch applied,
before/after web+task Deployment replicas and AWX CR `.status.conditions` snapshots, the
operator log window, the operator-restart result, and the `0→1→0` transition timings — all
on the Pi 4 / 8 GB arm64 node.

Steady-state knob: prefer **`web_replicas:0` / `task_replicas:0` with
`*_manage_replicas: true`** (the operator renders `spec.replicas` from them and holds it,
reconcile-safe). **`manage_replicas:false` + direct Deployment scaling is a *rejected
fallback*** — it creates split desired state and makes the helper the AWX replica controller,
i.e. exactly the hack this design avoids — used **only** if Phase 0 proves CR-zero impossible.
**Do not set born-asleep in the sandbox profile until this passes.**

### Live evidence (2026-06-19, env `2czo-i1d1`, RPi 4B / 8 GB arm64)

Captured during a real `dmf-init` bootstrap (post-#93 bundle, NetBox right-sizing holding) —
seeds the Phase-0 evidence and confirms the problem framing:

- **AWX is the floor even right-sized.** Per-container resident: `awx-task` 939 MiB,
  `awx-web` 665 MiB + a 166 MiB rsyslog sidecar, `awx-task` rsyslog 166 MiB,
  `awx-operator/awx-manager` 141 MiB. The CR already carries `uwsgi_processes: 2` +
  `web/task_resource_requirements` (#93), reconcile-safe — so the worker-pool lever is spent;
  awake AWX ≈ 2 GB is the floor.
- **Operator reconcile loop is a CPU hog.** `awx-manager` sat pegged at its 500m CPU cap.
  Scaling the *operator* deploy to 0 (web/task left up — API-only work needs no operator)
  dropped 1-min load **25.8 → 11.3** immediately. (Operational bring-up expedient only — not
  the permanent design; the permanent design keeps the operator and uses CR replicas.)
- **The failures were ingress-collateral, not AWX bugs.** Under load (load 26–50 on 4 cores,
  ~50 MiB free, swap engaged), liveness probes timed out cluster-wide and **Traefik restarted**
  → `*.sslip.io` calls got `Errno 111`. `configure` died at a *different* ingress task each
  re-run (NetBox `694`, then AWX `693`) — motivating §E as its own workstream.
- **Aside (separate bug, not this plan):** NetBox v4.5 v2-token mint crashed once with
  `value too long for character varying(12)` (`users/models/tokens.py`); track separately.

## Approach

### A. Thin taxonomy ADR (umbrella, RFC → ADR ≈0043)
Names *workload scale-to-zero* (this work, out-of-band) vs *node elasticity* (AWX-actuated,
deferred) vs *cost guardrail* (deferred); holds the narrow boundary above; defines the
reusable seam — *"scale a named workload to/from zero on demand"* — **without** building an
actuator. Cross-links the deferred Elastic Media Nodes plan and the committed NetBox + AWX
control loop (ADR-0013/0025/0037/0038). **The ADR must say explicitly (codex 2026-06-19):
AWX remains the catalog/workflow actuator under ADR-0013 / ADR-0025 / ADR-0037; the helper
changes AWX *availability* only — never job semantics, never media workload policy.**

### B. `awx-autoscale` helper (dmf-infra) — the cluster-scaling authority
- **`POST /ensure-awake`:** idempotently patch the AWX CR (per the Phase 0 knob), wait for
  `awx-web` Ready + API 200. Record `min_awake_until` (a wake lease).
- **Single-flight + durable lease (codex 2026-06-19).** Store `min_awake_until` / active wake
  ownership in a **Kubernetes `Lease` (or ConfigMap)**, not only in process memory, so
  concurrent dmf-cms clicks **collapse into one wake**. On helper restart, **fail *open*
  toward keeping AWX awake** until active work can be observed — never toward sleeping.
- **Idle-reaper loop:** query active work with the **proven DMF pattern**
  `status__in=new,pending,waiting,running` (NOT `status=running,pending,waiting`, which
  drops `new` and uses the wrong separator); cover **unified work** — jobs, workflow jobs,
  project updates, inventory updates — not just `/api/v2/jobs/`. Sleep only when there is no
  active work **and** `now > min_awake_until` **and** idle > `grace_period`. **If the AWX API
  cannot be queried, do not sleep.**
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
- **`awx-presence` role / state machine (codex 2026-06-19).** Model AWX presence as an
  **explicit `state: awake|asleep`** invoked at **phase boundaries** — *not* born-asleep, and
  *not* scattered task-level lazy gates. The bootstrap lifecycle is **1 → 0 → 1 → 0**:
  1. **640 installs AWX awake**, and the `awx-manage` admin-password `kubectl exec` sync
     **stays inside that awake window** (born-asleep breaks both the upstream operator's
     web-pod wait and our role's `readyReplicas ≥ 1` exec — keep it as a convergence step;
     do **not** redesign it to a direct DB mutation).
  2. **Sleep AWX for the non-AWX configure work.** These plays don't touch the AWX API and
     were starving on a constrained node while AWX ate ~2 GB: `191` zot OIDC, `692` forgejo
     bootstrap, `691` netbox-sot, `694` born-inventory (**order `694` before `693`** so NetBox
     inventory content exists before AWX integration), `160` promsd, `696` cms-authentik-api,
     `698` cms netbox/forgejo tokens.
  3. **One explicit AWX-awake window** for the AWX consumers: `693-awx-integration`,
     `697-cms-awx-token`, and the AWX/CMS smoke.
  4. **Sleep at the end** if the sandbox/on-demand flag is set; steady state then runs via the
     helper (§B).
  Use the presence role at boundaries, not as hidden per-task magic.
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

### E. Discriminating ingress readiness/retry gate (dmf-infra) — INDEPENDENT of AWX

**This is the fix that actually stops the mid-bootstrap failures** (codex 2026-06-19). Sleeping
AWX removes the *pressure source*, but `configure` tasks still call app APIs through
`*.sslip.io` → Traefik, so a Traefik liveness-flap under load still throws `Errno 111
Connection refused` at whatever task coincides with it (observed live: NetBox `694` "Create
worker device role", then AWX `693` "Lookup AWX project" — different task each re-run). Ship
this **as its own workstream**, not bundled into the AWX presence change.

- **Shared precondition gate** before external app-API calls: assert the **Traefik route is
  live** *and* the **target app health/API is ready**, then proceed.
- **Discriminating + bounded retry:** retry **only** on transient classes — connection-refused
  (Errno 111), timeouts, and 5xx — with bounded backoff. **Hard-fail immediately on 4xx, auth,
  and schema errors** so the gate cannot mask real integration bugs.
- **Internal-service access is NOT a host-side DNS swap.** The node runs the Ansible `uri`
  tasks and **cannot resolve `*.svc.cluster.local`.** Where a task moves off ingress, make the
  execution context **explicit**: (a) run the call from an in-cluster helper/runner pod, (b)
  `exec` into the known app pod where that's the established local pattern, or (c) keep ingress
  and wrap it with the shared route + target-readiness gate. **Never** just rewrite host-side
  `uri` hosts to service DNS.

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
- **697/698 reorder regression (codex 2026-06-19):** with `698` (cms netbox/forgejo tokens)
  in the asleep window and `697` (cms-awx-token) in the AWX-awake window, the dmf-cms runtime
  Secret must **merge keys and recompute the rollout checksum order-independently**, clobbering
  neither token. Assert both orders.
- **Ingress gate (§E):** under induced load (AWX awake + concurrent reconcile), a Traefik
  liveness-flap mid-`configure` no longer fails the run — the gate retries transient
  111/timeout/5xx and the phase completes; a genuine 4xx/auth/schema error still fails fast.
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
- **Status as of 2026-06-19:** **scheduled — `status: active`, tracking issue
  [dmfdeploy/dmfdeploy#97](https://github.com/dmfdeploy/dmfdeploy/issues/97).** Design captured
  and cross-checked by codex (gpt-5.5) via agent-bridge against awx-operator 2.19.1 source +
  DMF code in **two passes** (2026-06-18 P1/P2/P3 + 2026-06-19 `awx-presence` state machine,
  hardened Phase-0 evidence, the independent §E ingress gate, 697/698 reorder test, Lease
  single-flight/fail-open, ADR-0043 boundary) — all folded in. **Live evidence** added from a
  real Pi 4 bootstrap (env `2czo-i1d1`). Implementation is being orchestrated by the
  **claude-top** agent running the issues-cruncher trio (qwen = implementer, codex =
  adversary) on a shared worktree; nothing implemented yet at time of writing.
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
