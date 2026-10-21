# ADR-0040: Public-TLS tiering + dmfdeploy.io PSL design (removing the CA-trust step)

**Status:** Accepted (scoping decision, 2026-06-08) — **OSS uses Tiers 1 + 2 only;
dmfdeploy.io (Tier 3) is deferred to a future *managed-service* model and kept entirely separate
from OSS to protect the domain's reputation.** The Tier-3 design + hardening are **captured
for that future phase** in the [archive record](../archive/decisions/0040-public-tls-tiering-and-dmfdeploy-io-psl.md), not built now. (Reasoning/dead-ends recorded so they aren't re-derived
or re-proposed.)

**Date:** 2026-06-08
**Deciders:** @<handle>
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

Implementation detail: see the [archive record](../archive/decisions/0040-public-tls-tiering-and-dmfdeploy-io-psl.md).

## Consequences (if adopted)

- A maintainer-operated service (DNS/acme-dns/broker + abuse desk) + PSL footprint + LE
  relationship; a central dependency/SPOF for Tier-3 users.
- R1/R2 pull in TPM/confidential-compute + supply-chain signing — substantial complexity and
  cloud/hardware dependencies; almost certainly **out of scope for the experiment phase**
  (ADR-0004 stance / commitments-v1) until a concrete need exists.

## Status

Accepted (scoping decision, 2026-06-08) — **OSS uses Tiers 1 + 2 only;
dmfdeploy.io (Tier 3) is deferred to a future *managed-service* model and kept entirely separate
from OSS to protect the domain's reputation.** The Tier-3 design + hardening are **captured
for that future phase** in the [archive record](../archive/decisions/0040-public-tls-tiering-and-dmfdeploy-io-psl.md), not built now. (Reasoning/dead-ends recorded so they aren't re-derived
or re-proposed.)

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0040-public-tls-tiering-and-dmfdeploy-io-psl.md).
