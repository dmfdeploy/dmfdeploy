# ADR-0008 archive: OpenBao + ESO + AppRole shim as secrets architecture

This file holds material moved out of [ADR-0008](../../decisions/0008-openbao-secrets-architecture.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **HashiCorp Vault directly.** OpenBao is the OSS fork; functionally
  equivalent for our needs and not gated on enterprise-edition features.
- **k8s Secrets only (no external store).** Loses the audit trail, the
  human-and-pod unified policy model, and break-glass-vs-runtime
  separation.
- **`community.hashi_vault` lookup at task time.** Runtime API dependency,
  more complex error paths during playbooks, and harder to test offline.
  Wrapper-shim approach is simpler.
