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
- Keep `issue-link.yml` read-only and preserve its required check name. A
  separate trusted workflow handles reruns through `workflow_run` after the
  issue-link check completes. That coordinator uses default-branch code and
  never checks out PR code.
- Keep both workflows' top-level permissions empty. Grant `actions: write`
  only to the coordinator's rerun job; grant it only the read permissions
  needed to identify the current PR and candidate runs.
- A body or label edit may re-run an existing completed `issue-link` check
  suite for the same live PR head and event lineage. It must not dispatch a
  new workflow run, rerun a different workflow, or select a run for another PR
  or commit. New commits and normal open/reopen/synchronize events use the
  regular check path.
- Never cancel, delete, or mutate unrelated check runs. The required
  `issue-link` job name remains unchanged. Its concurrency key is unique to a
  workflow run and attempt so independent original suites do not cancel one
  another while a coordinator reruns their existing run IDs.

## Rerun contract

The coordinator accepts only successful, first-attempt `issue-link` workflow
runs from `pull_request_target`. It verifies the source workflow ID and path,
then obtains the live PR body, labels, head SHA, base ref, author, and number.
The event actor must be the PR author or a current repository actor with
permission to edit the PR. Missing or ambiguous identity and permission data
fails closed. The coordinator reruns only completed runs from the exact
`issue-link` workflow and `pull_request_target` event, tied to that PR number
and current head SHA. It excludes the source run and active candidates, but
may retry a previously rerun candidate that failed again after a later
legitimate edit. It rechecks the live PR head and each candidate immediately
before rerunning. Any missing, ambiguous, stale, or untrusted data fails
closed without making a rerun request.

Actions workflow-run associations are compact identity projections: their
base and head repository objects carry positive numeric IDs but may omit
`full_name`. Compare those IDs, refs, SHAs, and PR number with the canonical
full pull-request response fetched from the fixed umbrella endpoint. Require
the run's top-level repository name and ID to match that canonical base; a
fork head may have a different positive repository ID. Optional association
names must agree when present. If a failed candidate records an earlier base
commit than the live PR, rerun it only after the compare API proves that the
candidate base is an ancestor of the pinned live base. Validate all such
comparisons before the first rerun request, and pin the base identity again
before each request. This permits a trusted old suite to re-evaluate today's
body after main advances without treating a divergent or retargeted PR as the
same check.

Each rerun operates on an existing run ID, preserving that run's check suite,
and re-evaluates the live body and labels. The coordinator confirms the live
body still passes the same matcher before it issues a rerun. Thus a body that
changes back before a rerun remains failing, and a later successful check may
retry the same suite. If the PR head changes while selection is in progress,
no old-head run is rerun; the synchronize event evaluates the new head. If
multiple matching stale failed suites exist, rerun each eligible failure
sequentially and wait for completion before starting the next. Do not touch
successful or unrelated runs. The coordinator serializes by PR with
`cancel-in-progress: false`; GitHub retains only one pending run in a
concurrency group, so each coordinator freshly scans every eligible stale
failure, regardless of which event queued that coordinator.
`workflow_run` events produced by reruns are ignored after attempt one,
preventing loops while allowing later first-attempt events to retry failures.
The rerun API call uses the `actions: write` permission only in the trusted
coordinator job.

## Verification

- Mocked API tests cover a body fix without a push and a body changed back
  before rerun. They cover fork PRs and base or live-head changes during
  selection.
- Tests cover multiple stale failed suites (up to the fixed four-suite
  coordinator cap), current or active runs, and a failed prior rerun later
  retried by a new edit. They cover runs with a wrong workflow ID/path, event,
  PR number, head SHA, or actor, plus missing or ambiguous API fields.
- Prove rejected cases make no rerun request. Prove accepted calls target only
  exact existing eligible failed runs.
- The review-only current-API exercise at
  `tests/manual/issue_link_rerun_readonly_api.py` uses `gh api` for GET
  requests only and blocks every rerun request. Its event wrapper is synthetic
  because the runner-local webhook was unavailable; the run and PR identities
  come from current REST responses. Committed fixtures preserve the observed
  identity fields but use a neutral PR-author login; the live harness checks
  the current API actor and author directly.
- The coordinator waits at most five minutes for each of at most four stale
  suites and has a 30-minute job timeout. If more than four eligible failures
  match, or workflow history reaches the API's 1,000-result cap, it refuses
  before any rerun request and reports a sanitized bounded-work error. The
  operator must then handle that exceptional backlog explicitly; a later
  event does not silently process an unbounded queue.
- Tests prove candidate overflow and capped workflow history make no rerun
  request. Tests also cover polling timeout and an unexpected attempt jump.
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
