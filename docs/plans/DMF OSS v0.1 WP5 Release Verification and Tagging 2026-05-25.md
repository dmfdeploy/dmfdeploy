---
status: superseded
date: 2026-05-25
superseded_by: "DMF v0.1 Commitment & 30-Day Focus-Cut Plan 2026-06-06.md"
---
# DMF OSS v0.1 WP5 - Release Verification and Tagging
> **Superseded by** [DMF v0.1 Commitment & 30-Day Focus-Cut Plan 2026-06-06.md](DMF%20v0.1%20Commitment%20%26%2030-Day%20Focus-Cut%20Plan%202026-06-06.md) (adjudicated 2026-06-11, refs
> issue #32 WP5): [architectural-commitments-v1](../decisions/architectural-commitments-v1.md)
> re-cut v0.1 — the sandbox lane's proven core stands, the AWS/profile-matrix
> sequencing is dropped (cloud claims are a named non-goal), and the remaining
> gate (stranger-reproducibility) is carried by the successor plan (issue #36).

> **⚠️ RE-SCOPED (2026-05-25): per-profile matrix, not one flat AWS list.** Under
> [WP0](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md) /
> [ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md),
> verification produces a **matrix with one row per profile**:
> - **`sandbox-single-node` row — GATES v0.1.** The tag is blocked unless this
>   row passes from a fresh clone. Source list: [WP1S §8](DMF%20OSS%20v0.1%20WP1S%20Single-Node%20Sandbox%20Lane%202026-05-25.md).
> - **`aws-arm64-multi-node` row — informational** unless it also passes, at
>   which point it joins the release tag. Never blocks.
> - **`g2r6-foa9` row — reference only.** Not a release pass/fail.
> - Add a **`linux/arm64` image-availability gate** (every shipped image has an
>   arm64 manifest) and a **sandbox resource/memory sanity** check (AWX kept and
>   running at low concurrency, Longhorn removed, `local-path` in use).
> - DMF Console verification asserts **passkey** login ([ADR-0015](../decisions/0015-dmf-console-passkey-only.md)), not TOTP.
>
> The single matrix in §4 below was written as a flat AWS list; treat it as the
> **AWS-row** seed and add the sandbox + lab rows + arm64/resource gates.

**Status:** Active — per-profile verification matrix (sandbox row gates the tag)
**Date:** 2026-05-25
**Anchor:** [WP0 Release Contract & Profile Matrix](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md)
**Parent mission (superseded):** [DMF OSS v0.1 Release Mission 2026-05-25.md](DMF%20OSS%20v0.1%20Release%20Mission%202026-05-25.md)
**Outcome:** v0.1 is verified by a **per-profile matrix** — the sandbox row gates
the tag, the AWS row is informational-unless-passed, the lab row is reference —
then documented and tagged as a coherent multi-repo release.

---

## 1. Problem

The workspace is an umbrella plus component repos. That is useful during
development, but a public release needs a precise, repeatable answer to:

- Which SHAs are in the release?
- Which install path is supported?
- Which tests and smoke checks passed?
- Which providers are release-supported?
- Which roadmap features are intentionally excluded?

Without a verification and tagging package, the release will inherit the
current experiment sprawl.

---

## 2. Goals

1. Define the v0.1 release gate checklist.
2. Run a greenfield AWS install from documented inputs.
3. Run an idempotent second pass.
4. Verify DNS, TLS, S3, SNS, OpenBao recovery, ntfy, CMS MFA/authz, and
   catalog launch.
5. Produce a release manifest that pins component SHAs.
6. Update public-facing docs to point at the AWS-only release path.
7. Tag the umbrella and/or component repos consistently.

---

## 3. Non-Goals

- Building CI/CD for every future release shape.
- Certifying legacy provider paths.
- Publishing managed service artifacts.
- Exhaustive security audit beyond the v0.1 release gates.

---

## 4. Release Verification Matrix

| Area | Required check |
|---|---|
| Provider | Fresh AWS environment provisions from documented inputs. |
| DNS/TLS | Route53 records exist; cert-manager issues valid certs. |
| Object storage | S3 buckets exist; write/read smoke passes. |
| SNS | Platform/security alert topic exists; publish smoke passes. |
| OpenBao | Bootstrap completes; reboot/restart recovery passes. |
| Secrets | ESO/app secrets converge after bootstrap and after restart. |
| ntfy | `ntfy.<base_domain>` and in-cluster publish/subscribe smoke pass. |
| Headscale | `hs.<base_domain>`, Authentik/OIDC config, node registration, and cleanup pass without external Headscale. |
| CMS users | Admin invite/approve/assign role/disable flow works. |
| CMS MFA | Admin or privileged action requires approved second factor; SNS fallback works if enabled. |
| CMS authz | Viewer cannot perform operator/admin actions. |
| Catalog | Initial reference workflow deploys and tears down. |
| Idempotency | Second full run is clean or produces only expected no-op changes. |
| Docs | Quickstart matches the actual release path. |
| Hygiene | Public repo release checks pass. |
| **Version manifest — refs** | No `sandbox-required`/`aws-required` component (for the lane being released) carries a floating Helm chart, image, or Ansible-collection ref. All `must_pin_before_release` / `must_exact_pin_before_release` flags are cleared for that lane. |
| **Version manifest — drift** | The manifest agrees with every role default / playbook value it cites (e.g. nmos seed chart version/digest; the two k3s pins in `300-k3s.yml`). Fail on any disagreement. |
| **Version manifest — arch** | Every shipped `sandbox-required`/`aws-required` runtime image has a `linux/arm64` manifest (`arch_arm64: confirmed`). |
| **Version manifest — refs pinned** | No `component_repos[].current_observed_ref` is still `provisional` at tag time without an explicit operator waiver. |

### 4.1 Sandbox-row result — `imc1-cyh4`, 2026-05-29 (machine path PASS)

First execution of the sandbox row, on a fresh cold rollout (Lima Debian VM +
wizard env). **Machine path PASS:** fresh bootstrap (pre-seed 309/0, seed-bao
clean, post-seed 281/0, configure 685/0); the `nmos-cpp` catalog loop
(deploy → health → lifecycle → teardown) runs **end-to-end, offline, attributed
to `dmf-cms-svc`** over multiple cycles; AWX single-node fit verified (web
1178Mi / task 1040Mi, node ~76% with the full stack, 0 OOMKills); Longhorn
absent, `local-path` in use; EE pinned `awx-ee:0.1.1`
(`sha256:867faa97ed7391befe599ca0ad96fab1f6dfeeddb25b542c79229b6434ee9b51`).

Outstanding before the row is a full PASS:
- A formal **fresh-clone-by-a-non-maintainer** run (this was maintainer-driven).

Resolved since first run:
- **Passkey browser-Console catalog path** (gate item 2) — **operator-confirmed
  end-to-end on imc1-cyh4 2026-05-29** (human → browser → Console → AWX
  deploy/teardown, attributed to `dmf-cms-svc`).
- CMS deploy/teardown **double-launch guard** shipped in dmf-cms `0.9.2`
  (backend idempotency + frontend in-flight gate; verified on imc1-cyh4).

Follow-up logged (not gating): **deploy↔finalise race** — near-simultaneous
opposite actions race (different JTs, not covered by the same-action dedup);
fix = per-entry cross-action lock. See WP1S §8.1.

Findings + fixes are catalogued in
[WP1S §8.1](DMF%20OSS%20v0.1%20WP1S%20Single-Node%20Sandbox%20Lane%202026-05-25.md#81-proven-on-imc1-cyh4-2026-05-29--machine-path--findings).
The §4 matrix above remains the AWS-row seed.

---

## 5. Implementation Phases

### Phase 1 - Release manifest format

**Status: the manifest exists.** A draft machine-readable manifest and its
human companion already live in the umbrella repo (created 2026-05-26 under
ADR-0031 / WP0 §4.3):

- **Source of truth:** [`docs/releases/dmf-oss-v0.1-version-manifest.yaml`](../releases/dmf-oss-v0.1-version-manifest.yaml)
- **Companion:** [`docs/releases/DMF OSS v0.1 Version Manifest.md`](../releases/DMF%20OSS%20v0.1%20Version%20Manifest.md)

The manifest records release version, lane classification, component repo refs
(currently provisional HEADs), k3s version, every Helm chart / local chart /
raw manifest / DMF-built image / third-party image / Ansible collection, the
`linux/arm64` requirement, the gate fail-conditions, and a live `known_gaps`
list. WP5 must keep it current and fill `gates.passing_record` (per-lane SHAs,
image digests, verification env id) plus `toolchain` versions at the passing
run.

**Build the verifier here.** Phase 1 implementation work is the WP5-owned
checker that parses the manifest and enforces `gates.fail_conditions` (the four
"Version manifest — *" matrix rows in §4): fail on floating chart/image/
collection refs for the released lane, fail on manifest↔role-default
disagreement, fail on missing `linux/arm64`, fail on still-provisional refs.
No verifier script was written when the manifest was created (operator decision
2026-05-26: spec now, script in WP5).

For the `nmos-cpp` reference chart specifically, the agreed v0.1 path is:
first do the tactical fix in `630-zot-seed-platform.yml` so its fallback
version/digest matches the current chart (`0.1.1` /
`sha256:827bce1a0a769bd996033232d178ad1b057879f4619d8ef17ca1281903bd5ba0`),
then have the WP5 verifier fail unless all nmos chart sources agree: the
version manifest, `dmf-media/charts/nmos-cpp/Chart.yaml`,
`awx-integration/defaults/main.yml`, `630-zot-seed-platform.yml`,
`dmf-runbooks/playbooks/launch-nmos-cpp.yml`, and the published OCI chart digest
where reachable. Future hardening may remove the fallback entirely so unset
chart version/digest fails loudly.

Acceptance:

- A reader can reproduce which code was tested and tagged.
- The verifier fails a release attempt that violates any `gates.fail_condition`
  for the lane being released.

### Phase 2 - Verification command set

Define the exact commands for:

- Init wizard / environment generation.
- Terraform/OpenTofu plan/apply.
- Bootstrap provision.
- Configure.
- Verify.
- CMS test suite.
- Infra syntax/idempotency checks.
- Public release hygiene checks.

Acceptance:

- The release process is command-driven, not handwave-driven.

### Phase 3 - Greenfield AWS run

- Create a fresh AWS environment.
- Run the release bootstrap path.
- Capture failures and fix them in the relevant WP.
- Avoid accepting manual console edits as release fixes.

Acceptance:

- A full install succeeds from scratch.

### Phase 4 - Idempotency and recovery

- Rerun the full playbook path.
- Reboot or restart selected nodes/pods.
- Verify OpenBao recovery posture.
- Verify ESO/app convergence.
- Verify ntfy, CMS, and catalog behavior after recovery.
- Verify SNS alert publishing and MFA/OTP delivery where enabled.

Acceptance:

- The system behaves like an appliance, not a one-shot demo.

### Phase 5 - Docs and release notes

Update:

- Root README or release entrypoint.
- AWS quickstart.
- Provider scope note.
- Known exclusions.
- User admin docs.
- Recovery docs.
- Contribution/release hygiene docs if affected.

Acceptance:

- New operators are not directed toward Cloudflare/B2/Hetzner/Aliyun for the
  v0.1 path.

### Phase 6 - Tagging

Decide and execute one tagging model:

Option A:

- Tag each public component repo with `v0.1.0`.
- Tag the umbrella with `v0.1.0`.
- Release manifest records the exact component SHAs.

Option B:

- Tag only the umbrella.
- Release manifest pins component SHAs.
- Component repos remain individually versioned later.

Recommended: Option A if all component repos are public-facing and coherent at
release time; otherwise Option B for the first cut.

Acceptance:

- There is one canonical v0.1 release reference.

---

## 6. Dependencies

- WP1 must produce the AWS provider path.
- WP2 must produce the final boot/recovery posture.
- WP3 must deliver and verify in-cluster ntfy, SNS consumption, and Headscale
  OIDC/registration.
- WP4 must complete CMS user lifecycle and authz tests.

---

## 7. Risks

- Tagging before verification will freeze an experiment, not a release.
- Multi-repo tags can drift if the manifest is not treated as canonical.
- Docs can accidentally preserve stale provider instructions. Include an
  explicit provider-sprawl sweep before tagging.

---

## 8. Done Definition

WP5 is done when the v0.1 manifest exists, the AWS greenfield install and
idempotency pass are complete, release docs match reality, and the chosen tag
model has been applied.
