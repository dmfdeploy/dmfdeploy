# ADR-0053 archive: every component stays current, sorted into three lanes

This file holds the alternatives and the pointers for [ADR-0053](../../decisions/0053-version-policy-stay-current-in-three-lanes.md). The ADR is the binding record. This file is history and is not maintained.

## Alternatives considered

- Keep the blanket major-version ignore rules. Major versions then never get proposed, which is the gap the survey found. The ADR removes the rules and sorts a major version into a lane.
- Replace Dependabot with an update bot. A report-only Renovate trial on one repository is over. It didn't cover pins that pair a version with a SHA-256, the control image pinned only by digest, or our own images. Whether Renovate opens pull requests or replaces Dependabot's version updates is a later decision, so the ADR depends on neither outcome.
- Define v1.0 with a milestone now. The ADR text defines it, and a milestone is deferred.
- Change the installer's default refs to release tags now. No release exists yet, so the default stays on `main` until v1.0.
- A weekly batch install. The operator chose two weeks for the batched lane.

## Where the work lives

- Tracking issue: [#1010](https://github.com/dmfdeploy/dmfdeploy/issues/1010).
- RFC: <RFC link>
