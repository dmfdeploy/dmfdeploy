---
status: executed
date: 2026-05-12
---
# DMF Move 1 — Path A Reset (2026-05-12)

> **2026-05-19 update — partial re-pivot for catalog launchers.** The Path A
> architecture this audit normalised against is **partially superseded** for
> `media-*` JTs by the
> [DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19](./DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md)
> and [ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md).
> The "done" / "obviated" status of P1–P9 below stands as written — those
> Pieces are real and shipped under Path A. The catalog launcher's
> *implementation* now restructures (chart + EE-as-runtime), but the catalog
> *model* and Move 1 scope are unchanged.

> **Supersedes parts of**: [`dmf-platform-move-1-task-2026-05-04.md`](dmf-platform-move-1-task-2026-05-04.md).
> **Trigger**: Audit during agentic shift 5 (post Phase-0 baseline) revealed
> the May-4 Move 1 plan pre-dates the [ADR-0014 / ADR-0016 Path A pivot](../decisions/)
> (2026-05-06). Several Pieces had been implemented under Path A architecture
> with file shapes the source plan did not anticipate. Operator chose
> "Option B" (audit + mark satisfied entries done; re-derive narrative).

## TL;DR

Of the 9 source-plan Pieces:

- **P1** (catalog schema) — done; pre-existing
- **P2** (lifecycle-configure wrapper) — **OBVIATED** by Path A
- **P3** (Forgejo mirror + AWX projects) — done; AWX projects via
  `awx_catalog_projects`; Forgejo mirror deferred via 2026-05-07 GitHub
  push-mirror posture
- **P4** (NMOS provision-side) — done; consolidated into
  `dmf-runbooks/roles/nmos-cpp/tasks/provision.yml`
- **P5** (dmf-media configure-side launch) — **OBVIATED** by Path A
  consolidation into the role under dmf-runbooks
- **P6** (AWX launcher in dmf-runbooks) — done;
  `dmf-runbooks/playbooks/{launch,teardown}-nmos-cpp.yml` + AWX job
  templates `media-launch-nmos-cpp` + `media-finalise-nmos-cpp`
- **P7** (dmf-cms catalog page) — **PENDING** (real remaining work)
- **P8** (drift detector) — **PENDING** (real remaining work)
- **P9** (write-up) — **PENDING** (depends on P7 + P8)

So Move 1 has **3 genuine remaining work items**: P7, P8, P9.

## Path A architecture, in two paragraphs

The May-4 plan assumed three repos held three concerns:
- `dmf-media/` — media-domain roles + configure-side launch playbooks
- `dmf-infra/` — wrapper playbooks (`lifecycle-configure.yml`) that
  imported media launchers
- `dmf-runbooks/` — thin AWX launcher playbooks

Path A (May 6) consolidated this:
- The `nmos-cpp` role moved **into** `dmf-runbooks/roles/nmos-cpp/`
  (one role with three task files: `provision.yml`, `configure.yml`,
  `finalise.yml` per ADR-0012 stage split)
- `dmf-infra/k3s-lab-bootstrap/lifecycle-configure.yml` was rewritten as
  a stub redirecting to AWX
- AWX job templates (`media-launch-nmos-cpp`, `media-finalise-nmos-cpp`)
  call the launcher playbooks at `dmf-runbooks/playbooks/`, which in turn
  `include_role: nmos-cpp` with `nmos_stage: provision|configure|finalise`
- `dmf-media/` retains catalog metadata (`catalog/nmos-cpp.yaml`) but no
  longer holds workload-specific playbooks

This satisfies the source plan's intent (catalog-driven, lifecycle-aware,
single-source) via a different file layout. The May-4 spec items at the
old paths can never be satisfied because those paths are no longer the
architecture.

## Per-Piece audit findings

### P1 — catalog schema ✓ done
- `dmf-media/catalog/nmos-cpp.yaml` — exists, parses (8 top-level keys)
- `dmf-media/catalog/README.md` — exists, schema documented, references
  `docs/architecture/DMF Function Catalog Model.md` and ADR-0013

### P2 — lifecycle-configure wrapper — OBVIATED
- `dmf-infra/k3s-lab-bootstrap/lifecycle-configure.yml` exists but is a
  **stub** that explicitly says: *"Workload Configure (catalog launch,
  NetBox tag flip) is now driven through dmf-runbooks via AWX job
  templates. To configure a catalog entry: 1. Ensure entry exists in
  NetBox with tag lifecycle:bootstrapped 2. Launch the corresponding AWX
  job template (e.g. media-launch-nmos-cpp) 3. NetBox tag flips to
  lifecycle:active on success."*
- The source plan's `--list-tags` acceptance check would FAIL because
  the stub has no playbook tags. That acceptance is a remnant of
  pre-Path-A architecture, not a gap to fill.

### P3 — Forgejo mirror + AWX projects ✓ done
- `dmf-infra/.../awx-integration/defaults/main.yml` defines
  `awx_catalog_projects` containing `dmf-runbooks` and `dmf-media`
  (each with `roles_path`)
- `dmf-infra/.../forgejo-bootstrap/tasks/main.yml` has
  "Configure Forgejo mirror repos" task; `forgejo_mirror_repos` default
  is `{}` per the 2026-05-07 GitHub push-mirror posture (Forgejo now
  mirrors **out** to GitHub instead of pulling **in** from a personal
  upstream — this is a deliberate scope reduction, not a gap)
- `dmf-infra/.../awx-integration/tasks/main.yml` is ~1000 lines of AWX
  project + job template + permission management

### P4 — NMOS provision-side ✓ done (relocated)
- Source plan called for `dmf-infra/.../410-nmos-cpp-provision.yml` as a
  standalone playbook
- Path A relocated to `dmf-runbooks/roles/nmos-cpp/tasks/provision.yml`
  (called via launcher with `nmos_stage: provision`)
- Supporting files all present: `Dockerfile.registry`, `Dockerfile.node`,
  `scripts/push-nmos-images.sh`, `defaults/main.yml`

### P5 — dmf-media configure-side launch — OBVIATED
- Source plan: `dmf-media/playbooks/configure-media/{launch,teardown}-nmos-cpp.yml`
- Path A: directory does not exist; equivalent function lives at
  `dmf-runbooks/roles/nmos-cpp/tasks/configure.yml` invoked through the
  launcher (see P6)

### P6 — AWX launcher ✓ done
- `dmf-runbooks/playbooks/launch-nmos-cpp.yml` — exists; matches D3=B
  (`hosts: + roles:` style). Reads as: `include_role: nmos-cpp` with
  `nmos_stage: provision`, then again with `nmos_stage: configure`
- `dmf-runbooks/playbooks/teardown-nmos-cpp.yml` — exists (source plan
  named this `finalise-nmos-cpp.yml`; renamed for consistency with
  operator vocabulary)
- AWX job templates `media-launch-nmos-cpp` + `media-finalise-nmos-cpp`
  defined in `awx_catalog_job_templates` (defaults/main.yml line 130)

## Remaining work (real)

### P7 — dmf-cms catalog page (qwen-left, dmf-cms scope) **NOT STARTED**
- `dmf-cms/src/dmf_cms/catalog.py` — read catalog YAML from
  `/etc/dmf-cms/catalog/`, join with NetBox tag query
- `dmf-cms/src/dmf_cms/main.py` — add GET `/api/catalog`, POST
  `/api/catalog/<key>/deploy`, POST `/api/catalog/<key>/teardown`,
  GET `/api/catalog/<key>/status/<job_id>` (delegates to existing
  `awx.py` machinery)
- React routing — add a `/catalog` page with one card per entry,
  Deploy/Teardown buttons, status polling
- `dmf-cms/charts/dmf-cms/templates/configmap-catalog.yaml` — receives
  catalog YAML files as keys
- `dmf-infra/.../cms/tasks/main.yml` — gather catalog YAML from mirrored
  source repos, render into ConfigMap before `helm upgrade`

### P8 — drift detector (qwen-right, dmf-infra scope) **NOT STARTED**
- `dmf-infra/.../playbooks/lifecycle/operate-catalog-drift.yml` — for
  each catalog entry, fetch NetBox tag and Helm release presence;
  assert agreement
- `dmf-infra/.../lifecycle-operate.yml` — add the drift check after
  `test-layer6.yml`

### P9 — write-up (claude, umbrella scope) **NOT STARTED**
- `docs/reviews/dmf-platform-move-1-learnings-2026-05-XX.md` — six
  Q-and-A sections matching the six §"What this falsifies" items in
  the source plan, plus §"Bonus learnings". MUST include a section
  on the Path A pivot's effect on this Move (P2 + P5 obviation as a
  learning about premature-detail in Move planning).
- `docs/architectural-commitments-v1.md` — Move 1 + Move 2 closed →
  list architecture pieces that survived contact with reality and stop
  reshaping. Per strategic review's commit gate.

## Backlog state after this audit

```
move1-p1-catalog-schema:                 done       (pre-existing)
move1-p2-lifecycle-configure-wrapper:    obviated   (Path A stub)
move1-p3-forgejo-mirror-awx-projects:    done       (Path A; mirror deferred)
move1-p4-nmos-provision:                 done       (role provision.yml)
move1-p5-nmos-configure-launch:          obviated   (Path A consolidation)
move1-p6-awx-launcher-runbooks:          done       (playbooks + AWX templates)
move1-p7-dmf-cms-catalog-page:           pending    (qwen-left, real work)
move1-p8-drift-detector:                 pending    (qwen-right, real work)
move1-p9-writeup:                        pending    (claude, depends on P7+P8)
```

`obviated` is treated as terminal (dependency-equivalent-to-done).
`move1-p9` deps updated to skip the obviated entries while still
requiring P7 + P8 to be observable for the write-up.

## Lessons captured for the broader retrospective

- **Plan-vs-pivot drift**: the Move 1 plan was 2 days old when Path A
  landed; the plan's per-Piece file paths became stale within a week.
  Future plans should reference architectural commitments at the level
  of *intent* (e.g. "configure-side launch with NetBox tag flip"),
  binding to file paths only when those paths are themselves
  load-bearing decisions.
- **Audit-first dispatch**: the agentic harness now has a concrete
  precedent for treating pre-existing repo state as authoritative
  truth, with the source plan as guiding-but-not-binding intent.
  When backlog acceptance items reference paths that exist in
  unexpected shapes, halt + audit + reshape — do not dispatch as
  written.
- **`obviated` as a backlog status**: introduced this shift to mean
  "the original Piece is no longer applicable, equivalent function
  exists elsewhere, no remediation needed". Treated as terminal for
  dependency resolution but distinguishable from `done` in audit
  trails.

## Cross-references

- Source plan: [`docs/plans/dmf-platform-move-1-task-2026-05-04.md`](dmf-platform-move-1-task-2026-05-04.md)
- Path A pivot ADRs: [ADR-0014, ADR-0016](../decisions/)
- ADR-0012 (configure-stage-distinct-from-provision): [`docs/decisions/0012-configure-stage-distinct-from-provision.md`](../decisions/0012-configure-stage-distinct-from-provision.md)
- ADR-0013 (media-function-catalog-model): [`docs/decisions/0013-media-function-catalog-model.md`](../decisions/0013-media-function-catalog-model.md)
- Audit trigger handoff: [`docs/handoffs/DMF Agentic Shift 4 Move1 Plan-vs-Reality Halt 2026-05-12.md`](../handoffs/DMF%20Agentic%20Shift%204%20Move1%20Plan-vs-Reality%20Halt%202026-05-12.md)
