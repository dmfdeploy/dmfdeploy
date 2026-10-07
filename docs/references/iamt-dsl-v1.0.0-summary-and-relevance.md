# IAMT Dynamic Software Licensing v1.0.0 — summary and DMF relevance

**Source:** International Association of MediaTech (IAMT), *Dynamic Software
Licensing — Best Practices*, version 1.0.0, published 2026-09-07. 297 pages.
Apache License 2.0. Downloaded 2026-10-07 from
<https://theiamt.org/wp-content/uploads/2026/09/dynamic-software-licensing-best-practices-v1.0.0.pdf>.
Local copy: [iamt-dynamic-software-licensing-best-practices-v1.0.0.pdf](iamt-dynamic-software-licensing-best-practices-v1.0.0.pdf)
(SHA-256 `ffa6337b6406114d79f7bd4af0b75650ccea743c0ba5567f3a68a31f4d9fa472`).

**Status in DMF:** reference input only. Licensing is parked. This note
decides nothing and schedules nothing. It exists so whoever picks up the
ADR-0045 licensing RFC (tracked under the marketplace RFC track,
[dmfdeploy/dmfdeploy#245](https://github.com/dmfdeploy/dmfdeploy/issues/245))
starts from this document instead of from a blank page.

Section numbers below (§NN.NN) refer to the IAMT document. The first two
sections summarise what the document says. The last three are our reading of
how it bears on DMF; treat them as starting hypotheses for the RFC, not as
findings.

## What the document is

Dynamic Software Licensing (DSL) is an industry best-practice model for
licensing software in broadcast and media environments where workloads are
short-lived, automated, mobile across sites and clouds, and expected to fail
over. It is explicitly *not* a formal standard, a certification programme, or a
product (§00). It is written in standard-like form: terminology, a reference
model, conformance profiles, about 190 normative MUST statements, a canonical
REST API with an OpenAPI companion, a canonical data model, a security and
trust framework, operational profiles, and a migration path.

Its central move is to **separate commercial entitlement from runtime
authorisation**.

## Core model

- **Entitlement** — the durable commercial right a tenant holds for an
  application: which dimensions (channels, FPS, bandwidth, sessions), which
  licence modality, which policy. Exists independently of any running workload
  (§07.01).
- **Lease** — a time-bounded, signed grant of part of an entitlement to one
  specific workload identity. The control plane issues it only after it checks
  the entitlement, the requested dimensions, and quota availability (§07.01).
- **Token** — the signed JWS/JWT form of a lease. The workload validates it
  locally, with no per-use round trip to the control plane (§12.06 OFG-1).
- **Identity evidence** — how a workload proves who it is: OIDC workload
  tokens, SPIFFE/SVID, X.509, or a Kubernetes service-account JWT. It replaces
  hostname or MAC binding.
- **Policy** — renewal window, offline grace duration, the action on grace
  exhaustion, alert thresholds, and retry backoff. The vendor sets the default;
  the tenant may override only where the vendor allows (§12.06 OFG-2, OFG-3).
- **Work ID** — a correlation identifier per deployment or run, used for
  idempotency, audit, and reissue. It is a tracking reference, not a binding.
- **Licence modalities** (§04.03) — time-based, process-based (continuous
  counters such as channel count or FPS), outcome-based (counted outputs such
  as transcode jobs), and credit or unit pools (depleting or floating). Lease
  types are fixed-term, credit-consumption, or audit-based post-paid, where the
  application never stops and usage is reconciled later.

**Two planes.** The *control plane* owns entitlements, lease issuance, policy,
revocation, and usage intake. The *workspace plane* is where applications run.
There, a **licence agent** (sidecar, daemon, or CLI) gathers identity
evidence, issues and renews leases, delivers the token to the application,
buffers usage events, and enforces grace. An application SDK validates the
token in process (§07.02).

**Lease lifecycle** (Annex D): `ISSUED → ACTIVE → RENEWED`, `REISSUING` (a
controlled transfer to a new identity, for failover), `REVOKED`, `EXPIRED`, and
`TERMINATED`. Expiry (validity ran out) and termination (a deliberate close)
are distinct states.

**Canonical API** (Annex B, §10): `POST /v1/leases` (issue),
`:renew`, `:reissue`, `:finalizeReissue`, `GET` (inspect), `DELETE` (revoke),
`POST /v1/usage-records`, and `/.well-known/jwks.json`. Errors use RFC 9457
problem details. Requests carry `app`, `tenantId`, `identityEvidence`,
`client`, trace context, and `workId`.

**Offline and grace** (§12.06): disconnection must produce bounded, observable
behaviour. Grace exhaustion triggers one of three actions — **DRAIN** (finish
current work, refuse new), **DEGRADE** (reduced capability), or **STOP**.
Operators must be alerted as grace counts down. Offline time is bounded, and
revocation cannot be evaded past the next renewal attempt.

**Conformance profiles** (§08, Annex A) are cumulative:

| Profile | Shape |
|---|---|
| A — Foundational | Issue/renew/revoke/inspect, signed tokens with local validation, identity binding, explicit grace policy, basic audit. |
| B — Cloud Native | API-first lifecycle, IaC and orchestration integration, mature retry and reissue under workload churn, usage reporting for operations and finance. |
| C — Advanced Interoperable | Cross-vendor semantic stability, hybrid and DR portability, tenant isolation, evidence partners can rely on. |

Conformance targets are separate: control plane, workspace plane, interfaces
(SDKs, CLIs, portals, *automation adapters*), and end-to-end systems (§08.01).

**Integration requirements** (§09.09) matter most to an orchestrator: every
routine lifecycle step must be automatable (INT-1), licensing should take part
in provisioning and teardown (INT-2), it must run headless (INT-3), and
correlation IDs should link licence events to deployment and workflow contexts
(INT-4).

**Out of scope** (§02.02): wrapping or federating existing proprietary licence
managers, the media functions themselves (they are only API consumers), ERP and
billing integration, and legal contract wording.

## Why it matters to DMF

[ADR-0045](../decisions/0045-media-function-licensing-reservable-resource.md)
(Proposed) parks licensing as a `LicenceReservationProvider` seam —
`check` / `reserve` / `release` / `usage` — with a catalog `licence:` block
that is declared but not enforced. It lists five open items for the RFC:
licence-class taxonomy, provider backend, concurrency and expiry semantics,
whether Plan-stage reservation is separate from Provision-stage assignment, and
external-entitlement mapping. DSL is the first published industry model for
our domain that speaks to all five.

It also confirms several ADR-0045 choices independently:

- **NetBox is not the ledger.** DSL puts lease state in a dedicated control
  plane, which matches ADR-0045 §Decision.4.
- **Idempotency on a correlation key.** DSL's `workId` plays the same role as
  ADR-0045's `ctx.idempotency_key`.
- **Leases, expiry, and revocation are first-class.** These are the semantics
  ADR-0045 rejected NetBox tags for being unable to hold.

## How the seams line up

| ADR-0045 | Nearest DSL concept | Gap or question |
|---|---|---|
| `check(class, count)` | Entitlement plus quota check inside Issue | DSL has no standalone pre-flight call. The EBU "Ensure Licence Availability" step at Plan maps to an entitlement query, not a lease. |
| `reserve(class, count, ctx)` → `reservation_id` | Issue → `leaseId` plus signed token | DSL never reserves ahead of runtime. A lease binds to a *running workload's* identity, so it cannot exist at Plan stage. For the ADR-0045 open item, this means DSL leaves any Plan-stage reservation to us, as something separate from the lease. |
| `ctx.idempotency_key` | `workId` | Direct match. |
| `ctx.instance_id` | Identity evidence (for example a Kubernetes service-account JWT) | DSL binds to a *cryptographic workload identity*, not an inventory ID. That ties licensing to the identity work in ADR-0028, which may itself be stale. |
| `ctx.actor` (C5 audit) | Not modelled; DSL audit is per lease event | DMF still owns the who-asked record. |
| `release(reservation_id)` | Revoke (`DELETE`) or Terminate | DSL separates revoke (early) from terminate (deliberate close). The Finalise stage maps to terminate; failed-launch rollback maps to revoke. |
| `usage(class?)` → capacity / assigned / leaked | Inspect plus usage records | DSL usage records are *metering events* from the workload, not an inventory view. "Leaked" has no DSL equivalent; in DSL an abandoned lease simply stops renewing and expires. |
| `licence: {required: [{class, count}]}` | Entitlement dimensions plus modality | A single `count` cannot express DSL dimensions (channels, FPS, bandwidth) or modality. The catalog block likely needs a dimension map before it leaves the declared-only state. |

## Questions to carry into the ADR-0045 RFC

1. **Which DSL role does DMF play?** We see three options:
   - **(a) An orchestration client.** The vendor or customer runs a DSL control
     plane. DMF triggers Issue at Provision, as §10.02 explicitly allows. This
     fits §08.01 "automation adapter" conformance and the INT requirements.
   - **(b) DMF hosts a control plane** for facility-wide pools.
   - **(c) DMF only observes leases** that licence agents acquire on their own.

   Option (a) looks like the natural fit for an orchestrator, because ADR-0045
   already keeps the backend out of DMF's core. It has one consequence:
   `LicenceReservationProvider` would become an adapter to a DSL control plane
   rather than the ledger itself.
2. **Who calls Issue — the launcher or the workload's licence agent?** In DSL
   the agent sidecar, holding the workload's own identity, normally calls
   Issue. If DMF's launcher calls it, the lease binds to whose identity? This
   is the hardest design question, and it depends on the identity model.
3. **Grace exhaustion as an alarm.** DRAIN/DEGRADE/STOP and the OFG-7
   countdown alerts look like inputs to the console alarm taxonomy and to the
   EBU "Monitor Licence Usage" step.
4. **Licence-class taxonomy.** DSL modalities and dimensions are a ready-made
   starting vocabulary. They line up with the capability-classes RFC on #245.
5. **Conformance target.** Profile B (Cloud Native) describes DMF's runtime
   shape. Reissue for failover (Annex G sequence 3) touches HA, which is a v0.1
   non-goal, so leave it out of any first slice.
6. **Backend candidate.** The provider-backend candidate recorded on #245
   should be measured against DSL's canonical API and lease states, not only
   against ADR-0045's four methods. A DSL-shaped adapter seam keeps the backend
   swappable.

## Re-entry pointers

- Start with §07.01 (conceptual model), Annex B (API), Annex D (lifecycle), and
  §12.06 (grace). These sections hold most of what the RFC needs.
- §10.02 covers the Issue flow, including orchestration-triggered acquisition.
- §09.09 lists the integration requirements an orchestrator must meet.
- §13 describes operational profiles: 24x7 broadcast, event production, test
  and validation, and hybrid/DR.
- The document refers to an OpenAPI companion (`api/dsl-api.openapi.yaml`) in
  IAMT's own source repository. The PDF gives no repository URL, so find it
  before designing an adapter.
