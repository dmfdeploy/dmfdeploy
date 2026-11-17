# ADR-0029: Tiered Unseal Posture for OSS deployment

**Status:** Accepted (framework/posture only: implementation deferred)
**Date:** 2026-05-30
**Deciders:** @<handle> (operator). Distilled from the 2026-05-24 design session (operator + claude-bottom); promoted from plan to ADR on 2026-05-30 at operator request to close the reserved-0029 numbering gap.
**Reframes (does not yet supersede):** [ADR-0011](0011-auto-unseal-tradeoff.md)
**Concretizes:** [ADR-0028](0028-identity-and-authority-chain.md) D1/C2 (OpenBao custody) per declared tier.
**Orthogonal to:** [ADR-0009](0009-shamir-dr-model.md) (5-share Shamir remains the disaster-recovery custody layer for all tiers, except in the sandbox lane, as ADR-0009's amendment states); [ADR-0020](0020-deployment-scope-and-regulatory-posture.md) (deployment-scope axis is independent of this security-posture axis).
**Amended:** 2026-11-17, for the sandbox lane (see Amendments). The proposed sandbox-lane variant is [ADR-0052](0052-sandbox-lane-tier3-variant.md).
**Source plan:** `docs/plans/dmf-unseal-posture-tiered-framework-plan.md` (full design rationale, threat trees, and the passkey/PRF/QR transport design).

**Rule:** Declare the unseal tier at deploy time, bind it in signed git-tracked config, and refuse to run below it; lower it only through an explicit, signed, audited change.

## Context

OpenBao starts **sealed** after any restart. Today's single-replica lab seals it several times a week, and the only unseal paths need the operator's workstation, encrypted volume, OS keychain and Tailscale reachability. ADR-0009 declares 3-of-5 Shamir defense, while ADR-0011 records that the routine path collapses to 1-of-1 (the automation file). This ADR names the posture explicitly and per deployment.

> **Warning: this is a directional posture and an unavailable menu. Read this first.** Every tier below is defined on top of an HA-bao-plus-raft baseline, and that baseline is **not yet implemented** (deferred per the 2026-05-25 operator decision; see Scope). Until raft lands, the tiers are **not selectable**. The live cluster runs the ADR-0011 single-replica auto-unseal reality. The value of this ADR today is narrow but real: it makes ADR-0011's auto-unseal legible as an explicitly chosen, warned and audited **Tier 3** instead of a silent confidentiality weakness, and it fixes the vocabulary so future hardening has a target. Do not read the tier table as a posture you can pick right now. The sandbox lane is the one exception to the Raft baseline: the amendments allow it one server. Until its seal transition is built, it runs the ADR-0011 auto-unseal as Tier 3. [ADR-0052](0052-sandbox-lane-tier3-variant.md) (Proposed) describes the variant it is to move to.

## Decision

Adopt a **three-tier unseal posture**, declared at deploy time, as the framework the platform's unseal story is organized around. **HA bao + raft is the universal baseline** for all tiers (it eliminates routine pod-restart pain independent of cold-boot posture), except in the sandbox lane, which runs one server (see Amendments). A cluster-resident **unseal kiosk** (a Traefik-served app with no bao dependency of its own, so it is reachable precisely when bao is sealed) provides the cold-boot human interaction for Tiers 1-2.

| Tier | Name | Cold-boot effort | Threat boundary | Suitable for |
|---|---|---|---|---|
| 1 | **Quorum unseal** | ≥3 humans × ≥3 attested devices × ≥3 biometric events | Multi-device + multi-human | Multi-operator / regulated facilities |
| 2 | **Operator unseal** *(recommended default)* | 1 enrolled device × 1 user verification by any method the platform offers, such as a biometric or a device PIN (+ optional passphrase) | Operator + their device | Single-operator deployments, labs, single-admin facilities |
| 3 | **Self-recovering** | None: cluster auto-unseals on boot | Cluster admin = bao admin | Temporary / demo / disposable; uptime > confidentiality |

Naming discipline: Tier 2 is the correct security for a single-operator threat model, so it is never described as "reduced security." That framing pushes operators to over-declare Tier 1 and then silently bypass it, which produces the worst outcome (declared posture differs from actual posture).

**Tier 3 reframes ADR-0011.** The existing single-replica auto-unseal file *is* Tier 3 (sub-variant 3b, cluster-resident wrapped blob); cloud-KMS auto-unseal (`awskms`/`gcpkms`, the ADR-0031 release-profile path) is sub-variant 3a, the most defensible form. Tier 3 has **no human actor**, so audit entries carry `actor: system: cluster-bootstrap` per ADR-0028 C5, named explicitly rather than omitted. In the sandbox-lane variant that ADR-0052 proposes, the unseal stays a system action, and each approval of a root token or a restore carries the enrolled administrator as actor.

**Mandatory guardrails (all tiers, except where a bullet names its scope), recorded as invariants for the eventual implementation:**

- **Per-cold-boot one-time token** for Tier 1, printed to node console / SSH MOTD, required by the kiosk form. This holds the unseal surface to operators with legitimate infra access at boot. Tier 2 has no such token (see Amendments).
- **Tier-downgrade protection** (the load-bearing guardrail): the declared tier is bound at deploy time in git-tracked config and **cryptographically checked at boot**; the unsealer refuses to operate *below* the declared tier. A downgrade requires an explicit, signed, audited config change. Dropping a file in a directory never suffices. The tier is visible in `kubectl` and the dmf-cms console.
- **Hard rate-limiting + audit-per-submission** on the kiosk (actor / role / request_id / reason to a WORM target, per ADR-0028 C5). In the sandbox lane, the record stays on the server and write-once delivery is waived (see Amendments).
- **No useless factor-stacking:** TOTP-on-top of a passkey flow is rejected (NIST `SP 800-63B`: weaker-over-stronger does not compose). Tier 1 *is* the quorum control; Tier 2 + per-device passphrase *is* the multi-factor control.

### Scope (what this ADR does and does not promote)

- **In scope (Accepted now):** the tier vocabulary, the kiosk model, the guardrail invariants, and the reframing of ADR-0011 as Tier 3. These are decided and may be referenced by other ADRs and plans.
- **Out of scope / deferred (NOT promoted by this ADR):** the **HA-bao-plus-raft migration** and the **kiosk + passkey/PRF/QR implementation**. The operator deferred implementation on 2026-05-25 pending a further review pass; this ADR does not reverse that. The engineering detail lives in the source plan and is revived from there. Do not revive it from this ADR.

## Alternatives rejected

- Leaving ADR-0011 as the whole story: it offers no framework to choose a different posture per deployment.
- Relaxing the INDEX "no gaps" rule instead of writing 0029: the framework content already existed in plan form.
- Promoting the full framework including HA/raft implementation now: this reverses the operator's 2026-05-25 deferral, and the experiment phase (ADR-0004) does not require the hardening yet.

## Consequences

- **Negative / honest:** because the raft baseline is unbuilt, this ADR is a *direction* and is not an operable control. If raft never lands, Tier 1/2 remain paper tiers and the live posture stays Tier 3 (ADR-0011). The warning in Context exists to keep readers from over-reading the table.
- **Neutral:** ADR-0009's 5-share DR path is untouched and remains the disaster custody layer for every tier, except in the sandbox lane, as ADR-0009's amendment states.

### Amendments of 2026-11-17

The decision numbers are in the [Tier 2 operator unseal plan](../plans/operator-unlock-tier2-plan.md). The RFC thread is [Discussion #865](https://github.com/orgs/dmfdeploy/discussions/865). The signed, boot-checked tier and the audited downgrade are unchanged. Like the guardrails, these amendments bind the eventual implementation. None of them is built yet, and the live posture stays as Context and Enforcement describe it.

- The sandbox lane runs one OpenBao server, and the deploy shows a visible warning. Raft with three servers is the baseline for long-lived sites. A sandbox that was grown to three servers keeps them until it is rebuilt with one; there is no in-place shrink (decisions 1 and 23).
- Tier 2 has no per-boot one-time token, and Tier 1 keeps it. Removing the token weakens the original proof of infrastructure access (decision 4).
- The Tier 2 row accepts user verification by any method the platform offers, including a device PIN (decision 8).
- The sandbox lane keeps its chained, numbered audit record on the server and waives write-once delivery, so losing the server loses the trail. A full spool never blocks the automatic unseal, and a lost record is accepted. No root token is created unless its audit record is written. Other lanes keep the write-once target of the audit guardrail (decisions 5 and 28).
- [ADR-0052](0052-sandbox-lane-tier3-variant.md) (Proposed) describes the named sandbox-lane variant of Tier 3, with its recovery package and its snapshot downloads (decisions 12, 13 and 21).

### Enforcement

Discipline only: the implementation that would enforce tiers mechanically is deferred, and no check enforces the declared tier or the tier-downgrade guardrail. The sandbox profile does select Tier-3 self-recovering behaviour (`dmf-env/bin/init-wizard.sh` sets `openbao_breakglass_distribution_enabled: false` and one Shamir share, overriding the default in `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/defaults/main.yml`), but nothing checks that choice against a declared tier. When the HA/raft baseline and kiosk are built, the boot-time signed-tier check (tier-downgrade protection) becomes the enforcement mechanism, and ADR-0011's automation file is either deleted (Tiers 1-2) or relabelled as the declared Tier 3 mechanism. In the sandbox lane, the automation file stays the Tier 3 mechanism until the seal transition is built and rehearsed. ADR-0052 proposes the Static Key seal as its replacement, which holds only once that rehearsal passes. Re-open trigger: the deferred-implementation review pass, or any of ADR-0011's revisit triggers firing.

## Status

Accepted (framework/posture only: implementation deferred)
Amended 2026-11-17 for the sandbox lane: see Amendments.

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0029-tiered-unseal-posture.md).
