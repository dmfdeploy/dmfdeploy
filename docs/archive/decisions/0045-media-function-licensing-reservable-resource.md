# ADR-0045 archive: media function licences as IAMT leases

This file holds material moved out of [ADR-0045](../../decisions/0045-media-function-licensing-reservable-resource.md). Until 2026-10-25 the ADR was titled "Media function licensing is a reservable resource behind a provider seam; declared-but-not-enforced until a real provider exists." The sections up to and including "Moved from the ADR on 2026-10-23" came out when the ADRs were cut to a short shape. Their text is unchanged apart from headings, relative link paths and one voice pass on 2026-10-25: dashes became colons, commas or parentheses, and four contrast phrasings were restated with the same meaning. The last section records the 2026-10-25 revision onto the IAMT model. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Mock licence pool via NetBox tags (`licence:assigned`).** Rejected: a tag
  cannot represent counts, leases, concurrency, idempotency, rollback, expiry, or
  external entitlement mapping. It would teach the wrong model, pollute NetBox
  (an inventory/instance store that holds no reservation ledger), and produce a
  demo that *looks* like enforcement while proving nothing: the classic
  misleading fake.
- **Build a real reservation provider now (in v0.2).** Rejected for v0.2: our
  current functions (MXL, nmos-cpp/crosspoint) are unlicensed, so there is no
  driver, and a correct provider (atomic assign, deny-on-exhaustion, idempotent
  release, rollback, expiry) is a workstream that would crowd out the v0.2
  lifecycle-legibility slice. Deferred to a deliberately chosen later slice.
- **Omit licensing entirely / no ADR.** Rejected: the EBU model makes licences a
  first-class reservable resource; leaving it unmodelled is the silent gap this
  ADR exists to close. Recording the seam now (with declared-but-inert fields)
  is the cheap, honest middle.

## Context: EBU whitepaper background (moved from the ADR)

The EBU Dynamic Media Facility model treats **media-function licences as a
reservable resource**, on the same footing as compute/network/storage. The
whitepaper (pp. 3–4): **Plan** *"reserve … resources … and set up authorisations
for their access"*; **Operate** changes are *"limited to available resources
(compute, **licences**, connectivity, storage)"*; **Finalise** *"delete … Media
Functions, authorisations and reservations."* The orchestration figure's MEDIA
FUNCTIONS row spells out the lifecycle: **Ensure Licence Availability** (Plan) →
**Assign Licences** (Provision) → **Release Licences** (Finalise) → **Monitor
Licence Usage** (Monitor) → **Authorise/Audit Workload Usage** (Security).

## Moved from the ADR on 2026-10-23

### Metadata and RFC note (original)

**Relates to:** ADR-0003 (EBU taxonomy), ADR-0013 (media function catalog model),
ADR-0037 (Media Workloads = NetBox instance inventory), ADR-0028 (identity &
authority chain: authorisation of the reserve/release actions)

> **RFC status:** this ADR should be raised as a Discussions RFC before moving to
> Accepted ([RFC before ADR](../../decisions/README.md#propose-a-decision-with-an-rfc)). It is recorded as **Proposed** now so
> the v0.2 re-anchor plan has a stable seam to point at.

### Context (original)

DMF today has **no licensing model at all**: no ADR, no plan, no catalog field, no
NetBox model, no console surface. The console IA reserves a "Licenses" rail slot
but nothing designs it. Our current media functions (MXL, nmos-cpp/crosspoint) are
open/unlicensed, so there has been no concrete driver.

While re-anchoring v0.2 on the lifecycle, the north-star scenario ("two *licensed*
functions …") forced the question: build a licence subsystem now, or defer it? The
tempting shortcut (a "mock licence pool" of NetBox tags, `licence:assigned`) was
rejected: a tag cannot represent counts, leases, concurrency, idempotency,
rollback, expiry, or external entitlement mapping, so it would **teach the wrong
model** and pollute NetBox (a facility inventory + instance record that holds no
reservation ledger).

### Decision (original)

1. **Licences are modelled as a reservable resource behind a provider interface**,
   and ad-hoc tags are not used. In v0.2, define the interface and no implementation:

   ```
   LicenceReservationProvider:
     check(licence_class, count)        -> availability (available/exhausted)
     reserve(licence_class, count, ctx) -> reservation_id            # atomic; denies on exhaustion
     release(reservation_id)            -> ok                        # idempotent
     usage(licence_class?)              -> {capacity, assigned, leaked}
   ```
   - **`ctx` (required reserve context):** `idempotency_key` (typically the
     originating `request_id`), `function_key` (catalog key), `instance_id`
     (target NetBox instance), `actor` (requesting human, for the C5 record).
     **Reserve is retry-idempotent on `idempotency_key`:** a duplicate `reserve`
     with the same key returns the **same** `reservation_id` (does not double-
     assign), so a retried launch cannot leak seats. `release` is idempotent on
     `reservation_id`.
   - A catalog entry **declares** its required licence classes (the `licence:`
     block; schema in §Decision.2).
   - Provision/Configure launchers **reserve** and receive a `reservation_id`;
     Finalise (and any **failed launch**) **release** it idempotently, so no reservation
     leaks. Monitoring reads `usage()` (assigned vs capacity vs leaked).
   - The reserve/release actions are authorised + audited per ADR-0028 (C5).

   **Seam scope:** this ADR fixes the **interface seam** (the four methods, the
   `ctx` contract, the idempotency semantics, and NetBox-is-not-the-ledger). It
   does **not** fully specify provider internals: concurrency model, lease
   expiry, and whether Plan-stage reservation is separate from Provision-stage
   assignment are **deliberately open** and gated by a **later provider-slice
   ADR/spec**, written when the provider is built. Callers depend only on the
   seam above and are unaffected by those choices.

2. **v0.2 scope = declared-but-NOT-enforced.** v0.2 reserves the catalog/schema
   fields so a real provider slots in without rework, but **builds no provider and
   enforces nothing**. No mock tag-pool. The v0.2 catalog block:

   ```yaml
   # optional top-level block in a catalog entry; absent/empty = no licence requirement
   licence:
     required:
       - class: <string>      # licence class identifier
         count: <integer ≥ 1> # seats/instances per deployment
   ```
   In v0.2 this is **parsed, schema-validated, and may be displayed** as declared
   intent and nothing more (no `check`/`reserve`/`deny`/`release`, no NetBox
   lease/tag state). "licensed" is kept out of the v0.2 demo headline and tracked
   as a follow-on claim.

3. **A real provider is a later, deliberately chosen slice**, implemented only
   when a genuinely licensed function exists to drive it, or when the operator
   explicitly wants a resource-reservation spike. When built, it must demonstrate
   the failure semantics that make it honest: **deny on exhaustion, atomic
   assign, idempotent release, and rollback on failed launch.**

4. **NetBox is not the reservation ledger.** NetBox continues to record *which*
   function and *how many* instances (ADR-0037). The reservation ledger (leases,
   counts, expiry) belongs to the provider (its backend chosen when built:
   in-cluster store, OpenBao-backed, or an external entitlement service). NetBox
   may reference a `reservation_id`, but does not own the lease state.

### Consequences (original)

- **Positive:** the EBU licence thread becomes a recorded, intentional deferral
  with a defined seam where there was a silent gap; the catalog schema is forward-compatible;
  we avoid a misleading fake; a real provider (or external entitlement mapping)
  can be added later without touching callers.
- **Negative / accepted:** v0.2 cannot truthfully claim licence enforcement; the
  north-star "licensed" scenario waits on the provider slice; the `licence:` block
  sits declared-but-inert (documented as such so it is not mistaken for enforced).
- **Open (for the RFC / provider slice):** licence-class taxonomy; provider
  backend; concurrency/expiry semantics; whether Plan-stage reservation is
  separate from Provision-stage assignment; external-entitlement mapping.
- **Reference input (added 2026-10-07):** the IAMT *Dynamic Software Licensing*
  best practices v1.0.0 (2026-09-07) speak to all five open items above:
  entitlement vs lease split, lease lifecycle, canonical API, grace policy.
  Read the [summary and DMF relevance note](../../references/iamt-dsl-v1-0-0-summary-and-relevance.md)
  before opening the RFC.

## Moved from the ADR on 2026-10-25: the IAMT revision

This section records why the ADR moved from a reservation seam to the IAMT *Dynamic Software Licensing Best Practices* v1.0.0 model ([dmfdeploy/dmfdeploy#761](https://github.com/dmfdeploy/dmfdeploy/issues/761)). Section numbers (§, Annex) are IAMT's. The ADR text from 2026-10-23 restated the "(original)" sections with the same meaning. It's at [this commit](https://github.com/dmfdeploy/dmfdeploy/blob/524447b051045fc588067a95a6db9728565adb2f/docs/decisions/0045-media-function-licensing-reservable-resource.md).

### What the revision replaced

| Old seam | New position | IAMT basis |
|---|---|---|
| `check(class, count)` | Plan holds nothing; an entitlement query is an RFC question | §10.02, Annex B (no query call) |
| `reserve(class, count, ctx)` at Provision | The function's licence agent calls Issue; the launcher supplies inputs | §07.04, §07.07, §10.02 |
| Plan-stage reservation (left open) | No Plan-stage hold | §10.02 checks quota only at Issue |
| `ctx.idempotency_key` | An opaque `workId` the platform supplies; its contract is an RFC question | §07.01, §10.01, INT-4 |
| `ctx.instance_id` as binding | Workload identity binds; the instance id only correlates | IDB-1, IDB-2, §11.06 |
| `release(reservation_id)` | Revoke (`DELETE`, lease becomes REVOKED): `decommissioned` at teardown; whether teardown needs TERMINATED is an RFC question | §10.05, Annex D |
| `usage()` with "leaked" | Read-only usage records; a project reconciliation rule, "unreleased lease", replaces "leaked" | §10.06, Annex D (expiry) |
| `licence: {required: [{class, count}]}` | `licence: {app, modality, term, dimensions}`, with `modality` a project class | §04.03 concepts, §10.02, §11.02 |
| `LicenceReservationProvider` | `LicenceControlPlaneAdapter` | §08.01 automation adapter |

### The three roles

The relevance note named three roles the platform could play.

- **Orchestration client (adopted).** It fits an orchestrator, §10.02 allows orchestration-triggered Issue, and INT-2 asks for licensing in provisioning and teardown.
- **Host a control plane (rejected for this ADR).** The platform would become the ledger and a control-plane conformance target, with signing keys, a JWKS endpoint, an entitlements service and a usage store (§07.02). No function on the platform needs that today. A customer could still run a control plane on the cluster as its own package, outside the platform's core.
- **Observe only (rejected).** Agents don't revoke their own leases (§10.05, authorization table). An observer couldn't return a lease at teardown, so every lease would wait for expiry.

### Who calls Issue

The adopted option has the licence agent call Issue from inside the workload. The alternative had the launcher call Issue with evidence it mints for the workload's service account. That would put the workload's identity evidence in the launcher's hands. Renewal still re-verifies identity from the workload side (IDB-3), and the agent still has to deliver the token to the application (§07.04). The alternative adds a privileged path and saves nothing.

### Why Plan holds nothing

IAMT checks quota at Issue and has no hold call in Annex B. A hold kept by the platform can't bind the control plane, so another consumer could still take the slot. The console would show a guarantee it can't keep, which is the misleading-fake problem the first version of this ADR rejected. The first IAMT draft also had Plan run an entitlement query that answered covered, uncovered or unknown. Annex B has no such call, so the review moved it to the RFC, and Plan shows coverage as unknown until the RFC settles it.

### Revoke and terminate

The first IAMT draft called teardown "Annex D's Terminate intent" sent as `DELETE` with reason `decommissioned`. The review showed that this conflates two states. §10.05 names that call Revoke and sets the lease to `revoked`; Annex D lists REVOKED and TERMINATED as separate states and gives TERMINATED no baseline call. The ADR now states what IAMT gives (Revoke, REVOKED) and asks in the RFC whether a controlled teardown needs TERMINATED through a backend extension.

### Corrections after review (2026-10-25)

A codex review of the first IAMT draft found claims the IAMT text doesn't support. The ADR now leaves seven contracts to the RFC. They are the `workId` construction, an entitlement query, lease lookup by `workId`, the authority the platform closes leases with, the readiness predicate, the grace display contract, and the exact modality enum with its #245 alignment. On readiness, Annex D lets Issue enter ISSUED or ACTIVE, so "running only at ACTIVE or RENEWED" overstated it. Two more claims were withdrawn. A present-tense Profile B claim became a target for a later slice, because a declared-only release can't show the behavior §08.02 asks for. The "unreleased lease" lost its WF-13 and §13.03 citations, because neither section defines it; it's a project reconciliation rule.

### Grace from the platform's side

Grace runs while the control plane is unreachable (§12.06). A platform that learns lease state only from the control plane sees nothing during the period the operator most needs to see. The lease snapshot (`expiresAt` and the policy, Annex C) and the agent are the candidate sources; which one emits each alarm, and how the console handles stale data, are RFC questions.

### Alternatives considered in the revision

- **Keep the four-method seam and map it to IAMT later.** Rejected: `check` and `reserve` have no IAMT counterpart, and an outside publisher would build against a shape that's due to change.
- **Put grace policy in the descriptor.** Rejected: the vendor sets policy as an entitlement default, and the tenant may override it only where the vendor allows (OFG-3).
- **Use the provider-backend candidate recorded on #245 as the model.** Rejected as a model: it fitted the old four methods. It stays a candidate backend, measured against Annex B, Annex C, Annex D and OFG-2 like any other.
