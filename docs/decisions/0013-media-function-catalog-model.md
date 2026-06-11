# ADR-0013: Media function catalog model

**Status:** Accepted
**Date:** 2026-05-04
**Deciders:** @<handle>, planning session with Claude

## Context

The DMF Platform Plan §9 ("two lanes") and the strategic review
(2026-04-30) frame Layer 4–6 work as needing an operator-driven launch
mechanism — image bootstrapped into the cluster but actual deployment
deferred to operator action in dmf-cms, mirroring the
`Download Media Functions` / `Launch Media Functions` split in EBU
Figure 4 (white paper p.6). Move 2 closed the dmf-cms→AWX→NetBox
vertical slice but left the dmf-cms `app-contract` as a static YAML
fixture; the Move 2 learnings (`docs/reviews/dmf-platform-move-2-learnings-2026-05-04.md`
§Q2) flagged the pivot to NetBox-discovered as queued. The catalog
idea is the natural form of that pivot, with extensions for the upper
layers' bootstrap-but-don't-deploy semantics.

## Decision

Adopt a **function catalog model** for Layer 4–6 functions and (in v2,
post-Move-1) Layer 6 baseline apps. Each catalog entry has:

- **A YAML manifest** committed to the function's source repo at
  `<repo>/catalog/<key>.yaml`. Authoritative for static metadata:
  EBU layer/vertical, dependencies, the Configure and Finalise playbook
  references, image/chart pinning, default parameters. This is the
  "what's available" side.
- **A NetBox runtime record**, extending the existing `ipam.Service`
  registration written by `roles/common/dmf-born-inventory/`. Tagged
  `lifecycle:bootstrapped` after Provision, flipped to `lifecycle:active`
  after Configure, flipped back after Finalise. This is the "what's
  currently active" side.
- **A Configure playbook** (e.g. `playbooks/configure-media/launch-<key>.yml`
  in the function's source repo) that launches the workload from a
  catalog entry and updates the NetBox tag. Imported from
  `lifecycle-configure.yml` via per-function tag (ADR-0012).
- **A Finalise playbook** (symmetric, e.g. `teardown-<key>.yml`) that
  removes the workload and flips the tag back.

dmf-cms reads the catalog by joining YAML metadata (from the in-cluster
Forgejo mirrors) with NetBox runtime tags. It exposes Deploy and
Teardown buttons per entry that invoke the corresponding AWX job
templates (ADR-0014 governs the AWX project layout that makes those
templates resolve).

v1 scope: one instance per catalog entry, single cluster, no
parameterised launches, no per-user identity propagation (dmf-cms
continues to act as `dmf-cms-svc` per Move 2 learnings).

## Consequences

- **Positive** — bootstrap-but-don't-deploy becomes the default for
  upper-layer functions. The lab carries the full catalog without
  paying the runtime cost.
- **Positive** — completes the Move-2-queued `app-contract` pivot in
  a richer form. dmf-cms gains a real "service catalog" surface,
  not just a navigation manifest.
- **Positive** — direct probe of thesis-killer #3 (EBU taxonomy): the
  catalog entry schema must accommodate every layer/vertical/lifecycle
  combination the platform encounters. A function whose entry can't
  be expressed cleanly is the hard case ADR-0003 was waiting for.
- **Positive** — AWX audit trail per Configure/Finalise click closes
  the operations-lane loop from DMF Platform Plan §9.
- **Negative** — two stores of "what apps exist" (YAML + NetBox tags).
  Acceptable because they answer different questions (available vs.
  active), but drift between them must be detectable. v1 mitigation:
  Configure-stage smoke test asserts NetBox tag matches Helm release
  presence.
- **Negative** — per-user identity still not preserved end-to-end
  (Move 2 known gap). Catalog model inherits this; not a regression.
- **Negative** — no multi-instance support in v1. Defers
  parameterisation, which simplifies the schema but means HA / dual-
  registry scenarios need a v2 reshape.

## Alternatives considered

- **NetBox-only catalog** (custom fields on `ipam.Service`). Rejected —
  `ipam.Service` is the wrong shape for flow-producing media functions
  (which aren't "services on a port" in the NetBox sense), and custom
  fields accumulate without a schema home.
- **YAML-only catalog**. Rejected — runtime state then lives outside
  NetBox, contradicting the SoT decision (DMF Platform Plan §12, decision
  log 2026-04-17).
- **Pure Helm/ArgoCD model**, no catalog abstraction. Rejected — the
  operator-facing UI needs a richer abstraction than Helm releases
  (lifecycle state, dependencies, status semantics, dmf-cms-readable
  display metadata).

## Cross-references

- ADR-0038 — dynamic monitoring extends this catalog model with a
  separate monitoring contract, NetBox lane taxonomy, and k8s
  annotation/adapter bridge.

## Enforcement

The Move 1 task spec
(`docs/plans/dmf-platform-move-1-task-2026-05-04.md`) implements the
first catalog entry (nmos-cpp). After Move 1 lands, every new Layer
4–6 function gets a catalog entry as part of its initial implementation;
PRs adding Layer 4–6 work without a catalog entry should be flagged.
The architecture reference is
`docs/architecture/DMF Function Catalog Model.md`. ADR-0012 (Configure
split) is the lifecycle-vocabulary precondition for this ADR; ADR-0014
(AWX project layout) is the execution precondition.

## Amendments

### 2026-05-12 — `provision.namespace` added to schema

The Move 1 P8 drift detector (`operate-catalog-drift.yml`) surfaced a
gap: the schema had no k8s namespace field, so drift detection had to
derive namespace from the entry's `key` — a brittle heuristic that
produced false positives for `nmos-cpp` (actual namespace `nmos`, not
`nmos_cpp`). Decision
[`catalog-namespace-source-of-truth`](../agentic/decisions-open.md)
selected **Option A**: add `provision.namespace` (required) to the
schema. The field is the single source of truth for where the workload's
Helm release deploys, consumed by drift detection and any future
operator needing to locate the workload. The architecture reference and
`dmf-media/catalog/README.md` schema table were updated;
`dmf-media/catalog/nmos-cpp.yaml` now declares
`provision.namespace: nmos`.
