# ADR-0049: Managed service mode (`dmfdeploy.io`)

**Status:** Proposed
**Date:** 2026-05-11
**Deciders:** operator
**Rule:** The Mode B constraints are proposed reference text for any managed-service work. They bind no implementation today.

## Context

This ADR holds Mode B, which was split out of [ADR-0020](0020-deployment-scope-and-regulatory-posture.md) on 2026-11-06. In that ADR, Mode A (OSS self-host) is the Accepted decision. See that ADR for the three-mode framing.

## Decision

### Mode B: Managed service (`dmfdeploy.io`)

**Regulatory posture:** Full NIS2 *managed service provider* scope under
Annex I §8, governed by Implementing Reg. (EU) 2024/2690. GDPR Art. 28
processor obligations attach for customer-hub processing performed on a
customer's behalf; dmfdeploy.io remains controller for its own account,
billing, support, security-log, and vulnerability-intake processing.
ISO 27001 readiness is a customer-facing claim (Statement of
Applicability + Trust Package required). Schrems II analytic frame
applies to any third-country vendor in the stack (notably Aliyun,
regardless of region; see
[EDPB Recs 01/2020 v2.0](https://www.edpb.europa.eu/system/files/2021-06/edpb_recommendations_202001vo.2.0_supplementarymeasurestransferstools_en.pdf)).

The binding architectural constraints, B.1 to B.4, are in the [archive record](../archive/decisions/0049-managed-service-mode-dmfdeploy-io.md#binding-architectural-constraints).

### Enforcement

Discipline only: no script, test or workflow checks Mode B.

- **Mode B architectural constraints (B.1–B.4):** enforced by ADRs that
  follow once Mode B implementation starts. Until then, this ADR is the
  authoritative reference. No code in `dmf-central` or the umbrella may
  contradict B.1–B.4 without superseding this ADR. The first Mode B
  implementation ADR must explicitly close the ADR-0011 auto-unseal
  gap and include a GDPR controller/processor role matrix.

## Status

Proposed

Promote from **Proposed** → **Accepted** when:

1. The OSS-vs-managed boundary (B.4) has been confirmed by the operator
   as the chosen pattern (alternatives explicitly rejected in the [archive record](../archive/decisions/0049-managed-service-mode-dmfdeploy-io.md#alternatives-considered)).
2. The cluster-per-tenant constraint (B.3) has survived a unit-economics
   sanity check.
3. The ADR-0011 auto-unseal tradeoff has a named Mode B exit path
   (HA OpenBao, customer-side ceremony, or another design that keeps
   Shamir quorum material outside dmfdeploy.io custody).
4. The GDPR role split has a first-pass matrix: dmfdeploy.io as
   processor for customer-hub data and controller for its own account,
   billing, support, security-log, and vulnerability-intake data.

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0049-managed-service-mode-dmfdeploy-io.md).
