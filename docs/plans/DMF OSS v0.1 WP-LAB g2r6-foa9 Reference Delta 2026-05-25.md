---
status: historical
date: 2026-05-25
---
# DMF OSS v0.1 WP-LAB — `g2r6-foa9` Reference Delta

**Status:** Active — reference/regression aid (not a release profile)
**Date:** 2026-05-25
**Author:** Claude (planning sweep, under ADR-0031 framing)
**Anchor:** [WP0 Release Contract & Profile Matrix](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md)
**Related ADR:** [ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md) (Profile 3)
**Profile:** `g2r6-foa9` — **live reference / regression lab, NOT a release profile**

---

## 0. What this doc is (and is not)

This is **not** a release work package. `g2r6-foa9` (the live 3-node Hetzner
CAX21 ARM64 lab) is explicitly preserved as the maintainer's reference and
regression environment. It is **never** release-scrutinized and **never** ships
as a v0.1 profile.

This doc exists for one reason: the lab already proves much of the platform loop
on real ARM64 hardware. It is the richest source of **known-good settings** for
the sandbox lane ([WP1S](DMF%20OSS%20v0.1%20WP1S%20Single-Node%20Sandbox%20Lane%202026-05-25.md)).
WP-LAB records the **delta** between what the lab does and what the sandbox
needs — so we know what to **copy**, what to **trim**, and what to **defer**.

> The lab is the truth for *behavior*. The sandbox is the truth for *the
> release claim*. WP-LAB is the translation table between them.

---

## 1. Purpose

1. Compare live lab behavior against the sandbox requirements (WP0 §3 contract).
2. Identify settings worth copying verbatim into the sandbox profile.
3. Identify lab dependencies that must be trimmed for contributor replicability.
4. Identify behaviors worth deferring (lab-only for now).
5. Serve as a regression reference: when the sandbox misbehaves, diff against the
   lab to localize whether it is a profile-trim artifact or a real bug.

---

## 2. The delta table

| Concern | `g2r6-foa9` (lab) | `sandbox-single-node` (gate) | Action |
|---|---|---|---|
| Nodes | 3-node Hetzner CAX21 ARM64 | 1 ARM64 Debian host | **Trim** to single node. Harvest k3s + role settings that are node-count-agnostic. |
| Storage | Longhorn (replicated) + backup target | `local-path` | **Trim** Longhorn; reuse PVC sizing/class intent where it maps to local-path. |
| Backups | Backblaze B2 object storage | none | **Trim** — reset/rerun is the recovery story. |
| DNS | Cloudflare | local CA + `dmf.test` host mappings | **Trim** Cloudflare; **copy** cert-manager issuer wiring, swap DNS-01→local-CA. |
| TLS | cert-manager (Cloudflare DNS-01) | cert-manager (local CA ClusterIssuer) | **Copy** cert-manager structure; swap issuer. |
| Overlay mesh | external Headscale + Tailscale join | none | **Trim** for sandbox; this is AWS-lane only ([WP1A](DMF%20OSS%20v0.1%20WP1%20AWS%20Provider%20Profile%202026-05-25.md)/[WP3](DMF%20OSS%20v0.1%20WP3%20In-Cluster%20Platform%20Services%202026-05-25.md)). |
| Secrets boot | OpenBao + JuiceFS + Keychain Shamir shares (operator-Mac) | locally-generated seed, documented reset | **Trim** operator-Mac deps; **copy** OpenBao/ESO app wiring. See [WP2](DMF%20OSS%20v0.1%20WP2%20Bootstrap%20Independence%202026-05-25.md). |
| Identity | Authentik (seeded admin + role groups) | same | **Copy** — known-good Authentik config is directly reusable. |
| Console auth | passkey ([ADR-0015](../decisions/0015-dmf-console-passkey-only.md)) | passkey | **Copy** — unchanged. Passkey-only stays. |
| Automation | AWX | AWX (low concurrency, local-path) | **Copy** AWX role; **tune** concurrency/storage per [WP1S §6](DMF%20OSS%20v0.1%20WP1S%20Single-Node%20Sandbox%20Lane%202026-05-25.md). |
| Catalog path | dmf-cms → AWX → `nmos-cpp` | same | **Copy** — this is the loop the lab already proves; harvest the working launcher settings. |
| Monitoring | kube-prometheus-stack (full) | optional / trimmed | **Defer** most; keep minimal debug visibility. |
| Notifications | ntfy / ntfy.sh | optional / stub | **Defer** — sandbox does not gate on notifications. |

---

## 3. Harvest list (copy from lab → sandbox)

Concrete settings to lift, because the lab already has them working on ARM64:

- Authentik seeded-admin + role-group config and OIDC client wiring.
- OpenBao/ESO **application** secret paths and ExternalSecret definitions
  (everything *except* the JuiceFS/Keychain unseal mechanics).
- cert-manager ClusterIssuer structure (swap the solver from Cloudflare DNS-01
  to a local-CA issuer).
- AWX → dmf-cms integration and the `nmos-cpp` catalog launcher settings.
- k3s install flags and role orderings that are independent of node count.

## 4. Trim list (must NOT leak into the sandbox profile)

- Cloudflare credentials / DNS-01.
- Backblaze B2 / object-storage backup targets.
- JuiceFS, Keychain Shamir shares, operator-Mac unseal material.
- External Headscale URL / Tailscale auth keys.
- Any multi-node / Longhorn replication assumption.
- Hetzner-specific inventory and Terraform.

## 5. Defer list (lab-only for v0.1)

- Full kube-prometheus-stack observability.
- ntfy / out-of-band notification paths (sandbox optional/stub).
- Multi-node scheduling and HA OpenBao/raft.

---

## 6. Regression use

When WP1S work hits a failure that looks like a platform bug rather than a
trim artifact:

1. Reproduce the same step on `g2r6-foa9`.
2. If it works on the lab but not the sandbox → the cause is in a **trim** (a
   role made conditional, local-path vs Longhorn, local-CA vs DNS-01). Localize
   there before suspecting the component.
3. If it fails on both → it is a real component/platform bug; fix upstream and
   re-verify on both.

This keeps the sandbox lane from chasing phantom bugs that are really
profile-trim differences.

## 7. Boundaries

- WP-LAB never produces a release artifact, gate, or tag row that counts toward
  v0.1 pass/fail. The lab row in the [WP5](DMF%20OSS%20v0.1%20WP5%20Release%20Verification%20and%20Tagging%202026-05-25.md)
  matrix is **reference only**.
- The lab keeps moving on its own cadence; v0.1 release scrutiny does not apply
  to it (ADR-0031 Profile 3 / Consequences).
- Per the umbrella access rules, the lab env id rotates; the current id lives in
  the umbrella `STATUS.md`, not hardcoded here.
