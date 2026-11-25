# ADR-0053: Every component stays current, sorted into three lanes

**Status:** Proposed
**Date:** 2026-11-25
**Deciders:** operator
**Rule:** Keep every pin at its current version, or give it a one-line hard reason for staying behind. Sort each update into a lane by what it takes to prove it. Never treat version coupling or "not yet tested" as a reason to wait.
**Cross-references / touches:** ADR-0005, ADR-0034, ADR-0036, [architectural-commitments-v1](architectural-commitments-v1.md). **Tracking issue:** [#1010](https://github.com/dmfdeploy/dmfdeploy/issues/1010). **RFC:** [RFC: version policy](https://github.com/orgs/dmfdeploy/discussions/1015)

## Context

A survey of nine repositories and about 220 pins showed one pattern. A pin that something proposes updates for is current. A pin that nothing proposes is mostly behind, some by years. Dependabot reads GitHub Actions, CI Python tools, and npm packages. Nothing reads the chart and image pins in Ansible variables and templates, checksum-pinned CI binaries, Terraform providers in ecosystems Dependabot isn't set up for, or host images. Blanket ignore rules also block every major version, so none is ever proposed. No ADR sets a version policy.

## Decision

**Default rule.** Every component stays current. A pin holds the current version, or it carries a one-line hard reason that names why it can't.

**Three lanes.** The lane depends on what it takes to prove the update.

- **Automatic.** CI can prove the update, so it merges on green checks.
- **Batched.** Only a cluster can prove it. Each update merges on green checks, and one fresh install proves the whole batch.
- **Decision.** The update raises a question about the component itself. A maintainer decides before anything merges.

**Decision-lane triggers.**

- A license change.
- A breaking change in something the platform uses, found by searching the changelog. A major version number alone doesn't count.
- The project reaches end of life, forks, or changes owner.
- An upgrade that can't be rolled back, such as a data migration. This trigger applies from v1.0.

**Two non-reasons.** Neither justifies staying behind.

- Version coupling. Components that depend on each other move together in one change.
- "Not yet tested." The batched lane exists for this.

**Two refinements.** Flag a license change on the update pull request, so a reviewer sees it without reading the changelog. Wait a few days before taking a brand-new release, except for a security fix.

**Release model.**

- Until v1.0, `main` is the working line and may break. Environments are rebuilt. There are no release branches and no upgrade path, and tags are checkpoints. Commitment 6 (rebuild-only) holds until v1.0.
- v1.0 is the first release that is functional, feature complete and safe for a real production, even a small one. This text defines it. No milestone tracks it yet.
- Until v1.0, the installer's default repository refs stay on `main`.
- From v1.0, release branches start, with their own pipeline for stability and upgrades. In-place upgrade becomes a commitment, and a "latest stable" pointer names the newest proven release. The branch layout and the pointer come with v1.0.

**Cadence.** The automatic lane runs weekly. The batched lane runs as one batch every two weeks, with one fresh install to prove it.

**Mechanism.** Dependabot stays. The blanket major-version ignore rules go, so a major version is proposed like any other update and sorted into a lane by these rules. A report-only Renovate trial on one repository didn't cover pins that pair a version with a SHA-256, the control image pinned only by digest, or our own images. So one scheduled check, built with GitHub's own tools, opens or updates one issue that lists the pins nothing proposes, including those. Whether Renovate opens pull requests, or replaces Dependabot, is a separate decision.

## Consequences

- **Positive:** every pin is listed, has a proposer or has a written reason, and a major version gets a decision.
- **Negative:** more update pull requests, and a fresh install every two weeks.
- **Neutral:** this ADR sets no version for any component. A separate decision list covers each major move.

### Relation to other ADRs

This ADR supersedes nothing.

- ADR-0005 makes the dmf-cms `VERSION` file the source of that component's own version. This ADR covers how pins move, so the two don't overlap.
- ADR-0034 pins Ansible collections to a full commit SHA. ADR-0034 bumps the mirror list monthly, and at once for a security fix. Both rules stay in force. The two-week batch gives a regular chance to make the monthly bump, but it doesn't replace it.
- ADR-0036 has the installer clone playbooks at an operator-selected ref. Defaulting to `main` until v1.0 is consistent with it.
- The in-place upgrade trigger in `docs/OPEN-QUESTIONS.md` and in the v0.1 commitment plan changes from "a real upgrade-without-rebuild requirement" to v1.0.

### Enforcement

- `.github/dependabot.yml` proposes the pins Dependabot reads. Removing its blanket major-version ignore rule belongs to the mechanism work in #1010.
- The scheduled check does not exist yet. Until it does, nothing lists the pins that nothing proposes. It lists them and doesn't promise that every pin gets a proposer.
- Discipline only: a maintainer sorts each update into a lane, applies the decision-lane triggers and writes the one-line reason for a pin that stays behind.

## Status

Proposed. It becomes Accepted when the RFC thread converges.

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0053-version-policy-stay-current-in-three-lanes.md).
