# Secrets and unseal — Canonical Digest

**Scope:** How secrets are stored, distributed, and how OpenBao is unsealed across the DMF Platform.
**Canonical ADR(s):** [ADR-0029](../0029-tiered-unseal-posture.md), [ADR-0009](../0009-shamir-dr-model.md)
**Last refreshed:** 2026-06-09

> This digest states the **current consolidated truth** for this topic so a reader
> does not have to reverse-engineer it from multiple partially-superseding ADRs.
> The numbered ADRs remain authoritative source; this digest points at them.

## Current truth

- OpenBao uses a 5-share Shamir scheme with a 3-of-5 threshold, distributed across 5 locations: JuiceFS (shares 1+2), macOS Keychain (share 3), USB stick (shares 4+5). Routine break-glass unseal uses shares 1+2+3. USB shares 4+5 are held back for re-init/rekey disasters. (ADR-0009 Decision)
- A 3-share automation quorum is written to `openbao-keys-automation.json` for the openbao role's auto-unseal during normal playbook runs. (ADR-0009 Decision)
- A three-tier unseal posture is adopted, declared at deploy time: Tier 1 (Quorum unseal — ≥3 humans × ≥3 attested devices), Tier 2 (Operator unseal — 1 phone × 1 biometric), Tier 3 (Self-recovering — cluster auto-unseals on boot). HA bao + raft is the universal baseline for all tiers. (ADR-0029 Decision)
- The existing single-replica auto-unseal arrangement is **Tier 3** (sub-variant 3b, cluster-resident wrapped blob); cloud-KMS auto-unseal (AWS profile per ADR-0031) is sub-variant 3a. (ADR-0029 Decision)
- Mandatory guardrails (all tiers): per-cold-boot one-time token, tier-downgrade protection (cryptographically checked at boot), hard rate-limiting + audit-per-submission on the kiosk, no useless factor-stacking. (ADR-0029 Decision)
- Cluster-runtime secrets live in OpenBao; pods consume them via External Secrets Operator (ESO), which authenticates to OpenBao via an AppRole role+secret pair. (ADR-0008 Decision)
- Operator-side scripts generate ephemeral seed secrets at first bootstrap; the wrapper writes a temp vars file and injects it into Ansible, then cleans up. No `community.hashi_vault` runtime dependency. (ADR-0008 Decision)
- Break-glass material (Shamir shares, ops_admin userpass) lives outside the runtime path. (ADR-0008 Decision)
- The live cluster runs the ADR-0011 single-replica auto-unseal reality. Until HA raft lands, the tiers are not selectable — this ADR is directional. (ADR-0029 §Context warning)
- ADR-0011's auto-unseal tradeoff is honestly documented: Shamir defends the manual breakglass path but does NOT defend routine pod restarts, where bao security reduces to "is the operator's Mac uncompromised?" (ADR-0011 Decision)
- ADR-0011's §Alternatives C rejection of cloud-KMS is scoped to the local-first lab; cloud-first profiles (AWS per ADR-0031) adopt KMS by design. (ADR-0011 Amendment 2026-05-30)

## History / context behind it

| ADR | Role today | Superseded / amended by |
|---|---|---|
| 0008 | OpenBao + ESO + AppRole shim secrets architecture | — |
| 0009 | 5-share Shamir, 3-of-5 threshold, distributed across 5 locations | — |
| 0011 | Auto-unseal tradeoff (experiment-phase acceptance) | **Reframed as Tier 3 by ADR-0029**; cloud-KMS reconciliation with ADR-0031 |
| 0029 | Tiered Unseal Posture (Accepted posture; implementation deferred) | — |
| 0031 | OSS v0.1 release-profile matrix (AWS-KMS = Tier 3 sub-variant 3a) | — |

## Open items in this cluster

- HA-bao-+-raft migration and kiosk + passkey/PRF/QR implementation are **deferred** (ADR-0029 Scope). The live posture remains Tier 3 (ADR-0011 auto-unseal) until the raft baseline lands.
