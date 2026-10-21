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
