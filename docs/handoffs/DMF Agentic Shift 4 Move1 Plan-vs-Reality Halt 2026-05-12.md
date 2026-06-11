# DMF Agentic Shift 4 — Move 1 Plan-vs-Reality Halt (2026-05-12)

> **From**: Claude (orchestrator), agentic-shift 4, ticks 8–9.
> **To**: Operator returning to the workspace.
> **Why halt**: The Move 1 source plan was authored 2026-05-04, two days
> before the 2026-05-06 ADR-0014/0016 **Path A pivot**. The backlog entries
> I just generated (`move1-p2..p9`) describe pre-pivot file shapes that
> don't match what's actually on disk. Dispatching qwen against them would
> either overwrite working Path-A code or produce stale-shape duplicates.

## What landed this shift

| Tick | Task | Worker | Result |
|---|---|---|---|
| 8 | group-c-expansion | claude | done — produced 9 `move1-p*` entries |
| 9 | move1-p1-catalog-schema | qwen-left (not dispatched) | done — pre-existing work satisfies acceptance |

Commits: tick 8 `1d69332` (umbrella); tick 9 will land in the shift-close
commit alongside this handoff.

Per-shift autonomy: **1/10** used (group-c framing decision).

## The mismatch — pre-pivot plan vs. post-pivot reality

The Move 1 source plan was written assuming pre-Path-A architecture:
- Configure-side launch playbooks live in `dmf-media/playbooks/configure-media/`
- AWX projects sourced separately from `dmf-runbooks` AND `dmf-media`
- Provision-side playbook named `410-nmos-cpp-provision.yml`

Path A pivot (ADR-0014 + ADR-0016, 2026-05-06) reshaped this:
- The `nmos-cpp` role was relocated **into** `dmf-runbooks/roles/nmos-cpp/`
  (it now lives there, not in dmf-media)
- AWX launchers are thin playbooks under `dmf-runbooks/playbooks/`
- `dmf-infra/k3s-lab-bootstrap/lifecycle-configure.yml` was rewritten as
  a **stub** explaining "workload Configure is now driven through
  dmf-runbooks via AWX job templates"
- `dmf-infra/k3s-lab-bootstrap/playbooks/runbooks/` holds
  `media-launch-nmos-cpp.yml` and `media-finalise-nmos-cpp.yml`
  (different naming + location than the source plan's spec)

## Per-Piece status snapshot (file existence only — not content audit)

| Piece | Backlog acceptance file path | Actual state |
|---|---|---|
| **P1** catalog schema | `dmf-media/catalog/{nmos-cpp.yaml, README.md}` | **DONE** — exists, parses, schema documented |
| **P2** lifecycle-configure wrapper | `dmf-infra/.../lifecycle-configure.yml` | EXISTS but is a **post-pivot stub** describing AWX-based architecture, not the source-plan's `import_playbook` shape |
| **P3** Forgejo mirror + AWX projects | `dmf-infra/.../awx-integration/tasks/main.yml` | EXISTS and is **substantial** (1000+ lines, includes `dmf-runbooks` project setup, awx_catalog_project_ids, etc.). Probably partially or fully done in Path A shape. |
| **P4** NMOS provision-side | `dmf-infra/.../410-nmos-cpp-provision.yml` (per spec) | NOT FOUND under that name; instead `playbooks/runbooks/media-launch-nmos-cpp.yml` + `media-finalise-nmos-cpp.yml` exist (Path A naming) |
| **P5** dmf-media configure playbooks | `dmf-media/playbooks/configure-media/` | DIRECTORY DOES NOT EXIST — Path A relocated this to dmf-runbooks |
| **P6** dmf-runbooks AWX launcher | `dmf-runbooks/{launch,finalise}-nmos-cpp.yml` | NOT FOUND at root; possibly under playbooks/ or different naming |
| **P7** dmf-cms catalog page | `dmf-cms/src/dmf_cms/catalog.py`, etc. | NOT FOUND — this is genuine remaining work |
| **P8** drift detector | `dmf-infra/.../operate-catalog-drift.yml` | NOT FOUND — genuine remaining work |
| **P9** write-up | `docs/reviews/dmf-platform-move-1-learnings-…` | NOT FOUND — naturally last; depends on P1-P8 |

## Why I halted instead of proceeding

Per Constitution Rule 5 rubric:
- **(c)** the choice contradicts/supersedes existing ADR — *yes*: any
  reshape of move1-p2..p9 supersedes ADR-0014/0016 Path A interpretation
  baked into the source plan
- **(d)** removes an option already considered in a plan doc — *yes*:
  marking pre-existing work as "satisfies the spec's intent under a
  different file shape" is a substantive interpretation choice

That clears the bar for ADR-worthy → halt + surface, not auto-resolve.

## Operator decisions needed

Pick a strategy for getting Move 1 unstuck. The three plausible options:

### Option A — Reshape `move1-p2..p9` entries to Path A reality

Rewrite each backlog entry's `acceptance:` to point at actual Path A file
paths. Lower acceptance bar to "files match Path A architecture" rather
than "files match the May 4 source plan." Then the harness audits each
Piece against its real-world deliverables; some get auto-marked done,
others (P5, P7, P8) remain pending qwen dispatch.

**Pros**: smallest reshape; preserves the 9-Piece structure as a tracking
unit; respects the work that's already happened.

**Cons**: the source plan becomes documentation-of-intent rather than
truth-of-state; future re-readers may be confused. Worth a follow-up note
on the source plan saying "superseded by Path A pivot — see backlog +
ADR-0014/0016 for actual implementation shape."

### Option B — Audit + mark P2-P6 done if Path A satisfies their intent

Open each Path A file (lifecycle-configure stub, awx-integration tasks,
playbooks/runbooks/media-launch-*, etc.) and decide whether the *intent*
of the source-plan Piece has been served. Mark satisfied entries done.
Leave only the genuine gaps (P5 if no equivalent exists, P7, P8, P9) as
pending work.

**Pros**: ground-truth backlog; minimum re-work.

**Cons**: requires substantive code reading on each Piece. Probably one
shift of work for a single agent (claude or qwen-left depending on scope
of each audit).

### Option C — Re-derive Move 1 from a fresh post-Path-A plan

Author a new plan doc (e.g. `docs/plans/DMF Move 1 Path A Reset
2026-05-12.md`) that captures what's actually been done + what remains,
in Path A terms. Discard `move1-p2..p9`; replace with the fresh plan's
expansion.

**Pros**: cleanest forward trajectory; documents the pivot's effect on
Move 1 as a coherent narrative.

**Cons**: heaviest authoring cost; loses the audit trail of the Move 1
plan as it was originally conceived.

## Recommendation

**Option B** for the audit, then capture the findings in a thin **Option
C** new plan doc. This combines ground-truth assessment with a clean
forward narrative and minimal redundancy.

Concretely:
1. Operator (or claude in next shift) audits P2, P3, P4, P5, P6 against
   actual Path A files.
2. Mark satisfied entries `done`; surface real gaps.
3. Write a short `docs/plans/DMF Move 1 Path A Reset 2026-05-12.md`
   that says "P1, P2, P3, P4, P6 satisfied via Path A; P5 obviated; P7,
   P8, P9 remain pending. See backlog entries for deliverables."
4. The harness then dispatches the genuine remaining work (likely just
   P7 dmf-cms catalog page, P8 drift detector, P9 write-up).

## What's next-eligible after this halt resolves

If Option B audit completes and Path A equivalents satisfy P2-P6:
- Next eligible: `move1-p7-dmf-cms-catalog-page` (qwen-left, dmf-cms scope —
  watch for skill-guarded boundary if it touches release machinery).
- After P7: `move1-p8-drift-detector` (qwen-right, dmf-infra), then
  `move1-p9-writeup` (claude, umbrella).
- group-d-expansion (Tier A finish) also eligible — probably worth
  expanding before P7 so qwen-right has parallel work available.

## Other open items (carried from prior handoff)

Unchanged from
[`DMF Agentic Shift 3 Phase 0 Milestone Halt 2026-05-12.md`](DMF%20Agentic%20Shift%203%20Phase%200%20Milestone%20Halt%202026-05-12.md):

- `bin/agentic/install-agentic-hooks.sh` not yet run — closes hygiene
  gate's `.githooks/pre-push` gap across the 6 public repos.
- GitHub `dmfdeploy` org + 6 empty repos not yet stood up
  (`rel-p2-github-org-setup`).
- LAN Forgejo + forgejo-lab dev creds not yet rotated
  (`rel-p1-rotate-forgejo-dev-creds`).
- dmf-cms WIP at `dmf-cms` `stash@{0}` (AdminOverview QR fix) still
  awaiting pop-or-drop decision.
- dmf-env has WIP for the `aliyun-123` env (terraform/aliyun-123/main.tf
  + 3 inventory group_vars files) — operator-side, not blocking the
  agentic harness but noted in preflight.

## Resume

```bash
cd "$DMFDEPLOY_UMBRELLA"
git fetch && git pull
bin/generate-status.sh
# decide A/B/C strategy above
# then either:
/agentic-run                 # if you've reshaped backlog entries first
# or:
# manually audit P2-P6 against Path A files; update backlog.yaml
# `status:` per finding; then /agentic-run
```
