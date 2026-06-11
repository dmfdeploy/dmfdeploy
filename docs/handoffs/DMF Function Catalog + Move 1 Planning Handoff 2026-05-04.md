# DMF Function Catalog + Move 1 Planning Handoff — 2026-05-04

**Session:** Pure planning / architecture session. No code in component repos
modified. Output is umbrella docs only.
**Trigger:** Operator (<operator>) raised the question of bootstrapping upper-layer
playbooks/images into the cluster but deferring deployment to operator action
in dmf-cms — "like a marketplace". Discussion against EBU Figure 4 confirmed
the idea is canonically aligned with the DMF reference model's distinction
between PROVISION ("Download Media Functions") and CONFIGURE ("Launch Media
Functions").

## What was decided this session

Three architectural decisions formalised as ADRs:

1. **ADR-0012** — Configure is a distinct lifecycle stage from Provision. The
   existing `lifecycle-provision.yml` admits the conflation in line 1 of its
   header. Split is justified by Layer 4–6 functions where "available" and
   "running" are genuinely different states.
2. **ADR-0013** — Media function catalog model. YAML manifest in source repo
   (intent / what's available) + NetBox `ipam.Service` tag (runtime / what's
   active), joined by dmf-cms.
3. **ADR-0014** — AWX project layout: hybrid (`dmf-runbooks` thin launchers
   + mirrored source-repo projects). Survives the future dmf-central
   federation transition without restructure.

Architecture reference written:
- `docs/architecture/DMF Function Catalog Model.md` — canonical doc for the
  catalog concept. Schema, source-of-truth split, lifecycle integration,
  AWX wiring, dmf-cms responsibilities, failure modes, v1/v2/v3+ scope.

Task spec written:
- `docs/plans/dmf-platform-move-1-task-2026-05-04.md` — implementation plan
  in nine Pieces, mirroring the Move 2 task spec shape. Bundles the original
  NMOS spike with the catalog mechanism (rationale: probes thesis-killer #3
  alongside #1, only one round of lifecycle/AWX/dmf-cms work needed).

## Relationship to existing NMOS plan

`docs/plans/DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md` exists
in **Proposed — awaiting approval** status. Its Phase 1+2 (Dockerfile,
ConfigMaps, role tasks, ConfigMap shapes) is the **technical implementation
reference** for the nmos-cpp work. Its Phase 3 ("dmf-cms integration deferred")
is **superseded** by the Move 1 + Catalog task — Phase 3 is no longer
deferred; it's the point.

A header note has been added to that plan pointing at the new task spec.

## Why scope was expanded vs the strategic review

Strategic review's original Move 1: "deploy one NMOS registry, run for 24
hours" — ~1 day estimate. Move 1 + Catalog task: 3–5 days, bundles the
catalog mechanism.

Justification recorded in the task spec §"Note on scope expansion":

- Bare NMOS deploy probes thesis-killer #1 (NMOS on commodity k3s) but
  not #3 (EBU taxonomy survives a hard case).
- Catalog model directly probes #3 (the schema must accommodate the
  function's layer/vertical/lifecycle metadata cleanly).
- The lifecycle/AWX/dmf-cms work has to happen once anyway. Bundling
  is cheaper than two sequential experiments.
- A catalog with one entry is the minimum coherent shape; smaller
  experiments don't test the catalog model at all.

Effort risk: real. If Move 1 + Catalog stalls, the fallback is to
land NMOS bare (dropping Pieces 1, 2, 3, 6, 7, 8 of the task spec)
and queue the catalog as Move 1.5. The task spec's Piece 4 (NMOS
provision-side) is structured so it stands alone if needed.

## Commit gate status (no change from prior handoff)

| Condition | Status |
|---|---|
| First vertical slice end-to-end | ✅ DONE (Move 2) |
| NMOS registry deployed in `dmf-media` | ❌ NOT STARTED — addressed by Move 1 task spec |
| `docs/architectural-commitments-v1.md` written | ❌ Pending — Piece 9 of the new task spec |

**Half-met.** Same as 2026-05-04 prior handoff. Move 1 (now Move 1 + Catalog)
remains the gate.

## Open questions (decision points D1-D4 in the task spec)

These need answers before execution starts:

1. **D1** — NMOS implementation: Sony nmos-cpp build-from-source, or NVIDIA
   fork pre-built? Recommendation: A (Sony), B as fallback.
2. **D2** — `lifecycle-configure.yml` shape: tag-driven import-per-entry, or
   loop over manifest list? Recommendation: A (tag-driven) for v1.
3. **D3** — AWX launcher shape: `import_playbook` cross-project, or
   `hosts: + roles:` with `roles_path`? Recommendation: B (standard pattern).
4. **D4** — dmf-cms catalog source: live read from in-cluster Forgejo, or
   ConfigMap rendered at deploy time? Recommendation: B (ConfigMap) for v1,
   A as v2 evolution.

All recommendations land in the same place — biased toward simplicity and
single-cluster v1, with v2 evolution explicit.

## Open questions independent of execution

These were not addressed this session and are still open:

- **Path A (public push) — four prior decisions** (license, GitHub
  destination, repos in scope, Forgejo posture). Tracked in the prior
  2026-05-04 handoff `DMF Move 2 Closure + Path A Handoff 2026-05-04.md`.
  Independent of Move 1 timing.
- **`<operator>` Authentik superuser flip** still pending from the 2026-05-03
  privileges handoff. Independent of Move 1.

## Pre-execution blockers

These need attention before Move 1 execution starts:

- [ ] Confirm D1–D4 with operator (the four recommendations above)
- [ ] Verify Colima on Mac mini is up and reachable (per NMOS plan §6 Build
      commands; the build runs there)
- [ ] Verify Zot accepts pushes from the operator's docker-cli session
      (used in NMOS plan §A.4)
- [ ] (Optional) Pin a specific `sony/nmos-cpp` release tag rather than
      letting the implementer choose at build time

## Files touched this session

**Created in umbrella `docs/`:**
- `decisions/0012-configure-stage-distinct-from-provision.md`
- `decisions/0013-media-function-catalog-model.md`
- `decisions/0014-awx-project-layout.md`
- `architecture/DMF Function Catalog Model.md`
- `plans/dmf-platform-move-1-task-2026-05-04.md`
- `handoffs/DMF Function Catalog + Move 1 Planning Handoff 2026-05-04.md` (this file)

**Updated in umbrella:**
- `docs/decisions/INDEX.md` — added rows for 0012/0013/0014
- `docs/INDEX.md` — added new architecture doc + new task spec; updated
  reading order
- `TODOS.md` — Move 1 entry replaced with reference to new task spec;
  scaffold rows for `lifecycle-configure.yml` and catalog mechanism added
- `docs/plans/DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md` —
  header note added pointing at the Move 1 + Catalog task as the
  superseding plan for dmf-cms integration
- `STATUS.md` operator-notes section — updated to reflect the planned
  catalog work as in-flight architecture

**No code in component repos modified. Nothing committed. Nothing pushed.**

## Pickup steps for the next session

A fresh agent should:

1. Read `docs/CLAUDE.md` boot ritual (always).
2. Read this handoff (you're here).
3. Read in order:
   - `docs/architecture/DMF Function Catalog Model.md` (the architecture)
   - `docs/decisions/0012-…`, `0013-…`, `0014-…` (the decisions)
   - `docs/plans/dmf-platform-move-1-task-2026-05-04.md` (the spec)
   - `docs/plans/DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md`
     (technical implementation details for nmos-cpp; treat its Phase 3 as
     superseded)
4. Confirm decision points D1–D4 with the operator.
5. Pick an execution mode (Option A/B/C in the task spec). Mixed (Option C)
   matches the Move 2 pattern that worked.
6. Execute Pieces in dependency order. Manual verification points are
   noted at Pieces 4 and 6 — do not skip.
7. Land the write-up + commitments doc as Piece 9. The write-up IS the
   deliverable per ADR-0004; working code is incidental.

## Cross-reference

- Move 1 + Catalog task spec: [`docs/plans/dmf-platform-move-1-task-2026-05-04.md`](../plans/dmf-platform-move-1-task-2026-05-04.md)
- Catalog architecture: [`docs/architecture/DMF Function Catalog Model.md`](../architecture/DMF%20Function%20Catalog%20Model.md)
- ADR-0012: [`docs/decisions/0012-configure-stage-distinct-from-provision.md`](../decisions/0012-configure-stage-distinct-from-provision.md)
- ADR-0013: [`docs/decisions/0013-media-function-catalog-model.md`](../decisions/0013-media-function-catalog-model.md)
- ADR-0014: [`docs/decisions/0014-awx-project-layout.md`](../decisions/0014-awx-project-layout.md)
- Prior handoff (Move 2 closure + Path A): [`DMF Move 2 Closure + Path A Handoff 2026-05-04.md`](DMF%20Move%202%20Closure%20+%20Path%20A%20Handoff%202026-05-04.md)
- Strategic review: [`docs/reviews/dmf-platform-strategic-review-2026-04-30.md`](../reviews/dmf-platform-strategic-review-2026-04-30.md)
- Existing NMOS plan: [`docs/plans/DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md`](../plans/DMF%20NMOS%20Registry%20+%20Crosspoint%20Demo%20Plan%202026-05-04.md)
