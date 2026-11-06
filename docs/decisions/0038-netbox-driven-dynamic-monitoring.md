# ADR-0038: NetBox-driven dynamic monitoring with a standalone PromSD adapter

**Status:** Accepted
**Date:** 2026-06-04
**Deciders:** @<handle>, planning session with Claude (2026-06-04)
**Touches:** [ADR-0010](0010-run-playbook-as-sanctioned-entry.md) (sanctioned playbook entry). [ADR-0013](0013-media-function-catalog-model.md) (catalog model). [ADR-0023](0023-internal-service-dns-for-cross-app-wiring.md) (in-cluster HTTP wiring). [ADR-0027](0027-catalog-instance-vs-definition-separation.md) (instance-layer framing). [ADR-0028](0028-identity-and-authority-chain.md) (identity / scoped-token custody). [ADR-0032](0032-catalog-launcher-scoped-netbox-writer.md) (scoped NetBox writer). [ADR-0034](0034-internal-ansible-collection-source.md) (air-gap/runtime source posture). [ADR-0037](0037-media-workloads-netbox-instance-inventory.md) (NetBox instance inventory).

## Context

Monitoring targets were a static, chart-default scrape list. A dynamic media facility needs targets that attach and detach as devices, services, and media functions change. NetBox is already the operational source of truth (ADR-0037, ADR-0013). This ADR defines one declarative contract that drives monitoring from NetBox without a human re-running a playbook.

## Decision

**1. NetBox is the single source of truth for monitoring intent.**

A catalog entry declares what to observe, NetBox stores the live facility record, and Prometheus reconciles its targets against both NetBox and Kubernetes state. Monitoring is no longer a static scrape-config list.

**2. Discovery uses two lanes, but one contract.**

- **In-cluster workloads** are discovered by Prometheus Kubernetes service discovery. This lane stays annotation-driven and self-healing.
- **External or off-cluster objects** (physical devices, SNMP gear, service endpoints, other non-pod targets) are discovered from NetBox through a live `http_sd` bridge.

Both lanes are driven by the same catalog-level `monitoring:` block. The operator does not define separate monitoring intent for in-cluster and off-cluster targets. The lanes are an implementation detail of how the same contract is realized.

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
    probe_path: /ready  # optional; probe lane only, http probers only
  snmp:
    enabled: false
    snmp_module: if_mib
```

Rules:

- `monitoring.scrape.enabled` enables the in-cluster scrape lane.
- `monitoring.scrape.metrics_port` is required when scrape is enabled.
- `monitoring.scrape.metrics_path` defaults to `/metrics` unless the catalog entry overrides it.
- `monitoring.scrape.scheme` is optional and defaults to `http`. Set `https` only for TLS-only scrape targets (maps to `prometheus.io/scheme`). No NetBox custom field is needed. The launcher derives the annotation directly from the catalog block.
- `monitoring.probe.enabled` enables blackbox-style probing through the adapter.
- `monitoring.probe.probe_module` is required when probe is enabled.
- `monitoring.probe.probe_path` is optional and maps 1:1 to the `probe_path` custom field.
- `monitoring.snmp.enabled` enables SNMP discovery through the adapter.
- `monitoring.snmp.snmp_module` is required when SNMP is enabled.

The schema is additive rather than polymorphic. A catalog entry may enable one, two, or all three lanes. A lane that is disabled is absent from the adapter output.

The custom-field definitions are fixed and typed as follows:

| Contract field | NetBox custom field | Type | Default / choice set | Active when |
|---|---|---|---|---|
| `monitoring.scrape.metrics_port` | `metrics_port` | integer | required | `monitoring:scrape` tag and field are both present |
| `monitoring.scrape.metrics_path` | `metrics_path` | text | `/metrics` | `monitoring:scrape` tag and field are both present |
| `monitoring.probe.probe_module` | `probe_module` | text constrained by `dmf_blackbox_probe_modules` | `http_2xx`, `http_2xx_insecure`, `http_2xx_302`, `tcp_connect`, `icmp` | `monitoring:probe` tag and field are both present |
| `monitoring.snmp.snmp_module` | `snmp_module` | text constrained by `dmf_snmp_modules` | `if_mib` by default; values must match the deployed snmp-exporter modules for the `full` profile | `monitoring:snmp` tag and field are both present |
| `monitoring.probe.probe_path` | `probe_path` (on `ipam.service`, `dcim.device`, `virtualization.virtualmachine`) | text | empty | `monitoring:probe` tag and field are both present |

`http_2xx_302` is an http prober with `follow_redirects: false` and `valid_status_codes: [200, 301, 302, 303, 307, 308]`, for targets whose healthy root response is a redirect that must not be dereferenced (canonical case: Grafana's `/` to `/login` behind an OAuth auto-login chain to a local-CA URL). The choice set must stay lock-step with the deployed blackbox-exporter module list.

`dmf_monitoring_severities` is also seeded by WP1 for WP10 alerting. It is not part of the discovery contract and the adapter ignores it.

**4. NetBox stores the monitoring contract through a fixed tag and custom-field taxonomy.**

- `monitoring:scrape` means the object should be emitted on the scrape lane.
- `monitoring:probe` means the object should be emitted on the probe lane.
- `monitoring:snmp` means the object should be emitted on the SNMP lane.

The custom fields are fixed and map 1:1 to the catalog schema: `metrics_port`, `metrics_path`, `probe_module`, `probe_path`, and `snmp_module`. Three further typed, optional custom fields record the cluster identity of an in-cluster object (see §5). The tags carry lane selection. The custom fields carry lane parameters. A monitoring contract without the matching tag is not active, even if the custom field is populated.

`exposure:*` is a separate NetBox taxonomy defined by `netbox-sot` and consumed by the adapter only for label derivation. Expected values include `exposure:internal` and `exposure:public`.

**Round-trip mapping**

| Catalog field | NetBox field / tag | Kubernetes / Prometheus output |
|---|---|---|
| `monitoring.scrape.metrics_port` | `metrics_port` + `monitoring:scrape` | `prometheus.io/port` |
| `monitoring.scrape.metrics_path` | `metrics_path` + `monitoring:scrape` | `prometheus.io/path` |
| `monitoring.scrape.scheme` | derived from the workload / exposure; no NetBox field | `prometheus.io/scheme` (`http` by default; `https` only when explicitly required by the workload) |
| `monitoring.probe.probe_module` | `probe_module` + `monitoring:probe` | `__param_module` |
| `monitoring.snmp.snmp_module` | `snmp_module` + `monitoring:snmp` | `__param_module` |
| `monitoring.probe.probe_path` | `probe_path` + `monitoring:probe` | appended to the probe target |

**`probe_path` semantics (probe lane only):**

1. `probe_path` participates only in the probe lane. The scrape lane keeps `metrics_path`, and the SNMP lane ignores `probe_path` entirely.
2. The adapter appends the path to the composed probe target **only when the selected `probe_module` is an http prober** (module name starting `http_`). For any other module (`tcp_connect`, `icmp`, and so on) the field is ignored and the target remains `host:port`.
3. The path is normalized to a single leading `/` (`ready` and `/ready` both yield `…:3100/ready`). Trailing content is preserved as given.
4. An empty or absent `probe_path` is a no-op.
5. The append applies to **both** address compositions: the svc-DNS form (`<svc>.<ns>.svc.cluster.local:<cluster_port><probe_path>`) and the `primary_ip4.address` fallback (`<ip>:<port><probe_path>`).

The blackbox http prober accepts a schemeless full-URL target, and the existing probe-job relabelling (`__param_target <- __address__`) forwards it unchanged. So `probe_path` changes only the adapter's target composition. It leaves the Prometheus job contract and the `/sd/*` output shape unchanged.

**5. Kubernetes monitoring uses the standard `prometheus.io/*` conventions.**

For in-cluster workloads, the launcher stamps these annotations on the target Pod and/or Service selected by the workload pattern:

- `prometheus.io/scrape: "true"`
- `prometheus.io/port: "<metrics_port>"`
- `prometheus.io/path: "<metrics_path>"`
- `prometheus.io/scheme: "http"` unless the workload explicitly requires HTTPS

The launcher also preserves the normal `app.kubernetes.io/*` labels so the workload remains discoverable and traceable. The monitoring trigger itself is the `prometheus.io/*` annotation set. This ADR introduces no separate k8s monitoring label namespace.

**In-cluster targets use the stable cluster Service DNS name.** The probe and scrape targets for in-cluster objects are the object's stable cluster Service DNS name, composed by the adapter from identity recorded in NetBox. They are never a pod or ingress IP. This applies uniformly to born-inventoried platform apps and to dynamically deployed catalog/media-function services. The contract records no IP for in-cluster objects.

Three custom fields record the cluster identity, typed, optional and stamped by whoever deploys the object:

| Custom field | Type | Meaning |
|---|---|---|
| `cluster_service` | text | the Kubernetes `Service` name |
| `cluster_namespace` | text | the Kubernetes namespace |
| `cluster_port` | integer | the in-cluster Service port to probe (the app's service port, which is **not** necessarily the ingress `:443` recorded in `ipam.service.ports`) |

A Kubernetes Service's DNS name (`<svc>.<ns>.svc.cluster.local`) and ClusterIP are **stable for the Service's lifetime** and survive pod rescheduling, so the adapter never needs to discover or track an IP. The target is a deterministic function of `cluster_service` + `cluster_namespace`.

**The deployer is the bridge.** The agent that *creates* the Kubernetes Service holds both the cluster reality and the NetBox record, so it stamps `cluster_service`, `cluster_namespace` and `cluster_port` at registration time, in the same lifecycle step in which it stamps the monitoring tags (and `probe_path`, gated on `monitoring:probe`). Born-inventory (platform apps) knows each app's Service name, namespace and port. The catalog launcher (dynamic media functions) knows the Service it created (ADR-0037 instance inventory). No separate IP-to-service reconciler is needed.

Lane-level address contract, with `host = <cluster_service>.<cluster_namespace>.svc.cluster.local`:

| Lane | Adapter emits | Prometheus job contract |
|---|---|---|
| Scrape | `__address__ = <host>:<metrics_port>` and `__metrics_path__ = metrics_path` | Direct scrape against the object target |
| Probe | `__address__ = <host>:<cluster_port>` (plus `probe_path` per §4) and `__param_module = probe_module`. The request is plain internal **HTTP** (ADR-0023). | WP5 relabels `__param_target <- __address__`, `__address__ <- blackbox service addr`, `instance <- original target` |
| SNMP | `__address__ = <device primary_ip4.address>` and `__param_module = snmp_module` | WP9 applies snmp-exporter indirection analogous to blackbox |

**Precedence / fallback:** if `cluster_service` + `cluster_namespace` are present, the adapter uses the svc-DNS form. Otherwise it falls back to `primary_ip4.address` (for the scrape lane, also the `ipam.service` host), which remains correct for **external / off-cluster devices** and the **SNMP lane** (physical gear that legitimately has an IP and no cluster Service).

This fits the ADR-0023 internal-svc-DNS-over-plain-HTTP posture: no ingress Host/path juggling, no TLS/CA-in-pod problem, no shared-LB-IP ambiguity. The probe answers "is the Service responding." An **additional** external-URL probe for `exposure:public` objects (does the ingress serve it end-to-end), composed from `exposure:*` + `external_base_url`, is optional and **deferred**. The internal svc-DNS probe is the baseline and the default.

**6. The bridge is a standalone DMF PromSD service, and the platform does not use a NetBox plugin.**

The bridge is a small, own-built FastAPI service named `dmf-promsd`. It runs in the monitoring namespace, holds a scoped NetBox read token, queries NetBox directly via the stable REST API, and exposes Prometheus `http_sd` endpoints `/sd/scrape`, `/sd/probe`, and `/sd/snmp`. It is the canonical adapter between NetBox and Prometheus.

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

**7. The older bootstrap-time `file_sd` bridge is superseded.**

The Day-0 inventory and monitoring plan's bootstrap-time `file_sd` bridge is superseded by this ADR. Bootstrap may still seed the initial state. The canonical bridge is live `http_sd` from `dmf-promsd`. A one-time file export is not the canonical bridge.

### Operator decisions

**1. Create a new component repo for `dmf-promsd`.**

The adapter is a first-class component with its own repository. It does not live inside `dmf-cms` or `dmf-infra`. The repo is created on `main`, follows the same release discipline as the other DMF component repos, and owns the adapter service, its tests, its image build, and its release artifacts.

**2. Use a fixed cache cadence with a stable `http_sd` contract and an upgrade path.**

Prometheus polls the adapter on `refresh_interval: 30s`. The adapter serves targets from an in-memory cache refreshed on its own approximately `45s` timer, so NetBox is queried at a fixed low rate regardless of Prometheus replica count. Worst-case churn latency is roughly `75s`. NetBox webhook-driven cache invalidation is deferred.

The scaling path is fixed and non-breaking for the `http_sd` contract: v1 is a full-snapshot poll, as planned here; v1.5 adds delta sweeps using `?last_updated__gte=<since>` plus occasional full sweeps to catch deletes; v2 adds HMAC-verified webhooks plus a slow 5-15 minute full resync. Upgrade triggers are operational. They are not architectural: NetBox list p95 rising, sweep duration approaching the refresh interval, payloads growing into the tens of MB, or a need for sub-10-second churn detection. The `/sd/*` contract remains stable across all three phases.

**3. Do not extend `dmf-catalog-svc` permissions for this ADR.**

WP1 pre-creates the monitoring tags and custom-field definitions at bootstrap, so the launcher only references them. The existing `ipam.service` `change` permission and `extras.tag` `view` permission are sufficient for the monitoring contract as defined here. A grant bump is needed only if WP6 chooses to stamp monitoring metadata directly onto `dcim.device` via the catalog writer; external devices are stamped by `nmos-cpp` / born-inventory under different writers today. Reconfirm in WP6 and bump ADR-0032 only if that case actually appears.

The amendment history (Amendment A, cluster Service DNS targets, and Amendment B, `probe_path`) is in the [archive record](../archive/decisions/0038-netbox-driven-dynamic-monitoring.md#amendment-history). This Decision is the current rule with both amendments applied.

## Consequences

- **Negative**: There is one more component to build and operate.
- **Negative**: The platform now has a deliberate split between scrape, probe, and SNMP discovery paths, which is more to wire than a single discovery source.
- **Positive**: The `/sd/*` contract stays stable while the adapter's internal caching strategy evolves, so Prometheus wiring does not need to change.
- **Neutral**: The old bootstrap-time `file_sd` approach remains documented as historical context. It is no longer canonical.

### Enforcement

`dmf-promsd/tests/test_sd.py` tests the adapter's target composition for the three lanes, including the Amendment A and Amendment B behavior. `dmf-runbooks/tests/tag-preservation.yml` checks that launchers preserve a `monitoring:probe` tag, which is related but is not a schema check. No check found in dmf-infra, dmf-media or dmf-runbooks tests asserts the catalog `monitoring:` schema or the NetBox custom-field seeding, so review enforces those. The follow-on work packages must implement the contract exactly as written here. Any implementation that changes the monitoring contract schema, introduces a second contract shape, or reverts the bridge to a bootstrap-only file export should be treated as an ADR violation and reviewed against this decision first.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0038-netbox-driven-dynamic-monitoring.md).
