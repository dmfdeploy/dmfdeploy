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
