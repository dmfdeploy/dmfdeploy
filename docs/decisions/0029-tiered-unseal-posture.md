# ADR-0029: Tiered Unseal Posture for OSS deployment

**Status:** Accepted (framework/posture only — implementation deferred)
**Date:** 2026-05-30
**Deciders:** @<handle> (operator). Distilled from the 2026-05-24 design session
(operator + claude-bottom); promoted from plan to ADR on 2026-05-30 at operator
request to close the reserved-0029 numbering gap.
**Reframes (does not yet supersede):** [ADR-0011](0011-auto-unseal-tradeoff.md)
**Concretizes:** [ADR-0028](0028-identity-and-authority-chain.md) D1/C2 (OpenBao
custody) per declared tier.
**Orthogonal to:** [ADR-0009](0009-shamir-dr-model.md) (5-share Shamir remains the
disaster-recovery custody layer for all tiers); [ADR-0020](0020-deployment-scope-and-regulatory-posture.md)
(deployment-scope axis is independent of this security-posture axis).
**Source plan:** `docs/plans/DMF Unseal Posture Tiered Framework Plan 2026-05-24.md`
(full design rationale, threat trees, and the passkey/PRF/QR transport design).

## Context

OpenBao starts **sealed** after any restart. Today the lab runs a single-replica
StatefulSet, so routine pod churn (Longhorn rebalance, node drain, OS patch) seals
it multiple times per week, and the only unseal paths
(`dmf-env/bin/unseal-openbao.sh`, the openbao role) require the **operator's Mac +
JuiceFS + Keychain + Tailscale reachability**. The cluster cannot self-heal from a
reboot, and for air-gapped deployments the current mechanism cannot run at all.

ADR-0009 declares 3-of-5 Shamir defense; ADR-0011 records that the *routine* path
collapses to 1-of-1 (the automation file). Read together they leave a confusing
posture story — "do we have Shamir defense or not?" The honest answer is "it
depends which path you took." This ADR removes that ambiguity by naming the
posture **explicitly and per-deployment**, rather than leaving it as an unspoken
side effect of which unseal path happened to run.

The unseal pain decomposes into three scenarios with different tolerable friction:
**cold boot** (rare, one ceremony acceptable), **routine pod restart**
(multiple/week, zero operator tolerable), and **disaster/rekey** (once or never,
heavy ceremony fine). Today's posture conflates the first two and underserves the
third.

> **⚠ Directional posture, not an operationally-available menu (read this).**
> Every tier below is *defined on top of* an HA-bao-+-raft baseline, and that
> baseline is **not yet implemented** (deferred per the 2026-05-25 operator
> decision; see §Scope). Until raft lands, the tiers are **not selectable** —
> the live cluster runs the ADR-0011 single-replica auto-unseal reality. The
> concrete, *today* value of this ADR is narrow but real: it makes ADR-0011's
> auto-unseal legible as **"Tier 3 — explicitly chosen, warned, audited"**
> rather than a silent confidentiality weakness, and it fixes the vocabulary so
> future hardening has a target. Do not read the tier table as a posture you can
> pick right now.

## Decision

Adopt a **three-tier unseal posture**, declared at deploy time, as the framework
the platform's unseal story is organised around. **HA bao + raft is the universal
baseline** for all tiers (it eliminates routine pod-restart pain independent of
cold-boot posture). A cluster-resident **unseal kiosk** (a Traefik-served app with
no bao dependency of its own, so it is reachable precisely when bao is sealed)
provides the cold-boot human interaction for Tiers 1–2.

| Tier | Name | Cold-boot effort | Threat boundary | Suitable for |
|---|---|---|---|---|
| 1 | **Quorum unseal** | ≥3 humans × ≥3 attested devices × ≥3 biometric events | Multi-device + multi-human | Multi-operator / regulated facilities |
| 2 | **Operator unseal** *(recommended default)* | 1 phone × 1 biometric (+ optional passphrase) | Operator + their device | Single-operator deployments, labs, single-admin facilities |
| 3 | **Self-recovering** | None — cluster auto-unseals on boot | Cluster admin = bao admin | Temporary / demo / disposable; uptime > confidentiality |

Naming discipline: Tier 2 is **not** "reduced security" — for a single-operator
deployment it is the *correct* security for that threat model. Framing it as
reduced pushes operators to over-declare Tier 1 and then silently bypass it,
producing the worst outcome (declared posture ≠ actual posture).

**Tier 3 reframes ADR-0011.** The existing single-replica auto-unseal file *is*
Tier 3 (sub-variant 3b, cluster-resident wrapped blob); cloud-KMS auto-unseal
(`awskms`/`gcpkms`, the ADR-0031 release-profile path) is sub-variant 3a, the most
defensible form. Tier 3 has **no human actor** — audit entries carry
`actor: system: cluster-bootstrap` per ADR-0028 C5, named explicitly rather than
omitted.

**Mandatory guardrails (all tiers), recorded as invariants for the eventual
implementation:**

- **Per-cold-boot one-time token** printed to node console / SSH MOTD, required by
  the kiosk form — holds the unseal surface to operators with legitimate infra
  access at boot.
- **Tier-downgrade protection** (the load-bearing guardrail): the declared tier is
  bound at deploy time in git-tracked config and **cryptographically checked at
  boot**; the unsealer refuses to operate *below* the declared tier. A downgrade
  requires an explicit, signed, audited config change — not dropping a file in a
  directory. The tier is visible in `kubectl` and the dmf-cms console.
- **Hard rate-limiting + audit-per-submission** on the kiosk (actor / role /
  request_id / reason → WORM target, per ADR-0028 C5).
- **No useless factor-stacking:** TOTP-on-top of a passkey flow is rejected
  (NIST 800-63B — weaker-over-stronger does not compose). Tier 1 *is* the quorum
  control; Tier 2 + per-device passphrase *is* the multi-factor control.

## Scope (what this ADR does and does not promote)

- **In scope (Accepted now):** the tier vocabulary, the kiosk model, the
  guardrail invariants, and the reframing of ADR-0011 as Tier 3. These are
  decided and may be referenced by other ADRs and plans.
- **Out of scope / deferred (NOT promoted by this ADR):** the **HA-bao-+-raft
  migration** and the **kiosk + passkey/PRF/QR implementation**. The operator
  deferred implementation on 2026-05-25 pending a further review pass; this ADR
  does not reverse that. The engineering detail lives in the source plan and is
  revived from there, not from this ADR.

## Consequences

- **Positive** — the posture is named per-deployment instead of being an accident
  of which unseal path ran. ADR-0009 vs ADR-0011 ambiguity resolves into "which
  tier is this cluster?"
- **Positive** — ADR-0011's tradeoff stops reading as a quiet weakness and becomes
  an explicit, audited Tier 3 *choice*.
- **Positive** — closes the reserved-0029 numbering gap that the
  [2026-05-27 portfolio review](../reviews/DMF%20ADR%20Portfolio%20Review%202026-05-27.md)
  flagged (INDEX "no gaps" rule).
- **Negative / honest** — because the raft baseline is unbuilt, this ADR is a
  *direction*, not an operable control. If raft never lands, Tier 1/2 remain
  paper tiers and the live posture stays Tier 3 (ADR-0011). The §Context warning
  exists to keep readers from over-reading the table.
- **Neutral** — ADR-0009's 5-share DR path is untouched and remains the disaster
  custody layer for every tier.

## Alternatives considered

- **Leave ADR-0011 as the whole story.** Rejected — it documents the weakness
  honestly but offers no framework to choose a *different* posture per deployment,
  and conflates cold-boot with routine-restart pain.
- **Relax the INDEX "no gaps" rule instead of writing 0029.** Considered (review
  §6 action 1 offered it as the alternative). Rejected in favour of writing the
  ADR, since the framework content already existed in plan form and is worth
  recording as canonical vocabulary.
- **Promote the full framework including HA/raft implementation now.** Rejected —
  reverses the operator's 2026-05-25 deferral; experiment phase (ADR-0004) does
  not require the hardening yet.
- **Per-operation tier escalation** (rekey/root-issuance always Tier 1 regardless
  of declared tier). Noted as a worthwhile future extension; not required for
  first ship.

## Enforcement

Currently **discipline-only** (the implementation that would mechanically enforce
tiers is deferred). When the HA/raft baseline and kiosk are built, enforcement
becomes concrete: the boot-time signed-tier check (tier-downgrade protection)
is the enforcement mechanism, and ADR-0011's automation file is either deleted
(Tiers 1–2) or relabelled as the declared Tier 3 mechanism. Re-open trigger:
the deferred-implementation review pass, or any of ADR-0011's revisit triggers
firing.

## References

- [ADR-0011](0011-auto-unseal-tradeoff.md) — the auto-unseal tradeoff this reframes
  as Tier 3.
- [ADR-0009](0009-shamir-dr-model.md) — 5-share Shamir DR (orthogonal, all tiers).
- [ADR-0028](0028-identity-and-authority-chain.md) — custody (D1/C2) + audit (C5)
  contracts the tiers concretize.
- [ADR-0031](0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md) — the AWS-KMS
  release path that is Tier 3 sub-variant 3a.
- [ADR-0004](0004-experiment-phase-stance.md) — why the implementation is deferred.
- `docs/plans/DMF Unseal Posture Tiered Framework Plan 2026-05-24.md` — full design.
