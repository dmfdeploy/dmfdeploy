# ADR-0028: Identity and Authority Chain

**Status:** Accepted
**Date:** 2026-05-24
**Deciders:** @<handle> (operator). Three-reviewer chain:
claude-bottom (drafter + adversarial reviewer), codex (independent
code-grounded reviewer), claude-top (survey owner).
**Supersedes/amends:** [ADR-0024](0024-two-identity-admin-model.md)
[Alternatives entry](https://github.com/dmfdeploy/dmfdeploy/blob/dbf852b0fb91ae6d7747cd88bdb356056c8dcaad/docs/archive/decisions/0024-two-identity-admin-model.md#alternatives-considered) "Generalise the helper to read OpenBao too"
(deferred → realised). ADR-0024 §3 (sanctioned exceptions) is preserved
and re-confirmed by the per-app feasibility survey 2026-05-24.
**Rule:** Humans log in with passkeys (Authentik); emergency admins are sealed in OpenBao; machines use scoped, named service accounts; every automated action records the human who requested it.

## Context

The dmfdeploy platform's identity and authority surface needed a canonical,
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
[`docs/architecture/dmf-identity-and-authority-model.md`](../architecture/dmf-identity-and-authority-model.md)
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
    attributed to that admin. Correct provisioning: set+persist the
    service account's password, then authenticate as that account to
    mint its self-owned token.
- **C4.** No routine operation may require use of a break-glass account.
- **C5.** Every DMF-initiated automated action must carry actor, role,
  request id, and reason metadata, even when the downstream app
  executes under a service account.

**Direction (amendment 2026-10-21).** This block records where identity
goes next. It adds direction and changes none of C1–C5.

- The multi-user model is in scope for v0.2, whose outcome is "a team
  shares one console".
- Authentik stays the human identity authority (C1). Compatibility with
  external identity providers is a requirement of the multi-user model.
- A **tenant** is an intra-organisation scope that isolates a special
  case. For example, a vendor in a live production gets access to one
  device, network or service and nothing else. Every operation records
  its scope at dispatch. That scope is derived from the tenant of the
  operation's target and does not change after dispatch. The caller's
  own permitted scope never sets it.
- The single-operator assumption in Consequences expires with v0.2. The
  multi-user design lands as its own ADR.

**Sanctioned exceptions to "no local accounts except break-glass"**
(per-app feasibility survey 2026-05-24, confirmed unchanged from
ADR-0024 §3 across seven apps):

1. **Authentik** — `akadmin` (Authentik bootstrap convention).
2. **Zot** — `admin` (htpasswd format constraint).
3. **Grafana** — `admin` (Helm chart default; reaffirmed 2026-05-25
   after the rename sweep because login-form-disable + OIDC auto-login
   already satisfy C4, so the local admin remains dormant break-glass).

No fourth exception emerged. The **AWX shadow superuser**
(`<operator>22daa48fb6594ba3` observed in `<env>`) is explicitly
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
  [`docs/plans/dmf-unified-app-admin-helper-plan.md`](../plans/dmf-unified-app-admin-helper-plan.md)
  becomes implementation under D1's OpenBao custody half.
- **Implementation status 2026-05-25**: see the [archive record](../archive/decisions/0028-identity-and-authority-chain.md).
- **Neutral** — Multi-user model remains explicitly deferred
  (architecture doc §1). Single-operator assumption binds the current
  phase; ops-admin group is undifferentiated. The future revision
  expands actor cardinality and adds role-differentiation; per-action
  attribution is bound by C5 today and does not depend on multi-user
  promotion.

### Enforcement

- **Architecture doc** at
  [`docs/architecture/dmf-identity-and-authority-model.md`](../architecture/dmf-identity-and-authority-model.md)
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
  [`docs/plans/dmf-unified-app-admin-helper-plan.md`](../plans/dmf-unified-app-admin-helper-plan.md)
  is implementation under ADR-0028 D1. The plan was previously framed
  against the ADR-0024 deferral; that framing is now superseded.

## Status

Accepted

Amended 2026-10-21: forward direction recorded; the multi-user design lands as its own ADR.

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0028-identity-and-authority-chain.md).
