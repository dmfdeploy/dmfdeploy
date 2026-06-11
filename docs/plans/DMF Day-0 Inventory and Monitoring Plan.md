---
status: superseded
date: 2026-05-11
superseded_by: "DMF Dynamic NetBox-Driven Monitoring Plan 2026-06-04.md"
---
# DMF Day-0 Inventory and Monitoring Plan
> **Superseded by** [DMF Dynamic NetBox-Driven Monitoring Plan 2026-06-04.md](DMF%20Dynamic%20NetBox-Driven%20Monitoring%20Plan%202026-06-04.md) — see frontmatter.

> **Vocabulary updated 2026-04-25** — playbook numbering and Phase / Layer
> language in this doc may reference the pre-EBU naming. Canonical layer /
> vertical / lifecycle map is `DMF EBU Mapping (2026-04-25).md`.

## 1. Purpose

This document turns the existing DMF source-of-truth doctrine into an
implementation plan for day-0 inventory and monitoring.

It answers the practical question:

After deployment, how does the platform already know what exists and already
have metrics, probes, and alerts wired, without depending on LibreNMS as the
core discovery engine?

The core answer is:

- the deployment workflow creates systems that are born inventoried
- NetBox becomes the authoritative operational source of truth
- Prometheus becomes the single metrics backend
- app roles publish monitoring and registration contracts as part of deploy
- optional discovery tools reconcile or propose into NetBox staging later

## 2. Existing Doctrine This Plan Extends

This plan extends the current DMF Platform Plan, especially:

- NetBox is authoritative
- discovery tools write to staging, not active
- LibreNMS is optional and modular, not base
- Prometheus SNMP Exporter is the metrics path for infra devices
- media discovery has its own lane (`nmos-cpp`)

The relevant current doctrine already exists in
`DMF Platform Plan.md` under:

- `§7a. Discovery architecture — three lanes`
- decision log items for NetBox, LibreNMS, and the three-lane discovery model

This document adds the missing deployment-time workflow and implementation
shape.

## 3. Core Principles

### 3.1 Born inventoried

If the deployment engine created it, the deployment engine should register it.

We should not wait for a later discovery pass to figure out:

- cluster nodes
- VIPs
- services
- app endpoints
- ingress FQDNs
- monitoring targets

### 3.2 NetBox is authoritative for active inventory

NetBox active-state objects are the approved inventory.

Discovery tools may create or update:

- staging objects
- proposed links
- proposed devices
- enrichment data

But they do not become authoritative by themselves.

### 3.3 Prometheus is the single metrics backend

Metrics should converge in Prometheus, not be split between multiple TSDBs.

That implies:

- Kubernetes workloads use Prometheus-native discovery and scrape patterns
- infra devices export metrics via `snmp_exporter`
- endpoint reachability uses `blackbox_exporter`
- optional discovery tools do not become the primary metrics system

### 3.4 Every app role owns its monitoring surface

An app role is not complete unless it defines:

- what inventory objects it should register
- what metrics endpoint it exposes
- what synthetic endpoints should be probed
- what alerts should exist for it

### 3.5 Discovery reconciles; it does not define reality

Brownfield and network discovery are still useful, but they are not the core
workflow for a freshly deployed stack.

## 4. Day-0 End State

After a successful deployment, the environment should already have:

### Inventory

- NetBox site / cluster / tenancy objects created as needed
- nodes registered
- interfaces and IPs registered where available
- service endpoints and FQDNs registered
- device or VM roles and tags applied
- monitoring ownership tags applied

### Monitoring

- Prometheus running
- Alertmanager running
- app metrics scraped
- external/public/private endpoints probed
- default alert routes loaded
- baseline alert rules loaded

### Automation

- AWX inventory can read from NetBox immediately
- post-deploy reconciliation can compare manifest intent vs live inventory vs
  monitoring status

## 5. System-of-Record Boundaries

| System | Owns |
|---|---|
| Deployment manifest | desired environment intent |
| NetBox active | approved inventory and operational topology |
| NetBox staging | proposed or discovered objects not yet promoted |
| Prometheus | runtime metrics and target health |
| Alertmanager | notification routing and deduplication |
| AWX inventory | execution-time inventory derived from NetBox |
| OpenBao | secret values and secret references |

Important boundary:

Prometheus is not a source of truth for what should exist.
NetBox is not a metrics store.
AWX is not the primary inventory source.

## 6. Recommended Established Workflow Patterns

The implementation should follow established upstream patterns instead of
inventing custom discovery logic where standard mechanisms already exist.

### Kubernetes-native monitoring

Use Prometheus Operator patterns:

- `ServiceMonitor`
- `PodMonitor`
- `Probe`
- `PrometheusRule`
- `AlertmanagerConfig`
- `ScrapeConfig`

These are the standard Kubernetes-native contracts for Prometheus target
discovery, probing, and alerting.

### External endpoint probing

Use `blackbox_exporter` for:

- HTTP/HTTPS reachability
- TLS sanity
- TCP liveness
- DNS checks where needed

### Network and device metrics

Use `snmp_exporter` for:

- switches
- routers
- firewalls
- UPSes
- access points
- other SNMP-capable devices

### Inventory-driven automation

Use NetBox as the inventory source for AWX via the NetBox inventory plugin,
instead of duplicating host inventory somewhere else.

### Optional brownfield discovery

Keep LibreNMS or Netdisco optional in `modules/infra-monitoring/`, and treat
them as topology/discovery aids that propose into NetBox staging.

They are not required to make the core cloud deployment complete.

## 7. Inventory Classes and Their Bootstrapping Path

| Asset class | Day-0 source | Registration path | Monitoring path |
|---|---|---|---|
| k3s nodes | deployment manifest + playbooks | direct NetBox registration | node/kube metrics |
| Kubernetes apps | app roles | direct NetBox registration | `ServiceMonitor` / `PodMonitor` |
| public/private FQDNs | manifest + ingress roles | direct NetBox service/FQDN registration | `Probe` via blackbox exporter |
| external VMs / appliances | manifest or approved import | direct NetBox registration | exporter scrape or blackbox probe |
| network devices | manual seed or later discovery | active if approved, staging if discovered | `snmp_exporter` |
| media devices | future media workflow | NetBox media plugin | media exporters + Prometheus |

## 8. What Replaces LibreNMS-as-core

LibreNMS was originally filling too many roles at once:

- discovery
- topology view
- device inventory
- alerting
- metrics

That is too much responsibility for the DMF control plane, especially for cloud
and flypack lanes.

The replacement is a split model:

- NetBox for inventory
- Prometheus for metrics
- Alertmanager for alerting
- blackbox exporter for endpoint probes
- snmp_exporter for network-device metrics
- optional LibreNMS or Netdisco for topology discovery only

This is the cleaner and more portable architecture.

## 9. Day-0 Cloud Workflow

This is the desired sequence for a normal cloud deployment.

### Step 1: deploy the cluster and core stack

Deploy:

- k3s
- ingress
- TLS
- storage
- OpenBao / ESO path as required
- NetBox
- Prometheus / Alertmanager / Grafana / Loki as chosen
- operator apps

### Step 2: register foundational inventory into NetBox

Register directly from known deployment facts:

- cluster name
- nodes
- interfaces
- node IPs
- load balancer VIPs
- ingress hostnames
- app services
- role tags

### Step 3: create monitoring resources for the deployed apps

For each app:

- create `ServiceMonitor` or `PodMonitor`
- create `Probe` objects for ingress URLs
- create `PrometheusRule` alerts
- attach standard labels for ownership and severity

### Step 4: create external-target monitoring definitions

From the manifest or approved NetBox inventory:

- generate SNMP targets
- generate blackbox targets
- generate any required static scrape targets

### Step 5: verify

Deployment is not complete until:

- NetBox contains the expected active objects
- Prometheus is scraping the expected targets
- probes exist for declared endpoints
- alerts are loaded

## 10. Day-0 Airgapped Flypack Workflow

The shape is similar, but the deployment-time assumptions differ.

### Same principles

- born inventoried
- NetBox authoritative
- Prometheus single TSDB
- app roles own their monitoring surfaces

### Different execution details

- no requirement for public DNS checks during deploy
- no dependency on external cloud callbacks
- registration is fully local to the flypack system
- external probe targets are limited to what exists in the local/private lane

For this lane, inventory and monitoring must be complete without requiring any
central service round-trip.

## 11. Day-0 Cloud Plus Online Flypacks Workflow

This lane produces two inventory planes:

- cloud-side inventory and monitoring
- flypack-side inventory and monitoring

The rule is:

each plane must be internally complete on day 0.

Do not assume the flypack becomes meaningful only after later synchronization.
It still needs its own:

- NetBox objects
- monitoring objects
- local-admin access model
- endpoint probes

## 12. Recommended Role Contract for App Roles

Every app role should publish a machine-readable contract describing what it
creates and how it should be monitored.

Recommended common fact name:

`dmf_app_contract`

Example shape:

```yaml
dmf_app_contract:
  app: grafana
  inventory:
    service_name: grafana
    fqdns:
      - grafana.dmf.example.com
    tags:
      - dmf
      - monitoring
      - operator-ui
  monitoring:
    servicemonitors:
      - name: grafana
        namespace: monitoring
        selector:
          app.kubernetes.io/name: grafana
        endpoints:
          - port: service
            path: /metrics
    probes:
      - name: grafana-ui
        module: http_2xx
        targets:
          - https://grafana.dmf.example.com/
    alerts:
      - name: grafana-unavailable
      - name: grafana-high-error-rate
```

That contract should be consumed by common roles rather than reimplemented in
every app.

## 13. Recommended Common Roles

These are planning targets, not yet implemented code.

### In `dmf-infra`

- `roles/common/netbox-register`
  - create or update active inventory objects in NetBox from known deployment
    facts
- `roles/common/dmf-app-register`
  - consume `dmf_app_contract` and invoke `netbox-register`
- `roles/common/dmf-monitoring-contract`
  - consume `dmf_app_contract` and emit monitoring resources
- `roles/base/monitoring-core`
  - deploy Prometheus Operator stack, Alertmanager baseline, blackbox exporter
- `roles/modules/infra-monitoring/prometheus-snmp-exporter`
  - deploy and configure SNMP exporter
- `roles/modules/infra-monitoring/netdisco`
  - optional staging discovery
- `roles/modules/infra-monitoring/librenms`
  - optional staging discovery, not required for base completeness

## 14. Recommended Playbook and Execution Shape

This plan does not require a total renumbering of playbooks, but it does
require a clearer registration/monitoring stage.

Recommended execution stages:

1. cluster baseline
2. ingress and TLS
3. storage and secrets
4. monitoring core
5. NetBox
6. operator apps
7. registration and monitoring reconciliation
8. verification

Possible future additions:

- `26-monitoring-core.yml`
- `33-deployment-register.yml`
- `34-monitoring-reconcile.yml`

If introducing new numbered playbooks creates too much churn, the same stages
can be embedded as post-tasks in the existing app playbooks, but the stage
boundaries must still exist conceptually.

## 15. External Target Generation Pattern

Some monitoring targets will not come from Kubernetes objects.

Use one of these two established patterns:

### Option A: Prometheus `file_sd`

Generate files from approved NetBox objects for:

- SNMP targets
- VM exporters
- external HTTP/TCP probe targets

This is simple and robust.

### Option B: Prometheus Operator `ScrapeConfig`

Use when the target definition must remain Kubernetes-native and managed as CRs.

Rule of thumb:

- start with `file_sd` for external targets because it is simpler
- use `ScrapeConfig` when strong Kubernetes-native management is clearly worth
  the added complexity

## 16. AWX Inventory Workflow

AWX should not have its own manually curated parallel inventory.

Recommended model:

- NetBox active inventory is the authoritative host/device dataset
- AWX uses the NetBox inventory plugin
- AWX job templates operate against NetBox-derived groups and metadata

Implication:

if day-0 registration is missing, AWX commissioning remains empty even when the
cluster itself is healthy.

This is why inventory bootstrap must be part of deployment completion, not an
optional later cleanup pass.

## 17. Reconciliation Workflow

After day-0 bootstrap, add a reconciliation loop.

The reconciler compares:

- deployment manifest intent
- NetBox active inventory
- NetBox staging discoveries
- Prometheus targets and probe status
- AWX inventory sync health

It should answer:

- what was declared but not registered
- what was registered but is not healthy
- what was discovered but not approved
- what is being monitored but no longer exists

## 18. Brownfield and Discovery Module Workflow

Optional modules still matter, but they come later.

### Infra discovery module

LibreNMS or Netdisco may:

- discover switches and topology
- enrich interface and LLDP data
- propose inventory into NetBox staging

They do not automatically become active inventory.

### Metrics path

Once approved, those devices become monitoring targets through:

- NetBox tags or statuses
- generated SNMP target lists
- blackbox endpoint target lists where applicable

## 19. Implementation Phases

### Phase 1: monitoring core baseline

Deliverables:

- Prometheus Operator baseline
- Alertmanager baseline
- blackbox exporter
- baseline rule and route conventions

### Phase 2: deployment-time NetBox registration

Deliverables:

- common registration role
- site/cluster/node/service/FQDN object mapping
- registration from existing core app playbooks

### Phase 3: app contracts

Deliverables:

- `dmf_app_contract` shape
- common role to consume it
- first app roles upgraded to publish it

Suggested first apps:

- NetBox
- Grafana
- Forgejo
- AWX

### Phase 4: external targets

Deliverables:

- SNMP target-generation path
- blackbox target-generation path
- chosen `file_sd` or `ScrapeConfig` model

### Phase 5: brownfield optional modules

Deliverables:

- Netdisco and/or LibreNMS staging workflow
- approval path into NetBox active

## 20. Acceptance Criteria

The architecture is in place when a fresh environment deploy completes with:

- NetBox populated with the deployed core assets
- AWX able to pull inventory from NetBox immediately
- Prometheus scraping app and cluster metrics immediately
- probes created for declared FQDNs immediately
- alert rules present for the deployed apps immediately
- no dependency on LibreNMS for the cloud lane to be considered complete

## 21. External Reference Patterns

These are the upstream workflows this plan intentionally follows:

- Prometheus Operator CRDs for scrape, probe, and alert definitions
- Prometheus `file_sd` for external/static target generation
- NetBox as the operational source of truth
- AWX inventory sourcing from NetBox
- blackbox exporter for endpoint probes
- snmp_exporter for network-device metrics

These are not optional inspiration items; they are the preferred implementation
paths unless a concrete incompatibility is found.

