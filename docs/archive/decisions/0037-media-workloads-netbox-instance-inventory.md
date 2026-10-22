# ADR-0037 archive: Media Workloads are a NetBox-driven Media Function instance inventory; flows stay runtime-only

This file holds material moved out of [ADR-0037](../../decisions/0037-media-workloads-netbox-instance-inventory.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **ADR-0027 as written (`MediaFunctionInstance` CRD + custom operator).**
  Rejected for now: more machinery than the experiment phase warrants when NetBox
  already is the instance store. If a CRD/operator is later justified (high N,
  3rd-party isolation), it can sit *behind* the same NetBox-facing contract.
- **Model flows/Media Workloads as NetBox objects (custom fields / plugin).**
  Rejected: flows are live Media-Exchange state; persisting them in a config DB
  is the desired-vs-observed anti-pattern, and the custom relationship/plugin
  modelling is exactly the cost we avoid by scoping NetBox to instances.
- **A bespoke "MXL Flows" page (the spike's approach).** Rejected as the home:
  it is MXL-specific and built for the cross-host fabrics narrative; the
  general, durable surface is Media Workloads, with MXL flow detail folding into
  the runtime overlay later.
- **Frontend-only tenant filtering.** Rejected: scope is an authorisation
  boundary (ADR-0028); it must be enforced server-side.

## Cross-references

- **ADR-0027** — three-layer separation; this ADR amends it (installation/instance
  layer realised in NetBox + AWX, not a CRD + operator). ADR-0027's framing survives.
- ADR-0013 — catalog model (YAML + NetBox tag); unchanged, this builds on it.
- ADR-0017 — MXL intra-host data plane; `mxl-hello` is the first Media Function
  proving this model; its §5 placement contract is the k3s-scheduling input.
- ADR-0025 — in-cluster Helm/EE; the AWX launchers are the reconcile mechanism.
- ADR-0028 — Identity & Authority Chain; C5 quartet on the clear-for-deployment
  action; tenant-scope authz is a hard boundary.
- ADR-0032 — scoped NetBox writer (`dmf-catalog-svc`); instance writes use it.
- See also: ADR-0038 — dynamic monitoring builds on this inventory model with
  a separate monitoring contract and adapter bridge.
- ADR-0003 — EBU taxonomy; ADR-0004 — experiment-phase stance (favours the
  thinnest model that tests the thesis).
- `docs/architecture/DMF EBU Mapping (2026-04-25).md` — Media Workload =
  "assembly of Media Functions"; this surface is the upper-layer Design output.
- `docs/design/dmf-console-ux-constitution.md` Art. 3 + Glossary —
  the vocabulary-promotion forcing function.
- EBU DMF Reference Architecture V2.0 — Figures 1–3, Annex C orchestration grid.
