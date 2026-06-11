# ADR-0001: Umbrella as docs home; component repos remain independent gits

**Status:** Accepted (amended 2026-06-11 — sibling layout)
**Date:** 2026-05-03
**Deciders:** @<handle>

## Context

DMF Platform is split across 5 component repos (`dmf-cms`, `dmf-infra`,
`dmf-env`, `dmf-central`, `dmf-media`) and a previously-scattered set of
~24 design / planning documents stored on a JuiceFS volume at
`<note-store>/`. Multiple AI agents (Claude, Codex,
Qwen, Haiku) work in these repos in parallel sessions and need a single place to
find cross-cutting context.

## Decision

`<umbrella-path>/` is the **umbrella git repo**. It tracks
docs (`docs/`), architecture decisions (`docs/decisions/`), umbrella-level
plans, and Claude Code skills (`.claude/skills/`). The 5 component repos sit
inside it as `.gitignore`d sibling directories — each retains its own `.git`
and remote, ships independently, and is **not** a git submodule.

## Consequences

- **Positive:** single mental model ("the umbrella has the cross-cutting stuff,
  the component repo has the code"). One place for agents to fetch on session
  start. Component repos still ship independently with their own release cadence.
- **Positive:** docs that previously lived only on JuiceFS are now version-tracked,
  pushable to Forgejo, reviewable in PRs.
- **Negative:** standalone clones of a component repo (without the umbrella) lose
  cross-repo references in CLAUDE.md / READMEs. Mitigated by textual paths
  (`dmfdeploy/docs/...`) that signal where to look rather than relying on
  filesystem resolution.
- **Negative:** two `git push` operations needed when changes span umbrella + a
  component. Acceptable for current scale.

## Alternatives considered

- **Submodules.** Add ceremony for marginal benefit in experiment phase; pinning
  versions across 5 sibling repos is more friction than it's worth right now.
  Reconsider when releasing publicly.
- **Monorepo.** Would force one branching/release model on everything. Component
  repos already have established release workflows; collapsing them is a
  high-cost reorg without a clear forcing function.

## Enforcement

`.gitignore` excludes the 5 component dirs at the umbrella root. Component repo
CLAUDE.md / README files reference `dmfdeploy/docs/<subdir>/...` as textual
pointers; rewrite enforced by past commits (see component repo `docs: rewrite
<note-store> refs to dmfdeploy/docs/` commits). Boot ritual in umbrella
CLAUDE.md tells agents to `git fetch && git pull` the umbrella first.

## Amendment (2026-06-11): components are siblings, not nested

With the first public release (all 9 repos at `github.com/dmfdeploy/<repo>`),
the canonical checkout layout changed: the (now 8) component repos sit
**beside** the umbrella under a common parent directory
(`<parent>/dmfdeploy/` + `<parent>/dmf-*/`), no longer nested inside it.
The decision itself stands — the umbrella remains the docs home and the
component repos remain independent gits (still not submodules).

Consequences of the amendment:

- Component-repo paths from the umbrella root are `../dmf-*`.
- The umbrella `.gitignore` entries for `dmf-*` are retained only as a safety
  net for legacy nested clones; they are inert in the canonical layout.
- Umbrella `bin/` tooling (`generate-status.sh`, `generate-scripts-catalog.sh`,
  scrub/hygiene/export gates, `mxl-sync-check.sh`) resolves component repos in
  either layout: nested if present, otherwise sibling.
