# DMF Inventory Ownership and Bootstrap Boundary Plan

## 1. Purpose

This document defines how the DMF bootstrap system is supposed to work now
that the platform has reached the point where inventory must be treated as a
first-class, fully modeled artifact.

The goal is simple:

- all environment inventory lives in `dmf-env`
- all generic bootstrap logic lives in `dmf-infra`
- the live deployed environment is represented explicitly in NetBox
- the bootstrap workflow creates or reconciles that inventory as part of the
  deployment path, not as an afterthought

This document is also the boundary contract for future media environments:
the day-0 operator platform is one inventory plane, and later media
environments are another.

## 2. Repository Boundary

### 2.1 `dmf-env` owns environment truth

`dmf-env` is the home for all environment-specific data:

- Resource Profile manifests
- rendered Ansible inventory
- environment-scoped `group_vars`
- environment-specific secret metadata
- provider-specific task includes
- local wrappers for playbook and OpenTofu execution
- Terraform/OpenTofu state and Layer-1 provisioning

If a value changes because the environment changes, it belongs here.

### 2.2 `dmf-infra` owns generic execution logic

`dmf-infra` should contain only reusable bootstrap logic:

- roles
- playbooks
- charts
- generic docs
- generic example inventory templates

It should not be the authoritative home for any live environment inventory.

### 2.3 Example inventory in infra is only a template

The example inventory in `dmf-infra` is acceptable only as a placeholder
contract for structure and variable names.

It must not be treated as the source of truth for a real environment.

## 3. Current Bootstrap Shape

The current orchestration path is already close to the desired model.

### 3.1 Entry points

In `dmf-infra/k3s-lab-bootstrap`:

- `site.yml` imports the provisioning lifecycle
- `lifecycle-provision.yml` walks the stack bottom-up
- `lifecycle-operate.yml` runs read-only verification and operate-time checks
- `lifecycle-finalise.yml` handles teardown and reverse-order cleanup

### 3.2 Lifecycle structure

The provision path is organized as:

1. Host platform
2. Container platform
3. Security vertical
4. Monitoring vertical
5. Application and UI layer
6. Integration glue and SoT wiring

That is the right shape for a born-inventoried system because the platform
layers are established before app registration and reconciliation runs.

### 3.3 Inventory consumption model

The playbooks already assume the inventory is external to the infra repo:

- hostnames and IPs come from inventory
- cluster role flags come from inventory
- provider-specific ingress and firewall tasks are injected from the env repo
- secret metadata is supplied by the env repo
- app hostnames and domain values come from the env repo

That means the existing bootstrap architecture already expects
`dmf-env` to be the inventory authority.

## 4. What The Bootstrap Playbooks Actually Need

This is the practical inventory surface the bootstrap stack consumes.

### 4.1 Layer 1 and host bootstrap

The host and cluster bootstrap path needs:

- node names
- public IPs
- private node IPs
- SSH user
- control-plane membership
- private interface name
- provider-specific firewall or CCM wiring
- cluster token and SSH key references

### 4.2 Layer 3 and platform services

The container-platform playbooks need:

- cluster domain
- ingress mode
- hostnames for public and private services
- TLS issuer and DNS provider settings
- storage class and replica settings
- private lane settings

### 4.3 Vertical security and orchestration

Security and orchestration need:

- OpenBao endpoint and key metadata
- ESO settings
- Authentik hostnames and bootstrap references
- break-glass identity wiring

### 4.4 Monitoring and control

Monitoring and control need:

- Prometheus and Alertmanager configuration
- blackbox probe targets
- SNMP exporter inputs if network gear is present
- NetBox registration hooks
- AWX inventory source configuration
- alert receiver metadata

### 4.5 Application layer

The application layer needs:

- one hostname per exposed app
- app exposure mode
- namespace and storage settings
- admin secret references
- app-specific SSO settings

## 5. Existing Repo Structure To Preserve

### 5.1 In `dmf-env`

The current model is the right direction:

- `manifests/<env>.yaml` is the canonical Resource Profile
- `inventories/<env>/hosts.ini` is the rendered host inventory
- `inventories/<env>/group_vars/all/*.yml` holds environment values
- `tasks/` holds provider-specific and environment-specific task files
- `terraform/` owns Layer-1 provisioning and inventory rendering
- `bin/` owns wrappers that inject secrets and run playbooks

### 5.2 In `dmf-infra`

The infra repo should stay generic:

- `k3s-lab-bootstrap/site.yml`
- `lifecycle-*.yml`
- `playbooks/*`
- `roles/*`
- `charts/*`
- docs that describe patterns rather than live environment values

## 6. Detailed Playbook Analysis

### 6.1 `site.yml`

This is a thin top-level orchestrator.

It should not own inventory policy. It just stitches together the lifecycle
entry points.

### 6.2 `lifecycle-provision.yml`

This file is the main bootstrap chain.

Its current shape is good because it:

- starts with host validation and hardening
- brings up k3s before app workloads
- installs ingress, TLS, storage, and registry support
- installs security and orchestration verticals
- installs monitoring before or alongside app layers
- runs app registration and SoT wiring after the platform exists

This sequencing is exactly what a born-inventoried environment needs.

### 6.3 `lifecycle-operate.yml`

Operate should stay read-only.

Its role is to prove:

- the platform exists
- the inventory matches reality
- OIDC and app access still work
- monitoring and reconciliation are healthy

### 6.4 `lifecycle-finalise.yml`

Finalise is teardown only.

It should never become a second provisioning path.

### 6.5 Playbook groups

The current playbook groups are sensible:

- `200-baseline.yml`
- `210-harden.yml`
- `300-k3s.yml`
- `310-ingress-public.yml`
- `311-ingress-private.yml`
- `320-cert-manager.yml`
- `321-tailscale.yml`
- `330-longhorn.yml`
- `331-registry-zot.yml`
- `100-openbao.yml`
- `100-eso.yml`
- `110-authentik.yml`
- `100-prometheus.yml`
- `110-loki.yml`
- `120-grafana.yml`
- `130-promtail.yml`
- `140-librenms.yml`
- `600-landing-page.yml`
- `610-netbox.yml`
- `620-forgejo.yml`
- `640-awx.yml`
- `650-dmf-cms.yml`
- `691-netbox-sot.yml`
- `692-forgejo-bootstrap.yml`
- `693-awx-integration.yml`

This is already a coherent deployment ladder. The missing piece is inventory
discipline, not playbook topology.

## 7. Inventory That Must Stay In `dmf-env`

For the current DMF environment, the following belong only in the env repo:

- node IP addresses
- private network names and CIDRs
- provider tokens
- DNS zone and record settings
- cluster domain and hostnames
- ingress provider selection
- firewall rules and allowlists
- storage and replica settings
- secret references and bootstrap metadata
- monitoring receiver endpoints
- app exposure model
- NetBox and AWX integration values

Any future environment must get the same treatment:
one manifest, one inventory tree, one set of env-specific task includes.

## 8. Survey Scope For The Current Environment

The survey that follows this plan should collect the live environment in this
order:

1. Hetzner provider inventory
2. Debian host inventory
3. k3s cluster inventory
4. core platform service inventory
5. monitoring and probe inventory
6. NetBox reconciliation
7. day-0 versus media boundary mapping

### 8.1 Hetzner

Capture:

- project/account
- servers
- public IPs
- private network
- load balancer
- firewall
- DNS-managed records if any

### 8.2 Debian

Capture:

- hostname
- OS version
- kernel version
- NICs
- management IPs
- admin user
- SSH access path

### 8.3 k3s

Capture:

- control-plane membership
- worker membership
- node labels and taints
- ingress mode
- storage backend
- service exposure model

### 8.4 Services and monitoring

Capture:

- platform apps
- hostnames
- namespaces
- metrics endpoints
- probes
- alert routes

## 9. Day-0 Versus Media Boundary

### 9.1 Day-0 environment

Day-0 includes the platform required to bring the DMF facility online:

- the providers and hosts
- k3s
- ingress
- TLS
- storage
- secrets
- NetBox
- AWX
- monitoring
- core apps
- integration glue

### 9.2 Media environments

Media environments are anything that sits on top of the platform and is not
part of the base operator footprint:

- flow domains
- media functions
- NMOS and 2110 components
- media-specific exporters
- production-specific topology

### 9.3 Boundary rule

Media environments may refer to day-0 services, but they must not share the
same inventory object tree or naming assumptions unless explicitly modeled as
dependencies.

## 10. Recommended Implementation Policy

### 10.1 Canonical source

The canonical environment contract should be:

`manifest -> rendered inventory -> playbooks -> NetBox reconciliation`

### 10.2 Inventory generation

For the current environment, rendered inventory should come from the manifest
and/or provisioning state, then be written back into `dmf-env`.

### 10.3 Reconciliation

After deploy, the bootstrap system should:

- compare rendered inventory to live state
- register missing objects in NetBox
- flag discrepancies for review

### 10.4 Future media expansion

When media layers are added, they should extend the model through separate
environment manifests or clearly namespaced object groups, not by polluting the
day-0 environment tree.

### 10.5 End-of-bootstrap execution point

The actual bootstrap chain should end with a dedicated born-inventory playbook
after NetBox SoT and AWX integration complete.

Current implementation slot:

- `dmf-infra/k3s-lab-bootstrap/playbooks/694-born-inventory.yml`

That playbook must run on every new cluster deployment so the live environment
is surveyed and registered before bootstrap is considered complete.

## 11. Acceptance Criteria

This work is complete when:

- the live DMF environment can be reconstructed from `dmf-env`
- no real environment inventory is required in `dmf-infra`
- the bootstrap playbooks consume only env-owned inventory and secrets
- the day-0 platform is fully represented in NetBox
- the later media boundary is explicit and enforceable
