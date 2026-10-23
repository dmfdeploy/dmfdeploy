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
- [`docs/plans/dmf-init-wizard-expansion-survey.md`](../../plans/dmf-init-wizard-expansion-survey.md) —
  Survey Steps 6 + 7 + the `PRESET_DEFAULTS`-to-dmf-infra follow-up are
  absorbed by this ADR's promotion criteria.

## Moved from the ADR on 2026-10-23

## Context

Per-provider bootstrap knowledge accretes across five touchpoints: operator
prompt (`init-wizard.sh`), SOPS bundle key (`bootstrap-secrets.sh`), OpenBao
path (`seed-bao`), Ansible export var (`vault_*` in `export-vars`), and per-env
`group_vars/all/<provider>.yml` file. Roles then assert on the inventory vars.

The 5th touchpoint is hand-rolled — `hetzner-arm` has
`tailscale.yml` / `openbao.yml` / `eso.yml` / `bootstrap.yml`; wizard-generated
envs have none of them. The recent `<env>` rollout proved the failure
mode: the Tailscale authkey was collected, bundled, and exported, but no
per-env binding was rendered, so pre-seed died on the `base/tailscale`
assertion.

The Python wizard rewrite at `wizard-spike/` (53 tests, per the
[Init Wizard Expansion Survey](../../plans/dmf-init-wizard-expansion-survey.md))
models PROFILE shape (`Profile`, `Tier`, `PRESET_DEFAULTS`, discriminated-union
`ManifestBody`) but explicitly defers PROVIDER shape (Survey Steps 6 + 7).
There is no canonical provider abstraction shared by the bash wizard, the
Python wizard, and (later) dmf-cms's add-a-provider UI.

### Promotion criteria (Proposed → Accepted)

1. `dmf-infra/k3s-lab-bootstrap/providers/tailscale.yaml` (landed
   2026-05-20) is consumed by a pydantic loader in `wizard-spike/src/`
   that round-trips the descriptor in tests. *Status 2026-05-23: the
   descriptor exists; the loader does not. `wizard-spike/src/` has no
   provider-shaped code yet.*
2. The Python wizard renders
   `dmf-env/inventories/<env_id>/group_vars/all/tailscale.yml` from the
   descriptor for at least one **live** env (e.g. `<env>` —
   `hetzner-arm` is retired so the original byte-for-byte anchor no
   longer applies; equivalence against any live env's existing
   hand-rolled `tailscale.yml` is sufficient).
3. A second descriptor (cloudflare or hcloud) lands without schema
   mutation — i.e. v1 schema survives the second integration.

### Decision and Consequences detail (original wording)

- `secrets[]`: declared by logical reference only, never by literal value
  (ADR-0007). Each carries `bundle_path` (pre-OpenBao), `vault_path` +
  `vault_field` (post-OpenBao), `export_var` (the `vault_*` name the wrapper
  injects), `inventory_var` (the role-side input name), and `indirection`
  (the Jinja expression in the per-env `group_vars` file).
- **Neutral** — Provider Descriptors and `PRESET_DEFAULTS` (Survey Step 1
  follow-up) are sibling consolidations, not the same artifact.
  `PRESET_DEFAULTS` keys on `(Profile, Tier)` and outputs deployment-shape
  defaults; descriptors key on `provider_id` and output integration-shape
  contracts. Both will eventually load via the same pydantic layer in the
  Python wizard.
