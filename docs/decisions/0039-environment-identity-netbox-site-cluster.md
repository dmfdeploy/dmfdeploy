# ADR-0039: An environment's identity in NetBox is the Site + Cluster `dmf_env_id` custom field; no per-env tag

**Status:** Accepted
**Date:** 2026-06-04
**Deciders:** @<handle>, design conversation with Claude (2026-06-04) while scoping the
dmf-cms Facility page for NetBox-driven monitoring
**Relates to:** ADR-0013 (catalog model), ADR-0032 (scoped NetBox writer), ADR-0037
(Media Workloads = NetBox instance inventory), ADR-0038 (NetBox-driven dynamic
monitoring), ADR-0035 (operator-local self-contained envs)

## Context

Starting NetBox-driven monitoring, the operator asked whether the dmf-cms **Facility**
page could show the **born-inventoried `<env>`**, and whether every resource belonging to
an env should be **tagged** in NetBox — or whether that already happens. A read-only
survey of `dmf-born-inventory`, the `netbox-sot` taxonomy, the catalog/nmos writers, and
the dmf-cms NetBox client established the facts below.

**The env is already a first-class NetBox object — modelled structurally, not as a tag:**

- `dmf-born-inventory`
  (`dmf-infra/k3s-lab-bootstrap/roles/common/dmf-born-inventory/tasks/main.yml`,
  `defaults/main.yml`) creates, per env:
  - a **Site** named `DMF <label/id>` (slug per-env), and
  - a **Cluster** named `<env_id>` (`virtualization.cluster`),

  each stamped with four **custom fields** (defined on `dcim.site` +
  `virtualization.cluster`): `dmf_env_id`, `dmf_env_label`, `dmf_provider`,
  `dmf_architecture` (provider/architecture are choice-set enums).
- All envs share a single **Tenant** `DMF` (slug `dmf`) — tenant does **not**
  discriminate envs.
- Leaf resources carry **no** env field; they reach their env only **relationally**:
  VM → `cluster`; the `dmf-traefik` load-balancer **device** → `site`; `ipam.Service`
  (the platform apps) → `parent_object` → LB device → site; IP addresses →
  interface → VM → cluster.
- The only flat tag every DMF object shares is **`dmf-day0`** — an **env-agnostic**
  marker (identical string on every env ever built). A grep of `dmf-infra` and
  `dmf-runbooks` found **no `env:<id>` tag** anywhere; the catalog/nmos taxonomy
  (`dmf-catalog`, `lifecycle:*`, `exposure:*`, `app:<key>`) likewise has no env dimension.

Two further forces matter:

- **Env ids rotate.** Per the platform's operating model, env identifiers are
  short-lived — new ones are cut as the build shifts (`STATUS.local.md` holds the live id after running `bin/generate-status.sh`). A
  per-env *tag* would therefore accumulate dead tags (`env:imc1-cyh4`, `env:g2r6`, …)
  that nothing prunes.
- **Existing consumers already scope by Site/Cluster.** AWX's `nb_inventory` groups by
  `group_by: [sites, device_roles]` (`awx-integration`), and the ADR-0038 PromSD adapter
  derives target labels from `site`. Site/Cluster is the established scoping grain.

## Decision

1. **The env's canonical NetBox identity is its per-env Site and Cluster**, each carrying
   the `dmf_env_id` / `dmf_env_label` / `dmf_provider` / `dmf_architecture` custom fields
   already written by born-inventory. To answer "what env is this, and what's in it",
   read those objects and their custom fields.

2. **No per-env tag.** We deliberately do **not** introduce an `env:<id>` tag (or any
   per-env tag). Consumers scope an env by Site/Cluster directly — or by the
   `?cf_dmf_env_id=<id>` filter on Sites/Clusters — and reach leaf resources by foreign
   key: `dcim/devices/?site_id=`, `virtualization/virtual-machines/?cluster_id=`, and
   `ipam.Service` via its parent device. The generic `dmf-day0` tag stays as a
   "DMF day-0 inventory" marker and is **not** repurposed to carry env identity.

3. **Consistency.** This matches AWX `nb_inventory` `group_by: [sites, …]` and the
   ADR-0038 adapter's site-derived labels, so monitoring, automation inventory, and the
   console all scope envs the same way.

## Consequences

- **Positive** — self-cleaning: on teardown the Site and Cluster are deleted wholesale,
  so the env disappears with no orphaned tags; no tag sprawl across rotating env ids; the
  model is NetBox-idiomatic (Site/Tenant/Cluster are the scoping primitives, tags are for
  cross-cutting classification); zero new write surface in born-inventory or the catalog
  writers.
- **Negative** — `ipam.Service` env-reachability is a **2-hop** (service → parent device
  → site). This is acceptable for current facility sizes. If env-scoped *service* queries
  become hot, a **future option** is to add `dmf_env_id` to `ipam.Service` (and/or attach
  services to the Cluster) — explicitly **not** done now, both because it is unnecessary
  and to avoid editing born-inventory/`app-service.yml` while the ADR-0038 monitoring
  effort owns those files.
- **Neutral** — the shared `DMF` tenant is unchanged; ADR-0020 cluster-per-tenant is a
  different (media-tenant) axis and is not affected. The dmf-cms gap that prompted this
  (the Facility page querying NetBox unscoped and ignoring `dmf_env_id`) is closed in the
  **console query/UI layer**, not in the inventory model — see the work package
  `docs/plans/DMF Facility Console — Born-Inventoried Env Surfacing Plan 2026-06-04.md`.

## Alternatives considered

- **Per-env tag `env:<id>` on every object.** Rejected: env ids rotate, so tags
  accumulate and nothing prunes them; the information is redundant with the Site/Cluster
  structure and FK chains; tags enforce nothing. Single-dimension `?tag=` filtering is the
  only upside and is matched by `?cf_dmf_env_id=` / `?site_id=` / `?cluster_id=`.
- **Per-env Tenant.** Rejected: tenant is the shared `DMF` and ADR-0020 already assigns
  the tenant axis to media tenants (cluster-per-tenant); overloading it for operator envs
  would conflict.
- **Add `dmf_env_id` to all leaf object types now.** Deferred (see Consequences): more
  write surface for no current need, and it would touch files the monitoring effort owns.

## Cross-references

- `dmf-infra/k3s-lab-bootstrap/roles/common/dmf-born-inventory/` — writes the Site,
  Cluster, the four `dmf_*` custom fields, and the `dmf-day0` tag.
- ADR-0037 — Media Workloads scope by tenant/site (server-side authz); same scoping grain.
- ADR-0038 — PromSD adapter labels derive from `site`; this ADR keeps env scoping aligned.
- ADR-0032 — scoped NetBox writer (`dmf-catalog-svc`); a future `ipam.Service` env field
  would land through it.
- `docs/plans/DMF Facility Console — Born-Inventoried Env Surfacing Plan 2026-06-04.md` —
  the dmf-cms work package that surfaces the env on the Facility page using this model.
