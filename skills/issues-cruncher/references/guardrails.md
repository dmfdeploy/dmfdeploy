# Guardrails — the hard-gate checklist

The orchestrator owns these. They are gates, not suggestions. Most were paid for in
real failures this session.

## Before touching anything
- [ ] **Lease.** `git status` + branch on **every** repo you'll modify. Dirty or
      another agent active ⇒ isolate in a `git worktree` off the default branch.
      Never trust the shared checkout's branch.
- [ ] **Claim** the issue (assignee/comment) so two orchestrators don't collide.
- [ ] **Profile confirmed** with evidence; unknowns gated (`repo-profile.md`).

## During implementation
- [ ] **Scope freeze.** Anything discovered that isn't required to fix *this* issue
      becomes a follow-up issue — not silent extra scope.
- [ ] **Verify on disk, never agent reports.** Re-check every DONE claim against the
      actual code/tests. Reports cross, lag, and sometimes never landed.

## The test (the part that actually catches bugs)
- [ ] **Discrimination check.** The regression test must **fail against the OLD
      code** and pass with the fix. Prove it (e.g. `git stash` the fix, run the
      test, watch it fail, restore). A test that only passes is worthless.
- [ ] **Independent regression design.** If the same agent wrote both the fix and
      its discrimination test in one pass, the test can encode the same
      misunderstanding — have the discrimination re-designed independently
      (different agent, or orchestrator-authored test against the implementer's fix).
- [ ] **Clean-tree path** for artifact-fallback repos: verify from a clean export,
      not the dirty tree where built artifacts mask the fallback
      (`.qwen/skills/clean-tree-verification-protocol`).

## Before/at PR
- [ ] **Fresh-checkout verify the *pushed* branch**, not just your local tree.
- [ ] **Evidence bundle on the PR**: the commands run, old-code-failing output,
      new-code-passing output, CI run URL, and any known residual risk.
- [ ] **CI truth** from `gh run view`, not lagging aggregations
      (`github-adapter.md`).

## Reviewer / CI rounds
- [ ] **Re-run the whole verification chain after every fix.** A reviewer or CI
      change voids prior adversary/verify passes. The trio (and you) missed real
      bugs that only the external reviewer caught — expect rounds, re-verify each.
- [ ] **Don't assume green = mergeable.** Respect `REVIEW_REQUIRED`, required
      checks, and admin-bypass rules.

## Cross-cutting safety
- [ ] **Human approval gate** for: migrations, destructive/irreversible ops, costed
      cloud actions, public publish, dependency/license changes.
- [ ] **Redaction.** Scrub secrets/tokens from agent-bridge transcripts and PR
      comments before they leave the machine.
- [ ] **Hung-agent policy** (`harness-ops.md`): liveness ping is not enough — define
      a timeout, then interrupt/kill, capture the transcript, and restate context on
      restart. Don't wait forever on a wedged pane.

## After merge
- [ ] **Honor the profile's close behavior** — close the tracker item manually if
      the merge won't (cross-repo / rebase-severed), with a PR-linked comment.
- [ ] **Clean up** — delete the merged branch; remove the worktree; return agents to
      a clean default branch.
