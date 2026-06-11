# DMF Identity and Authority Model

**Status:** Binding — codified by [ADR-0028](../decisions/0028-identity-and-authority-chain.md) (Accepted 2026-05-24).
**Date:** 2026-05-24
**Revision:** v1.2 (per-app survey 2026-05-24 closed — §7 placeholder
replaced with concrete matrix; ADR-0028 landed; survey path no longer
flagged as "not yet present"). Prior: v1.1 codex corrections; v1.0
initial draft.
**Repos in scope:** `dmf-infra`, `dmf-env`, `dmf-cms`, umbrella.
**Pairs with:** ADR-0028 (Identity and Authority Chain — *deferred until
per-app feasibility survey completes*); supersedes/amends ADR-0024 §Alternatives.
**Cross-refs:** [ADR-0007](../decisions/0007-secrets-never-in-argv.md),
[ADR-0015](../decisions/0015-dmf-console-passkey-only.md),
[ADR-0020](../decisions/0020-deployment-scope-and-regulatory-posture.md),
[ADR-0024](../decisions/0024-two-identity-admin-model.md),
[Unified App-Admin Helper Plan v3](../plans/DMF%20Unified%20App-Admin%20Helper%20Plan%202026-05-23.md),
[Per-App Identity Feasibility Survey 2026-05-24](../plans/DMF%20Per-App%20Identity%20Feasibility%20Survey%202026-05-24.md)
(sibling plan, closed 2026-05-24; survey data folded into §7).

This document is the canonical reference for *who is authorised to do
what* on the DMF Platform. Read this for the **model**; read ADR-0028
(when it lands) for the *binding decisions*; read the per-app
feasibility survey for the *concrete exception list*. Schema and
contract mutations land here as amendments, not in the ADR.

---

## 1. Scope and constraints

**Single-operator assumption is current-phase binding.** The platform is
operated by one human today. Authentik's `ops-admin` group has one
member; `vault_bootstrap_admin_username` resolves to that human's
chosen identity; break-glass material is sealed with custody patterns
appropriate for a solo operator (Shamir 3-of-5 distributed, USB
recovery kit, offsite backup).

**Multi-user model is deferred** to a future revision when operator
departments and roles match media-facility organisational patterns
(per the operator's note, 2026-05-23). When that future revision lands:
ops-admin group becomes role-differentiated (separate groups per
department / function), authorization becomes role-aware (not every
operator can do everything), attribution becomes multi-user-aware
(the audit chain identifies *which* human, not just *a* human),
break-glass custody splits, and this document's §5 (the eight
decisions) is revisited against multi-tenant assumptions.
Per-action attribution itself is *not* deferred — C5 binds it
today; the future revision changes the cardinality of the actor
set, not the attribution requirement.

**Phase posture: experiment** per [ADR-0004](../decisions/0004-experiment-phase-stance.md).
Optimise for *learning whether the architecture survives contact with
reality*, not for hardening. Several operational defaults in §5 D8
(drills, multi-passkey enrolment, short OIDC token lifetimes) are
binding-by-default but acknowledged as not-yet-implemented; the gap
between target and implementation is recorded explicitly per decision.

---

## 2. The slogan

The binding target — a four-line statement a non-expert can hold in
working memory:

> *"Humans log in with passkeys.*
> *Emergency admins are sealed in OpenBao.*
> *Machines use scoped service accounts.*
> *Every automated action records the human who requested it."*

Everything in this document descends from those four lines. If a
proposed change to the platform's identity/authority surface cannot
be expressed against one of those four sentences, it is either out of
scope for this model or the model needs amendment first.

---

## 3. Five contract statements

The canonical assertions. Top of every identity/authority code review,
top of every per-app addition, top of every dispatch to a new operator
joining the project.

**C1.** *Authentik is the sole human identity authority in steady state.*

**C2.** *OpenBao is the custody layer for steady-state secrets;
physical recovery kits are disaster custody.*

**C3.** *Native service accounts are allowed only for machine-to-machine
work and must be scoped, named, documented, and stored in OpenBao.*

**C4.** *No routine operation may require use of a break-glass account.*

**C5.** *Every DMF-initiated automated action must carry actor, role,
request id, and reason metadata, even when the downstream app executes
under a service account.*

The statements are testable. C1 is testable by per-app inventory (the
per-app survey). C2 by `git grep` for credential storage outside
OpenBao + the physical kit's existence. C3 by per-app service-account
inventory. C4 by audit-log analysis of break-glass-account login
events. C5 by spot-checking AWX job extra_vars, NetBox changelog custom
fields, Forgejo commit metadata for the actor/role/request-id/reason
quartet.

---

## 4. Two postures — bootstrap and steady state

The slogan describes *steady-state*. The platform also has a
**bootstrap window** with a materially different trust model. Naming
this explicitly closes a class of failure where bootstrap shortcuts
silently persist into operations.

| Posture | Trust assumption | Authority concentration | Convergence target |
|---|---|---|---|
| **Bootstrap Trust Window** | Operator's workstation is the root of trust; SOPS bundle holds credentials; Ansible runtime materialises `vault_*` vars | High — operator can do anything | Hand off to steady-state authority within one bootstrap-configure run |
| **Steady-State Operations** | Authentik for humans, OpenBao for custody, native service accounts for machines, dmf-cms attests human-initiated actions | Distributed across C1–C5 boundaries | n/a (this is the destination) |

### Bootstrap convergence audit gate

> *"A bootstrap run is not complete until it has converged into steady
> state and any temporary bootstrap authority has either been sealed,
> rotated, or explicitly recorded as retained."*

This is the operational gate that prevents the bootstrap window from
silently extending into operations. Three valid outcomes for any
temporary bootstrap-time authority:

1. **Sealed** — the credential is now only in OpenBao, no longer on
   workstation disk, no longer in Ansible variable space, no longer in
   the SOPS bundle. Wipes are auditable.
2. **Rotated** — the credential that bootstrap saw is no longer valid;
   a new credential (typically generated in-cluster) is in use. The
   bootstrap-time copy is harmless even if leaked.
3. **Retained** — the credential is still trusted but its retention is
   explicitly recorded with a reason and a revisit gate. Used sparingly
   (Shamir DR shares per ADR-0009 are the canonical example).

`bootstrap-configure.yml` final-stage tasks (or
`bootstrap-verify.yml`) assert this gate. Implementation: a verifier
playbook checks the bootstrap-window credential set against an
inventory of expected outcomes, fails if any are still in the
"unconverged" state.

---

## 5. The eight decisions

The decisions that codify the slogan into a binding architecture.
Each: question / recommended answer / consequence-if-wrong.

### D1. Break-glass custody boundary

**Question:** Where do local-admin credentials live outside the cluster?

**Recommended answer:** OpenBao is steady-state custody; physical USB
recovery kit plus offsite backup are disaster custody. The bootstrap
workstation is NOT a credential store after the bootstrap window
closes.

The physical recovery kit contains:
- The local-admin password material for each app (per-app, unique,
  generated at wizard time, written to OpenBao + the kit).
- **Only the Shamir share(s) assigned to that medium** — not a full
  quorum. ADR-0009 binds a 3-of-5 distributed model; no single
  physical kit may hold three or more shares unless explicitly
  recorded as an experiment-phase retained risk under D2's bootstrap-
  convergence outcomes. The kit carries a reference to the other
  share locations (per the ADR-0009 location list) and the
  reassembly procedure, not the shares themselves.
- **A cold-paper lockout-recovery procedure** kept alongside the
  credential material in the same physical kit. The procedure is
  human-readable, requires no docs site access, and walks the operator
  through reassembling the Shamir quorum from distributed locations +
  unsealing OpenBao + retrieving credentials + restoring app access
  from a cold start. A second copy of the procedure lives in offsite
  backup.

The cold-paper requirement is binding (operator decision, 2026-05-23).
Custody without a recovery procedure is incomplete custody.

**Consequence if wrong:** one stolen/lost laptop or dead cluster becomes
either a credential compromise (workstation as store) or an
unrecoverable lockout (no physical fallback).

### D2. Bootstrap vs steady-state posture

**Question:** Is bootstrap allowed to have different trust assumptions?

**Recommended answer:** Yes. The two postures are explicitly named (§4
above): Bootstrap Trust Window and Steady-State Operations. Bootstrap
can temporarily concentrate authority; steady state MUST converge to
the contract statements (C1–C5). The bootstrap convergence audit gate
makes the handoff testable.

**Consequence if wrong:** reviewers judge the whole architecture by its
riskiest bootstrap moment (over-conservative), or operators
accidentally preserve bootstrap shortcuts forever (under-secure). Both
fail-modes break trust calibration.

### D3. Per-app local-account rule

**Question:** Can "only break-glass local account per app" become
binding now?

**Recommended answer:** Not until a per-app feasibility survey proves
it. The survey gates promotion across seven apps: Authentik, AWX,
NetBox, Forgejo, Zot, Grafana, dmf-cms. (LibreNMS deferred until
deployed on lab clusters.)

The survey deliverable per app:

```yaml
app: <name>
break_glass_feasible:     yes | no
oidc_projection_feasible: yes | no
shadow_account_behaviour: suppress | sanction | not-observed
sanctioned_exception_reason: <text or "none">
evidence:
  - <file:line refs from the app's role / blueprint>
  - <observation against g2r6-foa9 if relevant>
```

The `shadow_account_behaviour` field is required (operator refinement
R3). OIDC social-auth creates shadow superuser accounts in some apps
(observed in AWX as `<operator>22daa48fb6594ba3`). Whether to suppress
those at the OIDC-config layer or to sanction them as a known
side-effect must be explicitly classified per app — not left as a
discovery moment in production.

Per-app exceptions enumerated in §8 (the matrix) once the survey
completes. ADR-0028 ships with the matrix as binding.

**Consequence if wrong:** the slogan becomes false on day one (some app
silently has 14 local users), or implementation breaks apps whose
admin/bootstrap models require native local users.

### D4. Human identity authority

**Question:** What owns human identity and admin-role projection into
apps?

**Recommended answer:** Authentik owns ALL human identities. Passkeys
are primary auth. OIDC/SAML projects human users + groups into apps;
local app users are not created for humans except break-glass.

DMF Console's passkey-only flow (per ADR-0015) is the reference UX —
single click, browser passkey popup, no username field. Other apps use
the shared `default-authentication-flow` and retain username+password
forms for service accounts and non-passkey use. Group projection
(`ops-admin` → app-admin role per the blueprint at
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/20-app-providers.yaml.j2`)
remains the canonical mechanism for mapping organisational role to
per-app authority.

**Consequence if wrong:** every app becomes its own IAM island, the
non-expert flow chart collapses, and the slogan's first sentence is
false in practice.

### D5. Machine identity authority

**Question:** Where do service accounts and tokens come from?

**Recommended answer:** Native per-app service accounts/tokens, scoped
least-privilege, stored in OpenBao. Authentik does NOT mint service
credentials.

This is the codex correction to the operator's initial intuition.
Authentik supports OIDC clients that can represent services, but most
DMF apps (AWX personal tokens, NetBox API tokens, Forgejo service
tokens, registry pull credentials, K8s service accounts) require
tokens issued by the target app's own user/auth model. Forcing them
through Authentik either fails outright (no native OIDC support for
the API surface) or creates an awkward broker layer with no audit
benefit.

The boundary:
- **Authentik:** human identity, OIDC/SAML projection into apps, group
  membership.
- **Per-app native:** service users, service tokens, with custodial
  paths recorded centrally in OpenBao at `secret/apps/<app>/runtime`
  (or the app's canonical runtime path).

**Consequence if wrong:** either Authentik becomes an awkward secrets
broker (introducing a fragile single point of failure for machine
identity), or service credentials sprawl outside auditable custody
(killing the audit story).

### D6. Attribution strength

**Question:** Does DMF need dmf-cms attestation or cryptographically
bound attribution?

**Recommended answer:** For experiment phase and dynamic media-facility
operations, land on **strong dmf-cms attestation** now. Implementation:

- Immutable request log inside dmf-cms (one row per human-initiated
  action, indexed by request_id).
- Actor / session / request_id / reason quartet propagated to every
  downstream call:
  - **AWX:** `extra_vars` includes `dmf_requested_by`,
    `dmf_request_id`, `dmf_reason`, `dmf_role`.
  - **NetBox:** custom field `change_request_by` + comment text with
    the request_id; changelog correlated by request_id.
  - **Forgejo:** commit message footer carries
    `DMF-Requested-By: <actor>` and `DMF-Request-Id: <id>`.
  - **OpenBao:** audit context tag (`dmf-request-id=<id>`) where the
    audit backend supports it.
  - **Kubernetes:** dmf-cms API client sets a custom label/annotation
    on any object mutation carrying the request_id; K8s audit log
    correlates.

Do NOT block live operations on per-action cryptographic signing yet.
Cryptographic binding is the right destination for managed-service mode
(ADR-0020 Mode B) and for safety-critical automated changes (live
production graph mutations during a broadcast, e.g.), but the
complexity-vs-benefit math doesn't favour it during experiment phase.

**Revisit gate:** (a) ADR-0020 Mode B promotes to Accepted (managed-
service customers require cryptographic guarantees, not attestation);
or (b) the first safety-critical automated path lands (where a forged
request could affect live production output).

**Consequence if wrong:**
- Too weak (no attestation): audits say "the service account did it",
  attribution collapses, incident reviews can't reconstruct human
  decisions.
- Too strong (crypto binding before justified): live-production
  workflows slow under per-action signing latency; UX brittleness
  before the facility's operational model is proven.

### D7. Audit-log integrity pipeline

**Question:** What makes "records the human" trustworthy?

**Recommended answer:** Design streaming audit export to WORM as a
first-class architecture component, not nightly cron. dmf-cms, AWX,
NetBox, Forgejo, Authentik, OpenBao, and Kubernetes audit events all
need correlation IDs and retention rules.

Building on the [Pre-Release Compliance Readiness Plan](../plans/DMF%20Pre-Release%20Compliance%20Readiness%20Plan%202026-05-11.md)
Tier A.4 audit-log architecture:

- **Streaming export, not cron.** A cron-based archival has a window
  during which an attacker with app-admin can mutate the source audit
  log before export. Streaming closes the window.
- **Correlation IDs.** Every cross-app trace stays linkable. A human
  action that creates a NetBox change + an AWX job + a Forgejo commit
  is one chain in the WORM store, not three disconnected events.
- **Retention split** per the readiness plan:
  - 6 months hot in Loki for security-relevant streams.
  - 12 months WORM in object-locked S3 for the K8s API host file and
    cross-app correlated streams.
  - 30 days hot for general operational logs (no archival).

This is the *implementation* of C5's binding requirement. Without it,
attribution exists only in mutable app databases and cannot support
incident review under any compliance framework worth claiming.

**Supersession note:** D7's streaming-export commitment supersedes the
cron-based `audit-log-archival` mechanism described in
[`docs/processes/pre-release-compliance-checklist.md`](../processes/pre-release-compliance-checklist.md)
§A.4 for identity/authority audit streams. The cron model remains
valid for non-attribution log streams (general operational logging
that doesn't carry the actor/role/request-id/reason quartet). Update
the readiness plan + checklist to reflect this split before D7 can be
claimed implemented. Tracking: deferred to the same follow-on session
as ADR-0028 + D7 implementation work.

**Consequence if wrong:** attribution evaporates the moment an
attacker (or a buggy migration) touches the source database. C5 is
false in practice.

### D8. Operational hardening baseline

**Question:** What dormant controls does the slogan imply?

**Recommended answer:** Three binding defaults that the slogan requires
to actually hold under stress:

- **Scheduled break-glass drills** — monthly exercise of one local
  admin account against a real lockout scenario, with documented
  success/failure + password rotation. Otherwise break-glass works only
  the first time it's tried, and "first time tried" is during an
  actual incident.
- **Short OIDC access tokens with refresh and session-revoke-on-end** —
  10-15 minute access token lifetime; refresh-token revocation when
  the user session ends. Reduces the window an exfiltrated token is
  usable.
- **≥2 passkeys per human enrolled at wizard time** — single-device
  passkey loss must not lock the operator out. Hardware key + phone is
  a reasonable default; two hardware keys is stronger.

These are dormant in normal operation; their function is to make C4
(no routine break-glass), the OIDC attribution chain (C5), and the
recovery story (D1) work when something goes wrong.

**Consequence if wrong:** the model works in a diagram but fails under
lockout, lost passkey, stale credential, or abandoned session
conditions — i.e., precisely when it matters.

---

## 6. The four security planes

A conceptual diagram for non-expert audiences. Each plane is a
self-contained authority story.

```
┌─────────────────────────────────────────────────────────────────┐
│ HUMAN-IDENTITY PLANE                                            │
│                                                                 │
│  Operator ──passkey──▶ Authentik ──OIDC/SAML──▶ App user/role  │
│     │                       │                                   │
│     └── ≥2 passkeys         └── ops-admin group projection      │
│                                                                 │
│  Touched by: D4, D8, ADR-0015                                   │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ MACHINE-IDENTITY PLANE                                          │
│                                                                 │
│  App-native service user                                        │
│         │                                                       │
│         ├── App-issued token (AWX personal, NetBox API,         │
│         │   Forgejo service, registry pull, K8s SA)             │
│         │                                                       │
│         └── Custody recorded at secret/apps/<app>/runtime       │
│                                                                 │
│  Touched by: D5, C3                                             │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ CUSTODY PLANE                                                   │
│                                                                 │
│  OpenBao (cluster) ◀──────► Physical recovery kit (USB)        │
│       │                            │                            │
│       ├── secret/apps/<app>/admin  ├── per-app admin material  │
│       ├── secret/apps/<app>/runtime├── Shamir share(s) for this │
│       └── audit context tags       │   medium only (NOT quorum) │
│                                    ├── Reassembly procedure +   │
│                                    │   share-location reference │
│                                    └── Cold-paper procedure     │
│                                            │                    │
│                                            └── 2nd copy        │
│                                                offsite          │
│                                                                 │
│  Per ADR-0009: full 3-of-5 quorum is DISTRIBUTED across 5      │
│  locations; no single kit holds three or more shares.          │
│                                                                 │
│  Touched by: D1, D2, C2, ADR-0008, ADR-0009                     │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│ AUDIT PLANE                                                     │
│                                                                 │
│  dmf-cms request log (request_id, actor, role, reason)          │
│       │                                                         │
│       ├──▶ AWX extra_vars + job_events                          │
│       ├──▶ NetBox changelog + custom field                      │
│       ├──▶ Forgejo commit footer                                │
│       ├──▶ K8s audit (request_id annotation)                    │
│       └──▶ OpenBao audit context                                │
│                │                                                │
│                └──▶ Streaming export ──▶ WORM (object-lock S3) │
│                                                                 │
│  Touched by: D6, D7, C5                                         │
└─────────────────────────────────────────────────────────────────┘
```

The four planes are independent in design but cross-link operationally.
A given human action touches the human-identity plane (login), the
custody plane (token retrieval if needed), the machine-identity plane
(service-account execution), and the audit plane (correlation across
all three). Failure to wire one plane breaks the chain — the slogan
needs all four standing.

---

## 7. Per-app identity matrix

**Populated by the per-app feasibility survey 2026-05-24** at
[`docs/plans/DMF Per-App Identity Feasibility Survey 2026-05-24.md`](../plans/DMF%20Per-App%20Identity%20Feasibility%20Survey%202026-05-24.md).
The matrix below is the authoritative input to
[ADR-0028](../decisions/0028-identity-and-authority-chain.md).

| App | Break-glass feasible | OIDC-projection feasible | Shadow account | Sanctioned exception |
|---|---|---|---|---|
| Authentik | yes | n/a (Authentik *is* the IdP) | not-observed | **yes** — `akadmin` (Authentik bootstrap convention, pre-cleared) |
| AWX | yes (implemented as `awx-break-glass`) | yes (SAML) | sanction — `<operator>22daa48fb6594ba3` shadow observed; collision artefact, not an exception (see survey §3.2 + ADR-0028) | none — rename landed as D3 implementation, not a carve-out |
| NetBox | yes | yes | not-observed (`associate_by_email` + `preferred_username` link) | none |
| Forgejo | yes | yes | not-observed (`account_linking: auto` + `username_source: userid`) | none |
| Zot | yes (must keep `admin` — htpasswd) | partial (OIDC client provisioned; activation in `vertical-security/191-zot-oidc.yml`) | not-observed | **yes** — `admin` (htpasswd constraint, pre-cleared) |
| Grafana | yes | yes (`generic_oauth`, `disable_login_form: true`) | not-observed (OIDC links by `auth_id`) | **yes** — `admin` (chart default; reaffirmed 2026-05-25, no rename) |
| dmf-cms | n/a (no local user DB) | yes (passkey-only flow per ADR-0015) | n/a | none |

LibreNMS deferred until deployed on lab clusters.

**Confirmed sanctioned exceptions** (the three from ADR-0024 §3, all
re-validated by the survey, no fourth exception emerged): Authentik
(`akadmin`), Zot (`admin`), Grafana (`admin`).

**AWX shadow superuser is NOT a sanctioned exception.** It is the
deterministic consequence of a username collision between the local
bootstrap admin (`<operator>`) and the same operator's SAML-projected
identity (also `<operator>`) given AWX's default SOCIAL_AUTH pipeline.
Remediation is architectural — rename AWX local admin to a
non-colliding break-glass identity (e.g. `awx-break-glass`) and align
AWX's SOCIAL_AUTH pipeline with NetBox's `associate_by_email` pattern.
Landed as D3 implementation in `dmf-infra@c426dc0`; not a carve-out.

---

## 8. Time-bound and open decisions

| ID | Status | Revisit gate |
|---|---|---|
| D1 | Binding | n/a |
| D2 | Binding | n/a |
| D3 | Binding — survey closed 2026-05-24; 3 exceptions confirmed (Authentik / Zot / Grafana); AWX rename landed as follow-on, not a carve-out; Grafana rename evaluated and rejected 2026-05-25 | n/a |
| D4 | Binding | n/a |
| D5 | Binding | n/a |
| **D6** | **Binding — for experiment phase** | **ADR-0020 Mode B promotion** OR **first safety-critical automated path** |
| D7 | Binding (architectural commitment) — implementation per Tier A.4 readiness | n/a |
| D8 | Binding (operational defaults) — drills + token TTL + ≥2 passkeys | n/a |

D6 is the only decision with a forward revisit gate. All others are
binding in the current phase. D3's binding-ness rides on §7.

---

## 9. Relationship to other documents

- **[ADR-0024 — Two-Identity Admin Model](../decisions/0024-two-identity-admin-model.md):**
  Predecessor. Codified the *local + OIDC* split. ADR-0028 (when it
  ships) supersedes ADR-0024 §Alternatives' "Generalise the helper to
  read OpenBao too" deferral and the implicit assumption that local
  admin material lives only in OpenBao (D1 adds the physical kit).
- **[ADR-0015 — DMF Console passkey-only](../decisions/0015-dmf-console-passkey-only.md):**
  Reference UX precedent for D4. Not amended.
- **[ADR-0007 — Secrets never in argv](../decisions/0007-secrets-never-in-argv.md):**
  Transport-layer discipline that D6 and D7 inherit. Not amended.
- **[ADR-0020 — Deployment scope and regulatory posture](../decisions/0020-deployment-scope-and-regulatory-posture.md):**
  Mode B promotion is D6's revisit gate. Not amended.
- **[Unified App-Admin Helper Plan v3](../plans/DMF%20Unified%20App-Admin%20Helper%20Plan%202026-05-23.md):**
  Downstream implementation of D1's "OpenBao custody" half. The plan is
  the helper-role mechanism; this document is the architectural
  authority for that mechanism. The plan was drafted before this model
  existed; it has since been reframed as "implementation under D1".
- **[Per-App Identity Feasibility Survey 2026-05-24](../plans/DMF%20Per-App%20Identity%20Feasibility%20Survey%202026-05-24.md)
  (sibling plan, closed):** §7's data source. D3 promotion gate
  satisfied 2026-05-24.
- **[Pre-Release Compliance Readiness Plan](../plans/DMF%20Pre-Release%20Compliance%20Readiness%20Plan%202026-05-11.md):**
  Tier A.4 audit-log architecture is D7's implementation track.

---

## 10. Provenance — three-reviewer pattern

This document was produced by a deliberate three-reviewer chain:

1. **Operator — concept owner.** Stated the slogan in plain
   language; refined positions against the dissection; selected
   options 2+3 for execution.
2. **claude-bottom — drafter + adversarial reviewer.** 11-flaw
   dissection of the slogan (3 critical, 3 important, 5 operational);
   3 refinements (R1, R2, R3); architecture doc draft.
3. **codex — independent code-grounded reviewer.** Step-back conceptual
   analysis surfaced the human-identity-vs-service-account
   misconception that the operator had carried forward (Authentik as
   home for everything). 8-decision distillation. 5-statement
   contract-language tightening. Bootstrap convergence audit gate.
4. **claude-top — review + per-app survey owner.** v2 plan review (the
   precursor unified-helper plan), survey owner via agent-bridge
   delegation.

The three-reviewer pattern caught material that the two-Claude pattern
missed (notably the NetBox-OpenBao-admin misclassification that would
have wasted several PRs of implementation work). For future
architecture-scale work, **recommend repeating the pattern**: drafter +
adversarial Claude reviewer + independent code-grounded codex reviewer,
with the operator as the final concept gate.

---

## 11. Glossary

Brief definitions for terms that recur:

- **Slogan** — the four-line statement in §2.
- **Contract statement (Cn)** — one of the five top-of-doc canonical
  assertions in §3.
- **Decision (Dn)** — one of the eight question/answer/consequence
  blocks in §5.
- **Refinement (Rn)** — three operator-level scope refinements added
  after codex's distillation: R1 (single-operator scope, §1), R2 (cold-
  paper procedure, D1), R3 (shadow-account survey deliverable, D3).
- **Bootstrap window** — the period from `bin/init-wizard.sh` execution
  to the bootstrap convergence audit gate passing. See §4.
- **Steady state** — the operational mode after the bootstrap window
  closes; the slogan describes this mode.
- **Break-glass** — local-admin account per app, dormant in normal
  operation, used only for review or lockout recovery. C4 binds
  routine-use exclusion; D1 binds custody; D8 binds drill cadence.
- **Shadow account** — an OIDC-social-auth-created user in an app's
  native user table, distinct from the OIDC-projected user with the
  expected username. Observed in AWX. Per-app classification is a D3
  survey deliverable.
- **Physical recovery kit** — USB-format custody device(s) containing
  per-app admin material, Shamir shares, and the cold-paper
  lockout-recovery procedure. Per D1.
- **Streaming export** — audit-log architecture in which app-side
  audit events are written to WORM storage in near-real-time, closing
  the window during which a compromised app admin could mutate the
  source log before nightly archival. Per D7.
