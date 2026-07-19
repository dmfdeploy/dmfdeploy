---
status: active
date: 2026-07-16
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/202
---
# DMF L3 Run Preflight and Rollback Plan (2026-07-16)

> **STATUS: ACTIVE — spec/plan only, no implementation.** This is the deliverable
> of umbrella [#202](https://github.com/dmfdeploy/dmfdeploy/issues/202)
> ("L3 — run preflight (capacity budget) + rollback to pre-run state"). It is the
> **hard gate for all v0.2b live runs**: the multi-source switch spec
> ([#201](https://github.com/dmfdeploy/dmfdeploy/issues/201)) §8 states *no live
> multi-source J1 run happens before #202's preflight + rollback land*. This doc
> defines the contract the build work must honour; **no code lands under it**. It
> is gated by codex before push, then feeds the work packages in §7.

## 0. What this is, and what it is not

**Is:** the durable design for two operational-safety mechanisms wrapping a
catalog/lifecycle **run** on the single-node lane —
- **(a) Preflight** — before a deploy, measure the node's request budget against
  what the run would add, and **refuse** (operator-overridable, gated + audited)
  when it will not fit, with a **legible budget report**;
- **(b) Rollback** — return the three mutated surfaces (**NetBox records/tags**,
  **Helm releases**, **monitor targets**) to their **pre-run state** when a run
  fails partway.

**Is not:** a scheduler, a cost/quota system, node elasticity, or a generalised
admission controller. It does not change what a run *does*; it gates *whether* a
run starts and *cleans up* when one breaks. It is single-node, single-facility
scoped (the standing lane); the shapes are N-source and N-facility *aware* (they
consume the #201 `topology_params` contract) but the enforcement target is the
one standing facility.

**Motivating data (verbatim origin, MXL revival plan §7 capacity note + #202):**
the full demo menu (nmos-cpp registry + 2 mock nodes + nmos-crosspoint + the MXL
pair + mxl-hello) hit **96% CPU requests on a 3-CPU node**, AWX EE job pods went
**unschedulable** (`Insufficient cpu` → inventory-sync worker-stream death → JT
"Previous Task Failed"). The presentable-journey scenario (2×src + viewer +
crosspoint) is **exactly that shape** — a J1 live run sits at the budget ceiling,
and N>2 breaches it. Preflight exists to turn that silent, corrupting overrun into
a legible up-front refusal; rollback exists because the live env already carries
residue when a run dies mid-flight.

**Acceptance gate (verbatim, #202):** *a deliberately over-budget launch is
refused with a legible budget report; a killed mid-run deploy can be rolled back
to a clean pre-run state (NetBox + Helm + monitoring all verified).*

## 1. Framing and prior decisions this plan is bound by

L3 does not re-litigate settled contracts; it consumes them. The binding ones:

- **#201 switch spec §8 (HARD GATE) + §3 (`topology_params`).** L3 is the gate #201
  defers to. The `topology_params` set (§3: `sources[]` × per-source requests,
  `viewer`, `target_facility`) is preflight's **demand input**; `target_facility`
  is the **capacity scope** preflight budgets against (§3.4 table, L3 row). L3
  owns the check; #201 owns the parameter shape. **Do not re-specify the schema.**
- **ADR-0037** — Media Workload instances are NetBox `ipam.Service` records; git
  catalog owns definitions; k3s owns runtime; **flows stay runtime-only, never in
  NetBox**. Rollback's NetBox surface is the instance records + their tags, never
  flows.
- **ADR-0046** — a Media Workload is a `workload:<slug>` tag-derived grouping;
  **launchers must preserve non-owned tags** so `workload:*` survives a deploy
  (hard prerequisite). **Rollback inherits this rule verbatim**: rollback must
  restore *owned* state without stripping non-owned tags a human or another run
  placed. This is the single most dangerous way a naive rollback corrupts state.
- **ADR-0032** — launchers mutate NetBox via the **scoped writer service account**
  (`dmf-catalog-svc`), never the admin token; **lifecycle tags are pre-created at
  bootstrap**. Rollback writes go through the *same* scoped writer, and rollback
  **never deletes the pre-created tag definitions** — only the per-instance record
  or its tag *associations*.
- **ADR-0038** — monitoring is **NetBox-driven + continuous reconcile** (PromSD
  `http_sd` off-cluster; `prometheus.io/*` annotations + Prometheus kube-SD
  in-cluster). This is a **pull model** — see §4.3; it materially shrinks the
  rollback surface.
- **ADR-0010** — `bin/run-playbook.sh` is the only sanctioned Ansible entry;
  rollback is actuated as a **sanctioned playbook**, not an ad-hoc script.
- **ADR-0043** — scale-to-zero is an availability action scoped to AWX only. It is
  **why AWX is asleep at rest** and why a live run needs a wake — preflight must
  budget for AWX being **awake** during the run (§3.3 the EE headroom rule).
- **ADR-0028 (C5)** — every consequential write carries actor + effective role +
  request_id + reason + outcome. The preflight **override** and the rollback
  **trigger** are both C5-audited writes (§3.4, §4.5).

## 2. Definitions — what a "run" is, and its three mutated surfaces

A **run** = one catalog/lifecycle **deploy** of a topology (one or more catalog
instances) driven from the console: `POST /api/catalog/{key}/deploy` →
`_run_deploy_operation` → AWX launch → launcher playbook → Helm + NetBox +
annotations. For J1 a run instantiates the `topology_params` topology (2×source +
viewer). "**Pre-run state**" is the observable state of the three surfaces
*immediately before* that run's first mutation.

The **three rollback surfaces** (the acceptance gate's "NetBox + Helm +
monitoring"), and their ownership:

| Surface | What a run creates/mutates | Owner of the truth | Rollback primitive |
|---|---|---|---|
| **NetBox** | one `ipam.Service` record **per catalog key** (created at provision) + the **owned** tags `dmf-catalog` / `app:<key>` / `exposure:*` / `lifecycle:*` / `monitoring:probe` + monitoring custom fields (`cluster_service`/`cluster_namespace`/`cluster_port`/`probe_module`/`probe_path`); **`workload:*` is NOT launcher-stamped** — it is externally owned and only *preserved* (ADR-0037/0046/0038) | NetBox (via the scoped writer, ADR-0032) — catalog-launcher **mutations** use **raw `ansible.builtin.uri` REST**, not `netbox.netbox` modules (`nb_inventory` is used only for AWX inventory reads) | **finalise** reverts the `lifecycle:*` tag to `lifecycle:bootstrapped` + nulls monitoring fields + drops `monitoring:probe`, **but never deletes the record**; a *run-created* record needs an explicit DELETE (new work, §4.2). Scoped-writer only; tag writes go through `merge_owned_tags` so **non-owned tags survive** |
| **Helm** | one release **per source** + viewer release; MXL releases named by `mxl_function_key` (`mxl-videotestsrc`, `mxl-videotest-view`) in ns `mxl`; nmos-cpp/nmos-crosspoint in ns `nmos` | k3s / Helm | `helm uninstall` (idempotent), enumerated by the run's release-name set — reuse the existing `teardown-*.yml` plays |
| **Monitoring** | **no direct target writes** — targets are *derived* from the NetBox record's `monitoring:*` tag + custom fields (PromSD `http_sd`) and from `prometheus.io/*` annotations (kube-SD) | Prometheus + PromSD reconcile, TTL ~45s + Prom http_sd ~30s (ADR-0038) | **derived detach** — follows NetBox monitoring-field clear + Helm-uninstall; L3 *verifies* drain, does not imperatively delete (there is no PromSD deregister API) |

The asymmetry in the last column is the core design finding and shapes §4. Note the
**lifecycle model**: there is **no `ipam.Service.status` active/offline field** — the
lifecycle is carried entirely in the `lifecycle:*` **tag** (provision →
`lifecycle:bootstrapped`, configure → `lifecycle:active`, finalise →
`lifecycle:bootstrapped`).

## 3. §a/§b — Preflight

### 3.1 Where preflight runs — decision: **two-tier — the launcher first-play is the AUTHORITATIVE fail-closed gate (the single chokepoint every run passes through); the console is the EARLY operator-facing gate that refuses before AWX is consumed**

Both tiers are required, and their roles are distinct — the earlier draft's
"console is authoritative, launcher is secondary" framing was **wrong**, because
(a) the console cannot make the "hard gate for ALL runs" claim true (a direct
`run-playbook.sh` launch never touches the console), and (b) the console has no
k8s client (§3.2), so it cannot be the source of the in-cluster snapshot rollback
depends on (§4.1). The corrected split:

- **AUTHORITATIVE — launcher first play (the enforcement point on *every* entry
  path).** Console→AWX→launcher **and** direct `run-playbook.sh`→launcher both pass
  through the launcher's first play. It alone runs in-cluster with kube access, so
  it is the only site that can (1) **capture the pre-run 3-surface snapshot** (§4.1)
  and (2) **recompute the capacity budget in-cluster** — the *same*
  requests-vs-allocatable + EE-reserve math the console tier runs (§3.2), against
  live node/pod state it reads directly. It **fails the play (refuses) on NO-FIT**
  and on a **missing/absent budget declaration** (§3.2 fail-closed), **unless** the
  explicit `l3_override` override is present (§3.3), which it honours and **loudly
  logs**. Because the launcher **recomputes** rather than trusting any passed-in
  verdict, this tier is the acceptance-gate guarantee — it makes L3 a gate on
  **every** run, and no forged input can bypass it.
- **UX + AUDIT — console deploy handler, before AWX is consumed.** The gate in
  `api_catalog_deploy` (`main.py:1567`), **after** `entry`/`jt_name` resolve
  (`main.py:1588`/`main.py:1592`) and **before** `get_or_create`/dispatch (async)
  or the inline `launch_job` (sync, `main.py:1649`), computes the same budget via
  `prometheus.query()` (§3.2) and **refuses before any AWX side effect**. It is
  **not** the authority (the launcher recomputes authoritatively); its value is
  three things the launcher cannot give:
  1. **Refuse before AWX is consumed — the console tier's *unique* protection.** The
     revival failure is *AWX EE pods unschedulable* — once the launch reaches AWX the
     damage (wedged inventory-sync, "Previous Task Failed") is done. The launcher
     **cannot** prevent this on AWX paths: it runs *inside* the EE pod, so if the EE
     pod can't schedule the launcher never runs. So the console tier is the **only**
     thing that prevents the original 96% EE-unschedulable failure on console paths
     (§3.2 accounting table) — not a UX nicety. The launcher stays authoritative for
     **workload** fit; the console tier is authoritative for **EE schedulability**.
  2. **The operator interaction + C5 audit** — the legible report (§3.2) and the
     reason-gated override (§3.3), reusing
     `_require_min_role`/`_require_reason`/`_audit_awx_write`. A console refusal is a
     clean 409 with a report, not a failed AWX job.
  3. **It stamps the run envelope** (§4.1) — request_id + verdict, for **correlation
     and audit only** (see the provenance note below).

**On the run envelope — provenance only, nothing trusts it (codex R2).** The
envelope (request_id + preflight verdict + override flags, defined in §4.1) is
**correlation and audit context, not an authority token.** The launcher does **not**
trust a passed-in verdict — it **recomputes** the budget itself (above), so forging
or omitting the envelope buys **audit misattribution, not a capacity bypass**. This
is stated as the threat model deliberately: there is no "signed console override" and
no trust distinction between a console-stamped and a self-minted envelope at the
enforcement point.

**Override — exactly one mechanism, honoured and logged by the launcher on every
path.** An operator overrides a NO-FIT / missing-budget refusal with two extra_vars:
`l3_override=true` + `l3_override_reason=<non-empty>`. The **launcher itself honours
them and loudly logs the override + reason + run-id in the play output on every
entry path** — never silent, never unattributed at the enforcement point. A
**console-originated** override sets the *same* vars and **additionally** carries the
console-side C5 audit trail (operator gate + reason + request_id, §3.3). A **direct**
`run-playbook.sh` caller **can** override — that is the sanctioned ADR-0010 operator
escape — and it is still logged with its reason at the launcher. The trust boundary
for direct runs is ADR-0010 (who may invoke `run-playbook.sh` at all), not a token.

**Rejected: console-only** (breaks the all-runs claim; can't snapshot in-cluster).
**Rejected: a new admission webhook / controller** — out of scope, generalises
beyond the single-node lane, and #202 is operational safety, not a scheduler.

> **WP1 build note (2026-07-19) — kill switch + fail-closed dependency.** The
> console tier ships with exactly one **documented, default-on kill switch**:
> `l3.enabled` (env `DMF_CONSOLE_L3_ENABLED`, Helm `l3.enabled`). Disabling it
> is an explicit operational exception — the deploy proceeds with an audited
> `capacity-skipped` C5 outcome and a `l3_preflight_verdict: skipped` envelope
> (still carrying `l3_request_id`, so launcher-side refusals stay correlatable).
> The parser is fail-safe-on: only the explicit disable tokens
> `false`/`0`/`no` (case-insensitive) disable; `true`/`1`/`yes`/unset enable;
> any other token logs loudly and stays enabled. **Prometheus being
> unconfigured while the tier is enabled is NOT a skip** — it is a fail-closed
> `budget-unavailable` refusal (KSM/Prometheus is a hard dependency of this
> tier, per §3.2); the same refusal covers any query failure, malformed or
> non-positive/non-finite metric values, and **empty allocatable or
> liveness-sentinel families** (`kube_node_status_allocatable`,
> `kube_pod_info`, `kube_pod_status_phase`, and an empty bound∩running
> intersection). Empty *demand* families (app/init/overhead requests) are
> legitimately sparse — best-effort pods declare nothing — and are not
> refused. No data never reads as fit.

### 3.2 What preflight measures — decision: **node allocatable vs (sum of existing pod requests + the run's incremental requests), CPU and memory, with an EE-headroom reserve**

Preflight computes, for the run's `target_facility` node(s):

```
headroom      = node.allocatable(cpu,mem)  − Σ requests(running/pending pods on the node)
run_demand    = Σ over topology_params.sources[]  of per-source chart requests(cpu,mem)
              + viewer chart requests(cpu,mem)
              + (optional visible-only add-ons in the run, e.g. nmos-crosspoint)
ee_reserve    = the AWX EE job pod's requests (the run is driven by an AWX job;
                the EE pod must remain schedulable — this is the revival failure)
verdict       = FIT        if  run_demand + ee_reserve ≤ headroom   (both cpu AND mem)
                NO-FIT      otherwise
```

**`ee_reserve` is entry-path-specific — the launcher must NOT double-count its own
EE pod (codex R3 P1).** The launcher first-play executes **inside the AWX EE pod**
on catalog runs — by the time it runs, that pod is *already scheduled and already
in `existing demand`*. Adding `ee_reserve` again there would double-count and
spuriously flip a console-FIT into a launcher-NO-FIT with **zero real drift**. And
structurally, the launcher **cannot** prevent EE-unschedulability on AWX paths — if
the EE pod can't schedule, the launcher never runs at all. So the **console tier is
the only thing that prevents the original 96% failure mode (EE unschedulable) on
console paths** — that is its *unique* protection, not a mere UX nicety; the
launcher stays authoritative for **workload** fit. Accounting per entry path:

| Entry path | Where the check runs | `ee_reserve` | Why |
|---|---|---|---|
| **Console (AWX)** — pre-launch | console handler, EE pod not yet scheduled | **reserve the future EE pod** | the EE pod is *about to be* scheduled; reserving it is what prevents the 96% EE-unschedulable failure |
| **Launcher (AWX)** — in the EE pod | launcher first-play, inside the running EE pod | **0 (incremental)** | its own EE pod is already in `existing demand`; reserving zero incremental is simpler than and equivalent to exclude-self-then-reserve, and reads live state directly |
| **Direct `run-playbook.sh`** — SSH ansible, no AWX | launcher first-play, no EE pod involved | **0** | the run is not AWX-driven; a direct run does **not** reserve headroom for hypothetical future AWX work (out of L3 scope) |

**Divergence-report path (codex R3 P2-1).** A launcher-NO-FIT (including the
expected console-FIT-then-launcher-NO-FIT case) must surface to the operator
**legibly, not die in a play log**: the launcher writes the same structured budget
report (§3.4) to **job stderr**, correlated by the run envelope's `request_id`
(§4.1) so the console/operator can tie the failed AWX job back to the originating
request. The refusal is auditable via that request_id, not silent.

**Where the console tier's supply numbers come from — decision: reuse the shipped
read-only `prometheus.query()` against kube-state-metrics; do NOT add a Kubernetes
client to the console.** The dmf-cms backend has **no k8s client** (`pyproject.toml`
deps are fastapi/itsdangerous/PyYAML/uvicorn; no `kubernetes`/`kubectl`/`allocatable`
usage in `src/`). The seam to cluster capacity is `src/dmf_cms/prometheus.py`
`query()` — an instant PromQL client **already in production use** for the media-
workloads panels (`main.py:1273-1291` cpu/mem/restarts/pvc; `media_workloads.py:231,
355`), which is exactly why reusing it (rather than adding a kube client) is the
low-risk path. The console tier computes its budget from kube-state-metrics
expressions (see the PromQL contract below) via `prometheus.query()`, gated by
`settings.prometheus.configured` — keeping the console k8s-free ("writes NetBox
only, never k3s", `main.py:1945`), zero new dependency. The **launcher tier** (the
authoritative one, §3.1) applies the *same contract* directly in-cluster (live kube
reads). The two tiers use one contract but are **not guaranteed to agree** —
Prometheus scrape lag vs live kube reads, and real state change between the
pre-launch check and the in-EE recompute, mean a **console-FIT can become a
launcher-NO-FIT**. That is an **expected, honest final refusal**, not a bug (see the
divergence-report path below).
- **Hard dependency this creates (flagged):** kube-state-metrics must be a
  Prometheus scrape target for the *console* tier. **Decision:** WP1 verifies it is
  scraped and adds it if not — **not** a k8s client in the console. (The launcher
  tier does not depend on kube-state-metrics; it reads node/pod state directly.)

**PromQL contract for existing demand (codex P2-1) — the console tier.** "Already
requested" is **not** a naive global sum. It is the sum of container resource
requests over pods **bound to the target node**, `Running` **or** `Pending`
(a node-bound pending over-request still consumes schedulable budget), joined to
the node via `kube_pod_info{node="…"}` — **not** all `Pending` pods globally (an
unschedulable-elsewhere pod must not be charged to this node). Per pod the demand
mirrors the scheduler's own accounting: for sequential init containers, the
per-resource **maximum of any single init request vs the sum of app-container
requests** — never an init-container *sum* — with restartable (sidecar) init
containers accounted cumulatively per their newer semantics; **plus** pod
`overhead` when present. (Corrected 2026-07-18, codex WP0 round 3 — the original
wording here said `max(Σ init, Σ containers)`, which is not what the scheduler
computes.) CPU and memory computed independently. The launcher tier applies the
same accounting against live pod specs.

> **WP1 build note (2026-07-19) — the console tier is a conservative UPPER
> BOUND, not scheduler-exact.** kube-state-metrics does not expose init
> containers' `restartPolicy`, so the console cannot distinguish sequential
> inits (scheduler takes the highest single init vs the app sum) from
> restartable sidecars (accounted cumulatively). The console tier therefore
> charges each existing pod `Σ app-container requests + Σ init-container
> requests + overhead` — the upper bound of both semantics. This deliberately
> over-counts sequential inits, biasing toward refusal (fail-closed); it can
> produce a console-NO-FIT that the launcher's scheduler-accurate recompute
> (WP3, live pod specs) overturns — the expected divergence path of §3.1
> already covers that. `kube_pod_overhead_*` metrics carry no `node` label;
> the console filters them through the node's eligible pod set instead.

**Fail closed on absent budget declarations (codex P1-2) — load-bearing.** Verified
shipped reality: the `mxl-fabrics-demo` chart templates declare **no container
`resources.requests`** (the only `resources:` keys are RBAC rules), and the AWX EE
Container Group `pod_spec_override` declares **no worker resources**. A budget check
that summed those would compute `run_demand == 0` and `ee_reserve == 0` and
**false-pass the over-budget acceptance test**. Therefore:
- **(a) Preflight REFUSES with a `missing-budget` report** (distinct from NO-FIT)
  when any run-managed chart container or the EE pod lacks a **parseable CPU *and*
  memory request**. Fail-closed — the same posture applied everywhere else. It does
  **not** assume zero and pass.
- **(b) EE requests absent/zero → treated as *unavailable* → the configured
  conservative EE floor applies** (extends OQ1) rather than reserving nothing.
- **(c) A prerequisite WP declares the requests** — MXL chart container requests
  (dmf-media) + EE Container Group resources (dmf-infra). Named as **WP0** (§7) with
  its own gate, because **the acceptance test cannot pass until it lands**.

Decisions embedded here:
- **Requests, not limits, not usage.** k3s scheduling admits on **requests**; the
  revival failure was `Insufficient cpu` at schedule time (a requests decision).
  Live *usage* is irrelevant to schedulability and is explicitly not the metric.
- **EE headroom is a first-class reserve, not an afterthought.** The revival data's
  actual victim was the AWX EE pod. Because a run is AWX-driven and AWX is awake
  during it (ADR-0043), preflight must reserve the EE job pod's requests (or the
  §3.2(b) floor when unavailable) or it will green-light a run that strands its own
  executor. This is the single non-obvious measurement rule and the reason a naive
  "sum the charts" check would still reproduce the 96% failure.
- **CPU and memory both** — either breaching is NO-FIT (the 3-CPU node is CPU-bound
  today, but the check is symmetric so a memory-bound lane is covered).
- **Per-source requests come from the chart**, keyed by `len(topology_params.
  sources)` — the check is **N-source shaped** (source count × per-source request),
  never a literal 2 (§5). Once WP0 lands the chart's declared requests are the
  authority for per-source demand; an under-declaration is a chart bug L3 surfaces
  (via §3.2(a) fail-closed), not something L3 silently tolerates.

> **WP0 build note (2026-07-18).** The console tier cannot read chart values (no
> Helm/OCI reader in dmf-cms — it loads only the mounted catalog YAML), so WP0
> also added the **`provision.resources.requests` demand profile** to the mxl
> catalog entries: the aggregate *effective* demand of the entry's rendered
> workload (steady-state container sum + pod overhead, × replicas; the CI gate
> refuses initContainers fail-closed until scheduler-accurate init accounting
> is deliberately added), in a fail-closed grammar (whole millicores; whole
> binary Ki/Mi/Gi), equality-gated against the chart render by dmf-media's
> `bin/check-catalog-demand.py` in CI. This is the concrete form of §5's
> "demand computable from the catalog entry"; WP1 consumes it. Canonical field
> definition: `docs/architecture/DMF Function Catalog Model.md` §2. Sizing note:
> the initial values are lean placeholders — no honest sizing fits the
> documented node state today; umbrella **#258** (live scheduling proof +
> platform-request audit) is the authority on fit and gates chart publish and
> the J1 demo.

### 3.3 Refuse vs warn — decision: **refuse by default (fail-closed), operator override with reason**

- **Default: refuse.** A NO-FIT verdict **blocks the launch** and returns the
  budget report (§3.2 numbers) with HTTP 409-class semantics — *not* a silent warn.
  Fail-closed matches #201's "refused with a legible budget report" acceptance and
  the platform's fail-closed posture (§3.4 `target_facility` validation, the
  secret gates).
- **Override: one mechanism (`l3_override=true` + `l3_override_reason`), honoured
  and logged at the launcher; the console adds a C5 audit on top.** The launcher is
  the enforcement point and honours the two override extra_vars on **every** entry
  path, loudly logging override + reason + run-id (§3.1) — there is no separate
  "console override" concept and no launcher "stand-down on a trusted flag". What
  the **console** tier adds when the operator overrides from the UI is the
  *audit + gating*, reusing the deploy path's own authority (not a new gate):
  - gated by `_require_min_role(request, "operator")` — the same gate the deploy it
    overrides already uses (`main.py:1574`); a plain viewer cannot override;
  - requires `_require_reason` (400 `reason-required` before anything else,
    `main.py:140`) — which becomes `l3_override_reason`;
  - mints `request_id = uuid.uuid4().hex` and emits the **C5 quartet** via
    `_audit_awx_write(..., outcome="capacity-override")` (actor + effective role +
    real_role-under-view-as + request_id + reason + the budget numbers);
  - passes `l3_override=true` + `l3_override_reason` in the launch `extra_vars`.
  So a console override is C5-audited *and* launcher-logged; a direct override is
  launcher-logged (the ADR-0010 escape, §3.1). (The console gate is `operator`, not
  #201 §7's stricter `_require_media_workloads_access`, because L3 wraps the
  **deploy** path, whose shipped gate is `operator`; matching the wrapped action is
  the consistent choice. A refusal emits `outcome="capacity-denied"`.)

### 3.4 The legible budget report shape (what the operator sees on refusal)

On NO-FIT the console returns a structured, human-first report — the acceptance
gate's "legible budget report". Shape (fields illustrative, values from §3.2):

```
Launch refused — capacity budget exceeded on facility <target_facility>.

Node budget (<node-name>, single-node lane)
  allocatable:      CPU 3000m   MEM 5726Mi
  already requested: CPU 2100m   MEM 3900Mi   (12 pods)
  headroom:          CPU  900m   MEM 1826Mi

This run would add
  mxl-videotestsrc × 2   CPU  700m   MEM 1024Mi
  mxl-videotest-view     CPU  300m   MEM  512Mi
  nmos-crosspoint        CPU  200m   MEM  256Mi
  AWX EE job pod (rsv)   CPU  500m   MEM  512Mi
  ─────────────────────  ─────────  ─────────
  run demand + reserve   CPU 1700m   MEM 2304Mi

Verdict: NO-FIT — CPU short by 800m (need 1700m, have 900m).

To proceed anyway an engineer must re-launch with an override and a reason
(audited). To fit without override: finalise a running workload first
(e.g. the largest current instance), then retry.
```

Design intent: it names the **facility**, shows **supply / existing demand /
headroom / incremental demand / the shortfall**, calls out the **EE reserve**
explicitly (so the operator understands the AWX-executor coupling), and states the
**two ways forward** (audited override, or finalise-then-retry). It never dumps
raw kubectl. It carries no cluster IPs / node internal addresses beyond the node's
display name (public-safety, §6). The same numbers (as data) back the API response
so the frontend can render its own view; the text block is the canonical legible
form for logs + the runbook.

## 4. §c — Rollback

### 4.1 How pre-run state is captured — decision: **the LAUNCHER first-play captures the snapshot in-cluster (the console cannot — it has no k8s client), persisted as a run-scoped ConfigMap keyed by the run envelope's request_id (console) or a self-minted run-id (direct)**

Rollback must return surfaces to *pre-run* state, which means knowing that state.
The earlier draft had the **console** capture the snapshot at preflight time —
**that is impossible** and is corrected here: the console has no k8s client (§3.2),
so it cannot observe the Helm surface at all, and a direct `run-playbook.sh` run
never reaches the console. **Capture is therefore a launcher first-play
responsibility** — the launcher is the one actor that runs in-cluster on *every*
entry path and can see all three surfaces. It captures, immediately after the
capacity recompute and **before the first mutation**, a snapshot of:

- **NetBox snapshot** — the set of `ipam.Service` records (by `name`==catalog key /
  `cluster_service` identity, ADR-0046) + their tags/`lifecycle:*` state that exist
  for this topology *before* the run. Distinguishes "the run created this record"
  (rollback DELETEs it, §4.2) from "this record pre-existed" (rollback reverts its
  `lifecycle:*`/monitoring state, never deletes).
- **Helm snapshot** — `helm list` in the workload namespace(s) *before* the run
  (release names + revisions). The run's releases = post-run − pre-run; rollback
  uninstalls exactly those.
- **Monitoring snapshot** — the PromSD `/sd/*` + Prometheus active-target set
  attributable to this topology *before* the run (for **verification** only, §4.3;
  monitoring has no independent restore primitive).

**The run envelope (defined here — the one place; referenced elsewhere).** The
envelope is the run's correlation/audit context — **provenance only, trusted by
nothing** (§3.1): `request_id` (console-minted or launcher-self-minted for direct
runs), the console preflight `verdict`, and the override flags
(`l3_override`/`l3_override_reason`). A **console run** threads it into the launch
`extra_vars`; a **direct `run-playbook.sh` run** has no envelope, so the launcher
**self-mints a `run_id`** and proceeds. Either way a snapshot is captured, so direct
runs stay **rollbackable** — the "all runs" guarantee (§3.1) covers cleanup, not
just the gate — and the launcher's recompute (§3.1) is the authority regardless of
what the envelope claims.

**Persistence + lifecycle — an in-cluster run-scoped ConfigMap (codex P2-1).** The
launcher writes the snapshot (small structured JSON) to a run-scoped ConfigMap
`dmf-run-<run_id>` in the workload namespace (idiomatic alongside `mxl-coordinator`),
carrying:
- **labels** `dmf.io/run-id`, `dmf.io/facility` (= `target_facility`),
  `dmf.io/topology` (catalog key/topology name), `dmf.io/owner` (console subject or
  the direct caller identity);
- **fields** `created_at`, the three-surface snapshot, and a **terminal `status`**
  (`in-progress` → `rollback_complete` | `run_complete` | `failed_rollback_required`
  | `rollback_incomplete`).
- **Retention:** the ConfigMap lives **only while a rollback could still run.** On
  `run_complete` (clean success, nothing to roll back) or `rollback_complete` it is
  **deleted or marked closed**; it is retained while `failed_rollback_required` /
  `rollback_incomplete` so an operator retry has its pre-run state.
- **Staleness invariant (load-bearing):** a **later run on the same facility
  invalidates earlier snapshots** — a subtractive diff against a stale snapshot
  would corrupt the *newer* run's state. So rollback **refuses a `closed`/stale
  snapshot** (one superseded by a newer run_id on the same facility, or already
  marked terminal) with a `stale-snapshot` report, and — because the facility lock
  (§4.5) is held for at most one live run — a valid rollback **acquires the facility
  lock before acting** (§4.5), guaranteeing no concurrent run is mutating the
  surfaces it is reconciling.

**Missing-snapshot posture (codex R1) — refuse, never guess.** If rollback is asked
to run for a run whose snapshot ConfigMap is absent (e.g. the launcher died *before*
first-play capture), rollback **refuses with a `no-snapshot` report** naming the
run-id and the surfaces it cannot safely reconcile — it does **not** fall back to a
blind teardown (which would delete pre-existing records/releases and violate
ADR-0046's preserve-non-owned rule). With no snapshot there is no safe subtraction,
so the honest action is manual escalation.

### 4.2 NetBox rollback — build on the teardown/finalise plays, with one added primitive

The existing prior art is the three **`teardown-*.yml`** plays + each role's
**finalise** stage (there is no `finalise-*.yml`/`rollback-*.yml` today). Finalise
PATCHes the record back to `lifecycle:bootstrapped`, nulls the monitoring custom
fields, and drops `monitoring:probe` — via **raw `ansible.builtin.uri` REST**. The
catalog launchers' NetBox **mutations** use raw REST, **not** `netbox.netbox`
modules (the `netbox.netbox.nb_inventory` plugin *is* used, but only for AWX
dynamic-inventory **reads** — dmf-infra `awx-integration`); rollback must therefore
replicate REST PATCH/DELETE, not a module's `state: absent`.

- **The one gap finalise does not cover — DELETE of a run-created record (NEW WP3
  work).** Finalise **never deletes** the `ipam.Service`; it only reverts tags. But
  "pre-run state" for a record the run *created* is *absent*. So the §4.1 snapshot
  diff drives two paths:
  - **record pre-existed** → rollback = finalise semantics (revert to the snapshot's
    `lifecycle:*` + monitoring state). No delete.
  - **record created by this run** → rollback = finalise **then DELETE**
    `/api/ipam/services/{id}/` via the scoped writer. This DELETE is the single
    piece of rollback that is *not* in the shipped teardown path and is called out
    as new WP3 work.
- **Scoped writer only (ADR-0032).** All NetBox mutation goes through the scoped
  catalog writer service account; rollback never touches the admin token and never
  deletes the bootstrap-precreated `lifecycle:*` tag *definitions* (only per-record
  associations / the record itself).
- **Preserve non-owned tags (ADR-0046, hard rule) — reuse `merge_owned_tags`.** The
  owned namespace is exactly `dmf-catalog`, `app:`, `exposure:`, `lifecycle:`,
  `monitoring:` (`roles/netbox_catalog_common/defaults/main.yml`). Every tag-array
  PATCH is a **full replace**, so any rollback that writes `tags` **must** run the
  same `roles/netbox_catalog_common/tasks/merge_owned_tags.yml` +
  `filter_plugins/netbox_tags.py` the launchers use, or it destroys externally
  owned `workload:*` tags. The existing `tests/tag-preservation.yml` (asserts
  `workload:videotest` survives all three stages) is the regression the rollback
  path must also pass.

### 4.3 Monitoring rollback — decision: **derived detach + verify, no imperative delete**

Because ADR-0038 monitoring is a **pull/reconcile** model, monitor targets are not
independently created state — they are a projection of (NetBox tags + K8s
annotations):

- **Off-cluster (probe/http_sd) lane — the one the MXL/nmos launchers use.** PromSD
  emits probe targets from the NetBox `ipam.Service` record's `monitoring:probe`
  tag + its `cluster_service`/`cluster_namespace`/`cluster_port`/`probe_module`/
  `probe_path` custom fields. The **removal lever is the finalise clear** (§4.2:
  null the five custom fields + drop `monitoring:probe`) — after which PromSD's
  full-recompute refresh (`PromSDCache.refresh`, TTL default **45s**) stops emitting
  the target, and Prometheus drops it on its next `http_sd` pull (`refresh_hint`
  default **30s**). **No separate L3 promsd call** — there is no deregister API or
  cache-invalidation endpoint, only the TTL loop.
- **In-cluster (scrape) lane** — where `prometheus.io/*` annotations are used, they
  live on the Pod/Service the Helm release owns; `helm uninstall` (§4.4) removes
  them → kube-SD drops the target. **No L3 action.**

So L3's monitoring rollback is **verification, not mutation**: after §4.2 + §4.4,
L3 confirms the run's targets have drained from PromSD `/sd/*` and from Prometheus
active targets. This is the honest posture: "monitoring returned to pre-run state"
= the derived targets are gone, verified against the §4.1 snapshot, **not** a claim
that L3 deleted them. **Staleness caveat (stated so it is not a surprise):** there
is a bounded lag (~45s PromSD TTL + ~30s Prom SD refresh ≈ up to ~75s) between the
§4.2 clear and target drain; verification polls until drained or a timeout (then
reports `monitoring-drain-pending`, §4.6 — a soft state, not a rollback failure).

### 4.4 Helm rollback — idempotent uninstall of the run's release set

- Enumerate the run's releases = post-run − pre-run (§4.1 Helm snapshot). For J1
  that is **one release per source** (`mxl-videotestsrc`, `mxl-videotest-view`, in
  ns `mxl`) + any add-on (`nmos-crosspoint` in ns `nmos`). Release name =
  `mxl_function_key` (`roles/mxl/defaults/main.yml`); this is also the
  `cluster_service` custom-field value, so releases and NetBox records share the
  key.
- **Reuse the shipped `teardown-*.yml` plays** — they already `helm uninstall`
  tolerating "release: not found" (idempotent, re-runnable), and
  `teardown-mxl-fabrics-demo.yml` also removes the shared `mxl-coordinator`
  ConfigMap **only when the last `mxl-*` release is gone** (`kubernetes.core.k8s
  state: absent`). This idempotent convergence is exactly what the revival plan
  hardened after AWX job #164 stranded a record between `helm uninstall` and the
  NetBox finalise (dmf-runbooks#12). Rollback wraps these, scoped to the run's
  release set — it does not reinvent teardown.
- **Console never runs helm itself** (invariant: console writes NetBox only, never
  k3s — `main.py:1945`). The Helm uninstall runs in the **launcher/AWX** rollback
  play (WP3), triggered by the console command (WP2), mirroring how deploy launches
  AWX rather than touching k3s directly.

### 4.5 Concurrency lock + rollback trigger + idempotency + partial-failure posture

- **Enforced single-run-at-a-time — a facility-scoped run lock (codex P2-2).** The
  snapshot-diff model is only sound if no *other* run mutates the facility between
  snapshot A and run A's rollback. The shipped console dedupe is action+target only
  (`get_or_create(action, target)`) — it does **not** prevent two *different*
  topologies running on one node concurrently. So L3 **enforces** one run per
  `target_facility` at a time via a facility-scoped lock. The **authoritative** lock
  is **in-cluster and launcher-acquired** (before snapshot capture); a second run on
  a locked facility is **refused** (`facility-busy`), not queued, for J1; rollback
  also acquires it before acting (§4.1).
  - **The console check is ADVISORY only, from console-local run state — never a k8s
    read (codex P2-2).** The console may refuse early using *its own in-flight run
    record* (the same source as its existing `get_or_create` dedupe) to give the
    operator a fast `facility-busy`, but it does **not** read the ConfigMap/Lease
    (that would breach the no-k8s-client invariant, §3.2). The real lock semantics
    live entirely in the launcher (WP3); the console (WP2) only **surfaces** launcher
    outcomes (`facility-busy` / `no-snapshot` / `stale-snapshot`) back to the
    operator. A run that slips past the advisory console check still hits the
    authoritative launcher lock and is refused there.
  - **Atomic acquisition (load-bearing).** Acquisition **must** be atomic —
    a **create-only** ConfigMap (a 409 `AlreadyExists` = lock held; **never**
    `apply`/upsert, which would silently steal a held lock) **or** a
    `coordination.k8s.io` **Lease** with `resourceVersion` compare-and-swap. The
    lock record carries a **holder identity** (`run_id` + owner) and a **TTL**.
  - **Stale-owner posture.** A lock is reclaimable **only past its TTL** (a crashed
    holder's lock expires and the TTL-expiry path recovers it); within TTL the lock
    is honoured even if the holder looks idle. This is the same lock shape as the
    dmf-init manage-lock work (create-only + holder + TTL-expiry recovery). This is
    a **blocking WP2/WP3 gate**, not an operator courtesy.
- **Trigger.** Rollback is invoked (a) automatically when a run reaches
  `failed_rollback_required` (the #201 `SwitchSourceCommand` status has this exact
  terminal state; the deploy path gets the analogous "deploy failed partway"
  terminal), or (b) explicitly by an operator via an audited console action
  (reason-gated, C5 — same authority as deploy/override). Rollback itself is a
  **sanctioned playbook** (ADR-0010) carrying the run's `request_id` + snapshot.
- **Idempotency (hard requirement).** Every rollback step is idempotent: helm
  uninstall of an absent release = ok; NetBox finalise of an already-offline record
  = ok; monitoring verify is read-only. Re-running rollback converges — this is
  what lets an operator safely retry a rollback that itself was interrupted (the
  exact AWX-job-#164 residue class the revival plan hit).
- **Partial-rollback-failure posture — fail loud, converge on retry, never
  false-green.** If a rollback step fails (e.g. NetBox unreachable mid-rollback),
  rollback **stops and reports which surfaces are clean and which are still dirty**
  (per-surface status against the §4.1 snapshot), leaving the run in an explicit
  `rollback_incomplete` state with the residue named. It does **not** report
  success while a surface is dirty. Because steps are idempotent, an operator
  re-runs rollback and it completes the remaining surfaces. This mirrors the
  audit/verify discipline elsewhere (a POST-400 that might be "already done" is
  re-read and asserted, not assumed).

### 4.6 What "clean pre-run state" verification means (the acceptance gate)

The acceptance gate requires "a clean pre-run state (NetBox + Helm + monitoring all
verified)". L3 verifies each surface against the §4.1 snapshot:

| Surface | "Clean" = | Verified by |
|---|---|---|
| **NetBox** | run-**created** records DELETEd; pre-**existing** records reverted to snapshot `lifecycle:*` + monitoring state; **`workload:*` and other non-owned tags intact** | scoped-writer read-back of the topology's records (by `name`==catalog key / `cluster_service`) vs snapshot |
| **Helm** | the run's release set is uninstalled; pre-run releases untouched | `helm list -n {mxl,nmos}` vs snapshot |
| **Monitoring** | the run's targets have drained from PromSD `/sd/*` + Prometheus active targets (within the ~75s window) | read-only poll of PromSD + Prometheus vs snapshot, bounded wait |

A rollback is **complete** only when all three verify clean; otherwise
`rollback_incomplete` with the dirty surface named (§4.5).

## 5. §d — Relationship to the v0.2b `topology_params` contract

L3 is a **consumer** of #201 §3's contract, not a co-author of it:
- **Preflight demand input** = `topology_params.sources[]` (count × per-source
  chart requests) + `viewer` + any visible-only add-ons in the run. Source count is
  `len(sources)` — **N-source shaped**, never a literal 2 (the same hard constraint
  #201 §3.3 puts on every layer).
- **Capacity scope** = `topology_params.target_facility` (the #201 §3.4 table's L3
  row: the facility whose node budget preflight budgets against). J1 has one legal
  facility; L3 budgets that node. When #231's Design surface later drives N
  facilities, L3's scope parameter already exists — no schema change (the same
  "survives the actuator/Design upgrade unchanged" discipline).
- **Provenance rule respected** — L3 reads `topology_params` as it arrives over the
  launch seam (#201 §3.2); it does **not** re-author or re-shape it. If the seam
  does not yet carry `extra_vars` (F2 today), preflight's demand for a *catalog-
  defined* topology is still computable from the catalog entry the console is about
  to launch; L3 does not block on WP3a but composes cleanly with it once it lands.

**Non-duplication (explicit, #201 §8):** #201 states the capacity requirement and
defers enforcement to L3; this plan is that enforcement and does **not** re-specify
the parameter schema, the switch actuator, or the console switch surface.

## 6. Public-safety, identity, and audit posture

- **No cluster/tailnet IPs, node internal addresses, or env slugs** in the budget
  report, the API response, the snapshot JSON, or any committed artifact — node
  **display name** only; concrete values stay operator-local (repo convention,
  gitleaks + scrub gates). The report is demo-surface-visible, so it is written to
  the same public-safety bar as the console.
- **Every L3 write is C5-audited** (ADR-0028): the preflight override and the
  rollback trigger both emit actor + effective role + request_id + reason +
  outcome. Preflight *evaluation* (the read) is not a write and is not gated, but a
  refusal and an override are recorded.
- **Scoped identities only** (ADR-0032): rollback's NetBox writes use
  `dmf-catalog-svc`; no admin token, no new machine identity introduced.

## 7. §e — Work packages, acceptance gates, and v0.2b-blocking split

Spans three repos. **The v0.2b-blocking core is preflight-refusal + rollback-verify;
the polish is deferrable.** Each WP names its repo and gate.

| WP | Repo | Work | v0.2b? | Gate |
|----|------|------|--------|------|
| **WP0 — Declare resource requests (PREREQUISITE)** | dmf-media + dmf-infra | Declare container `resources.requests` (CPU+mem) on the `mxl-fabrics-demo` chart workloads (dmf-media) **and** worker resources on the AWX EE Container Group `pod_spec_override` (dmf-infra). **Without this the budget computes zero and the over-budget acceptance test cannot pass** (§3.2 P1-2). | **Blocking (gates all others)** | codex + render/dry-run showing non-zero requests |
| **WP1 — Console early preflight tier + envelope (backend)** | dmf-cms | Early capacity gate in the deploy **handler** (after `entry`/`jt_name` resolve `main.py:1588/1592`, before dispatch): budget via the in-use `prometheus.query()` over kube-state-metrics with the §3.2 PromQL contract, **reserving the FUTURE EE pod** (§3.2 table — this is the tier's unique protection against the 96% EE-unschedulable failure); **`missing-budget` refusal** on absent declarations (§3.2 P1-2); NO-FIT refusal with the structured report (§3.4); its verdict is **advisory** (the launcher recomputes authoritatively); audited override via `_require_min_role("operator")` + `_require_reason` + `_audit_awx_write` passing `l3_override`/`l3_override_reason`; **stamps the provenance-only run envelope** (request_id + verdict; §4.1) into `extra_vars`. Verify kube-state-metrics is scraped. | **Blocking** | codex + backend-test (over-budget → NO-FIT report; absent-decl → missing-budget; fitting → launches) |
| **WP2 — Advisory lock check + rollback command (backend)** | dmf-cms | **Advisory** early `facility-busy` from **console-local run state only** (never a k8s read of the ConfigMap/Lease — §4.5 P2-2; the authoritative lock is WP3); **surfaces** launcher outcomes (`facility-busy`/`no-snapshot`/`stale-snapshot`) to the operator; `RollbackRunCommand(run_id, reason)` with the `failed_rollback_required` auto-trigger + audited manual trigger; **triggers the launcher rollback play (never runs helm/k3s itself)**; verifies clean (§4.6). | **Blocking** | codex + backend-test (advisory refusal uses no k8s read; launcher outcomes surfaced) |
| **WP3 — Launcher first-play (authoritative) + rollback play** | dmf-runbooks (+ dmf-infra JT) | First-play: **atomically acquire the facility run-lock** (create-only/Lease-CAS + TTL, §4.5), **recompute capacity in-cluster fail-closed** on every entry path with **entry-path `ee_reserve` (AWX-path incremental = 0, no double-count of the executing EE pod; direct = 0)** (§3.2 table), **honour+loudly-log the `l3_override`/`l3_override_reason` extra_vars** and write the divergence report to job stderr correlated by request_id (§3.1/§3.2); **capture the 3-surface snapshot to the run-scoped `dmf-run-<run_id>` ConfigMap** with its lifecycle labels/status (§4.1, self-minting a run-id for direct runs); rollback play **wrapping the shipped `teardown-*.yml`** scoped to the run's release set (§4.4) that also **DELETEs run-created `ipam.Service` records** via raw `uri` REST + the scoped writer (§4.2), reusing `merge_owned_tags` so `workload:*` survives; **refuses stale/closed/missing snapshots** (§4.1). | **Blocking** | codex + `ansible-playbook --syntax-check` + render/dry-run + `tests/tag-preservation.yml` + **no-double-count check** (AWX-launched run: console-FIT → launcher-FIT when nothing changed) + **state-drift sim** (console-FIT → launcher-NO-FIT surfaces legibly) |
| **WP4 — Monitoring drain verification** | dmf-cms (+ dmf-promsd read) | Read-only verify that the run's targets drain from PromSD `/sd/*` + Prometheus active targets within the reconcile window (§4.3/§4.6); report monitoring-drain-pending on timeout. | **Blocking** (verify is part of the gate) | codex + backend-test (targets gone after rollback) |
| **WP5 — Legible report polish + runbook wiring** | dmf-cms (frontend) + umbrella | Frontend rendering of the budget report + finalise-then-retry affordance; wire the L3 gate into the demo runbook (#203) and **delete §8 rough-edges row for the capacity precheck** once landed. | Deferrable | codex + design-review |
| **WP6 — Preflight for the *switch* path** | dmf-cms | Extend preflight to the `SwitchSourceCommand` reconfigure (a switch re-points, adds ~0 net requests, but a re-point that restarts the viewer briefly double-books — decide budget treatment). | Deferrable (switch is coarse-reconnect; low delta) | codex |

**Blocking vs deferrable rationale.** The acceptance gate (§0) needs exactly:
**WP0** (or the budget is zero and the over-budget test cannot fail) + refusal-with-
report (WP1) + rollback-to-verified-clean across all three surfaces (WP2+WP3+WP4).
Those are v0.2b-blocking — #201 §8's HARD GATE will not lift without them. WP5
(frontend polish, runbook row deletion) and WP6 (switch-path preflight) improve
legibility and completeness but are not on the critical path; they can follow.

**Sequencing.** **WP0 lands first** — it is the frozen input every budget check
reads (an unblocked WP1 against undeclared requests is untestable). WP1
(console early tier + envelope) and WP2 (run-lock + rollback command) are the
backend spine. **WP3 is the authoritative tier** — the launcher first-play that
captures the snapshot, enforces the lock, runs the fail-closed recompute, and hosts
the rollback play; WP1's envelope and WP2's command both terminate in it. WP3 can
proceed in parallel behind the WP2 command contract + the envelope shape. WP4
depends on WP3 (targets drain only after Helm/NetBox rollback). WP5/WP6 follow.

**Dependency on #201.** L3's preflight *demand* reads cleanest once #201 WP3a lands
the `extra_vars` seam, but L3 does not block on it (§5): for a catalog-defined
topology the demand is computable from the catalog entry. L3 **must land before or
with** the v0.2b switch demo (#201 §8).

## 8. Open questions (flagged, not deferred where decidable)

1. **EE reserve sizing** — the exact CPU/mem to reserve for the AWX EE job pod.
   *Decision:* once WP0 declares EE Container Group resources, read the real
   number from the pod/pod_spec_override; when absent/zero (§3.2(b)) fall back to a
   conservative configured floor rather than reserving nothing. **Operator-level
   knob:** the floor value.
2. **Reconcile-window timeout for monitoring drain** — how long L3 waits for target
   drain before reporting `monitoring-drain-pending`. *Decision:* bounded to the
   PromSD poll interval × a small factor; **operator-tunable**, defaulted from the
   PromSD scrape/poll config, not hard-coded blind.
3. **Multi-run concurrency** — two runs overlapping on one node (snapshot A taken
   before run B's mutations). *Decision for J1:* **enforced**, not confirmed — a
   facility-scoped run lock refuses a concurrent run (`facility-busy`, §4.5/WP2)
   before snapshot capture. A queue/reservation model for multi-facility
   concurrency is a **future L-tier item**, not v0.2b.
4. **Preflight for scale-to-zero interactions (ADR-0043)** — if AWX is asleep at
   preflight time, the EE reserve must account for the wake that the run itself
   triggers. *Decision:* preflight assumes AWX **awake during the run** (it must be,
   to drive the job) and reserves the EE pod accordingly; the wake cost is the EE
   reserve, already counted. No separate knob.

## 9. References

- Umbrella issues: [#202] (this plan), [#201] (switch spec — §3 `topology_params`,
  §8 HARD GATE), [#200] (presentable journey), [#189] (v0.2 scope), [#203]/PR #237
  (demo runbook), [#231] (Design beat v1).
- Plans: `DMF v0.2b Multi-Source Switch Spec 2026-07-15.md` (§3, §8);
  `DMF v0.2 EBU Facility-Orchestration Re-anchor Plan 2026-07-07.md` §5 (L3 origin,
  v0.2a acceptance items 5); `DMF MXL Single-Node Revival Plan 2026-07-03.md` §7
  (the 96%-CPU capacity note + the hardened idempotent finalise, dmf-runbooks#12).
- ADRs: ADR-0037 (instances = NetBox `ipam.Service`; flows runtime-only),
  ADR-0046 (Media Workload = `workload:<slug>` grouping; **preserve non-owned
  tags**), ADR-0032 (scoped NetBox writer `dmf-catalog-svc`; lifecycle tags
  pre-created), ADR-0038 (NetBox-driven monitoring, pull/reconcile — derived
  detach), ADR-0010 (`run-playbook.sh` sanctioned entry), ADR-0043 (scale-to-zero
  availability, AWX-only — EE-awake reserve), ADR-0028 (C5 reason-gated audit).
- Shipped seams (build hooks), verified 2026-07-16:
  - `dmf-cms` — deploy handler `api_catalog_deploy` (`src/dmf_cms/main.py:1567`) →
    `_run_deploy_operation` (`main.py:340-425`) → `launch_job` (`src/dmf_cms/awx.py:117`);
    gates `_require_min_role` (`main.py:101`), `_require_media_workloads_access`
    (`main.py:119`), `_require_reason` (`main.py:140`), audit `_audit_awx_write`
    (`main.py:161`); precedent write `api_media_workloads_clear` (`main.py:1938`,
    "writes NetBox only, never k3s" `main.py:1945`); capacity seam
    `prometheus.query()` (`src/dmf_cms/prometheus.py:45`, **already in production
    use** — `main.py:1273-1291`, `media_workloads.py:231,355`); **no k8s client**
    (`pyproject.toml`).
  - `dmf-runbooks` — `playbooks/launch-*.yml`; `playbooks/teardown-mxl-fabrics-demo.yml`,
    `teardown-nmos-cpp.yml`, `teardown-nmos-crosspoint.yml` (idempotent helm
    uninstall + coordinator cleanup); role finalise stages
    `roles/{mxl,nmos-cpp,nmos-crosspoint}/tasks/finalise.yml` (PATCH lifecycle→
    bootstrapped + null monitoring, **no record delete**); tag preservation
    `roles/netbox_catalog_common/tasks/merge_owned_tags.yml` +
    `filter_plugins/netbox_tags.py` + `tests/tag-preservation.yml`; catalog-launcher
    **NetBox mutations** via raw `ansible.builtin.uri` REST (no `netbox.netbox`
    module for writes; `netbox.netbox.nb_inventory` used only for AWX inventory
    reads, dmf-infra `awx-integration`).
  - `dmf-infra` — `…/awx-integration/defaults/main.yml` (JT defaults).
  - `dmf-promsd` — `/sd/{scrape,probe,snmp}` http_sd (`src/dmf_promsd/main.py:80-90`);
    tag selectors `src/dmf_promsd/sd.py:8-10`; TTL-recompute cache
    (`src/dmf_promsd/cache.py:26,62-103`) — pull model, no deregister API.

[#189]: https://github.com/dmfdeploy/dmfdeploy/issues/189
[#200]: https://github.com/dmfdeploy/dmfdeploy/issues/200
[#201]: https://github.com/dmfdeploy/dmfdeploy/issues/201
[#202]: https://github.com/dmfdeploy/dmfdeploy/issues/202
[#203]: https://github.com/dmfdeploy/dmfdeploy/issues/203
[#231]: https://github.com/dmfdeploy/dmfdeploy/issues/231
