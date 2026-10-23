# ADR-0013 archive: Media function catalog model

This file holds material moved out of [ADR-0013](../../decisions/0013-media-function-catalog-model.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **NetBox-only catalog** (custom fields on `ipam.Service`). Rejected —
  `ipam.Service` is the wrong shape for flow-producing media functions
  (which aren't "services on a port" in the NetBox sense), and custom
  fields accumulate without a schema home.
- **YAML-only catalog**. Rejected — runtime state then lives outside
  NetBox, contradicting the SoT decision (dmfdeploy platform plan §12, decision
  log 2026-04-17).
- **Pure Helm/ArgoCD model**, no catalog abstraction. Rejected — the
  operator-facing UI needs a richer abstraction than Helm releases
  (lifecycle state, dependencies, status semantics, dmf-cms-readable
  display metadata).

## 2026-05-12 — provision.namespace: problem and evidence (moved from the ADR)

The Move 1 P8 drift detector (`operate-catalog-drift.yml`) surfaced a
gap: the schema had no k8s namespace field, so drift detection had to
derive namespace from the entry's `key` — a brittle heuristic that
produced false positives for `nmos-cpp` (actual namespace `nmos`, not
`nmos_cpp`).
