# ADR-0032 archive: Catalog launchers mutate NetBox via a scoped writer service account, never the admin token

This file holds material moved out of [ADR-0032](../../decisions/0032-catalog-launcher-scoped-netbox-writer.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

1. **Keep using the admin token (just fix the empty value).** Rejected — directly violates ADR-0028 C3; a superuser token in every catalog JT's extra_vars is a standing least-privilege and blast-radius failure (and ADR-0025 noted JT extra_vars are returned in launch responses).
2. **Give the existing `awx-svc` write permissions.** Rejected as the primary path — `awx-svc` is the inventory-sync identity (`awx-readonly`); widening it to write conflates two roles. A purpose-named `dmf-catalog-svc` keeps scopes legible. (Acceptable fallback only if a separate account proves disproportionate.)
3. **Let launchers create tags on demand with the writer token.** Rejected as default — requires `extras.add_tag` in the steady-state scope. Pre-creating tags at bootstrap keeps the launcher's permission to a single model (`ipam.service`).

   **[Amended — "a single model" reflected the original two-model scope this account held at ADR-authoring time; it no longer holds as of Amendment 4, which adds a second read-only model (`dcim.site`) on top of the pre-existing `dcim.device` view. See Amendment 4's consolidated current-matrix table.]**

## Cross-references

- See also: [ADR-0038](../../decisions/0038-netbox-driven-dynamic-monitoring.md) — monitoring
  metadata uses the same launcher path, but this ADR does not need a permission
  bump unless WP6 proves a direct `dcim.device` write path is required.

## Amendment 1 — problem and discovery (moved from the ADR)

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

## Amendment 2 — problem and review narrative (moved from the ADR)

lkirc reviewed Amendment 1 on this PR and caught a real least-privilege gap:
the `delete` grant above has no object-level `constraints` — `dmf-catalog-svc`
can delete **any** `ipam.service`/`extras.tag` record in the instance, not
just residue belonging to the workload actually being purged. A compromised
or misused catalog token could delete unrelated services and tags platform-
wide. The operator's direction: fix this with a genuine NetBox object-level
constraint, not just redocument the wider blast radius or split the delete
capability into a separate identity.

## Amendment 2 — residual risk found in review (moved from the ADR)

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

## Amendment 2 — why the constraint cannot also require inactivity (moved from the ADR)

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

## Amendment 2 — verification (moved from the ADR)

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

## Amendment 3 — problem and direction (moved from the ADR)

The residual risk Amendment 2 documented as accepted-not-closed —
`dmf-catalog-svc`'s necessary `add`/`change` on the same two models making
its `delete` grant self-manufacturable — is exactly what lkirc flagged again
on Amendment 2's own review: "the delete predicate remains self-satisfiable
by this same token." The operator's direction: fix this for real, by
identity separation, not a detective control or a documented waiver.

## Amendment 3 — task include graph check (moved from the ADR)

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

## Amendment 3 — verification (moved from the ADR)

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

## Amendment 4 — problem and evidence (moved from the ADR)

Media workload creation failed deterministically on any clean environment:
the L3 topology guard's first NetBox call — `GET /api/dcim/sites/`, listing
the env's own facility identity — 403'd, because `dmf-catalog-writer` was
never granted `view` on `dcim.site`. Diagnosed live (AWX job event record:
`403`, empty `job_explanation`/`result_traceback`, failing inside the
playbook before any rescue path) and adversarially confirmed; full evidence
chain on [dmfdeploy/dmfdeploy#399](https://github.com/dmfdeploy/dmfdeploy/issues/399).

## Amendment 4 — timeline: not a regression from Amendment 3 (moved from the ADR)

**Not a regression from Amendment 3.** The timeline is a latent mismatch,
not new breakage: the `media-*` catalog job-template lane was swept onto
the scoped-writer-only token on 2026-07-20 (dropping the fallback admin
token), and `l3_run_guard`'s topology-validation site read landed five days
later, 2026-07-25 — three weeks before Amendment 3's identity split. The
permission gap predates every prior amendment on this ADR; it simply had no
topology-carrying launch to exercise it until the single-template demo
catalog made the topology path the only supported one.

## Amendment 4 — verification (moved from the ADR)

Verification: negative check unchanged from every prior amendment's own
posture — the catalog identity still cannot write or delete `dcim.site` (no
`add`/`change`/`delete` action granted, this or any prior amendment). Live
proof — a topology-carrying launch completes on a clean environment — is
the operator's to run against real infra, per #399's own acceptance
criteria, not something a documentation or ansible-role change can
establish on its own.
