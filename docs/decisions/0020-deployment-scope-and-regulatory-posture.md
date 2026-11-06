# ADR-0020: Deployment scope and regulatory posture (three named modes)

**Status:** Accepted
**Date:** 2026-05-11
**Amended:** 2026-05-23; Mode A promoted to Accepted; Modes B and C remain Proposed pending a real driver (see §Amendment 2026-05-23).
**Deciders:** operator
**Rule:** DMF ships in three named modes, each with a binding regulatory posture and a binding architectural constraint. Only Mode A (OSS self-host, no attestation, zero outbound calls to dmfdeploy.io) is Accepted here; the Mode B (managed service) and Mode C (flypack) constraints stay Proposed in [ADR-0049](0049-managed-service-mode-dmfdeploy-io.md) and [ADR-0050](0050-flypack-mode-portable-offline-kit.md).

## Context

Every ISO 27001, NIS2 and GDPR control's applicability depends on whether DMF
is a lab, a customer-hosted reference or a managed service. As of 2026-05-11
DMF ships as three distinct modes, and one posture cannot cover them without
over-claiming (treating OSS self-host as attested) or over-building (applying
managed-service controls to the lab and OSS modes). Regulatory background and
the full context are in the [archive record](../archive/decisions/0020-deployment-scope-and-regulatory-posture.md).

## Decision

DMF ships in three explicitly named modes, each with a binding
regulatory posture and a binding architectural constraint.

### Mode A: OSS self-host (`github.com/dmfdeploy/*`)

**Regulatory posture:** None claimed. Apache-2.0, "use at own risk."
Self-host operators are themselves responsible for any compliance work
they pursue. The repos provide the **framework** (see
[`dmf-infra/docs/security-compliance-framework-plan.md`](../../dmf-infra/docs/security-compliance-framework-plan.md))
but no attestation.

**Binding architectural constraint:** No dependency on dmfdeploy.io
services required to operate. The OSS clone must boot, provision, and
serve a working DMF cluster with **zero outbound calls to dmfdeploy.io**.
Telemetry and registration are explicitly out of scope for this mode.

### Amendment 2026-05-23: Mode A Accepted; Modes B and C remain Proposed

The operator answered the promotion gate on 2026-05-12 with "Mode A only":
the full answer is in the [archive record](../archive/decisions/0020-deployment-scope-and-regulatory-posture.md).
Reconciling that answer with this ADR's promotion gates:

- **Mode A is Accepted as of 2026-05-23.** It is the active deployment
  mode. Its single binding constraint (no outbound dependency on
  `dmfdeploy.io`) is what `dmf-runbooks`, public registry pushes,
  `bin/scrub-public-repos.sh`, and the public-publish prep work all
  enforce in practice today. The Mode-A "promote when…" gates in the Status section
  (B.4 boundary confirmation, B.3 unit-economics, ADR-0011 Mode B exit,
  GDPR role split, flypack reference platform) describe **Mode B / Mode C**
  promotion. Promoting Mode A does not require any of them.

**Mode B and Mode C may be split into their own ADRs** (numbers assigned
at creation time) at the moment a real driver appears, replacing the
B / C sections of this ADR with cross-refs. Until then, keeping them in
this ADR preserves the "three-mode framing" context. Do not infer Mode B/C
ADR numbers from this section: ADR-0028 and ADR-0029 are other decisions
(Identity & Authority Chain, Tiered Unseal Posture), and the Mode B/C ADRs
will be numbered when written.

#### What flips on 2026-05-23 promotion of Mode A

- Mode-A enforcement (`bin/check-public-repo-hygiene.sh` /
  `bin/scrub-public-repos.sh` Mode-A gates) is no longer "discipline-only."
  It is policy. New public-publish prep work for the remaining repos
  (`dmf-cms`, `dmf-central`, `dmf-infra`, `dmf-media`, umbrella) MUST
  pass these gates before publish (Move 7 prep).
- The compliance-framework plan and pre-release-compliance-checklist
  reference downstream stop treating Mode A's posture as "to be
  determined": it is fixed at "no attestation claimed; Apache-2.0 use
  at own risk."
- No public-repo manifest, default, or Helm value may add a runtime
  dependency on `dmfdeploy.io`-resident services without superseding
  this ADR's Mode A constraint.

#### What does NOT flip

- Mode B's architectural constraints (B.1–B.4) and Mode C's (C.1–C.4)
  remain authoritative reference text but bind no implementation today.
- ADR-0011 (auto-unseal tradeoff) is unaffected. Its experiment-phase
  posture lives under Mode A, where the operator-local automation quorum
  is acceptable. The "Mode B exit path" requirement only attaches if
  and when Mode B promotes.
- ADR-0027's promotion criterion #4 ("ADR-0020 promotes to Accepted with
  Mode B active") still refers to a future Mode-B-Accepted event. This
  Mode-A-only promotion does not trigger it. Cross-reference updated in
  ADR-0027.

## Alternatives considered

Each was rejected:

- **Single posture "we are a managed service":** it over-applies NIS2 MSP
  controls to the OSS lab work, kills experiment-phase velocity, and forces
  the cluster-per-tenant decision before it is needed in Mode A.
- **Single posture "we are OSS only, refer customers elsewhere":** it forgoes
  the dmfdeploy.io revenue plan and the flypack differentiation, and the
  product ceiling is low.

## Consequences

- **Negative**
  - More artifacts to maintain (three terms documents, three trust
    packages eventually).

The positive and neutral consequences are in the [archive record](../archive/decisions/0020-deployment-scope-and-regulatory-posture.md).

### Enforcement

Discipline only: no script, test or workflow checks any of the three modes.
On 2026-10-23, a grep of the umbrella and every component repo's `bin`,
`scripts`, `.github` and `.githooks` paths for `dmfdeploy.io` found no match.
`bin/sync-to-github.sh` gates publishing on `bin/scrub-public-repos.sh`, the
author check and gitleaks; `bin/check-public-repo-hygiene.sh` runs only from
`bin/export-scan.sh`. The 2026-05-23 amendment makes passing both scripts
policy, but neither detects an outbound dependency on dmfdeploy.io.

- **Mode A "no outbound to dmfdeploy.io" constraint:** the intended check is
  an extension of `bin/check-public-repo-hygiene.sh` (per the Release &
  Contribution Model implementation plan, Phase 2) that greps public-repo
  manifests, defaults, and Helm values for `dmfdeploy.io` and fails on hit.
  Until that script lands, the constraint is discipline only.

Reference downstream links: see the [archive record](../archive/decisions/0020-deployment-scope-and-regulatory-posture.md).

## Status

Accepted

Status history: until 2026-11-06 this ADR also carried Mode B and Mode C, each Proposed. Mode B is now [ADR-0049](0049-managed-service-mode-dmfdeploy-io.md) and Mode C is [ADR-0050](0050-flypack-mode-portable-offline-kit.md). The amendment above is kept as written, so it still describes the split as a later step. The split was made to give each Proposed mode its own record; it does not mean the amendment's condition for a split was met.

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0020-deployment-scope-and-regulatory-posture.md).
