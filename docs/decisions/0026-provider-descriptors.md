# ADR-0026: Provider Descriptors as single source of truth for bootstrap integrations

**Status:** Proposed
**Date:** 2026-05-20
**Deciders:** @<handle>, planning session with Claude

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
[Init Wizard Expansion Survey](../plans/DMF%20Init%20Wizard%20Expansion%20Survey%202026-05-13.md))
models PROFILE shape (`Profile`, `Tier`, `PRESET_DEFAULTS`, discriminated-union
`ManifestBody`) but explicitly defers PROVIDER shape (Survey Steps 6 + 7).
There is no canonical provider abstraction shared by the bash wizard, the
Python wizard, and (later) dmf-cms's add-a-provider UI.

## Decision

Adopt **Provider Descriptors**: declarative YAML manifests at
`dmf-infra/k3s-lab-bootstrap/providers/<id>.yaml`, one per provider, each
declaring:

- `id`, `name`, `kind` (`vpn` | `dns` | `vps` | `storage` | `tls` |
  `identity` | `registry` | ...)
- `applies_to_profiles[]`: subset of `cloud` / `flypack-offline` /
  `flypack-online`, per ADR-0022
- `inputs[]`: operator-typed values; each maps to an `inventory_var`
- `secrets[]`: declared by logical reference only, never by literal value
  (ADR-0007). Each carries `bundle_path` (pre-OpenBao), `vault_path` +
  `vault_field` (post-OpenBao), `export_var` (the `vault_*` name the wrapper
  injects), `inventory_var` (the role-side input name), and `indirection`
  (the Jinja expression in the per-env `group_vars` file).
- `group_vars_file`: the per-env binding file path
  (`group_vars/all/<file>.yml`) and a template body that the
  descriptor-renderer materializes into `dmf-env/inventories/<env_id>/...`
- `roles_consuming[]` — the Ansible role paths that assert on the declared
  inventory vars
- `secret_rotation` (optional) — `{ owner, cadence }` for audit clarity per
  ADR-0009 / ADR-0021

These descriptors are authoritative for the bash wizard, the Python wizard at
`wizard-spike/`, and dmf-cms's future add-a-provider UI. Schema specified in
[`docs/architecture/DMF Provider Descriptor Model.md`](../architecture/DMF%20Provider%20Descriptor%20Model.md).

Instance values (real authkeys, tokens, secret_ids) continue to live in the
SOPS bundle (pre-OpenBao) and OpenBao (post-cluster) per ADR-0007 and
ADR-0008; descriptors *reference* them, never embed them.

## Consequences

- **Positive** — the 5-touchpoint accretion converges to one file + one
  schema; the class of bug Tailscale exhibited becomes structurally
  impossible (a descriptor with a `group_vars_file` field guarantees the
  per-env binding gets rendered whenever the descriptor's inputs are
  collected); future providers ship as one file rather than coordinated edits
  across two repos; dmf-cms's add-a-provider UI gets its data model for free.
- **Negative** — one new schema to maintain; existing hand-rolled per-env
  `group_vars/all/*.yml` files become technical debt to migrate; v1 schema
  will mis-fit at least one provider (Aliyun RAM/STS with optional STS
  token-exchange is a likely candidate) and require an amendment to the
  schema doc.
- **Neutral** — Provider Descriptors and `PRESET_DEFAULTS` (Survey Step 1
  follow-up) are sibling consolidations, not the same artifact.
  `PRESET_DEFAULTS` keys on `(Profile, Tier)` and outputs deployment-shape
  defaults; descriptors key on `provider_id` and output integration-shape
  contracts. Both will eventually load via the same pydantic layer in the
  Python wizard.

## Status

Proposed

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

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0026-provider-descriptors.md).
