---
status: active
date: 2026-10-27
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/758
---

# Trusted issue-link check rerun plan

## Goal

Complete #758 by allowing a repaired PR body or label change to turn the
existing required `issue-link` check green without a push, while keeping the
check trusted and preventing the rerun token from affecting unrelated runs.

## Boundaries

- Run the check only from the base branch's trusted
  `pull_request_target` workflow. Never check out or execute PR-controlled
  files. Read the current body and labels through GitHub's pull-request API on
  every attempt; treat the body only as data passed to the matcher by file.
- Keep top-level workflow permissions empty. Grant `actions: write` only to
  the narrowly scoped rerun job; grant it only the read permissions needed to
  identify the current PR and candidate runs.
- A body or label edit may re-run an existing completed `issue-link` check
  suite for the same live PR head and event lineage. It must not dispatch a
  new workflow run, rerun a different workflow, or select a run for another PR
  or commit. New commits and normal open/reopen/synchronize events use the
  regular check path.
- Never cancel, delete, or mutate unrelated check runs. The existing
  `issue-link` concurrency group remains scoped to the same PR.

## Rerun contract

The trusted workflow validates its trigger and obtains the live PR body,
labels, head SHA, author, and number. Only the first attempt of a body/label
event may dispatch reruns. The dispatcher accepts the PR author or a current
repository actor with permission to edit the PR; it fails closed when the live
PR author, event actor, or permission result is missing or ambiguous. It
considers only completed runs owned by the exact `issue-link` workflow on
`pull_request_target`, for that PR number and current PR head SHA. It excludes
the current run and active candidates, but may retry an older run that failed
again on a later legitimate edit even if that run already has a prior rerun
attempt. It rechecks the PR head and each candidate immediately before
rerunning. Any missing, ambiguous, stale, or untrusted data fails closed
without making a rerun request.

Each rerun operates on an existing failed run ID, preserving that run's check
suite, and re-evaluates the live body and labels. Thus a body that changes
back before a rerun remains failing, and the next legitimate edit can retry
the same suite. If the PR head changes while selection is in progress, no
old-head run is rerun; the synchronize event evaluates the new head. If
multiple matching stale failed suites exist, rerun every eligible suite for
that PR and commit, without touching successful, active, or unrelated runs.
Rerun attempts themselves never dispatch another rerun, preventing loops.
The rerun API call uses the `actions: write` permission only in this trusted
job.

## Verification

- Mocked API tests cover a body fix without a push and a body changed back
  before rerun. They cover fork PRs and base or live-head changes during
  selection.
- Tests cover multiple stale failed suites, current or active runs, and a
  failed prior rerun later retried by a new edit. They cover runs with a wrong
  workflow ID/path, event, PR number, head SHA, or actor, plus missing or
  ambiguous API fields.
- Prove rejected cases make no rerun request. Prove accepted calls target only
  exact existing eligible failed runs.
- Workflow tests verify the event and permissions boundaries, trusted base
  workflow behavior, live body fetch, and no PR checkout/execution.
- Run the issue-link matcher tests, the rerun helper's hermetic tests,
  `actionlint`, `shellcheck` for changed scripts, documentation checks, and
  voice checks.
- After the trusted workflow change is reviewed and merged, a disposable PR
  body-only edit may verify failure-to-pass without a push. Until then, do not
  claim live behavior or mutate any PR body to test the unmerged workflow.

## Security and failure behavior

The rerun job uses only GitHub's API and base-branch code. It does not execute
PR files or consume PR secrets. API errors, malformed responses, unauthorized
actors, stale heads, and ambiguous run matches stop without issuing a rerun.
The plan does not add repository-wide write permission, and does not cancel or
delete checks to force a green result.
