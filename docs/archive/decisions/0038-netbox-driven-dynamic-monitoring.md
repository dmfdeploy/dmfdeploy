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

## Amendment history

These are Amendments A and B to ADR-0038, moved from the ADR when its Decision was rewritten as the current rule. The text is unchanged apart from relative link paths. Where an amendment overrides an earlier rule, the ADR's Decision states only the later rule.

### Amendment A (2026-06-04): probe / scrape targets via cluster service DNS

**Status:** Accepted. Amends §3, §4, and the §5 lane-level address contract.

Problem statement and evidence: see the [archive record](0038-netbox-driven-dynamic-monitoring.md).

#### Decision

**The probe and scrape targets for in-cluster objects are the object's stable
cluster Service DNS name, composed by the adapter from identity recorded in NetBox.
They are never a pod or ingress IP.** This applies uniformly to born-inventoried platform
apps and to dynamically deployed catalog/media-function services.

1. **Record the stable cluster identity.** Add three custom fields to the
   contract (typed, optional, stamped by whoever deploys the object). The contract records no IP for in-cluster objects.

   | Custom field | Type | Meaning |
   |---|---|---|
   | `cluster_service` | text | the Kubernetes `Service` name |
   | `cluster_namespace` | text | the Kubernetes namespace |
   | `cluster_port` | integer | the in-cluster Service port to probe (the app's service port, which is **not** necessarily the ingress `:443` recorded in `ipam.service.ports`) |

   A Kubernetes Service's DNS name (`<svc>.<ns>.svc.cluster.local`) and ClusterIP are
   **stable for the Service's lifetime** and survive pod rescheduling; only the pods
   behind it churn. So the adapter never needs to discover or track an IP. The
   target is a deterministic function of `cluster_service` + `cluster_namespace`.

2. **The deployer is the bridge.** The agent that *creates* the Kubernetes Service is
   the one thing that holds both the cluster reality and the NetBox record, so it
   stamps `cluster_service`/`cluster_namespace`/`cluster_port` at registration time,
   in the same lifecycle step it already stamps the monitoring tags:
   - **born-inventory** (platform apps) knows each app's Service name/ns/port.
   - **catalog launcher** (dynamic media functions) knows the Service it
     created (ADR-0037 instance inventory).

   No separate IP-to-service reconciler is needed.

3. **Adapter composition (replaces the §5 Probe / Scrape `__address__` derivation for
   in-cluster objects).** Let `host = <cluster_service>.<cluster_namespace>.svc.cluster.local`:
   - **Probe:** `__address__ = host:<cluster_port>`; the request is plain internal
     **HTTP** (ADR-0023). `__param_module = probe_module` as before. WP5's blackbox
     indirection relabel is unchanged.
   - **Scrape:** `__address__ = host:<metrics_port>`, `__metrics_path__ = metrics_path`.
   - **Precedence / fallback:** if `cluster_service` + `cluster_namespace` are present,
     the adapter uses the svc-DNS form. Otherwise it falls back to
     `primary_ip4.address`, which remains correct for **external / off-cluster
     devices** and the **SNMP lane** (physical gear that legitimately has an IP and no
     cluster Service).

#### Consequences / notes

- This fits the ADR-0023 internal-svc-DNS-over-plain-HTTP posture: no
  ingress Host/path juggling, no TLS/CA-in-pod problem, no shared-LB-IP ambiguity.
  The probe answers "is the Service responding," which is the right health signal.
- `exposure:public` objects *may* later warrant an **additional** external-URL probe
  (does the ingress actually serve it end-to-end), composed from `exposure:*` +
  `external_base_url`. That is an optional second probe and is **deferred**; the
  internal svc-DNS probe is the robust baseline and the default.

### Amendment B (2026-07-03): `probe_path` probe-lane URL path

**Status:** Accepted. Amends §3, §4, and the Amendment A adapter composition.

Problem statement: see the [archive record](0038-netbox-driven-dynamic-monitoring.md).

#### Decision

**Add one custom field to the monitoring contract:**

| Custom field | Type | Default | Object types |
|---|---|---|---|
| `probe_path` | text | empty | `ipam.service`, `dcim.device`, `virtualization.virtualmachine` |

**Semantics (probe-lane only):**

1. `probe_path` participates only in the probe lane. The scrape lane keeps
   `metrics_path`; the SNMP lane ignores `probe_path` entirely.
2. The adapter appends the path to the composed probe target **only when the
   selected `probe_module` is an http prober** (module name starting `http_`).
   For any other module (`tcp_connect`, `icmp`, …) the field is ignored and the
   target remains `host:port`.
3. The path is normalized to a single leading `/` (`ready` and `/ready` both
   yield `…:3100/ready`); trailing content is preserved as given.
4. An empty or absent `probe_path` is a no-op: the composed target is exactly
   what Amendment A specifies.
5. The append applies to **both** address compositions: the svc-DNS form
   (`<svc>.<ns>.svc.cluster.local:<cluster_port><probe_path>`) and the
   `primary_ip4.address` fallback (`<ip>:<port><probe_path>`).

The blackbox http prober accepts a schemeless full-URL target, and the existing probe-job relabelling (`__param_target <- __address__`) forwards it unchanged. So this amendment changes only the adapter's target composition. It leaves the Prometheus job contract and the `/sd/*` output shape unchanged.

**The `dmf_blackbox_probe_modules` choice set (§3) additionally gains
`http_2xx_302`**, an http prober with `follow_redirects: false` and
`valid_status_codes: [200, 301, 302, 303, 307, 308]`, for targets whose healthy
root response is a redirect that must not be dereferenced (canonical case:
Grafana's `/` to `/login` behind an OAuth auto-login chain to a local-CA URL).
As everywhere in §3, the choice set must stay lock-step with the deployed
blackbox-exporter module list.

#### Consequences / notes

- The catalog `monitoring.probe` block gains an optional `probe_path` key,
  mapping 1:1 to the custom field, consistent with §3's additive-schema rule.
- Stamping follows Amendment A's "the deployer is the bridge" rule: born-inventory
  (platform apps) and the catalog launcher stamp `probe_path` alongside the other
  monitoring fields, gated on `monitoring:probe`.
