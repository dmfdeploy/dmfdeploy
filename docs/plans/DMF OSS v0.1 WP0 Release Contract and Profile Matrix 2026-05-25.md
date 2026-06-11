---
status: active
date: 2026-05-25
---
# DMF OSS v0.1 WP0 — Release Contract & Profile Matrix
> Supersedes: [DMF OSS v0.1 Release Mission 2026-05-25.md](DMF%20OSS%20v0.1%20Release%20Mission%202026-05-25.md)

**Status:** Active — binding planning anchor for OSS v0.1
**Date:** 2026-05-25
**Author:** Claude (planning sweep, under ADR-0031 framing)
**Related ADR:** [ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md) (Accepted; this doc is its WP0 acceptance artifact)
**Supersedes (as binding sequence):** [DMF OSS v0.1 Release Mission 2026-05-25.md](DMF%20OSS%20v0.1%20Release%20Mission%202026-05-25.md) (now superseded draft)
**Premise basis:** [DMF OSS v0.1 Contributor Replicability Premise Pass 2026-05-25.md](DMF%20OSS%20v0.1%20Contributor%20Replicability%20Premise%20Pass%202026-05-25.md)
**Work packages:** [WP1S](DMF%20OSS%20v0.1%20WP1S%20Single-Node%20Sandbox%20Lane%202026-05-25.md) · [WP-LAB](DMF%20OSS%20v0.1%20WP-LAB%20g2r6-foa9%20Reference%20Delta%202026-05-25.md) · [WP1A](DMF%20OSS%20v0.1%20WP1%20AWS%20Provider%20Profile%202026-05-25.md) · [WP2](DMF%20OSS%20v0.1%20WP2%20Bootstrap%20Independence%202026-05-25.md) · [WP3](DMF%20OSS%20v0.1%20WP3%20In-Cluster%20Platform%20Services%202026-05-25.md) · [WP4](DMF%20OSS%20v0.1%20WP4%20CMS%20User%20Administration%202026-05-25.md) · [WP5](DMF%20OSS%20v0.1%20WP5%20Release%20Verification%20and%20Tagging%202026-05-25.md)

---

## 0. What this doc is

WP0 is the **anchor** for OSS v0.1. It is the doc that binds the *sequence* and
the *scope*. It replaces the old [Release Mission](DMF%20OSS%20v0.1%20Release%20Mission%202026-05-25.md)
as the source of truth for "what v0.1 is and in what order we build it." The
Mission and the original WP1–WP5 drafts predate the [ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md)
profile-matrix framing; their AWS-as-gate sequencing is stale. Their AWS / boot /
platform / CMS / verification *material* is still useful and is preserved under
re-scoped successors (see §6).

The single most important sentence in this doc:

> **`sandbox-single-node` is the immediate implementation center and the v0.1
> release gate. Everything else is parallel, secondary, or reference.**

---

## 1. Vocabulary

These four terms are used precisely throughout the v0.1 doc set. Mixing them up
is what produced the stale AWS-as-gate framing.

| Term | Definition |
|---|---|
| **Release profile** | A named, verifiable deployment shape that v0.1 makes a *claim* about. A profile has a gate list; passing it means v0.1 can assert that profile works. Only `sandbox-single-node` is release-*gating*; `aws-arm64-multi-node` is release-*eligible*. |
| **Implementation harness** | The concrete substrate we *develop and iterate on* to make a profile real. The harness is not the claim. For `sandbox-single-node` the first live harness is a local Lima Debian ARM64 VM on the maintainer's Mac; the *claim* is generic ARM64 Debian single-node (VM / bare metal / cheap VPS). The harness is allowed to be more specific than the claim. |
| **Atomic playbook** | A reusable playbook that installs or configures one platform capability (`300-k3s.yml`, `320-cert-manager.yml`, `640-awx.yml`, etc.). Atomic playbooks should stay shared across lanes wherever possible. They may read profile capability variables, but they should not be forked per provider unless behavior is genuinely different. |
| **Lane wrapper** | A profile-specific orchestration entrypoint that selects which atomic playbooks run, in what order, for a lane. Wrappers make sequence differences explicit: sandbox can skip Longhorn/object backups/Headscale while AWS can add S3/SNS/KMS/Headscale work without cloning every atomic playbook. |
| **Profile capability variables** | Manifest/inventory variables that describe what a lane needs (`dmf_storage_backend`, `dmf_ingress_mode`, `dmf_object_storage_enabled`, etc.). Prefer capability variables over provider-name conditionals so future lanes can reuse the same behavior. |
| **Reference / regression lab** | A live environment used to compare behavior, harvest working settings, and catch regressions. It is **not** release-scrutinized and never ships as a profile. `g2r6-foa9` (the 3-node Hetzner ARM lab) is this. |
| **Secondary eligible-if-ready lane** | A release profile that gets real work but is **never** allowed to gate or delay the release. It ships in the v0.1 tag only if it passes its gates without holding up the sandbox lane. `aws-arm64-multi-node` is this. |

---

## 2. Lane matrix

Three architectural profiles from ADR-0031, plus the concrete work lanes they map
to right now.

| Lane / profile | Role in v0.1 | Substrate | Status of claim |
|---|---|---|---|
| **`sandbox-single-node`** | **Release gate.** Default docs path. v0.1 cannot be tagged unless this passes its gates from a fresh clone. | Generic ARM64 Debian single host: local VM, bare metal, or cheap VPS. First live implementation harness is local Lima. | The claim is generic single-node ARM64 Debian. Lima is *how we build it first*, not *what we promise*. |
| **`aws-arm64-multi-node`** | **Secondary, eligible-if-ready.** Real work, never gating. Ships in the tag only if it catches up without delaying sandbox. | ARM64 EC2 (Graviton), self-managed k3s (ADR-0018), Route53 / S3 / SNS / KMS, in-cluster Headscale + ntfy. | Terraform skeleton is **`tofu validate`-clean and template-complete, NOT plan-proven.** A real plan/apply needs an operator-named AWS profile + real Route53 zone + read-only preflight. See [WP1A](DMF%20OSS%20v0.1%20WP1%20AWS%20Provider%20Profile%202026-05-25.md). |
| **`g2r6-foa9`** (and successors) | **Live reference / regression lab.** Not a release profile. | 3-node Hetzner CAX21 ARM64, with maintainer-specific deps (Cloudflare, B2, JuiceFS, Keychain shares, external Headscale, Tailscale). | No release claim. Used to compare against sandbox requirements and harvest known-good settings. See [WP-LAB](DMF%20OSS%20v0.1%20WP-LAB%20g2r6-foa9%20Reference%20Delta%202026-05-25.md). |

**Center of gravity:** `sandbox-single-node`. If a choice ever arises between
polishing the AWS lane and making the sandbox lane concrete, the sandbox lane
wins. AWS work must not be sequenced ahead of the sandbox lane.

---

## 3. Common v0.1 workflow contract

Every release profile must support, end to end, this contributor experience.
This is copied and aligned from [ADR-0031 §Canonical workflow contract](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md).

1. Clone the repo and install documented prerequisites.
2. Provide a small profile manifest (common fields + a few profile-specific fields).
3. Provision or bind one ARM64 host / node set per the chosen profile.
4. Bootstrap k3s and core platform services.
5. Log in as the seeded admin (DMF Console passkey, per [ADR-0015](../decisions/0015-dmf-console-passkey-only.md)).
6. Deploy one reference catalog item end to end (`nmos-cpp` registry + mock nodes, per ADR-0031 O2).
7. Verify auth / storage / ingress / catalog to the level the profile claims.
8. Rerun the workflow idempotently from the same manifest.
9. Reset or teardown cleanly.

Steps that vary by profile (DNS source, TLS source, object storage, secret-boot
posture, notification path, overlay mesh) are encoded as profile-specific
manifest fields. The *workflow itself* stays uniform across profiles. The
inline v0.1 manifest is shaped for later migration to ADR-0026 provider
descriptors but does **not** gate on full descriptor implementation (ADR-0031 O5).

Implementation rule: **do not fork the full bootstrap tree per lane.** Keep the
existing atomic playbooks shared where possible, add lane wrappers for sequence
differences, and express behavioral differences as profile capability variables.
The current lab wrappers remain the reference/regression path; the sandbox lane
gets its own wrapper sequence first; the AWS lane can add a secondary wrapper
when it moves from Terraform validation to a real plan/apply proof.

---

## 4. Gates

### 4.1 Common gates (every release profile)

Aligned with [ADR-0031 §Common gates](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md).

1. Fresh install reproducible from public docs + public repos only.
2. No maintainer-specific credentials or private inventory required.
3. `linux/arm64` image availability for **every** workload shipped in the profile.
4. Seeded admin login works through the DMF Console **passkey-only** flow
   ([ADR-0015](../decisions/0015-dmf-console-passkey-only.md)). No "TOTP or
   passkey" weakening of the console login. (SNS/OTP, where a profile has it,
   is for non-console / break-glass / step-up only — never the console gate.)
5. One reference catalog item deploys end to end.
6. Idempotent rerun from the same manifest.
7. Reset / teardown documented and tested.
8. No hardcoded operator paths, domains, IPs, or secrets in release artifacts.

### 4.2 Profile-specific gates

| Profile | Adds these gates |
|---|---|
| `sandbox-single-node` | Local CA issued + trust documented; explicit `dmf.test` host mappings resolve; local-path storage works; OpenBao boots without operator-Mac / JuiceFS / Keychain material; AWX runs at low concurrency without starving the node; seeded admin passkey login. **No** Longhorn, **no** object-storage backup, **no** Headscale, **no** SNS/KMS/Route53, monitoring trimmed/optional. |
| `aws-arm64-multi-node` | Route53 DNS-01 TLS; S3 read/write; SNS publish; AWS KMS auto-unseal; in-cluster Headscale wired to Authentik/OIDC at `hs.<base_domain>`; in-cluster ntfy at `ntfy.<base_domain>`; multi-node scheduling. |
| `g2r6-foa9` | **None — not release-scrutinized.** Used as a behavioral reference only. |

### 4.3 Release version manifest (mandatory common gate / release artifact)

Every release profile is composed from a single, canonical **version manifest /
bill of materials**:

- **Source of truth:** [`docs/releases/dmf-oss-v0.1-version-manifest.yaml`](../releases/dmf-oss-v0.1-version-manifest.yaml)
  (human companion: [DMF OSS v0.1 Version Manifest](../releases/DMF%20OSS%20v0.1%20Version%20Manifest.md)).
- It pins or explicitly lane-classifies every release-relevant component repo
  ref, k3s version, Helm chart, raw manifest, DMF-built image, third-party
  image, and Ansible collection, plus the `linux/arm64` requirement.
- It is **mandatory**: v0.1 cannot be tagged unless the manifest is current for
  the lane being released and that lane's components are non-floating,
  arm64-available, and free of manifest↔role-default drift. **[WP5](DMF%20OSS%20v0.1%20WP5%20Release%20Verification%20and%20Tagging%202026-05-25.md)
  owns enforcement** of this gate.
- It is WP0/WP5 release discipline under [ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md),
  **not** a new ADR.
- The manifest's `known_gaps` already records the live drift the release must
  close (nmos seed-chart fallback, floating `:latest` images, unpinned/ranged
  collections, dmf-cms runtime version resolution).

### 4.4 What v0.1 explicitly does NOT claim (any profile)

From [ADR-0031 §Claim split](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md):
production ST-2110 / PTP / multicast / NIC-isolation correctness; real-time
media-plane behavior; multi-tenant / Mode B; enterprise RBAC / policy admin /
audit retention SLOs; geographic redundancy / DR / backup-restore SLOs;
performance / capacity numbers under load. Media-realism is a later profile with
an explicit data-plane testbed.

---

## 5. Explicit scope trims

These are the deliberate cuts that keep v0.1 small and the sandbox lane
honest. They specialize ADR-0031's per-profile resolutions.

| Trim | Decision | Rationale |
|---|---|---|
| **Storage** | No Longhorn in sandbox; use k3s `local-path`. | Single node has no replication story to gain from Longhorn; local-path is the appliance-shaped default. |
| **Backups** | No object-storage backup requirement in sandbox. | A sandbox is disposable; teardown + fresh rerun *is* the recovery story. Documented reset replaces backup. |
| **AWX** | **Retained.** dmf-cms depends on AWX to drive the catalog/deploy loop. Run it at low concurrency on local-path RWO; disable backup CronJobs. Do **not** try to starve AWX below realistic limits. | AWX is load-bearing for the reference catalog deploy (workflow contract step 6). Cutting it would cut the loop. |
| **Monitoring** | Reduce in sandbox; Prometheus optional / trimmed. | A single-node sandbox does not need full kube-prometheus-stack to prove the loop. Keep enough to debug, not a full observability stack. |
| **Overlay mesh** | Headscale **not required** in sandbox. | Sandbox-local communication suffices on one node. Headscale stays mandatory for the AWS multi-node lane. |
| **DNS / TLS** | Local CA + explicit `.test` host mappings (default `dmf.test`) for sandbox. | ADR-0031 O1. Installer/docs must help trust the CA. User-owned DNS + ACME DNS-01 is an optional escape hatch, not the gate. Do not use `.local`. |
| **Auth gate** | Seeded admin **passkey** login is the auth gate. | ADR-0031 O4 + [ADR-0015](../decisions/0015-dmf-console-passkey-only.md). Full signup/approval/role-assignment UI moves to v0.2 (see [WP4](DMF%20OSS%20v0.1%20WP4%20CMS%20User%20Administration%202026-05-25.md)). |
| **Secrets boot** | Sandbox uses locally-generated bootstrap material + documented reset. No operator-Mac / JuiceFS / Keychain dependency. AWS KMS auto-unseal is the AWS lane's posture, not the sandbox's. | ADR-0031 O4 / Profile 1. |
| **Kiosk** | Not a hard v0.1 gate (any profile). Follow-on product work. | ADR-0031. |

---

## 6. Work-package sequence

The binding sequence. Numbers are priority order, not parallelism bans —
WP1A and WP-LAB run alongside the sandbox lane but never ahead of it.

```
WP0  ── Release Contract & Profile Matrix .................. THIS DOC (anchor)
 │
 ├─▶ WP1S  Single-Node Sandbox Lane ........................ FIRST ACTIONABLE ★
 │     the v0.1 release gate; immediate implementation center
 │
 ├── WP-LAB  g2r6-foa9 Reference Delta ..................... parallel, reference
 │     compare lab → sandbox; harvest known-good settings
 │
 ├── WP1A  AWS ARM64 Multi-Node Lane ....................... parallel, secondary
 │     eligible-if-ready; never gates; not sequenced ahead of WP1S
 │
 ├── WP2   Bootstrap Independence (split by profile) ....... sandbox-local / AWS-KMS
 ├── WP3   Platform Services (split / trim) ................ sandbox-trim / AWS-full
 ├── WP4   CMS Auth scope-trim ............................. seeded-admin passkey only
 │
 └─▶ WP5   Release Verification Matrix ..................... per-profile gate; sandbox row gates v0.1
```

| WP | Doc | Role under the matrix |
|---|---|---|
| **WP0** | this doc | Anchor: vocabulary, lanes, contract, gates, trims, sequence. |
| **WP1S** | [Single-Node Sandbox Lane](DMF%20OSS%20v0.1%20WP1S%20Single-Node%20Sandbox%20Lane%202026-05-25.md) | **First actionable.** The release gate. Lima Debian harness -> generic ARM64 Debian single-node claim. |
| **WP-LAB** | [g2r6-foa9 Reference Delta](DMF%20OSS%20v0.1%20WP-LAB%20g2r6-foa9%20Reference%20Delta%202026-05-25.md) | Reference/regression delta. Not a release profile. |
| **WP1A** | [AWS Provider Profile](DMF%20OSS%20v0.1%20WP1%20AWS%20Provider%20Profile%202026-05-25.md) | Secondary lane. Bannered; Terraform validate-clean, not plan-proven. |
| **WP2** | [Bootstrap Independence](DMF%20OSS%20v0.1%20WP2%20Bootstrap%20Independence%202026-05-25.md) | Split: sandbox-local seed for the gate; KMS/SSM/SNS for AWS. Kiosk = follow-on. |
| **WP3** | [In-Cluster Platform Services](DMF%20OSS%20v0.1%20WP3%20In-Cluster%20Platform%20Services%202026-05-25.md) | Split: sandbox trims Headscale + heavy ntfy; AWS gets in-cluster Headscale/OIDC + ntfy + SNS. |
| **WP4** | [CMS User Administration](DMF%20OSS%20v0.1%20WP4%20CMS%20User%20Administration%202026-05-25.md) | Trim: v0.1 = seeded admin passkey login + backend role guards. Full user-admin → v0.2. |
| **WP5** | [Release Verification and Tagging](DMF%20OSS%20v0.1%20WP5%20Release%20Verification%20and%20Tagging%202026-05-25.md) | Per-profile matrix. Sandbox row gates the tag; AWS row informational unless passed; lab row reference only. |

---

## 7. How this binds the older drafts

- The [Release Mission](DMF%20OSS%20v0.1%20Release%20Mission%202026-05-25.md) is a **superseded draft**. Read it for context only; WP0 binds the sequence.
- WP1–WP5 keep their filenames (stable cross-links) but carry banners re-scoping
  them to the matrix. The original WP1 is retitled **WP1A** in place.
- No code, Terraform, wizard, cert-manager, OpenBao, ntfy, or Headscale defaults
  should be changed to "match v0.1" except along the **WP1S** path. ADR-0031
  is accepted, and the AWS-lane changes proceed under WP1A but do not gate.

## 8. Acceptance / ADR re-acceptance

ADR-0031 is **Accepted** as of 2026-05-26. This doc is the WP0 artifact used for
operator re-acceptance. The operator confirmed:

- [x] The lane matrix (§2) and vocabulary (§1) match operator intent.
- [x] The scope trims (§5) are the right cuts for v0.1.
- [x] WP1S (§6) is the correct first actionable package.

Treat WP0 as the binding plan and WP1S as the active work front.
