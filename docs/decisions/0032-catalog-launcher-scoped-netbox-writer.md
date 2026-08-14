# ADR-0032: Catalog launchers mutate NetBox via a scoped writer service account, never the admin token

**Status:** Accepted (amended 2026-08-13 — `delete` added on `ipam.service` + `extras.tag` for `media-finalise-purge`; amended again 2026-08-14 — that `delete` grant object-scoped to workload-tagged records; see Amendments below)
**Date:** 2026-05-27
**Deciders:** @<handle> (raised the least-privilege question during the `<env>` catalog-deploy debugging session), with Claude investigation
**Refines:** [ADR-0028](0028-identity-and-authority-chain.md) C3 (scoped service accounts for machine-to-machine). Related: [ADR-0013](0013-media-function-catalog-model.md) (catalog model — NetBox runtime lifecycle tag), [ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md) (in-cluster launchers), [ADR-0007](0007-secrets-never-in-argv.md).

## Amendment 1 (2026-08-13, dmfdeploy/dmfdeploy#347)

The original scope below (`view`/`add`/`change` on `ipam.service`, `view`/`add`
on `extras.tag`, explicitly **no** `delete`) predates `media-finalise-purge`
(Arc 2b delete-permanently, added later in 2026). Every launcher this ADR was
originally scoped against only ever *patches* a lifecycle tag — "teardown
returns a record to recorded-but-not-running, it does not remove it."
`finalise-purge` is categorically different: it is the first and only
launcher that actually **deletes** an `ipam.service` record and its
`extras.tag`, a capability this account was never granted.

Discovered live (2026-08-13): the delete-permanently operator flow ran the
full AWX job to completion, but NetBox's own `ObjectPermission` model
silently rejected both DELETE calls (403, hidden by the launcher's
`no_log`/`ignore_errors` on that call — see
`dmf-runbooks/roles/netbox_catalog_common/tasks/_purge_delete_one_member.yml`
and `purge_workload_tag.yml`). The workload's residual records stayed
present; the playbook's own fail-closed final-read assert correctly refused
to report success rather than lying about it (`DMF_L3_PURGE_OUTCOME:
refused detail=final-read`) — the gate did its job, the permission grant
was just never widened to cover the new capability.

**Amended scope:** `delete` added to both `catalog-service-writer`
(`ipam.service`) and `catalog-tag-writer` (`extras.tag`) in
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox-sot/defaults/main.yml`
— narrowly, to the same two models this account already writes. No other
model, no staff/superuser bit, `dcim.device` stays view-only. The existing
`691-netbox-sot.yml` reconcile task already updates `ObjectPermission`
actions/object-types/group-binding idempotently — re-running it is
sufficient; no new provisioning task was needed. The Decision section below
is left as originally written for the historical record; this amendment is
the current source of truth for the permission matrix.

**Superseded in part by Amendment 2 below**: this amendment's `delete`
grant was model-wide (unconstrained across every `ipam.service`/`extras.tag`
record); Amendment 2 narrows it to an object-level constraint without
changing the models or actions granted here.

## Amendment 2 (2026-08-14, dmfdeploy/dmfdeploy#393 review)

lkirc reviewed Amendment 1 on this PR and caught a real least-privilege gap:
the `delete` grant above has no object-level `constraints` — `dmf-catalog-svc`
can delete **any** `ipam.service`/`extras.tag` record in the instance, not
just residue belonging to the workload actually being purged. A compromised
or misused catalog token could delete unrelated services and tags platform-
wide. The operator's direction: fix this with a genuine NetBox object-level
constraint, not just redocument the wider blast radius or split the delete
capability into a separate identity.

**What makes an `ipam.service` record legitimately purge-eligible**, per
`dmf-cms`'s own preflight (`resolve_purge_target`,
`src/dmf_cms/media_workloads.py`) and tag-classification logic:
- carries a tag matching `workload:<slug>` (the record is actually assigned
  to some workload — an unassigned/untagged record is never a purge
  candidate);
- the workload's members are not currently active/running — a **live**
  condition, cross-referencing the NetBox `lifecycle:*` tag against
  Prometheus overlay state (ADR-0013's model: liveness is a NetBox+
  Prometheus join, not data NetBox itself holds an opinion on).

**Amended scope:** `delete` is split out of `catalog-service-writer`
(`ipam.service`) and `catalog-tag-writer` (`extras.tag`) into its own
`ObjectPermission` entry per model
(`catalog-service-delete`, `catalog-tag-delete` in
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox-sot/defaults/main.yml`),
each carrying a `constraints` filter:

- `catalog-service-delete`: `{"tags__name__startswith": "workload:"}` —
  **allows** deleting an `ipam.service` record only if it carries at least
  one tag matching `workload:*`; **forbids** deleting any service with no
  workload assignment (which is never a legitimate purge target regardless
  of anything else).
- `catalog-tag-delete`: `{"name__startswith": "workload:"}` — `extras.Tag`'s
  own `name` field is a plain `CharField`, not a many-to-many relation, so
  this **allows** deleting only `Tag` objects literally named
  `workload:<slug>`; it **forbids** deleting any `lifecycle:*`, `app:*`,
  `dmf-catalog`, or other tag — the account can never remove platform-wide
  tag taxonomy, only a workload's own assignment tag.
- `view`/`add`/`change` on both models are **unchanged and still
  unconstrained** (Decision §1) — those actions apply to a record before a
  launcher has tagged it (at creation) or need to reach any record the
  launcher already manages (at patch time), so constraining them the same
  way would break every catalog CREATE/PATCH, including outside
  finalise-purge.

**What this constraint deliberately does *not* cover, and why:** it does
**not** additionally require the record's lifecycle to be
bootstrapped/unknown (i.e. it does not exclude a currently-active service
from being delete-eligible at the NetBox layer). This was investigated and
rejected as *not achievable*, not skipped as extra work:

1. NetBox's `ObjectPermission.constraints` (verified against v4.5.0 source —
   `netbox/utilities/permissions.py:qs_filter_from_constraints`,
   `netbox/users/models/permissions.py:ObjectPermission.list_constraints`)
   builds exactly one `Q(**dict)` per constraint dict and ORs across dicts/
   permission rows. Two conditions on the *same* many-to-many field (`tags`)
   inside one dict require the *same* related tag row to satisfy both —
   Django's documented multi-valued-relationship behavior — and the
   dict-of-lookups format has no negation primitive (no `__ne`, no subquery
   `exclude`). "Has a `workload:*` tag AND lacks a `lifecycle:active` tag"
   spans two different tag rows and is consequently not expressible as a
   single NetBox constraint, full stop — this is a structural limit of the
   mechanism, confirmed against source and Django's own docs, not a
   workaround gap in this change.
2. Independently of (1): whether a workload is *currently* active/running is
   a live join between NetBox's static `lifecycle:*` tag and Prometheus's
   observed state (ADR-0013) — it was never going to be expressible as a
   static NetBox queryset filter regardless of the M2M limitation above,
   because NetBox has no queryable concept of "is this running right now."
   RBAC duplicating a check that requires live Prometheus data isn't real
   defense-in-depth — it's impossible, and claiming otherwise here would be
   the "constraint that looks right in the YAML but doesn't actually bind"
   failure this review was specifically watching for.

That liveness axis remains, as it always has, exclusively enforced by
`media-finalise-purge`'s own preflight (`resolve_purge_target`'s
three-layered zero-running check against NetBox + Prometheus) before any
DELETE is ever issued. The object-level NetBox constraint added here is a
second, independent enforcement point for the *static* half of purge
eligibility (workload assignment) — genuine defense in depth for that half,
not a duplicate of the app-layer check, and not a claim to cover the half
only the app layer can ever see.

Verification: `yamllint`, `ansible-lint` (production profile), and
`ansible-playbook --syntax-check` all pass on the `dmf-infra` change; the
templated NetBox provisioning script was rendered locally for all five
`netbox_sot_catalog_permissions` entries and each syntax-checked as valid
Python. Live positive proof (`delete-permanently` still works end to end)
and negative proof (a non-workload-tagged or otherwise ineligible record's
delete is rejected by NetBox's own RBAC, not just the playbook's app-layer
check) are the operator's to run directly against real infra before this
amendment's status can be called verified — not something a documentation
or ansible-role change can establish on its own.

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

- **Positive** — Catalog deploys run under a named, audited, minimally-scoped identity. Closes the C3 gap. The blast radius of the AWX/catalog plane shrinks from "NetBox superuser" to a token that can only ever touch two models (`ipam.service`, `extras.tag`) plus read `dcim.device`. **Stale as of Amendment 1/2 — corrected here:** it is no longer accurate to say a compromised token "can touch lifecycle tags on services, nothing more." As of Amendment 1 (2026-08-13) the token can also **delete** `ipam.service`/`extras.tag` records; as of Amendment 2 (2026-08-14) that delete is object-scoped to records carrying a `workload:*` tag (an `ipam.service` delete) or literally named `workload:<slug>` (an `extras.tag` delete) — a compromised token cannot delete anything outside that shape, but `view`/`add`/`change` on both models remain unconstrained across every record of those two types the account can reach, as they always have been (§1). The actual current blast radius: create/patch any `ipam.service` or `extras.tag` record (including flipping a lifecycle tag on one that isn't the token's own), plus delete any record that is or was workload-assigned — never anything outside those two models, never dcim/other apps, never staff/superuser.
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
