# Catalog and execution — Canonical Digest

**Scope:** How media functions are catalogued, deployed, executed, and monitored.
**Canonical ADR(s):** [ADR-0013](../0013-media-function-catalog-model.md), [ADR-0025](../0025-ansible-in-cluster-pods-and-catalog-helm.md), [ADR-0038](../0038-netbox-driven-dynamic-monitoring.md)
**Last refreshed:** 2026-06-09

> This digest states the **current consolidated truth** for this topic so a reader
> does not have to reverse-engineer it from multiple partially-superseding ADRs.
> The numbered ADRs remain authoritative source; this digest points at them.

## Current truth

- Each catalog entry has a YAML manifest (committed to the source repo at `catalog/<key>.yaml`), a NetBox runtime record (tagged `lifecycle:bootstrapped` / `active`), a Configure playbook, and a Finalise playbook. dmf-cms joins YAML metadata with NetBox runtime tags. (ADR-0013 Decision)
- The catalog schema includes `provision.namespace` (required) as the single source of truth for the k8s namespace where the workload's Helm release deploys. (ADR-0013 Amendment 2026-05-12)
- Media catalog launchers (`media-*` AWX Job Templates) execute in-cluster via AWX-spawned Execution Environment pods, not by SSHing to a control node. The shared EE image is hosted in cluster-internal Zot. (ADR-0025 Decision)
- Catalog functions deploy as Helm charts. Function images and chart artifacts are published outside the cluster, then Stage 4b seeds them into the cluster-local Zot registry. (ADR-0025 Decision)
- AWX controller ServiceAccount needs target-namespace RBAC for pods (create/get/list/watch/delete), pods/log (get/list/watch), pods/exec (create), pods/attach (create). (ADR-0025 Decision)
- Catalog launchers use explicit `kubernetes.core.k8s_info` readiness checks rather than `helm wait: true`. (ADR-0025 Decision)
- NetBox is the single source of truth for monitoring intent. Monitoring is no longer a static scrape-config list; a catalog entry declares what should be observed, NetBox stores the live facility record, and Prometheus continuously reconciles its targets against both NetBox and Kubernetes state. (ADR-0038 Decision 1)
- Discovery uses two lanes (in-cluster via Kubernetes SD; external via NetBox `http_sd` bridge), both driven by the same catalog-level `monitoring:` block. (ADR-0038 Decision 2)
- The monitoring contract schema is fixed with `scrape`, `probe`, and `snmp` lanes, each with specific typed custom fields in NetBox: `metrics_port` (integer), `metrics_path` (text), `probe_module` (constrained choice), `snmp_module` (constrained choice). (ADR-0038 Decision 3)
- The bridge is a standalone DMF PromSD service (`dmf-promsd`), not a NetBox plugin. It runs in the monitoring namespace, queries NetBox via REST API, and exposes `/sd/scrape`, `/sd/probe`, `/sd/snmp` endpoints. (ADR-0038 Decision 6)
- Prometheus polls the adapter on `refresh_interval: 30s`; the adapter serves targets from an in-memory cache refreshed on its own ~45s timer, giving worst-case churn latency of ~75s. (ADR-0038 Operator decisions 2)
- For in-cluster objects, the probe and scrape targets are composed from stable cluster Service DNS names (`<svc>.<ns>.svc.cluster.local`), never pod or ingress IPs. (ADR-0038 Amendment A)
- The older bootstrap-time `file_sd` bridge is superseded by the live `http_sd` adapter. (ADR-0038 Decision 7)
- Media Workloads are represented across three stores: git catalog (definitions), NetBox (instances + placement + lifecycle), and k3s (actual runtime + scheduling). Flows stay runtime-only — never written to NetBox. (ADR-0037 Decision 1–2)
- AWX is the reconciler — extending the existing `nb_inventory` + `operate-catalog-drift.yml` loop, not a custom CRD + operator. (ADR-0037 Decision 4)

## History / context behind it

| ADR | Role today | Superseded / amended by |
|---|---|---|
| 0013 | Media function catalog model (YAML intent + NetBox runtime tag) | — |
| 0014 | AWX project layout — hybrid (launchers + mirrored source repos) | — |
| 0016 | AWX↔control-node SSH via cloud-init + OpenBao (Path A) | **Partially superseded by ADR-0025** (canonical for `media-*` JTs; still authoritative for AWX→infrastructure plays) |
| 0025 | Ansible in in-cluster pods + catalog functions as Helm charts | — |
| 0027 | Separate catalog-entry/installation/runtime-instance layers (CRD+operator proposed-deferred) | **Amended by ADR-0037** (instance layer in NetBox + AWX, not a CRD) |
| 0037 | Media Workloads — NetBox instance inventory, flows stay runtime-only | — |
| 0038 | NetBox-driven dynamic monitoring with standalone PromSD adapter | — |

## Open items in this cluster

- ADR-0027 (CRD + operator) remains Proposed-deferred; the installation/instance layer is now realised in NetBox + AWX per ADR-0037, so the CRD path is superseded for the current trajectory but the ADR remains as history. No forcing function to build a custom operator.
