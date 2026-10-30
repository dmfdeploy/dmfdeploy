# ADR-0048 archive: Two scoped GitHub Apps for unattended dmf-cms releases

This file holds the deliberation behind [ADR-0048](../../decisions/0048-two-scoped-github-apps-for-dmf-cms-releases.md). The ADR is the binding record. This file is history and is not maintained.

## How the RFC converged

[Discussion #805](https://github.com/orgs/dmfdeploy/discussions/805) proposed option 3. The operator approved going ahead. The second maintainer supported option 3 and asked for two things: keep the plan's pre-enable probes and checks as rollout gates, and prove the pattern in dmf-cms before extending it to other repositories. The ADR records both.

## Why the first design changed

The first plan for the fix ([PR #796](https://github.com/dmfdeploy/dmfdeploy/pull/796)) kept the earlier no-credential rule. It used `GITHUB_TOKEN` as the tag bypass actor, started the release with a manual `repository_dispatch`, and checked a ruleset timestamp to detect drift. Review found three problems:

- The Actions bypass applies to every workflow in the repository, so no ruleset setting can limit it to the release workflow.
- A manual trigger means the release is not unattended.
- The drift check depends on API behavior that fixtures cannot establish.

## Options considered

1. **Stay attended.** An operator triggers every release and publishes from a workstation. This needs no new credential and no new work, and it is not unattended.
2. **One App for everything.** A single App arms auto-merge and creates tags. The workflow that arms auto-merge must be able to read its key, so any job that can use the key can also create a release tag.
3. **Two Apps, each in its own environment (chosen).** One App arms auto-merge. A second App creates `v*` tags and is the only bypass actor on the tag ruleset. Each key lives in an environment limited to `main`.
4. **A personal access token.** It ties a release to one person and carries broader scope than the task needs. Rejected.
5. **A merge queue.** GitHub tests the exact commit that lands on `main`, which removes the root cause of #568 without an App. It gives tag creation no scoped identity, so a tag bypass actor is still needed. Nobody verified how the queue treats rebase merges on this repository. The Apps can still be added later for tag creation, but the queue alone does not meet the goal.

## Probe record

On 2026-10-30, throwaway repositories (a Free-plan personal account and the Free-plan `dmfdeploy` organization) showed the facts listed in the ADR. The plan's "Observed behavior" section holds the detail. The test Apps were removed and the repositories archived. The rollout repeats each probe on the real Apps and dmf-cms.
