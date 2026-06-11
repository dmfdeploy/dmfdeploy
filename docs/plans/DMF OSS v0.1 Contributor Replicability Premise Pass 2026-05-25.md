---
status: executed
date: 2026-05-25
---
# DMF OSS v0.1 Contributor Replicability — Premise Pass

**Status:** Closed — operator decisions promoted into ADR-0031; WP0 remains
the next planning artifact
**Date:** 2026-05-25
**Author:** Claude (CEO-mode review)
**Related ADR:** [ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md) (Proposed; operator decisions closed, WP0 pending)
**Related plans:** OSS v0.1 Mission + WP1–WP5 (all dated 2026-05-25; not yet binding)
**Purpose:** Confront the premise of ADR-0031 honestly before re-Accepting it,
so the v0.1 framing is durable rather than emergent from a single planning sweep.

---

## 1. What is actually settled

The operator has confirmed (2026-05-25 chat):

- **Goal:** Make the project replicable by OSS contributors *without* requiring
  them to sign up for the maintainer's specific provider mix (Hetzner +
  Cloudflare + Backblaze B2 + Tailscale + external Headscale + ntfy.sh +
  the operator's Mac + JuiceFS + Keychain unseal shares).
- **Posture:** AWS-as-the-replicable-path was the operator's idea, motivated
  by sprawl reduction without giving up the long-term multi-provider direction.
- **Hard constraint:** v0.1 is an **initial minimal system that contributors
  can replicate**. It is **not** a replacement for the current Hetzner
  architecture, not a deprecation of the work spent landing ADR-0028 /
  ADR-0024 / ADR-0021, and not a demotion of the live `g2r6-foa9` setup
  to second-class status.
- **Future direction unchanged:** Multi-provider remains the eventual goal
  (per `project_multi_provider_resource_selection` memory and ADR-0026).

## 2. What is *not* yet settled

ADR-0031 as drafted bundles the settled goal with several implementation
claims that were not separately challenged. They each need their own answer:

### Q1 — Does v0.1 forbid non-AWS providers, or just designate AWS as the primary contributor path?

ADR-0031 currently says "Cloudflare, B2, Hetzner, Aliyun, public ntfy.sh,
external Headscale … are not required by the v0.1 release path" — which is
fine — but also says non-AWS providers "must not be required for the OSS
v0.1 path" and that release-facing docs "must treat AWS as the only
supported v0.1 profile." That is stronger than the underlying goal needs.

A weaker posture that still meets the goal:

> **v0.1 ships one *primary* known-good install profile (AWS) that a new
> contributor can replicate cold. The Hetzner profile remains documented
> as a working alternative used by the maintainer's lab; it is not the
> canonical contributor onboarding path but it is not "experimental" either.**

That keeps the friction-reduction win without forcing self-amputation of
the live env.

### Q2 — What is v0.1's actual contributor surface?

The mission's 15 release gates conflate three different concerns:

| Concern | Gates | Required for contributor replicability? |
|---|---|---|
| Clean install path on AWS | 1, 3, 4, 6, 7, 11, 12 | Yes — core. |
| Boot independence (no operator laptop) | 2, 5 | Yes — core. A contributor can't replicate if your Mac is part of the boot story. |
| Public release hygiene + manifest | 14, 15 | Yes — small. |
| Full CMS user-admin product surface | 8, 10 | **No.** A contributor doesn't need invite/approval/role-assignment/revoke to *replicate*. They need to log in as the seeded admin and try the loop. |
| MFA-enforced second factor | 9 | Maybe. Depends on the persona (see Q3). |
| Recovery / TLS renewal / reboot survival | 13 | Stretch. Worth verifying but not blocking. |

The **smallest credible v0.1** that still serves the goal is roughly gates
1, 2, 3, 5, 6, 7, 11, 12, 14, 15 — ten gates, not fifteen, and the
biggest cut is full CMS user-admin (WP4) which is moved to v0.2 except
for "seeded admin can log in." That cut probably halves the timeline.

### Q3 — Who is the v0.1 contributor persona? — **answered 2026-05-25**

**Operator's answer (2026-05-25 chat):**

> "Initially some trusted friends, and people I might send the link to,
> as well as GitHub users that might discover the repo. I might even
> start a small vlog series explaining the project which would drive
> more users to the project. **Self-hosted single-node sandbox deploy
> is a near-term goal.**"

This resolves the persona toward a blend of (b) homelabber and (d) future
maintainer in the original list. Critically, the operator added a
goal that was not in the ADR-0031 framing: **single-node self-hosted
sandbox deploy.**

**Implications for the other open questions:**

- **Q1 (provider exclusivity)** — "AWS-only" is now actively misaligned
  with this persona. A homelabber discovering the repo via vlog does
  not want to swipe their card for AWS to try a sandbox. The right v0.1
  *primary* path is more likely "single-node k3s self-host on a $5–$20
  VPS or a local box" with AWS as one of several documented backends
  for that single-node profile. AWS becomes a *supported provisioning
  option*, not the *only release profile*.
- **Q2 (gate scope)** — The 15 gates were written for a multi-instance
  AWS release. Several gates lose meaning under a single-node sandbox
  framing: SNS-based out-of-band alerting (overkill for a sandbox),
  full S3 audit/archive/snapshot/backup wiring (overkill), AWS KMS
  auto-unseal (overkill — the sandbox can keep manual unseal or use a
  local kiosk). The right v0.1 gate list under this persona is more
  like: clean single-command install on a fresh box, OpenBao boots
  without operator-laptop assets, seeded admin can log in, one happy-
  path catalog deploy works, idempotency check passes. Five gates,
  not fifteen.
- **Q4 (sequencing)** — Under this persona, the spike-WP4-first
  argument weakens because most of WP4 (full user admin, invite/approve
  flows, MFA enforcement) is out-of-scope for a sandbox. What remains
  is "seeded admin can log in with a passkey," which is already largely
  done under ADR-0028. The real sequencing risk shifts: it's now about
  *whether the existing Hetzner working setup can be re-derived as a
  generic single-node profile* without rebuilding most of it on AWS
  first.
- **Critical reframe:** Under this persona, the existing **`g2r6-foa9`
  Hetzner setup is closer to v0.1 than the AWS plan is.** g2r6-foa9
  already proves the loop on a single ARM64 box. The v0.1 work could be
  primarily *documentation hygiene + install-script cleanup + secrets
  bootstrapping without the operator Mac* — i.e., a much smaller WP2 +
  a new WP0 ("make the current Hetzner profile cleanly replicable")
  rather than the full WP1 AWS replatform.

This is the strongest argument for keeping ADR-0031 Proposed: the
persona and goal as the operator described them today do not require
the AWS replatform that ADR-0031 mandates.

### Q3 (original framing — preserved for context)

ADR-0031 names "OSS contributors" but does not characterize them. The
right v0.1 differs significantly:

- **(a) Broadcast engineer evaluating DMF for an OB-truck or studio pilot.**
  Cares about ST 2110, NMOS, real media flows. Probably has AWS account
  access through employer. Wants the catalog/deploy loop to actually do
  something media-shaped at the end.
- **(b) Open-source media-IP hacker / homelabber.**
  Cares about replicating a working environment cheaply, prefers no
  cloud cost. AWS-only is actively *worse* for this persona than
  "install on your own machine / k3s on a Pi." Hetzner-with-clean-defaults
  or local-k3s would serve them better than AWS.
- **(c) Vendor or integrator evaluating DMF for SaaS embed.**
  Cares about identity model, audit chain, multi-tenancy hooks. AWS-only
  fits naturally. Doesn't care about catalog yet.
- **(d) Future maintainer / co-contributor onboarding to the codebase.**
  Just needs *some* environment that boots cleanly so they can `git
  clone` and contribute. Doesn't really care which cloud.

If (a) is the persona, AWS makes sense and the catalog loop matters more
than user admin. If (b) is the persona, AWS is wrong and a local /
Hetzner profile is the right v0.1. If (c) or (d) is the persona, AWS is
fine and CMS user admin is over-scoped.

**The operator's intent ("get the project into a state that is repeatable
by contributors") fits (d) most closely, possibly (b).** Worth confirming
explicitly because it changes WP scope.

### Q4 — Why is WP4 (CMS User Administration) sequenced last?

WP4 is the only WP that is product work — it touches frontend, backend,
auth, role enforcement, MFA flows. Product work has higher estimate
variance than infrastructure work. Sequencing it last means you discover
it's 3x larger than expected after WP1–WP3 have already burned 6 weeks.

If WP4 stays in v0.1 at full scope, it should be **spiked first**:
- Week 1: cold AWS provision → boot → seeded admin logs in with MFA →
  invites one user → that user accepts → assigns viewer role → viewer
  cannot deploy. End to end, ugly, but real.
- After that spike, you know whether WP4 is a 2-week polish job or a
  3-month vertical.

If WP4 gets cut to "seeded admin can log in" per Q2, then this question
goes away.

### Q5 — What is the DNS/TLS posture for the sandbox profile? — **answered 2026-05-25**

If `sandbox-single-node` is the v0.1 release gate, it needs a concrete
answer on how a contributor obtains a working TLS chain and reachable
hostnames without paying for / configuring upstream DNS.

The candidates considered:

- **(a) Local CA + self-signed certificates** — the sandbox installs a
  local cert-manager CA, issues certificates for `*.dmf.test` (or
  similar). Contributor adds the CA to their trust store. Zero external
  dependencies; matches the "homelab cheap" persona. Negative: trust-store
  bootstrap is per-OS friction and a known footgun.
- **(b) `nip.io` / `sslip.io` + Let's Encrypt HTTP-01** — sandbox derives a
  hostname from the host IP via `nip.io`/`sslip.io` and obtains
  Let's Encrypt certs via HTTP-01. Requires public IPv4 reachability on
  port 80. Negative: rate-limits, can't work behind NAT, depends on
  third-party DNS reflector being healthy.
- **(c) `*.localtest.me` or operator-controlled dev domain** — the project
  ships a small dev domain that resolves to `127.0.0.1` and ACME-issued
  certs are cached in the repo. Negative: certs in a repo go stale,
  domain becomes a project liability.
- **(d) Require user-owned DNS + ACME DNS-01** — same posture as
  production. Contributor must own a domain and provide DNS credentials.
  Negative: highest first-time friction; eliminates "I just want to try
  it on my laptop."

Codex's framing: "local CA / self-signed / dev domain is acceptable for
sandbox, or require user-owned DNS. I would not require Route53 here."

**Operator close-out (2026-05-25):** choose **(a) local CA** as the
`sandbox-single-node` release-gating default, with explicit host mappings
under a reserved `.test` sandbox domain (default `dmf.test`). Do not use
`.local`, to avoid mDNS/resolver ambiguity. Keep **(d) user-owned DNS +
ACME DNS-01** as an optional escape hatch for contributors who already own
a domain and want the production-shaped path. Route53 is not required for
the sandbox gate.

This close-out is now recorded in ADR-0031 O1.

## 3. Convergence with codex sequencing review (2026-05-25 afternoon)

After Q3 was answered, the sequencing question (Q4) was dispatched to
codex via `agent-bridge`. Codex's reply (recorded in the chat transcript;
the substantive points are absorbed here) materially sharpened the
framing. Key convergence points:

1. **The right v0.1 unit is not a provider, it is a canonical workflow
   contract** (clone → manifest → provision → bootstrap → admin login →
   reference deploy → verify → idempotent rerun → teardown). Providers
   become *lanes* under that contract, not the contract itself. This is
   sharper than the "AWS-as-primary-but-not-exclusive" framing in this
   doc's first draft.
2. **Three named profiles** rather than "AWS-only" or "any single cloud":
   - `sandbox-single-node` — v0.1 release gate, primary docs path.
   - `aws-arm64-multi-node` — parallel lane, eligible for v0.1 only if
     it catches up without delaying the sandbox.
   - `g2r6-foa9` — live lab / regression reference, **not** a release
     profile and explicitly preserved as the operator's testbed.
3. **Claim split** — v0.1 sandbox claims contributor-replicable
   end-to-end install/auth/operator workflow; v0.1 AWS multi-node (if
   shipped) claims architecture scales beyond one node; **neither v0.1
   profile claims production ST-2110 / PTP / multicast / NIC-isolation
   correctness.** Media-realism validation is a later profile with an
   explicit data-plane testbed.
4. **Pushback on the "AWS multi-instance is fairly attainable" amendment**
   — substrate readiness is not release fitness. AWS multi-instance being
   attainable in Terraform terms doesn't mean it should define the v0.1
   release promise, because the contributor still pays the AWS-account /
   IAM / Route53 / KMS friction *before* they ever see DMF. AWS continues
   in parallel, but does not gate the release.
5. **WP-level resequencing** — replace the current WP1→WP5 sequence with:
   - **WP0** — Release Contract & Profile Matrix (this ADR rewrite plus
     a successor plan doc).
   - **WP1S** — Replicable Single-Node Sandbox.
   - **WP1A** — AWS ARM64 Multi-Node Lane (continued; informational, not
     gating).
   - **WP2** — Bootstrap Independence (split by profile: local-generated
     for sandbox, KMS/SNS/SSM for AWS).
   - **WP3** — Platform Services scope-trim (Headscale gated to AWS lane;
     ntfy in-cluster for AWS, lightweight or stubbed for sandbox).
   - **WP4** — CMS auth/user-admin scope-trim (v0.1 = seeded admin login
     + role guards; full user-admin product → v0.2).
   - **WP5** — Release Verification Matrix (per-profile gate lists +
     common gates).

These convergence points have been **promoted into ADR-0031** as the
rewritten Decision section (2026-05-25 afternoon). The original AWS-only
Decision is preserved at §Historical draft of the ADR for context.

## 4. Status of the original open questions

- **Q1 (provider exclusivity):** resolved — not exclusive; profile matrix.
  Sandbox is primary, AWS is parallel-eligible, Hetzner-lab is reference
  only.
- **Q2 (gate scope):** resolved direction — common gates (~8) + per-profile
  gates. Full matrix to be drafted as WP5 successor. Many of the original
  15 gates collapse or become AWS-profile-specific.
- **Q3 (persona):** resolved — trusted friends, GitHub-discovery, vlog
  audience; self-hosted single-node sandbox as near-term goal.
- **Q4 (sequencing):** resolved direction — WP0 → WP1S+WP1A (parallel) →
  WP2-split → WP3-trim → WP4-trim → WP5-matrix. Full plan doc to be
  drafted under WP0.
- **Q5 (sandbox DNS/TLS):** resolved — local CA + explicit host mappings
  under a reserved `.test` sandbox domain, with user-owned DNS + ACME
  DNS-01 as an optional escape hatch.

## 5. Things I am explicitly *not* recommending

- Not recommending discarding the current Hetzner setup or the
  `g2r6-foa9` lab. The lab is explicitly preserved as Profile 3
  (reference, not release).
- Not recommending discarding ADR-0028 / ADR-0024 / ADR-0021 /
  ADR-0011 / ADR-0015 / ADR-0030 work. All remain in force.
- Not recommending postponing the multi-provider end-state direction
  (ADR-0026); the matrix framing actually makes that direction easier.
- Not recommending shutting down the AWS work; just removing it from the
  v0.1 release gate. AWS remains a serious parallel lane.

## 6. Follow-up status

This premise pass is now the historical basis for the accepted ADR-0031
profile matrix. The follow-up planning work has landed:

1. **WP0** ([Release Contract & Profile Matrix](DMF%20OSS%20v0.1%20WP0%20Release%20Contract%20and%20Profile%20Matrix%202026-05-25.md))
   is drafted and binds the sequence.
2. **ADR-0031** is re-accepted as **Accepted** on 2026-05-26 against WP0.
3. The original Mission + WP1–WP5 drafts remain on disk with re-scope banners;
   WP1 is retitled in place as WP1A for the AWS secondary lane.

Now that ADR-0031 is accepted, code changes should start on the **WP1S**
sandbox path first. AWS-lane work may continue under WP1A but must not gate or
delay the sandbox release path.
