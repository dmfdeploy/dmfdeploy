# ADR-0049 archive: Managed service mode (`dmfdeploy.io`)

This file holds material moved out of [ADR-0049](../../decisions/0049-managed-service-mode-dmfdeploy-io.md), which took it from ADR-0020 when Mode B was split out. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

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
