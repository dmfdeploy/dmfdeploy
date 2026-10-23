# ADR-0029 archive: Tiered Unseal Posture for OSS deployment

This file holds material moved out of [ADR-0029](../../decisions/0029-tiered-unseal-posture.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

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

## References

- [ADR-0011](../../decisions/0011-auto-unseal-tradeoff.md) — the auto-unseal tradeoff this reframes
  as Tier 3.
- [ADR-0009](../../decisions/0009-shamir-dr-model.md) — 5-share Shamir DR (orthogonal, all tiers).
- [ADR-0028](../../decisions/0028-identity-and-authority-chain.md) — custody (D1/C2) + audit (C5)
  contracts the tiers concretize.
- [ADR-0031](../../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md) — the AWS-KMS
  release path that is Tier 3 sub-variant 3a.
- [ADR-0004](../../decisions/0004-experiment-phase-stance.md) — why the implementation is deferred.
- `docs/plans/dmf-unseal-posture-tiered-framework-plan.md` — full design.

## Moved from the ADR on 2026-10-23

### Context (original text)


OpenBao starts **sealed** after any restart. Today the lab runs a single-replica
StatefulSet, so routine pod churn (Longhorn rebalance, node drain, OS patch) seals
it multiple times per week, and the only unseal paths
(`dmf-env/bin/unseal-openbao.sh`, the openbao role) require the **operator's workstation +
encrypted volume + OS keychain + Tailscale reachability**. The cluster cannot self-heal from a
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

### Positive consequences (original text)

- **Positive** — the posture is named per-deployment instead of being an accident
  of which unseal path ran. ADR-0009 vs ADR-0011 ambiguity resolves into "which
  tier is this cluster?"
- **Positive** — ADR-0011's tradeoff stops reading as a quiet weakness and becomes
  an explicit, audited Tier 3 *choice*.
- **Positive** — closes the reserved-0029 numbering gap that the
  [2026-05-27 portfolio review](../../reviews/dmf-adr-portfolio-review.md)
  flagged (INDEX "no gaps" rule).

### Enforcement (original text)


Currently **discipline-only** (the implementation that would mechanically enforce
tiers is deferred). When the HA/raft baseline and kiosk are built, enforcement
becomes concrete: the boot-time signed-tier check (tier-downgrade protection)
is the enforcement mechanism, and ADR-0011's automation file is either deleted
(Tiers 1–2) or relabelled as the declared Tier 3 mechanism. Re-open trigger:
the deferred-implementation review pass, or any of ADR-0011's revisit triggers
firing.
