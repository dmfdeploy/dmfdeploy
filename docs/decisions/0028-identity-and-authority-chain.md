# ADR-0028: Identity and Authority Chain

**Status:** Accepted
**Date:** 2026-05-24
**Deciders:** @<handle> (operator). Three-reviewer chain:
claude-bottom (drafter + adversarial reviewer), codex (independent
code-grounded reviewer), claude-top (survey owner).
**Supersedes/amends:** [ADR-0024](0024-two-identity-admin-model.md)
§Alternatives entry "Generalise the helper to read OpenBao too"
(deferred → realised). ADR-0024 §3 (sanctioned exceptions) is preserved
and re-confirmed by the per-app feasibility survey 2026-05-24.

## Context

The DMF Platform's identity and authority surface needed a canonical,
binding architecture. Identity material is split across human authority
(Authentik OIDC/SAML), machine authority (per-app native service
accounts), custody (OpenBao + physical recovery kit), and audit
(per-app native logs → streaming WORM). The model existed only as
informal convention and scattered references in ADR-0015 (DMF Console
passkey-only), ADR-0024 (two-identity admin model), and the
security-compliance framework plan. A single binding statement was
needed to: (a) codify the operator's slogan as testable architecture;
(b) close the bootstrap-vs-steady-state ambiguity; (c) settle whether
attribution is dmf-cms-attested or cryptographically bound for the
experiment phase; (d) enumerate sanctioned exceptions to "no
locally-created accounts except break-glass."

## Decision

Adopt the **DMF Identity and Authority Model** documented at
[`docs/architecture/DMF Identity and Authority Model.md`](../architecture/DMF%20Identity%20and%20Authority%20Model.md)
as binding architecture. The model has five contract statements
(C1–C5), eight decisions (D1–D8), three operator-led refinements
(R1–R3), and a bootstrap-convergence audit gate; ADR-0028 binds each.

**The slogan** — the four-line target:

> *Humans log in with passkeys. Emergency admins are sealed in OpenBao.
> Machines use scoped service accounts. Every automated action records
> the human who requested it.*

**The binding contract** (top-of-doc canonical assertions):

- **C1.** Authentik is the sole human identity authority in steady state.
- **C2.** OpenBao is the custody layer for steady-state secrets;
  physical recovery kits are disaster custody.
- **C3.** Native service accounts are allowed only for machine-to-machine
  work and must be scoped, named, documented, and stored in OpenBao.
  - **C3.1 (amend 2026-05-29).** A machine token must be minted while
    authenticated *as* the scoped service identity. Token/credential
    ownership binds to the **authenticating principal**, not to a
    `description` field or a user-scoped URL path — creating a token as
    an admin/break-glass account with a service-account description
    yields an **admin-owned** token, and every action taken with it is
    attributed to that admin. Empirically verified on AWX (`imc1-cyh4`,
    2026-05-29): the DMF Console's catalog launches were running as
    `awx-break-glass` because its token, though named `dmf-cms-svc-token`,
    was created by the admin. Correct provisioning: set+persist the
    service account's password, then authenticate as that account to
    mint its self-owned token.
- **C4.** No routine operation may require use of a break-glass account.
- **C5.** Every DMF-initiated automated action must carry actor, role,
  request id, and reason metadata, even when the downstream app
  executes under a service account.

**Sanctioned exceptions to "no local accounts except break-glass"**
(per-app feasibility survey 2026-05-24, confirmed unchanged from
ADR-0024 §3 across seven apps):

1. **Authentik** — `akadmin` (Authentik bootstrap convention).
2. **Zot** — `admin` (htpasswd format constraint).
3. **Grafana** — `admin` (Helm chart default; reaffirmed 2026-05-25
   after the rename sweep because login-form-disable + OIDC auto-login
   already satisfy C4, so the local admin remains dormant break-glass).

No fourth exception emerged. The **AWX shadow superuser**
(`<operator>22daa48fb6594ba3` observed in `g2r6-foa9`) is explicitly
**not** a sanctioned exception. It is the deterministic consequence of
a username collision between the local bootstrap admin and the
SAML-projected operator identity given AWX's default SOCIAL_AUTH
pipeline. Architectural remediation — rename AWX local admin to a
non-colliding break-glass identity + align AWX SOCIAL_AUTH pipeline
with NetBox's `associate_by_email` pattern — landed in
`dmf-infra@c426dc0` as D3 implementation, not an ADR carve-out.
Adding a fourth sanctioned exception requires amendment to this ADR.

**Bootstrap convergence audit gate** (D2): a bootstrap run is not
complete until temporary bootstrap authority has been sealed, rotated,
or explicitly recorded as retained. Enforced by
`k3s-lab-bootstrap/playbooks/verify-bootstrap-convergence.yml`
(`dmf-infra@0f9e7f0`).

**Attribution strength for experiment phase** (D6): **strong dmf-cms
attestation**. The immutable request log inside dmf-cms is the source
of truth; actor / role / request_id / reason propagate to AWX
`extra_vars`, NetBox change-request custom fields, Forgejo commit
footer metadata, OpenBao audit context tags, and Kubernetes audit
annotations. Cryptographic binding (per-action signed tokens) is
deferred. Revisit gate: (a) ADR-0020 Mode B (managed service) promotes
to Accepted, or (b) the first safety-critical automated path lands
where a forged request could affect live production output.

## Consequences

- **Positive** — The slogan is now testable, binding architecture. The
  four security planes (human / machine / custody / audit) and the
  exception list are explicit. Per-app additions to the platform have a
  pre-existing template (D3 survey deliverable schema) for the
  identity-and-authority addition.
- **Positive** — Bootstrap vs steady-state postures are explicit;
  bootstrap shortcuts cannot silently persist into operations once the
  convergence audit gate is enforced.
- **Positive** — D7 (audit-log integrity) is architectural commitment,
  not afterthought. The pre-release compliance Tier A.4 cron acceptance
  is explicitly superseded for identity/authority audit streams;
  streaming export to WORM is the binding pattern.
- **Positive** — ADR-0024's "Generalise the helper to read OpenBao too"
  deferred-alternative is superseded. The unified app-admin helper plan
  v3 at
  [`docs/plans/DMF Unified App-Admin Helper Plan 2026-05-23.md`](../plans/DMF%20Unified%20App-Admin%20Helper%20Plan%202026-05-23.md)
  becomes implementation under D1's OpenBao custody half.
- **Implementation status 2026-05-25** — The immediate follow-ons this
  ADR created have been resolved or deliberately closed:
  1. AWX local-admin rename + SOCIAL_AUTH pipeline alignment landed in
     `dmf-infra@c426dc0`.
  2. NetBox + Forgejo local-admin rename landed in `dmf-infra@3953c62`.
     Grafana was evaluated separately and intentionally retained as the
     sanctioned `admin` exception; no Grafana code change is required.
  3. D2 bootstrap-convergence verifier landed in `dmf-infra@0f9e7f0`
     and passed live on `g2r6-foa9`.
  4. D8 operational defaults (monthly drill doc, ≥2 passkeys per human,
     short OIDC token lifetimes, verifier hook) landed in
     `dmf-infra@2dcafb9`; `dmf-env@4ae3971` aligned the passkey
     enrollment helper with the new count-based gate. Live adoption on
     `g2r6-foa9` remains an operational rollout step.
  5. OIDC client_secret rotation runbook lives at
     [`docs/runbooks/oidc-client-secret-rotation.md`](../runbooks/oidc-client-secret-rotation.md).
- **Neutral** — Multi-user model remains explicitly deferred
  (architecture doc §1). Single-operator assumption binds the current
  phase; ops-admin group is undifferentiated. The future revision
  expands actor cardinality and adds role-differentiation; per-action
  attribution is bound by C5 today and does not depend on multi-user
  promotion.

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

## Enforcement

- **Architecture doc** at
  [`docs/architecture/DMF Identity and Authority Model.md`](../architecture/DMF%20Identity%20and%20Authority%20Model.md)
  is the canonical reference. Schema and contract mutations land there
  as amendments; ADR-0028 binds the model but does not re-derive it.
- **Per-app feasibility survey** at
  [`docs/plans/DMF Per-App Identity Feasibility Survey 2026-05-24.md`](../plans/DMF%20Per-App%20Identity%20Feasibility%20Survey%202026-05-24.md)
  is the authoritative input to the §7 matrix and the exception list
  in this ADR. New apps added to the platform receive a survey entry
  before their roles land.
- **`audit-admin-identities.yml`** (dmf-infra) is the runtime
  drift-detection mechanism for C1 (sole human identity authority).
  `bootstrap-verify.yml` wires it.
- **OIDC client_secret rotation** — runbook at
  [`docs/runbooks/oidc-client-secret-rotation.md`](../runbooks/oidc-client-secret-rotation.md);
  required when a secret value enters any agent transcript, gets
  exfiltrated, or as part of scheduled D8 rotation.
- **D2 bootstrap convergence audit gate** —
  `dmf-infra/k3s-lab-bootstrap/playbooks/verify-bootstrap-convergence.yml`
  is wired into `bootstrap-verify.yml`.
- **Code review** — flag any new app addition that creates local user
  accounts beyond the break-glass identity without amending this
  ADR's exception list (currently 3 entries; 4th requires amendment).
- **Helper plan v3** — the eight-PR sequence at
  [`docs/plans/DMF Unified App-Admin Helper Plan 2026-05-23.md`](../plans/DMF%20Unified%20App-Admin%20Helper%20Plan%202026-05-23.md)
  is implementation under ADR-0028 D1. The plan was previously framed
  against the ADR-0024 deferral; that framing is now superseded.

## Cross-references

- [ADR-0007](0007-secrets-never-in-argv.md) — secrets discipline that
  the helper inherits; clarified by §"ADR-0007 reading" in the
  architecture doc (task-scoped Ansible `environment:` blocks are the
  canonical pattern for stdin-piping).
- [ADR-0008](0008-openbao-secrets-architecture.md) — OpenBao + ESO +
  AppRole shim foundation that D1 / C2 build on.
- [ADR-0009](0009-shamir-dr-model.md) — 5-share Shamir 3-of-5
  distributed; constrains D1 (no single physical kit holds a full
  quorum).
- [ADR-0011](0011-auto-unseal-tradeoff.md) — experiment-phase
  auto-unseal acceptance; D2 bootstrap convergence gate makes the
  trade explicit per-run.
- [ADR-0015](0015-dmf-console-passkey-only.md) — passkey precedent
  that D4 generalises; not amended.
- [ADR-0020](0020-deployment-scope-and-regulatory-posture.md) — Mode B
  promotion is D6's revisit gate.
- [ADR-0024](0024-two-identity-admin-model.md) — the predecessor;
  §Alternatives "Generalise the helper" entry superseded by this ADR.
- [DMF Identity and Authority Model](../architecture/DMF%20Identity%20and%20Authority%20Model.md)
  — the canonical architecture doc.
- [Per-App Identity Feasibility Survey 2026-05-24](../plans/DMF%20Per-App%20Identity%20Feasibility%20Survey%202026-05-24.md)
  — exception-list data source.
- [Unified App-Admin Helper Plan v3](../plans/DMF%20Unified%20App-Admin%20Helper%20Plan%202026-05-23.md)
  — implementation under D1.
