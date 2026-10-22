# ADR-0028 archive: Identity and Authority Chain

This file holds material moved out of [ADR-0028](../../decisions/0028-identity-and-authority-chain.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **N ADRs (one per decision).** Splitting D1–D8 into separate ADRs
  would fragment the model and make piecemeal implementation easier.
  Rejected; one architecture doc + one binding ADR (this one) is the
  chosen format per the codex distillation.
- **Defer ADR until follow-on implementation work lands.** Would leave
  the model as a draft document with no binding force; risks scope
  drift during implementation. Rejected; the architecture doc + survey
  provide enough concrete data to bind now.
- **Single helper covering both K8s-Secret and OpenBao backends.**
  Plausible long-term, but ADR-0024's split on backend
  (`admin-identity-resolve` for K8s Secret; `app-admin-facts` for
  OpenBao) is operationally clean. Rejected as scope creep for
  ADR-0028; revisit if a third backend appears.
- **Cryptographic binding for attribution now.** Materially more
  complex, slows live-production operational tempo, no current driver
  in experiment phase. Rejected; D6 revisit gate covers the future case.

## Cross-references

- [ADR-0007](../../decisions/0007-secrets-never-in-argv.md) — secrets discipline that
  the helper inherits; clarified by §"ADR-0007 reading" in the
  architecture doc (task-scoped Ansible `environment:` blocks are the
  canonical pattern for stdin-piping).
- [ADR-0008](../../decisions/0008-openbao-secrets-architecture.md) — OpenBao + ESO +
  AppRole shim foundation that D1 / C2 build on.
- [ADR-0009](../../decisions/0009-shamir-dr-model.md) — 5-share Shamir 3-of-5
  distributed; constrains D1 (no single physical kit holds a full
  quorum).
- [ADR-0011](../../decisions/0011-auto-unseal-tradeoff.md) — experiment-phase
  auto-unseal acceptance; D2 bootstrap convergence gate makes the
  trade explicit per-run.
- [ADR-0015](../../decisions/0015-dmf-console-passkey-only.md) — passkey precedent
  that D4 generalises; not amended.
- [ADR-0020](../../decisions/0020-deployment-scope-and-regulatory-posture.md) — Mode B
  promotion is D6's revisit gate.
- [ADR-0024](../../decisions/0024-two-identity-admin-model.md) — the predecessor;
  §Alternatives "Generalise the helper" entry superseded by this ADR.
- [DMF Identity and Authority Model](../../architecture/dmf-identity-and-authority-model.md)
  — the canonical architecture doc.
- [Per-App Identity Feasibility Survey 2026-05-24](../../plans/DMF%20Per-App%20Identity%20Feasibility%20Survey%202026-05-24.md)
  — exception-list data source.
- [Unified App-Admin Helper Plan v3](../../plans/dmf-unified-app-admin-helper-plan.md)
  — implementation under D1.

## Consequences — implementation status 2026-05-25 (moved from the ADR)

- **Implementation status 2026-05-25** — The immediate follow-ons this
  ADR created have been resolved or deliberately closed:
  1. AWX local-admin rename + SOCIAL_AUTH pipeline alignment landed in
     `dmf-infra@c426dc0`.
  2. NetBox + Forgejo local-admin rename landed in `dmf-infra@3953c62`.
     Grafana was evaluated separately and intentionally retained as the
     sanctioned `admin` exception; no Grafana code change is required.
  3. D2 bootstrap-convergence verifier landed in `dmf-infra@0f9e7f0`
     and passed live on `<env>`.
  4. D8 operational defaults (monthly drill doc, ≥2 passkeys per human,
     short OIDC token lifetimes, verifier hook) landed in
     `dmf-infra@2dcafb9`; `dmf-env@4ae3971` aligned the passkey
     enrollment helper with the new count-based gate. Live adoption on
     `<env>` remains an operational rollout step.
  5. OIDC client_secret rotation runbook lives at
     [`docs/runbooks/oidc-client-secret-rotation.md`](../../runbooks/oidc-client-secret-rotation.md).

## C3.1 — empirical evidence (moved from the ADR)

Empirically verified on AWX (`<env>`,
    2026-05-29): the DMF Console's catalog launches were running as
    `awx-break-glass` because its token, though named `dmf-cms-svc-token`,
    was created by the admin.
