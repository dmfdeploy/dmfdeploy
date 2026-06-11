# ADR-0032: Catalog launchers mutate NetBox via a scoped writer service account, never the admin token

**Status:** Accepted
**Date:** 2026-05-27
**Deciders:** @<handle> (raised the least-privilege question during the wobe-9n0c catalog-deploy debugging session), with Claude investigation
**Refines:** [ADR-0028](0028-identity-and-authority-chain.md) C3 (scoped service accounts for machine-to-machine). Related: [ADR-0013](0013-media-function-catalog-model.md) (catalog model — NetBox runtime lifecycle tag), [ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md) (in-cluster launchers), [ADR-0007](0007-secrets-never-in-argv.md).

## Context

ADR-0028 C3 binds: *"Machines use scoped service accounts… scoped, named, documented, and stored in OpenBao."* But `netbox-sot` provisions the catalog-relevant service accounts **read-only** (`dmf-cms-svc`→`dmf-cms-readonly`, `awx-svc`→`awx-readonly`). The steady-state catalog launchers (e.g. `media-launch-nmos-cpp`, run in-cluster as the AWX identity per ADR-0025) must **write** NetBox — create/apply the ADR-0013 lifecycle tag on the function's `ipam.service` record. With no scoped writer available, the nmos-cpp launcher authenticated with `netbox_admin_token` (NetBox superuser), and on a fresh sandbox where that token was empty it fell back to the read-only token and 403'd at the first write. The real tension: a steady-state automated action was using superuser custody to paper over a missing least-privilege identity — exactly the posture C3 forbids.

## Decision

**Catalog launchers (and any steady-state automation that mutates NetBox) authenticate with a dedicated, narrowly-scoped NetBox *writer* service account — never the NetBox admin/superuser token.** Concretely:

1. `netbox-sot` provisions a catalog writer service account (`dmf-catalog-svc`) in a `dmf-catalog-writer` group whose object permissions are limited to exactly the three models the launchers touch (verified against the nmos-cpp role, all stages + the live deploy):
   - `ipam.service`: **view, add, change** — a launcher *creates* the per-deployment service record at provision (`POST /ipam/services/`) and *patches* its lifecycle tag at configure/teardown (`PATCH`).
   - `extras.tag`: **view, add** — a launcher creates the per-function `app:<key>` tag (e.g. `app:nmos-cpp`) which is *not* in the bootstrap taxonomy; the `lifecycle:*` tags are pre-created by `netbox-sot`.
   - `dcim.device`: **view** (read-only) — a launcher looks up the parent load-balancer device (`dmf-traefik`) to attach the service to. No write on dcim.
   No superuser/staff, no dcim *write*, no tag `change`/`delete`. Token minted to OpenBao under the `<system>-token-<purpose>` convention and wired into the catalog JT extra_vars by `awx-integration`.
2. Launchers drop the `netbox_admin_token` input **across all stages** (provision/configure/finalise) and use the scoped catalog token for every NetBox call — reads and writes.
3. The platform-wide `lifecycle:*` tags stay pre-created at bootstrap (`netbox-sot`). **Tightening follow-up:** pre-create per-function `app:<key>` tags at bootstrap too (born-inventory already reconciles catalog entries), which would let the writer drop `extras.add_tag` and shrink to `extras.view_tag`. Deferred — the launcher's create-if-missing is idempotent and keeps `netbox-sot` decoupled from the function list for now.
4. The NetBox admin/superuser token is **bootstrap/break-glass only** (per ADR-0028 C4 sanctioned-exception posture) and must not appear in any steady-state JT, role default, or runtime secret consumed by a launcher.

## Consequences

- **Positive** — Catalog deploys run under a named, audited, minimally-scoped identity; a compromised launcher token can touch lifecycle tags on services, nothing more. Closes the C3 gap. The blast radius of the AWX/catalog plane shrinks from "NetBox superuser" to "flip a lifecycle tag."
- **Negative** — One more service account + permission set to provision and keep in sync; lifecycle tags must be guaranteed-present at bootstrap (a new ordering obligation on `netbox-sot`). Launcher refactor + token re-provision is multi-repo work.
- **Neutral** — Read paths already used the read-only svc tokens; only the write path changes. The admin token still exists (bootstrap/break-glass), just not in steady-state hands.

## Alternatives considered

1. **Keep using the admin token (just fix the empty value).** Rejected — directly violates ADR-0028 C3; a superuser token in every catalog JT's extra_vars is a standing least-privilege and blast-radius failure (and ADR-0025 noted JT extra_vars are returned in launch responses).
2. **Give the existing `awx-svc` write permissions.** Rejected as the primary path — `awx-svc` is the inventory-sync identity (`awx-readonly`); widening it to write conflates two roles. A purpose-named `dmf-catalog-svc` keeps scopes legible. (Acceptable fallback only if a separate account proves disproportionate.)
3. **Let launchers create tags on demand with the writer token.** Rejected as default — requires `extras.add_tag` in the steady-state scope. Pre-creating tags at bootstrap keeps the launcher's permission to a single model (`ipam.service`).

## Enforcement

- `netbox-sot` owns the `dmf-catalog-svc` + `dmf-catalog-writer` permission set and the baseline lifecycle tags; a `bootstrap-verify`-class assertion confirms the account exists, is non-superuser, and its permissions are limited to the allowed models.
- Review gate on `dmf-runbooks` launchers and `awx-integration` defaults: any `netbox_admin_token` (or other superuser/admin token) referenced from a steady-state launcher path is a violation — flag against this ADR.
- Discipline until the verifier lands; the audit-admin-identities / bootstrap-convergence verifier (ADR-0028 D2) is the natural home for the automated check.

## Cross-references

- See also: [ADR-0038](0038-netbox-driven-dynamic-monitoring.md) — monitoring
  metadata uses the same launcher path, but this ADR does not need a permission
  bump unless WP6 proves a direct `dcim.device` write path is required.
