# ADR-0009: 5-share Shamir, 3-of-5 threshold, distributed across 5 locations

**Status:** Accepted
**Date:** 2026-04-22 (rebuild session)
**Deciders:** @<handle>
**Amended:** 2026-11-17, for the sandbox lane only (see the amendment before Enforcement).

## Context

OpenBao seals on every pod restart. It needs to be unsealed by reassembling the
master key from a quorum of Shamir shares. The choice of how many shares,
where they live, and what threshold is required determines:

- How easy / hard it is to do routine unseal (post-pod-restart)
- How easy / hard it is to lose access (any of the locations going dark)
- How easy / hard it is for an attacker to compromise the master

Earlier design used a single combined keys file
(`openbao-keys.json` in the maintainer's secure store). It was fast but a
single point of compromise.

## Decision

**5 shares, 3-of-5 threshold**, distributed across 5 distinct locations:

| # | Location | Medium |
|---|---|---|
| 1 | `<secure-store>/openbao-breakglass/<env>/share-1.json` | Encrypted volume, synced off the workstation |
| 2 | `<secure-store>/openbao-breakglass/<env>/share-2.json` | Same encrypted volume |
| 3 | An entry in the workstation's OS keychain | OS keychain |
| 4 | `<removable-drive>/share-4.json` | Removable drive, kept offline |
| 5 | `<removable-drive>/share-5.json` | Same removable drive |

**Routine break-glass unseal** uses shares 1 + 2 + 3 (the "always available"
trio on a workstation with the encrypted volume mounted and the OS keychain
unlocked). Driven by
`dmf-env/bin/unseal-openbao.sh` (see `dmf-openbao-unseal` skill).

**Removable-drive shares 4 + 5** are held back for **re-init / rekey disasters**,
when the running OpenBao no longer matches the keys you have, or when rotating
share material. They are not part of the routine path.

A 3-share automation quorum is also written to
`<secure-store>/openbao-breakglass/<env>/openbao-keys-automation.json`
for the openbao role's auto-unseal during normal playbook runs.

## Consequences

- **Positive:** loss of any one location (drive lost, volume unmounted, keychain
  reset) doesn't lock you out. The 3 of 4 remaining still meet threshold.
- **Positive:** compromise of any one location doesn't reveal the master.
  Even compromise of any two doesn't.
- **Positive:** routine unseal (1+2+3) is fast and needs no removable drive.
- **Negative:** 5 locations to maintain. Periodic verification needed
  (`docs/plans/dmf-improvement-run-plan.md` §verify-shares).
- **Negative:** Removable-drive shares 4+5 are physical hardware. They degrade over
  time and can be lost. Backup discipline matters.
- **Negative:** if the volume's sync is misconfigured, shares 1+2 could end up in
  unintended cloud locations. Volume-level encryption is the mitigation.

### Amendment 2026-11-17 for the sandbox lane

The decision numbers are in the [Tier 2 operator unseal plan](../plans/operator-unlock-tier2-plan.md). In the sandbox lane, the recovery package holds the seal key as one copy in the administrator's custody, in place of five shares at a threshold of three (decisions 14 and 15). The package also holds the recovery keys, because its jobs of approving, checking in and enrolling need them (decisions 25 and 32). [ADR-0052](0052-sandbox-lane-tier3-variant.md) (Proposed) lists the contents for each job of the package. One custodian rests on the accepted local-root risk of this lane. A lane with a boot-time unseal keeps this ADR unchanged.

### Enforcement

`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml`
writes the shares to all 5 locations during init. `dmf-env/bin/unseal-openbao.sh`
reads from canonical paths only. The `dmf-openbao-unseal` skill is the
operator-facing interface; never improvise share handling outside it
(see ADR-0007).

## Status

Accepted
Amended 2026-11-17 for the sandbox lane: see the amendment before Enforcement.

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0009-shamir-dr-model.md).
