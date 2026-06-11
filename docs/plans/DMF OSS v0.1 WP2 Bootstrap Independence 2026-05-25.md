---
status: executed
date: 2026-05-25
---
# DMF OSS v0.1 WP2 - Bootstrap Independence

> **⚠️ RE-SCOPED (2026-05-25): split by profile.** Under
> [WP0](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md) /
> [ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md),
> bootstrap independence has **two paths**, not one:
> - **`sandbox-single-node` (the gate):** no **maintainer-private** SOPS bundle /
>   operator-Mac / JuiceFS / Keychain dependency; **locally-generated sandbox
>   bootstrap material is allowed and resettable**, plus a **documented reset**
>   procedure. This is what gates v0.1. The AWS KMS
>   sections below do **not** apply to the sandbox; the sandbox keeps a simple
>   local OpenBao seed/unseal and treats reset/rerun as recovery. See
>   [WP1S](DMF%20OSS%20v0.1%20WP1S%20Single-Node%20Sandbox%20Lane%202026-05-25.md).
> - **`aws-arm64-multi-node` (secondary):** the AWS **KMS auto-unseal + SSM
>   seed + SNS alert** path below applies here. AWS-specific, non-gating.
> - **Kiosk** remains a **follow-on, not a hard v0.1 gate** (any profile).
>
> Below, read "AWS KMS auto-unseal is the v0.1 default" as **AWS-lane default
> only**. The sandbox gate does not require KMS.

**Status:** Active — split by profile (sandbox-local gate / AWS-KMS secondary)
**Date:** 2026-05-25
**Anchor:** [WP0 Release Contract & Profile Matrix](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md)
**Parent mission (superseded):** [DMF OSS v0.1 Release Mission 2026-05-25.md](DMF%20OSS%20v0.1%20Release%20Mission%202026-05-25.md)
**Outcome:** A released DMF cluster reaches and recovers steady state without
recurring dependence on the operator laptop, Mac keychain, JuiceFS, local
maintainer-private SOPS bundle, or external private network — **sandbox via locally-generated seed
+ documented reset; AWS via KMS auto-unseal.**

---

## 1. Problem

The current bootstrap flow still has a manual break between cluster creation
and steady state:

- The init wizard produces local bundle state.
- Terraform/OpenTofu runs from the operator environment.
- `bootstrap-provision-pre-seed.yml` installs the base cluster and OpenBao.
- The operator then runs `dmf-env/bin/bootstrap-secrets.sh seed-bao <env>`.
- Current OpenBao unseal paths depend on operator-local material and access.

That is acceptable for the current experiment, but it is not acceptable for a
self-contained OSS release.

---

## 2. Goals

1. Remove recurring operator-laptop dependency from OpenBao boot/recovery.
2. Make the v0.1 secrets posture explicit and reviewable.
3. Use AWS-native primitives where they reduce bootstrap ceremony safely.
4. Move seed/recovery actions into cluster-executed or release-orchestrated
   steps with clear auditability.
5. Emit boot, unseal, and seed alerts through the release notification paths,
   including AWS SNS for out-of-band delivery.
6. Define the kiosk mechanic as a scoped feature instead of an open-ended
   design idea.
7. Preserve a break-glass story for disaster/rekey scenarios.

---

## 3. Recommended v0.1 Shape

Minimum release gate:

- OpenBao uses AWS KMS auto-unseal for the AWS release profile.
- Initial secret seeding is performed by an in-cluster Job or a single
  release-orchestrated step that does not require Mac-specific state.
- The cluster can recover from reboot without the operator's laptop.

Kiosk track:

- The boot kiosk is not a hard v0.1 gate.
- Document kiosk as follow-on product work.
- Keep AWS KMS auto-unseal as the v0.1 self-contained posture.

---

## 4. Current State

Relevant files:

- `dmf-env/bin/init-wizard.sh`
- `dmf-env/bin/bootstrap-secrets.sh`
- `dmf-env/bin/unseal-openbao.sh`
- `dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml`
- `dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml`
- `dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml`
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao`
- `docs/decisions/0011-auto-unseal-tradeoff.md`
- `docs/plans/DMF Unseal Posture Tiered Framework Plan 2026-05-24.md`

Observed gaps:

- OpenBao remains a bootstrap boundary that requires external operator action.
- The unseal posture plan is not implemented.
- The seed path assumes local encrypted bundle material.
- Kiosk behavior is designed but not yet scoped to a minimal release feature.
- The current lifecycle names still encode a pre-seed/post-seed manual split.

---

## 5. Implementation Phases

### Phase 1 - Posture decision

Write or promote a binding decision that answers:

- Is AWS KMS auto-unseal the v0.1 default?
- How is kiosk documented as follow-on, non-blocking product work?
- Is HA OpenBao/raft required for v0.1 or a follow-on?
- What is the break-glass procedure?
- What local operator artifacts are still allowed after install?

Acceptance:

- WP2 has one approved posture, not three competing options.
- ADR-0011 is either superseded or explicitly narrowed.

### Phase 2 - AWS KMS auto-unseal

- Add AWS KMS key creation or lookup in WP1 Terraform.
- Give the OpenBao pod identity the minimum required KMS permissions.
- Configure OpenBao seal type for AWS KMS in the release profile.
- Remove the routine unseal requirement from the release path.
- Publish seal/unseal/recovery alerts to the configured release alert path.
- Add reboot/restart verification.

Acceptance:

- After node or pod restart, OpenBao returns to usable state without
  operator-local unseal material.

### Phase 3 - Cluster-side seed job

- Convert the manual `seed-bao` boundary into a Kubernetes Job or similarly
  orchestrated release step.
- Define how the initial bootstrap payload reaches the cluster.
- Ensure seed material is not left in long-lived plaintext.
- Add idempotency guards so reruns do not overwrite active secrets.
- Emit audit records and SNS/ntfy notifications for seed actions.

Acceptance:

- The bootstrap sequence no longer instructs the operator to run a manual
  local seed command as a required middle step.

### Phase 4 - Kiosk follow-on plan

- Write the v0.2 kiosk plan from the existing tiered framework.
- Add an explicit "not a hard v0.1 gate" note to the release docs.
- Preserve security constraints for the later implementation:
  - starts without depending on OpenBao/ESO;
  - uses one-time boot token handling;
  - uses the WP4 MFA policy and WP1 SNS substrate for any OTP or
    out-of-band confirmation;
  - rate-limits and audits all recovery actions;
  - exposes a clear disabled/idle state once the cluster is healthy.

Acceptance:

- The release docs explicitly say AWS KMS auto-unseal is the v0.1 boot
  mechanism and kiosk is follow-on product work.

### Phase 5 - Lifecycle sequence cleanup

- Rename or restructure the lifecycle phases if the pre-seed/post-seed split
  is no longer accurate.
- Ensure `site.yml` and `lifecycle-provision.yml` represent the actual release
  sequence.
- Update `bootstrap-verify.yml` to assert the new boot posture.

Acceptance:

- A new operator can follow one release bootstrap path without hidden manual
  seed/unseal steps.

---

## 6. Dependencies

- WP1 must provide AWS KMS/IAM decisions.
- WP3 ntfy may consume secrets produced by the new seed flow.
- WP5 needs reboot/recovery tests after this package lands.

---

## 7. Risks

- KMS auto-unseal changes the trust model. It must be documented honestly.
- A kiosk can become a security-sensitive web surface. Keep the MVP narrow.
- Moving seed into the cluster can accidentally create long-lived bootstrap
  secrets. The data lifetime must be designed, not assumed.
- HA OpenBao/raft may be desirable, but it can expand the release scope.

---

## 8. Done Definition

WP2 is done when a fresh AWS v0.1 cluster can complete bootstrap and recover
from reboot without the current operator-laptop seed/unseal dependency, and
the AWS KMS posture is documented and verified while kiosk remains clearly
tracked as follow-on product work.
