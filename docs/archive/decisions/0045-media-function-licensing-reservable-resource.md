# ADR-0045 archive: Media function licensing is a reservable resource behind a provider seam; declared-but-not-enforced until a real provider exists

This file holds material moved out of [ADR-0045](../../decisions/0045-media-function-licensing-reservable-resource.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

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

## Context — EBU whitepaper background (moved from the ADR)

The EBU Dynamic Media Facility model treats **media-function licences as a
reservable resource**, on the same footing as compute/network/storage. The
whitepaper (pp. 3–4): **Plan** *"reserve … resources … and set up authorisations
for their access"*; **Operate** changes are *"limited to available resources
(compute, **licences**, connectivity, storage)"*; **Finalise** *"delete … Media
Functions, authorisations and reservations."* The orchestration figure's MEDIA
FUNCTIONS row spells out the lifecycle: **Ensure Licence Availability** (Plan) →
**Assign Licences** (Provision) → **Release Licences** (Finalise) → **Monitor
Licence Usage** (Monitor) → **Authorise/Audit Workload Usage** (Security).
