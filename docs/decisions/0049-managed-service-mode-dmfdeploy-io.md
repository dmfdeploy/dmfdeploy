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

**Binding architectural constraints:**

1. **Shamir shares originate customer-side and never traverse dmfdeploy.io.**
   The control plane orchestrates; the customer holds the unseal quorum
   from second 1. Sigstore-style "dmfdeploy.io signs, customer verifies"
   pattern for image and config provenance. This is the dividing line
   between "we are a data processor" and "we are a software supplier."
   This constraint is incompatible with the experiment-phase
   auto-unseal tradeoff accepted in
   [ADR-0011](0011-auto-unseal-tradeoff.md), where an operator-local
   automation file holds a Shamir quorum. Before Mode B ships, that
   automation-quorum path must be removed or replaced for customer hubs
   (for example by HA OpenBao with manual initial unseal, or by a
   customer-side unseal ceremony whose share material never reaches
   dmfdeploy.io systems or agent transcripts).
2. **No long-lived customer cloud credentials at rest in dmfdeploy.io.**
   Use OIDC/workload-identity federation where the provider supports it
   (for example AWS IAM Roles Anywhere or GCP Workload Identity).
   Provider-specific bootstrap mechanisms such as Hetzner cloud-init
   seed are not federation. They are acceptable only when customer-side,
   ephemeral, and documented as a non-federated bootstrap path.
   Providers without federation (Aliyun, small clouds) are handled
   out-of-band via the customer's own credential vault and logged as
   residual risk in their TIA.
3. **Each tenant gets its own cluster.** Mode B has no multi-tenant shared
   cluster. This inherits from the existing Authentik-per-cluster +
   `dmf-central` scaffold posture. Wrong for unit economics; right for
   compliance blast-radius and is the binding constraint that lets us
   answer customer auditors honestly.
4. **External-service gating enforces the OSS / managed boundary.** Feature
   flags do not. Managed features (multi-tenant billing,
   hub-orchestration UI, support-portal hooks) require an API key from
   dmfdeploy.io to function; they may live in the public OSS repos as
   "dormant" code but provide no value without the managed API. Avoids
   the open-core fragmentation and the feature-flag-flip risk.

### Amendment 2026-05-23: Mode B remains Proposed

- **Mode B (managed `dmfdeploy.io`) remains Proposed.** The B.1–B.4
  architectural constraints stand as the authoritative reference for any
  future managed-service work, but no Mode B work is in flight and no
  ship date is committed. Promotion is gated on the original Status
  criteria 1–4 and on a concrete managed-service driver (paying customer pilot,
  funded contract, or explicit dmfdeploy.io GmbH formation).

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

Promote from **Proposed** → **Accepted** when the criteria below hold and the concrete managed-service driver that the 2026-05-23 amendment above requires exists:

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
