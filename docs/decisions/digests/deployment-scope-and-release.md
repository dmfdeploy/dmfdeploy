# Deployment scope and release — Canonical Digest

**Scope:** What deployment modes the DMF Platform supports and what the OSS v0.1 release claims.
**Canonical ADR(s):** [ADR-0031](../0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md)
**Last refreshed:** 2026-06-09

> This digest states the **current consolidated truth** for this topic so a reader
> does not have to reverse-engineer it from multiple partially-superseding ADRs.
> The numbered ADRs remain authoritative source; this digest points at them.

## Current truth

- DMF OSS v0.1 ships as a release-profile matrix organized around one canonical workflow contract with two named provisioning lanes and an explicit lab/reference profile that is not a release. (ADR-0031 Decision)
- Every v0.1 release profile must support the nine-step canonical workflow contract: clone, provide manifest, provision, bootstrap k3s, log in as seeded admin, deploy reference catalog item, verify, rerun idempotently, teardown. (ADR-0031 "Canonical workflow contract")
- Profile 1 — `sandbox-single-node` (v0.1 release gate): one ARM64 Debian host, no required dependence on Cloudflare/B2/Hetzner/Tailscale/external Headscale/public ntfy.sh/operator Mac, local CA + `.test` domain, locally generated bootstrap material. v0.1 cannot be tagged unless this profile passes. (ADR-0031 Decision)
- Profile 2 — `aws-arm64-multi-node` (secondary lane, eligible-if-ready): ARM64 EC2 Graviton, Route53, S3, SNS, AWS KMS for OpenBao auto-unseal, in-cluster Headscale + ntfy. Eligible for v0.1 only if it catches up without delaying sandbox. (ADR-0031 Decision)
- Profile 3 — `g2r6-foa9` and successors (live lab / regression reference): explicitly not a release profile; allowed to depend on operator-specific credentials. (ADR-0031 Decision)
- v0.1 explicitly does NOT claim: production ST-2110/PTP/multicast correctness, real-time media plant behavior, multi-tenant/Mode B posture, enterprise RBAC, geographic redundancy, or performance numbers. (ADR-0031 "What v0.1 says and does not say")
- The platform stays on self-managed k3s for every environment regardless of cloud provider. We do not adopt managed Kubernetes (ACK, EKS, GKE, AKS). (ADR-0018 Decision)
- DMF ships in three explicitly-named modes: Mode A (OSS self-host, no attestation claimed, no dependency on dmfdeploy.io), Mode B (managed dmfdeploy.io, NIS2 MSP scope, GDPR Art. 28, cluster-per-tenant), Mode C (flypack, Mode B obligations plus physical-media controls). Mode A is Accepted; Modes B and C remain Proposed. (ADR-0020 Decision + Amendment 2026-05-23)
- No public-repo manifest, default, or Helm value may add a runtime dependency on `dmfdeploy.io`-resident services without superseding ADR-0020's Mode A constraint. (ADR-0020 Amendment 2026-05-23)
- `flypack-online` is a thin local edge agent paired to a cloud DMF hub (hub-paired, WAN-dependent, no local OpenBao/Authentik on the edge). `flypack-offline` runs the full DMF stack locally with no cloud dependency. (ADR-0022 Decision)
- Provider Descriptors are declarative YAML manifests at `dmf-infra/k3s-lab-bootstrap/providers/<id>.yaml`, one per provider, declaring inputs, secrets, group_vars, and roles. Status: Proposed. (ADR-0026 Decision)
- Common gates for every release profile: fresh install from public docs, no maintainer-specific credentials, linux/arm64 image availability, seeded admin login via passkey (ADR-0015), reference catalog item deploys, idempotent rerun, teardown tested, no hardcoded operator paths. (ADR-0031 "Common gates")

## History / context behind it

| ADR | Role today | Superseded / amended by |
|---|---|---|
| 0004 | Experiment phase, not hardening | **Stance superseded for committed core by architectural-commitments-v1** (2026-06-04); still describes reserved post-v0.1 experiments |
| 0018 | Self-managed k3s on every cloud, not managed Kubernetes | — |
| 0020 | Three deployment modes (A Accepted, B/C Proposed) | — |
| 0022 | Flypack-online as thin edge agent (Proposed) | — |
| 0026 | Provider Descriptors (Proposed) | — |
| 0031 | OSS v0.1 release-profile matrix (Accepted) | — |

## Open items in this cluster

- ADR-0020 Mode B (managed dmfdeploy.io) and Mode C (flypack) remain Proposed until a concrete driver appears (paying customer pilot, funded contract, or flypack partner).
- ADR-0022 (flypack-online) is Proposed; promotion requires wizard v2, per-edge AppRole rotation runbook, and first end-to-end site pairing.
- ADR-0026 (Provider Descriptors) is Proposed; promotion requires pydantic loader in wizard-spike, live env rendering, and a second descriptor without schema mutation.
