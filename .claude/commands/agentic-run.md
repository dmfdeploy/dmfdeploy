---
description: Start a self-paced agentic harness shift (loops /agentic-tick until halt)
allowed-tools: Bash, Read, Edit, Write, Agent, Skill
---

# /agentic-run — self-paced agentic shift

You are starting a new shift of the DMF agentic harness. The shift continues
until **any** halt condition fires, then writes a handoff and stops. The
operator returns to the handoff, optionally answers any surfaced decisions,
and re-invokes `/agentic-run` to continue.

## Step 0 — shift open

1. Read `docs/agentic/CONSTITUTION.md` end-to-end. Compute its SHA-256:
   `shasum -a 256 docs/agentic/CONSTITUTION.md`. Remember it for the
   per-tick hash-drift check (Halt Condition 5).
2. Append a marker to `docs/agentic/loop-log.md`:

   ```
   ═══ shift start @ <ISO-timestamp> ═══════════════════════════════════════════
   constitution_sha256: <hash>
   autonomy_budget:     <N from --autonomy-budget=N, default 10>
   resumed:             <true if --continue-after-summary, false otherwise>
   ```

3. Quick survey of state — read `decisions-open.md` and count entries with
   `Status: open`. If `≥ 6` (the K1 seed count) AND no `Status: answered`
   entries exist anywhere → **halt immediately** with a handoff: the seed
   gates need at least one operator answer before useful work can start.
   ADR-0020 promotion is the load-bearing one.

## Step 1 — invoke the loop

Run `/agentic-tick` in a self-paced loop. After each tick:

- If the tick returned a halt → exit Step 1 → go to Step 2.
- If the tick returned `done` or `blocked` for a task → wait briefly
  (default 60-120 s; quicker if the next task is queued and ready), then
  fire the next `/agentic-tick`.
- If the shift autonomy budget is exhausted (per Constitution Rule 14) →
  exit Step 1 → go to Step 2 with reason "shift budget".

Use the `Skill` tool to invoke `/loop` skill if available, OR drive the
loop directly via `ScheduleWakeup` if `/loop` is not present. Self-paced
means **you** decide the wait between ticks based on what just happened —
not a fixed interval.

## Step 2 — shift close

When the loop halts:

1. The tick that halted already wrote its own halt handoff (per
   `/agentic-tick` Halt Conditions). Read that handoff.
2. Append a shift-close block to `docs/agentic/loop-log.md`:

   ```
   ═══ shift close @ <ISO-timestamp> ═════════════════════════════════════════
   ticks_run:            <count>
   tasks_done:           <count>
   tasks_blocked:        <count>
   autonomous_decisions: <count>
   halt_condition:       <1..10>
   handoff:              <path>
   ```

3. Run `bin/agentic/postflight.sh` one more time (no `--tick-id`) to ensure
   STATUS.md and `docs/SCRIPTS.md` are fresh.
4. Commit the harness state changes (loop-log, autonomous-decisions, backlog)
   along with the halt handoff in a single commit:

   ```
   chore(agentic): shift close — <N> ticks, halt cond <M>
   ```

   This commit is the audit-readable boundary the operator scans on return.

## Flags

- `--autonomy-budget=N` — raise per-shift autonomous decision cap from default
  10 to N. Use sparingly; high N defeats the soft-pause review semantic.
- `--continue-after-summary` — resume after a soft-pause caused by a previous
  shift hitting its autonomy budget. Skips Step 0's "fresh state" check.
- `--dry-run` — Step 0 runs, but Step 1 is replaced with a single
  `/agentic-tick --dry-run` that does not mutate state. Useful for verifying
  the loop machinery without consuming budget.

## What this command does NOT do

- Does not push to GitHub. The shift terminates with "ready-for-operator-push"
  state when the v0.1.0 backlog is exhausted; the operator runs
  `bin/sync-to-github.sh` themselves after answering remaining decisions.
- Does not run unattended for more than ~10 autonomous decisions before
  soft-pausing (Rule 14).
- Does not bypass any hook, gate, or skill — Constitution Rules 1, 2, 4.

---

**Cross-references**

- Tick body: `.claude/commands/agentic-tick.md`
- Constitution: `docs/agentic/CONSTITUTION.md`
- Canonical plan: `docs/plans/DMF Agentic Harness Plan 2026-05-11.md`
- Forward decision queue: `docs/agentic/decisions-open.md`
- Retrospective decision log: `docs/agentic/autonomous-decisions.md`
- Tick history: `docs/agentic/loop-log.md`
