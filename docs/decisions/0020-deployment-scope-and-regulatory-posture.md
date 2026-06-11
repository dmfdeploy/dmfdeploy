## ADR-0020: Deployment scope and regulatory posture — three named modes

**Status:** Accepted (Mode A); Proposed (Mode B, Mode C)
**Date:** 2026-05-11
**Amended:** 2026-05-23 — Mode A promoted to Accepted; Modes B and C remain Proposed pending a real driver (see §Amendment 2026-05-23).
**Deciders:** operator

## Context

`dmf-infra/docs/security-compliance-framework-plan.md` §"Open Questions"
left the central scope question unanswered: *"is this a lab / customer-hosted
reference / managed service?"*. Every ISO 27001 / NIS2 / GDPR control's
**applicability** hinges on this answer, and the answer determines whether
several architectural decisions are cheap (now) or expensive (later).

The operating stance has shifted as of 2026-05-11: DMF is intended to ship
as **three distinct deployment modes**, not one. The compliance and
architectural implications of each are materially different and cannot be
collapsed into a single posture without producing one of two failure modes:

- **Over-claim:** treat OSS self-host as if it were attested, misleading
  downstream operators
- **Over-build:** apply managed-service controls to the lab and OSS modes,
  stalling experimentation under audit weight

The three modes are also not equivalent in terms of which EU regulatory
regimes attach: as of May 2026, **NIS2 Implementing Regulation (EU)
2024/2690** (17 Oct 2024) sets a technical floor for *managed service
providers* under Annex I §8; the Directive itself
([Directive (EU) 2022/2555](https://eur-lex.europa.eu/eli/dir/2022/2555/oj))
imposes 24h / 72h / 1-month incident-reporting on essential and
important entities; GDPR Art. 28 processor obligations attach the
moment dmfdeploy.io processes customer-hub data on a customer's behalf.
Mode B also creates controller obligations for dmfdeploy.io's own
account, billing, support, security-log, and vulnerability-intake data.
None of this attaches to a clone-and-self-host user.

## Decision

DMF ships in three explicitly-named modes, each with a binding
regulatory posture and a binding architectural constraint:

### Mode A — OSS self-host (`github.com/dmfdeploy/*`)

**Regulatory posture:** None claimed. Apache-2.0, "use at own risk."
Self-host operators are themselves responsible for any compliance work
they pursue. The repos provide the **framework** (see
[`dmf-infra/docs/security-compliance-framework-plan.md`](../../dmf-infra/docs/security-compliance-framework-plan.md))
but no attestation.

**Binding architectural constraint:** No dependency on dmfdeploy.io
services required to operate. The OSS clone must boot, provision, and
serve a working DMF cluster with **zero outbound calls to dmfdeploy.io**.
Telemetry and registration are explicitly out of scope for this mode.

### Mode B — Managed service (`dmfdeploy.io`)

**Regulatory posture:** Full NIS2 *managed service provider* scope under
Annex I §8, governed by Implementing Reg. (EU) 2024/2690. GDPR Art. 28
processor obligations attach for customer-hub processing performed on a
customer's behalf; dmfdeploy.io remains controller for its own account,
billing, support, security-log, and vulnerability-intake processing.
ISO 27001 readiness is a customer-facing claim (Statement of
Applicability + Trust Package required). Schrems II analytic frame
applies to any third-country vendor in the stack (notably Aliyun,
regardless of region — see
[EDPB Recs 01/2020 v2.0](https://www.edpb.europa.eu/system/files/2021-06/edpb_recommendations_202001vo.2.0_supplementarymeasurestransferstools_en.pdf)).

**Binding architectural constraints:**

1. **Shamir shares originate customer-side, never traverse dmfdeploy.io.**
   The control plane orchestrates; the customer holds the unseal quorum
   from second 1. Sigstore-style "dmfdeploy.io signs, customer verifies"
   pattern for image and config provenance. This is the dividing line
   between "we are a data processor" and "we are a software supplier."
   This constraint is incompatible with the experiment-phase
   auto-unseal tradeoff accepted in
   [ADR-0011](0011-auto-unseal-tradeoff.md), where an operator-local
   automation file holds a Shamir quorum. Before Mode B ships, that
   automation-quorum path must be removed or replaced for customer hubs
   (for example by HA OpenBao with manual initial unseal, or by a
   customer-side unseal ceremony whose share material never reaches
   dmfdeploy.io systems or agent transcripts).
2. **No long-lived customer cloud credentials at rest in dmfdeploy.io.**
   Use OIDC/workload-identity federation where the provider supports it
   (for example AWS IAM Roles Anywhere or GCP Workload Identity).
   Provider-specific bootstrap mechanisms such as Hetzner cloud-init
   seed are not federation; they are acceptable only when customer-side,
   ephemeral, and documented as a non-federated bootstrap path.
   Providers without federation (Aliyun, small clouds) are handled
   out-of-band via the customer's own credential vault and logged as
   residual risk in their TIA.
3. **Cluster-per-tenant, not multi-tenant-shared-cluster.** Inherits
   from the existing Authentik-per-cluster + `dmf-central` scaffold
   posture. Wrong for unit economics; right for compliance blast-radius
   and is the binding constraint that lets us answer customer auditors
   honestly.
4. **OSS / managed boundary is enforced by external-service gating, not
   feature flags.** Managed features (multi-tenant billing,
   hub-orchestration UI, support-portal hooks) require an API key from
   dmfdeploy.io to function; they may live in the public OSS repos as
   "dormant" code but provide no value without the managed API. Avoids
   the open-core fragmentation and the feature-flag-flip risk.

### Mode C — Flypack (portable offline kit)

**Regulatory posture:** Mode B obligations *plus* ISO 27001 A.7.10
(Storage media), A.7.13 (Equipment maintenance), A.7.14 (Secure disposal)
applied to physical hardware; EBU R 143 vendor-systems acceptance for
the assembled kit. Lost or stolen flypack = mandatory 72h GDPR Art. 33
breach assessment.

**Binding architectural constraints:**

1. **Per-flypack ephemeral identity** issued at first boot via a
   provisioning ceremony; no shared identities across flypacks.
2. **Secrets sealed to local TPM/HSM**, never recoverable from disk
   alone. Shamir share threshold inside the unit, recovery shares held
   by the operator off-pack.
3. **Tamper-evident enclosure + documented loss procedure** in the
   incident response runbook before any flypack ships.
4. **No automatic phone-home.** If a flypack reconnects to dmfdeploy.io
   it does so via an explicitly-installed customer-side relay; the
   flypack must function disconnected.

## Consequences

- **Positive**
  - Every downstream compliance question now has a "for which mode?"
    answer instead of a deferred decision.
  - The "experiment phase" stance (ADR-0004) can continue to apply to
    Mode A development while Mode B and Mode C accrue their own
    readiness gates.
  - The customer-conversation boundary is explicit: managed = attested
    + supported, self-host = framework-provided + as-is, flypack =
    Mode B obligations plus portable-media controls.
- **Negative**
  - More artifacts to maintain (three terms documents, three trust
    packages eventually).
  - The cluster-per-tenant decision (B.3) commits us to higher
    per-tenant cost than a multi-tenant SaaS would; this is a
    deliberate trade for clean compliance blast-radius and is binding.
  - Mode B and Mode C *require* compliance work to ship; cannot be
    deferred indefinitely the way Mode A can.
  - Mode B requires retiring or superseding the ADR-0011 auto-unseal
    tradeoff for customer hubs; the current experiment-phase automation
    quorum must not become a managed-service security claim.
- **Neutral**
  - Adopts the GitLab / Sentry / Coder / Replicated multi-modal model
    rather than the Elastic / Redis pure-OSS-plus-cloud model. The
    distinction is enforced via external-service gating (see B.4),
    chosen to avoid Elastic-style relicensing fights.
  - Mode A is what is currently being prepared for the github.com push
    per the 2026-05-07 Public Publish Readiness handoff; this ADR
    formalizes the implicit posture.

## Alternatives considered

- **Single posture ("we are a managed service")** — over-applies NIS2
  MSP controls to the OSS lab work, kills experiment-phase velocity,
  and forces the cluster-per-tenant decision before it's needed in Mode
  A. Rejected.
- **Single posture ("we are OSS only, refer customers elsewhere")** —
  forgoes the dmfdeploy.io revenue plan and the flypack differentiation;
  the strategic review's career-credibility goal is met but the product
  ceiling is low. Rejected.
- **Open-core (managed features in a private repo)** — works
  commercially but creates an "are you really OSS?" conversation we
  don't need at v0.1.0. Rejected in favour of external-service-gated
  managed features (B.4).
- **Multi-tenant shared cluster for Mode B** — better unit economics,
  worse compliance blast-radius, and incompatible with the existing
  Authentik-per-cluster / `dmf-central` posture. Rejected.

## Enforcement

This ADR binds three things; each has a different enforcement path:

- **Mode A "no outbound to dmfdeploy.io" constraint:** enforced by
  `bin/check-public-repo-hygiene.sh` (per the Release & Contribution
  Model implementation plan, Phase 2) — extend it to grep for
  `dmfdeploy.io` in public-repo manifests, defaults, and Helm values
  and fail on hit. Until that script lands, discipline-only.
- **Mode B architectural constraints (B.1–B.4):** enforced by ADRs that
  follow once Mode B implementation starts; until then, this ADR is the
  authoritative reference. No code in `dmf-central` or the umbrella may
  contradict B.1–B.4 without superseding this ADR. The first Mode B
  implementation ADR must explicitly close the ADR-0011 auto-unseal
  gap and include a GDPR controller/processor role matrix.
- **Mode C architectural constraints (C.1–C.4):** enforced by the
  flypack readiness checklist (Tier C of the
  [Pre-Release Compliance Readiness Plan](../plans/DMF%20Pre-Release%20Compliance%20Readiness%20Plan%202026-05-11.md)).
  No flypack ships without that checklist clean.

Reference downstream:

- [`docs/plans/DMF Pre-Release Compliance Readiness Plan 2026-05-11.md`](../plans/DMF%20Pre-Release%20Compliance%20Readiness%20Plan%202026-05-11.md)
- [`docs/processes/pre-release-compliance-checklist.md`](../processes/pre-release-compliance-checklist.md)
- [`dmf-infra/docs/security-compliance-framework-plan.md`](../../dmf-infra/docs/security-compliance-framework-plan.md) (amended to point here)

Promote from **Proposed** → **Accepted** when:

1. The OSS-vs-managed boundary (B.4) has been confirmed by the operator
   as the chosen pattern (alternatives explicitly rejected above).
2. The cluster-per-tenant constraint (B.3) has survived a unit-economics
   sanity check.
3. The ADR-0011 auto-unseal tradeoff has a named Mode B exit path
   (HA OpenBao, customer-side ceremony, or another design that keeps
   Shamir quorum material outside dmfdeploy.io custody).
4. The GDPR role split has a first-pass matrix: dmfdeploy.io as
   processor for customer-hub data and controller for its own account,
   billing, support, security-log, and vulnerability-intake data.
5. The flypack hardware story (C.1–C.4) has at least one identified
   reference platform (TPM-equipped mini-PC class).

## Amendment 2026-05-23 — Mode A Accepted; Modes B and C remain Proposed

The operator answered the `adr-0020-promote` seed gate on 2026-05-12 with:

> *"Mode A only. Experiment phase; no managed-service or flypack partner
> yet. B and C become future ADRs when there's a concrete driver."*

Reconciling that answer with this ADR's promotion gates:

- **Mode A is Accepted as of 2026-05-23.** It is the active deployment
  mode. Its single binding constraint (no outbound dependency on
  `dmfdeploy.io`) is what `dmf-runbooks`, public registry pushes,
  `bin/scrub-public-repos.sh`, and the public-publish prep work all
  enforce in practice today. The Mode-A "promote when…" gates above
  (B.4 boundary confirmation, B.3 unit-economics, ADR-0011 Mode B exit,
  GDPR role split, flypack reference platform) describe **Mode B / Mode C**
  promotion, not Mode A. Promoting Mode A does not require any of them.

- **Mode B (managed `dmfdeploy.io`) remains Proposed.** The B.1–B.4
  architectural constraints stand as the authoritative reference for any
  future managed-service work, but no Mode B work is in flight and no
  ship date is committed. Promotion is gated on the original criteria 1–4
  above and on a concrete managed-service driver (paying customer pilot,
  funded contract, or explicit dmfdeploy.io GmbH formation).

- **Mode C (flypack) remains Proposed.** ADR-0022 (flypack-online thin
  edge) already split out the WAN-paired variant; flypack-offline (Mode C
  as originally framed) still awaits hardware-reference work. Promotion
  is gated on criterion 5 above plus a named operator/integrator partner
  for the sealed-hardware ceremony.

**Mode B and Mode C may be split into their own ADRs** (numbers assigned
at creation time) at the moment a real driver appears, replacing the
B / C sections of this ADR with cross-refs. Until then, keeping them in
this ADR preserves the "three-mode framing" context that the consequences
and alternatives sections lean on.

> **2026-05-30 correction (portfolio-review §2.2):** an earlier draft of
> this paragraph predicted "ADR-0028 managed-service, ADR-0029
> flypack-offline." Those numbers were assigned to **other** decisions —
> ADR-0028 is the Identity & Authority Chain, ADR-0029 is the Tiered
> Unseal Posture. Do not infer Mode B/C ADR numbers from this section;
> they will be numbered when written.

### What flips on 2026-05-23 promotion of Mode A

- Mode-A enforcement (`bin/check-public-repo-hygiene.sh` /
  `bin/scrub-public-repos.sh` Mode-A gates) is no longer "discipline-only,"
  it is policy. New public-publish prep work for the remaining repos
  (`dmf-cms`, `dmf-central`, `dmf-infra`, `dmf-media`, umbrella) MUST
  pass these gates before publish (Move 7 prep).
- The compliance-framework plan and pre-release-compliance-checklist
  reference downstream stop treating Mode A's posture as "to be
  determined" — it is fixed at "no attestation claimed; Apache-2.0 use
  at own risk."
- No public-repo manifest, default, or Helm value may add a runtime
  dependency on `dmfdeploy.io`-resident services without superseding
  this ADR's Mode A constraint.

### What does NOT flip

- Mode B's architectural constraints (B.1–B.4) and Mode C's (C.1–C.4)
  remain authoritative reference text but bind no implementation today.
- ADR-0011 (auto-unseal tradeoff) is unaffected — its experiment-phase
  posture lives under Mode A, where the operator-local automation quorum
  is acceptable. The "Mode B exit path" requirement only attaches if
  and when Mode B promotes.
- ADR-0027's promotion criterion #4 ("ADR-0020 promotes to Accepted with
  Mode B active") still refers to a future Mode-B-Accepted event, not
  this Mode-A-only promotion. Cross-reference updated in ADR-0027.
