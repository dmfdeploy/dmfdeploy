---
status: active
date: 2026-07-15
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/201
---
# DMF v0.2b Multi-Source Switch Spec (2026-07-15)

> **STATUS: ACTIVE — spec before build.** This is the deliverable of umbrella
> [#201](https://github.com/dmfdeploy/dmfdeploy/issues/201) ("v0.2b — multi-source
> videotest topology + launcher source selection + coarse connection-intent
> switch, spec first"). It writes the full v0.2b spec that
> `DMF v0.2 EBU Facility-Orchestration Re-anchor Plan 2026-07-07.md` §5 deferred
> ("full v0.2b spec is written when we start it"). It is **doc only** — no
> implementation lands under this doc; it defines the contract the build work
> must honour. It is gated by codex before push, then feeds the work packages in
> §10.

## 0. What this is, and what it is not

**Is:** the durable design for the missing climax of the presentable journey —
switching one viewer live between **two** test-pattern sources from the console,
with a parameterisation shape that makes a later N-source Design surface cheap.

**Is not:** a live IS-05 switch. The honest v0.2b actuator is a **coarse
reconnect** (re-point the viewer, restart/reconnect it). The `nmos-crosspoint`
IS-05 Connection API path stays **visible-only** and is a tracked follow-on claim
with its own acceptance gate (re-anchor §5, codex P1.1/P3). "Switched via
nmos-crosspoint IS-05" is **not claimed** by this spec.

**Build scope is unchanged by this spec** (operator decision, #201 comment
2026-07-15): J1 stays 2×src + 1 viewer on the single-node lane, L3 gate
([#202](https://github.com/dmfdeploy/dmfdeploy/issues/202)) unchanged. This spec
constrains only the **shape** of the parameterisation the issue already requires.

## 1. Framing

- **North star** (re-anchor §1): two licensed media functions + a switching
  function taken through Design → Plan → Provision → Configure → Operate →
  Finalise, with the viewer switched live via IS-05. v0.2b is the **connection-
  intent** slice of that — the first honest switch, on the coarse actuator.
- **Presentable journey** (#200): the demo runbook (#203, PR #237) currently
  marks *Switch* as the v0.2b placeholder this spec fills.
- **Legibility-only round stands** (#201 comment, 2026-07-15): the 2026-07-07
  legibility-only scope holds for this round. The Design/Plan hexagons stay
  non-interactive in the demo. The obligation this spec carries is narrower: J1
  must expose the topology parameters **cleanly enough that the first honest
  Design surface becomes cheap afterwards** — see §2 (the binding parameter
  contract) and the Design-beat-v1 flag (#231).

## 2. Baseline — the shipped state this spec changes

Three hard facts from the current tree set the whole problem. Each is a place the
"single fixed pairing" is wired in, and each must become parameterised.

**F1 — the flow id is fixed, in two places.** `dmf-media`
`charts/mxl-fabrics-demo/values.yaml:60` hard-codes `flow.id` (`5fbec3b1-…`) and
duplicates the same UUID inside the embedded `flow.json`. Both catalog entries
statically declare the *same* UUID:
`catalog/mxl-videotestsrc.yaml` (`mxl_flows.produces`) and
`catalog/mxl-videotest-view.yaml` (`mxl_flows.consumes`). There is **no** flow-id
or test-pattern parameter anywhere. One chart, role-gated by `role: source|view`
(`templates/initiator.yaml`, `templates/target.yaml`). MXL flows are a local
libfabric transport and are **not** registered in NMOS IS-04/05 or visible in
`nmos-crosspoint` today.

**F2 — the launcher carries no source selection, and the pairing is implicit.**
The catalog `configure.awx_job_template` names a fixed JT
(`media-launch-mxl-videotestsrc` / `-view`). Those JTs
(`dmf-infra/…/awx-integration/defaults/main.yml`) bake **fixed** `extra_vars`
(`mxl_role`, `mxl_release`, `mxl_interface`, `mxl_placement_mode`) — no survey, no
flow id. The playbook `dmf-runbooks/playbooks/launch-mxl-fabrics-demo.yml`
threads only `--set role=… fabrics.interface=… image.tag=… placementMode=…`;
`flow.id` is never set. The console `/api/catalog/{key}/deploy` posts **`body={}`**
to the AWX launch (`dmf-cms/src/dmf_cms/awx.py` `launch_job`) — **no per-launch
extra_vars ever cross from the console.** Source↔viewer rendezvous is **implicit
and runs in the *inverted* direction from the intuitive one** (verified in the
chart templates before writing this): the **viewer** (`role: view`,
`view-handshake.yaml`) is the receiver — it scrapes its own libfabric *"Target
info:"* endpoint plus an `epoch` (`TARGET_POD_UID:start_ts`), and a sidecar
**patches** them into the shared `mxl-coordinator` ConfigMap
(`data.target-info` / `data.epoch`) in namespace `mxl`. Each **source**
(`role: source`, `source-handshake.yaml`) is the initiator — it **waits for**
`/coordinator/target-info`, then starts `mxl-fabrics-demo -i -f <flow.id>
--target-info <…>` **sending its flow toward the viewer**, and stops/restarts
whenever the `epoch` changes. So the **viewer publishes, the sources consume.**
With one source today there is no contention; there is **no `active-source`
concept and no "which source" selector at all.**

**F3 — the console has a proven reason-gated, audited write to model on.** The
media-workloads surface (`dmf-cms` `frontend/src/pages/MediaWorkloads/`:
`index.tsx`, `WorkloadTile.tsx`, `InstanceLiveModal.tsx`, `ClearForDeployment.tsx`)
already carries exactly one consequential write —
`POST /api/media-workloads/{instance}/clear` (`main.py`). It is gated by
`_require_media_workloads_access` (engineer capability **or** `media-engineers`
group; 403 otherwise; enforced on the *effective* user so view-as downgrade
holds — ADR-0037 §5, #185 WP-B), it requires a non-empty `reason` via
`_require_reason` (C5, ADR-0028), and it emits the C5 quartet (actor + effective
role + request_id + reason + outcome) to the dmf-cms log + console-local Activity
lane — **not** into AWX `extra_vars`. Entity model: ADR-0037 (instances are
NetBox `ipam.Service` records; git catalog owns definitions; k3s owns runtime;
flows stay runtime/overlay, never persisted to NetBox) and ADR-0046 (a Media
Workload is a `workload:<slug>` tag-derived grouping; workload lifecycle is
derived provision/configure/operate; observed state is joined by `cluster_service`
identity, not the collapsing `app` label).

The v0.2b build turns F1/F2 from "fixed" into "parameterised by a named contract"
and adds one new write to F3's surface.

## 3. §a — The topology parameter contract (the centerpiece)

**Binding requirement (operator, #201 comment 2026-07-15):** the topology
parameters are a **named, versioned contract**, not incidental plumbing —
*defined once* at the catalog → AWX job template → chart values seam, N-source
shaped, and flagged as the future Design-surface input.

### 3.1 The named set

Define a first-class, versioned schema — the **Topology Parameter Set** (working
name `topology_params`, `schema_version: 1`) — authored **once** in the git
catalog (the definition store per ADR-0037), versioned with the catalog:

```yaml
# Topology Parameter Set — schema_version 1 (illustrative shape; authored in the
# git catalog; rides launch extra_vars as the object; playbook projects to values)
topology_params:
  schema_version: 1
  target_facility: <facility-slug>        # where the topology instantiates
  sources:                                # a LIST, not source_a / source_b
    - id: <source-instance-slug>          # stable per-source identity
      flow_id: <uuid>                     # per-source NMOS/MXL flow id
      pattern: <test-pattern-name>        # per-source test pattern (distinct)
    - id: <source-instance-slug>
      flow_id: <uuid>
      pattern: <test-pattern-name>
  viewer:
    id: <viewer-instance-slug>
    source_selection: <source-instance-slug>   # which source.id the viewer consumes
```

**The four named parameters the issue requires**, mapped to the schema:
1. **source count** — `len(sources)` (derived from the list; never a literal `2`).
2. **per-source identity** — `sources[].id` + `sources[].flow_id` +
   `sources[].pattern`.
3. **viewer source selection** — `viewer.source_selection` (references a
   `sources[].id`).
4. **target facility** — `target_facility`.

### 3.2 The seam — canonical payload, projected once, never re-authored per layer

**Contract boundary (decision, P2-1):** the **AWX launch `extra_vars` carries
`topology_params` as the single authoritative object** — the canonical payload.
The **playbook** derives chart values from it by a mechanical, lossless
projection (iteration over `sources[]` happens in the playbook/chart layer). AWX
**job-template defaults carry NO topology values** — nothing is re-authored per
layer. Provenance rule (stated in-spec): *the catalog authors `topology_params`;
the launch `extra_vars` threads the object unchanged; the playbook projects it to
chart `--set` values.*

```
git catalog (authoritative source — authors topology_params)
    │   topology_params  (the whole named object)
    ▼
AWX launch extra_vars  ──►  carries topology_params AS THE OBJECT
    │                        (JT defaults hold NO topology values)
    ▼
playbook (the projector)  ──►  iterates sources[]; derives per-source flow.id /
    │                           pattern + the viewer's active-source — mechanical,
    │                           lossless, nothing re-authored
    ▼
Helm chart values  ──►  helm --set flow.id=… pattern=… (per source);
    │                    viewer flow.id + coordinator active-source (§4/§5)
    ▼
k3s runtime (reconciled)
```

The projection is **mechanical and lossless** (the earlier "verbatim" wording is
retired): the catalog stays the source of truth, the object rides `extra_vars`
unchanged, and only the playbook flattens it into chart values.

**Consequence for the console→AWX seam (F2).** Today `launch_job` posts
`body={}`, so nothing parameterised can reach a launch. The canonical-payload
contract therefore **requires the launch seam to carry `extra_vars`** — that is
where `topology_params` rides. This is not optional polish: the Design-beat-v1
form (§3.3) *is* a thin console form that posts exactly this object, so the seam
that carries it must exist in J1. J1 authors the object in the catalog and threads
it; the J1 console selects a **catalog-defined** topology (no free-form authoring
yet), but over a seam that already passes the object as data.

### 3.3 N-source shaped, and flagged as the Design-surface input

- **N-source shaped (hard constraint).** `sources` is a list and every layer
  **iterates** over it — **one Helm release per source**, all gated by the **one
  shared `active-source` selector** in the coordinator (§4.1); there is **no**
  per-source coordinator key (the viewer endpoint stays single). There is **no**
  `source_a`/`source_b` special case, no branch that assumes
  exactly two. Going from 2 to N sources costs a longer list, not new code paths
  or new catalog/JT entries. This is the operator's explicit "no hard-coded
  2-source special case where an N-source parameter is the same cost."
- **Design-surface input (flagged).** This set is the declared input to the
  future **"Design beat v1 — template instantiation"** ([#231]): a thin console
  form that drives exactly these parameters and posts them over the seam in §3.2.
  J1 stays honest for that future only if it exposes the set cleanly now.
- **Survives the actuator upgrade (hard constraint).** Like `SwitchSourceCommand`
  (§6), the parameter contract must survive the coarse `reconnect` →
  `nmos-is05` actuator upgrade **unchanged**. The set describes *topology intent*
  (who the sources are, which one the viewer consumes); it does not encode *how*
  the switch is actuated. Swapping the actuator must not touch the schema.

### 3.4 `target_facility` — the minimal J1 seam (so #231 need not rediscover it)

`target_facility` is **passed and validated end-to-end**, even though J1 has
exactly one legal value (the standing single-node lane's facility slug). What it
maps to at each layer:

| Layer | `target_facility` maps to |
|---|---|
| AWX | the job's **inventory / `limit`** — which facility's hosts the run targets |
| k3s | the **namespace + placement** the chart deploys into (today `mxl`, single-node placement) |
| L3 (#202) | the **capacity scope** preflight budgets against (that facility's node budget) |

**J1 validation:** the launcher **validates `target_facility` against the single
legal value** for the standing single-node lane and **rejects an unknown value**
(fail-closed) rather than defaulting or silently ignoring it. One legal value in
J1 — but passed and validated at every layer, so #231's Design surface inherits a
working seam instead of rediscovering it.

## 4. §b — Topology for J1

**J1 build target (unchanged):** `2 × mxl-videotestsrc` (distinct flow ids **and**
distinct test patterns, so the switch is visually unambiguous) + `1 ×
mxl-videotest-view`, single-node lane.

**What changes vs today:**

| Concern | Today (F1/F2) | J1 |
|---|---|---|
| Flow id | single fixed UUID (`values.yaml:60`), shared by both catalog entries | per-source `flow_id` from `topology_params.sources[]` |
| Test pattern | none (writer on/off only) | per-source `pattern`, distinct per source (visible proof) |
| Source count | 1 | `len(sources)` = 2 for J1, list-shaped for N |
| Rendezvous | one viewer publishes `target-info`; the single source consumes it; no contention | viewer **still** publishes `target-info`/`epoch`; an added **`active-source`** selector gates which source transmits (§4.1) |
| Viewer source | fixed (one source, always transmitting) | `viewer.source_selection` → `active-source`; **only the selected source transmits** (§5) |

### 4.1 Selection-gated coordinator model (correct direction)

The shipped direction (F2) is **viewer-publishes / sources-consume**. The
multi-source model **keeps that direction** and adds a *selection gate* — it does
**not** invert it (the naive "each source publishes its own key and the viewer
picks one" model is backwards and is explicitly rejected):

- **The viewer endpoint stays single and published.** One viewer → one receiver
  endpoint. The viewer keeps patching `target-info` + `epoch` into
  `mxl-coordinator` exactly as today. This is **not** keyed per source — there is
  one viewer.
- **The coordinator gains one new field, `active-source`, keyed by the selected
  `sources[].id`** (`data.active-source: <source.id>`). This is the switch intent,
  expressed by source identity.
- **Source supervisors gate on it — NEW WP2 logic.** Each supervisor starts its
  initiator **only when** `active-source == its own source.id` **and**
  `target-info`/`epoch` are present, and — **while the initiator runs** —
  **continuously re-checks** that predicate, **stopping the initiator and parking**
  on mismatch or empty. This is **not shipped**: the shipped supervisor
  (`source-handshake.yaml`, lines 66–99) has **no `active-source` concept** — it
  stops a *running* initiator only on process death or a **non-empty `epoch`
  change** (a cleared `epoch` is ignored by the `[ -s epoch_file ]` guard), and its
  epoch-change restart is **unconditional**. So the entry gate, the continuous
  re-check, **and** gating the epoch-restart on `active-source == self` are all new
  v0.2b work (**WP2**, §10). N sources ⇒ N supervisors reading one `active-source`
  value — list-shaped, no two-source branch.

**Idle / parked semantics (specified).** A non-selected source keeps its pod and
its local MXL flow ring warm but **does not run the initiator** — it emits **no
fabric traffic toward the viewer**. This is what stops N sources from all blasting
the single viewer at once (the collision the naive "every source sends" model
would cause). Parked = the supervisor holding in its select loop until it becomes
`active-source`.

**Epoch / restart handling on switch (specified).** Because each source produces a
**distinct** `flow.id`, changing which source feeds the viewer means the viewer
must receive a **different** flow — so the coarse actuator **re-points and
restarts/reconnects the viewer**. To avoid a supervisor starting against a stale
endpoint, the actuator sequences **quiesce → re-point → select** (full ordering,
invariant, and failure posture in §6.2): it first **de-selects** (clears
`active-source`) — the **WP2 continuous re-check stops the running initiator and
parks it** — and clears the coordinator `target-info`/`epoch` as a *secondary*
newcomer-block (the shipped `wait_for_target_info` presence-gate then holds any
*not-yet-started* supervisor); then restarts the viewer (fresh `target-info` + new
`epoch`); then sets `active-source`, so the one matching supervisor can only start
against the fresh endpoint. Convergence: exactly one source transmits. What is
**reused** from shipped code: the `wait_for_target_info` presence-gate and the
epoch-change → restart *trigger* (`source-handshake.yaml`); what is **new (WP2)**:
the `active-source` gate, the stop-on-de-select, and gating that restart on
`active-source == self` (else the de-selected source relaunches on the re-point
epoch bump).

## 5. §c — Launcher source selection

The viewer's consumed source becomes a **launch/reconfigure parameter** threaded
through the full seam, replacing the implicit single-source rendezvous (F2). In
the correct direction, "source selection" = **which source is the
`active-source`** — the one activated to transmit toward the viewer, and the flow
the viewer is (re-)pointed to receive:

1. **Catalog** — `viewer.source_selection` in `topology_params` names which
   `sources[].id` is active.
2. **Launch `extra_vars`** — the canonical `topology_params` object (§3.2) carries
   the selection; nothing is baked per-JT. (Needs the seam to carry `extra_vars`;
   today `body={}`.)
3. **Playbook / chart** — the playbook projects the selection to (a) the
   coordinator **`active-source`** value and (b) the viewer's received `flow.id`
   (`--set`, parallel to how `role`/`interface`/`placementMode` are threaded
   today).
4. **Runtime** — `active-source` gates the source supervisors (§4.1): the selected
   source transmits, the viewer receives its flow.

Selection is a first-class parameter at **both** initial launch **and**
reconfigure (the switch, §6) — the same value, set once at launch and re-set by
the switch actuator.

## 6. §d — `SwitchSourceCommand` seam + coarse reconnect actuator

### 6.1 Domain command (durable seam)

Per re-anchor §5, the backend domain command is:

```
SwitchSourceCommand(receiver_instance, source_instance, reason)
    with pluggable actuator:
        actuator = reconnect   # v0.2b — coarse, ships now
        actuator = nmos-is05   # later — live IS-05, tracked follow-on
status: pending → reconnecting → active → failed_rollback_required
```

`receiver_instance` is **the viewer** (the stable published receiver, F2);
`source_instance` is the source to make `active-source`.

- **Classification:** a **Configure/Control reconfigure**, *not* a
  Finalise→Provision (re-anchor §5, codex P2). It re-points an existing viewer; it
  does **not** model the switch as workload destruction + redeploy — that would
  never reconcile with a later live IS-05 switch.
- **Domain vs actuator split is the whole point.** The command, its status
  machine, its audit record, and the console contract (§7) are **actuator-
  agnostic**. Only the actuator implementation differs between `reconnect` and
  `nmos-is05`.

### 6.2 Coarse `reconnect` actuator (v0.2b, honest semantics)

**Load-bearing prerequisite — the WP2 supervisor gate (NEW logic, not shipped).**
The whole sequencing below **depends on** the new WP2 supervisor behaviour (§4.1):
while its initiator runs, each supervisor **continuously re-checks**
`(active-source == own id) AND (target-info/epoch present)` and, on mismatch or
empty, **stops the initiator and parks**; the shipped epoch-change restart is
**gated on `active-source == own id`**. The shipped loop does none of this — it
stops a running initiator only on process death or a non-empty `epoch` change and
restarts *unconditionally* — so without WP2, clearing the coordinator would **not**
stop a running initiator and the phase-2 epoch bump would **relaunch the
de-selected source** (both would transmit; codex R3).

**Three-phase sequencing (quiesce → re-point → select).** Setting `active-source`
*before* the viewer restart would race: a newly selected supervisor could start
against the **stale** `target-info`/`epoch` left by the outgoing viewer. The
actuator sequences strictly:

1. **Quiesce — de-select.** The actuator sets `active-source` to none. The **WP2
   continuous re-check** sees the mismatch and **stops the running initiator and
   parks** the previously selected source — *this* is what halts transmission, not
   the field-clear. As a **secondary** newcomer-block, the actuator also clears the
   coordinator `target-info`/`epoch`, so the shipped `wait_for_target_info`
   presence-gate holds any *not-yet-started* supervisor.
   *Guards:* the outgoing source transmitting into a viewer about to change flow
   (crossed streams); a newcomer starting against the stale endpoint.
2. **Re-point + restart the viewer.** Reconfigure the viewer for
   `source_instance`'s `flow.id` and restart/reconnect it. The restart publishes a
   **fresh** `target-info` + a **new** `epoch` (new `TARGET_POD_UID:start_ts`) —
   the only valid rendezvous; the new `epoch` is a secondary discriminator (a
   supervisor holding a cached pre-switch epoch treats the new one as a fresh
   start). Because the epoch-restart is now WP2-gated on `active-source == self`,
   the still-de-selected sources do **not** relaunch on this bump.
   *Guards:* the viewer receiving the wrong flow id; the de-selected source
   relaunching on the epoch bump (the failure codex R3 confirmed).
3. **Select — set `active-source` = `source_instance.id`.** Only the matching
   supervisor un-parks, and because step 1 cleared the endpoint it can **only**
   start against step 2's fresh `target-info`. Exactly one source transmits.
   *Guards:* more than one transmitter — `active-source` is a single value, set
   last.

**Visible proof:** the viewer's tile/preview shows the **distinct test pattern** of
the newly selected source; a status field reflects `active-source`; preview
captured before/after (re-anchor §5).

**Switch invariant:** *no initiator ever starts against a `target-info` older than
the switch, and never more than one transmits.* It rests on the WP2 gate: step 1's
de-select stops the outgoing initiator and the presence-gate blocks newcomers;
step 3 un-parks exactly one, and by then the only endpoint that exists is step 2's
fresh one. Safety is independent of whether step 2 or step 3 completes first — if
`active-source` is set while the viewer is still restarting, the matching
supervisor simply waits at `wait_for_target_info` for the fresh endpoint.

**Failure posture:** if step 2's viewer restart fails, `active-source` stays
cleared (never advanced), so **no** source transmits — a clean quiesced state — and
the command reports `failed_rollback_required` for operator retry/rollback. This
zero-transmitters posture holds **only because** the WP2 de-select stop actually
halts the outgoing initiator; an entry-time-only gate would leave it running.

The switch is a **substitution, not an addition** — during phases 1–2 zero sources
transmit; after phase 3 exactly one does.

**Honest UI copy:** "coarse reconfigure / reconnect actuator." Not "IS-05 switch."

### 6.3 Invariant — the console contract is unchanged when IS-05 replaces reconnect

When `actuator=nmos-is05` later replaces the coarse one:
- `SwitchSourceCommand(receiver_instance, source_instance, reason)` — **unchanged.**
- The status machine (`pending → reconnecting → active →
  failed_rollback_required`) — **unchanged** (the IS-05 path may make
  `reconnecting` near-instant, but the states hold).
- The console request/response shape (§7) and the topology parameter set (§3) —
  **unchanged.**
The only difference the operator sees is honest copy and a faster, glitchless
switch. This invariant is a review gate on the build: any change to the console
contract or the parameter schema to make IS-05 work is a spec violation.

### 6.4 Not claimed

No live IS-05 switch. `nmos-crosspoint` stays visible-only; MXL flows are not
registered in NMOS in v0.2b. "Switched via nmos-crosspoint IS-05 Connection API"
is a **separate** tracked follow-on with its own acceptance gate (re-anchor §5
P1.1/P3) — the nmos-cpp↔MXL adapter is its own workstream.

## 7. §e — Console surface

**Where the action lives.** The switch action lives on the media-workloads
surface — on the **viewer instance** in `InstanceLiveModal.tsx` (the viewer's
workload/instance detail), alongside the existing live preview. It presents the
selectable sources (`sources[]` from the topology set) and requires a reason,
mirroring `ClearForDeployment.tsx` (the proven reason-field component).

**The write contract — reuse the shipped pattern (F3), do not invent a new one:**
`POST /api/media-workloads/{viewer_instance}/switch-source` (name illustrative),
body `{ "source_instance": "<source.id>", "reason": "<non-empty>" }`:
1. **Gate** with `_require_media_workloads_access` — grants iff the **effective**
   role is ≥ `engineer` **OR** the user's **real** `media-engineers` membership is
   present. (Verified in `main.py`/`security.py`: the role check runs on the
   view-as-downgraded *effective* role; groups are **never** altered by view-as,
   so real `media-engineers` membership is media-write authority per the surface's
   model. `ROLE_ORDER = viewer < operator < engineer < admin`.)
2. **Reason** via `_require_reason` — 400 `reason-required` *before* any actuator
   call.
3. Allocate `request_id = uuid.uuid4().hex` early.
4. Invoke `SwitchSourceCommand` (actuator=reconnect).
5. **C5 audit** the quartet (actor + effective role + real_role under view-as +
   request_id + `source_instance` + reason + outcome) to the dmf-cms log +
   console-local Activity lane — **not** into AWX `extra_vars` (matches
   clear-for-deployment / `_audit_awx_write`).
6. Response echoes `request_id`, actor, role, reason, previous/requested source,
   outcome.

**Authz decision (P2-3): reuse `_require_media_workloads_access`, no new gate.**
Consistency with the surface's only other consequential write
(clear-for-deployment) wins over introducing a looser operator-only gate, which
would fragment the surface's access model. This **intentionally diverges** from
#201's looser "operator-gated" wording — the effective gate is *engineer-or-real-
`media-engineers`*, which is stricter and already refuses a plain viewer. (The PR
body will surface this divergence for the operator.)

**Acceptance gate (verbatim, #201):** *operator switches the viewer between source
A and B from the console; tiles/preview reflect the change; every switch is
audited; a viewer-role user gets 403 on the same action.*

**Precise restatement of the 403 criterion:** *a viewer-role user **without
`media-engineers` membership** gets 403 on the switch action.* (A real viewer who
*is* in `media-engineers` legitimately reaches the surface — that group is the
media-write authority, by design; ADR-0037 §5, #185 WP-B.)

## 8. §f — Capacity envelope

**Shape:** `2 × mxl-videotestsrc + 1 × mxl-videotest-view` (+ optional
`nmos-crosspoint` visible-only) on the **single-node** lane.

**Why it is a real constraint (data point, #202):** the full demo menu (nmos-cpp
registry + 2 mocks + crosspoint + MXL pair) hit **96% CPU requests on a 3-CPU
node** and left AWX EE pods unschedulable. The presentable-journey scenario
(2×src + viewer + crosspoint) is exactly that shape — so a J1 live run is close to
the budget ceiling, and adding sources (N>2) will breach it.

**Coordinate with L3 — do not duplicate it.** Capacity **enforcement** (preflight
budget check that refuses/​warns an over-budget launch; rollback of NetBox tags +
Helm releases + monitor targets on partial failure) is owned by
[#202](https://github.com/dmfdeploy/dmfdeploy/issues/202) (L3). This spec **does
not** re-specify preflight/rollback. It states the requirement and defers:

> **HARD GATE:** no live multi-source J1 run happens before #202's preflight +
> rollback land. A deliberately over-budget launch must be refused with a legible
> budget report; a killed mid-run deploy must roll back to a clean pre-run state.
> #202 should land **before or with** the v0.2b switch demo.

The parameter set (§3) *feeds* L3's preflight (source count × per-source
CPU/mem request → node budget) but the check itself is L3's.

## 9. What is NOT claimed (honest scope, consolidated)

- **No live IS-05 switch** in v0.2b; coarse reconnect only (§6.4).
- **`nmos-crosspoint` stays visible-only**; MXL flows not NMOS-registered.
- **No free-form topology authoring** in the console for J1; the console selects a
  catalog-defined topology. Free-form authoring is Design-beat-v1 (#231), enabled
  by the seam this spec builds, not delivered by it.
- **No Design/Plan interactivity** in the demo this round (legibility-only holds).
- **No capacity enforcement here** — that is L3 (#202).

## 10. §g — Work packages & sequencing

Spans three repos; each WP names its repo. **Nothing that runs a live multi-source
topology lands before the L3 gate (#202).**

| WP | Repo | Work | Gate |
|----|------|------|------|
| **WP1 — Parameter contract** | dmf-media (catalog) | Define `topology_params` schema v1 (§3) in the git catalog; author the J1 2-source instance; document the seam mapping. Doc/schema only. | codex |
| **WP2 — Chart parameterisation + supervisor gate** | dmf-media (charts) | `mxl-fabrics-demo`: make `flow.id` + test `pattern` per-source values (kill the fixed UUID, F1); add the coordinator **`active-source`** selector and the **NEW supervisor logic** — entry gate + **continuous re-check** that stops+parks a *running* initiator on de-select/empty, and **gates the shipped epoch-restart on `active-source == self`** (§4.1, §6.2); viewer re-point/restart on switch. **Acceptance gate (hard):** an entry-time-selector-only implementation **FAILS** — must demonstrate (i) **stop-on-de-select of a running initiator** and (ii) **no relaunch of a de-selected source on the phase-2 epoch bump**. | codex + render/dry-run + two-part supervisor demo |
| **WP3 — Launcher projection** | dmf-runbooks + dmf-infra | The **playbook projects** `topology_params` (received as `extra_vars`) to chart `--set`, iterating `sources[]` (N-shaped); JT defaults hold no topology values; **validate `target_facility`** against the single legal value, reject unknown (§3.4). | codex + syntax-check |
| **WP3a — Console launch seam** | dmf-cms (backend) | **Extend the launch seam to carry `extra_vars`** (F2, §3.2) — today `/api/catalog/{key}/deploy` (`main.py:1567`) → `_run_deploy_operation` (`main.py:340`) → `launch_job` (`awx.py:117`) posts **`body={}`**. Pass a catalog-defined `topology_params` object through to the AWX launch as `extra_vars`. **Backend-test gate:** a catalog-defined topology reaches AWX as `extra_vars` (asserted, not `{}`). | codex + backend-test |
| **WP4 — SwitchSourceCommand** | dmf-cms (backend) | `SwitchSourceCommand(receiver, source, reason)` domain command + status machine + `actuator=reconnect` (§6); actuator interface shaped for `nmos-is05`. | codex |
| **WP5 — Console switch write** | dmf-cms (backend+frontend) | `POST …/switch-source` reusing `_require_media_workloads_access` + `_require_reason` + C5 audit (§7); switch UI in `InstanceLiveModal.tsx`; viewer 403; before/after preview proof. | codex + acceptance gate |
| **WP-L3 (dependency)** | cross-repo (#202) | Preflight budget check + rollback (§8). **Blocks any live J1 run.** | #202's own gate |

**Sequencing:** WP1 (contract) first — it is the frozen input for WP2–WP5.
WP2/WP3/WP3a (data-plane: charts + playbook projection + console launch seam) can
proceed in parallel behind WP1; WP3a is the prerequisite for any parameterised
launch reaching AWX. WP4 (domain command) precedes WP5 (console wiring). **WP5's
live acceptance run and any demo are gated on WP-L3 (#202).** Dry-run/render
verification of WP2/WP3, the WP3a backend-test, and unit/contract verification of
WP4/WP5 do **not** need L3; only a live multi-source deploy does.

**Follow-ons (out of scope, tracked elsewhere):** live IS-05 actuator +
nmos-cpp↔MXL adapter (re-anchor §5 P1.1); Design-beat-v1 template-instantiation
console form ([#231]) driving `topology_params`.

## 11. References

- Umbrella issues: [#201] (this spec), [#202] (L3 preflight/rollback),
  [#200] (presentable journey), [#189] (v0.2 scope), [#231] (Design beat v1),
  [#203]/PR #237 (demo runbook).
- Plans: `DMF v0.2 EBU Facility-Orchestration Re-anchor Plan 2026-07-07.md` §5
  (v0.2b framing).
- ADRs: ADR-0037 (Media Workloads = NetBox instance inventory; flows runtime-only),
  ADR-0046 (first-class Media Workload entity — `workload:<slug>` grouping),
  ADR-0028 (C5 reason-gated audit).
- Shipped state cited in §2 (F1/F2/F3): `dmf-media`
  `charts/mxl-fabrics-demo/values.yaml`, `catalog/mxl-videotestsrc.yaml`,
  `catalog/mxl-videotest-view.yaml`; `dmf-runbooks`
  `playbooks/launch-mxl-fabrics-demo.yml`; `dmf-infra`
  `…/awx-integration/defaults/main.yml`; `dmf-cms` `src/dmf_cms/main.py`
  (`_require_media_workloads_access`, `_require_reason`, `_audit_awx_write`,
  `/api/media-workloads/{instance}/clear`), `src/dmf_cms/awx.py` (`launch_job`),
  `frontend/src/pages/MediaWorkloads/`.

[#189]: https://github.com/dmfdeploy/dmfdeploy/issues/189
[#200]: https://github.com/dmfdeploy/dmfdeploy/issues/200
[#201]: https://github.com/dmfdeploy/dmfdeploy/issues/201
[#202]: https://github.com/dmfdeploy/dmfdeploy/issues/202
[#203]: https://github.com/dmfdeploy/dmfdeploy/issues/203
[#231]: https://github.com/dmfdeploy/dmfdeploy/issues/231
