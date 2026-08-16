# ADR-0032: Catalog launchers mutate NetBox via a scoped writer service account, never the admin token

**Status:** Accepted (amended 2026-08-13 — `delete` added on `ipam.service` + `extras.tag` for `media-finalise-purge`; amended again 2026-08-14 — that `delete` grant object-scoped to workload-tagged records; amended a third time, same day — `delete` moved off `dmf-catalog-svc` entirely, onto a new delete-only `dmf-catalog-purge-svc` identity; amended a fourth time, 2026-08-16 — `view` on `dcim.site` added to `dmf-catalog-writer` for the L3 topology guard's site-agreement read; see Amendments below)
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

**Residual risk, found by adversarial review (codex, 2026-08-14) and not
closeable within this design — stated precisely rather than left implicit:**
because `catalog-tag-writer` keeps unconstrained `add` on `extras.tag` and
`catalog-service-writer` keeps unconstrained `change` on `ipam.service` (both
necessarily, per the point above), the *same* `dmf-catalog-svc` token can
manufacture delete-eligibility for a record that was never actually a purge
candidate: create a `workload:<arbitrary>` tag, attach it to any existing
`ipam.service` record via `change`, then delete that record because it now
matches `tags__name__startswith: "workload:"`. The `catalog-tag-delete`
constraint has the same shape of gap: it makes every `workload:*` Tag object
deletable by name alone, not only the one tied to the workload actually being
purged — a compromised token isn't limited to deleting the tag for the
workload it has a legitimate reason to touch. This constraint therefore does
**not** provide a hermetic guarantee against a *maliciously used* token; what
it closes is the blast radius lkirc actually named — an accidental, careless,
or narrowly-compromised use hitting arbitrary unrelated NetBox records with
no `workload:*` involvement at all, which is the realistic failure mode a
scoped-but-multi-action writer account can meaningfully defend against. A
deliberate escalation now costs the attacker two extra, auditable NetBox
writes (tag create + service retag) instead of zero — real, but not a closed
door. Closing it fully would require either a materially different identity
model (a separate, even-more-restricted account for `workload:*` tag
creation, which the operator's direction for this amendment explicitly ruled
out reaching for by default) or a detective control (alerting on
tag-create-then-delete in short succession on this account). Neither is
implemented here; flagged as follow-up, not resolved.

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
templated NetBox provisioning script was rendered locally for all
`netbox_sot_catalog_permissions` entries (plus adversarial inputs — a JSON
boolean, embedded quotes/backslashes/newlines in a constraint value) and each
syntax-checked and evaluated as correct Python. An adversarial codex review
of the `dmf-infra` diff found and this amendment fixed one real templating
bug (constraints were rendered as raw JSON tokens pasted into Python source —
correct for today's plain-string values by coincidence of overlapping
syntax, but `true`/`false`/`null` would `NameError` and only quotes were
escaped, not backslashes/newlines; fixed by `json.loads()`-ing a properly
string-escaped payload instead) and one real, not-closeable-here scope gap
(the residual risk documented just above) — both taken seriously rather than
argued away. Live positive proof (`delete-permanently` still works end to
end) and negative proof (a non-workload-tagged or otherwise ineligible
record's delete is rejected by NetBox's own RBAC, not just the playbook's
app-layer check) are the operator's to run directly against real infra
before this amendment's status can be called verified — not something a
documentation or ansible-role change can establish on its own.

**Superseded by Amendment 3 below**: lkirc rejected this amendment's
constraint-only design twice, on exactly the residual risk documented above
— asked for it closed, not documented. Amendment 3 closes it.

## Amendment 3 (2026-08-14, dmfdeploy/dmfdeploy#347)

The residual risk Amendment 2 documented as accepted-not-closed —
`dmf-catalog-svc`'s necessary `add`/`change` on the same two models making
its `delete` grant self-manufacturable — is exactly what lkirc flagged again
on Amendment 2's own review: "the delete predicate remains self-satisfiable
by this same token." The operator's direction: fix this for real, by
identity separation, not a detective control or a documented waiver.

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

**Verified against the actual task include graph, not assumed:** every task
`media-finalise-purge` (`dmf-runbooks/playbooks/finalise-purge.yml`) invokes
— `netbox_catalog_common`'s `purge_workload_records`/`purge_workload_tag`/
`purge_final_read`, plus every `l3_run_guard` task in its call path
(`lock_only`, `teardown_pre_mutation`, `lock_checkpoint`, `lock_release`,
`release`, `fault_inject`, `_emit_purge_outcome`, `purge_outcome_guard`,
`gate_rescue`) — was read, not grepped-and-trusted. Its entire NetBox surface
is `GET` (list, by-id, tag-by-name) and `DELETE` on `ipam.service` and
`extras.tag`; no `POST`, no `PATCH`, no `dcim.device` read (that lookup is
CREATE-time only, attaching a fresh service to its parent device — a launcher
this playbook never behaves like). The facility lock itself is a Kubernetes
ConfigMap `PUT`/`DELETE` (`l3_run_guard/tasks/lock_checkpoint.yml`,
`lock_release.yml`) against `_l3_api_url`, a wholly separate API from
NetBox — locking needs nothing from this account beyond the token being
non-empty (`_assert_netbox_token.yml` is a structural presence check, never
a live NetBox call). `dmf-catalog-purge-svc`'s scope is therefore both
necessary and sufficient for everything this launcher actually does.

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

Verification: `yamllint roles/stack/operator/netbox-sot/
roles/stack/operator/awx-integration/`, `ansible-lint playbooks/ -p`
(production profile), and `ansible-playbook --syntax-check` on every
`dmf-infra` playbook all pass. The templated purge-permission provisioning
script was rendered locally (including the multi-model `catalog-purge-reader`
entry) and syntax/runtime-checked the same way as Amendment 2's constraints.
`dmf-runbooks`' `tests/l3-finalise-purge-execution.yml` — the real,
stub-backed integration suite for this exact playbook, ~18 nested
`ansible-playbook` subprocess invocations — was run locally end to end
against the updated var. Live proof against real infra (both directions,
plus lkirc's gate) remains the operator's, as with every prior amendment.

## Amendment 4 (2026-08-16, dmfdeploy/dmfdeploy#399)

Media workload creation failed deterministically on any clean environment:
the L3 topology guard's first NetBox call — `GET /api/dcim/sites/`, listing
the env's own facility identity — 403'd, because `dmf-catalog-writer` was
never granted `view` on `dcim.site`. Diagnosed live (AWX job event record:
`403`, empty `job_explanation`/`result_traceback`, failing inside the
playbook before any rescue path) and adversarially confirmed; full evidence
chain on [dmfdeploy/dmfdeploy#399](https://github.com/dmfdeploy/dmfdeploy/issues/399).

**Not a regression from Amendment 3.** The timeline is a latent mismatch,
not new breakage: the `media-*` catalog job-template lane was swept onto
the scoped-writer-only token on 2026-07-20 (dropping the fallback admin
token), and `l3_run_guard`'s topology-validation site read landed five days
later, 2026-07-25 — three weeks before Amendment 3's identity split. The
permission gap predates every prior amendment on this ADR; it simply had no
topology-carrying launch to exercise it until the single-template demo
catalog made the topology path the only supported one.

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

Verification: negative check unchanged from every prior amendment's own
posture — the catalog identity still cannot write or delete `dcim.site` (no
`add`/`change`/`delete` action granted, this or any prior amendment). Live
proof — a topology-carrying launch completes on a clean environment — is
the operator's to run against real infra, per #399's own acceptance
criteria, not something a documentation or ansible-role change can
establish on its own.

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

- **Positive** — Catalog deploys run under named, audited, minimally-scoped identities. Closes the C3 gap. **Rewritten for Amendment 3 (2026-08-14) — the AWX/catalog plane is now TWO identities, not one, each with a materially narrower blast radius than "NetBox superuser":**
  - `dmf-catalog-svc` (every catalog launcher except finalise-purge): can create or patch any `ipam.service`/`extras.tag` record — e.g. flip a lifecycle tag, attach a tag, create a new service record — but, as of this amendment, **cannot delete anything at all**. No `delete` action on any model.
  - `dmf-catalog-purge-svc` (`media-finalise-purge` only): can **delete** an `ipam.service`/`extras.tag` record, but only one already carrying/matching a `workload:*` tag (Amendment 2's constraint) — and, critically, **cannot create or patch anything**, on either model. It cannot manufacture a record's eligibility before deleting it; the constraint is a real bound on this identity, not a filter a sibling capability could route around (Amendment 1/2's own residual risk, now closed).
  - Neither identity ever reaches `dcim.device` write, staff, or superuser. `dcim.device` stays `dmf-catalog-svc`-view-only, unchanged (§1).
  This corrects two prior versions of this paragraph in turn: Amendment 1 made "flip a lifecycle tag, nothing more" stale by adding delete to the shared token; Amendment 2's constraint narrowed but did not remove that same-token delete capability; Amendment 3 removes it from the shared token entirely and gives the narrower capability its own, non-mutating identity.
- **Negative** — One more service account + permission set to provision and keep in sync; lifecycle tags must be guaranteed-present at bootstrap (a new ordering obligation on `netbox-sot`). Launcher refactor + token re-provision is multi-repo work.
- **Neutral** — Read paths already used the read-only svc tokens; only the write path changes. The admin token still exists (bootstrap/break-glass), just not in steady-state hands.

## Alternatives considered

1. **Keep using the admin token (just fix the empty value).** Rejected — directly violates ADR-0028 C3; a superuser token in every catalog JT's extra_vars is a standing least-privilege and blast-radius failure (and ADR-0025 noted JT extra_vars are returned in launch responses).
2. **Give the existing `awx-svc` write permissions.** Rejected as the primary path — `awx-svc` is the inventory-sync identity (`awx-readonly`); widening it to write conflates two roles. A purpose-named `dmf-catalog-svc` keeps scopes legible. (Acceptable fallback only if a separate account proves disproportionate.)
3. **Let launchers create tags on demand with the writer token.** Rejected as default — requires `extras.add_tag` in the steady-state scope. Pre-creating tags at bootstrap keeps the launcher's permission to a single model (`ipam.service`).

## Enforcement

- `netbox-sot` owns the `dmf-catalog-svc` + `dmf-catalog-writer` permission set, the `dmf-catalog-purge-svc` + `dmf-catalog-purge` permission set (Amendment 3), and the baseline lifecycle tags; a `bootstrap-verify`-class assertion confirms both accounts exist, are non-superuser, and their permissions are limited to the allowed models — for `dmf-catalog-purge-svc` specifically, that its `actions` never include `add` or `change` on any model, which is the entire property Amendment 3 depends on.
- Review gate on `dmf-runbooks` launchers and `awx-integration` defaults: any `netbox_admin_token` (or other superuser/admin token) referenced from a steady-state launcher path is a violation — flag against this ADR.
- Discipline until the verifier lands; the audit-admin-identities / bootstrap-convergence verifier (ADR-0028 D2) is the natural home for the automated check.

## Cross-references

- See also: [ADR-0038](0038-netbox-driven-dynamic-monitoring.md) — monitoring
  metadata uses the same launcher path, but this ADR does not need a permission
  bump unless WP6 proves a direct `dcim.device` write path is required.
