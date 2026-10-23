# ADR-0031 archive: OSS v0.1 release-profile matrix

This file holds material moved out of [ADR-0031](../../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

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
- [x] `<env>` and successor labs are lab/regression reference, not
  release profiles, and are exempt from v0.1 release scrutiny.
- [x] Open decisions O1–O6 are closed (DNS/TLS, reference catalog,
  sandbox Headscale, MFA-by-profile, ADR-0026 timing, release artifact
  granularity). Close-outs recorded 2026-05-25 in §Closed operator
  decisions.
- [x] WP0 (Release Contract & Profile Matrix) is drafted as a successor /
  replacement to the current draft Mission + WP1–WP5 plan set
  ([DMF OSS v0.1 WP0 Release Contract and Profile Matrix 2026-05-25](../../plans/dmf-oss-v0-1-wp0-release-contract-and-profile-matrix.md);
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
  [`docs/plans/dmf-oss-v0-1-release-mission.md`](../../plans/dmf-oss-v0-1-release-mission.md)
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

## Trajectory note (2026-05-25) (moved from the ADR metadata block)

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

## Moved from the ADR on 2026-10-23

### Context (second paragraph and the three questions)

The release question is not whether DMF should eventually support multiple
providers — it should, per ADR-0026 — and it is not solely "which single
cloud profile becomes the v0.1 contract." The CEO-mode review surfaced that
the more useful frame is:

- What is the **release experience** a contributor encounters?
- Which **provisioning lanes** honor that experience?
- What does v0.1 **claim** and what does it explicitly not claim yet?

Those three questions, answered together, produce a release-profile matrix
rather than a single-provider contract.

### Profile 3 purpose bullet

- Purpose: validate architecture under real provider conditions, exercise
  ADR-0028 / ADR-0024 / ADR-0021 / ADR-0011 / ADR-0015 / ADR-0030
  end-to-end, surface bugs and architectural smells the generic profiles
  will not see.

### Consequences (Positive, rationale only)

- **Positive** — v0.1 has a defensible single canonical *experience*, with a
  low-friction default lane that matches the actual operator-stated persona
  (trusted friends, GitHub-discovery contributors, possible vlog audience,
  self-hosted single-node sandbox as near-term goal).
- **Positive** — ADR-0020 Mode A becomes easier to enforce: both v0.1
  profiles are demonstrably self-host and demonstrably independent of
  `dmfdeploy.io` services.
