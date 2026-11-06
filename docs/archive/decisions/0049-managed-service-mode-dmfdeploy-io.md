# ADR-0049 archive: Managed service mode (`dmfdeploy.io`)

This companion record holds the full text that ADR-0049 links to: the Mode B constraint list and promotion gate, which are the authoritative reference text for Mode B (Proposed; they bind no implementation today), and the Mode B amendment text, alternatives and consequences. Change it together with ADR-0049.

## Binding architectural constraints

**Binding architectural constraints:**

1. **Shamir shares originate customer-side and never traverse dmfdeploy.io.**
   The control plane orchestrates; the customer holds the unseal quorum
   from second 1. Sigstore-style "dmfdeploy.io signs, customer verifies"
   pattern for image and config provenance. This is the dividing line
   between "we are a data processor" and "we are a software supplier."
   This constraint is incompatible with the experiment-phase
   auto-unseal tradeoff accepted in
   [ADR-0011](../../decisions/0011-auto-unseal-tradeoff.md), where an operator-local
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

## Amendment 2026-05-23: Mode B remains Proposed

- **Mode B (managed `dmfdeploy.io`) remains Proposed.** The B.1–B.4
  architectural constraints stand as the authoritative reference for any
  future managed-service work, but no Mode B work is in flight and no
  ship date is committed. Promotion is gated on the original Status
  criteria 1–4 and on a concrete managed-service driver (paying customer pilot,
  funded contract, or explicit dmfdeploy.io GmbH formation).

## Alternatives considered

Each was rejected:

- **Open-core (managed features in a private repo):** it creates an "are you
  really OSS?" conversation we do not need at v0.1.0. External-service-gated
  managed features (B.4) replace it.
- **Multi-tenant shared cluster for Mode B:** it has better unit economics but
  worse compliance blast-radius, and it is incompatible with the existing
  Authentik-per-cluster / `dmf-central` posture.

## Consequences

- **Negative**
  - The cluster-per-tenant decision (B.3) commits us to higher
    per-tenant cost than a multi-tenant SaaS would. This is a
    deliberate trade for clean compliance blast-radius and is binding.
  - Mode B and Mode C *require* compliance work to ship, and cannot be
    deferred indefinitely the way Mode A can.
  - Mode B requires retiring or superseding the ADR-0011 auto-unseal
    tradeoff for customer hubs. The current experiment-phase automation
    quorum must not become a managed-service security claim.
