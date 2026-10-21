# ADR-0036 archive: dmf-init is a thin control-plane container — runtime-pull playbooks at a selected ref; nothing baked

This file holds material moved out of [ADR-0036](../../decisions/0036-dmf-init-thin-control-container.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **A — Bake the repo layer at a release tag (image tag == release).** Max
  reproducibility + offline control-plane, but binds the image to private
  `dmf-env` today (operator-internal), needs per-release image builds, and is
  blocked by the absence of tags + a clean public `dmf-env`. Rejected for Phase 1
  in favor of the thinner, public-safe, more flexible runtime-pull (B).
- **C — "Huge" container baking all app images.** Only pays off for a true
  air-gap; GB-scale, version-locked, duplicates GHCR+Zot. Rejected; air-gap is a
  separate future profile (portable bundle).
