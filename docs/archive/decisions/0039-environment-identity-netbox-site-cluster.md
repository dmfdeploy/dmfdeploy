# ADR-0039 archive: An environment's identity in NetBox is the Site + Cluster `dmf_env_id` custom field; no per-env tag

This file holds material moved out of [ADR-0039](../../decisions/0039-environment-identity-netbox-site-cluster.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

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
- `docs/plans/dmf-facility-console-born-inventoried-env-surfacing-plan.md` —
  the dmf-cms work package that surfaces the env on the Facility page using this model.

## Moved from the ADR on 2026-10-23

### Context (original)

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
  per-env *tag* would therefore accumulate dead tags (`env:<env-a>`, `env:<env-b>`, …)
  that nothing prunes.
- **Existing consumers already scope by Site/Cluster.** AWX's `nb_inventory` groups by
  `group_by: [sites, device_roles]` (`awx-integration`), and the ADR-0038 PromSD adapter
  derives target labels from `site`. Site/Cluster is the established scoping grain.
