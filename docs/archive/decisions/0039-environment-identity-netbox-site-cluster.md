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
