# ADR-0052: Sandbox lane Tier 3 variant

**Status:** Proposed
**Date:** 2026-11-17
**Deciders:** operator
**Amends:** [ADR-0029](0029-tiered-unseal-posture.md) and [ADR-0009](0009-shamir-dr-model.md), for the sandbox lane only.
**Rule:** Declare the sandbox lane as Tier 3 and never describe it as Tier 2; keep every recovery key off the node except as a copy encrypted for one enrolled passkey; keep the seal key's backups, the recovery package and the snapshot downloads as this ADR specifies.

## Context

The sandbox lane auto-unseals on every boot, with no administrator action, and with no time window. Under ADR-0029 that is Tier 3 (decision 12). The lane still needs a root token and a restore without physical access to the node, so it needs recovery material that stays off the node. The RFC thread is [Discussion #865](https://github.com/orgs/dmfdeploy/discussions/865). The decisions cited below are numbered in the [Tier 2 operator unseal plan](../plans/operator-unlock-tier2-plan.md). Physical and local root access to the node is a known, accepted risk in this lane. Lanes with legal or regulatory duties need their own decision.

## Decision

The sandbox lane is a named sub-variant of Tier 3 with these properties.

- The declared posture equals the actual one (decision 12).
- The auto-unseal seal is OpenBao's Static Key seal (decision 43). That choice holds once the seal rehearsal on the pinned OpenBao version passes. Recovery keys are separate from the seal key (decision 13).
- The server stores one copy of the recovery keys and the seal key for each enrolled passkey, encrypted for that passkey. One passkey meets the threshold alone. The administrator enrols at least two independent passkeys (decisions 14, 21 and 26). Two passkeys in one sync account are not independent (decision 40).
- Recovery keys cannot unseal, so the seal key has its own backup: the per-passkey copies, stored on the server with the Raft snapshots, and a direct copy in the recovery package (decisions 15 and 21).
- The unseal is a system action under ADR-0028. Each approval carries the enrolled administrator as actor.
- Synced passkeys are the default. A takeover of the passkey sync account is a remote risk that the accepted local-root risk does not cover. The limits are encrypted copies on access-controlled storage, unseal surfaces and approval surfaces on the private network only, and an audit record of every use (decision 18).

### Recovery package

dmf-init writes the package at the end of the install, after the seal transition, and again whenever it changes the keys (decision 32). The package holds the recovery keys, the seal key, the OpenBao snapshot saved with it, the environment backup that dmf-init already packages, and the private key that opens every snapshot download. It holds no root token and no passkey material. The dmf-init passphrase encrypts all of it. The administrator keeps the passphrase apart from the package. Whoever holds both holds everything, which is the accepted single-administrator risk of this lane.

| Job | The package must hold | Required outcome |
|---|---|---|
| Restore | The seal key, the saved snapshot and the download private key (decisions 32 and 33) | With no passkey, the restore completes from the saved snapshot and from a later download. |
| Approve | The recovery keys, which meet the threshold alone (decision 32) | With no passkey, the recovery keys complete one approval. The executor's own login is still required. |
| Check in | The recovery keys (decision 32) | After expiry and with no passkey, a check-in succeeds. How the package authenticates it is open. |
| Enrol | The recovery keys and the seal key (decision 32) | With no passkey, the package enrols a new one, and that passkey then approves. How the package authenticates it is open. |

The authentication of a check-in and of an enrolment by the package is open. The design must not accept an unauthenticated claim of possession (decision 25).

### Snapshot downloads

The console builds one versioned download at a time (decision 33). It holds a fresh snapshot, the encrypted copies that match it, a copy of the audit record, the identifier of the seal key it needs, and a manifest with digests. The download is encrypted and authenticated with public-key encryption, so building it needs no passkey assertion. Its recipients are the enrolled passkeys and a recovery key pair whose private key is in the package. A download needs the operator role and writes an audit line.

The off-server copy can lag the latest snapshot or a key change, and a restore recovers the state of that download. The console shows the time of the last download and warns when the server holds a change that no download carries. A warning cannot prove that the off-server copy is current, so the off-server copy holds only as far as the administrator keeps up (decisions 27 and 33).

## Consequences

- Gain: one administrator approves a root token or a restore from one device. Material on the node cannot mint a root token.
- Cost: the seal key rests on the node, and the lane does not suit regulated use. A stale download loses recent state.
- Unchanged: a lane with a boot-time unseal keeps ADR-0029 and ADR-0009 as written.

### Enforcement

Each property names the package that adds its mechanism. None exists yet.

- For the declared tier and the seal, the unseal-page package (WP5) adds a boot-time check that compares the declared tier with the configured seal and refuses a mismatch.
- For the seal transition, the backups and the package rewrite, the seal-transition package (WP4) rehearses each step and checks the package copy.
- For two independent passkeys and the copies, the enrolment package (WP6) refuses an install with fewer than two, and it records the synced-passkey notice.
- For the audit actor and the root token rule, the audit package (WP9) writes the records, and WP5 creates no root token without its record.
- For a check-in by the package, the check-in package (WP8) records the authentication design.
- For restore and snapshot downloads, the restore package (WP10) rehearses a restore from a real download and from the package.

Discipline only: the administrator keeps the passphrase apart from the package, and keeps downloads current. No check can prove either.

## Status

Proposed
