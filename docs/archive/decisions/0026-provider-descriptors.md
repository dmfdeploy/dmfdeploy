# ADR-0026 archive: Provider Descriptors as single source of truth for bootstrap integrations

This file holds material moved out of [ADR-0026](../../decisions/0026-provider-descriptors.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Keep hand-rolling per-env files.** Rejected — Tailscale proved this
  fails the moment a wizard generates a new env.
- **Generate `group_vars/all/<provider>.yml` from `init-wizard.sh` heredocs
  per-provider.** Rejected — perpetuates bash-as-truth, hides provider
  knowledge in imperative code, and violates §3.1 of the Deployment
  Workflow Plan (the wizard-not-engine boundary).
- **Extend the Function Catalog model (ADR-0013) to providers.** Rejected —
  the function catalog describes operator-launchable workloads (a distinct
  launch / teardown lifecycle). Providers are bootstrap integrations
  (collected once during init, then static for the env's life). Wrong shape,
  wrong lifecycle.

## Cross-references

- ADR-0002 — two-repo model. Descriptors live in `dmf-infra` (generic,
  public), not `dmf-env` (instance, private).
- ADR-0007 — secrets never in argv. Descriptors carry no literal secrets;
  only `bundle_path` / `vault_path` references.
- ADR-0008 — OpenBao layout provides `vault_path` / `vault_field` reference
  targets.
- ADR-0010 — `bin/run-playbook.sh` is the sanctioned entry. Descriptor
  consumers must read descriptors *adjacent* to the wrapper, never bypass it.
- ADR-0013 — function catalog. Naming-collision note: do not confuse
  "Provider Descriptor" with "function catalog entry" — different lifecycle.
- ADR-0022 — flypack-online profile provides the `applies_to_profiles` enum.
- ADR-0025 — cluster-internal Ansible execution + Catalog Helm pivot.
  Orthogonal; no overlap with descriptor scope.
- [`docs/plans/DMF Init Wizard Expansion Survey 2026-05-13.md`](../../plans/DMF%20Init%20Wizard%20Expansion%20Survey%202026-05-13.md) —
  Survey Steps 6 + 7 + the `PRESET_DEFAULTS`-to-dmf-infra follow-up are
  absorbed by this ADR's promotion criteria.
