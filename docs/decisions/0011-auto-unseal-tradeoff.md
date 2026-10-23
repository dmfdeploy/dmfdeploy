# ADR-0011: Auto-unseal trades Shamir defense-in-depth for operational tolerability

> **⚠️ Canonical truth for this topic is in
> [ADR-0029](0029-tiered-unseal-posture.md).** This ADR's status: reframed as "Tier 3, explicitly chosen" by **ADR-0029**; AWS-KMS variant adopted in **ADR-0031**.
> Full text is preserved in the [archive record](../archive/decisions/0011-auto-unseal-tradeoff.md) for decision
> history. Do not act on it without reading the canonical ADR and the named successor.

**Status:** Accepted (with explicit known tradeoff)
**Date:** 2026-05-03
**Deciders:** @<handle>
**Amended:** 2026-05-30: reframed as "Tier 3" by [ADR-0029](0029-tiered-unseal-posture.md); cloud-KMS reconciliation with [ADR-0031](0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md) recorded; stale revisit-triggers refreshed. See §Amendment 2026-05-30.
**Reframed by:** [ADR-0029](0029-tiered-unseal-posture.md) (this ADR remains the *operative* description of the live single-replica posture until the HA-bao-+-raft baseline lands)

## Context

OpenBao is currently deployed as a **single-replica StatefulSet** (`openbao-0`), so every pod restart seals the bao. The ADR-0009 5-share Shamir scheme (3-of-5) and the restart frequency are described in the [archive record](../archive/decisions/0011-auto-unseal-tradeoff.md).

To make this tolerable, the openbao Ansible role writes a file `<secure-store>/openbao-breakglass/<env>/openbao-keys-automation.json` containing **the first 3 unseal shares + root token + ops_admin userpass**, and auto-feeds those shares to bao on routine playbook runs.

This file collapses the Shamir threshold from 3-of-5 to **1-of-1 against compromise of the operator Mac.** Anyone who reads it has full bao compromise. The 5-share distribution defends the *manual breakglass path* but provides **zero protection** for the auto-unseal path. There is currently no other location where 3 shares sit pre-assembled.

## Decision

**Accept the tradeoff for the duration of the experiment phase (per ADR-0004).** Document it explicitly here so the architecture is not misread as "we have Shamir, therefore single-Mac compromise is bounded." It is not bounded.

The current security posture is honestly stated as:

- **Shamir distribution defends:** the manual breakglass path (`bin/unseal-openbao.sh`), used when the automation file is missing, corrupted, or the operator deliberately wants the 3-source quorum.
- **Shamir does NOT defend:** routine pod restarts. For routine restarts, bao security reduces to "is the operator's workstation uncompromised?" (disk encryption, volume encryption, the user account's process integrity).

Conditions for revisiting (any one of these triggers a re-evaluation, which may or may not lead to a change):

1. An external collaborator joins and gains read access to `<secure-store>/`
2. The repo goes public (OSS goal iii). Outside readers should see a security posture that holds up to scrutiny
3. A Mac-compromise scare or actual incident
4. Move 2 lands and the post-experiment hardening pass begins
5. A bao HA migration becomes operationally feasible

The next-state target, when one of those conditions triggers, is **HA bao**: 3 replicas in raft mode, manual initial-boot unseal only, automation file deleted. Sketched in the [archive record](../archive/decisions/0011-auto-unseal-tradeoff.md#alternatives-considered); full plan to be drafted at that time.

### Amendment 2026-05-30

Recorded to close two drift gaps the 2026-05-27 portfolio review flagged (contradiction §2.1, staleness §3); **reopens no decision**: the live posture is unchanged.

- **Reframed as Tier 3 (ADR-0029).** The tiered-unseal posture ADR names this single-replica auto-unseal arrangement as **"Tier 3: explicitly chosen, warned, audited"** (sub-variant 3b, cluster-resident wrapped blob). The weakness recorded below is not retracted. It is *relabelled* as a deliberate tier choice rather than a silent gap. This ADR stays the operative description of today's cluster until the HA-bao-+-raft baseline (deferred) lands; ADR-0029 is directional.
- **Cloud-KMS reconciliation (ADR-0031).** The archive record's [Alternatives C](../archive/decisions/0011-auto-unseal-tradeoff.md#alternatives-considered) calls cloud-KMS auto-unseal a "philosophical mismatch with a local-first lab." [ADR-0031](0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md) makes **AWS-KMS auto-unseal the release-default boot posture for the AWS profile** (= ADR-0029 Tier 3 sub-variant 3a, the most defensible auto-unseal form). The Alternatives C verdict is therefore **scoped to the local-first lab**. Cloud-first profiles adopt KMS by design.
- **Trigger refresh.** Of the §Decision revisit triggers: **#2 ("repo goes public") is now actively firing** via ADR-0031 (OSS v0.1), so outside readers do see this posture, which is exactly why ADR-0029 names it explicitly. **#4's "Move 2 lands" is retired vocabulary**; post-experiment hardening is now tracked per release-profile (ADR-0031) and via the tiered framework (ADR-0029).

## Consequences

- **Positive:** the architecture's security claims are now *honest*. No one reads ADR-0009 and concludes "5-share Shamir defends all bao compromise paths"; they read this ADR alongside it and see the gap.
- **Positive:** routine cluster operations (pod restarts, node drains) proceed unattended. Aligns with experiment-phase priorities (ADR-0004); unattended-DR-drill is a useful capability *during* experimentation.
- **Negative:** real security weakness exists. A compromise of the operator Mac yields the bao master, and through it, every secret consumed by every app. This includes Hetzner / Cloudflare / Tailscale provider tokens, all app admin passwords, AWX/NetBox/Forgejo API tokens, OIDC client secrets.
- **Negative:** "we have Shamir" is the kind of architecture claim that invites cargo-cult adoption. Public-facing materials must not over-claim.
- **Neutral:** the 5-share scheme is still useful: the breakglass path is fully redundant with the automation file, so a corrupted automation file does not produce a permanently locked bao. In the auto-unseal scenario it is defense-in-depth for *availability*. It is not defense-in-depth for *confidentiality*.

### Enforcement

discipline only: no script or check enforces this ADR. It keeps the architecture's actual security posture documented honestly, so future agents and collaborators reading `docs/decisions/` see both ADR-0009 (Shamir model) and this ADR (where Shamir doesn't defend) and aren't misled. When any of the §Decision triggers fires, an engineering plan to migrate to option A (HA bao) should be opened. That plan supersedes this ADR.

## Status

Accepted (with explicit known tradeoff)

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0011-auto-unseal-tradeoff.md).
