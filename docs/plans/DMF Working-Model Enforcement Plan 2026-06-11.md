---
status: executed
date: 2026-06-11
executed: 2026-06-11
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/32
---
# DMF Working-Model Enforcement Plan 2026-06-11

> **✅ EXECUTED 2026-06-11, same day** (issue #32 closed by the PR carrying this
> flip). WP1–WP6 + WP8 all delivered and merged: canonical WORKING-MODEL.md,
> template-identical agent blocks in all 9 repos (strict CI sync), SessionStart
> digest hooks, issue-link PR gates, the W2 hard-fail after the 6-plan
> adjudication, the backlog-hygiene detector + weekly schedule (first run's 10
> findings triaged to zero), and approval-driven auto-merge (#34).
> **WP7 (org `.github`) was optional and is NOT executed** — deferred with a
> written analysis on #32 (slim scope recommended: org profile README +
> CoC/SUPPORT/GOVERNANCE defaults + new-repo bootstrap checklist). If picked
> up, it gets a fresh issue.

> **Goal:** any agent (Claude Code, codex, qwen) or human contributor working in
> **any** of the 9 repos is exposed to — and where possible machine-held to —
> the GitHub working model (Issues / milestones / Project board / Discussions)
> and the documentation rules, so the model stops drifting.
>
> Tracking: [umbrella issue #32](https://github.com/dmfdeploy/dmfdeploy/issues/32).
> Reviewed 2026-06-11 by claude-bottom (dmf-init pane); all five review points
> folded in (marked **[R1]–[R5]** below).

## Problem

The working model is real and already partially machine-enforced, but the
knowledge of it lives only in umbrella prose:

- Component-repo agent files say **nothing** about issues/milestones/board/
  Discussions — confirmed first-hand in `dmf-cms` (grep: zero hits) and
  `dmf-init` (claude-bottom: knew the model only via per-machine agent memory,
  which doesn't scale across agents or machines) **[R5]**.
- No CI anywhere ties a PR to an issue.
- No check detects backlog-hygiene drift (missing milestone, missing
  `component:*`/`workstream:*` labels, absent from Project #1, empty board
  fields, untriaged component-repo issues).
- The model itself is smeared across CLAUDE.md, CONTRIBUTING.md, ADR-0041, and
  the entrance plan — no single canonical URL to point a gate or an agent at.
- The "umbrella backlog is canonical; component-repo issues are drive-by
  intake" policy is written nowhere.

## Enforcement ladder

Prose an agent must choose to read < context an agent is *given* < CI that
fails. Work packages are ordered accordingly.

### WP1 — canonical doc (umbrella, this session)

`docs/WORKING-MODEL.md`: the single canonical statement of the GitHub working
model + documentation rules. Contains a marked **digest** section
(`<!-- WM-DIGEST-START/END -->`) that runtime tooling extracts — the digest is
maintained once, here, and never copied by hand **[R1]**. Everything else
(CONTRIBUTING, agent files, hook output) points at or extracts from this file.

### WP2 — mandatory agent-context block, all 9 repos

An **identical, minimal** block (3 rules + link to WORKING-MODEL.md — no more
**[R1]**) inserted between `<!-- WORKING-MODEL-BLOCK-START/END -->` markers in
`CLAUDE.md`, `AGENTS.md`, and `QWEN.md` of every repo. The canonical copy is
`docs/templates/working-model-block.md` in the umbrella;
`bin/check-working-model-sync.sh` diffs every discovered copy against it so the
27 copies cannot drift **[R1]** (umbrella copies gated in umbrella CI/pre-commit;
component repos add a `--strict` invocation to their `ci.yml` in the WP4 batch,
fetching the template from the umbrella raw URL).

**This block is the forcing mechanism for codex and qwen** — their harnesses
auto-load AGENTS.md/QWEN.md as context; they have no hook system **[R2]**.

### WP3 — Claude Code SessionStart hook, all 9 repos

Checked-in `.claude/settings.json` `SessionStart` hook running
`bin/working-model-digest.sh`, which locates the umbrella checkout
(`$DMFDEPLOY_UMBRELLA` → script-relative → sibling `../dmfdeploy`) and prints
the WM-DIGEST section of `docs/WORKING-MODEL.md` into session context **at
runtime — no embedded copy** **[R1]**.

Stated limits **[R2]**: covers Claude Code only (codex/qwen are covered by
WP2); checked-in hooks require the user's one-time trust approval per project,
so this is *forced-once-trusted*, not unconditional; the script **degrades
gracefully** — if the umbrella checkout is absent it emits a one-line warning
and exits 0, never wedging the session.

### WP4 — PR-must-link-issue CI gate, all 9 repos

A job in `guard.yml`: the PR body must reference an issue, else fail; escape
hatch = `no-issue` label for trivial changes.

**Cross-repo reference trap [R3]:** the canonical backlog lives in the
umbrella, and GitHub closing keywords only work same-repo unless fully
qualified — a bare `#N` in a component-repo PR silently targets that repo's own
issue #N. Therefore:

- **Umbrella PRs:** `(Closes|Fixes|Refs) #N` accepted.
- **Component-repo PRs:** the gate **requires** the qualified form
  `(Closes|Fixes|Refs) dmfdeploy/dmfdeploy#N` (or the full issue URL) and
  **rejects bare `#N`**.
- **Batch convention (pinned):** one umbrella issue per cross-repo batch; all
  nine PRs reference it qualified.

### WP5 — promote frontmatter warning to failure (umbrella)

Backfill `tracking_issue` for the 6 active plans missing one (operator
adjudicates which are genuinely active vs stale-active), then flip
`bin/check-docs.sh` W2 ("active but no tracking_issue") from warn to **fail**.

### WP6 — backlog-hygiene drift detector (umbrella)

`bin/check-backlog-hygiene.sh` (gh GraphQL, read-only) flagging:

- umbrella issues missing milestone, missing `component:*` or `workstream:*`
  label, not on Project #1, or with empty Component/Workstream board fields;
- active plans whose tracking issue is closed (extends existing W3);
- **untriaged component-repo issues older than N days** (default 7) — the
  two-backlog policy gets a detector, not just prose **[R4]**.

Run weekly via a scheduled umbrella workflow that opens/updates a single
"backlog hygiene" issue; also runnable locally.

### WP8 — approval-driven auto-merge (added 2026-06-11, [issue #34](https://github.com/dmfdeploy/dmfdeploy/issues/34))

Operator request: after approval, PRs merge themselves (rebase) and delete
their branch — regardless of who submitted or approved. Three layers:

1. **Repo settings, all 9:** `allow_auto_merge` + `delete_branch_on_merge`
   (umbrella also dropped squash/merge-commit for rebase-only parity).
2. **Ruleset `required_status_checks`, all 9:** the gap that made auto-merge
   unsafe — green CI was a human habit, not a gate. Contexts harvested from
   the WP2–4 batch PRs (dco + guard incl. `issue-link` + per-stack ci incl.
   `working-model`). Non-strict (no forced re-runs after each merge).
   Found+fixed along the way: **the umbrella had no rulesets at all** — branch
   + 2 tag rulesets cloned from dmf-cms.
3. **`automerge.yml`, all 9:** arms GitHub-native rebase auto-merge on PR
   open/reopen/ready/label-change; `hold` label disarms; drafts skipped.
   `pull_request_target`, metadata-only, never checks out PR code.

Behavioral change: **approval = landing** (no post-approval hold window);
documented in WORKING-MODEL.md §6.

### WP7 (optional) — org `.github` repo

`dmfdeploy/.github` with default community-health files + org profile README
pointing at WORKING-MODEL.md, so future repos inherit the model with zero
setup.

## Execution order

| WP | Scope | Status |
|---|---|---|
| WP1 canonical doc + digest | umbrella | this session |
| WP2 (umbrella part): template + blocks in umbrella agent files + sync-check | umbrella | this session |
| WP3 (umbrella part): digest script + umbrella SessionStart hook | umbrella | this session |
| WP2/3/4 propagation: blocks + settings hook + guard.yml job, 8 component repos | 8 repos | follow-up PR batch (one umbrella issue = #32, all PRs reference it qualified) |
| WP5 backfill + flip W2 | umbrella | after operator adjudicates the 6 plans |
| WP6 hygiene detector + schedule | umbrella | follow-up |
| WP8 auto-merge: settings + required-checks rulesets (live) + automerge.yml (9-repo batch) | all repos | 2026-06-11, issue #34 |
| WP7 org .github | org | optional, last |

## Acceptance

- A fresh Claude Code session in any repo receives the digest without reading
  anything voluntarily; codex/qwen receive the block via AGENTS.md/QWEN.md.
- `bin/check-working-model-sync.sh --strict` passes in every repo's CI; editing
  any block copy without the template fails CI.
- A component-repo PR with a bare `#N` reference fails the gate; qualified
  passes; `no-issue` label bypasses.
- `check-docs.sh` fails on an active plan without `tracking_issue`.
- The weekly hygiene run reports zero findings on a clean backlog and flags a
  seeded violation.
