<!-- ADR doc convention: every ADR carries a top-of-doc **Rule:** line — the binding
constraint in one imperative sentence — directly under the metadata block. See
CONTRIBUTING.md → "ADR conventions". -->
# ADR-0046: First-class Media Workload entity — a tag-derived assembly of Media Functions

**Status:** Accepted
**Date:** 2026-07-08
**Deciders:** @znerol2 (Discussion [#190](https://github.com/dmfdeploy/dmfdeploy/discussions/190)), with Claude; codex adversarial cross-check (RFC 3 rounds → PASS)
**Amends:** ADR-0037 (adds the assembly layer ADR-0037 deliberately deferred — as a tag-derived *virtual* grouping, still no NetBox graph object)
**Cross-references / touches:** ADR-0003 (EBU taxonomy — the vertical/type correction), ADR-0013 (catalog model — the `media_function_type` field), ADR-0027 (catalog/instance separation), ADR-0032 (scoped NetBox writer — stamps `workload:*`)
**Rule:** A **Media Workload** is a tag-derived grouping of Media Function instances (NetBox `workload:<slug>`, exactly **0-or-1 per service**); the six-stage EBU lifecycle is **workload-level**; launchers **must preserve non-owned tags** so `workload:*` survives the deploy lifecycle.

## Context

The EBU DMF Reference Architecture is unambiguous: a **Media Workload** is the
production-level *assembly*, and Media Functions are *combined to implement* it
(Annex B, Figure B1). ADR-0037 knowingly modelled the console's "Media Workloads"
page as a Media *Function* instance inventory and **deferred** the assembly. As
the MXL demo grows past a single function (`mxl-videotestsrc` + `mxl-videotest-view`),
the assembly is the unit the operator reasons about — its lifecycle, its future
switch target, its resource budget — and there is nowhere to hang those. RFC
[#190](https://github.com/dmfdeploy/dmfdeploy/discussions/190) converged on
introducing the entity without new NetBox machinery.

## Decision

**1. The entity is a derived grouping, not a graph object.** A Media Workload is
derived from existing NetBox instance records; it owns no persisted graph.
Membership is a **NetBox tag `workload:<slug>`** on each member service, scoped by
identity **`(tenant/site scope, slug)`** and applied only *after* the console's
existing tenant/site scoping.

**2. Single membership for v0.2 (hard constraint).** Exactly **zero or one**
`workload:*` per service. Zero → an explicit **`unassigned`** bucket (one code
path, not a synthetic single-function workload). More than one is **invalid/
degraded and surfaced as such**, never silently multi-member. A function that
genuinely serves multiple productions is modelled through connection/flow intent
or explicit shared-resource semantics — shared support/control systems (e.g.
NMOS) stay shared facility functions unless deliberately instantiated into one
production workload.

**3. Lifecycle is workload-level; functions carry run intent.** The six-stage EBU
lifecycle (Design → Plan → Provision → Configure → Operate → Finalise & Review)
belongs to the workload (Fig 1 is the *Media Workload Lifecycle*); a
function-instance `lifecycle:*` tag is desired/run intent — this is the console
rule, not a claim that functions have no lifecycle. v0.2 derives **only** the
stages the current signals support:
- **Provision** — member services exist / are bootstrapped;
- **Configure** — active intent exists but observed health / declared-flow
  readiness is incomplete or mixed;
- **Operate** — required members are active and observed healthy and the declared
  flow overlay is present or at least not failing.

Design / Plan / Finalise & Review show **declared/unknown** or are deferred;
**finalise is never inferred from absence**. Workload health/lifecycle **must join
by NetBox service/instance identity**, not the collapsing Prometheus `app` rollup
(which breaks once two instances of one function key live in different workloads).

**4. Launcher tag preservation is a prerequisite, not implementation detail (hard
constraint).** The launcher owns a bounded tag set and **must preserve everything
else** (including `workload:*`). Owned set/algorithm, per stage:
- replace **exactly one** `lifecycle:*` tag (the stage's desired state);
- ensure the required static tags (`dmf-catalog`, `app:<key>`, `exposure:private`);
- apply/remove the deliberate monitoring tags/custom fields the stage requires;
- **preserve all other non-owned tags verbatim**, including `workload:*`.

(Today's MXL/NMOS launchers PATCH *exact* tag lists and would erase `workload:*`.)
Threading `workload` through launcher defaults is acceptable only as a
**seed/backfill convenience** (e.g. for `videotest`), not as the authority —
membership belongs to the workload/design/NetBox layer. Proven by a
**provision→configure→finalise survival test covering both `mxl-videotestsrc` and
`mxl-videotest-view`** before the entity ships.

**5. Console IA + API split.** Reserve **"Media Workloads"** for the assembly;
rename the flat per-function surface to **"Media Functions" / "Function
Instances."** No in-place reshape of `/api/media-workloads`: add the grouped API
first, migrate the UI, then deprecate the flat shape. Target end state:
`/api/media-workloads` = grouped workload-first payload; `/api/media-function-instances`
= flat instance inventory (interim: keep the flat response briefly or expose
`/api/media-workloads/grouped` until the frontend/tests move).

**6. Classification (narrow vertical correction) — concrete catalog contract.**
Verticals are cross-cutting and apply at **every** layer, so Layer-5
*support/control* functions legitimately carry one (`nmos-cpp`=orchestration,
`nmos-crosspoint`=control). The catalog bug is only the media-*processing*
entries' non-vertical pseudo-values. The schema contract:

- New field **`ebu.media_function_type`** (string), nested under the existing
  `ebu:` block alongside `layer`/`vertical`/`lifecycle_owner`. v0.2 enum (seed,
  extensible via follow-up): `source`, `view`, `processor`, `mixer`, `output`,
  `render`, `gfx`, `multiviewer`.
- **Exactly one** of `ebu.vertical` or `ebu.media_function_type` is present per
  entry — the author declares the function's nature by which field they set. A
  *media-processing* function sets `media_function_type`; a *support/control*
  function sets `vertical`.
- **Schema check** (fail-closed): `ebu.vertical`, if present, must be one of
  {orchestration, control, monitoring, security}; `ebu.media_function_type`, if
  present, must be in the enum; neither-both-nor-neither. This rejects the current
  non-vertical pseudo-values without breaking legitimate support/control verticals.
- **Migration of the MXL entries** (only the two that remain — see below):
  - `mxl-videotestsrc` — keep `layer:5`; drop `vertical: media-functions`; add
    `media_function_type: source`.
  - `mxl-videotest-view` — keep `layer:5`; drop `vertical: media-functions`; add
    `media_function_type: view`.
  - `mxl-hello` — **retired** (removed from the catalog), superseded by the
    `videotest` workload; this deletes the anomalous `layer:4` +
    `vertical: media-processing` entry rather than migrating it. Tracked in
    [#193](https://github.com/dmfdeploy/dmfdeploy/issues/193).

**7. Flows stay runtime/overlay (ADR-0037 preserved).** Membership is the tag;
flow edges are a separate overlay, **never persisted to NetBox**: declared from
the catalog (`mxl_flows.produces/consumes`) and observed at runtime. Flows may
cross workload boundaries (Annex B Fig B2) — a Workload is not defined as *only*
the flows between its members.

## Consequences

- **Positive** — the vocabulary becomes honest; the workload is a real home for
  the lifecycle, the future switch target, and L3 preflight/rollback; the catalog
  stops mis-tagging media-processing functions; minimal new infrastructure (one
  tag, no graph object, no CRD).
- **Negative** — launcher tag-flip hardening (decision 4) is a prerequisite, not
  free; a console IA change and an additive API split; a catalog schema migration;
  a one-time NetBox backfill of the two MXL services.
- **Neutral** — Flows stay runtime/overlay (ADR-0037 unchanged on that point);
  single-membership assumed for v0.2; the flat inventory API lives on during
  migration.

## Alternatives considered

- **Catalog-level workload manifest** (declare members in YAML) — richer, but adds
  a new store/authority duplicating NetBox's instance record. Rejected for now.
- **Keep the page as a function inventory** (do nothing) — leaves the
  Function/Workload conflation and gives the lifecycle/switch/budget nowhere to
  live. Rejected.
- **Re-stamp `workload` from the launcher as the authority** (option b) — rejected:
  membership is a workload/design concern, not a per-launcher one; acceptable only
  as a seed/backfill convenience.

## Enforcement

- **Catalog schema check** (dmf-media + dmf-cms) — enforces exactly one of
  `ebu.vertical` (∈ {orchestration, control, monitoring, security}) or
  `ebu.media_function_type` (∈ the enum) per entry; rejects the current
  non-vertical pseudo-values; accepts legitimate support/control verticals.
- **Launcher tag-preservation survival test** (dmf-runbooks) — a
  provision→configure→finalise cycle must leave `workload:*` intact; blocks the
  entity from shipping otherwise.
- **Console rollup-by-identity** (dmf-cms) — workload health/lifecycle joins by
  NetBox service/instance identity, not the `app` label.
- **ADR-0037** carries an amendment pointer to this ADR.
- Implementation slices open as their own issues under
  [#189](https://github.com/dmfdeploy/dmfdeploy/issues/189), each codex-gated.
