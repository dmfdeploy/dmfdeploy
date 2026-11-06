# ADR-0032: Catalog launchers mutate NetBox via a scoped writer service account, never the admin token

<!-- vale Dmfdeploy.SentenceLength = NO -->
**Status:** Accepted (amended 2026-08-13; `delete` added on `ipam.service` + `extras.tag` for `media-finalise-purge`; amended again 2026-08-14; that `delete` grant object-scoped to workload-tagged records; amended a third time, same day; `delete` moved off `dmf-catalog-svc` entirely, onto a new delete-only `dmf-catalog-purge-svc` identity; amended a fourth time, 2026-08-16; `view` on `dcim.site` added to `dmf-catalog-writer` for the L3 topology guard's site-agreement read; see Amendments 1–4 in the archive record)
<!-- vale Dmfdeploy.SentenceLength = YES -->
**Date:** 2026-05-27
**Deciders:** @<handle> (raised the least-privilege question during the `<env>` catalog-deploy debugging session), with Claude investigation
**Rule:** Catalog launchers (and any steady-state automation that mutates NetBox) authenticate with a dedicated, narrowly scoped NetBox writer service account, and never the NetBox admin/superuser token.
**Refines:** [ADR-0028](0028-identity-and-authority-chain.md) C3 (scoped service accounts for machine-to-machine). Related: [ADR-0013](0013-media-function-catalog-model.md) (catalog model: NetBox runtime lifecycle tag), [ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md) (in-cluster launchers), [ADR-0007](0007-secrets-never-in-argv.md).

## Context

ADR-0028 C3 requires scoped service accounts for machines. But `netbox-sot` provisions the catalog-relevant service accounts **read-only** (`dmf-cms-svc`, `awx-svc`), while steady-state catalog launchers must **write** NetBox: they apply the ADR-0013 lifecycle tag on the function's `ipam.service` record. The nmos-cpp launcher used `netbox_admin_token` (NetBox superuser) to cover the missing identity, which is the posture C3 forbids. The full original wording is in the [archive record](../archive/decisions/0032-catalog-launcher-scoped-netbox-writer.md).

## Decision

**Catalog launchers (and any steady-state automation that mutates NetBox) authenticate with a dedicated, narrowly scoped NetBox *writer* service account, and never the NetBox admin/superuser token.** Concretely:

1. `netbox-sot` provisions two scoped identities. It declares their `ObjectPermission` entries in `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox-sot/defaults/main.yml`, and the idempotent create-or-update reconcile in `691-netbox-sot.yml` applies them. Neither identity has superuser/staff, and neither has a dcim *write*.

   **`dmf-catalog-svc`** (group `dmf-catalog-writer`) serves every catalog launcher except `media-finalise-purge`. Its permissions are limited to exactly these, none constrained:
   - `ipam.service`: **view, add, change**. A launcher *creates* the per-deployment service record at provision (`POST /ipam/services/`) and *patches* its lifecycle tag at configure/teardown (`PATCH`).
   - `extras.tag`: **view, add**. A launcher creates the per-function `app:<key>` tag (for example `app:nmos-cpp`), which is *not* in the bootstrap taxonomy. The `lifecycle:*` tags are pre-created by `netbox-sot`. No tag `change`.
   - `dcim.device`: **view** (read-only). A launcher looks up the parent load-balancer device (`dmf-traefik`) to attach the service to.
   - `dcim.site`: **view** (read-only), via the `catalog-site-reader` permission. The fail-closed L3 topology guard (`topology_validate.yml`) reads it to assert *site agreement*. This grant has the same shape as the `dcim.device` read and adds no new capability class.
   - **No `delete` on any model.**

   **`dmf-catalog-purge-svc`** (group `dmf-catalog-purge`) serves `media-finalise-purge` only. It is genuinely delete-only:
   - `view` (unconstrained) on `ipam.service` and `extras.tag`, for the launcher's own preflight reads and readback-confirms.
   - `delete` on `ipam.service`, constrained `{"tags__name__startswith": "workload:"}`. This **allows** deleting a record only if it *currently* carries at least one `workload:*` tag, and **forbids** deleting any service bearing no such tag at the moment of the DELETE call.
   - `delete` on `extras.tag`, constrained `{"name__startswith": "workload:"}`. This **allows** deleting only `Tag` objects literally named `workload:<slug>`, and **forbids** deleting any `lifecycle:*`, `app:*`, `dmf-catalog`, or other tag. The account can never remove platform-wide tag taxonomy, only a `workload:*` assignment tag.
   - **No `add`, no `change`, on either model.** This identity cannot create a tag or retag a service, so it cannot manufacture its own delete-eligibility. The constraint is a real bound on what this token can do, and no sibling capability on the *same* token can route around it.

   The effective permission matrix:

   | Object type | Actions | Constraint | Identity |
   |---|---|---|---|
   | `ipam.service` | view, add, change | none | `dmf-catalog-svc` |
   | `extras.tag` | view, add | none | `dmf-catalog-svc` |
   | `dcim.device` | view | none | `dmf-catalog-svc` |
   | `dcim.site` | view | none | `dmf-catalog-svc` |
   | `ipam.service` | view | none | `dmf-catalog-purge-svc` |
   | `extras.tag` | view | none | `dmf-catalog-purge-svc` |
   | `ipam.service` | delete | `tags__name__startswith: "workload:"` | `dmf-catalog-purge-svc` |
   | `extras.tag` | delete | `name__startswith: "workload:"` | `dmf-catalog-purge-svc` |

   `dmf-catalog-svc` never holds `delete` on anything. `dmf-catalog-purge-svc` never holds `add` or `change` on anything. The purge identity's split depends on the first invariant and the constraint on the second.

   `dcim.site` is **deliberately left unconstrained (operator ruling)**. Do not scope visible sites to the env's own. A constrained read cannot support the check it is for: an identity that sees only one site would pass the site-agreement assertion unconditionally, because it cannot observe disagreement. The console's Plan step is also meant to become a facility picker, with an environment owning one or more `Site`s scoped by `cf_dmf_env_id`, so a single-site constraint would have to be undone. This is directional context only. It opens no scope beyond the `dcim.site` view grant and implements nothing toward that picker.

   The `delete` actions were once granted to `dmf-catalog-svc`, first model-wide and then object-constrained, and have been retired from it. An explicit idempotent cleanup task removes the retired `catalog-service-delete` and `catalog-tag-delete` `ObjectPermission` rows on an already-provisioned instance. Dropping them from the declared list is not enough, because the reconcile loop only creates or updates what it is given and never prunes.

   Tokens are minted to OpenBao under the `<system>-token-<purpose>` convention and wired into the catalog JT extra_vars by `awx-integration`. The purge token is minted by `netbox-sot` into `secret/apps/netbox/runtime` (key `netbox_purge_token`), and `awx-integration` wires it into `media-finalise-purge`'s own JT `extra_vars` as `vault_netbox_purge_token`. Every other catalog launcher JT stays on `vault_netbox_catalog_token`.
2. Launchers drop the `netbox_admin_token` input **across all stages** (provision/configure/finalise) and use their scoped token for every NetBox call (reads and writes): `vault_netbox_catalog_token` for every launcher except `media-finalise-purge`, which uses `vault_netbox_purge_token`. This is one principal per job, which keeps the single-principal audit story and [ADR-0028](0028-identity-and-authority-chain.md) C3.1 attribution intact. `dmf-catalog-svc` remains the only NetBox identity a topology-carrying launch authenticates as. Routing only the `dcim.site` read through the read-only `awx-netbox` identity was rejected, because two NetBox principals inside one job is a real audit boundary that ADR-0028 C3.1 would require documenting. It is not a free routing choice.
3. **Purge eligibility has two halves.** The *static* half is enforced by NetBox: an `ipam.service` record is purge-eligible only if it carries a tag matching `workload:<slug>`, and an unassigned or untagged record is never a purge candidate. The *live* half is that the workload's members are not currently active/running. It is a cross-reference of the NetBox `lifecycle:*` tag against Prometheus overlay state (ADR-0013's model: liveness is a NetBox+Prometheus join, and NetBox itself holds no opinion on it), so no NetBox constraint can express it. It stays exclusively enforced by `media-finalise-purge`'s own preflight (`resolve_purge_target` in `dmf-cms`'s `src/dmf_cms/media_workloads.py`, a three-layered zero-running check against NetBox + Prometheus) before any DELETE is issued. The object-level constraint is a second, independent enforcement point for the static half. It does not duplicate the app-layer check, and it does not cover the half only the app layer can see. The identity split never addressed that gap and does not claim to.
4. The platform-wide `lifecycle:*` tags stay pre-created at bootstrap (`netbox-sot`). **Tightening follow-up:** pre-create per-function `app:<key>` tags at bootstrap too (born-inventory already reconciles catalog entries), which would let the writer drop `extras.add_tag` and shrink to `extras.view_tag`. Deferred: the launcher's create-if-missing is idempotent and keeps `netbox-sot` decoupled from the function list for now.
5. The NetBox admin/superuser token is **bootstrap/break-glass only** (per ADR-0028 C4 sanctioned-exception posture) and must not appear in any steady-state JT, role default, or runtime secret consumed by a launcher.

The amendment history (Amendments 1–4: the `delete` grant, its constraint, the move to the purge identity, and the `dcim.site` read) is in the [archive record](../archive/decisions/0032-catalog-launcher-scoped-netbox-writer.md#amendment-history). This Decision is the current rule with those amendments applied.

## Consequences

- **Positive:** Catalog deploys run under named, audited, minimally scoped identities. Closes the C3 gap. As of Amendment 3 the AWX/catalog plane is two identities, each with a materially narrower blast radius than "NetBox superuser":
  - `dmf-catalog-svc` (every catalog launcher except finalise-purge) can create or patch any `ipam.service`/`extras.tag` record, for example flip a lifecycle tag, attach a tag or create a new service record. It **cannot delete anything at all**. It has no `delete` action on any model.
  - `dmf-catalog-purge-svc` (`media-finalise-purge` only) can **delete** an `ipam.service`/`extras.tag` record, but only one already carrying/matching a `workload:*` tag (Amendment 2's constraint). It **cannot create or patch anything** on either model, so it cannot manufacture a record's eligibility before deleting it. The constraint is a real bound on this identity. A sibling capability cannot route around it, which closes Amendment 1/2's own residual risk.
  - Neither identity ever reaches `dcim.device` write, staff, or superuser. `dcim.device` stays `dmf-catalog-svc`-view-only, unchanged (§1).
- **Negative:** One more service account + permission set to provision and keep in sync; lifecycle tags must be guaranteed-present at bootstrap (a new ordering obligation on `netbox-sot`). Launcher refactor + token re-provision is multi-repo work.
- **Neutral:** Read paths already used the read-only svc tokens; only the write path changes. The admin token still exists (bootstrap/break-glass), but no steady-state job holds it.

### Enforcement

discipline only: no check asserts these permission sets or flags an admin token in a launcher path, and `bootstrap-verify.yml` has no such assertion (confirmed by grep of dmf-infra and dmf-runbooks). `netbox-sot` (`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox-sot/defaults/main.yml`) declares and reconciles the `dmf-catalog-svc` + `dmf-catalog-writer` and `dmf-catalog-purge-svc` + `dmf-catalog-purge` permission sets and the baseline lifecycle tags, but that is provisioning only; it verifies nothing. Review gate on `dmf-runbooks` launchers and `awx-integration` defaults: any `netbox_admin_token` (or other superuser/admin token) referenced from a steady-state launcher path is a violation, flagged against this ADR. The audit-admin-identities / bootstrap-convergence verifier (ADR-0028 D2) is the natural home for an automated check, including that `dmf-catalog-purge-svc` never holds `add` or `change` on any model, the property Amendment 3 depends on.

## Status

<!-- vale Dmfdeploy.SentenceLength = NO -->
Accepted (amended 2026-08-13; `delete` added on `ipam.service` + `extras.tag` for `media-finalise-purge`; amended again 2026-08-14; that `delete` grant object-scoped to workload-tagged records; amended a third time, same day; `delete` moved off `dmf-catalog-svc` entirely, onto a new delete-only `dmf-catalog-purge-svc` identity; amended a fourth time, 2026-08-16; `view` on `dcim.site` added to `dmf-catalog-writer` for the L3 topology guard's site-agreement read; see Amendments 1–4 in the archive record)
<!-- vale Dmfdeploy.SentenceLength = YES -->

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0032-catalog-launcher-scoped-netbox-writer.md).
