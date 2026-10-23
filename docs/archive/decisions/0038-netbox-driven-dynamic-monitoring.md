# ADR-0038 archive: NetBox-driven dynamic monitoring with a standalone PromSD adapter

This file holds material moved out of [ADR-0038](../../decisions/0038-netbox-driven-dynamic-monitoring.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

1. **Use the `netbox-plugin-prometheus-sd` plugin.** Rejected. It couples the DMF
   NetBox lifecycle to a third-party plugin compatibility matrix, and it weakens the
   platform’s ability to keep the mapping under local control.
2. **Keep bootstrap-time `file_sd` as the bridge.** Rejected. It only captures a
   one-time snapshot and cannot continuously reconcile target sets as the facility
   changes.
3. **Use only Kubernetes discovery.** Rejected. That leaves physical devices,
   off-cluster services, and SNMP gear outside the monitoring model.
4. **Model monitoring separately per lane.** Rejected. The platform would then need
   multiple contracts, which creates drift between the catalog, NetBox, and the
   launcher behavior.

## Cross-references

- [ADR-0010](../../decisions/0010-run-playbook-as-sanctioned-entry.md) — deploy/verify work packages
  and live checks run through the sanctioned wrapper.
- [ADR-0013](../../decisions/0013-media-function-catalog-model.md) for the catalog definition /
  runtime-record split that this monitoring contract extends.
- [ADR-0023](../../decisions/0023-internal-service-dns-for-cross-app-wiring.md) for the internal
  service-DNS posture used by cross-app plumbing inside the cluster.
- [ADR-0028](../../decisions/0028-identity-and-authority-chain.md) — the adapter holds a scoped
  NetBox read token under the machine-identity model.
- [ADR-0027](../../decisions/0027-catalog-instance-vs-definition-separation.md) for the layering
  language that this ADR reuses while choosing NetBox + AWX over a custom operator.
- [ADR-0032](../../decisions/0032-catalog-launcher-scoped-netbox-writer.md) for the scoped NetBox
  writer model used when launchers stamp lifecycle and monitoring metadata.
- [ADR-0034](../../decisions/0034-internal-ansible-collection-source.md) for the air-gap /
  internal-source posture that the adapter release path must respect.
- [ADR-0037](../../decisions/0037-media-workloads-netbox-instance-inventory.md) for the decision
  that NetBox stores media-function instances and placement, not live flow state.

## Context — what this ADR defines (moved from the ADR)

This ADR closes that gap by defining:

- a two-lane discovery model with one monitoring contract;
- a precise catalog schema for the monitoring contract;
- the NetBox tag and custom-field taxonomy that drives the adapter;
- the Kubernetes annotation conventions for in-cluster scrape targets;
- the adapter boundary for a standalone DMF PromSD service; and
- the decision to supersede the older bootstrap-time `file_sd` bridge from the
  Day-0 monitoring plan.

## Amendment A — problem and evidence (moved from the ADR)

#### Problem (found in the first live e2e)

The original §5 "Probe" row said the adapter emits `__address__ = <real target>` but
never defined how a *service* yields a target. In practice a NetBox `ipam.Service`
registered by born-inventory (and, by extension, by the catalog launcher) carries a
name, ports, a parent device, and the monitoring tags/fields — **but no usable
address**: `ipaddresses` is empty, and every platform app sits behind one shared
Traefik ingress on `LB-IP:443`, differentiated only by Host/path. So the adapter
fetched all tagged services but emitted **zero** probe/scrape targets (no
`__address__` to compose). Pod IPs are unusable anyway — they churn on reschedule.

## Amendment A — work-package impact (moved from the ADR)

- Work-package impact: WP1 (netbox-sot) seeds the three custom fields; WP6 (catalog
  launcher) and WP7 (born-inventory) stamp them; WP3 (dmf-promsd) implements the
  composition + fallback. The `/sd/*` http_sd output contract is unchanged.

## Amendment B — problem (moved from the ADR)

#### Problem

The probe lane composes a host:port target (Amendment A) and selects a blackbox
module (`probe_module`), but has no way to express a URL path. Some targets are
only meaningfully probeable on a specific path — the canonical case is Loki, whose
root returns non-2xx by design while its health contract is `GET /ready` on the
HTTP port. Blackbox modules cannot carry a path (the http prober takes the path
from the *target*), and `metrics_path` is scrape-lane-only by §3. Without a
path field the only workarounds are wrong ones: a public ingress detour for an
internal health check, or `tcp_connect` (port-open ≠ ready).

## Amendment B — work-package impact (moved from the ADR)

- Work-package impact (monitoring close-out plan, 2026-07-02): netbox-sot seeds
  the field; born-inventory stamps it (`loki → /ready`); dmf-promsd implements
  the normalization + conditional append.

## Moved from the ADR on 2026-10-23

### Context (original)

The platform proved the Prometheus stack principle, but the current target wiring is
still static. It is effectively a frozen copy of chart-default scrape jobs with only
in-cluster Kubernetes discovery, a self-scrape, and one dangling probe target. That
shape is not sufficient for a dynamic media facility where devices, services, and
media functions appear, disappear, and move continuously.

NetBox is already the operational source of truth for the facility. ADR-0037 settled
that deployed media-function instances live in NetBox as inventory, not as a custom
CRD. ADR-0013 already established the catalog pattern as YAML intent plus a NetBox
runtime record. The missing piece is monitoring: the platform needs one declarative
contract that lets monitoring attach and detach automatically as the facility
changes, without a human re-running a playbook.

### Decision 1, original wording

Monitoring is no longer a static scrape-config list. A catalog entry declares what
should be observed, NetBox stores the live facility record, and Prometheus
continuously reconciles its targets against both NetBox and Kubernetes state. The
intended effect is simple: when an object is created, moved, or removed in the
facility, its monitoring follows automatically.

### Decision 6, rationale for the standalone service

Rationale for the standalone service, versus the rejected
`netbox-plugin-prometheus-sd` approach:

- **Air-gap and source control:** the adapter can ride the existing image rail and
  release process without requiring a custom NetBox image or a new Python-package
  distribution path.
- **Version compatibility:** the adapter depends on the stable NetBox REST API, so
  NetBox upgrades do not require coupling to a third-party plugin compatibility
  matrix.
- **Mapping ownership:** the dmfdeploy platform owns the NetBox-to-target mapping and can
  encode the exact taxonomy above without waiting on external plugin behavior.

### Decision 7, original wording

The Day-0 inventory and monitoring plan’s bootstrap-time `file_sd` bridge is now
superseded by this ADR. Bootstrap may still seed the initial state, but the canonical
bridge is live `http_sd` from `dmf-promsd`, not a one-time file export.

### Operator decision 2, original cache paragraph

Prometheus polls the adapter on `refresh_interval: 30s`. The adapter serves targets
from an in-memory cache refreshed on its own approximately `45s` timer so NetBox is
queried at a fixed low rate regardless of Prometheus replica count, matching the
`nb_inventory` cache-timeout pattern. That gives a worst-case churn latency of
roughly `75s` from NetBox change to scraped target visibility. NetBox webhook-driven
cache invalidation is deferred.

### Consequences (original)

- **Positive**: Monitoring becomes declarative and facility-driven instead of
  being a frozen scrape list.
- **Positive**: NetBox remains the single source of truth for what exists and
  should be observed, while Kubernetes stays responsible for in-cluster pod
  discovery.
- **Positive**: The contract is explicit enough for downstream implementation work
  to proceed without new architecture decisions.
- **Positive**: The adapter can be versioned, tested, and released independently of
  NetBox.
- **Positive**: The `/sd/*` contract stays stable while the adapter’s internal
  caching strategy evolves, so Prometheus wiring does not need to change as the
  implementation matures.
- **Negative**: There is one more component to build and operate.
- **Negative**: The platform now has a deliberate split between scrape, probe, and
  SNMP discovery paths, which is more to wire than a single discovery source.
- **Neutral**: The old bootstrap-time `file_sd` approach remains documented as
  historical context, but it is no longer canonical.

### Enforcement (original)

The follow-on work packages must implement the contract exactly as written here.
Any implementation that changes the monitoring contract schema, introduces a second
contract shape, or reverts the bridge to a bootstrap-only file export should be
treated as an ADR violation and reviewed against this decision first.
