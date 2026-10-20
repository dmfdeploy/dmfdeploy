# DMF Infrastructure Inventory Survey and Boundary Plan

## 1. Purpose

This document defines the inventory survey needed to make the deployed DMF
environment fully and correctly represented in NetBox.

The goal is not just to inventory applications. The goal is to survey the full
deployed stack so the authoritative record covers:

- Hetzner provider resources
- Debian host state
- k3s cluster nodes and topology
- platform services and app workloads
- monitoring and probe surfaces
- the boundary between day-0 platform infrastructure and later media
  environments

This is the operational side of the "born inventoried" doctrine.

## 2. Non-Negotiable Principles

### 2.1 NetBox is the active inventory source

Survey output must land in NetBox active objects where the environment is
already deployed and approved.

Discovery tools may enrich or propose, but they do not define reality.

### 2.2 Survey the actual deployed environment, not the intended one

The survey must capture live state:

- what Hetzner resources exist
- what nodes actually exist
- what IPs, hostnames, and interfaces are live
- what workloads and endpoints are currently exposed
- what monitoring surfaces are actually available

### 2.3 Day-0 and media environments are distinct planes

The day-0 platform environment and later media environments must not be mixed
into one inventory bucket.

They may share infrastructure concepts and tooling, but they have different
lifecycle rules, object ownership, and expansion paths.

## 3. Survey Scope

### 3.1 Hetzner layer

Capture provider-side facts such as:

- project or account reference
- regions and zones in use
- dedicated servers or cloud servers
- public IPs and floating IPs
- private networks
- load balancers
- firewalls
- DNS records and authoritative hostnames where they are provider-managed

### 3.2 Debian host layer

Capture host facts for each node or VM:

- hostname
- OS release
- kernel version
- SSH access method
- primary and secondary interfaces
- interface-to-network mapping
- management IPs
- system role
- time sync / NTP state
- storage attachments that matter operationally

### 3.3 k3s layer

Capture cluster facts:

- cluster name
- control-plane and worker membership
- node labels and taints
- cluster ingress mode
- internal service exposure model
- storage class or CSI backend
- namespace ownership for platform services

### 3.4 Application and platform service layer

Capture the deployed services that matter to operators:

- NetBox
- Prometheus
- Alertmanager
- Grafana
- Loki
- Authentik
- OpenBao
- ESO
- AWX
- Forgejo
- registry services
- console or CMS services

For each service, capture:

- service owner
- namespace or deployment location
- hostname or ingress path
- internal service endpoint
- exposed metrics endpoint
- synthetic probe target
- whether the service is day-0 or media-scope

### 3.5 Monitoring and probe layer

Capture the observability surface:

- Prometheus targets
- `ServiceMonitor` and `PodMonitor` sources
- `Probe` targets
- `blackbox_exporter` checks
- `snmp_exporter` targets if any network gear is present
- alerting routes and ownership tags

## 4. Boundary Between Day-0 and Media Environments

### 4.1 Day-0 environment

The day-0 environment is the infrastructure required to bring the DMF
platform online and keep it operational.

It includes:

- provider resources
- hosts and cluster nodes
- ingress and TLS
- secrets and control-plane services
- platform observability
- core operator applications

### 4.2 Later media environments

Later media environments are anything that depends on the platform but is not
part of the base platform itself.

Examples:

- media function clusters
- flow domain infrastructure
- NMOS / 2110 specific components
- media-specific exporters and probe models
- venue or production-specific inventory

### 4.3 Boundary rule

Day-0 inventory must be complete on its own.

Media environments may reference day-0 services, but they must be represented
as separate environment objects, not as undocumented extensions of the base
platform.

## 5. Recommended NetBox Modeling Approach

This is the recommended direction, not a final schema lock.

### 5.1 Use NetBox as the authoritative container for:

- sites or regions
- tenants or environment groups
- clusters
- devices or virtual machines
- interfaces
- IP addresses
- services
- tags
- custom fields for provider metadata where needed

### 5.2 Use staging only for uncertainty

If a resource was discovered but not yet approved, keep it in staging or an
equivalent proposed state.

Once the environment is deployed and verified, promote the object into active
inventory.

### 5.3 Keep provider facts visible

Provider-specific facts should not disappear into free-form notes.

If the survey finds a stable provider fact that operators will need later, it
should become a real object, field, or tag in NetBox.

## 6. Survey Order

The survey should run in this order:

1. manifest and repo review
2. Hetzner provider inventory
3. Debian host inventory
4. k3s node and cluster inventory
5. platform service inventory
6. monitoring and probe inventory
7. reconcile against NetBox active state
8. create gaps list for unresolved items

This order matters because later layers depend on earlier ones.

## 7. Expected Outputs

The survey should produce:

- a complete inventory checklist
- a NetBox object mapping by layer
- a list of missing or ambiguous facts
- a boundary map for day-0 versus media environments
- a reconciliation list for discovery-only or unresolved items

## 8. Completion Criteria

The survey is complete only when:

- the day-0 platform can be described end to end in NetBox
- the deployed Hetzner resources are visible in the inventory model
- the Debian hosts are identifiable by role, interface, and address
- the k3s cluster membership is explicit
- the platform apps and monitoring targets are represented
- the media boundary is documented so later expansion does not pollute the
  base environment model

