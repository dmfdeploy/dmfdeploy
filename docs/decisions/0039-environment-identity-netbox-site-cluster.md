# ADR-0039: An environment's identity in NetBox is the Site + Cluster `dmf_env_id` custom field; no per-env tag

**Status:** Accepted
**Date:** 2026-06-04
**Deciders:** @<handle>, design conversation with Claude (2026-06-04) while scoping the
dmf-cms Facility page for NetBox-driven monitoring
**Relates to:** ADR-0013 (catalog model), ADR-0032 (scoped NetBox writer), ADR-0037
(Media Workloads = NetBox instance inventory), ADR-0038 (NetBox-driven dynamic
monitoring), ADR-0035 (operator-local self-contained envs)

## Context

The operator asked whether the dmf-cms **Facility** page could show the
born-inventoried `<env>`, and whether every resource in an env should carry a
NetBox tag. A read-only survey found that the env is already a first-class NetBox
object, modelled structurally and not as a tag. `dmf-born-inventory`
(`dmf-infra/k3s-lab-bootstrap/roles/common/dmf-born-inventory/`) creates a per-env
**Site** and a **Cluster** named `<env_id>`, each with the custom fields
`dmf_env_id`, `dmf_env_label`, `dmf_provider` and `dmf_architecture`.

All envs share one Tenant `DMF`, so tenant does not tell envs apart. Leaf resources
carry no env field and reach their env through foreign keys (VM to cluster, device
to site, `ipam.Service` to parent device to site). The only shared flat tag is
`dmf-day0`, which is the same string on every env. No `env:<id>` tag exists.
Env ids rotate, so a per-env tag would leave dead tags that nothing prunes. AWX
`nb_inventory` (`group_by: [sites, device_roles]`) and the ADR-0038 PromSD adapter
already scope by Site. The survey detail is in the archive record.

## Decision

1. **The env's canonical NetBox identity is its per-env Site and Cluster**, each carrying
   the `dmf_env_id` / `dmf_env_label` / `dmf_provider` / `dmf_architecture` custom fields
   already written by born-inventory. To find out which env an object belongs to and what it contains,
   read those objects and their custom fields.

2. **No per-env tag.** We deliberately introduce no `env:<id>` tag and no other
   per-env tag. Consumers scope an env by Site/Cluster directly, or by the
   `?cf_dmf_env_id=<id>` filter on Sites/Clusters. They reach leaf resources by foreign
   key: `dcim/devices/?site_id=`, `virtualization/virtual-machines/?cluster_id=`, and
   `ipam.Service` via its parent device. The generic `dmf-day0` tag stays as a
   "DMF day-0 inventory" marker. It does not carry env identity.

3. **Consistency.** This matches AWX `nb_inventory` `group_by: [sites, …]` and the
   ADR-0038 adapter's site-derived labels, so monitoring, automation inventory, and the
   console all scope envs the same way.

## Consequences

- **Positive:** the model is self-cleaning. On teardown the Site and Cluster are deleted
  wholesale, so the env disappears with no orphaned tags. There is no tag sprawl across
  rotating env ids. The model is NetBox-idiomatic: Site, Tenant and Cluster are the
  scoping primitives, and tags are for cross-cutting classification. It adds zero new
  write surface in born-inventory or the catalog writers.
- **Negative:** `ipam.Service` env-reachability is a **2-hop** (service → parent device
  → site). This is acceptable for current facility sizes. If env-scoped *service* queries
  become hot, a **future option** is to add `dmf_env_id` to `ipam.Service` (and/or attach
  services to the Cluster). This is explicitly not done now. It is unnecessary, and it
  avoids editing born-inventory/`app-service.yml` while the ADR-0038 monitoring effort
  owns those files.
- **Neutral:** the shared `DMF` tenant is unchanged. ADR-0020 cluster-per-tenant is a
  different (media-tenant) axis and is not affected. The dmf-cms gap that prompted this
  (the Facility page querying NetBox unscoped and ignoring `dmf_env_id`) is closed in the
  **console query/UI layer**. The inventory model does not change. See the work package
  `docs/plans/dmf-facility-console-born-inventoried-env-surfacing-plan.md`.

### Rejected alternatives

- A per-env `env:<id>` tag: rejected, env ids rotate and nothing prunes the tags.
- A per-env Tenant: rejected, ADR-0020 assigns the tenant axis to media tenants.
- `dmf_env_id` on every leaf object type now: deferred, more write surface for no current need.

### Enforcement

Discipline only: no check or test in this repo or in dmf-infra rejects an `env:<id>` tag. The rule holds because born-inventory writes none.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0039-environment-identity-netbox-site-cluster.md).
