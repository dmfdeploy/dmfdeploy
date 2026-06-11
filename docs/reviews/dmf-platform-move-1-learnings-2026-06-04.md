# DMF Platform — Move 1 + Catalog Learnings (NMOS spike)

**Date:** 2026-06-04
**Scope:** `nmos-cpp` as the first function-catalog entry, proving the full
Provision → Configure → Finalise → Operate loop on commodity ARM k3s. Move 1
from the strategic review (`docs/reviews/dmf-platform-strategic-review-2026-04-30.md`),
expanded to bundle the function-catalog mechanism (ADRs 0012/0013/0014) per the
task spec `docs/plans/dmf-platform-move-1-task-2026-05-04.md`.
**Status:** Move 1 acceptance met. This doc is the closing deliverable — Piece 9
of the task spec, *"the actual deliverable, per ADR-0004; the working code is
incidental."* It was overdue: Pieces 1–8 landed by 2026-05-12 and the runtime
loop was re-verified 2026-05-27/29, but the synthesis was never written until now.

> **This write-up supersedes** the provisional
> [`docs/architectural-commitments-v1.md`](../architectural-commitments-v1.md)
> (dated 2026-05-05, pre-Path-A). Where that doc named files that the
> 2026-05-06 **Path A pivot** later obviated (`410-nmos-cpp-provision.yml`,
> `playbooks/configure-media/`, the `lifecycle-configure.yml` wrapper), the
> corrected shape is recorded here.

---

## TL;DR

The catalog loop closed end-to-end on commodity ARM64 k3s. Sony `nmos-cpp` built
from source and ran under flannel CNI; a single catalog entry drove
Provision → Configure → Finalise → Operate via Console → AWX, with NetBox
holding lifecycle state. Six architectural assumptions tested:

| # | Assumption | Verdict | Evidence |
|---|---|---|---|
| 1 | NMOS IS-04/05 deploys on commodity ARM k3s | ✅ Confirmed | registry + 2 nodes Running on `imc1-cyh4`; full cold-cycle gate on `y834-bcwe` (2026-05-29) |
| 2 | Catalog YAML schema accommodates a real L5 function | ✅ Confirmed (additive growth only) | `dmf-media/catalog/nmos-cpp.yaml`; later gained `provision.namespace` + `monitoring:` — no reshape |
| 3 | Configure-as-distinct-stage holds | ✅ Confirmed — **stage split moved from wrapper to role** | Path A pivot (ADR-0014/0016, 2026-05-06) |
| 4 | dmf-cms drives the lifecycle through AWX | ✅ Confirmed (new failure modes found + mostly fixed) | Console→AWX catalog deploy/teardown re-verified 2026-05-29 |
| 5 | Hybrid AWX project layout (ADR-0014) works | ✅ Confirmed (with offline-EE work) | launcher resolves `nmos-cpp` role from `dmf-runbooks`; EE 0.1.1 |
| 6 | Drift detector catches NetBox/Helm divergence | ⚠️ Built + schema-sound; live drift-injection is an evidence gap | `move1-p8` reads `provision.namespace` explicitly |

**The nmos-cpp / catalog thesis is closed (confirmed).** The harder thesis-killer
#3 — "EBU taxonomy survives a function that genuinely spans two layers/verticals"
— is **not** closed by a single registry entry. The **MXL spike** (src + view
two-function fabric, 2026-05-29 →) is the *successor pressure test*, not
successor *evidence* for this closure.

---

## What landed

Nine Pieces from the task spec. Two were **obviated by the Path A pivot** (their
function moved, not vanished); the rest landed and were file-verified by
2026-05-12 (`docs/agentic/loop-log.md`, shifts 4–8) and runtime-verified
2026-05-27/29.

| Piece | Plan | Reality | Status |
|---|---|---|---|
| 1 | Catalog schema + first entry | `dmf-media/catalog/nmos-cpp.yaml` + README | ✅ done |
| 2 | `lifecycle-configure.yml` wrapper | **Obviated** — Path A replaced wrapper-driven Configure with AWX-driven role stages; the wrapper is now a stub redirecting to AWX | ⊘ obviated |
| 3 | Forgejo mirror + AWX projects | `awx_catalog_projects` = dmf-runbooks + dmf-media (with `roles_path`) | ✅ done |
| 4 | NMOS provision-side | consolidated into `dmf-runbooks/roles/nmos-cpp/tasks/provision.yml` (Path A) | ✅ done |
| 5 | NMOS configure-side launch playbook | **Obviated** — configure stage folded into `roles/nmos-cpp/tasks/configure.yml`, invoked by the launcher | ⊘ obviated |
| 6 | AWX launcher in dmf-runbooks | `playbooks/{launch,teardown}-nmos-cpp.yml`; JTs `media-launch/finalise-nmos-cpp` | ✅ done |
| 7 | dmf-cms catalog page | backend `catalog.py` + 4 endpoints (7a), React `/catalog` (7b), ConfigMap+gather (7c) | ✅ done |
| 8 | Drift detector | `operate-catalog-drift.yml` reads `provision.namespace` as source of truth | ✅ done |
| 9 | **Write-up** | **this document** | ✅ done |

The Path A pivot (`docs/handoffs/DMF Move 1 Gate 2 Path A Pivot Handoff 2026-05-06.md`)
is the single biggest deviation from the task spec and is treated as a finding,
not a failure — see Q3 and §Bonus learnings.

---

## Q1 — Does NMOS IS-04/05 deploy on commodity ARM k3s?

**Yes.** Sony `nmos-cpp` built from source on ARM64 (Colima) and ran cleanly
under k3s flannel CNI. On fresh env `imc1-cyh4` (2026-05-29) the **registry
StatefulSet + 2 node Deployments reached Running**, driven through the catalog
loop with zero galaxy egress (STATUS §"WP1S Phase 3/4 proven"); the same loop was
re-verified as part of the **full cold-cycle v0.1 gate on `y834-bcwe`** (Sandbox
v0.1 Gate handoff §0).

The build was real work, not a pull. Footguns (carried forward from
commitments-v1 §B, all confirmed durable):
- **No upstream version tags** → clone `master`, never `--branch vX`; pin by
  commit SHA in production.
- **Conan source lives in `Development/`** → `WORKDIR /src/Development` after clone.
- **Colima disk exhaustion mid-build** → `docker system prune -a -f`; check free
  space before any image build.

**What this falsifies:** nothing — the #1 thesis-killer ("NMOS won't run on
commodity k3s") **did not fire**. The Layer 4–5 thesis survives its first
contact with reality on ARM64.

---

## Q2 — Does the catalog YAML schema accommodate a real Layer 5 function?

**Yes, and it has grown only additively since.** `nmos-cpp.yaml` populated the
v0 schema (`key`, `display_name`, `summary`, `ebu`, `provision`, `configure`,
`finalise`, `dependencies`) without needing escape hatches or free-text "extras".

Two **additive** extensions appeared later, neither a reshape:
- `provision.namespace` — promoted from a drift-detector heuristic to an explicit
  schema field (Piece 8, Option A), so the invariant reads namespace from the
  entry instead of guessing.
- `monitoring:` — added by the NetBox-driven monitoring work (ADR-0038/WP6) to
  carry per-function scrape intent.

**What this falsifies:** nothing — falsification #2 ("schema needs a v0 reshape")
**did not fire**. The schema absorbed a real function and two follow-on needs by
adding optional blocks. The growth pattern to watch: each new cross-cutting
concern (monitoring, and likely identity/quotas next) wants its own top-level
block. That's sustainable as long as blocks stay optional and additive.

---

## Q3 — Does Configure-as-distinct-stage hold for nmos-cpp?

**Yes conceptually — but the *mechanism* moved from a playbook wrapper to the
role, via the Path A pivot.** This is the most important learning in Move 1.

The task spec (D2 = A) assumed Configure would be a `lifecycle-configure.yml`
wrapper importing a per-entry `configure-media/launch-nmos-cpp.yml` playbook. In
practice (ADR-0014/0016, **Path A**, 2026-05-06), the in-cluster execution model
changed: a thin AWX launcher in `dmf-runbooks` calls the `nmos-cpp` **role** with
a stage variable (`nmos_stage: provision|configure|finalise`). The
`lifecycle-configure.yml` wrapper and the `dmf-media/playbooks/configure-media/`
path became stubs — hence Pieces 2 and 5 are *obviated*, not done.

The ADR-0012 **split survived**: Provision still creates artifacts without
launching workloads; Configure still launches on operator action; Finalise still
tears down and resets the NetBox tag. NetBox `ipam.Service` registration did
**not** require the workload to be running to know its endpoint, so the
Provision/Configure boundary did not collapse (the specific failure ADR-0012 was
worried about).

**What this falsifies:** falsification #3 did not fire (the split is real), but it
**corrects the task spec's D2/D3 assumption** about *where* the split lives. The
stage boundary is a property of the **role**, not of a wrapper playbook. ADR-0012
stands; the wrapper-centric framing in commitments-v1 (C1/C3) is superseded by
the role-stage + AWX-launcher shape.

---

## Q4 — Can dmf-cms drive the lifecycle through AWX?

**Yes — the browser → Console → AWX → catalog deploy/teardown loop is
operator-confirmed.** Re-verified end-to-end on `y834-bcwe` and `imc1-cyh4`
(2026-05-29), grounded on live `kubectl`/`awx-manage`, not buffered stdout.

This piece exercised the AWX path harder than Move 2's single runbook, and **four
new failure modes surfaced** — all real, most fixed:

1. **Catalog Deploy 403 (scoped writer).** The `nmos-cpp` role's NetBox PATCH was
   denied because it fell back to a read-only token. Fixed by the **scoped catalog
   writer** (ADR-0032), verified on `wobe-9n0c`/`9y6o-zn0t` (2026-05-27). Pre-2026-05-27
   envs carry the skew — re-run 691+693 (see memory `adr0032_catalog_teardown_skew`).
2. **Offline galaxy egress.** `media-launch` triggered `ansible-galaxy install
   netbox.netbox` against public galaxy.ansible.com, breaking the self-contained
   sandbox (ADR-0030/0031). Fixed by baking `netbox.netbox`/`pynetbox` into the
   **DMF AWX EE 0.1.1** and pinning the EE on the NetBox **inventory source**, not
   just the JTs (inventory_update was still using the default EE → "unknown plugin
   nb_inventory"). Permanent internal collection source = ADR-0034 (separate WP).
3. **Double-launch TOCTOU.** The Console re-enabled the deploy button before the
   AWX job completed; a second click duplicated the job. Fixed in dmf-cms 0.9.2
   (`find_active_job_for_template` backend guard + frontend in-flight gate).
4. **Deploy↔finalise cross-action race.** The 0.9.2 guard dedupes the *same*
   action only; deploy (`media-launch`, JT14) and finalise (`media-finalise`, JT15)
   are different JTs, so firing them ~1s apart races (observed `imc1-cyh4`, jobs
   92/96: finalise ran before the deploy's Helm release existed → no-op teardown;
   deploy won; end state pods Running + tag `active` + a finalise that reported
   success but tore down nothing). **Still open** — needs a per-entry cross-action
   lock. Memory `project_dmf_catalog_deploy_finalise_race`.

**What this falsifies:** falsification #4 did not fire — dmf-cms *can* drive the
lifecycle — but the spike's predicted "new failure modes (Helm wait timeouts,
partial deploys, NetBox-tag drift)" landed as a richer set: auth scoping,
air-gap egress, and two concurrency edges. None is a path failure; all are the
kind of edge a single-runbook Move 2 could not have surfaced.

---

## Q5 — Does the hybrid AWX project layout (ADR-0014) work?

**Yes.** The thin launcher in `dmf-runbooks` resolves the `nmos-cpp` role from the
`dmf-media`/`dmf-runbooks` mirror project via configured `roles_path` (D3 = B —
the standard `hosts: + roles:` pattern, not cross-project `import_playbook ..`).
`roles_path` resolution did **not** fail, so ADR-0014 stands.

The non-obvious cost was **air-gap completeness** (see Q4 #2): making the hybrid
layout work offline meant the EE must carry the collections *and* be pinned on
every consumer (JTs **and** inventory sources). The 630 EE-tag fallback being
decoupled from the role default is a standing footgun (hand-sync on bump) flagged
for a single-source-of-truth follow-up.

**What this falsifies:** falsification #5 did not fire. The project-boundary story
holds; the work was in making it hermetic.

---

## Q6 — Does the drift detector catch NetBox/Helm divergence?

**Partially confirmed — the detector is built and schema-sound, but a live
drift-injection observation is an evidence gap.** Piece 8 landed
`operate-catalog-drift.yml` + `catalog-drift-check.yml` in `lifecycle-operate`,
and the Option A patch made it read `entry.provision.namespace` explicitly
(the previous heuristic is gone), asserting `lifecycle:active ↔ Helm release
exists`.

**Evidence gap:** the task spec's acceptance for this piece was behavioural —
*"manually delete a Helm release without flipping the NetBox tag → drift check
fails on next run and names the entry."* That specific fault-injection run is not
recorded in the handoffs. The detector's *correctness* is asserted by inspection
of the playbook logic, not by an observed failing run. **P0b (optional):** inject
the divergence on the next live env and append the observation here.

**What this falsifies:** inconclusive by direct observation. The invariant is
expressible and the detector reads the right source of truth; whether it *fires*
on real drift is the one Move 1 claim still resting on code review rather than a
recorded run.

---

## Acceptance — falsification or confirmation

From the task spec §"Acceptance" (line 265) and §"What this falsifies" (lines 54–65):

- [x] NMOS builds on ARM64 + runs under k3s flannel — registry+2 nodes Running (Q1)
- [x] Catalog schema accommodates nmos-cpp with no reshape — additive growth only (Q2)
- [x] Provision/Configure/Finalise split holds — at the role level post-Path-A (Q3)
- [x] dmf-cms drives the lifecycle through AWX — operator-confirmed loop (Q4)
- [x] Hybrid AWX project layout resolves roles across projects — `roles_path` works (Q5)
- [⚠️] Drift detector catches divergence — built + schema-sound; live injection = evidence gap (Q6)
- [x] **A write-up captures what was learned** — this document (Piece 9)

**Five of six falsifications did not fire; the sixth is unproven by direct
observation, not falsified.** No assumption was falsified outright.

---

## Bonus learnings (not predicted by the task spec)

### The Path A pivot was the real architectural finding
The task spec assumed wrapper-driven Configure. Reality replaced it with
AWX-launcher → role-stage execution (ADR-0014/0016). This obviated two Pieces and
relocated provision/configure/finalise into the role. The lesson:
**lifecycle-stage identity belongs to the unit that owns the workload (the role),
not to an orchestration wrapper.** Everything downstream (launchers, JTs, the
drift detector's namespace source) follows from that.

### Air-gap is a cross-cutting tax on every catalog entry
Closing the loop hermetically surfaced galaxy egress, EE collection-baking, and
the inventory-source EE pin — none of which a non-air-gapped spike would have
hit. ADR-0034 (Forgejo-git internal collection source) is the durable fix.

### Auth scoping is per-stage, not per-app
The 403 (Q4 #1) showed the NetBox writer token must be **scoped to the catalog
write**, and that the scope can silently degrade to read-only on older envs
(ADR-0032 + `adr0032_catalog_teardown_skew`). Move 2's "service-account auth
composes" generalizes, but catalog *writes* need their own scoped identity.

### Concurrency is the catalog's unsolved edge
Two distinct races (same-action TOCTOU, fixed; cross-action deploy↔finalise, open)
show the catalog needs a **per-entry lifecycle lock**, not just per-JT dedup. The
end-to-end loop works; near-simultaneous opposite actions are where it frays.

### Env identity got a model mid-flight
Born-inventory now writes per-env Site + Cluster + `dmf_*` custom fields
(ADR-0039); the env is a first-class NetBox object. Catalog consumers should scope
by Site/Cluster, not by a per-env tag.

### Shared-checkout branch hygiene is a recurring footgun
Commits silently landed on `feat/mxl` because the shared working copy was on it
(recovered via `git branch -f`). Now codified: verify `HEAD == main` before
touching any shared repo; use worktrees for isolation
(`feedback_verify_main_branch_before_work`, converge-on-main policy).

---

## ADR-0004 revisit verdict

ADR-0004 put the project in **experiment phase** ("does the architecture survive
contact with reality?"). Move 1's exit criterion was to write this doc and trigger
that revisit.

**Verdict:** the **catalog mechanism + NMOS-on-commodity-k3s** half of the thesis
**survived** — confirmed, not falsified. That is sufficient to retire Move 1 as a
gate item. It is **not** sufficient to exit experiment phase wholesale, because
thesis-killer #3 (EBU taxonomy under a genuinely two-layer/two-vertical function)
has only been tested by a single, well-behaved registry entry. The **MXL spike**
is the next, harder pressure test and should carry the experiment-phase question
forward.

> **This is a recommendation, not an ADR edit.** ADR-0004's status is left for the
> operator to flip; this doc records that its revisit criterion is now met.

---

## Implications for the next moves

1. **Move 1 is closed.** `move1-p9` → done; `TODOS.md` Move 1 row closed; this
   doc is the gate artifact. MXL = successor pressure, not successor evidence.
2. **Close the one evidence gap (P0b, optional):** a live drift-injection run for
   Q6 on the next env, appended here.
3. **Per-entry lifecycle lock** is the highest-value catalog follow-up (Q4 #4) —
   tracked in `TODOS.md`.
4. **ADR-0034** (internal collection source) graduates the air-gap fix from
   EE-baking to a maintainable source.
5. **MXL spike** inherits the open thesis-killer #3 question.

---

## Cross-reference

- Task spec: [`docs/plans/dmf-platform-move-1-task-2026-05-04.md`](../plans/dmf-platform-move-1-task-2026-05-04.md)
- Superseded provisional: [`docs/architectural-commitments-v1.md`](../architectural-commitments-v1.md)
- Move 2 learnings (sibling): [`docs/reviews/dmf-platform-move-2-learnings-2026-05-04.md`](dmf-platform-move-2-learnings-2026-05-04.md)
- Path A pivot: [`docs/handoffs/DMF Move 1 Gate 2 Path A Pivot Handoff 2026-05-06.md`](../handoffs/DMF%20Move%201%20Gate%202%20Path%20A%20Pivot%20Handoff%202026-05-06.md)
- Sandbox v0.1 gate (runtime proof): [`docs/handoffs/DMF Sandbox v0.1 Gate — Verification + Open Follow-Ups Handoff 2026-05-29.md`](../handoffs/DMF%20Sandbox%20v0.1%20Gate%20—%20Verification%20+%20Open%20Follow-Ups%20Handoff%202026-05-29.md)
- ADRs: 0004 (experiment stance), 0012 (Configure split), 0013 (catalog model), 0014 (AWX layout), 0016/0025 (Path A / in-cluster Helm), 0032 (scoped writer), 0034 (internal collections), 0038 (monitoring), 0039 (env identity)
- Strategic review: [`docs/reviews/dmf-platform-strategic-review-2026-04-30.md`](dmf-platform-strategic-review-2026-04-30.md)

---

## Single-line verdict

**The catalog loop held on commodity ARM k3s: NMOS built and ran, one real Layer 5
entry drove Provision→Configure→Finalise→Operate through Console→AWX with NetBox
as state-of-truth, and the only architectural surprise — Path A moving the stage
split from wrapper to role — strengthened the model rather than breaking it. The
nmos-cpp/catalog thesis is confirmed; the per-entry concurrency lock and a live
drift-injection check are the residue; MXL is the next pressure test, not the
proof of this one.**
