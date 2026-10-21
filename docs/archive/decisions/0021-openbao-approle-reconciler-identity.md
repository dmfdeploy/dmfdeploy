# ADR-0021 archive: OpenBao AppRole reconciliation uses a dedicated bootstrap identity

This file holds material moved out of [ADR-0021](../../decisions/0021-openbao-approle-reconciler-identity.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Broaden `policy-reconciler` into a general bootstrap reconciler.** Simpler
  operationally, but one identity would then rewrite ACLs, create AppRoles, and
  write ESO binding records. Rejected because it blurs the security boundary
  that `policy-reconciler` was created to preserve.
- **Extend `ops-admin`.** Fastest, but operator credentials would gain platform
  identity powers. Rejected because an operator-credential compromise could mint
  AppRoles and escalate into broad app-data access.
- **Reintroduce root for post-seed.** Rejected because ADR-0009 and the OpenBao
  bootstrap model deliberately treat root as first-bootstrap-only material.
