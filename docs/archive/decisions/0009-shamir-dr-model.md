# ADR-0009 archive: 5-share Shamir, 3-of-5 threshold, distributed across 5 locations

This file holds material moved out of [ADR-0009](../../decisions/0009-shamir-dr-model.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **3-share, 2-of-3.** Smaller threshold, less resilience to share loss. Less
  defense-in-depth.
- **Single key (no Shamir).** Simpler ops, single point of compromise. Rejected.
- **Cloud KMS auto-unseal.** Trades local-only security for cloud-vendor trust.
  For an experiment-phase lab where the operator IS the security boundary,
  Shamir is more appropriate.
