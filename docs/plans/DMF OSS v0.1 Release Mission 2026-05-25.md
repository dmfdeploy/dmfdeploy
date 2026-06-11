---
status: superseded
date: 2026-05-25
superseded_by: "DMF OSS v0.1 WP0 Release Contract and Profile Matrix 2026-05-25.md"
---
# DMF OSS v0.1 Release Mission
> **Superseded by** [DMF OSS v0.1 WP0 Release Contract and Profile Matrix 2026-05-25.md](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md) — see frontmatter.

> **⚠️ SUPERSEDED DRAFT (2026-05-25).** This Mission predates the
> [ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md)
> profile-matrix framing. Its core premise — *v0.1 = a single AWS-backed
> self-contained cluster, AWS-only, with full CMS user-admin as a release gate*
> — is **stale**. The binding sequence and scope are now owned by
> [**WP0 — Release Contract & Profile Matrix**](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md).
>
> Under WP0: the v0.1 **release gate** is `sandbox-single-node` (generic ARM64
> Debian single host), **not** AWS. AWS (`aws-arm64-multi-node`) is a secondary
> eligible-if-ready lane that never gates. `g2r6-foa9` is reference/regression
> only. This Mission is kept for context (its AWS/boot/services material is
> reused under the re-scoped WPs); **do not treat its sequence or gates as
> binding.**

**Status:** Superseded draft — see [WP0](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md)
**Date:** 2026-05-25
**Author:** Codex planning sweep
**Related ADR:** [ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md)
**Purpose:** Narrow the current experiment into a self-contained OSS release
that can be installed, operated, and verified without multi-provider sprawl or
operator-laptop dependency.

---

## 1. Mission

DMF OSS v0.1 should be the smallest credible release of the platform:

> A single AWS-backed, self-contained DMF cluster with DNS, object storage,
> compute, identity, notifications, out-of-band alerts, admin-managed users,
> and release verification all inside one supported deployment profile.

The release should prove the product loop end to end:

1. An operator creates one AWS-backed environment.
2. The cluster provisions its required platform services.
3. OpenBao and steady-state secrets recover without the operator's laptop as
   an ongoing dependency.
4. Users can request or receive access.
5. An admin can approve users and assign roles.
6. The CMS can launch and manage the initial catalog/deployment workflow.
7. The install can be verified, rerun idempotently, and tagged as a coherent
   set of component SHAs.

This release is not a full platform roadmap. It is a stable first public cut.

---

## 2. Release Posture

| Axis | v0.1 direction | Rationale |
|---|---|---|
| Cloud provider | AWS only | Removes Cloudflare, B2, Hetzner, Aliyun, and external-provider sprawl from the release path. |
| DNS | Route53 | Keeps DNS inside the selected provider. |
| Object storage | S3 | Replaces Backblaze B2 as the required release storage target. |
| Compute | EC2-backed k3s | Matches the existing VPS-oriented architecture while staying single-provider. |
| Identity | Authentik + CMS admin workflow | Current Authentik integration exists; user lifecycle is incomplete. |
| Notifications | In-cluster ntfy at `ntfy.<base_domain>` + AWS SNS | ntfy handles cluster-local/app notifications and external subscriptions; SNS provides AWS-native out-of-band alerting. |
| MFA / 2FA | Passkeys or TOTP primary; AWS SNS-backed OTP/SMS/email as optional fallback or step-up path | Avoids SMS-only admin security while still using AWS for message delivery. |
| Secrets boot | AWS KMS auto-unseal plus cluster-side seed/recovery flow | Fastest path to remove the recurring bootstrap-laptop dependency. |
| Kiosk | Not a hard v0.1 gate; tracked as follow-on product work | AWS KMS auto-unseal is the v0.1 boot-independence gate. |
| Headscale | Mandatory in-cluster service at `hs.<base_domain>`, wired to Authentik/OIDC, sequenced after base cluster bootstrap | Current early Tailscale join conflicts with in-cluster Headscale and must move. |
| Media/catalog scope | One reference catalog/deploy path | Enough to prove the loop without expanding the media roadmap. |

---

## 3. Explicit Non-Goals

The following are out of the v0.1 release path unless a later ADR moves them
back in:

- Multi-provider install support.
- Hetzner, Aliyun, Cloudflare, or Backblaze B2 as supported release profiles.
- dmf-central federation or managed central services.
- Flypack/air-gapped deployment mode.
- Multiple catalog domains beyond the initial reference path.
- Full enterprise RBAC/policy administration.
- SMS-only authentication as the sole admin security posture.
- Managed SaaS/Mode B deployment.
- LibreNMS or additional observability products not already needed for the
  release loop.

These can remain in the repository as experimental or future work, but they
must not be required for the OSS v0.1 path.

---

## 4. Work Package Map

| Work package | Doc | Primary outcome |
|---|---|---|
| WP1 | [DMF OSS v0.1 WP1 AWS Provider Profile 2026-05-25.md](DMF%20OSS%20v0.1%20WP1%20AWS%20Provider%20Profile%202026-05-25.md) | AWS becomes the only supported v0.1 provider profile. |
| WP2 | [DMF OSS v0.1 WP2 Bootstrap Independence 2026-05-25.md](DMF%20OSS%20v0.1%20WP2%20Bootstrap%20Independence%202026-05-25.md) | Cluster reaches and recovers steady state without recurring operator-laptop dependency. |
| WP3 | [DMF OSS v0.1 WP3 In-Cluster Platform Services 2026-05-25.md](DMF%20OSS%20v0.1%20WP3%20In-Cluster%20Platform%20Services%202026-05-25.md) | ntfy is internal; Headscale is internal, OIDC-wired, and sequenced after base bootstrap. |
| WP4 | [DMF OSS v0.1 WP4 CMS User Administration 2026-05-25.md](DMF%20OSS%20v0.1%20WP4%20CMS%20User%20Administration%202026-05-25.md) | CMS supports signup/invite, admin approval, role assignment, and role-gated operations. |
| WP5 | [DMF OSS v0.1 WP5 Release Verification and Tagging 2026-05-25.md](DMF%20OSS%20v0.1%20WP5%20Release%20Verification%20and%20Tagging%202026-05-25.md) | Release gates, greenfield verification, docs, and tags are repeatable. |

---

## 5. Recommended Sequence

1. **Scope lock and ADR update**
   - Promote this mission into a binding ADR or update ADR-0026 with an
     explicit v0.1 provider scope.
   - Record kiosk as a non-blocking follow-on after AWS KMS auto-unseal.
   - Record Headscale as mandatory for v0.1, wired to Authentik/OIDC, and
     sequenced after base cluster readiness.

2. **WP1: AWS provider profile**
   - This is the foundation for DNS, storage, cert-manager, and secrets boot.
   - Do this before rewriting the bootstrap lifecycle.

3. **WP2: Bootstrap independence**
   - Implement the chosen OpenBao boot path and remove manual seed/unseal
     assumptions from the release flow.
   - This depends on AWS KMS/IAM decisions from WP1.

4. **WP3: In-cluster platform services**
   - Add ntfy before Authentik/Prometheus consumers.
   - Deploy Headscale in-cluster, wire it to Authentik/OIDC, and re-sequence
     node Tailscale join to avoid the bootstrap loop.

5. **WP4: CMS user administration**
   - Can proceed partly in parallel with WP1/WP2.
   - Must finish before release verification.

6. **WP5: Release verification and tagging**
   - Run once the release path is coherent.
   - Produces the final release manifest and tags.

---

## 6. Release Gates

v0.1 is not ready until all of these are true:

1. A new AWS environment can be created from scratch with documented inputs.
2. No Cloudflare, Backblaze B2, Hetzner, Aliyun, public ntfy.sh, or external
   Headscale server/credential is required on the release path.
3. Route53 DNS and S3 object storage are provisioned and verified.
4. AWS SNS alert delivery is provisioned and smoke-tested.
5. OpenBao reaches usable state after install and after reboot without the
   current operator Mac / JuiceFS / Keychain / Tailscale dependency.
6. ntfy is provided in-cluster and exposed at `ntfy.<base_domain>`.
7. Headscale is deployed in-cluster, exposed at `hs.<base_domain>`, wired to
   Authentik/OIDC, and node join is sequenced after Headscale is reachable.
8. CMS admin can invite or approve a user, assign a role, and revoke or
   disable access.
9. Admin and privileged operational flows require a configured second factor.
10. Viewer users cannot perform deploy/teardown/admin operations.
11. The initial catalog/deploy workflow works from CMS.
12. A full second run is idempotent.
13. Recovery checks cover reboot, OpenBao seal/recovery posture, TLS renewal
    assumptions, S3 write/read, ntfy/SNS notification smoke, and CMS MFA/authz.
14. Public release hygiene checks pass across the public repos.
15. The umbrella release manifest pins component SHAs and tags.

---

## 7. Open Decisions

| Decision | Default recommendation | Required before |
|---|---|---|
| Kiosk in v0.1? | Not a hard v0.1 gate; keep as follow-on after AWS KMS auto-unseal. | WP2 implementation |
| Headscale in v0.1? | Mandatory; deploy in-cluster after base cluster readiness and wire to Authentik/OIDC. | WP3 implementation |
| AWS node shape | Start with one supported EC2 architecture/size class. | WP1 Terraform |
| Load balancer strategy | Prefer the simplest working Route53/TLS ingress path for k3s. | WP1 Terraform/cert-manager |
| SNS scope | Provision security/platform alert topics; use SMS/email OTP only as fallback or step-up, not SMS-only admin auth. | WP1/WP4 |
| Release tags | Tag each component plus umbrella manifest, or tag umbrella only with pinned SHAs. | WP5 |
| Legacy providers | Keep as experimental docs/code or move out of release-facing docs. | WP1/WP5 docs |

---

## 8. Status Tracking

This mission doc is the index. Each work package should update its own
status and acceptance section as it progresses. `STATUS.md` remains the
cross-repo snapshot, but v0.1 scope decisions should live here or in a
promoted ADR so they do not get lost in session handoffs.
