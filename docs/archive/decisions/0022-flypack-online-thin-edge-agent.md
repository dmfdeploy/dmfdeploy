# ADR-0022 archive: Flypack-online profile is a thin local edge agent paired to a cloud DMF hub

This file holds material moved out of [ADR-0022](../../decisions/0022-flypack-online-thin-edge-agent.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Sovereign-with-hub** (round-1 decision #2 in the wizard survey).
  Defined flypack-online as a peer holding its own identity/secrets
  with telemetry/config sync to a hub. Rejected because (a) it
  duplicated the offline-lane spec at higher operational cost, (b) the
  operator's clarified intent is a thin edge, not a federated peer,
  and (c) OpenBao OSS does not provide Vault Enterprise-style
  performance-replica federation, so embedded-secrets-with-sync was
  non-trivial to build. **Superseded by this ADR.**

- **Thick mirror at the edge** — full DMF stack at the edge plus
  bidirectional sync to hub. Rejected because the resource envelope
  at edge sites (RPi-class to 1U mini-server class) does not
  accommodate a full stack, and because bidirectional sync of
  OpenBao + Authentik + NetBox + AWX is an entire research project.

- **Drop flypack-online entirely** — support only `cloud` and
  `flypack-offline`. Rejected because the broadcast-facility use case
  the operator described (local provisioning, local L2 control,
  local boot-image caching, local data plane) is real and served by
  neither of the other two profiles. Cloud is too far for L2;
  flypack-offline is too thick for low-touch edge sites.
