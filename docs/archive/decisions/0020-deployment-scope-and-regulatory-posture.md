# ADR-0020 archive: Deployment scope and regulatory posture — three named modes

This file holds material moved out of [ADR-0020](../../decisions/0020-deployment-scope-and-regulatory-posture.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

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

## Enforcement — reference downstream (moved from the ADR)

Reference downstream:

- [`docs/plans/DMF Pre-Release Compliance Readiness Plan 2026-05-11.md`](../../plans/DMF%20Pre-Release%20Compliance%20Readiness%20Plan%202026-05-11.md)
- [`docs/processes/pre-release-compliance-checklist.md`](../../processes/pre-release-compliance-checklist.md)
- [`dmf-infra/docs/security-compliance-framework-plan.md`](../../../dmf-infra/docs/security-compliance-framework-plan.md) (amended to point here)

## Amendment 2026-05-23 — operator answer (moved from the ADR)

The operator answered the `adr-0020-promote` seed gate on 2026-05-12 with:

> *"Mode A only. Experiment phase; no managed-service or flypack partner
> yet. B and C become future ADRs when there's a concrete driver."*

## Context — regulatory regimes background (moved from the ADR)

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


## Moved from the ADR on 2026-10-23

### Context (moved from the ADR)

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

Regulatory background: see the [archive record](0020-deployment-scope-and-regulatory-posture.md).

### 2026-05-30 correction note (moved from the ADR)

> **2026-05-30 correction (portfolio-review §2.2):** an earlier draft of
> this paragraph predicted "ADR-0028 managed-service, ADR-0029
> flypack-offline." Those numbers were assigned to **other** decisions:
> ADR-0028 is the Identity & Authority Chain, ADR-0029 is the Tiered
> Unseal Posture. Do not infer Mode B/C ADR numbers from this section;
> they will be numbered when written.

### Positive and neutral consequences (moved from the ADR)

- **Positive**
  - Every downstream compliance question now has a "for which mode?"
    answer instead of a deferred decision.
  - The "experiment phase" stance (ADR-0004) can continue to apply to
    Mode A development while Mode B and Mode C accrue their own
    readiness gates.
  - The customer-conversation boundary is explicit: managed = attested
    + supported, self-host = framework-provided + as-is, flypack =
    Mode B obligations plus portable-media controls.
- **Neutral**
  - Adopts the GitLab / Sentry / Coder / Replicated multi-modal model
    rather than the Elastic / Redis pure-OSS-plus-cloud model. The
    distinction is enforced via external-service gating (see B.4),
    chosen to avoid Elastic-style relicensing fights.
  - Mode A is what is currently being prepared for the github.com push
    per the 2026-05-07 Public Publish Readiness handoff; this ADR
    formalizes the implicit posture.
