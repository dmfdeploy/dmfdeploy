# ADR-0038: NetBox-driven dynamic monitoring with a standalone PromSD adapter

**Status:** Accepted
**Date:** 2026-06-04
**Deciders:** @<handle>, planning session with Claude (2026-06-04)
**Touches:** [ADR-0010](0010-run-playbook-as-sanctioned-entry.md) (sanctioned playbook entry), [ADR-0013](0013-media-function-catalog-model.md) (catalog model), [ADR-0023](0023-internal-service-dns-for-cross-app-wiring.md) (in-cluster HTTP wiring), [ADR-0027](0027-catalog-instance-vs-definition-separation.md) (instance-layer framing), [ADR-0028](0028-identity-and-authority-chain.md) (identity / scoped-token custody), [ADR-0032](0032-catalog-launcher-scoped-netbox-writer.md) (scoped NetBox writer), [ADR-0034](0034-internal-ansible-collection-source.md) (air-gap/runtime source posture), [ADR-0037](0037-media-workloads-netbox-instance-inventory.md) (NetBox instance inventory)

## Context

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

This ADR closes that gap by defining:

- a two-lane discovery model with one monitoring contract;
- a precise catalog schema for the monitoring contract;
- the NetBox tag and custom-field taxonomy that drives the adapter;
- the Kubernetes annotation conventions for in-cluster scrape targets;
- the adapter boundary for a standalone DMF PromSD service; and
- the decision to supersede the older bootstrap-time `file_sd` bridge from the
  Day-0 monitoring plan.

## Decision

**1. NetBox is the single source of truth for monitoring intent.**

Monitoring is no longer a static scrape-config list. A catalog entry declares what
should be observed, NetBox stores the live facility record, and Prometheus
continuously reconciles its targets against both NetBox and Kubernetes state. The
intended effect is simple: when an object is created, moved, or removed in the
facility, its monitoring follows automatically.

**2. Discovery uses two lanes, but one contract.**

The platform distinguishes two discovery lanes:

- **In-cluster workloads** are discovered by Prometheus Kubernetes service
  discovery. This lane stays annotation-driven and self-healing because the pods and
  services already exist inside the cluster.
- **External or off-cluster objects** are discovered from NetBox through a live
  `http_sd` bridge. This lane covers physical devices, SNMP gear, service endpoints,
  and other non-pod targets.

Both lanes are driven by the same catalog-level `monitoring:` block. The operator
does not define separate monitoring intent for "in-cluster" and "off-cluster"; the
lanes are an implementation detail of how the same contract is realized.

**3. The monitoring contract schema is fixed as follows.**

The catalog `monitoring:` block is the canonical declaration. It is intentionally
small and explicit:

```yaml
monitoring:
  scrape:
    enabled: true
    metrics_port: 8080
    metrics_path: /metrics
    scheme: http        # optional; default http, set https only for TLS-only targets
  probe:
    enabled: false
    probe_module: http_2xx
  snmp:
    enabled: false
    snmp_module: if_mib
```

Rules:

- `monitoring.scrape.enabled` enables the in-cluster scrape lane.
- `monitoring.scrape.metrics_port` is required when scrape is enabled.
- `monitoring.scrape.metrics_path` defaults to `/metrics` unless the catalog entry
  overrides it.
- `monitoring.scrape.scheme` is optional and defaults to `http`; set `https` only for
  TLS-only scrape targets (maps to `prometheus.io/scheme`). No NetBox custom field is
  needed — the launcher derives the annotation directly from the catalog block.
- `monitoring.probe.enabled` enables blackbox-style probing through the adapter.
- `monitoring.probe.probe_module` is required when probe is enabled.
- `monitoring.snmp.enabled` enables SNMP discovery through the adapter.
- `monitoring.snmp.snmp_module` is required when SNMP is enabled.

The schema is additive rather than polymorphic. A catalog entry may enable one, two,
or all three lanes. A lane that is disabled is absent from the adapter output.

The custom-field definitions are fixed and typed as follows:

| Contract field | NetBox custom field | Type | Default / choice set | Active when |
|---|---|---|---|---|
| `monitoring.scrape.metrics_port` | `metrics_port` | integer | required | `monitoring:scrape` tag and field are both present |
| `monitoring.scrape.metrics_path` | `metrics_path` | text | `/metrics` | `monitoring:scrape` tag and field are both present |
| `monitoring.probe.probe_module` | `probe_module` | text constrained by `dmf_blackbox_probe_modules` | `http_2xx`, `http_2xx_insecure`, `tcp_connect`, `icmp` | `monitoring:probe` tag and field are both present |
| `monitoring.snmp.snmp_module` | `snmp_module` | text constrained by `dmf_snmp_modules` | `if_mib` by default; values must match the deployed snmp-exporter modules for the `full` profile | `monitoring:snmp` tag and field are both present |

`dmf_monitoring_severities` is also seeded by WP1 for WP10 alerting, but it is not
part of the discovery contract and the adapter ignores it.

**4. NetBox stores the monitoring contract through a fixed tag and custom-field
taxonomy.**

The adapter and launcher logic use the following NetBox contract:

- `monitoring:scrape` means the object should be emitted on the scrape lane.
- `monitoring:probe` means the object should be emitted on the probe lane.
- `monitoring:snmp` means the object should be emitted on the SNMP lane.

The custom fields are fixed and map 1:1 to the catalog schema:

- `metrics_port`
- `metrics_path`
- `probe_module`
- `snmp_module`

The tags carry lane selection. The custom fields carry lane parameters. A monitoring
contract without the matching tag is not active, even if the custom field happens to
be populated.

`exposure:*` is a separate NetBox taxonomy defined by `netbox-sot` and consumed by
the adapter only for label derivation. Expected values include `exposure:internal`
and `exposure:public`.

**Round-trip mapping**

| Catalog field | NetBox field / tag | Kubernetes / Prometheus output |
|---|---|---|
| `monitoring.scrape.metrics_port` | `metrics_port` + `monitoring:scrape` | `prometheus.io/port` |
| `monitoring.scrape.metrics_path` | `metrics_path` + `monitoring:scrape` | `prometheus.io/path` |
| `monitoring.scrape.scheme` | derived from the workload / exposure; no NetBox field | `prometheus.io/scheme` (`http` by default; `https` only when explicitly required by the workload) |
| `monitoring.probe.probe_module` | `probe_module` + `monitoring:probe` | `__param_module` |
| `monitoring.snmp.snmp_module` | `snmp_module` + `monitoring:snmp` | `__param_module` |

**5. Kubernetes monitoring uses the standard `prometheus.io/*` conventions.**

For in-cluster workloads, the launcher stamps the standard scrape annotations on the
target Pod and/or Service selected by the workload pattern:

- `prometheus.io/scrape: "true"`
- `prometheus.io/port: "<metrics_port>"`
- `prometheus.io/path: "<metrics_path>"`
- `prometheus.io/scheme: "http"` unless the workload explicitly requires HTTPS

The launcher also preserves the normal `app.kubernetes.io/*` labels so the workload
remains discoverable and traceable, but the monitoring trigger itself is the
`prometheus.io/*` annotation set. No separate k8s monitoring label namespace is
introduced in this ADR.

Lane-level address contract:

| Lane | Adapter emits | Prometheus job contract |
|---|---|---|
| Scrape | `__address__ = <object primary_ip4.address or ipam.service host>:<metrics_port>` and `__metrics_path__ = metrics_path` | Direct scrape against the object target |
| Probe | `__address__ = <real target>` and `__param_module = probe_module` | WP5 relabels `__param_target <- __address__`, `__address__ <- blackbox service addr`, `instance <- original target` |
| SNMP | `__address__ = <device primary_ip4.address>` and `__param_module = snmp_module` | WP9 applies snmp-exporter indirection analogous to blackbox |

**6. The bridge is a standalone DMF PromSD service, not a NetBox plugin.**

The bridge is a small, own-built FastAPI service named `dmf-promsd`. It runs in the
monitoring namespace, holds a scoped NetBox read token, queries NetBox directly via
the stable REST API, and exposes Prometheus `http_sd` endpoints for the three lanes.
It is the canonical adapter between NetBox and Prometheus.

The adapter emits target groups for:

- `/sd/scrape`
- `/sd/probe`
- `/sd/snmp`

Rationale for the standalone service, versus the rejected
`netbox-plugin-prometheus-sd` approach:

- **Air-gap and source control:** the adapter can ride the existing image rail and
  release process without requiring a custom NetBox image or a new Python-package
  distribution path.
- **Version compatibility:** the adapter depends on the stable NetBox REST API, so
  NetBox upgrades do not require coupling to a third-party plugin compatibility
  matrix.
- **Mapping ownership:** the DMF platform owns the NetBox-to-target mapping and can
  encode the exact taxonomy above without waiting on external plugin behavior.

**7. The older bootstrap-time `file_sd` bridge is superseded.**

The Day-0 inventory and monitoring plan’s bootstrap-time `file_sd` bridge is now
superseded by this ADR. Bootstrap may still seed the initial state, but the canonical
bridge is live `http_sd` from `dmf-promsd`, not a one-time file export.

## Operator decisions

**1. Create a new component repo for `dmf-promsd`.**

The adapter is a first-class component and gets its own repository. It does not live
inside `dmf-cms` or `dmf-infra`. The repo is created on `main`, follows the same
release discipline as the other DMF component repos, and owns the adapter service,
its tests, its image build, and its release artifacts.

**2. Use a fixed cache cadence with a stable `http_sd` contract and an upgrade path.**

Prometheus polls the adapter on `refresh_interval: 30s`. The adapter serves targets
from an in-memory cache refreshed on its own approximately `45s` timer so NetBox is
queried at a fixed low rate regardless of Prometheus replica count, matching the
`nb_inventory` cache-timeout pattern. That gives a worst-case churn latency of
roughly `75s` from NetBox change to scraped target visibility. NetBox webhook-driven
cache invalidation is deferred.

The scaling path is fixed and non-breaking for the `http_sd` contract:

1. **v1** — full-snapshot poll, as planned here.
2. **v1.5** — delta sweeps using `?last_updated__gte=<since>` plus occasional full
   sweeps to catch deletes.
3. **v2** — HMAC-verified webhooks plus a slow 5-15 minute full resync.

Upgrade triggers are operational, not architectural: NetBox list p95 rising, sweep
duration approaching the refresh interval, payloads growing into the tens of MB, or
a need for sub-10-second churn detection. The `/sd/*` contract remains stable across
all three phases.

**3. Do not extend `dmf-catalog-svc` permissions for this ADR.**

WP1 pre-creates the monitoring tags and custom-field definitions at bootstrap, so
the launcher only references them. The existing `ipam.service` `change` permission
and `extras.tag` `view` permission are sufficient for the monitoring contract as
defined here. A grant bump is needed only if WP6 chooses to stamp monitoring metadata
directly onto `dcim.device` via the catalog writer; external devices are stamped by
`nmos-cpp` / born-inventory under different writers today. Reconfirm in WP6 and
bump ADR-0032 only if that case actually appears.

## Consequences

- **Positive** — Monitoring becomes declarative and facility-driven instead of
  being a frozen scrape list.
- **Positive** — NetBox remains the single source of truth for what exists and
  should be observed, while Kubernetes stays responsible for in-cluster pod
  discovery.
- **Positive** — The contract is explicit enough for downstream implementation work
  to proceed without new architecture decisions.
- **Positive** — The adapter can be versioned, tested, and released independently of
  NetBox.
- **Positive** — The `/sd/*` contract stays stable while the adapter’s internal
  caching strategy evolves, so Prometheus wiring does not need to change as the
  implementation matures.
- **Negative** — There is one more component to build and operate.
- **Negative** — The platform now has a deliberate split between scrape, probe, and
  SNMP discovery paths, which is more to wire than a single discovery source.
- **Neutral** — The old bootstrap-time `file_sd` approach remains documented as
  historical context, but it is no longer canonical.

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

- [ADR-0010](0010-run-playbook-as-sanctioned-entry.md) — deploy/verify work packages
  and live checks run through the sanctioned wrapper.
- [ADR-0013](0013-media-function-catalog-model.md) for the catalog definition /
  runtime-record split that this monitoring contract extends.
- [ADR-0023](0023-internal-service-dns-for-cross-app-wiring.md) for the internal
  service-DNS posture used by cross-app plumbing inside the cluster.
- [ADR-0028](0028-identity-and-authority-chain.md) — the adapter holds a scoped
  NetBox read token under the machine-identity model.
- [ADR-0027](0027-catalog-instance-vs-definition-separation.md) for the layering
  language that this ADR reuses while choosing NetBox + AWX over a custom operator.
- [ADR-0032](0032-catalog-launcher-scoped-netbox-writer.md) for the scoped NetBox
  writer model used when launchers stamp lifecycle and monitoring metadata.
- [ADR-0034](0034-internal-ansible-collection-source.md) for the air-gap /
  internal-source posture that the adapter release path must respect.
- [ADR-0037](0037-media-workloads-netbox-instance-inventory.md) for the decision
  that NetBox stores media-function instances and placement, not live flow state.

## Enforcement

The follow-on work packages must implement the contract exactly as written here.
Any implementation that changes the monitoring contract schema, introduces a second
contract shape, or reverts the bridge to a bootstrap-only file export should be
treated as an ADR violation and reviewed against this decision first.

---

## Amendment A (2026-06-04): probe / scrape targets via cluster service DNS

**Status:** Accepted. Amends §3, §4, and the §5 lane-level address contract.

### Problem (found in the first live e2e)

The original §5 "Probe" row said the adapter emits `__address__ = <real target>` but
never defined how a *service* yields a target. In practice a NetBox `ipam.Service`
registered by born-inventory (and, by extension, by the catalog launcher) carries a
name, ports, a parent device, and the monitoring tags/fields — **but no usable
address**: `ipaddresses` is empty, and every platform app sits behind one shared
Traefik ingress on `LB-IP:443`, differentiated only by Host/path. So the adapter
fetched all tagged services but emitted **zero** probe/scrape targets (no
`__address__` to compose). Pod IPs are unusable anyway — they churn on reschedule.

### Decision

**The probe and scrape targets for in-cluster objects are the object's stable
cluster Service DNS name, composed by the adapter from identity recorded in NetBox —
never a pod or ingress IP.** This applies uniformly to born-inventoried platform
apps and to dynamically deployed catalog/media-function services.

1. **Record the stable cluster identity, not an IP.** Add three custom fields to the
   contract (typed, optional, stamped by whoever deploys the object):

   | Custom field | Type | Meaning |
   |---|---|---|
   | `cluster_service` | text | the Kubernetes `Service` name |
   | `cluster_namespace` | text | the Kubernetes namespace |
   | `cluster_port` | integer | the in-cluster Service port to probe (the app's service port, which is **not** necessarily the ingress `:443` recorded in `ipam.service.ports`) |

   A Kubernetes Service's DNS name (`<svc>.<ns>.svc.cluster.local`) and ClusterIP are
   **stable for the Service's lifetime** and survive pod rescheduling; only the pods
   behind it churn. So the adapter never needs to discover or track an IP — the
   target is a deterministic function of `cluster_service` + `cluster_namespace`.

2. **The deployer is the bridge.** The agent that *creates* the Kubernetes Service is
   the one thing that holds both the cluster reality and the NetBox record, so it
   stamps `cluster_service`/`cluster_namespace`/`cluster_port` at registration time,
   in the same lifecycle step it already stamps the monitoring tags:
   - **born-inventory** (platform apps) — knows each app's Service name/ns/port;
   - **catalog launcher** (dynamic media functions) — knows the Service it just
     created (ADR-0037 instance inventory).
   No separate IP↔service reconciler is needed.

3. **Adapter composition (replaces the §5 Probe / Scrape `__address__` derivation for
   in-cluster objects).** Let `host = <cluster_service>.<cluster_namespace>.svc.cluster.local`:
   - **Probe:** `__address__ = host:<cluster_port>`; the request is plain internal
     **HTTP** (ADR-0023). `__param_module = probe_module` as before. WP5's blackbox
     indirection relabel is unchanged.
   - **Scrape:** `__address__ = host:<metrics_port>`, `__metrics_path__ = metrics_path`.
   - **Precedence / fallback:** if `cluster_service` + `cluster_namespace` are present,
     the adapter uses the svc-DNS form. Otherwise it falls back to
     `primary_ip4.address` — which remains correct for **external / off-cluster
     devices** and the **SNMP lane** (physical gear that legitimately has an IP and no
     cluster Service).

### Consequences / notes

- Fits the existing **ADR-0023** internal-svc-DNS-over-plain-HTTP posture exactly: no
  ingress Host/path juggling, no TLS/CA-in-pod problem, no shared-LB-IP ambiguity.
  The probe answers "is the Service responding," which is the right health signal.
- `exposure:public` objects *may* later warrant an **additional** external-URL probe
  (does the ingress actually serve it end-to-end), composed from `exposure:*` +
  `external_base_url`. That is an optional second probe and is **deferred**; the
  internal svc-DNS probe is the robust baseline and the default.
- Work-package impact: WP1 (netbox-sot) seeds the three custom fields; WP6 (catalog
  launcher) and WP7 (born-inventory) stamp them; WP3 (dmf-promsd) implements the
  composition + fallback. The `/sd/*` http_sd output contract is unchanged.

---

## Amendment B (2026-07-03): `probe_path` probe-lane URL path

**Status:** Accepted. Amends §3, §4, and the Amendment A adapter composition.

### Problem

The probe lane composes a host:port target (Amendment A) and selects a blackbox
module (`probe_module`), but has no way to express a URL path. Some targets are
only meaningfully probeable on a specific path — the canonical case is Loki, whose
root returns non-2xx by design while its health contract is `GET /ready` on the
HTTP port. Blackbox modules cannot carry a path (the http prober takes the path
from the *target*), and `metrics_path` is scrape-lane-only by §3. Without a
path field the only workarounds are wrong ones: a public ingress detour for an
internal health check, or `tcp_connect` (port-open ≠ ready).

### Decision

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

The blackbox http prober accepts a schemeless full-URL target, and the existing
probe-job relabelling (`__param_target <- __address__`) forwards it unchanged —
so this amendment changes only the adapter's target composition, not the
Prometheus job contract or the `/sd/*` output shape.

**The `dmf_blackbox_probe_modules` choice set (§3) additionally gains
`http_2xx_302`** — an http prober with `follow_redirects: false` and
`valid_status_codes: [200, 301, 302, 303, 307, 308]`, for targets whose healthy
root response is a redirect that must not be dereferenced (canonical case:
Grafana's `/` → `/login` behind an OAuth auto-login chain to a local-CA URL).
As everywhere in §3, the choice set must stay lock-step with the deployed
blackbox-exporter module list.

### Consequences / notes

- The catalog `monitoring.probe` block gains an optional `probe_path` key,
  mapping 1:1 to the custom field, consistent with §3's additive-schema rule.
- Stamping follows Amendment A's "the deployer is the bridge" rule: born-inventory
  (platform apps) and the catalog launcher stamp `probe_path` alongside the other
  monitoring fields, gated on `monitoring:probe`.
- Work-package impact (monitoring close-out plan, 2026-07-02): netbox-sot seeds
  the field; born-inventory stamps it (`loki → /ready`); dmf-promsd implements
  the normalization + conditional append.
