<!-- ADR doc convention: every ADR carries a top-of-doc **Rule:** line — the binding
constraint in one imperative sentence — directly under the metadata block. See
CONTRIBUTING.md → "ADR conventions". -->
# ADR-0043: Workload scale-to-zero is an availability concern, scoped to AWX

**Status:** Accepted
**Date:** 2026-06-19
**Deciders:** @znerol2, umbrella session (claude)
**Rule:** On-demand scale-to-zero changes a *named workload's availability* (replicas 0↔N) out-of-band; it is **not** node elasticity or a cost guardrail, it **never** alters AWX job/catalog/media semantics (AWX stays the actuator under ADR-0013/0025/0037), and it is authorized **for AWX only** — any other workload adopting the pattern needs its own ADR.

## Context

The constrained single node (Pi 4 / 8 GB) cannot hold AWX (~2 GiB across `awx-web` + `awx-task`) awake alongside everything else, yet AWX is idle most of the time. The fix is to switch AWX off when unused and back on when a job is needed. Three superficially similar ideas get conflated, and the danger is that a small wake/sleep mechanism quietly grows into something with a much larger blast radius:

1. **Workload scale-to-zero** — switch a *named workload* off/on (replicas 0↔N) to reclaim node resources. An **availability** concern, out-of-band from any control loop.
2. **Node elasticity** — add/remove *nodes* under load. AWX-actuated, deferred (see the *Elastic Media Nodes & Cloud Cost Controller* plan).
3. **Cost guardrail** — cloud-spend controls. Deferred.

The risk is twofold: (a) the wake/sleep helper reaching into AWX's job/catalog/media semantics (it must not — that is AWX's role under ADR-0013/0025/0037), and (b) the pattern being treated as a general "scale anything to zero" framework and proliferating into many bespoke helpers — exactly the kind of tooling sprawl the platform avoids, and out of step with the v0.1 freeze (`architectural-commitments-v1`).

## Decision

Treat **workload scale-to-zero as an availability primitive, narrowly scoped to AWX**, with a hard semantic boundary.

- **Definition.** *Workload scale-to-zero* = scaling a named workload to/from zero on demand. It is an **availability** action only — it changes whether the workload is *running*, never *what it does*.
- **Scoped to AWX.** This ADR authorizes the pattern **for AWX only**, implemented by two cooperating pieces that share identical AWX CR semantics: the `awx-presence` role (bootstrap, 1→0→1→0 at phase boundaries) and the `awx-autoscale` helper (steady-state, on-demand wake + idle-reap). The seam is *named* here for legibility — *"scale a named workload to/from zero on demand"* — but it is **not** generalized: any other workload adopting it requires a **new ADR**. No general elasticity/actuator framework is built.
- **Hard boundary.** AWX remains the catalog/workflow **actuator** under ADR-0013 / ADR-0025 / ADR-0037. The helper changes AWX **availability only** — it may patch replica fields and read readiness; it must **never** launch or cancel jobs, alter catalog manifests, or touch NetBox runtime tags.
- **Distinct from** node elasticity (deferred; AWX-actuated) and cost guardrails (deferred). Cross-links: ADR-0013/0025/0037 (the actuator commitments), ADR-0038 (the NetBox-driven control loop), and the *Elastic Media Nodes & Cloud Cost Controller* plan (the deferred elasticity track this is explicitly **not**). Full design: `docs/plans/DMF AWX On-Demand Scale-to-Zero Plan 2026-06-18.md` (tracking issue #97).

## Consequences

- **Positive** — a narrow, legible primitive; AWX's actuator role is preserved untouched; single-node viability without scope-creep into elasticity or cost control; the "new ADR per workload" rule prevents helper sprawl.
- **Negative** — two AWX-presence authorities (the bootstrap role and the steady-state helper) must agree on the CR replica semantics; the boundary needs ongoing enforcement (review + RBAC scoping).
- **Neutral** — opt-in via `dmf_awx_autoscale_enabled`; cloud/lab lanes keep AWX at `replicas: 1` and deploy no helper, so there is no behaviour change there.

## Alternatives considered

- **Name it a general "scale any workload to zero" primitive** (the plan's "reusable seam" read literally) — forward-looking, but an open invitation to build more bespoke wake/sleep helpers; rejected as sprawl-inviting and premature against the v0.1 freeze. The pattern is described, not generalized; reuse goes through a new ADR.
- **Build a general workload-elasticity actuator now** — over-engineering; conflates availability with elasticity; violates the freeze's non-goals.
- **Let AWX manage its own sleep** — circular: the controller must be running to act, so something out-of-band must own wake/sleep.
- **Node elasticity instead** — heavier and deferred; does not address the steady-state idle-RAM problem on a single node.

## Enforcement

The boundary's teeth are **RBAC + scope**: the `awx-autoscale` helper holds a namespaced Role limited to the AWX CR (`get`,`patch`), Deployments (`get`), and a coordination Lease — **no** `secrets` verbs, **no** job-launch path — so it is structurally incapable of touching job/catalog/media semantics. Any proposal to scale a *different* workload to zero must open a new ADR rather than extend this one. Tracked by issue #97; implemented in `dmf-infra` (`roles/stack/operator/awx-presence`, `roles/stack/operator/awx-autoscale`).
