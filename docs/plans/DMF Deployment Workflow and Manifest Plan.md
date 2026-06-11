---
status: historical
date: 2026-05-11
---
# DMF Deployment Workflow and Manifest Plan

> **Vocabulary aligned 2026-04-25** with the EBU *Dynamic Media Facility Reference
> Architecture* White Paper V2.0. See `DMF EBU Mapping (2026-04-25).md` for the
> canonical layer / vertical / lifecycle map.

## 1. Purpose

This document turns the current DMF lane model into an implementation-grade
deployment workflow that any agent can follow.

It answers one core question:

How should a future deployment wizard hand configuration to the existing
Ansible/playbook system without turning the wizard into an unmaintainable blob
of infrastructure logic?

The answer is:

- the wizard collects and validates input
- the wizard produces a canonical Resource Profile manifest (EBU "Design"
  lifecycle stage output)
- the deployment engine renders environment-specific artifacts from that
  manifest
- Ansible executes the rollout across the relevant EBU layers and verticals
- post-deploy registration and monitoring bootstrap make the system "born
  inventoried" rather than retroactively discovered

This extends, but does not replace, the existing doctrine in
`DMF Platform Plan.md`:

- NetBox is authoritative SoT
- discovery tools propose into staging, never active by default
- Prometheus is the single metrics backend (vertical-monitoring)
- lane differences are profile differences, not separate codebases

## 2. Scope

This plan covers the deployment-control workflow for these lanes:

1. `cloud`
2. `airgapped-flypack`
3. `cloud-plus-online-flypacks`

It does not define the detailed UI itself. It defines the data model,
execution boundaries, and handoff contract between:

- future wizard or CMS
- `dmf-env`
- `dmf-infra`
- future `dmf-central`
- future post-deploy inventory and monitoring bootstrap

## 3. Non-Negotiable Design Rules

### 3.1 Wizard is not the deployer

The wizard must not become a second infrastructure engine.

Its responsibilities are:

- lane selection
- data collection
- secret intake
- validation
- Resource Profile manifest generation
- status reporting

It must not own:

- provider-specific imperative rollout logic
- application install logic
- infrastructure mutation logic beyond invoking the deployment engine

### 3.2 One canonical deployment artifact

Every environment must have one canonical non-secret manifest. In EBU terms
this is the **Resource Profile** — the "Design" lifecycle stage output that
declares compute, network, storage, and licence requirements together with
the target layer and vertical selections.

That manifest is the desired-state contract for the environment.

Everything else is derived:

- rendered inventory files
- playbook parameters
- post-deploy NetBox registration payloads
- monitoring target definitions (vertical-monitoring)

### 3.3 Secrets never live in the manifest repo

The manifest contains secret references, not raw secret values.

Secret values land in OpenBao (vertical-security) or another approved secrets
backend. The manifest only stores enough information to retrieve them during
deploy.

### 3.4 Lane choice changes validation and execution semantics

The three lanes share a common model, but `deploy` does not mean exactly the
same thing in each lane.

The lane controls:

- what inputs are required
- what validations must pass
- what playbooks are allowed to run
- whether the result is a live Cluster, a factory-seeded install image, or a
  cloud-plus-edge bundle

### 3.5 The system should be born inventoried

The deployment workflow must register what it creates as part of the same
transactional rollout process.

Discovery is a reconciliation aid, not the primary mechanism for learning what
exists.

## 4. Canonical Objects

### 4.1 Resource Profile manifest

The Resource Profile manifest is the primary non-secret source document for
one environment. It corresponds to the EBU "Design" lifecycle stage output:
it declares the target Hosts, Cluster shape, Container Platform parameters,
verticals to enable, and (eventually) Media Functions / Flow Domains.

Recommended home:

- repo: `dmf-env`
- path: `manifests/<environment>.yaml`

The manifest should be human-readable, diffable, and stable enough to review in
Git.

### 4.2 Rendered environment artifacts

These are generated from the Resource Profile manifest and written into the
normal inventory layout the existing playbooks already expect.

Recommended outputs:

- `inventories/<environment>/hosts.ini`
- `inventories/<environment>/group_vars/all/*.yml`
- `inventories/<environment>/group_vars/<group>/*.yml`

Rendered files are derived artifacts. The Resource Profile manifest remains
the higher-order truth for environment intent.

### 4.3 Secret references

The manifest must reference secrets by stable logical names, for example:

- `openbao:secret/infra/dns/hetzner#api_token`
- `openbao:secret/infra/cloud/hetzner#api_token`
- `openbao:secret/platform/authentik/bootstrap#admin_password`

### 4.4 Deployment run record

Each deploy should emit a run record that captures:

- manifest version or checksum
- environment name
- lane
- playbooks executed (by layer / vertical / lifecycle stage)
- start/end times
- success/failure
- post-deploy verification summary

The run record can live in the wizard backend later, but the deployment engine
must emit it in a machine-readable form from the beginning.

## 5. Recommended Manifest Shape

The exact schema can evolve, but every lane should share this minimum
skeleton. Field groupings map to EBU concepts as noted (the manifest is the
concrete realisation of the Resource Profile):

```yaml
apiVersion: dmf.<lan-host>/v1alpha1
kind: ResourceProfile
metadata:
  name: hetzner-arm-lab
  lane: cloud
  description: Hetzner ARM operator lab

spec:
  topology:                              # EBU Layer 2 (Host Platform) + Layer 3 (Container Platform)
    profile: hub-cluster-first
    kubernetes_distribution: k3s
    environment_name: hetzner-arm

  domain:                                # Layer 6 (Application & UI) hostnames
    cluster_domain: dmf.example.com
    public_base_url: https://dmf.example.com
    hosts:
      authentik: auth.dmf.example.com
      forgejo: forgejo.dmf.example.com
      grafana: grafana.dmf.example.com
      netbox: netbox.dmf.example.com
      awx: awx.dmf.example.com

  provider:                              # Layer 1 (Infrastructure) provider binding
    cloud:
      kind: hetzner
      region: fsn1
      tokens:
        cloud_api: openbao:secret/infra/cloud/hetzner#api_token
        dns_api: openbao:secret/infra/dns/hetzner#api_token

  network:                               # Layer 1 + Layer 3 networking
    ingress_model: public-plus-private
    private_lane:
      enabled: true
      wireguard:
        cidr: 10.77.77.0/24
        endpoint_node: k3s-node-01

  secrets:                               # vertical-security
    backend: openbao
    key_root: secret/platform/hetzner-arm

  apps:                                  # Layer 6 (Application & UI)
    landing_page: { enabled: true }
    authentik: { enabled: true }         # also vertical-security
    forgejo: { enabled: true }
    grafana: { enabled: true }           # also vertical-monitoring
    netbox: { enabled: true }
    awx: { enabled: true }

  monitoring:                            # vertical-monitoring
    strategy: born-inventoried
    netbox_registration: true
    prometheus_operator: true
    blackbox_probes: true
    snmp_exporter: false

  inventory:                             # vertical-control
    source_of_truth: netbox
    awx_inventory_plugin: netbox
```

Future extensions to the Resource Profile schema (tracked separately):

- **Flow Domains** (EBU §Media Exchange) — required once Layer 4 lands
- **Media Functions** (Layer 5) — declarative list of containerised media
  processing units
- **JT-DMF compliance markers** — industry alignment fields

## 6. Lane Semantics

### 6.1 Cloud

`deploy` means:

- validate cloud and DNS provider access
- render the environment inventory from the Resource Profile
- run the Cluster (Layer 2 + Layer 3) and Application (Layer 6) playbooks
  along with the relevant verticals (security, monitoring, orchestration)
- write resulting inventory objects into NetBox
- create monitoring objects (vertical-monitoring)
- verify endpoints and hand back operator access data

### 6.2 Airgapped flypack

`deploy` means:

- validate all required offline inputs exist before execution
- render a flypack-specific Resource Profile and environment inventory
- seed local secrets and local trust material (vertical-security)
- run the factory-stage lifecycle-provision playbooks against the build target
- generate the handoff bundle and recovery data
- verify the local system can operate with no external control-plane
  dependency

In this lane, "deploy" may happen in a factory/staging environment before
shipment rather than in the final field location.

### 6.3 Cloud plus online flypacks

`deploy` means two coordinated outputs:

- deploy or update the cloud-side environment
- generate or apply the flypack-side environment contracts and trust material

The workflow must make the boundary explicit. It is not one giant generic
"deploy everything everywhere" button.

## 7. Wizard Workflow

The wizard should drive this sequence.

### Step 1: select lane and profile

The user selects:

- `cloud`
- `airgapped-flypack`
- `cloud-plus-online-flypacks`

This determines the required schema.

### Step 2: collect common inputs

Collect data shared across all lanes:

- environment name
- operator/org name
- cluster domain
- primary app hostnames
- enabled apps and modules
- exposure model
- local-admin / break-glass identity policy

### Step 3: collect lane-specific inputs

Examples:

- cloud provider tokens
- DNS provider tokens
- node size/count
- LB strategy
- WireGuard peers
- offline update-pack signing keys
- flypack local domain or PKI mode

### Step 4: write secrets to the secrets backend

The wizard writes collected sensitive values to OpenBao (vertical-security)
first, then stores references into the draft Resource Profile manifest.

### Step 5: preflight validation

The wizard must validate before any playbook run starts.

Minimum validation categories:

- schema validity
- secret reference resolution
- provider credential validity
- DNS zone existence and writeability
- hostname uniqueness and lane compatibility
- cluster sizing and profile compatibility
- feature/lane compatibility
- bootstrap path prerequisites

### Step 6: freeze manifest

After validation passes:

- assign a Resource Profile manifest version
- persist the manifest
- generate a checksum
- mark the environment as ready-to-deploy

### Step 7: render environment artifacts

A renderer converts the Resource Profile manifest into the existing
`dmf-env` inventory shape.

This renderer is a separate concern from the wizard UI.

### Step 8: execute deployment

The deployment engine runs the relevant playbooks against the rendered
inventory. Execution is grouped by EBU layer / vertical / lifecycle stage:

1. Layer 2 — Host Platform (baseline, harden)
2. Layer 3 — Container Platform (k3s, ingress, TLS, storage)
3. vertical-security + vertical-orchestration (OpenBao, ESO)
4. vertical-monitoring (Prometheus, Loki, Grafana, Promtail)
5. vertical-security continued (Authentik)
6. Layer 6 — Application & UI (NetBox, Forgejo, AWX, dmf-cms, LibreNMS via
   vertical-monitoring)
7. Layer 6 — App integration glue (NetBox SoT, Forgejo bootstrap, AWX
   integration)
8. lifecycle-operate (full-stack verify)
9. lifecycle-finalise (teardown, reverse order — only when explicitly
   requested)

### Step 9: publish run results

The system emits:

- pass/fail
- executed playbooks (tagged by layer / vertical / lifecycle stage)
- resulting endpoints
- unresolved warnings
- run artifacts

## 8. Manifest -> Inventory -> Playbook Contract

Fresh agents must preserve this direction:

`Resource Profile manifest` -> `rendered inventory` -> `playbooks`

Not:

`playbook defaults` -> "whatever inventory happened to exist"

That means:

- inventory values should be explicit render targets
- app hostnames should not be inferred ad hoc inside roles when the manifest
  already knows them
- lane-critical choices should be rendered into inventory, not reconstructed at
  runtime from weak heuristics

## 9. Manifest Ownership by Repo

### `dmf-env`

Owns:

- environment Resource Profile manifests (EBU "Design" outputs)
- rendered inventory files
- environment-scoped non-secret values

Does not own:

- generic role logic
- embedded secret values

### `dmf-infra`

Owns:

- generic roles
- playbooks (organised by layer / vertical / lifecycle stage)
- render expectations
- validation contracts for app roles

Does not own:

- cloud-provider secret material
- environment-specific hostnames beyond examples and defaults

### `dmf-cms` future

Owns:

- wizard UI
- Resource Profile manifest authoring UX
- deployment-run orchestration UI
- validation/reporting UX

Does not replace:

- Ansible as the deployment engine
- NetBox as the SoT
- OpenBao as the secrets backend (vertical-security)

## 10. Preflight Validation Matrix

The wizard must fail fast before deployment on these classes of errors.

### Domain and ingress

- cluster domain is syntactically valid
- every declared host is unique
- public/private exposure choices match the lane
- DNS provider can manage the required zone

### Secrets

- all required secret references exist
- tokens have the permissions required by the chosen profile
- no unresolved placeholder values remain

### Infrastructure

- node count and sizing satisfy the selected stack profile
- required provider settings are present
- private-lane inputs exist if private ingress is enabled

### Application model

- app dependencies are satisfied
- disabled apps are not referenced by enabled integrations
- OIDC assumptions are only enabled where the role support exists

## 11. Recommended Implementation Stages

### Stage A: codify the Resource Profile manifest

Deliverables:

- Resource Profile schema
- manifest examples for all three lanes
- renderer from Resource Profile -> `dmf-env` inventory

### Stage B: codify validations

Deliverables:

- schema validation
- provider and DNS validators
- lane compatibility validators
- hostname and ingress validators

### Stage C: codify run orchestration

Deliverables:

- lifecycle-staged execution wrapper (`lifecycle-provision.yml`,
  `lifecycle-operate.yml`, `lifecycle-finalise.yml`)
- machine-readable run record
- failure and retry semantics

### Stage D: connect to inventory and monitoring bootstrap

Deliverables:

- post-deploy NetBox registration
- monitoring bootstrap from declared assets (vertical-monitoring)
- verification reports

## 12. Acceptance Criteria

This plan is implemented when:

- a fresh agent can create a new environment from a Resource Profile manifest
  without reverse-engineering hidden inventory assumptions
- the same logical environment can be rendered differently by lane without
  cloning the role codebase
- secrets are referenced, not copied into repo config
- deployment inputs are validated before playbooks start
- the deployment result includes inventory registration and monitoring setup
  (vertical-monitoring) as first-class outputs

## 13. Relationship to the Inventory and Monitoring Plan

This document defines the deployment-control workflow.

The companion doc
`DMF Day-0 Inventory and Monitoring Plan.md`
defines what must happen after the deploy engine creates infrastructure and
applications.
