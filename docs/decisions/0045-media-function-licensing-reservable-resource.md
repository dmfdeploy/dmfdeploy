# ADR-0045: Media function licensing is a reservable resource behind a provider seam; declared-but-not-enforced until a real provider exists

**Status:** Proposed
**Date:** 2026-07-07
**Deciders:** @znerol2, design conversation with Claude (2026-07-07) while
re-anchoring v0.2 on the EBU facility-orchestration model; adversarially reviewed
by codex (RESCOPE round, P1.2/P2 folded)
**Relates to:** ADR-0003 (EBU taxonomy), ADR-0013 (media function catalog model),
ADR-0037 (Media Workloads = NetBox instance inventory), ADR-0028 (identity &
authority chain — authorisation of the reserve/release actions)

> **RFC status:** this ADR should be raised as a Discussions RFC before moving to
> Accepted (CONTRIBUTING RFC-before-ADR). It is recorded as **Proposed** now so
> the v0.2 re-anchor plan has a stable seam to point at.

## Context

The EBU Dynamic Media Facility model treats **media-function licences as a
reservable resource**, on the same footing as compute/network/storage. The
whitepaper (pp. 3–4): **Plan** *"reserve … resources … and set up authorisations
for their access"*; **Operate** changes are *"limited to available resources
(compute, **licences**, connectivity, storage)"*; **Finalise** *"delete … Media
Functions, authorisations and reservations."* The orchestration figure's MEDIA
FUNCTIONS row spells out the lifecycle: **Ensure Licence Availability** (Plan) →
**Assign Licences** (Provision) → **Release Licences** (Finalise) → **Monitor
Licence Usage** (Monitor) → **Authorise/Audit Workload Usage** (Security).

DMF today has **no licensing model at all**: no ADR, no plan, no catalog field, no
NetBox model, no console surface. The console IA reserves a "Licenses" rail slot
but nothing designs it. Our current media functions (MXL, nmos-cpp/crosspoint) are
open/unlicensed, so there has been no concrete driver.

While re-anchoring v0.2 on the lifecycle, the north-star scenario ("two *licensed*
functions …") forced the question: build a licence subsystem now, or defer it? The
tempting shortcut — a "mock licence pool" of NetBox tags (`licence:assigned`) — was
rejected: a tag cannot represent counts, leases, concurrency, idempotency,
rollback, expiry, or external entitlement mapping, so it would **teach the wrong
model** and pollute NetBox (which is a facility inventory + instance record, not a
reservation ledger).

## Decision

1. **Licences are modelled as a reservable resource behind a provider interface**,
   not as ad-hoc tags. Define (interface, not implementation, in v0.2):

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
     block — schema in §Decision.2).
   - Provision/Configure launchers **reserve** and receive a `reservation_id`;
     Finalise (and any **failed launch**) **release** it idempotently — no leaked
     reservations. Monitoring reads `usage()` (assigned vs capacity vs leaked).
   - The reserve/release actions are authorised + audited per ADR-0028 (C5).

   **Seam scope:** this ADR fixes the **interface seam** (the four methods, the
   `ctx` contract, the idempotency semantics, and NetBox-is-not-the-ledger). It
   does **not** fully specify provider internals — concurrency model, lease
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
   intent — nothing more (no `check`/`reserve`/`deny`/`release`, no NetBox
   lease/tag state). "licensed" is kept out of the v0.2 demo headline and tracked
   as a follow-on claim.

3. **A real provider is a later, deliberately-chosen slice** — implemented only
   when a genuinely licensed function exists to drive it, or when the operator
   explicitly wants a resource-reservation spike. When built, it must demonstrate
   the failure semantics that make it honest: **deny on exhaustion, atomic
   assign, idempotent release, and rollback on failed launch.**

4. **NetBox is not the reservation ledger.** NetBox continues to record *which*
   function and *how many* instances (ADR-0037). The reservation ledger — leases,
   counts, expiry — belongs to the provider (its backend chosen when built:
   in-cluster store, OpenBao-backed, or an external entitlement service). NetBox
   may reference a `reservation_id`, but does not own the lease state.

## Alternatives considered

- **Mock licence pool via NetBox tags (`licence:assigned`).** Rejected: a tag
  cannot represent counts, leases, concurrency, idempotency, rollback, expiry, or
  external entitlement mapping. It would teach the wrong model, pollute NetBox
  (an inventory/instance store, not a reservation ledger), and produce a
  demo that *looks* like enforcement while proving nothing — the classic
  misleading fake.
- **Build a real reservation provider now (in v0.2).** Rejected for v0.2: our
  current functions (MXL, nmos-cpp/crosspoint) are unlicensed, so there is no
  driver, and a correct provider (atomic assign, deny-on-exhaustion, idempotent
  release, rollback, expiry) is a workstream that would crowd out the v0.2
  lifecycle-legibility slice. Deferred to a deliberately-chosen later slice.
- **Omit licensing entirely / no ADR.** Rejected: the EBU model makes licences a
  first-class reservable resource; leaving it unmodelled is the silent gap this
  ADR exists to close. Recording the seam now (with declared-but-inert fields)
  is the cheap, honest middle.

## Consequences

- **Positive:** the EBU licence thread becomes a recorded, intentional deferral
  with a defined seam, not a silent gap; the catalog schema is forward-compatible;
  we avoid a misleading fake; a real provider (or external entitlement mapping)
  can be added later without touching callers.
- **Negative / accepted:** v0.2 cannot truthfully claim licence enforcement; the
  north-star "licensed" scenario waits on the provider slice; the `licence:` block
  sits declared-but-inert (documented as such so it is not mistaken for enforced).
- **Open (for the RFC / provider slice):** licence-class taxonomy; provider
  backend; concurrency/expiry semantics; whether Plan-stage reservation is
  separate from Provision-stage assignment; external-entitlement mapping.
