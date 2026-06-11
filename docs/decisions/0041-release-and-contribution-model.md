# ADR-0041: DMF Release and Contribution Model

**Status:** Accepted
**Date:** 2026-06-09
**Deciders:** <handle>, umbrella session (claude)

## Context

The DMF Platform needs a canonical contribution and release model that all repos follow. The prior model described a Forgejo-canonical, GitHub-push-mirror, sync-to-github.sh-only workflow with a Constitution and five sibling repos — all of which are stale. Four locked decisions (2026-06-09) resolved the outstanding TBDs: GitHub-canonical-forward, DCO (not CLA), retire-to-archive for Forgejo, and Free-tier locked-window flip.

## Decision

Adopt the **GitHub-canonical-forward** model codified in `docs/architecture/DMF Release and Contribution Model.md` as amended by the First Public Release Plan. The full detail document is that architecture doc; this ADR records its acceptance and the key rule changes:

- **GitHub `main` is the single source of truth.** All forward work is GitHub Pull Requests. Direct push to `main` is blocked; force-push is banned.
- **Forgejo is archive-only.** LAN Forgejo repos (`<repo>-archive`) are read-only history snapshots, never an upstream or contribution path.
- **`bin/sync-to-github.sh` is retired** post-import — it was a one-time import tool, not the publish path.
- **DCO, not CLA.** Every commit must carry `Signed-off-by:` (`git commit -s`); a DCO check enforces it on PRs.
- **Conventional Commits required** on `main`; SemVer; `VERSION` file is the single source of truth (ADR-0005); no VERSION bump → no release.
- **Topic branches** `<handle>/<short-slug>`; linear history; rebase-merge onto `main` so DCO trailers survive.

**External contributor flow — RESOLVED.** GitHub-first PRs with DCO; no Forgejo round-trip path needed. The stale §5 TBD in the source doc is closed.

## Consequences

- **Positive** — clear contribution path for external contributors; CI-enforced DCO + Conventional Commits; no more stale Forgejo-canonical confusion.
- **Negative** — DCO merge-method gap: squash-merge can drop Signed-off-by trailers; mitigated by Workstream A setting rebase-merge-only (or requiring signed-off squash messages).
- **Neutral** — governance files (CONTRIBUTING.md, SECURITY.md, PR/issue templates, CODEOWNERS, DCO workflow) added to every repo; existing ADRs unchanged.

## Alternatives considered

1. **Keep Forgejo-canonical + GitHub mirror** — rejected: the GitHub org is now the public collaboration surface; maintaining Forgejo as canonical adds operational complexity without benefit.
2. **CLA instead of DCO** — rejected: DCO is lighter-weight, requires no legal overhead, and is standard for infrastructure projects of this scale.

## Enforcement

- **Governance files:** CONTRIBUTING.md, SECURITY.md, `.github/` templates, CODEOWNERS, DCO workflow in every repo (this workstream).
- **CI gates:** DCO workflow checks every PR; gitleaks/scrub/commitlint/trivy (Workstream E1).
- **Branch protection:** GitHub rulesets enforce linear history, required reviews (CODEOWNERS), and required status checks (Workstream A).
