# ADR-0032: Catalog launchers mutate NetBox via a scoped writer service account, never the admin token

**Status:** Accepted (amended 2026-08-13: `delete` added on `ipam.service` + `extras.tag` for `media-finalise-purge`; amended again 2026-08-14: that `delete` grant object-scoped to workload-tagged records; amended a third time, same day: `delete` moved off `dmf-catalog-svc` entirely, onto a new delete-only `dmf-catalog-purge-svc` identity; amended a fourth time, 2026-08-16: `view` on `dcim.site` added to `dmf-catalog-writer` for the L3 topology guard's site-agreement read; see Amendments 1–4 in the Decision section)
**Date:** 2026-05-27
**Deciders:** @<handle> (raised the least-privilege question during the `<env>` catalog-deploy debugging session), with Claude investigation
**Refines:** [ADR-0028](0028-identity-and-authority-chain.md) C3 (scoped service accounts for machine-to-machine). Related: [ADR-0013](0013-media-function-catalog-model.md) (catalog model — NetBox runtime lifecycle tag), [ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md) (in-cluster launchers), [ADR-0007](0007-secrets-never-in-argv.md).

## Context

ADR-0028 C3 binds: *"Machines use scoped service accounts… scoped, named, documented, and stored in OpenBao."* But `netbox-sot` provisions the catalog-relevant service accounts **read-only** (`dmf-cms-svc`→`dmf-cms-readonly`, `awx-svc`→`awx-readonly`). The steady-state catalog launchers (e.g. `media-launch-nmos-cpp`, run in-cluster as the AWX identity per ADR-0025) must **write** NetBox: create/apply the ADR-0013 lifecycle tag on the function's `ipam.service` record. With no scoped writer available, the nmos-cpp launcher authenticated with `netbox_admin_token` (NetBox superuser), and on a fresh sandbox where that token was empty it fell back to the read-only token and 403'd at the first write. The real tension: a steady-state automated action was using superuser custody to paper over a missing least-privilege identity, which is exactly the posture C3 forbids.

## Decision

**Catalog launchers (and any steady-state automation that mutates NetBox) authenticate with a dedicated, narrowly-scoped NetBox *writer* service account, and never the NetBox admin/superuser token.** Concretely:

1. `netbox-sot` provisions a catalog writer service account (`dmf-catalog-svc`) in a `dmf-catalog-writer` group whose object permissions are limited to exactly the three models the launchers touch (verified against the nmos-cpp role, all stages + the live deploy):

   **[Amended: this list is the original 2026-05-27 record, left as written per this ADR's own convention (Amendment 1: "the Decision section above is left as originally written for the historical record"). It has since been amended four times; as of Amendment 4 the grant covers a fourth model, `dcim.site`, so "exactly the three models" is no longer accurate. Do not read the list below as current. See Amendment 4's consolidated current-matrix table.]**

   - `ipam.service`: **view, add, change**: a launcher *creates* the per-deployment service record at provision (`POST /ipam/services/`) and *patches* its lifecycle tag at configure/teardown (`PATCH`).
   - `extras.tag`: **view, add**: a launcher creates the per-function `app:<key>` tag (e.g. `app:nmos-cpp`) which is *not* in the bootstrap taxonomy; the `lifecycle:*` tags are pre-created by `netbox-sot`.
   - `dcim.device`: **view** (read-only): a launcher looks up the parent load-balancer device (`dmf-traefik`) to attach the service to. No write on dcim.
   No superuser/staff, no dcim *write*, no tag `change`/`delete`. Token minted to OpenBao under the `<system>-token-<purpose>` convention and wired into the catalog JT extra_vars by `awx-integration`.
2. Launchers drop the `netbox_admin_token` input **across all stages** (provision/configure/finalise) and use the scoped catalog token for every NetBox call (reads and writes).

   **[Amended: as of Amendment 3 (2026-08-14), this no longer covers every launcher: `media-finalise-purge` authenticates as a second, separate identity (`dmf-catalog-purge-svc`, its own `vault_netbox_purge_token`), so the single scoped catalog token described here does not cover it. See Amendment 4's consolidated current-matrix table, which lists both identities.]**
3. The platform-wide `lifecycle:*` tags stay pre-created at bootstrap (`netbox-sot`). **Tightening follow-up:** pre-create per-function `app:<key>` tags at bootstrap too (born-inventory already reconciles catalog entries), which would let the writer drop `extras.add_tag` and shrink to `extras.view_tag`. Deferred: the launcher's create-if-missing is idempotent and keeps `netbox-sot` decoupled from the function list for now.
4. The NetBox admin/superuser token is **bootstrap/break-glass only** (per ADR-0028 C4 sanctioned-exception posture) and must not appear in any steady-state JT, role default, or runtime secret consumed by a launcher.

### Amendment 1 (2026-08-13, dmfdeploy/dmfdeploy#347)

Problem statement and evidence: see the [archive record](../archive/decisions/0032-catalog-launcher-scoped-netbox-writer.md).

**Amended scope:** `delete` added to both `catalog-service-writer`
(`ipam.service`) and `catalog-tag-writer` (`extras.tag`) in
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox-sot/defaults/main.yml`
— narrowly, to the same two models this account already writes. No other
model, no staff/superuser bit, `dcim.device` stays view-only. The existing
`691-netbox-sot.yml` reconcile task already updates `ObjectPermission`
actions/object-types/group-binding idempotently — re-running it is
sufficient; no new provisioning task was needed. The Decision section above
is left as originally written for the historical record; this amendment is
the current source of truth for the permission matrix.

**Superseded in part by Amendment 2 below**: this amendment's `delete`
grant was model-wide (unconstrained across every `ipam.service`/`extras.tag`
record); Amendment 2 narrows it to an object-level constraint without
changing the models or actions granted here.

### Amendment 2 (2026-08-14, dmfdeploy/dmfdeploy#393 review)

Problem statement and evidence: see the [archive record](../archive/decisions/0032-catalog-launcher-scoped-netbox-writer.md).

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
  **allows** deleting an `ipam.service` record only if it *currently* carries
  at least one tag matching `workload:*`; **forbids** deleting any service
  bearing no such tag at the moment of the DELETE call.
- `catalog-tag-delete`: `{"name__startswith": "workload:"}` — `extras.Tag`'s
  own `name` field is a plain `CharField`, not a many-to-many relation, so
  this **allows** deleting only `Tag` objects literally named
  `workload:<slug>`; it **forbids** deleting any `lifecycle:*`, `app:*`,
  `dmf-catalog`, or other tag — the account can never remove platform-wide
  tag taxonomy, only a `workload:*` assignment tag.
- `view`/`add`/`change` on both models are **unchanged and still
  unconstrained** (Decision §1) — those actions apply to a record before a
  launcher has tagged it (at creation) or need to reach any record the
  launcher already manages (at patch time), so constraining them the same
  way would break every catalog CREATE/PATCH, including outside
  finalise-purge.

Investigation of why a NetBox constraint cannot also require inactivity: see the [archive record](../archive/decisions/0032-catalog-launcher-scoped-netbox-writer.md).

That liveness axis remains, as it always has, exclusively enforced by
`media-finalise-purge`'s own preflight (`resolve_purge_target`'s
three-layered zero-running check against NetBox + Prometheus) before any
DELETE is ever issued. The object-level NetBox constraint added here is a
second, independent enforcement point for the *static* half of purge
eligibility (workload assignment) — genuine defense in depth for that half,
not a duplicate of the app-layer check, and not a claim to cover the half
only the app layer can ever see.

**Superseded by Amendment 3 below**: lkirc rejected this amendment's
constraint-only design twice, on exactly the residual risk documented above
— asked for it closed, not documented. Amendment 3 closes it.

### Amendment 3 (2026-08-14, dmfdeploy/dmfdeploy#347)

Problem statement and evidence: see the [archive record](../archive/decisions/0032-catalog-launcher-scoped-netbox-writer.md).

**Amended scope:** `delete` is removed from `dmf-catalog-svc` entirely.
`catalog-service-writer`/`catalog-tag-writer` revert to exactly their
original ADR-0032 scope — `view`/`add`/`change` on `ipam.service`,
`view`/`add` on `extras.tag`, no `delete` at all. The Amendment-2-era
`catalog-service-delete`/`catalog-tag-delete` entries are retired (not just
undeclared — an explicit idempotent cleanup task removes the corresponding
`ObjectPermission` rows on an already-provisioned instance; simply dropping
them from the role's declared permission list would have left them silently
in place, since the reconcile loop only ever creates/updates what it is
given, never prunes what it no longer sees).

`media-finalise-purge` moves to a **new, genuinely delete-only identity**:
`dmf-catalog-purge-svc` (group `dmf-catalog-purge`), granted:
- `view` (unconstrained) on `ipam.service` + `extras.tag` — needed for the
  launcher's own preflight reads and readback-confirms.
- `delete` on `ipam.service`, constrained `{"tags__name__startswith":
  "workload:"}` — Amendment 2's constraint, unchanged, reused as-is.
- `delete` on `extras.tag`, constrained `{"name__startswith": "workload:"}`
  — likewise reused unchanged.
- **No `add`, no `change`, on either model.** This is the entire point: this
  identity cannot create a tag or retag a service, so it cannot manufacture
  its own delete-eligibility. Amendment 2's constraint is now a real bound on
  what this token can do, not a filter a sibling capability on the *same*
  token could route around.

**Token plumbing:** `netbox-sot` mints and persists the new token to the
same `secret/apps/netbox/runtime` OpenBao secret, key `netbox_purge_token`
(mint-if-absent, OpenBao-reuse-on-rerun — byte-same idempotency shape as the
existing `netbox_catalog_token` gate). `awx-integration` reads it from the
same `bao kv get` that already fetches `netbox_catalog_token` (no second
round-trip) and wires it into `media-finalise-purge`'s own JT `extra_vars`
as `vault_netbox_purge_token` — every *other* catalog launcher JT is
unchanged, still on `vault_netbox_catalog_token`. `finalise-purge.yml`'s
play-scope `netbox_api_token` mapping now sources
`vault_netbox_purge_token` instead — its header already anticipated
per-launcher token isolation being reachable this way. The `dmf-runbooks`
integration test suite (`tests/l3-finalise-purge-execution.yml`, ~18
nested real-playbook invocations including the dedicated blank-token
refusal probe) was updated in lockstep and re-run locally against the stub
NetBox/K8s harness — a suite left on the old var name would have kept
passing while silently testing a var the playbook no longer reads.

**What this closes, precisely:** the self-manufactured-eligibility path
Amendment 2 left open. `dmf-catalog-purge-svc` cannot create a
`workload:<anything>` tag or attach one to a service — it has no `add`/
`change` capability on either model, full stop — so there is no path by
which this token can make an ineligible record eligible before deleting it.
Combined with Amendment 2's constraint (reused unchanged), delete is now
bound to records that were *already*, independently, `workload:*`-tagged —
not records this same token chose to tag moments before deleting them.

**What this still does not close, unchanged from Amendment 2, and for the
same reason:** whether a workload is *currently* active/running remains
outside NetBox's own queryable data (a live NetBox+Prometheus join per
ADR-0013) and stays exclusively enforced by `resolve_purge_target`'s own
preflight. That was never a gap this identity split could address, and
isn't claimed to be one.

### Amendment 4 (2026-08-16, dmfdeploy/dmfdeploy#399)

Problem statement and evidence: see the [archive record](../archive/decisions/0032-catalog-launcher-scoped-netbox-writer.md).

**Amended scope:** a new `catalog-site-reader` ObjectPermission — `view` on
`dcim.site`, bound to `dmf-catalog-writer` — added to
`netbox_sot_catalog_permissions` in
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox-sot/defaults/main.yml`,
adjacent to `catalog-device-reader`. No write, no delete, no staff/superuser
bit, no change to any existing grant. The existing catalog-permission
reconcile loop (`691-netbox-sot.yml`, the same idempotent
create-or-update-by-name task Amendment 1 already relied on) applies it on
the next run; no new provisioning task was needed.

**Directly precedented.** This is the same shape as the existing
`catalog-device-reader` grant (Decision §1): *"the launcher looks up the
parent load-balancer device (dmf-traefik) to attach the service to. View
only — no write."* The site read is identical in kind — a read-only lookup
the launcher needs to complete a fail-closed validation before any media
work runs, not a new capability class for this identity.

**Deliberately left unconstrained (operator ruling).** Amendment 2 set a
precedent on this ADR for object-level `constraints` — on `delete`. Applying
that same instinct here, e.g. scoping visible sites to the env's own, would
be wrong, for two reasons:

1. **A constrained read cannot support the check it's for.**
   `topology_validate.yml` asserts *site agreement* — that the env's own
   facility identity matches what the topology expects. An identity that
   can only ever see one site would pass that assertion unconditionally,
   because it is structurally incapable of observing disagreement. A check
   that is green because it is blind is worse than no check.
2. **The intended direction moves the other way.** The console's Plan step
   is meant to become a real facility picker, with an environment owning
   one-or-more `Site`s scoped by `cf_dmf_env_id`. A single-site constraint
   imposed now would have to be undone for that to work. Recorded here as
   directional context only — it opens no scope beyond this amendment's own
   grant, and implements nothing toward that picker.

**ADR-0032 Decision §2 is preserved, not touched.** Decision §2 states
launchers use the scoped catalog token for every NetBox call, "reads and
writes" — one principal per job, which is what makes the single-principal
audit story and [ADR-0028](0028-identity-and-authority-chain.md) C3.1
attribution hold. This amendment keeps that: `dmf-catalog-svc` gains one
more read-only model; it remains the only NetBox identity a
topology-carrying launch ever authenticates as. The rejected alternative —
routing just this read through the existing read-only `awx-netbox`
identity — was rejected precisely because it would have broken that
contract: two NetBox principals inside one job is a real audit boundary
ADR-0028 C3.1 would require documenting, not a free routing choice. (The
model is readable by that other identity — `awx-readonly` does hold
`dcim.site` view — the gap was never that the data was unreadable
platform-wide, only that this identity couldn't read it.)

**Current effective permission matrix, all four amendments applied.**
Decision §1 above is the *original* record and is deliberately left
unedited (this ADR's own convention); it now undercounts by one model and
says nothing about the second identity Amendment 3 introduced. This table
is the single place that reflects both — derived directly from the
committed `dmf-infra` source
(`k3s-lab-bootstrap/roles/stack/operator/netbox-sot/defaults/main.yml`,
`netbox_sot_catalog_permissions` and `netbox_sot_catalog_purge_permissions`,
branch `fix/399-catalog-site-reader` @ `cf30fb8`), not re-derived from this
ADR's own prose:

| Object type | Actions | Constraint | Identity |
|---|---|---|---|
| `ipam.service` | view, add, change | — | `dmf-catalog-svc` |
| `extras.tag` | view, add | — | `dmf-catalog-svc` |
| `dcim.device` | view | — | `dmf-catalog-svc` |
| `dcim.site` | view | — | `dmf-catalog-svc` |
| `ipam.service` | view | — | `dmf-catalog-purge-svc` |
| `extras.tag` | view | — | `dmf-catalog-purge-svc` |
| `ipam.service` | delete | `tags__name__startswith: "workload:"` | `dmf-catalog-purge-svc` |
| `extras.tag` | delete | `name__startswith: "workload:"` | `dmf-catalog-purge-svc` |

`dmf-catalog-svc` (group `dmf-catalog-writer`) never holds `delete` on
anything; `dmf-catalog-purge-svc` (group `dmf-catalog-purge`) never holds
`add` or `change` on anything — the two invariants Amendment 3 and
Amendment 2's constraint respectively depend on, both still holding.

## Consequences

- **Positive** — Catalog deploys run under named, audited, minimally-scoped identities. Closes the C3 gap. **Rewritten for Amendment 3 (2026-08-14) — the AWX/catalog plane is now TWO identities, not one, each with a materially narrower blast radius than "NetBox superuser":**
  - `dmf-catalog-svc` (every catalog launcher except finalise-purge): can create or patch any `ipam.service`/`extras.tag` record — e.g. flip a lifecycle tag, attach a tag, create a new service record — but, as of this amendment, **cannot delete anything at all**. No `delete` action on any model.
  - `dmf-catalog-purge-svc` (`media-finalise-purge` only): can **delete** an `ipam.service`/`extras.tag` record, but only one already carrying/matching a `workload:*` tag (Amendment 2's constraint) — and, critically, **cannot create or patch anything**, on either model. It cannot manufacture a record's eligibility before deleting it; the constraint is a real bound on this identity, not a filter a sibling capability could route around (Amendment 1/2's own residual risk, now closed).
  - Neither identity ever reaches `dcim.device` write, staff, or superuser. `dcim.device` stays `dmf-catalog-svc`-view-only, unchanged (§1).
  This corrects two prior versions of this paragraph in turn: Amendment 1 made "flip a lifecycle tag, nothing more" stale by adding delete to the shared token; Amendment 2's constraint narrowed but did not remove that same-token delete capability; Amendment 3 removes it from the shared token entirely and gives the narrower capability its own, non-mutating identity.
- **Negative** — One more service account + permission set to provision and keep in sync; lifecycle tags must be guaranteed-present at bootstrap (a new ordering obligation on `netbox-sot`). Launcher refactor + token re-provision is multi-repo work.
- **Neutral** — Read paths already used the read-only svc tokens; only the write path changes. The admin token still exists (bootstrap/break-glass), just not in steady-state hands.

### Enforcement

- `netbox-sot` owns the `dmf-catalog-svc` + `dmf-catalog-writer` permission set, the `dmf-catalog-purge-svc` + `dmf-catalog-purge` permission set (Amendment 3), and the baseline lifecycle tags; a `bootstrap-verify`-class assertion confirms both accounts exist, are non-superuser, and their permissions are limited to the allowed models — for `dmf-catalog-purge-svc` specifically, that its `actions` never include `add` or `change` on any model, which is the entire property Amendment 3 depends on.
- Review gate on `dmf-runbooks` launchers and `awx-integration` defaults: any `netbox_admin_token` (or other superuser/admin token) referenced from a steady-state launcher path is a violation — flag against this ADR.
- Discipline until the verifier lands; the audit-admin-identities / bootstrap-convergence verifier (ADR-0028 D2) is the natural home for the automated check.

## Status

Accepted (amended 2026-08-13: `delete` added on `ipam.service` + `extras.tag` for `media-finalise-purge`; amended again 2026-08-14: that `delete` grant object-scoped to workload-tagged records; amended a third time, same day: `delete` moved off `dmf-catalog-svc` entirely, onto a new delete-only `dmf-catalog-purge-svc` identity; amended a fourth time, 2026-08-16: `view` on `dcim.site` added to `dmf-catalog-writer` for the L3 topology guard's site-agreement read; see Amendments 1–4 in the Decision section)

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0032-catalog-launcher-scoped-netbox-writer.md).
