# DMF OSS v0.1 — Version Manifest (companion)

**Status:** Draft — provisional snapshot 2026-05-26
**Source of truth:** [`dmf-oss-v0.1-version-manifest.yaml`](dmf-oss-v0.1-version-manifest.yaml) (this doc is the human-facing companion; the YAML is canonical)
**Governing ADR:** [ADR-0031 — OSS v0.1 sandbox-and-AWS release-profile matrix](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md)
**Anchor plan:** [WP0 Release Contract & Profile Matrix](../plans/DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md)
**Verification owner:** [WP5 Release Verification and Tagging](../plans/DMF%20OSS%20v0.1%20WP5%20Release%20Verification%20and%20Tagging%202026-05-25.md)

---

## 1. What this is and why it exists

The DMF workspace is an umbrella plus six component repos, with charts, raw
manifests, built images, third-party images, and Ansible collections scattered
across them. Most Helm charts are already pinned, but **release reproducibility
is not yet governed by a single artifact**. Without one, a "release" inherits
the experiment's floating tags and per-role version drift, and nobody can say
precisely *which bytes* a v0.1 tag refers to.

The **version manifest** is that single artifact. It is a machine-readable
bill of materials that:

- pins or explicitly classifies every release-relevant component;
- pins the node **host OS** (family / version / arch) as a release component,
  not an environmental detail;
- records which release **lane** each component belongs to;
- flags every floating ref honestly with a `must_*_before_release` marker
  instead of pretending it is acceptable;
- gives WP5 a concrete, enforceable spec for the release gate.

It is **not a new ADR**. It is WP0/WP5 release discipline *under* ADR-0031.

## 2. Scope and the sandbox-first rule

ADR-0031 makes v0.1 a **profile matrix**, and the manifest mirrors it exactly:

| Lane class | Role in v0.1 | Gates the tag? |
|---|---|---|
| `sandbox-required` | `sandbox-single-node` profile — the **release gate**. | **Yes.** |
| `aws-required` | `aws-arm64-multi-node` secondary lane. | No — informational unless it also passes. |
| `lab-only` | `g2r6-foa9` reference/regression lab. | No — reference only. |
| `optional` | Shippable but not gate-required (e.g. monitoring). | Only if actually shipped in a release lane. |
| `deferred` | Out of v0.1 scope (scaffold/future). | Excluded. |

> **Sandbox-first is binding.** Only the `sandbox-required` row gates v0.1. AWS
> entries exist in the manifest but must not gate the tag unless the AWS row
> itself passes. Lab-only entries are recorded for drift tracking and are never
> a release pass/fail.

A component may carry more than one lane (e.g. cert-manager is both
`sandbox-required` and `aws-required`; the aws-cli backup CronJobs are
`lab-only` + `aws-required` and trimmed out of sandbox entirely).

## 3. What the manifest pins / classifies

See the YAML for exact values. Sections:

1. **Component repos** — `current_observed_ref` is the local HEAD at generation
   time, marked **provisional** (these are not yet release tags). Per ADR-0031
   O6 the umbrella manifest is canonical; public component repos may also carry
   matching `v0.1.0` tags (WP5 Phase 6 picks tag Option A vs B). Private
   `dmf-env` is **not** a public release artifact and is excluded from the tag.
2. **Kubernetes** — k3s `v1.30.6+k3s1`.
   - **Host OS (YAML §2b `host_os`)** — the node base OS is a pinned BOM
     component, not an environmental detail: Debian 12 (bookworm), `linux/arm64`.
     Sandbox-gating; the AWS lane requires a Debian 12 arm64 AMI. ADR-0031
     states the claim as "one ARM64 Debian host."
3. **Upstream Helm charts** — cert-manager, external-secrets, AWX operator,
   Authentik (sandbox+aws); Traefik-private, Loki, Promtail, Grafana,
   Prometheus, LibreNMS (optional/lab).
4. **Local / vendored charts** — dmf-cms `0.9.0`, nmos-cpp `0.1.1`
   (+digest), NetBox wrapper `0.1.0` over upstream `7.3.0` (+lock digest),
   Forgejo vendored `16.0.2` (+lock digest).
5. **Raw manifests** — MetalLB `v0.14.9` (optional), Longhorn `v1.10.1`
   (lab-only; explicitly removed from sandbox in favor of `local-path`).
6. **DMF-built images** — dmf-cms `0.9.0`, awx-ee `0.1.0`, nmos-cpp-registry
   `0.1.0`, nmos-cpp-node `0.1.0` (GHCR → mirrored to cluster Zot).
7. **Third-party images** — pinned (openbao 2.5.2, busybox 1.36) and **floating
   `:latest`** entries flagged `must_pin_before_release: true`.
8. **Ansible collections** — release-lane repo reqs **unpinned** (`dmf-infra`,
   `dmf-runbooks`, `dmf-media`), EE reqs **ranged**, `dmf-central` reqs
   unpinned but deferred; release-lane entries are flagged
   `must_exact_pin_before_release: true`.
9. **Toolchain** — ansible-core, ansible-builder, helm, kubectl, skopeo,
   opentofu — versions to be recorded at the passing verification run.

**Architecture requirement:** every `sandbox-required` and `aws-required`
runtime image must have a `linux/arm64` manifest. Each image carries
`arch_arm64: verify` until WP5 asserts it.

## 4. Gating rules (WP5 enforces)

v0.1 **cannot be tagged** if, for the lane being released, any of these hold
(full list in the YAML `gates.fail_conditions`):

1. A `sandbox-required`/`aws-required` component still carries a floating Helm
   chart, image, or collection ref.
2. The manifest and a role default / playbook value disagree (e.g. the nmos
   seed chart version/digest).
3. A `sandbox-required`/`aws-required` runtime image has no `linux/arm64`
   manifest.
4. A component ref is still `provisional` at tag time without an operator
   waiver.
5. The two k3s pins in `300-k3s.yml` disagree with each other or the manifest.
6. The host OS for the lane does not match `host_os` (family / version / arch):
   the sandbox node is not Debian 12 (bookworm) on `linux/arm64`, or the AWS
   lane is not on a Debian 12 arm64 AMI.

Only the **sandbox row** blocks the tag. The AWS row joins the tag if it
passes; otherwise it slips to v0.2 with no release penalty. The lab row is
reference only.

## 5. Update process

The manifest is hand-maintained for v0.1 (no generator script yet — see §7).

1. **When a pinned version changes** in a role default, playbook, chart, or
   image ref, update the corresponding manifest entry in the same change set.
   The manifest and the source must not drift — WP5 fails on disagreement.
2. **When a floating ref is pinned**, set `must_pin_before_release: false` (or
   remove the flag) and record the immutable tag/digest. Remove the matching
   `known_gaps` entry.
3. **When a component repo is tagged** for release, replace
   `current_observed_ref` with the tag and set `provisional: false`.
4. **At the passing verification run**, WP5 fills in `gates.passing_record`
   (per-lane SHAs, image digests, verification env id) and the `toolchain`
   versions.
5. Keep the `known_gaps` list current: add new gaps as they surface, delete
   them as they are fixed.

## 6. Current known gaps

These are the exact, current gaps the Codex sweep surfaced (full detail in the
YAML `known_gaps`). Recorded here so they are not lost:

| Gap | Severity | Disposition |
|---|---|---|
| **nmos seed chart fallback** — `630-zot-seed-platform.yml:105,106` fallback defaulted to `0.1.0` + stale digest `sha256:4de2...` vs live `0.1.1` / `sha256:827b...` | ~~release-blocker~~ → **patched (2026-05-26)** | Tactical patch landed: fallback now `0.1.1` / `sha256:827bce...` (dmf-infra `b644c3a`), so the tree is no longer knowingly wrong. **Residual (WP5 must enforce):** the manifest, `dmf-media` Chart.yaml, `awx-integration` defaults, `630-zot-seed-platform.yml`, `dmf-runbooks/playbooks/launch-nmos-cpp.yml`, and the published OCI digest must all agree; future hardening may remove the fallback entirely so an unset version/digest fails loudly. |
| **Floating third-party images** — valkey, curl (x2), nginx:alpine, python, openbao-raft-snapshot, aws-cli (x4), skopeo all on `latest`/floating | release-blocker per lane | Pin to digest/version before the relevant lane passes WP5. |
| **OpenBao image inconsistency** — server pinned `2.5.2`, raft-snapshot CronJob on `latest` | medium | Align both to one pinned version. |
| **Unpinned/ranged Ansible collections** — release-lane repo reqs unpinned (`dmf-infra`, `dmf-runbooks`, `dmf-media`); EE reqs ranged; `dmf-central` unpinned but deferred | release-blocker | Exact-pin all release-lane entries before release. |
| **dmf-cms runtime version resolution** — image tag read from sibling `VERSION` at runtime | medium | Release installs must resolve the tag through this manifest. |
| **k3s double-pin** — `k3s_version` duplicated in `300-k3s.yml` | low | Agree now; WP5 fails on divergence. |
| **EE requirements duplication** — `ee/requirements.yml` + `ee/context/_build/requirements.yml` | low | Keep in lockstep. |
| **NetBox/Forgejo sandbox necessity** | scope-open | WP1S to confirm whether the single-node reference deploy needs the SoT + automation repos or can trim them. |

## 7. Enforcement status

There is **no verifier script yet** (operator decision 2026-05-26: spec the
checks, defer the script to WP5 which owns verification). The manifest is
machine-readable so a future WP5 checker can parse it and enforce
`gates.fail_conditions`. Until then the gate is a documented checklist (this
doc + the WP5 plan).
