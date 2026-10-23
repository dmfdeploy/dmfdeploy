# ADR-0027: Separate catalog-entry, installation, and runtime-instance layers for media functions

> **⚠️ Canonical truth for this topic is in [ADR-0037](0037-media-workloads-netbox-instance-inventory.md) (instances in NetBox, amended by [ADR-0046](0046-first-class-media-workload-entity.md)) and [ADR-0013](0013-media-function-catalog-model.md) (catalog model, extended by [ADR-0047](0047-media-function-packaging-catalog-sources-trust-model.md)).** This ADR's status: **amended by ADR-0037** (the instance layer lives in NetBox + AWX; it is not a CRD).
> Full text is preserved in the [archive record](../archive/decisions/0027-catalog-instance-vs-definition-separation.md) for decision history. Do not act on it without reading the canonical ADR and the named successor.

**Status:** Proposed (deferred): **three-layer framing survives; installation/instance-layer implementation resolved by ADR-0037** (NetBox instances + AWX reconcile; not a CRD + custom operator)
**Date:** 2026-05-22
**Deciders:** @<handle>, design conversation with GPT-5 (2026-05-22 share), captured by Claude
**Amended by:** ADR-0037 (Media Workloads: installation/instance layer realised in NetBox + AWX)

**Rule:** Media catalog functions keep three separate layers: catalog entry, installation, and runtime instance. Implementation is deferred until the second catalog function (or the first third-party submission, whichever comes first) makes the per-function bootstrap-layer pattern's friction concrete.

## Context

Lane B's RBAC pre-creation block in `awx-integration` creates the `nmos` namespace + `nmos-cpp-launcher` SA + Role + RoleBinding **at bootstrap**, regardless of whether the function is ever instantiated. This pattern **conflates** three distinct layers: catalog entry, installation, and runtime instance. The archive record has the layer descriptions and background.

## Decision

Adopt the **three-layer separation** for media catalog functions:

| Layer | Storage | Lifecycle |
|---|---|---|
| **Catalog entry** | `dmf-media/catalog/<key>.yaml` (already exists per ADR-0013); future third-party entries submitted as YAML + chart reference | Static metadata; many entries, most never instantiated |
| **Installation** | A `MediaFunctionInstance` CRD (name provisional) declaring `function: <catalog-key>`, `namespace: <target>`, `values: {}`. Reconciled by a DMF Catalog Operator. | One CR per (function, target-namespace) tuple; few per cluster |
| **Runtime instance** | Kubernetes namespace + Helm release + Deployment/StatefulSet/Service/etc. produced by the reconciler. | Lifecycle bound to the CR; namespace created on CR creation, deleted on CR deletion |

The reconciler's responsibilities are in the archive record.

**Implementation is deferred.** This ADR is Proposed-deferred and is not Proposed-imminent: Lane B ships with the bootstrap-RBAC pattern as acceptable debt for the single-function case. The reconciler is built when the **second** catalog function makes the per-function bootstrap-layer pattern's friction concrete. That function is EBU LIST, MXL, flow-exporter, or the first third-party submission, whichever comes first. **Letting the second function force the design** prevents premature abstraction.

## Consequences

- **Positive**: when implemented, eliminates per-function bootstrap-layer churn. Third-party functions become a YAML+chart contribution (no DMF maintainer code change). Namespace count tracks instantiations and does not track catalog size. The trust-boundary tooling (NetworkPolicy, PSA, image signing, ResourceQuota) lands in one reconciler instead of being duplicated per function.
- **Negative**: a Kubernetes operator/controller is a new platform component to build and operate; CRDs are an API surface to version; the migration from today's bootstrap-RBAC pattern to the reconciler-RBAC pattern requires a one-time per-function lift.
- **Neutral**: the catalog YAML schema (ADR-0013) survives; the Helm chart pattern (ADR-0025 Lane B) survives; ADR-0020 B.3 cluster-per-tenant survives. This ADR is additive and inserts the middle layer that today is implicit.

## Enforcement

Discipline only: this ADR is Proposed-deferred, so no check, test or workflow enforces it. A grep of the component repos finds no `MediaFunctionInstance` CRD or catalog operator.

<!-- Status words stay as decided; only these word rules are off for this section. -->
<!-- vale Google.Latin = NO -->
<!-- vale Google.Ordinal = NO -->
## Status

Proposed (deferred): **three-layer framing survives; installation/instance-layer implementation resolved by ADR-0037** (NetBox instances + AWX reconcile; not a CRD + custom operator)

### Promotion criteria (Proposed-deferred → Proposed-imminent)

Promote from **deferred** to **imminent** (i.e. start building) when
**any one** of the following holds:

1. A second catalog function reaches the point of requiring its own
   bootstrap-layer RBAC block. The second `dmf-media/catalog/*.yaml`
   that needs Phase-4-style awx-integration changes is the trigger.
2. A first 3rd-party catalog contribution is on the inbound roadmap
   (a vendor or community submission is being scoped, not yet merged).
3. Cluster namespace count crosses 50 from catalog functions alone
   (well below SIG Scalability's 10K, but the operational-overhead
   inflection point per GPT-5's guidance).
4. ADR-0020 **Mode B** promotes to Accepted (managed `dmfdeploy.io`
   active), since Mode B implies 3rd-party functions become a real
   channel. The 2026-05-23 Mode-A-only promotion of ADR-0020 does not
   trigger this criterion: Mode A is single-tenant operator-self-host
   and has no 3rd-party-contribution channel.

Promotion from **imminent** to **Accepted** requires:

- `MediaFunctionInstance` CRD schema + a reconciler running in
  `dmf-system` (or equivalent).
- Lane B's NMOS-cpp lifted to the new pattern: bootstrap-RBAC block
  removed from `awx-integration`; an `MediaFunctionInstance` CR
  declares NMOS-cpp's installation.
- One second function landed via the new pattern (no awx-integration
  change required for it).
- 3rd-party-safety baseline (default-deny NetPol, PSA, ResourceQuota,
  LimitRange) applied automatically by the reconciler in every
  function namespace.

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0027-catalog-instance-vs-definition-separation.md).
