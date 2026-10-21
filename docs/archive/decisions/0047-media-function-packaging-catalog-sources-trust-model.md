# ADR-0047 archive: Media Function packaging, catalog sources and trust model

This file holds material moved out of [ADR-0047](../../decisions/0047-media-function-packaging-catalog-sources-trust-model.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Single trust_tier axis** (RFC rev 1) — rejected: conflates who controls a
  source, how mature a release is, and what code may execute; "vendor
  bespoke launchers, reviewed" died in cross-check round 1 because review is
  not a boundary.
- **Git-history-only revocation** — rejected: history proves what happened,
  not what is currently denied; consumers need a fail-closed current-state
  artifact.
- **External marketplace portal** (Backstage/Devtron class) — not adopted;
  the console Catalog rail plus classed sources covers the need, and the
  air-gap/self-contained doctrine (ADR-0030/0034) plus the roadmap's
  recommendation park external portals unless a real multi-publisher
  ecosystem materialises.
