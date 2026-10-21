# ADR-0031: OSS v0.1 release-profile matrix

**Status:** Accepted (2026-05-26; operator open decisions closed; WP0 successor plan drafted —
[DMF OSS v0.1 WP0 Release Contract and Profile Matrix 2026-05-25](../plans/DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md);
premise basis: [Contributor Replicability Premise Pass 2026-05-25](../plans/DMF%20OSS%20v0.1%20Contributor%20Replicability%20Premise%20Pass%202026-05-25.md)).
**Date:** 2026-05-25 (original draft); 2026-05-25 (rewritten as profile matrix)
**Deciders:** @<handle>, Codex planning sweep, Claude CEO-mode review, Codex sequencing review
**Specializes:** [ADR-0020](0020-deployment-scope-and-regulatory-posture.md)
Mode A, [ADR-0018](0018-self-managed-k3s-not-ack.md),
[ADR-0026](0026-provider-descriptors.md)
**Touches:** [ADR-0011](0011-auto-unseal-tradeoff.md),
[ADR-0015](0015-dmf-console-passkey-only.md),
[ADR-0028](0028-identity-and-authority-chain.md),
[ADR-0030](0030-console-i18n-and-airgap-posture.md)
**Filename note:** this file was renamed on 2026-05-25 from
`0031-oss-v0-1-aws-self-contained-release-profile.md` to reflect the
current draft shape: sandbox release gate plus AWS secondary lane under a
release-profile matrix. The historical AWS-only draft is preserved in the
[archive record](../archive/decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md#historical-draft-superseded-by-current-decision--preserved-for-context-not-binding) but is not binding.

## Context

The platform is currently broad enough to prove experiments but too broad for
a credible first OSS release. A greenfield environment as installed by the
maintainer touches Hetzner/Aliyun compute, Cloudflare DNS, Backblaze B2 object
storage, external Headscale, public ntfy.sh, local OpenBao seed/unseal
material, and operator-laptop state. That sprawl conflicts with ADR-0020 Mode
A's self-host promise and makes the first public release hard to install,
explain, or verify for someone who is not the maintainer.

The release question is not whether DMF should eventually support multiple
providers — it should, per ADR-0026 — and it is not solely "which single
cloud profile becomes the v0.1 contract." The CEO-mode review surfaced that
the more useful frame is:

- What is the **release experience** a contributor encounters?
- Which **provisioning lanes** honor that experience?
- What does v0.1 **claim** and what does it explicitly not claim yet?

Those three questions, answered together, produce a release-profile matrix
rather than a single-provider contract.

## Decision

DMF OSS v0.1 ships as a **release-profile matrix** organized around one
canonical workflow contract, with two named provisioning lanes and an
explicit lab/reference profile that is **not** a release.

### Canonical workflow contract (honored by every release profile)

Every v0.1 release profile must support, end to end, this contributor
experience:

1. Clone repo and install documented prerequisites.
2. Provide a small profile manifest (provider/profile-specific fields plus
   common fields).
3. Provision or bind one ARM64 host/node set per the chosen profile.
4. Bootstrap k3s and core platform services.
5. Log in as the seeded admin.
6. Deploy one reference catalog item / workload end to end.
7. Verify alerts / auth / storage / ingress to the level the profile claims.
8. Rerun the workflow idempotently from the same manifest.
9. Reset or teardown cleanly.

Steps that vary by profile (DNS, TLS source, object storage, secret-boot
posture, notification path, overlay mesh) are encoded as profile-specific
manifest fields; the workflow itself stays uniform.

### Profile 1 — `sandbox-single-node` (v0.1 release gate)

The primary v0.1 release profile and the default docs path. This is the
profile that gates whether v0.1 can be tagged.

- One ARM64 Debian host: local VM, cheap VPS, or bare metal. No multi-node
  assumption.
- **No required dependence** on Cloudflare, Backblaze B2, Hetzner-specific
  credentials, Tailscale, external Headscale, public `ntfy.sh`, or the
  maintainer's Mac / JuiceFS / Keychain unseal material.
- DNS/TLS posture: local CA plus explicit host mappings under a reserved
  `.test` sandbox domain (default `dmf.test`). User-owned DNS + ACME
  DNS-01 is an optional production-shaped escape hatch, not the sandbox
  release gate.
- Bootstrap independence: locally generated bootstrap material, documented
  reset procedure. No private operator inventory required.
- Seeded admin can log in. One reference catalog deploy works. Idempotent
  rerun + documented teardown.
- v0.1 **cannot** be tagged unless this profile passes the verification
  matrix from a fresh clone.

### Profile 2 — `aws-arm64-multi-node` (secondary lane, eligible-if-ready)

Parallel work. Eligible for inclusion in the v0.1 tag **only if it catches
up without delaying the sandbox lane**. Not gating.

- ARM64 EC2 (Graviton) baseline per ADR-0018; self-managed k3s, not EKS.
- Route53 for DNS, S3 for object storage, SNS for out-of-band alerts,
  AWS KMS for OpenBao auto-unseal, NLB/SSM as needed.
- In-cluster Headscale wired to Authentik/OIDC, exposed at
  `hs.<base_domain>`, sequenced after base cluster readiness.
- In-cluster ntfy at `ntfy.<base_domain>`.
- This profile may use AWS KMS auto-unseal as its release-default boot
  posture. The sandbox profile is **not** required to do so.

### Profile 3 — `<env>` and successors (live lab / regression reference)

Explicitly preserved as the maintainer's live lab and regression reference.
**Not** a release profile.

- Allowed to depend on operator-specific credentials, JuiceFS, Keychain
  shares, Cloudflare, B2, Tailscale, external Headscale, and any other
  maintainer infrastructure.
- Purpose: validate architecture under real provider conditions, exercise
  ADR-0028 / ADR-0024 / ADR-0021 / ADR-0011 / ADR-0015 / ADR-0030
  end-to-end, surface bugs and architectural smells the generic profiles
  will not see.
- Findings from the lab feed the generic profiles; the lab itself is never
  packaged as a profile.
- Removing the "release contract" expectation from this profile is a
  deliberate consequence of this ADR.

### Claim split — what v0.1 says and does not say

Release-fitness claims:

- **v0.1 sandbox claim:** DMF can be installed, operated, authenticated, and
  used end-to-end by a contributor on commodity infrastructure, without
  maintainer-specific credentials.
- **v0.1 AWS multi-node claim (if shipped):** the deployment architecture
  scales beyond one node on a major public cloud, keeping the future
  production shape reachable.

Explicitly **not** claimed by v0.1 in any profile:

- Production ST-2110 / PTP / multicast / NIC-isolation correctness.
- Real-time media plant behavior.
- Multi-tenant / Mode B / customer-managed posture.
- Enterprise RBAC, policy administration, or audit retention guarantees.
- Geographic redundancy, DR, or backup-restore SLOs.
- Performance / capacity numbers under load.

Media-realism validation is a later profile (`media-realism-multi-node` or
similar) with explicit data-plane testbed assumptions. v0.1 does not gate on
it.

### Common gates (every release profile)

1. Fresh install reproducible from public docs + public repo only.
2. No maintainer-specific credentials or private inventory required.
3. `linux/arm64` image availability for every workload shipped in the profile.
4. Seeded admin login works through the DMF Console passkey-only flow
   (ADR-0015). TOTP / SNS-backed OTP may support non-console,
   break-glass, or profile-specific step-up flows, but do not satisfy
   the console login gate.
5. One reference catalog item / workload deploys end to end.
6. Idempotent rerun from the same manifest.
7. Reset / teardown documented and tested.
8. No hardcoded operator paths, domains, IPs, or secrets in release
   artifacts.

Profile-specific gates (Route53/S3/SNS/KMS for AWS; local DNS/TLS for
sandbox; in-cluster Headscale + ntfy for AWS multi-node) live in the
WP5-successor verification matrix.

### What this ADR replaces and does not replace

Replaces:

- The earlier "AWS self-contained release profile" Decision of this ADR
  (preserved in the [archive record](../archive/decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md#historical-draft-superseded-by-current-decision--preserved-for-context-not-binding) and no longer binding).
- The implicit assumption in the Mission + WP1–WP5 plans (all dated
  2026-05-25, all currently draft) that v0.1 = AWS replatform. Those
  plans must be re-scoped to the matrix before they bind code changes.

Does **not** replace or deprecate:

- The current Hetzner-based architecture and live lab.
- ADR-0028 (Identity and Authority Chain), ADR-0024, ADR-0021, ADR-0011,
  ADR-0015, or ADR-0030. All remain in force; v0.1 is *additive*, not a
  rewrite.
- The long-term multi-provider direction (ADR-0026). This ADR makes that
  direction structurally easier by establishing "profiles as lanes under
  one contract" as the v0.1 pattern.
- Mode A (ADR-0020). Both v0.1 profiles are expressible under Mode A.

### Closed operator decisions (2026-05-25)

| # | Decision | Close-out |
|---|---|---|
| O1 | DNS/TLS posture for `sandbox-single-node` | Sandbox default is a generated local CA plus explicit host mappings for a reserved `.test` domain (default `dmf.test`). The installer / docs must help the operator trust the CA on the browser/admin client. Do not use `.local`. User-owned DNS + ACME DNS-01 remains an optional escape hatch for contributors who want production-shaped TLS; it is not the sandbox release gate. |
| O2 | Reference catalog item for v0.1 | Use `nmos-cpp` registry + mock nodes as the v0.1 happy-path catalog item. Gate on chart deploy through the catalog path, health probe success, lifecycle state transition, and teardown. This validates the catalog/operator loop only; it does not claim ST-2110/PTP/media-plane correctness. |
| O3 | Headscale in `sandbox-single-node`? | Not required for the sandbox release gate. Sandbox-local communication is sufficient. Headscale remains mandatory for `aws-arm64-multi-node`, must be wired to Authentik/OIDC, and must be exposed as `hs.<base_domain>`. |
| O4 | MFA posture by profile | Keep ADR-0015 firm: DMF Console is passkey-only. The sandbox gate requires seeded admin passkey enrollment/login and has no SMS/SNS/OTP dependency. AWS may add SNS-backed alerting or step-up/fallback paths, but SNS/OTP is never primary console auth. Any TOTP fallback for the DMF Console would require amending ADR-0015. |
| O5 | Provider Descriptors (ADR-0026) timing | Do not gate v0.1 on full ADR-0026 implementation. WP0 defines an inline v0.1 profile manifest shaped for later descriptor migration. Existing descriptor work can be reused opportunistically; descriptor generalization is v0.2 unless it becomes trivial during WP0/WP1S. |
| O6 | Release artifact granularity | The umbrella release manifest is canonical. It records included public component repo tags/SHAs, image/chart digests, and profile pass/fail results. Public component repos may also carry matching release tags. Private `dmf-env` is not a public release artifact; OSS sample manifests/templates must live in public docs or public infra/template locations. |

## Consequences

- **Positive** — v0.1 has a defensible single canonical *experience*, with a
  low-friction default lane that matches the actual operator-stated persona
  (trusted friends, GitHub-discovery contributors, possible vlog audience,
  self-hosted single-node sandbox as near-term goal).
- **Positive** — The Hetzner lab (`<env>` and successors) is freed from
  the contradictory expectation of being both the experimental playground and
  the release contract. The lab keeps moving; v0.1 release scrutiny does not
  apply to it.
- **Positive** — AWS work continues without being a release gate. If the AWS
  lane catches up by v0.1 tag time, it ships; if not, it lands in v0.2 with
  no ADR-level shame.
- **Positive** — Claim-split discipline prevents v0.1 from over-promising
  media-realism or production characteristics it does not yet exercise.
- **Positive** — ADR-0011's auto-unseal trade-off resolves per-profile.
  Sandbox can keep simpler local-unseal (or adopt the tiered-unseal posture
  once that ADR lands). AWS profile may use KMS.
- **Positive** — ADR-0026 (Provider Descriptors) gets a concrete first use
  case: the manifest fields and profile-specific fields become first-class
  deliverables. Full descriptor implementation is not a v0.1 gate.
- **Positive** — ADR-0020 Mode A becomes easier to enforce: both v0.1
  profiles are demonstrably self-host and demonstrably independent of
  `dmfdeploy.io` services.
- **Negative** — Two install lanes is more documentation and verification
  work than one. The "common gates / profile-specific gates" structure is
  harder to keep coherent than a single flat gate list.
- **Negative** — The AWS lane no longer has the ADR-locked "release-only"
  status the original draft of this ADR gave it. It may slip without a
  clear release penalty. Mitigation: WP1A still gets resources, just not
  release-gating ones.
- **Negative** — Some content from the original AWS-only draft (SNS as
  universal alert path, KMS as universal unseal posture, Headscale as
  mandatory across all profiles, CMS user-admin as universal gate) is
  downgraded to profile-specific or trimmed.
- **Neutral** — ADR-0030's runtime-self-contained rule still applies to
  every profile.
- **Neutral** — The Authentik identity authority (ADR-0028) is unchanged.
  v0.1 profiles ship a seeded admin and the minimum role guards; the full
  user-administration product surface (signup, invite, approval queue,
  role-assignment UI, lifecycle management) is out of v0.1 scope unless it
  is already nearly-complete by tag time.

### Enforcement (to be elaborated in WP0)

The original Enforcement section was AWS-specific and is preserved in the
[archive record](../archive/decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md#historical-draft-superseded-by-current-decision--preserved-for-context-not-binding). Generic enforcement under the matrix framing:

- `init-wizard.sh` and the future Python wizard must expose
  `sandbox-single-node` as the default install path and
  `aws-arm64-multi-node` as an explicit alternative. Neither requires
  Cloudflare, B2, Hetzner-specific creds, external Headscale, or public
  `ntfy.sh`.
- Release docs and quickstarts must lead with the sandbox profile. AWS
  docs must be clearly labeled as the "production-shaped lane; requires
  AWS account."
- The v0.1 verification harness (WP5 successor) must produce a per-profile
  pass/fail matrix, not a single boolean. v0.1 cannot be tagged unless the
  sandbox profile row passes. The AWS row is informational unless it also
  passes, at which point it joins the release tag.
- The v0.1 release manifest must record which profiles passed and at what
  component SHAs.
- No release-facing artifact may claim "DMF runs on AWS" or "DMF runs on
  any single-node Debian host" without the verification matrix backing it.
- No release-facing artifact may claim production media-plane validation
  unless a future profile explicitly exercises it.

## Status

Accepted (2026-05-26; operator open decisions closed; WP0 successor plan drafted:
[DMF OSS v0.1 WP0 Release Contract and Profile Matrix 2026-05-25](../plans/DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md);
premise basis: [Contributor Replicability Premise Pass 2026-05-25](../plans/DMF%20OSS%20v0.1%20Contributor%20Replicability%20Premise%20Pass%202026-05-25.md)).

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md).
