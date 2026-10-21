# ADR-0037: Media Workloads are a NetBox-driven Media Function instance inventory; flows stay runtime-only

**Status:** Accepted (model); implementation in flight
**Date:** 2026-06-03
**Deciders:** @<handle>, design conversation with Claude (2026-06-03) while reading the EBU DMF Reference Architecture V2.0 whitepaper
**Supersedes/amends:** ADR-0027 (resolves its deferred installation/instance-layer implementation: NetBox instances, not a `MediaFunctionInstance` CRD)
**Amended by:** ADR-0046 (adds the deferred *assembly* layer — a first-class Media Workload as a tag-derived grouping, `workload:<slug>`; this ADR's function-inventory model stays intact underneath it)

## Context

ADR-0013 set the catalog model (YAML definition + NetBox runtime tag).
ADR-0025 made the runtime substrate concrete (Helm chart from Zot via an AWX
EE pod). ADR-0027 added a three-layer separation — **catalog entry /
installation / runtime instance** — but **deferred** the implementation of the
middle (installation) layer, proposing a `MediaFunctionInstance` CRD plus a
custom DMF Catalog Operator, and naming **MXL** as one of the triggers that
would force the design (promotion criterion 1).

MXL is now that second function. Standing up the intra-host `mxl-hello` Media
Function on the sandbox forced the concrete question the EBU whitepaper sharpens:
**where, in EBU terms, does a *deployed* Media Function belong in the operator
console?** Working through the whitepaper's layered model (Figure 2), lifecycle
(Figure 1), verticals (Figure 3), and the Annex C orchestration grid produced a
clear answer:

- The operator's real question is **"what Media Functions are deployed, how many,
  and where?"** — a fleet/inventory question, scoped to the tenant/site they may
  see. That is squarely what NetBox (the facility SoT) is built to answer.
- A **Flow** (Media Exchange edge) is *live, transient* state — it appears,
  advances a head index, and disappears. The whitepaper places "Monitor Status
  of Flows" in the **Monitoring** vertical at the **Media Exchange** layer, i.e.
  observed runtime state, **not** the configuration record.
- ADR-0027's CRD-plus-operator is more machinery than the experiment phase
  (ADR-0004) warrants when NetBox already *is* the instance/inventory store and
  AWX already consumes NetBox as a dynamic inventory (`nb_inventory`,
  `694-born-inventory`) and already has a drift loop (`operate-catalog-drift.yml`).

## Decision

**1. Three stores, clean ownership.** A deployed Media Function is represented
across exactly three stores, each owning one thing:

| Store | Owns | Mutability |
|---|---|---|
| **git catalog** (`dmf-media/catalog/<key>.yaml`) | Media Function **definitions** | versioned, immutable |
| **NetBox** | Media Function **instances** + **placement** (tenant / site / AZ / cluster / node) + lifecycle status | mutable: intent + record |
| **k3s** | **actual runtime** + **scheduling** (nodeSelector / affinity / taints) | reconciled to match |

**2. NetBox holds instances only — never flows, never live state.** We
deliberately **do not model Media Exchange Flows** (edges) in NetBox, and we do
not create a "Media Workload" graph object there. NetBox records *which* Media
Function, *how many* instances, and *where* they run — reusing the existing
`netbox_service` model and tag convention (`app:<key>`, `dmf-catalog`,
`lifecycle:*`), so "filter by Media Function, see the resources and the count"
is an aggregation over tagged Services. **Desired-vs-observed rule:** NetBox is
the config DB (desired + recorded placement); live flow telemetry (Active, head
index, preview) is the Monitoring vertical's concern (status sidecar now,
Prometheus/NMOS later) and is never written to NetBox.

**3. NetBox *scopes*; k3s *schedules*.** NetBox models eligibility
(tenant/site/cluster) and the resource profile; the container orchestrator makes
the actual node placement within that scope (for MXL, the ADR-0017 §5
processor-node contract expressed as Helm values); born-inventory then records
*where it landed* back into NetBox. We do not build a scheduler in NetBox/AWX.

**4. AWX is the reconciler — extend the existing loop, don't invent one.** A
*cleared* desired instance-set in NetBox is converged onto the cluster by AWX
(parameterised Helm via the catalog launchers), reusing `nb_inventory` +
`operate-catalog-drift.yml`. Trigger is a scheduled poll first; webhook later.
This realises ADR-0027's "installation" layer in **NetBox + AWX** rather than a
CRD + custom operator.

**5. The console surface is "Media Workloads".** A page scoped to a
**media-engineers** group and filtered, **server-side**, to the tenant/site the
user may view. Its first-cut content is a **Media Function instance inventory**
(count + placement, filter by function) with live status overlaid from runtime.
Authorisation is a **hard backend boundary**, not a frontend filter, on both read
and the consequential **"clear for deployment"** action, which captures the
ADR-0028 C5 quartet (actor / role / request-id / reason) per UX Constitution
Art. 7. The flow/composition **graph** is a *future runtime overlay* (Media
Exchange status → NMOS), not part of this decision.

**6. Naming and the EBU vocabulary promotion.** The page is named **"Media
Workloads"** (the EBU destination concept) even though its MVP content is the
instance inventory; the *assembly/graph* sense of a Media Workload arrives with
the runtime flow overlay. Building this real operator workflow is the evidence
the Console Glossary's open question asks for: it **promotes** "Media Workload /
Media Function" out of the `dmf-internal` tier toward operator-native status
(UX Constitution Art. 3) — recorded here as the forcing function.

## Consequences

- **Positive** — no new platform component (no CRD, no custom operator); the
  instance layer rides NetBox + AWX, which already exist and already inter-operate.
  The hard NetBox-modelling problem (flows-as-edges) is avoided by scoping NetBox
  to instances. Drift becomes a feature (NetBox-desired vs cluster-actual is
  diffable). The model is layer-faithful to the EBU whitepaper.
- **Positive** — answers the operator's actual question (what/how-many/where),
  tenant-scoped, with a clean growth path to composition + flow visualisation.
- **Negative** — the composition/flow graph and free "design canvas" are
  deferred; the page is an inventory before it is a true Media *Workload*
  (assembly) view. Tenant scoping with today's single service NetBox token means
  scope is enforced by the console mapping group → permitted tenants until
  per-user NetBox tokens exist — a security-sensitive surface needing review.
- **Neutral** — ADR-0013 catalog YAML, ADR-0025 Helm/EE pattern, ADR-0017 MXL
  placement contract, and ADR-0020 cluster-per-tenant all survive unchanged.
  This decision inserts ADR-0027's middle layer using existing stores.

## Status

Accepted (model); implementation in flight

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0037-media-workloads-netbox-instance-inventory.md).
