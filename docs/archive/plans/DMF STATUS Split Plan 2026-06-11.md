---
status: executed
date: 2026-06-11
executed: 2026-06-13
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/40
---
# DMF STATUS Split Plan 2026-06-11

> **Goal:** stop committing the volatile auto-generated repo-state tables of
> `STATUS.md` while keeping the hand-edited operator notes committed,
> versioned, and reviewable. Removes the one-commit-lag invariant, cross-PR
> merge conflicts, rebase-merge hash rot, and generated review noise in one
> move.
>
> Tracking: [umbrella issue #40](https://github.com/dmfdeploy/dmfdeploy/issues/40).
> Context: the lkirc review rounds on PR #39; refs #32 (working-model
> enforcement plan, executed).

## Problem

`STATUS.md` is a hybrid file:

- a **hand-edited operator-notes section** (`<!-- HUMAN-START/END -->`) —
  genuine cross-session memory; must stay committed;
- **auto-generated tables** (repo state, active plans, recent activity)
  derived from **live git state**, regenerated and auto-staged by the
  pre-commit hook on every umbrella commit.

Committing the generated half has structural costs, amplified by the
PR + auto-merge working model:

1. **One-commit lag, by construction.** The hook regenerates STATUS
   *mid-commit*, so the committed copy can never reference the commit that
   carries it. `--check` from a PR checkout therefore always reports drift
   (two review rounds on #39 were spent on this).
2. **Cross-PR conflicts.** Every PR regenerates STATUS → any two concurrent
   umbrella PRs conflict on it → the second auto-merge fails. Currently only
   avoidable by strictly serializing PRs.
3. **Hash rot.** Rebase-merge rewrites commit hashes, so the tables on `main`
   reference commits that don't exist on `main`; topic-branch names get baked
   into the published file.
4. **Review noise.** Generated churn lands in every diff.
5. **No reader.** The boot ritual regenerates *before* reading; the committed
   generated copy serves only web browsers, for whom it is wrong-on-arrival.

**Not in scope:** `docs/SCRIPTS.md` and `docs/plans/INDEX.md` are also
committed-generated but derive from *committed file content* — stable, no
lag, no conflicts. They stay exactly as they are.

## Target design

1. **`STATUS.md` (committed)** = a small static header + the operator-notes
   section only. The header points at the generator and at
   `STATUS.local.md`. The HUMAN markers stay so existing tooling and habits
   keep working.
2. **`bin/generate-status.sh`** writes the full snapshot (tables + a copy of
   the committed notes, so the local read experience is unchanged) to
   **`STATUS.local.md`**, which is **gitignored**. `--check` is dropped or
   repurposed (nothing committed is generated anymore, so there is nothing to
   drift).
3. **`.githooks/pre-commit`** drops the STATUS regenerate-and-stage step.
   SCRIPTS.md and plans-INDEX auto-refresh and the doc/scrub gates stay.
4. **Boot ritual + docs sweep:** CLAUDE.md / AGENTS.md / QWEN.md step 2
   becomes "run `bin/generate-status.sh`, read `STATUS.local.md`"; the
   end-of-session rule still edits `STATUS.md` (notes). Update
   `docs/WORKING-MODEL.md` §1 source-of-truth row, `docs/INDEX.md`, and any
   `STATUS.md` references that mean the snapshot rather than the notes
   (grep sweep; historical docs untouched per convention).
5. **Migration commit:** rewrite `STATUS.md` to header + current HUMAN
   section; add `STATUS.local.md` to `.gitignore`.

## Work packages

| WP | Content |
|---|---|
| WP1 | `generate-status.sh`: emit `STATUS.local.md`; keep notes-embedding; retire `--check` |
| WP2 | pre-commit hook: drop STATUS step |
| WP3 | migration: shrink `STATUS.md`, gitignore `STATUS.local.md` |
| WP4 | docs sweep: boot rituals ×3, WORKING-MODEL.md, docs/INDEX.md |

One PR, closes #40, flips this frontmatter to `executed` in the same change.

## Acceptance

- Two concurrent umbrella PRs no longer both touch `STATUS.md` (unless both
  edit operator notes — a real conflict that *should* surface).
- Fresh clone: `bin/generate-status.sh` produces `STATUS.local.md` with
  tables + notes; `git status` stays clean afterwards.
- Committed `STATUS.md` contains no volatile git-state content.
- `bin/check-docs.sh`, sync-check, and the scrub gate stay green; nothing in
  CI references the removed `--check` mode.
