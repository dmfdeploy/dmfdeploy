# ADR-0014 archive: AWX project layout — hybrid (launchers + mirrored source repos)

This file holds material moved out of [ADR-0014](../../decisions/0014-awx-project-layout.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Option A — single `dmf-runbooks` repo with role copies.** Rejected
  — role drift across copies becomes unmanageable as the catalog grows
  beyond the first few entries.
- **Option B — one project per source repo, no `dmf-runbooks` layer.**
  Rejected — operator-facing audit needs a thin launcher layer; raw
  role-invocation from an AWX job template makes the operator-facing
  diff harder to review and conflates "what's published for operator
  use" with "what's available in the source tree".
