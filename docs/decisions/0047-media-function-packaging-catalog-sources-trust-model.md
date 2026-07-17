<!-- ADR doc convention: every ADR carries a top-of-doc **Rule:** line — the binding
constraint in one imperative sentence — directly under the metadata block. See
CONTRIBUTING.md → "ADR conventions". -->
# ADR-0047: Media Function packaging, catalog sources and trust model

**Status:** Accepted
**Date:** 2026-07-17
**Deciders:** @znerol2 (Discussion [#248](https://github.com/dmfdeploy/dmfdeploy/discussions/248)), with Claude; codex adversarial cross-check (RFC 3 rounds → PASS)
**Rule:** A media function enters a catalog only as a signed, digest-pinned **Media Function Package** from a classed catalog source (`project` / `vendor` / `community`); bespoke launcher playbooks are `project`-source-only, everything else goes through the generic declarative launcher under `generic-chart-policy/v1`, and nothing deploys past a revocation record — fail closed.
**Cross-references / touches:** ADR-0013 (catalog model — extended, not replaced), ADR-0025 (in-cluster EE + Helm-from-Zot — why launcher code is privileged), ADR-0027 (**checklist source only** — its CRD/operator design stays retired per ADR-0037), ADR-0032/0033 (scoped writers — the per-publisher Zot namespace is a sibling), ADR-0034 (internal mirrors — generalized to catalog sources), ADR-0036 (offline bundle stays a future profile beside dmf-init), ADR-0037 (NetBox scopes; k3s schedules; AWX reconciles — untouched), ADR-0041 (GitHub + DCO contribution path), ADR-0043 (AWX sole actuator — untouched), ADR-0045 (licence seam — presence enforcement **not** decided here)
**Plan:** `docs/plans/DMF Marketplace Resource Model and Placement Grounded Roadmap 2026-07-17.md` (#245); RFC converged in Discussion #248 (tracked by #204)

## Context

The catalog is first-party-only: entries, charts, launchers and AWX seeding are
smeared across `dmf-media`/`dmf-runbooks`/`dmf-infra`, all fully trusted, with
no publisher identity, provenance, signatures, or trust gradations anywhere in
the chain. A launcher playbook is arbitrary code executing in an AWX EE pod
with Kubernetes and NetBox write authority (ADR-0025/0032) — so third-party
contribution is structurally impossible today without handing strangers the
control plane. The real tension: preserve the property that made the catalog
good (adding a function is a pure-git, digest-pinned operation) while opening
a contribution path whose trust is graded, enforceable, and honest about what
is built versus designed.

## Decision

### 1. Four separate axes — never one "trust tier"

1. **Source class** — who controls the catalog source. Exactly three:
   `project` (dmfdeploy maintainers, via the project-controlled catalog-source
   index; deliberately not named "official" — no corporate authority implied),
   `vendor` (identified external publisher, project-indexed), `community`
   (external/local/unaffiliated). Source class is project-controlled **source
   metadata**; a package can never assert its own class.
2. **Release promotion state** — `Draft → Candidate → Approved → Certified →
   Stable → Revoked` (semantics in §3). The console's "testing" label is a
   derived display for pre-`Approved` states of any source class — never a
   schema value.
3. **Support attribute** — `none` / `best_effort` / `lts`; a policy attribute,
   not a trust boundary and not a commercial SLA.
4. **Launcher privilege** — derived from source class by rule (§4); never
   stored as a package field.

### 2. The Media Function Package

The contribution unit is: catalog metadata (ADR-0013 schema) + **Helm chart**
+ image closure + probes + declared `resources.requests` + `licence:` block +
provenance + cosign/Sigstore signatures. Pinning covers the full closure:
catalog-source commit SHA, chart digest, every image digest, chart
dependencies, provenance URI.

- **Helm is the mandatory v1 baseline.** Operator bundles, CRDs, controllers,
  webhooks, or any other cluster machinery are not accepted through the
  generic path — publishers ship apps, not new cluster machinery. If an
  operator install path is ever needed, it requires its own ADR.
- Signatures are verified at **promotion/ingestion time** (cosign/Sigstore for
  charts, images, provenance, revocation metadata). Kubernetes runtime
  admission enforcement (Kyverno-class) remains deferred Stage-5 hardening.
- `resources.requests` are raw admission-preflight inputs (L3), deliberately
  not a certified resource profile — the capability-classes RFC owns that
  ladder. **Anti-regression rule:** a publisher must not reduce a certified
  declaration in a later release without revalidation.
- The `licence:` block stays declared-but-not-enforced per the ADR-0045 seam;
  whether licence *presence* is enforced at promotion is **explicitly not
  decided here** and belongs to ADR-0045's ratification.

### 3. Promotion states and quorums

- `Draft` — publisher/source-owned; not deployable by default.
- `Candidate` — submitted; automated checks + maintainer triage; still
  pre-approved ("testing" label).
- `Approved` — provenance/signatures verified; schema + generic chart policy
  pass; deployable per §5's source-class rules.
- `Certified` — Approved + validation evidence for the declared envelope
  (resources, probes, compatibility, policy fixtures).
- `Stable` — Certified + an explicit maintenance commitment for the release
  line (vulnerability/revocation updates expected; not a commercial SLA).
- `Revoked` — blocked for new deploys fail-closed; running instances flagged
  loudly; teardown stays an operator decision.

Quorums: a new `vendor` publisher slug and every promotion to
`Approved`/`Certified`/`Stable` require **two project maintainers**; a
publisher never counts toward its own quorum. **Revocation requires one
maintainer** (emergency fail-closed action; second-maintainer review follows
but never blocks denial). Publisher slug ownership binds through the
project-controlled **catalog-source index** — not package YAML.

### 4. Launcher privilege boundary

**Bespoke launcher playbooks are `project`-source-only.** All other classes
get the **generic declarative launcher** (chart + values + netbox_service +
probes, nothing else) validated under `generic-chart-policy/v1` (normative
appendix below). A future "privileged vendor" launcher class (isolated AWX
project, dedicated SA/RBAC, static checks, approval quorum) is deferred to
its own ADR — "reviewed" is not a boundary.

### 5. Deployability (honest about what exists)

- `project` — deployable, as today.
- `vendor` — **browse-only until the generic launcher and its ingestion
  policy are implemented** (Horizon-2 build items; listing precedes
  deployability by design).
- `community` and pre-`Approved` releases — browse-only / disabled by
  default even after the generic launcher exists. Deploying one is a
  **trust-bypass** operator override (C5 reason + audit, deliberately heavier
  than the L3 capacity override), confined to designated quarantined
  non-media nodes; packages touching the media data plane stay
  non-deployable outside dedicated isolation (hostile data-plane separation
  is unsolved — Vendor Multi-Tenancy Vision).

### 6. Promotion, revocation, and offline propagation

Promotion is a reviewed git change of a digest-pinned catalog-source
reference; history is the audit trail. Revocation additionally has
**current-state enforcement**: a signed revocation record (deny-list) with a
freshness bound, consumed fail-closed by catalog assembly, mirror/seeding
(630-pattern), console display, launcher preflight on every entry path, and
running-instance reconciliation (warnings). Stale or missing revocation
metadata beyond the freshness bound fails closed for the affected sources.
Already-mirrored Zot artifacts are retained but marked, never re-seeded.

Air-gapped sites update via a **signed offline bundle** applied through the
dmf-init/Manage flow (environment credentials authorize the apply; bundle
signatures prove content): catalog-index updates, charts, image blobs,
provenance/signatures, revocation records, vulnerability/advisory metadata,
trust/keyring updates, and a signed manifest with sequence/`generated_at`/
`valid_until`. Revocations are processed first and override additions in the
same bundle. Key rotation must be signed by the currently trusted chain;
emergency root-key replacement is a manual, audited operator action. Bundle
**tooling** is deferred (a future profile beside dmf-init, per ADR-0036);
this ADR fixes the bundle's shape only.

### 7. Schema

- `publisher` — identity slug only; ownership binds through the
  catalog-source index. Package identity is the tuple publisher + package
  key + version + artifact digest.
- `origin` — provenance record (source commit SHA + provenance URI).
- Source class lives in the catalog-source index, never on the package.
- The catalog-source index itself (schema, field ownership, collision rules,
  reserved namespaces, what is signed) is the first implementation
  deliverable under this ADR.

## Consequences

- **Positive** — third-party contribution has a defined, graded path that
  never hands out control-plane execution; promotion/revocation stay pure-git
  plus one signed deny artifact; the four-axis model kills the
  trust/maturity/privilege conflation; air-gap propagation has a defined
  shape; everything unbuilt is named as unbuilt.
- **Negative** — two-maintainer quorums put real load on a two-maintainer
  project; ingestion-time policy validation is substantial machinery to
  build before any vendor deployability exists; browse-only vendor listings
  may disappoint eager publishers.
- **Neutral** — current first-party entries become `project`-source packages
  with no behavior change; ADR-0013's catalog model is extended, not
  replaced; the actuator chain (ADR-0025/0037/0043) is untouched.

## Alternatives considered

- **Single trust_tier axis** (RFC rev 1) — rejected: conflates who controls a
  source, how mature a release is, and what code may execute; "vendor
  bespoke launchers, reviewed" died in cross-check round 1 because review is
  not a boundary.
- **Git-history-only revocation** — rejected: history proves what happened,
  not what is currently denied; consumers need a fail-closed current-state
  artifact.
- **External marketplace portal** (Backstage/Devtron class) — not adopted;
  the console Catalog rail plus classed sources covers the need, and the
  air-gap/self-contained doctrine (ADR-0030/0034) plus the roadmap's
  recommendation park external portals unless a real multi-publisher
  ecosystem materialises.

## Enforcement

Ingestion-time: rendered-manifest validation against the versioned
`generic-chart-policy/v1` with conformance fixtures (known-good packages
pass; every forbidden capability has a failing fixture); signature
verification at promotion. Runtime: revocation deny-list consumed fail-closed
at every listed consumer; the trust-bypass override is C5-audited. Until the
generic launcher ships, enforcement is structural: no non-`project` source is
deployable at all. Runtime admission (Kyverno-class) is deferred Stage-5
hardening — until then, policy conformance is ingestion-gated and
discipline-backed at the git review step.

## Appendix A — `generic-chart-policy/v1` (normative)

Both a safety policy and a package contract; versioned; testable with
conformance fixtures.

**Security deny-list.** No cluster-scoped resources; no CRDs, controllers,
mutating/validating webhooks, or operator install paths; no privileged pods;
no hostPath/hostNetwork/hostPID/hostIPC; no added Linux capabilities or
privilege escalation; no Helm lifecycle hooks or hidden hook Jobs; no broad
RBAC or use of existing powerful service accounts; no service-account token
automount; no namespace escape; no non-digest image references; no images
outside the signed package closure.

**Operational contract.** Every workload container declares
`resources.requests`; health/readiness probes declared; labels/annotations
follow the catalog contract; declared ports/services match the catalog entry;
rendered manifests are deterministic and testable; chart values are
constrained by versioned schemas, not free-form runtime overrides.

**Placement/isolation contract.** Namespace assigned by DMF; per-instance
service account with `automountServiceAccountToken: false`; default-deny
NetworkPolicy covering ingress **and egress** with explicit allowed flows;
nodeSelector/tolerations/runtimeClass injectable or constrained by DMF;
ResourceQuota/LimitRange compatibility required.

v1 gate is ingestion-time rendered-manifest validation; runtime admission
enforcement layers on later.
