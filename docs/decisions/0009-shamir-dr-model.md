# ADR-0009: 5-share Shamir, 3-of-5 threshold, distributed across 5 locations

**Status:** Accepted
**Date:** 2026-04-22 (rebuild session)
**Deciders:** @<handle>

## Context

OpenBao seals on every pod restart. It needs to be unsealed by reassembling the
master key from a quorum of Shamir shares. The choice of how many shares,
where they live, and what threshold is required determines:

- How easy / hard it is to do routine unseal (post-pod-restart)
- How easy / hard it is to lose access (any of the locations going dark)
- How easy / hard it is for an attacker to compromise the master

Earlier design used a single combined keys file
(`~/secure/openbao-breakglass/hetzner-lab/openbao-keys.json`) — fast but a
single point of compromise.

## Decision

**5 shares, 3-of-5 threshold**, distributed across 5 distinct locations:

| # | Location | Medium |
|---|---|---|
| 1 | `<secure-store>/openbao-breakglass/hetzner-lab/share-1.json` | JuiceFS (cloud-synced encrypted volume) |
| 2 | `<secure-store>/openbao-breakglass/hetzner-lab/share-2.json` | JuiceFS |
| 3 | macOS Keychain `service=openbao-breakglass-share-3, account=share` | OS keychain |
| 4 | `/Volumes/OPENBAO_A/share-4.json` | USB stick (ExFAT, labeled `OPENBAO_A`) |
| 5 | `/Volumes/OPENBAO_A/share-5.json` | Same USB |

**Routine break-glass unseal** uses shares 1 + 2 + 3 (the "always available"
trio for a Mac with JuiceFS + login keychain). Driven by
`dmf-env/bin/unseal-openbao.sh` (see `dmf-openbao-unseal` skill).

**USB shares 4 + 5** are held back for **re-init / rekey disasters** — when
the running OpenBao no longer matches the keys you have, or when rotating
share material. They are not part of the routine path.

A 3-share automation quorum is also written to
`<secure-store>/openbao-breakglass/hetzner-lab/openbao-keys-automation.json`
for the openbao role's auto-unseal during normal playbook runs.

## Consequences

- **Positive:** loss of any one location (USB lost, JuiceFS unmounted, keychain
  reset) doesn't lock you out — 3 of 4 remaining still meet threshold.
- **Positive:** compromise of any one location doesn't reveal the master.
  Even compromise of any two doesn't.
- **Positive:** routine unseal (1+2+3) is fast — no USB plug required.
- **Negative:** 5 locations to maintain. Periodic verification needed
  (`docs/plans/DMF Improvement Run Plan 2026-04-22.md` §verify-shares).
- **Negative:** USB-based shares 4+5 are physical hardware — degrade over
  time, can be lost. Backup discipline matters.
- **Negative:** if JuiceFS sync is misconfigured, shares 1+2 could end up in
  unintended cloud locations. Volume-level encryption is the mitigation.

## Alternatives considered

- **3-share, 2-of-3.** Smaller threshold, less resilience to share loss. Less
  defense-in-depth.
- **Single key (no Shamir).** Simpler ops, single point of compromise. Rejected.
- **Cloud KMS auto-unseal.** Trades local-only security for cloud-vendor trust.
  For an experiment-phase lab where the operator IS the security boundary,
  Shamir is more appropriate.

## Enforcement

`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml`
writes the shares to all 5 locations during init. `bin/unseal-openbao.sh`
reads from canonical paths only. The `dmf-openbao-unseal` skill is the
operator-facing interface; never improvise share handling outside it
(see ADR-0007).
