# ADR-0040: Public-TLS tiering + dmfdeploy.io PSL design (removing the CA-trust step)

**Status:** Accepted (scoping decision, 2026-06-08) — **OSS uses Tiers 1 + 2 only;
dmfdeploy.io (Tier 3) is deferred to a future *managed-service* model and kept entirely separate
from OSS to protect the domain's reputation.** The Tier-3 design + hardening below are **captured
for that future phase**, not built now. (Reasoning/dead-ends recorded so they aren't re-derived
or re-proposed.)

**Date:** 2026-06-08
**Domain:** architecture / security / TLS / env-lifecycle
**Relates to:** ADR-0028 D8 (mandatory passkeys), ADR-0031 (OSS v0.1 sandbox + release-profile
matrix), ADR-0035 (operator-local self-contained envs), ADR-0036 (dmf-init thin control
container), plan *DMF Sandbox Zero-Setup Addressing (sslip.io) 2026-06-07*.

---

## Context — why this exists

The sandbox lane uses a **local CA** (cert-manager self-signed wildcard) for host-based HTTPS.
That forces a **manual CA-trust step** on the tester's machine. It can't be skipped because:

- **WebAuthn (mandatory passkeys, ADR-0028 D8) requires a *secure context*.** A secure context
  is `https://` with a **validating** cert chain, or `http://localhost`. Clicking through a
  TLS warning ("proceed anyway") loads the page but marks the origin **non-secure**
  (`isSecureContext === false`), so `navigator.credentials.create()` **fails** — surfaced
  misleadingly as *"Registration cancelled or timed out."* So "just accept the warning and use
  a passkey" **cannot work** for a host-based HTTPS origin; passkeys only worked once the CA was
  trusted (padlock green). The cert is load-bearing, not cosmetic.

The sslip.io work (2026-06-07) removed the **DNS/`/etc/hosts`** wall but deliberately kept the
local CA — so **CA-trust is the one remaining manual step.** This ADR explores removing it.

### The tiering model (the frame)

| Tier | How TLS is trusted | What the maintainer holds |
|---|---|---|
| 1. **Own domain** | tester's domain + their ACME (their LE bucket) | **nothing** |
| 2. **Local CA** (sslip.io today) | one-time CA install on client | **nothing** |
| 3. **dmfdeploy.io convenience** | publicly-trusted certs under *our* domain | a small DNS/cert service ⇒ **the only tier with custody/abuse/liability** |

Tiers 1 & 2 are fully decentralized (zero custody) and should be the **primary** product.
Tier 3 is an opt-in convenience whose *entire* risk surface is the subject of the rest of this ADR.

---

## Forces & dead-ends (recorded so they aren't re-litigated)

### Why sslip.io + Let's Encrypt is NOT viable
LE's main rate limit is **~50 certs per *registered domain* per week**, where "registered
domain" = the label below a *public suffix* (per the Public Suffix List, PSL). **`sslip.io` is
NOT on the PSL** (verified 2026-06-08: downloaded the PSL — `github.io` present, `sslip.io` and
`nip.io` absent). So every `*.sslip.io` name worldwide rolls up to the **single** registered
domain `sslip.io` → one shared 50/week bucket for the whole planet → effectively always
exhausted (`too many certificates already issued for: sslip.io`). Unreliable issuance is
unacceptable for "reproducible by a stranger." (Secondary, minor: HTTP-01 can't do wildcards;
needs :80.)

### Why we cannot "self-issue" browser-trusted certs (PKI law)
- A Let's Encrypt **wildcard is a leaf cert** (`basicConstraints: CA:FALSE`). **Only a CA cert
  (`CA:TRUE` + `keyCertSign`) can sign other certs.** A wildcard leaf cannot mint subdomain
  certs — path validation rejects anything it "signs."
- A **publicly-trusted *intermediate* CA** is given only to audited public CAs (CA/Browser
  Forum + WebTrust). No public root will delegate a signing CA to this project.
- ∴ "issue our own short-lived certs that browsers trust" is **empty**. Any self-issuance means
  *our own (untrusted) CA* → clients must install it → back to (and worse than) Tier 2, now with
  a central CA key whose leak MITMs **everyone**.
- **One shared LE wildcard for all envs** also fails: serving it per node means copying its
  private key onto every (untrusted) tenant node → one breach impersonates all; terminating it
  centrally means all tenant traffic flows through us → we become a data custodian/MITM
  (violates the zero-custody goal).

**Conclusion:** the fork is binary — *browser-trusted ⇒ per-node public ACME* (Tier 1 or 3),
or *self-issued ⇒ client installs a CA* (Tier 2). There is no third cell.

---

## The dmfdeploy.io PSL design (the promising path for Tier 3)

### Naming + PSL (the foundation)
```
box.dmfdeploy.io                     ← submitted to the PSL as a public suffix
└─ <env>.box.dmfdeploy.io            ← one env = one REGISTERED domain ⇒ its OWN LE bucket
   ├─ auth.<env>.box.dmfdeploy.io        → node
   ├─ console.<env>.box.dmfdeploy.io     → node   (one wildcard cert *.<env>.box.dmfdeploy.io)
   └─ …
```
- **PSL entry = the keystone.** Making `box.dmfdeploy.io` a public suffix means each
  `<env>.box.dmfdeploy.io` is its own registered domain → **its own LE rate-limit bucket**
  (one env can't starve others) **and browser site-isolation** (cookies/JS can't cross envs).
  Set via a **PR to `github.com/publicsuffix/list`** (NOT a Cloudflare action); **weeks** of
  propagation into browsers + LE; slow to reverse. Dedicate a sub-label (`box.`) so the apex
  `dmfdeploy.io` stays a normal site.

### Cloudflare (zone host) — one-time
- Zone `dmfdeploy.io` already on Cloudflare.
- One API token scoped *Zone:dmfdeploy.io / DNS:Edit*. **Cloudflare cannot scope a token to a
  single subdomain — only the whole zone.** That single fact drives the credential-placement
  decision below.

### Per-bootstrap flow
1. Wizard renders `base_domain=<env>.box.dmfdeploy.io`, `tls_mode=acme`, `acme_email`,
   `dns01_provider=cloudflare`. (No local CA.)
2. Create `*.<env>.box.dmfdeploy.io A <node-ip>` (one wildcard A covers all app hosts) → resolves
   everywhere, **no `/etc/hosts`**.
3. cert-manager requests `*.<env>.box.dmfdeploy.io` from LE via **DNS-01** (wildcards require it):
   writes `_acme-challenge.<env>.box… TXT`, LE validates, issues the **publicly-trusted** wildcard,
   TXT removed, cert+key stored in-cluster.
4. Traefik serves every app with it → green padlock, **secure context, no warning, no CA install**
   → passkeys work.
5. Rate limit counts against `<env>.box.dmfdeploy.io` — **its own bucket** (PSL). Isolated.

Teardown: delete the env's A record; cert expires. **Data we ever hold = a DNS record
(hostname→IP). No accounts, no PII, no cluster data.**

### The one real decision — where the DNS credential lives
A zone-wide Cloudflare token on a tenant node is an abuse vector (a popped node could rewrite any
dmfdeploy.io record). Two clean resolutions:
- **(A) Token stays on *our* side (cert-broker).** A small service of ours creates the A record
  and runs the DNS-01 challenge on the node's behalf; node makes its own keypair+CSR (key never
  leaves the node). All-Cloudflare, no extra DNS infra, but we operate the broker.
- **(B) acme-dns + CNAME delegation.** We run a tiny acme-dns; each node gets a credential that
  can write **only its own** `_acme-challenge` TXT; a static CNAME on Cloudflare points LE there.
  Max isolation; one more service to run.

Either way: node never holds a zone-wide key; we never hold tenant data.

---

## Open hardening requirements (operator-raised 2026-06-08) — ideas, not yet designed

Two further properties wanted for Tier 3, with idea sketches + honest limits:

### R1 — only *genuine, integrity-checked, unmodified* DMF systems may obtain a cert
This is **remote attestation**, defense-in-depth:
1. **Supply-chain integrity** — node verifies (cosign/sigstore + SLSA provenance) that the DMF
   images/charts/init-container it runs are the genuine signed artifacts (authentic DMF, not a fork).
2. **Hardware root of trust** — TPM 2.0 measured-boot quote, or cloud confidential-VM attestation
   (AWS Nitro, GCP Confidential VM vTPM, Azure attestation). The issuance broker (option A)
   verifies the signed attestation against known-good measurements **before** issuing, and binds
   the cert request to it.
3. **Continuous** — short-lived certs (hours) requiring *fresh* attestation on each renewal → a
   tampered node loses its cert within hours (self-healing).

**Honest limit:** a system whose owner is the adversary can be trusted only to the extent of its
hardware root of trust. Software-only attestation is defeatable by an operator who controls the
kernel; **TPM/confidential-VM is the only real assurance**, and even then it covers the
boot/platform layer, not arbitrary app-layer behavior after attestation. "Confirmed unchanged"
is achievable in proportion to available hardware trust: *confidential VM > TPM bare-metal >
software-only*.

### R2 — the certificate/key as inaccessible to the operator as possible
1. **Non-exportable hardware-backed key** — generate the TLS key inside a **TPM / PKCS#11 HSM /
   cloud KMS**, marked non-exportable; the node signs handshakes via the device but can't extract
   the key.
2. **Confidential-compute termination** — terminate TLS inside an enclave (SEV-SNP / TDX
   confidential VM, or Nitro enclave) so key + plaintext live only in memory the host OS/operator
   can't read.
3. **Short-lived + auto-rotate** — minimize the value/window of any extracted material;
   re-issuance requires re-attestation (ties R2 back to R1).

**Honest limit:** if TLS terminates on a node where the operator has root and there is no hardware
key isolation, a determined operator can always read the key/plaintext from memory. True
inaccessibility **requires hardware** (non-exportable TPM/HSM key, or confidential computing).
There is also a **philosophical tension**: protecting the cert *from* the operator means trusting
hardware more than the operator — a shift away from the "operator is sovereign" ethos (ADR-0028
two-layer identity); adopt deliberately.

### Reframe — what R1+R2 actually protect
A per-env dmfdeploy.io cert only covers that env's *own* name, which the operator already controls
— so extracting it enables **no cross-tenant** compromise. The real asset is **dmfdeploy.io's
reputation**: only genuine DMF nodes should fly under our domain, so it doesn't become a
phishing/malware haven that gets the parent blocklisted. R1+R2 are primarily **domain-reputation /
abuse controls**, not cross-tenant secrecy — which should right-size the effort.

### Other abuse vectors already noted
Phishing under a trusted subdomain (mitigate: encoded/opaque env names, never vanity labels;
proof-of-IP-control gate; CAA; per-name throttle + monitoring + fast revoke); subdomain takeover
(stateless/derivable naming sidesteps); ToS + abuse contact.

---

## Decision (2026-06-08)
**OSS / v0.1 ships Tiers 1 + 2 only** — Tier 1 *own-domain ACME* (tester's domain + their LE
bucket; zero maintainer custody) and Tier 2 *local CA* (sslip.io default; one-time CA-trust;
zero custody). The CA-trust step stays an accepted cost of the OSS local-CA lane.

**Tier 3 (dmfdeploy.io) is deferred to a future managed-service model** and is **drawn cleanly
apart from OSS**: OSS users never touch dmfdeploy.io. Rationale — **dmfdeploy.io's domain
reputation is a key asset**; letting arbitrary OSS nodes fly under it is exactly how a parent
domain gets blocklisted. Reputation is best protected by *not* exposing the domain until there's
a managed-service context with the attestation (R1) + key-inaccessibility (R2) + abuse controls
to back it.

When the managed-service model is taken up, the design above (PSL per-env registered domains +
Cloudflare/DNS-01 + broker-vs-acme-dns + R1/R2 hardening) is the captured starting point. **Not
now.**

## Consequences (if adopted)
- A maintainer-operated service (DNS/acme-dns/broker + abuse desk) + PSL footprint + LE
  relationship; a central dependency/SPOF for Tier-3 users.
- R1/R2 pull in TPM/confidential-compute + supply-chain signing — substantial complexity and
  cloud/hardware dependencies; almost certainly **out of scope for the experiment phase**
  (ADR-0004 stance / commitments-v1) until a concrete need exists.

## Open questions
1. Is Tier 3 worth operating at all, vs. shipping only Tiers 1+2?
2. Credential placement: broker (A) vs acme-dns (B)?
3. Naming: opaque per-env slug vs IP-encoded vs vanity (phishing surface).
4. How far into R1/R2 is justified — software-only, TPM, or confidential-VM — given the
   reputation-not-secrecy reframe?
5. PSL submission timing (weeks of lead) — do it speculatively now or only on adoption?
