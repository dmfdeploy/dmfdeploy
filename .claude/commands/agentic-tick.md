---
description: Run one iteration of the DMF agentic harness loop
allowed-tools: Bash, Read, Edit, Write, Agent
---

# /agentic-tick — one iteration of the harness loop

You are the orchestrator for one tick of the DMF agentic harness. Execute the
steps below **in order**, halting at the first stop condition. Do not improvise
beyond what's specified — that's why the constitution exists.

**Read before doing anything else:**

1. `docs/agentic/CONSTITUTION.md` — the 14 rules. Note especially Rule 5
   (halt-vs-proceed rubric) and Rule 14 (autonomy budgets).
2. `docs/agentic/backlog.yaml` — find the next eligible task.
3. `docs/agentic/decisions-open.md` — note which gates are still `Status: open`.

## Step 1 — preflight

Run `bin/agentic/preflight.sh --json` and parse the output. Capture:

- `constitution_sha256` — compare to the value in the last block of
  `docs/agentic/loop-log.md` (if present). **Halt if different** — operator
  edited the constitution; harness must restart fresh.
- `status_fresh` — if `false`, the postflight will regenerate. Not a halt.
- `umbrella_dirty_count` + `dirty_subrepos` — record but do not halt yet
  (step 3 may legitimately produce dirty state).
- `decisions_open_count` + `backlog_pending|blocked|in_progress` — informational.

## Step 2 — select next eligible task

From `backlog.yaml`, pick the first entry where:

- `status: pending`
- `deps:` all reference entries with `status: done`
- `decision_gate:` is either `null` OR the matching entry in `decisions-open.md`
  has `Status: answered ...`

If no eligible task exists:

- All entries `done` and no terminal-marker → write a "ready-for-operator-push"
  handoff in `docs/handoffs/DMF Agentic Harness Terminal State <date>.md` and
  **halt**.
- Some entries `blocked` on `decisions-open.md` and nothing else eligible →
  write a handoff listing the blocked entries + open decision ids and
  **halt** (operator decides which to answer first).
- Otherwise → write a "progress" handoff and **halt**.

## Step 3 — dispatch

Worker assignment is in the selected entry's `worker:` field:

- `worker: claude` — execute the task yourself in this pane. Use Read/Edit/Write
  as normal.
- `worker: qwen-left` or `qwen-right` — send a structured prompt via
  `~/.claude/skills/agent-bridge/bin/agent-bridge send <pane>`. Before
  sending, apply the `/clear` protocol per Constitution Rule 5 / Layer 3
  "Qwen context hygiene" — clear if scope/kind/group changed, count ≥5, post-
  failure, or skill-guarded boundary crossed.
- `worker: operator` — this should never reach Step 3; operator-decision tasks
  surface via `decisions-open.md` (Step 2 marks them blocked). If you reach
  here, that's a bug — write a handoff describing it and halt.

The prompt to the Qwen pane MUST be self-contained and include:

```
TASK ID: <id>
SCOPE: <repo-path>
KIND: <rote|taste|...>
CONSTITUTION: $DMFDEPLOY_UMBRELLA/docs/agentic/CONSTITUTION.md
SKILL (if applicable): <skill-name> — read §0 before any tool call in scope.

WORK:
<acceptance items from backlog.yaml entry>

REPORT FORMAT:
- Reply with "DONE: <id>" + paths of files changed, OR
- Reply with "BLOCKED: <id>" + obstacle (do not improvise), OR
- Reply with one of the structured tokens from
  $DMFDEPLOY_UMBRELLA/docs/agentic/ISSUE-TEMPLATES.md (WORKAROUND, BUG,
  FEATURE-GAP, DECISION-NEEDED).
Do not push, deploy, or mutate cluster state. Do not edit other repos.
```

Read the reply via `agent-bridge read <pane>`.

## Step 4 — verify worker output

Run `git diff` (umbrella) and `git -C <touched-repo> diff` for each touched
repo. **Read the actual diff** — never trust the worker's DONE message alone
(Constitution Rule 7).

If diff matches the task's `acceptance:` items → proceed to Step 5.
If diff is empty, partial, or surprising → halt with a handoff describing
the gap.

## Step 5 — handle reply tokens (if any)

If the worker emitted a `WORKAROUND:`, `BUG:`, `FEATURE-GAP:`, or
`DECISION-NEEDED:` token, parse the fields per `ISSUE-TEMPLATES.md` and:

- For `DECISION-NEEDED:` → append entry to `decisions-open.md`. The K4
  `bin/agentic/issue-open.sh` is not yet built, so also stub a Forgejo issue
  draft in a handoff note for the operator to file manually.
- For `WORKAROUND:` / `BUG:` / `FEATURE-GAP:` → same: append a draft to
  `docs/handoffs/<date>-issue-drafts.md` for operator review. Once K4 lands
  this becomes `bin/agentic/issue-open.sh` invocation.

Mark the backlog entry's status accordingly:
- `WORKAROUND:` → entry continues (workaround applied); add `issue: pending`.
- `BLOCKED:` → entry → `status: blocked`.
- `DONE:` → entry → `status: done`.

## Step 6 — autonomy budget check

If you made a non-ADR-worthy choice during the task (Constitution Rule 5
rubric (a–e) all `false`), append a single line to
`docs/agentic/autonomous-decisions.md` with the format described there.

**Per-tick cap**: ≤1 autonomous decision. If you would log a second, halt
instead and write a handoff explaining why two decisions arose in one tick
(usually a sign the task scope was too large).

**Per-shift cap**: 10 autonomous decisions per `/agentic-run` invocation
(unless operator raised via `--autonomy-budget=N`). Count by reading
`autonomous-decisions.md` entries since the last `=== shift start ===`
marker in `loop-log.md`. On hit: soft-pause — write the "Autonomous decisions
taken" summary block to a handoff and halt for operator review.

## Step 7 — postflight

Run:

```bash
bin/agentic/postflight.sh \
  --tick-id <N> \
  --task <task-id> \
  --result done|blocked|halt \
  --touched <comma-separated-repo-list>
```

If postflight exits non-zero, **halt** with a handoff naming the failed guard.
Do NOT attempt to bypass — Constitution Rule 2.

## Step 8 — update backlog

Edit `docs/agentic/backlog.yaml` to reflect the new `status:` for the
selected entry. Commit ONLY the harness state changes (backlog.yaml,
autonomous-decisions.md, loop-log.md auto-updated by postflight) along
with the task's actual code changes — never split them.

## Step 9 — print summary

A 3-5 line summary on stdout:

- Task: `<id>` (worker: `<role>`)
- Result: `<done|blocked|halt>`
- Touched: `<repos>` or `<umbrella-only>`
- Autonomous decisions this tick: `<0|1>` (link to log if 1)
- Next eligible: `<next-id>` or `<none — would halt next tick>`

Then exit. The harness `/agentic-run` loop fires the next tick after a
self-paced wait (~20 min default, sooner if an obvious event landed).

---

## Halt conditions reference (Constitution + canonical plan)

1. Decision gate hit (Step 2 or Step 5 `DECISION-NEEDED`)
2. Guard failed (Step 7 postflight non-zero)
3. Backlog exhausted at current dependency layer (Step 2)
4. Error budget exceeded (same task fails postflight 2× — track via loop-log)
5. Constitution hash changed mid-loop (Step 1 comparison)
6. Dirty sub-repo not expected by current task (Step 1 vs Step 2)
7. Terminal state reached (Step 2)
8. Scrub blocked issue creation 2× on same content (K4 surface)
9. Forgejo API unreachable (K4 surface)
10. Local issue-mirror reconciliation failed (K4 postflight extension)

When you halt: write a handoff. STATUS.md auto-refreshes via pre-commit. The
operator reads the handoff to understand where you stopped.

---

## What this command does NOT do

- Does not push to GitHub. Ever. That's operator-only via `sync-to-github.sh`.
- Does not run `tofu apply`, `kubectl apply`, or cluster mutations except
  under skill-guarded scope where the skill's §0 was just read.
- Does not modify CONSTITUTION.md mid-loop (Rule 5).
- Does not log to `decisions-open.md` retroactively after a tick completes —
  that file is the forward queue, not history.
