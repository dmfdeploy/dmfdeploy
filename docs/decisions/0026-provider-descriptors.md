# ADR-0026: Provider Descriptors as single source of truth for bootstrap integrations

**Status:** Proposed
**Date:** 2026-05-20
**Deciders:** @<handle>, planning session with Claude

## Context

Per-provider bootstrap knowledge accretes across five touchpoints, and the
hand-rolled per-env `group_vars/all/<provider>.yml` file is the weak one: the
`<env>` Tailscale authkey was collected and exported, but no binding was
rendered, so pre-seed died. The full context is in the archive record.

## Decision

Adopt **Provider Descriptors**: declarative YAML manifests at
`dmf-infra/k3s-lab-bootstrap/providers/<id>.yaml`, one per provider, each
declaring:

- `id`, `name`, `kind` (`vpn` | `dns` | `vps` | `storage` | `tls` | `identity` | `registry` | ...)
- `applies_to_profiles[]`: subset of `cloud` / `flypack-offline` /
  `flypack-online`, per ADR-0022
- `inputs[]`: operator-typed values; each maps to an `inventory_var`
- `secrets[]`: declared by logical reference only, never by literal value
  (ADR-0007), with the paths, export var and indirection in the schema doc
- `group_vars_file`: the per-env binding file path and a template body that the descriptor-renderer materializes into `dmf-env/inventories/<env_id>/...`
- `roles_consuming[]`: the Ansible role paths that assert on the declared inventory vars
- `secret_rotation` (optional): `{ owner, cadence }` for audit clarity per ADR-0009 / ADR-0021

These descriptors are authoritative for the bash wizard, the Python wizard at
`wizard-spike/`, and dmf-cms's future add-a-provider UI. Schema specified in
[`docs/architecture/DMF Provider Descriptor Model.md`](../architecture/DMF%20Provider%20Descriptor%20Model.md).

Instance values (real authkeys, tokens, secret_ids) continue to live in the
SOPS bundle (pre-OpenBao) and OpenBao (post-cluster) per ADR-0007 and
ADR-0008. Descriptors reference them and never embed them.

## Consequences

- **Positive:** five touchpoints converge to one file and one schema. A `group_vars_file` field guarantees the per-env binding gets rendered whenever a descriptor's inputs are collected, so the Tailscale failure class becomes structurally impossible. Future providers ship as one file rather than coordinated edits across two repos. The dmf-cms add-a-provider UI gets its data model for free.
- **Negative:** one new schema to maintain. Hand-rolled per-env `group_vars/all/*.yml` files become technical debt to migrate. The v1 schema will mis-fit at least one provider (Aliyun RAM/STS with optional STS token-exchange is a likely candidate) and require an amendment to the schema doc.

The Neutral consequence (`PRESET_DEFAULTS`) is in the archive record.

## Enforcement

`dmf-env/bin/init-wizard.sh` (`render_inventory_tailscale`) consumes the descriptor for every non-sandbox env with a Tailscale authkey. It passes `dmf-infra/k3s-lab-bootstrap/providers/tailscale.yaml` to `dmf-env/bin/lib/render-provider-descriptor.py`, which validates the descriptor against the schema's MUST rules and renders its `group_vars_file` template into the env inventory. No test or CI workflow runs the renderer.

<!-- vale Google.Latin = NO -->
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
   descriptor for at least one **live** env (e.g. `<env>`;
   `hetzner-arm` is retired so the original byte-for-byte anchor no
   longer applies; equivalence against any live env's existing
   hand-rolled `tailscale.yml` is sufficient).
3. A second descriptor (cloudflare or hcloud) lands without schema
   mutation, i.e. v1 schema survives the second integration.

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0026-provider-descriptors.md).
