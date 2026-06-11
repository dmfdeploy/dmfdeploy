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
release-profile matrix. The historical AWS-only draft is preserved below
but is not binding.

> **Trajectory note (2026-05-25):**
>
> 1. **Original draft (2026-05-25 morning):** Codex planning sweep filed this
>    ADR as Accepted under the title "OSS v0.1 uses an AWS self-contained
>    release profile." The Decision section mandated AWS as the only supported
>    v0.1 provider profile and demoted all non-AWS providers to experimental.
> 2. **CEO-mode review (2026-05-25 afternoon):** Claude (Opus) reviewed the
>    drafted Mission + WP1–WP5 from a CEO perspective, surfaced premise
>    concerns, and demoted this ADR to Proposed. Operator clarified the actual
>    v0.1 goal: contributor-replicable single-node sandbox for trusted
>    friends, GitHub-discovery, and a possible vlog audience, with AWS
>    multi-instance also deemed fairly attainable.
> 3. **Codex sequencing review (2026-05-25 afternoon):** Codex consulted via
>    agent-bridge, agreed with the demotion, sharpened the framing into
>    "canonical workflow contract with profile lanes," and split the v0.1
>    claim into release-fitness (sandbox) and substrate-scale-readiness (AWS
>    multi-node).
> 4. **Current draft (this file):** rewrites the Decision around the
>    profile matrix. The earlier AWS-only Decision content is preserved
>    verbatim at §"Historical draft" below for context; it is **not
>    binding**.
>
> This ADR was re-accepted on 2026-05-26 after the operator confirmed the
> WP0 lane matrix, scope trims, and WP1S-first sequence.

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

### Profile 3 — `g2r6-foa9` and successors (live lab / regression reference)

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
  (preserved at §Historical draft below, not binding).
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
- **Positive** — The Hetzner lab (`g2r6-foa9` and successors) is freed from
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

## Alternatives considered

- **Keep AWS-only as the v0.1 release contract.** (Previous draft of this
  ADR.) Rejected. Misaligned with the operator's homelabber/contributor/
  vlog persona, demands AWS account + IAM + Route53 + KMS literacy as a
  precondition for trying DMF, and unnecessarily demoted the live Hetzner
  lab.
- **Use the live Hetzner lab as the v0.1 release.** Rejected. The lab
  depends on operator-specific credentials, JuiceFS, Keychain shares, and
  external Headscale — none of which are contributor-replicable. The lab
  remains useful as Profile 3 (reference, not release).
- **Three or more equal-weight v0.1 profiles** (sandbox + AWS + Hetzner +
  Aliyun, etc.). Rejected. Fragments documentation, dilutes verification
  effort, increases the "which one do I actually try?" friction the OSS
  release is meant to remove.
- **Sandbox-single-node only; defer AWS multi-node to v0.2 entirely.**
  Considered. Acceptable as a fallback if AWS lane slips, but the operator
  has already invested in the AWS path and Codex's read is that AWS
  multi-node is "fairly attainable" in parallel. So: parallel-with-sandbox-
  as-gate, not exclusive.
- **Defer v0.1 framing entirely until ADR-0026 (Provider Descriptors)
  lands.** Considered. Rejected because the matrix framing gives ADR-0026
  a concrete first use case; deferring forecloses that and leaves v0.1
  framing in limbo.
- **Adopt EKS for the AWS lane.** Rejected by ADR-0018. Self-managed k3s
  remains the architecture across all profiles.

## Enforcement (to be elaborated in WP0)

The original Enforcement section was AWS-specific and is preserved at
§Historical draft below. Generic enforcement under the matrix framing:

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

## Acceptance record

This ADR is **Accepted** as of 2026-05-26. The 2026-05-25 morning
"Accepted" markers from the original AWS-only draft were voided because
the underlying release-contract framing changed materially; the current
accepted record is the profile-matrix decision above.

Re-acceptance criteria met:

- [x] The canonical workflow contract (the nine-step experience above) is
  correct and binding for every v0.1 profile.
- [x] `sandbox-single-node` is the v0.1 release gate; v0.1 tag is blocked
  on this profile passing the verification matrix.
- [x] `aws-arm64-multi-node` is the secondary lane; eligible for v0.1
  inclusion if ready, never gating.
- [x] `g2r6-foa9` and successor labs are lab/regression reference, not
  release profiles, and are exempt from v0.1 release scrutiny.
- [x] Open decisions O1–O6 are closed (DNS/TLS, reference catalog,
  sandbox Headscale, MFA-by-profile, ADR-0026 timing, release artifact
  granularity). Close-outs recorded 2026-05-25 in §Closed operator
  decisions.
- [x] WP0 (Release Contract & Profile Matrix) is drafted as a successor /
  replacement to the current draft Mission + WP1–WP5 plan set
  ([DMF OSS v0.1 WP0 Release Contract and Profile Matrix 2026-05-25](../plans/DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md);
  WP1S/WP-LAB added, Mission + WP1→WP1A/WP2–WP5 bannered to the matrix).
- [x] Operator re-accepted the ADR on 2026-05-26 against the drafted WP0.

---

## Historical draft (superseded by current Decision — preserved for context, NOT binding)

The text below was the original 2026-05-25 morning draft of this ADR, which
was filed as Accepted before the CEO-mode and Codex sequencing reviews. It
is retained here so that the design rationale and the prior alternative
analysis are not lost. Nothing in this section is binding on code,
infrastructure, or release artifacts.

### Historical Decision

DMF OSS v0.1 ships one supported release profile: **Mode A self-host on AWS,
using self-managed k3s on EC2, Route53 for DNS, S3 for object storage, SNS for
out-of-band alerts and optional OTP delivery, and AWS KMS for OpenBao
auto-unseal**.

For the v0.1 release path:

- AWS is the only supported cloud provider profile.
- k3s remains self-managed on EC2; EKS is not part of the release profile per
  ADR-0018.
- Route53 is the DNS provider and cert-manager DNS-01 integration.
- S3 is the object storage target for audit/archive/snapshot/app-backup uses.
- SNS is the provider-native out-of-band alert path and may deliver OTP/SMS or
  email fallback for MFA flows, but SMS/OTP is not the sole admin security
  posture.
- OpenBao uses AWS KMS auto-unseal for the release profile. The legacy
  operator-local automation-quorum path accepted by ADR-0011 remains
  experiment debt and is not release-compliant for v0.1.
- Authentik remains the human identity authority. Passkeys or TOTP are the
  preferred second factors; SNS-backed OTP is fallback or step-up only.
- ntfy is deployed in-cluster for cluster-local/application notifications and
  exposed at `ntfy.<base_domain>` for browser/mobile clients and external
  subscribers.
- Cloudflare, Backblaze B2, Hetzner, Aliyun, public ntfy.sh, external
  Headscale, and dmfdeploy.io services are not required by the v0.1 release
  path.
- Headscale is mandatory for v0.1 and must run in-cluster. It must be wired to
  Authentik/OIDC for human authentication and must not create a separate local
  human identity island. It is exposed at `hs.<base_domain>`. It must be
  sequenced after the base cluster exists; node Tailscale join must not remain
  a precondition for creating the Headscale service.
- The boot kiosk is not a hard v0.1 gate. AWS KMS auto-unseal is the minimum
  v0.1 self-contained boot posture. Kiosk work remains tracked as follow-on
  product work and, when implemented, must not depend on OpenBao/ESO being
  available to start and must inherit ADR-0028 audit attribution and MFA rules.
- dmf-cms user administration is a release gate: admin invite/signup approval,
  role assignment, disable/revoke, MFA posture, and backend role enforcement
  must work before tagging v0.1.
- The release proves one catalog/deploy path end to end; wider catalog/media
  scope is deferred.

This ADR does not deprecate the multi-provider direction. It freezes the first
release contract. Non-AWS providers may remain in the repository as lab,
legacy, or experimental paths, but release-facing docs, verification, and tags
must treat AWS as the only supported v0.1 profile.

### Historical Consequences

- **Positive** - The release has one install story, one provider credential
  model, and one verification matrix. Operators do not need to collect
  Cloudflare, B2, Hetzner, Headscale, and ntfy.sh credentials to try the OSS
  system.
- **Positive** - ADR-0020 Mode A becomes easier to enforce: the OSS release
  has no dependency on dmfdeploy.io services and no hidden dependency on
  third-party providers outside the selected AWS account.
- **Positive** - ADR-0011's public-release revisit trigger is answered for
  v0.1. The operator-local automation-quorum path stops being acceptable as
  the release boot story; AWS KMS is an explicit trade under the AWS profile.
- **Positive** - ADR-0026 gets a concrete first provider target. Provider
  descriptors can still become the long-term abstraction, but the first
  accepted cloud profile is AWS rather than an abstract multi-provider matrix.
- **Positive** - SNS gives the release an out-of-band alert path without adding
  another provider token. Keeping passkeys/TOTP as primary factors preserves
  ADR-0015 and ADR-0028 rather than downgrading admin security to SMS-only.
- **Negative** - The first OSS tag will not claim Hetzner, Aliyun, Cloudflare,
  B2, public ntfy.sh, or external Headscale support, even though some of those
  paths currently exist or work in the lab.
- **Negative** - AWS KMS auto-unseal moves part of the OpenBao trust boundary
  to AWS. That is acceptable for this AWS release profile, but it must be
  documented honestly and must not be re-used as a Mode B/customer-managed
  claim without a new decision.
- **Negative** - Provider-native resources now include more than compute and
  DNS: Route53, S3, SNS, KMS, IAM, and EC2 must all be modeled and verified.
- **Neutral** - ADR-0030's console runtime self-contained rule still applies:
  the browser/app runtime must not fetch external CDNs, fonts, telemetry, or
  SaaS APIs. This ADR permits server-side calls to AWS services that are part
  of the selected provider profile.
- **Neutral** - The kiosk is not erased; it is moved out of the hard v0.1 gate.
  Headscale is promoted from implicit external dependency to mandatory
  in-cluster release work with Authentik/OIDC integration and explicit
  sequencing constraints.

### Historical Alternatives considered

- **Keep the current multi-provider lab shape for v0.1.** Rejected. It
  publishes the sprawl instead of reducing it and makes verification depend on
  several unrelated provider accounts.
- **Use Hetzner + Cloudflare + B2 as the first OSS profile because it already
  works.** Rejected. It is cheaper to preserve the lab path than to explain it
  as a self-contained release; the user goal is a single-provider OSS story.
- **Adopt EKS for the AWS release.** Rejected by ADR-0018. The first AWS
  profile must preserve the self-managed k3s architecture.
- **Defer Headscale from v0.1.** Rejected by operator direction. Private
  networking is a release requirement, so v0.1 must internalize Headscale,
  wire it to Authentik/OIDC, and rebalance the bootstrap sequence.
- **Make the boot kiosk the only v0.1 boot posture.** Not selected as the
  default. The kiosk is valid product work, but the operator confirmed it is
  not a hard v0.1 gate. AWS KMS auto-unseal removes the recurring
  operator-laptop dependency sooner and is the cleaner fit for a single AWS
  release profile.
- **Use SNS/SMS as the primary second factor.** Rejected. SNS is useful for
  delivery and fallback, but passkeys/TOTP remain the preferred admin factors.

### Historical Enforcement

- The implementation plan is
  [`docs/plans/DMF OSS v0.1 Release Mission 2026-05-25.md`](../plans/DMF%20OSS%20v0.1%20Release%20Mission%202026-05-25.md)
  and its WP1-WP5 work packages.
- `dmf-env/bin/init-wizard.sh` and the future Python wizard must expose the
  AWS profile as the v0.1 release path and must not require Cloudflare, B2,
  Hetzner, Aliyun, external Headscale, or public ntfy.sh credentials for that
  path.
- The AWS Terraform/OpenTofu profile must provision or reference EC2, IAM,
  Route53, S3, SNS, and KMS resources needed by the release.
- cert-manager release defaults must use Route53 DNS-01.
- OpenBao release defaults must use AWS KMS auto-unseal or an explicitly
  accepted kiosk/alternate posture that supersedes this sentence.
- Headscale release defaults must deploy Headscale in-cluster, configure
  Authentik/OIDC login, expose `hs.<base_domain>`, and move node Tailscale
  join after Headscale is reachable.
- ntfy release defaults must deploy ntfy in-cluster and expose
  `ntfy.<base_domain>`.
- `bootstrap-verify.yml` or its release successor must verify provider
  profile, Route53/TLS, S3 write/read, SNS publish, OpenBao recovery, ntfy
  publish/subscribe, Headscale OIDC/node registration, CMS MFA/authz, and the
  initial catalog deploy/teardown.
- Release docs and quickstarts must not present non-AWS providers as supported
  v0.1 install options.
- The v0.1 release manifest must pin the component SHAs that passed the AWS
  greenfield and idempotency verification.

### Historical Acceptance record

Operator confirmations recorded 2026-05-25 (morning):

1. AWS is the sole supported provider for OSS v0.1.
2. AWS KMS auto-unseal is the minimum release boot posture.
3. Kiosk is not a hard v0.1 gate.
4. Headscale is mandatory for v0.1.
5. Headscale must be wired into Authentik/OIDC.

These confirmations are voided by the rewritten Decision above. Items 3
(kiosk not a hard gate) and the multi-vendor end-state direction survive in
spirit but are no longer expressed as AWS-only.
