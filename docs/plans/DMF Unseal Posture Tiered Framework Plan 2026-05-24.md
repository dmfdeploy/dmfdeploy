---
status: historical
date: 2026-05-24
---
# DMF Unseal Posture Tiered Framework Plan

**Status:** Design proposal — pre-ADR; postponed pending further review.
Captures a design discussion between the operator and claude-bottom on
2026-05-24. The operator chose on 2026-05-25 to defer ADR promotion and
HA/raft implementation until another review pass. If revived, this plan
is intended to land as ADR-0029 (working title: *Tiered Unseal Posture for
OSS Deployment*).
**Date:** 2026-05-24
**Author:** session-collaborative (claude-bottom + operator)
**Supersedes when accepted:** ADR-0011 (auto-unseal trade is reframed as
"Tier 3, explicitly chosen + warned + audited," not a quiet accepted weakness).
**Concretizes:** ADR-0028 D1 ("OpenBao custody") + C2 ("OpenBao is the
custody layer for steady-state secrets") per declared tier.
**Orthogonal to:** ADR-0009 (5-share Shamir remains the disaster-recovery
custody layer for all tiers); ADR-0020 (Mode A/B is deployment-scope axis;
tiers are security-posture axis — every deployment lives at a point in the
2D space).

---

## 0. Why this plan exists

The conversation started from a concrete operator question — *flypack / OB
truck cold-boot: the cluster can't run with OpenBao sealed, and today's
unseal path assumes the operator's Mac with JuiceFS + Tailscale; what's a
secure but operator-friendly path for an air-gapped venue?*

The discussion narrowed to a more tractable first cut: improve the
**OSS / internet-reachable** cold-boot path first, because (a) it's the
shape most adopters will deploy, (b) the air-gapped flypack case
genuinely needs more work and would otherwise hold up the simpler win,
and (c) the OSS improvements form the foundation on which the air-gapped
variant can later build.

This plan documents what we settled on for OSS, and explicitly defers the
air-gapped/flypack variant to a follow-on plan that builds on this one.

---

## 1. Current state on the live cluster (researched, not assumed)

The current cold-boot reality, verified against the openbao role
(`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml`)
and the unseal script (`dmf-env/bin/unseal-openbao.sh`):

1. **k3s comes up cleanly.** kube-apiserver, etcd, kubelet, containerd,
   Cilium, Longhorn, Traefik, MetalLB — none depend on bao. Control and
   data planes are healthy within minutes of node power-on.
2. **`openbao-0` (single-replica StatefulSet) starts sealed.** Default bao
   behaviour after any process restart. Readiness probe keeps the pod
   NotReady.
3. **ESO stops syncing.** Already-mounted secrets keep their values;
   pods that re-roll (image bump, OOM, node drain, restart) block on
   missing secret material and CrashLoop or stay Pending.
4. **Nothing on the cluster unseals bao.** There is no systemd unit,
   sidecar, init container, CronJob, or operator. The only auto-unseal
   logic is the openbao role's tasks at `main.yml:264, 596–648`, which
   only fire when *the operator runs the playbook from their Mac*. The
   standalone path is `bin/unseal-openbao.sh <env>`, also Mac-only.
5. **Cluster stays half-broken until the operator acts.** Workloads that
   were running and don't need fresh ESO syncs keep humming; everything
   that gets bounced piles up in Pending/CrashLoop.

Both unseal paths require the operator's **Mac + JuiceFS mounted + login
Keychain unlocked + SSH reachability to the control node (Tailscale + DNS)**.
The cluster cannot self-heal from a reboot. For air-gapped deployments,
the current mechanism literally cannot run at all — JuiceFS needs B2,
SSH to the control node needs Tailscale or a public route.

ADR-0009 declares 3-of-5 Shamir defense; ADR-0011 acknowledges the
routine path collapses to 1-of-1 (the automation file). Both are accurate
but read together they leave a confusing posture story — "do we have
Shamir defense or not?" The answer today is "it depends which path you
took" — and that ambiguity is what this plan removes.

---

## 2. Three separable problems

Before discussing solutions, the unseal pain decomposes into three
scenarios with different tolerable friction:

| # | Scenario | Tolerable friction | Frequency on live cluster |
|---|---|---|---|
| 1 | **Cold boot** — full cluster power-cycle | One ceremony, seconds to minutes | Rare (per-quarter or less) |
| 2 | **Routine pod restart** mid-operation — Longhorn rebalance, node drain, OS patch | **Zero** operator | Multiple per week |
| 3 | **Disaster / rekey** — keys lost, master corrupted, share material rotated | Heavy ceremony (full ADR-0009 path) | Once or never |

Today's posture conflates #1 and #2 (both use the same automation-file
path) and underserves #3 (the 5-share path exists but only as a
break-glass curiosity). The tiered framework addresses #1 explicitly,
makes #2 painless via HA bao + raft (orthogonal to tier), and leaves #3
intact as the ADR-0009 path.

---

## 3. Design space considered

The discussion walked through a number of patterns. Summarized briefly
with the verdicts that emerged:

**Operator's first proposals**

- **Password-only wrapped shares on cluster** — wrapped blob sits on
  cluster disk indefinitely; stolen node = offline attack at attacker's
  leisure. Memorable typeable passphrases give ~30–50 bits effective
  entropy (Argon2id helps but doesn't save you against a stolen NVMe).
  Acceptable **only** combined with a second factor whose secret isn't on
  the same disk (FDE with different unlock token, TPM PCR binding, or
  hardware token). Not sound as the only mechanism.
- **Browser-uploaded shares from operator devices** — much closer to
  ADR-0009's intent. Shares not at rest on cluster. Needs trusted local
  HTTPS (cert trust on a no-internet LAN), a trusted browser/laptop
  during the unseal moment, and accepts that the operator devices
  become availability single points. Not bad, but the friction model is
  identical to today's CLI script — just moved to a browser.

**Other patterns weighed**

- **YubiKey / FIDO2 as a wrapping factor** — operator touches YubiKey on
  the boot device; the HMAC response unwraps a stored share. Stolen
  truck without YubiKey = useless. Industry-standard (systemd-cryptenroll
  pattern). Strong, but introduces "another physical thing to carry."
- **TPM-bound seal with PCR measurement** — bao's seal key wrapped
  against PCRs that change if you swap disks or boot a different OS.
  Zero operator friction; defeats partial theft (disk pulls) but does
  *not* defeat whole-rig theft. Pairs naturally with "phone home once at
  boot" gates when there's connectivity; not applicable to air-gapped.
- **HA bao with raft** (ADR-0011 §Alternatives A) — 3 bao replicas,
  raft storage. Cold boot needs *one* manual unseal of one replica;
  others auto-unseal from peers. Subsequent pod restarts during normal
  operation auto-unseal from peers, zero operator. **The single biggest
  improvement available; not novel; already named as the successor.**
- **Operator key card (NFC tag / smart card)** — same shape as
  browser-upload but with a single dedicated artifact, cheaper kiosk,
  no general-purpose laptop in the boot path.
- **Cloud KMS auto-unseal** — bao seal type `awskms` / `gcpkms`.
  Trades local-only trust for cloud-vendor trust. Standard production
  pattern. Philosophical mismatch with operator's local-first lab
  posture, but the *most defensible* form of automatic unseal for
  users who don't share that posture.

The synthesis converged on: **HA bao + raft as universal baseline; an
unseal kiosk on the apex URL for cold-boot human interaction; passkey
+ PRF + cross-device QR transport for share submission; tier-selectable
posture so the same kiosk implementation serves Tier 1 (multi-device
quorum), Tier 2 (single-operator), and Tier 3 (skip the kiosk entirely
via auto-unseal).**

---

## 4. The cluster-resident unseal kiosk

A small app served at a dedicated subdomain (e.g.
`unseal.dmf.example.com`) by Traefik. It has **no bao dependency itself**
(static config, K8s Secrets baked at deploy time) so it can come up when
bao is sealed — which is exactly when it's needed.

Behavior:

1. When any bao replica is sealed, the page is reachable.
2. Operator's device (laptop or phone) loads the page; UX depends on
   declared tier (see §5).
3. The page collects N shares via the tier's chosen mechanism.
4. The page calls `bao operator unseal` server-side against the in-cluster
   bao endpoint.
5. When bao is unsealed, the page reports done and goes idle.

The kiosk is a thin HTTPS wrapper around the same bao API calls
`bin/unseal-openbao.sh` already makes. Differences from today:

- Recovery works from **any browser, anywhere**, not "operator's Mac +
  JuiceFS + Tailscale."
- Shares can live wherever the operator chooses — YubiKey-wrapped
  storage, password manager, paper, PRF-wrapped phone storage.
- No SSH-into-control-node, no kubectl-exec, no shell expertise.

**Mandatory guardrails (any tier):**

- **Per-cold-boot one-time token** printed to the node console / SSH
  MOTD, required as an additional field on the form. Holds the unseal
  surface to operators who legitimately have infra access at the time
  of boot — not just anyone holding shares.
- **Hard rate-limiting** on the form. Even though Shamir math makes
  share-guessing infeasible, exposing an unseal endpoint openly is the
  kind of thing that draws CVE-class scrutiny in OSS.
- **Audit log entry per submission.** ADR-0028 C5 (every action carries
  actor / role / request_id / reason) applies: log who unsealed, when,
  from what IP, with what reason text, streamed to the WORM target.
- **Kiosk does not itself depend on ESO/bao to start.** Critical
  bootstrapping rule: it cannot fail in exactly the scenario it's needed
  for.

---

## 5. The tiered framework

**Three tiers, declared at deploy time, surface different kiosk
behavior. HA bao + raft is the baseline for all tiers (it kills routine
pod-restart pain regardless of cold-boot posture).**

| Tier | Name | Cold-boot effort | Threat boundary | Suitable for |
|---|---|---|---|---|
| 1 | **Quorum unseal** | ≥3 humans × ≥3 attested devices × ≥3 biometric events | Multi-device + multi-human | Multi-operator production, regulated facilities |
| 2 | **Operator unseal** | 1 phone × 1 biometric (+ optional passphrase) | Operator + their device | Single-operator deployments, lab, broadcast facility w/ one admin |
| 3 | **Self-recovering** | None — cluster auto-unseals on boot | Cluster admin = bao admin | Temporary / demo / disposable deployments where uptime > confidentiality |

Naming note: Tier 2 should **not** be framed as "reduced security" —
for a single-operator deployment, it is the *correct* security for that
threat model. Calling it "reduced" implies the operator should feel
guilty for picking it, which leads to operators picking Tier 1 they
don't operationally need, then silently bypassing it by hand to escape
the friction — putting them in the worst spot (declared posture doesn't
match actual posture). "Operator unseal" is the recommended name.

### 5.1 Tier 1: Quorum unseal

- **HA bao + raft, 3 replicas.**
- **No automation file at rest anywhere.** ADR-0011's trade is fully
  retired in this tier.
- **Kiosk requires shares from ≥3 distinct enrolled humans**, each
  attested via a passkey belonging to that human (not just ≥3 devices —
  one human with 3 phones must not satisfy the threshold).
- Each share submission flow uses passkey + PRF + biometric on the
  share-holder's phone (see §6).
- ADR-0009 5-share DR path remains for true disaster.
- Audit log: 3 actor entries per unseal event, each with attestation,
  biometric timestamp, device identifier, passphrase-evidence flag.
- Cold-boot recovery time: minutes (humans coordinate).
- Cluster compromise yields nothing without 3 humans + 3 devices + 3
  biometrics.

### 5.2 Tier 2: Operator unseal (recommended default)

- **HA bao + raft, 3 replicas** (same baseline).
- **Operator's phone holds 3 PRF-wrapped shares** (not 1 — the Shamir
  structure is preserved cryptographically inside the phone's storage,
  but operationally one device releases all three).
- **One device unseal:** scan QR, one Face ID, all 3 shares released to
  the kiosk in sequence.
- **Per-device passphrase recommended** (mixed into PRF wrapping;
  autofills from phone's password manager — adds ~1 second of friction
  for real defense against compromised biometric alone).
- Audit log: 1 actor entry, attestation + biometric timestamp + device
  identifier + boot token.
- Cold-boot recovery time: ~10 seconds, one human, one tap.
- Threat model honestly stated: "compromise of operator's phone +
  biometric (or passphrase, if enabled) = full bao compromise."
- **Why this is the recommended default:** Tier 1 is too heavy for a
  first-time OSS adopter trying the platform; Tier 3 is too security-low
  to default to. Tier 2 hits the friction sweet spot and matches what
  most OSS users actually are — a single admin trying it out.

### 5.3 Tier 3: Self-recovering

- **HA bao + raft, 3 replicas** (still — operational benefit).
- **Cluster auto-unseals on boot.** Two implementations, operator picks:
  - **3a. Cloud KMS** (`awskms`, `gcpkms`, `azurekeyvault`). Bao seal
    type set to KMS; cluster boot triggers KMS decrypt; zero operator.
    Standard upstream pattern. **The most defensible form of Tier 3.**
    Trust shifts to cloud vendor — documented as such.
  - **3b. Cluster-resident wrapped blob.** A K8s Secret holds the
    automation material (3 shares + root token), optionally wrapped
    via sealed-secrets. K8s controller posts shares to bao at boot.
    No cloud dependency. Threat model: anyone with cluster admin =
    bao compromise.
- No operator interaction at all on reboot.
- Audit log: actor = `system: cluster-bootstrap`, reason = `tier 3
  self-unseal enabled at deploy time by <git commit>`, request_id =
  boot epoch. ADR-0028 C5 is not violated — Tier 3 has *no human
  actor*, which is named explicitly rather than omitted.
- Cold-boot recovery time: ~30 seconds after last node reboots.
- Threat model honestly stated: "Tier 3 trades cold-boot custody for
  automatic recovery. Anyone with cluster admin access = full bao
  compromise. Suitable for temporary / demo / disposable deployments
  where uptime > confidentiality."

---

## 6. Passkey + QR + PRF design (Tiers 1 and 2)

The kiosk's share-submission mechanism uses WebAuthn primitives end-to-end.

**Primitives leveraged:**

- **WebAuthn PRF extension** — a passkey can derive a deterministic
  32-byte key on each authentication. Used to wrap each share at rest on
  the share-holder's phone. Supported on Apple platforms (Safari/iOS),
  Chrome on Android, hardware keys with PRF (YubiKey 5.7+). Verify on
  actual operator devices before committing.
- **Cross-device authentication** (CTAP 2.2 hybrid / caBLE) — desktop
  shows QR; phone scans; Bluetooth handshake brings up Face ID; phone
  returns assertion. Production pattern (Google, Apple, Microsoft
  passwordless sign-in).

**Flow (Tier 1 — three humans × three phones):**

1. Cold boot. Cluster up, bao replicas sealed, kiosk reachable.
2. Operator-on-call opens kiosk URL on any laptop. Kiosk shows QR + the
   per-cold-boot one-time token (grabbed from node MOTD).
3. Operator scans QR with phone 1 (their own). PWA opens session URL,
   prompts Face ID, PRF derives wrapping key, decrypts Share-A, POSTs
   to kiosk over server-mediated session.
4. Operator coordinates with two other authorized humans; each scans
   the same QR (or the session URL forwarded over Signal/similar),
   each repeats step 3 with their own passkey + their own share.
5. Kiosk has 3 shares + boot token + 3 distinct attestations →
   calls `bao operator unseal` three times → raft propagates → ESO
   resumes → cluster fully recovers.

**Flow (Tier 2 — one human × one phone):**

Same as above but the operator's single phone holds 3 PRF-wrapped shares
(each potentially wrapped under a different passkey or all under one).
Steps 3 + 4 collapse into a single ceremony: one Face ID, three share
releases in sequence, optional one passphrase confirm.

**Total operator effort:**

- Tier 1: ~3 minutes (mostly coordination overhead).
- Tier 2: ~10 seconds (one URL, one tap).
- Tier 3: zero seconds (none).

**Transport choice:** server-mediated session is preferred over direct
WebAuthn hybrid for OSS — kiosk generates a session ID, phone opens
session URL via normal internet, phone runs its own passkey assertion
locally, POSTs share to kiosk server. This works whether the phone is
next to the laptop or in another country. Hybrid (Bluetooth proximity)
remains useful for the air-gapped flypack case discussed in §10.

**Phone-side software:** a PWA installed on each authorized phone
(add-to-home-screen on `unseal.dmf.example.com` or similar). First-launch
enrollment receives a share via a one-time bootstrap URL, stores it
PRF-wrapped in IndexedDB. Subsequent unseal events use Face ID to
decrypt + POST. No app store needed; minimal footprint.

**Failure modes the design must handle gracefully** (open question — see
§9):

- Suspicious passkey attestation (revoked credential, unfamiliar AAGUID).
- One phone unreachable / dead battery / wiped — fall back to USB share
  4 or 5 from ADR-0009.
- iCloud rotation of synced passkey (PRF output changes — the wrapped
  share blob also needs re-wrapping).
- Phone offline at moment of unseal but online later (queue + recover?
  or hard fail and require fallback?).

---

## 7. The 2FA question, explicitly

The discussion explored adding "another 2FA step" on top of the passkey
flow. Key clarification: **passkey + PRF + biometric is already 2FA**
(possession of enrolled phone + something you are). Adding a third
factor is meaningful only if it closes a specific gap.

**Threat gaps and which controls actually close them:**

1. **One phone lost or stolen** → already covered by Shamir threshold.
2. **Multiple authorized phones in one stolen bag** → biometric
   requirement on each phone covers it.
3. **Compromised biometric (face photographed, fingerprint lifted)** →
   per-device passphrase (mixed into PRF wrapping) closes this.
4. **Coerced operator (held at gunpoint, social-engineering on-call)** →
   biometric and passphrases don't help; only two-person quorum (Tier 1)
   does.
5. **Insider threat (authorized operator is the adversary)** → only
   two-person quorum (Tier 1) closes this.
6. **Synced passkey compromised via iCloud takeover** → still needs the
   wrapped share blob + biometric bypass; per-device passphrase closes
   the remaining gap.

**The four "add another factor" shapes considered:**

- **A. Knowledge factor mixed into PRF wrapping (per-device passphrase).**
  Covers gaps 3 and 6 cleanly. Adds ~1 second of friction (autofills
  from password manager). **Recommended for Tier 2 baseline.**
- **B. Independent hardware token (YubiKey alongside the phone passkey).**
  Covers 3, 6, and some of 2. Doubles the "things to lose" count;
  operationally heavier than A. Optional upgrade for security-sensitive
  Tier 2 deployments.
- **C. Two-person quorum (structural, not a factor at all).** The only
  control that addresses 4 and 5. **This is what Tier 1 already is** —
  named as a tier rather than as an add-on factor.
- **D. TOTP code from a separate authenticator.** **DO NOT.** Mostly
  theater on top of a passkey flow. TOTP is weaker than passkey; layering
  weaker auth on stronger auth does not compose multiplicatively (per
  NIST 800-63B). Friction without meaningful defense.

**Conclusion:** the tiered framework already provides what "add 2FA"
would aim for — Tier 1 *is* the quorum control, Tier 2 plus the
recommended per-device passphrase *is* the multi-factor control. There
is no useful additional factor beyond these. The doc should be explicit
that "more layers" is not always better and that TOTP-on-top is
specifically rejected.

**Per-operation tier escalation (optional extension):** the kiosk could
enforce different thresholds per operation type. Cold boot uses the
cluster's declared tier; rekey or root-token issuance could *always*
require Tier 1 regardless of declared tier. This matches PKI software
("intermediate CAs need less ceremony than root"). Worth designing in,
but not required for first ship.

---

## 8. Tier-downgrade protection (the most important guardrail)

If an attacker can silently flip the cluster from Tier 1 → Tier 3 by
writing an automation file, the strictest tier provides no defense.
The tier choice must be:

- **Bound at deploy time** in a helm chart value or Ansible group_var
  tracked in git.
- **Cryptographically declared at boot.** The kiosk (or the unsealer)
  checks "this cluster declares Tier N" against a signed config and
  refuses to operate in a tier *lower* than declared. A downgrade
  requires an explicit, signed, audited config change — not just dropping
  a file in a directory.
- **Visible in cluster status.** `kubectl get ...` and the dmf-cms
  console always show the current declared tier prominently. A Tier 1
  cluster that has silently been operating as Tier 3 for six months
  because someone copied in an automation file is exactly the drift
  this framework is designed to prevent.

Without these protections, the tiered framework is just labels on the
same mess we have today. **With them, it is the actual control.**

---

## 9. Open questions before ADR draft

The framework needs operator decisions on these before becoming binding
architecture:

1. **HA raft migration plan.** When does the live `g2r6-foa9` env
   migrate from single-replica to 3-replica raft? Or is the migration
   gated on the next env spin-up?
2. **Default tier confirmation.** Plan recommends **Tier 2** as default.
   Operator agreement or pushback?
3. **Tier-declaration mechanism.** Helm value? Ansible group_var? Both?
   Signed config? What's the cryptographic root for the signature?
4. **Per-cold-boot one-time token UX.** Print to MOTD on each node?
   Generate per kiosk session and require operator to read from
   node console via SSH first? What if the operator can't SSH (the
   scenario the kiosk exists to fix)?
5. **PWA bootstrap.** First-launch enrollment URL — how authenticated
   is it? Who's allowed to enroll a new authorized phone, and what
   does revocation look like?
6. **Failure-mode handling.** Specifically: phone wiped + share lost,
   iCloud passkey rotation, kiosk-but-no-shares fallback path. Each of
   these wants a documented procedure; should they live in this plan,
   in the ADR, or in a separate runbook?
7. **Migration matrix.** Tier 3 → 2 is easy (enroll a phone, delete
   automation material). Tier 2 → 1 is medium (enroll more devices,
   possibly re-shard). Tier 1 → 2 → 3 is dangerous; needs explicit
   teardown + audit-log entry, not just a config flip. Plan should
   spell each transition's procedure before ADR.
8. **Per-operation escalation.** Land in the first ADR or defer to a
   follow-on? Operator preference.
9. **Tier 3 sub-choice.** Document both 3a (cloud KMS) and 3b (cluster
   wrapped blob)? Recommend one over the other in the default doc?
10. **Naming.** "Operator unseal" (not "reduced security") for Tier 2 —
    confirm. Any objections to "Quorum unseal" / "Self-recovering" for
    Tiers 1 and 3?

---

## 10. Deferred: air-gapped / flypack variant

The original question that started this thread — OB-truck / flypack cold
boot with no internet, no Tailscale, no public DNS — is **deferred to a
follow-on plan** that builds on this one. Reasons:

- The OSS path is the broader deployment shape; doing it first benefits
  more users.
- The flypack variant reuses much of this design (the kiosk, the
  passkey/QR flow, the tier framework) but with substitutions:
  - Local CA pre-trusted on operator devices instead of Let's Encrypt
    (no internet for DNS-01 challenge).
  - Direct WebAuthn hybrid (Bluetooth proximity) instead of
    server-mediated session (no LAN-to-internet bridge).
  - In-truck kiosk + share-holder phones all on the truck LAN, with the
    kiosk acting as both share collector and local rendezvous.
  - Possibly a fourth tier or a flypack-specific profile that explicitly
    accepts the "truck is the security boundary" framing.
- The flypack design also wants to revisit ADR-0022 (flypack-online thin
  edge agent) for any constraints that interact with the unseal
  mechanism.

Once this OSS-path plan is accepted as an ADR, the air-gapped variant
gets its own plan + ADR sequencing.

---

## 11. Cross-references

**Superseded / amended when accepted:**

- [ADR-0011](../decisions/0011-auto-unseal-tradeoff.md) — the "auto-unseal
  trade we accept" is reframed as "Tier 3, opt-in, warned, audited." The
  trade isn't gone; it's named and chosen.

**Concretized:**

- [ADR-0028](../decisions/0028-identity-and-authority-chain.md) — D1
  (OpenBao custody) + C2 (custody layer) get per-tier realizations. C5
  (every action carries actor / role / request_id / reason) gets
  per-tier audit semantics (Tier 1: 3 actors; Tier 2: 1 actor; Tier 3:
  actor = `system: cluster-bootstrap` with deploy-time provenance).

**Orthogonal but referenced:**

- [ADR-0009](../decisions/0009-shamir-dr-model.md) — 5-share Shamir
  distribution remains the disaster-recovery custody layer for all
  tiers. Tier 1 uses it for routine + DR; Tiers 2/3 use it only for DR.
- [ADR-0008](../decisions/0008-openbao-secrets-architecture.md) —
  OpenBao + ESO + AppRole foundation; unchanged. The tier choice does
  not affect ESO behavior, per-secret ACLs, or AppRole shim.
- [ADR-0015](../decisions/0015-dmf-console-passkey-only.md) — passkey
  precedent. The kiosk's use of passkeys for human authentication is a
  direct extension of this ADR's binding rule.
- [ADR-0020](../decisions/0020-deployment-scope-and-regulatory-posture.md)
  — Mode A/B is a deployment-scope axis; tiers are a security-posture
  axis. Every deployment is at one point in the 2D space.
- [ADR-0007](../decisions/0007-secrets-never-in-argv.md) — the kiosk
  must respect this discipline end-to-end: shares never in URL params,
  never in server-side argv, never logged.
- [ADR-0022](../decisions/0022-flypack-online-thin-edge-agent.md) —
  referenced for the deferred air-gapped/flypack variant in §10.

**Implementation references:**

- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml`
  — current openbao role; reference for the unseal calls the kiosk
  needs to replicate server-side.
- `dmf-env/bin/unseal-openbao.sh` — current manual break-glass script;
  the kiosk subsumes its core function for routine recovery (the script
  remains the canonical break-glass fallback when the kiosk itself is
  unavailable).
- `docs/architecture/DMF Identity and Authority Model.md` — the
  identity-and-authority architecture this plan concretizes against.

---

## 12. Next steps

1. **Postponed pending further review.** Do not draft ADR-0029 or start
   HA/raft implementation until the operator explicitly reopens this
   workstream.
2. **Operator review of this plan.** Pressure-test against three concrete
   deployment scenarios: (a) a single-admin homelab Tier 2 default, (b)
   a multi-operator regulated broadcast facility Tier 1, (c) a one-week
   demo cluster Tier 3 with cloud KMS. Do all three feel honest and
   operationally workable?
3. **Resolve open questions in §9.** Especially: default tier, tier-
   declaration mechanism, PWA bootstrap, failure-mode handling.
4. **Draft ADR-0029** from this plan, with the operator decisions folded
   in. ADR is shorter than the plan — it binds; the plan retains the
   reasoning.
5. **Sequence the implementation** as a separate plan once the ADR
   lands. Likely PR breakdown: (1) HA raft migration; (2) kiosk
   skeleton with Tier 3 cluster-wrapped-blob (cheapest tier to ship);
   (3) Tier 2 passkey + PRF + PWA + QR flow; (4) Tier 1 multi-human
   enrollment + audit semantics; (5) tier-downgrade protection +
   cluster-status visibility.
6. **Follow-on: air-gapped flypack plan** (deferred per §10).

---

*This plan was produced during a 2026-05-24 design conversation between
the operator and claude-bottom. Reasoning is preserved here so future
agents and reviewers can reconstruct why each choice was made, not just
what was decided. Pressure-testing welcomed; revisions expected before
ADR-0029 lands.*
