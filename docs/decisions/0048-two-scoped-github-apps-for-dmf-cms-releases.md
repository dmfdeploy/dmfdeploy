<!-- ADR doc convention: every ADR carries a top-of-doc **Rule:** dmf-cms release automation uses two organization-owned GitHub Apps, one for merges and one as the only bypass actor for `v*` tags, each with its key held only in an environment limited to `main`. Use no personal access token and no `GITHUB_TOKEN` bypass.
constraint in one imperative sentence) directly under the metadata block. See
docs/decisions/README.md, "ADR conventions". -->
# ADR-0048: Two scoped GitHub Apps for unattended dmf-cms releases

**Status:** Accepted
**Date:** 2026-10-30.
**Deciders:** @znerol2 and a second maintainer (Discussion [#805](https://github.com/orgs/dmfdeploy/discussions/805)).
**Rule:** dmf-cms release automation uses two organization-owned GitHub Apps, one that arms or performs merges and one that is the only bypass actor for `v*` tag creation, each with its private key held only in a GitHub environment limited to `main`; no personal access token and no `GITHUB_TOKEN` bypass.
**Cross-references / touches:** ADR-0007 (secrets never in argv), ADR-0041 (release model). **Plan:** [`docs/plans/dmf-cms-exact-sha-release-gate-plan.md`](../plans/dmf-cms-exact-sha-release-gate-plan.md) (tracked by [#568](https://github.com/dmfdeploy/dmfdeploy/issues/568))

## Context

Issue #568 found that the dmf-cms release commit `v0.38.0` reached `main` with no check
runs. dmf-cms allows only rebase merges, so the commit on `main` is not the commit the pull
request tested. Auto-merge ran as `GITHUB_TOKEN`, and GitHub starts no workflows from events
that token causes, so the rebased commit never got its checks.

An earlier choice, recorded only in an issue comment, was to add no App and no personal
credential. This ADR replaces that choice for dmf-cms. A `GITHUB_TOKEN` tag bypass would apply
to every workflow in the repository.

## Decision

dmf-cms uses two GitHub Apps owned by the `dmfdeploy` organization, installed only on it.
- **`dmf-cms-automerge`** arms auto-merge, or merges directly when checks have already
  passed. Its events start workflows, so the commit on `main` gets its checks. It has
  pull-requests and contents write only.
- **`dmf-cms-release`** creates `v*` tags with contents write only. It is the only bypass
  actor on the `tags-release-create` ruleset.
- Each key lives in its own environment (`automerge`, `release`) limited to `main`. It reaches
  the token action as an input, never argv (ADR-0007).
- The pattern is proven in dmf-cms first. Other repositories need their own decision.

## Options considered

1. **Stay attended.** No new credential, but a person starts every release.
2. **One App.** Any job that can arm a merge could also create a release tag.
3. **Two Apps (chosen).** The key that can create tags exists in one environment only.
4. **Personal access token.** It ties releases to one person and has broader scope.
5. **Merge queue.** Tests the exact commit, but tag creation still needs a scoped identity,
   and its behavior with rebase merges here is unverified.

## Consequences

- **Positive:** the commit on `main` gets checks, and releases run unattended.
- **Negative:** two long-lived keys exist. An organization owner creates the Apps and
  environments, rotates both keys every 90 days and after any owner change, and records it in
  the pinned operator-notes issue [#618](https://github.com/dmfdeploy/dmfdeploy/issues/618).
- **Residual risk:** anyone who can change environment settings, or merge to `main` without
  review, is inside the trust boundary. Review rules limit this and do not remove it.

Observed in throwaway probes on 2026-10-30:

- An App-armed merge started the push workflow. A `GITHUB_TOKEN`-armed merge did not.
- A Free-plan organization accepted its own App as the only tag bypass actor. An organization
  admin could not create a matching tag, and neither could a stray-branch `GITHUB_TOKEN` workflow.
- The built-in GitHub Actions integration cannot be a bypass actor.
- An environment limited to `main` withholds its secret from other branches.
- Attestations work on a Free-plan public repository.
Unconfirmed, and checked before the release trigger is enabled: a direct App merge,
skipped-job concurrency behavior, `workflow_run` under the new `pull_request_target` policy,
and attestation of a container digest.

### Enforcement

- The plan's required tests run in dmf-cms CI. A workflow lint test fails unless only the
  `release` job holds the concurrency group, the `release` environment and write permissions.
  It also fails if another workflow references the release secrets. Trigger tests cover
  `automerge` and `release`, and a ruleset fixture requires one tag bypass actor.
- The rollout probes and the live `tags-release-create` setup are pre-enable gates.
- Nothing checks the live tag ruleset after rollout (`bin/check-ruleset-drift.sh` reads only
  the branch ruleset), and nothing checks the 90-day key rotation: discipline only.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the
[archive record](../archive/decisions/0048-two-scoped-github-apps-for-dmf-cms-releases.md).
