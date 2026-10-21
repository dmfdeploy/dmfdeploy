# ADR-0001 archive: Umbrella as docs home; component repos remain independent gits

This file holds material moved out of [ADR-0001](../../decisions/0001-umbrella-as-docs-home.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Submodules.** Add ceremony for marginal benefit in experiment phase; pinning
  versions across 5 sibling repos is more friction than it's worth right now.
  Reconsider when releasing publicly.
- **Monorepo.** Would force one branching/release model on everything. Component
  repos already have established release workflows; collapsing them is a
  high-cost reorg without a clear forcing function.
