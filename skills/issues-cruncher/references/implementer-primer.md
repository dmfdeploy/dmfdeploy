---
name: implementer-primer
description: How the implementer (qwen lane) operates in the lifter/fix-round loop — scope discipline, verification, test design, failure modes
type: reference
---

# Implementer Primer (qwen lane)

## Receiving a brief

The orchestrator sends a scoped brief via agent-bridge, usually pointing at a spec file (`/tmp/slice-N-spec.md`) or a direct task description (e.g., an umbrella issue number with implementation instructions). **Read the full brief before touching code.** Identify: repo path, branch, files to change, verify commands, and commit/commit-gate instructions.

## Scope discipline — execute ONLY what's specified

Do not fix adjacent issues, refactor nearby code, or touch unrelated files. If you spot something else that looks wrong, flag it in the DONE reply — do not fix it. The brief is the boundary.

## Style and precedent matching

Match existing indentation, naming, and structure exactly. When the brief says "mirror X" (e.g., the existing `bootstrap_start` active-run guard), copy that entry's structure verbatim — same keys, same lock acquisition pattern, same error status codes. Do not invent a new pattern when a precedent exists in the same codebase.

## Test discipline — discriminating tests

Every fix that adds a guard must have a test that **discriminates**: it must FAIL on the old code and PASS on the new code. A test that passes vacuously (e.g., a single-process cancellation test that doesn't exercise the actual race) is not a test.

**Design rule for discrimination:** ask "what would the OLD code do differently under this test?" If the answer is "nothing," the test is not discriminating. In the createnew idempotency fix, the first cancellation test used a single-process fake wizard — it passed with the old `proc.kill()` because there were no descendants. The discriminator was a fake wizard that spawns a background descendant; the old code would leave it alive, the new group-kill catches it.

**Independent regression design:** if you (the implementer) authored both the fix and its discrimination test, flag this in the DONE reply so the orchestrator can route the test for independent review. Self-authored tests can have blind spots — a second pair of eyes catches vacuous assertions.

## Verify before reporting DONE

Run the project's full test suite, lint, and type checks before sending DONE. Paste the actual output — not a claim. The orchestrator re-verifies every claim on disk.

```
.venv/bin/python -m pytest tests/ -q     → paste the summary line
.venv/bin/ruff check ...                  → paste "All checks passed" or the errors
```

For fix rounds: amend into the existing commit (`git commit --amend`), do not create a separate fix commit.

## Reporting via agent-bridge

Reply `DONE` or `BLOCKED` via `agent-bridge send <orchestrator> -- "<message>"`. Include pasted evidence (grep output, test summaries, diff stats). Do not assert claims without the raw output. If blocked, state the specific reason and what would unblock you.

## No commits or pushes

The orchestrator gates all commits. Stage changes, verify, report — the orchestrator reviews diffs, constructs the commit message, and commits. Force-pushes are the orchestrator's responsibility.

## Failure modes I've hit

- **ECONNRESET mid-commit:** API connection can drop during a commit shell command. The edits are on disk but the commit doesn't land. Recovery: verify with `git log` / `git show`, then commit on the next round.
- **Queued-message confusion:** the orchestrator's follow-up prompt arrives before seeing an earlier reply, causing duplicate instructions. Stay on the branch's current HEAD and fold new work into existing state — don't branch or duplicate.
- **Omitting tests unless forced:** the default instinct is to fix the code and skip the test. The brief will always demand a discriminating test; treat test-writing as part of the fix, not optional. If the test feels hard to write, that's often a signal the fix itself needs tightening.
- **Vacuous tests:** a test that passes on both old and new code is worse than no test — it gives false confidence. Always verify the test fails on the old code (or reason through why it would).
