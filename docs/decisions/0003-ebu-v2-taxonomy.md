# ADR-0003: EBU DMF V2.0 layer/vertical/lifecycle taxonomy

**Status:** Accepted
**Date:** 2026-04-25 (vocabulary aligned with EBU White Paper V2.0)
**Deciders:** @<handle>

## Context

The platform's playbooks were originally numbered with an ad-hoc "phase"
scheme (`50-authentik`, `phase5-identity.yml`). The EBU's *Dynamic Media
Facility Reference Architecture White Paper V2.0* (2026-04-15) defines a
canonical structure for media facilities; aligning vocabulary lets the platform
slot into industry conversations and gives external readers a familiar map.

## Decision

All playbooks, roles, and docs use the EBU V2.0 taxonomy:

- **6 horizontal layers:** 1 Infrastructure, 2 Host Platform, 3 Container
  Platform, 4 Media Exchange, 5 Media Functions, 6 Application & UI
- **4 cross-cutting verticals:** Orchestration, Control, Monitoring, Security
- **6 lifecycle stages:** Design, Plan, Provision, Configure, Operate, Finalise

Playbook numbering encodes layer + lifecycle:
`200-baseline.yml` (Layer 2 / Provision), `300-k3s.yml` (Layer 3),
`vertical-security/100-openbao.yml`, `lifecycle-provision.yml`, etc.

Canonical map: `dmfdeploy/docs/architecture/DMF EBU Mapping (2026-04-25).md`.

## Consequences

- **Positive:** new playbooks have an obvious home. The numbering scheme is
  self-explanatory once you know the EBU map. External readers (employers,
  OSS users) can locate themselves.
- **Positive:** taxonomy is a forcing function — when a playbook genuinely spans
  two layers/verticals, that's a signal that one of *them* needs splitting, not
  that the taxonomy is wrong (mostly).
- **Negative:** the taxonomy is itself one of the three thesis-killer risks
  (per ADR-0004 / strategic review). It survives every existing playbook
  because they were written with it in mind. The first genuinely-spanning
  workload will test it.
- **Negative:** playbook renames break old references; one-time pain.

## Alternatives considered

- **Keep ad-hoc phase numbering.** Loses the credibility/OSS leverage of EBU
  alignment.
- **Adopt only the layer scheme, not verticals.** The verticals are where
  cross-cutting concerns live (security, monitoring); without them, those
  concerns end up scattered. Adopting half is worse than adopting all.

## Enforcement

`dmfdeploy/docs/architecture/DMF EBU Mapping (2026-04-25).md` is the canonical
map. The renumbering plan (`docs/plans/DMF Orchestrator and Renumbering Plan
2026-04-22.md`) is DONE. New playbooks must fit the map; if they don't, treat
that as a smell and either split the playbook or update the ADR.
