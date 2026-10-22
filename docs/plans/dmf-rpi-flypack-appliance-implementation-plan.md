---
status: historical
date: 2026-05-13
---
# DMF RPi Flypack Appliance Implementation Plan - 2026-05-13

## Purpose

Define an implementation path for a **CMS-capable RPi flypack appliance** that
minimizes divergence from the existing DMF component repos.

Target hardware for the first prototype:

- Raspberry Pi 5, 16 GB RAM
- 1 TB NVMe
- wired Ethernet
- active cooling and stable PSU
- all container images prebuilt and seeded into local Zot
- future offline k3s agent nodes may join and pull only from local Zot

This is not a new canonical monorepo. It is a distribution/appliance shape that
consumes pinned releases from the existing repos.

## Fresh-Agent Preflight

Before implementing any part of this plan:

1. Read root `CLAUDE.md` and `AGENTS.md`.
2. Run `git fetch && git pull` in the umbrella repo.
3. Run `bin/generate-status.sh` and read `STATUS.md`.
4. Read the most recent file in `docs/handoffs/`.
5. Read `docs/decisions/INDEX.md`, then at minimum:
   - `0001-umbrella-as-docs-home.md`
   - `0002-two-repo-model.md`
   - `0003-ebu-v2-taxonomy.md`
   - `0004-experiment-phase-stance.md`
   - `0008-openbao-secrets-architecture.md`
   - `0010-run-playbook-as-sanctioned-entry.md`
   - `0013-media-function-catalog-model.md`
   - `0014-awx-project-layout.md`
   - `0016-awx-control-node-ssh-via-cloud-init-and-openbao.md`
   - `0020-deployment-scope-and-regulatory-posture.md` if still Proposed
6. Check `git status` in any component repo before touching it.
7. Do not inspect or edit `dmf-env` unless explicitly instructed by the
   operator; it is private/secrets-sensitive.

Known state at plan creation:

- The umbrella repo has unrelated local edits.
- `dmf-infra` and `dmf-env` have dirty/unpushed work.
- The plan below is umbrella-only context. Component implementation must start
  with fresh status checks.

## Canonical References

Architecture and scope:

- `docs/architecture/DMF Platform Plan.md`
  - Defines DMF as an IP media operations platform.
  - Warns that the full operator stack can require about 14-18 GB RAM before
    media workloads when naively run on one node.
  - Maps NetBox, Forgejo, AWX, CMS, monitoring, OpenBao, Authentik, and Zot
    into the EBU layer/vertical model.
- `dmf-infra/k3s-lab-bootstrap/docs/flypack-offline-lane.md`
  - Defines the flypack as a single self-contained k3s appliance.
  - Current profile default marks NetBox/AWX/Forgejo off. For a CMS-capable
    flypack this must become a different preset, not the primary product path.
- `docs/plans/DMF Console Initial Implementation Plan 2026-04-26.md`
  - States that the console is not an iframe aggregator.
  - NetBox is inventory/topology truth.
  - AWX executes workflows.
  - Forgejo carries reviewable config changes.
  - Authentik provides identity.
  - OpenBao protects secrets.
  - Prometheus/Alertmanager provide monitoring.

CMS implementation references:

- `dmf-cms/CLAUDE.md`
  - Current implementation stack is React + FastAPI BFF.
  - Consumes NetBox, AWX, Prometheus, and NMOS APIs.
- `dmf-cms/src/dmf_cms/settings.py`
  - Runtime settings include Authentik, AWX, NetBox, Prometheus, and Forgejo.
- `dmf-cms/src/dmf_cms/main.py`
  - AWX workflow endpoints list, launch, and poll jobs.
  - Admin health checks Authentik, AWX, NetBox, Prometheus.
  - Facility endpoints read NetBox.
  - Monitoring endpoints read Prometheus.
  - Changes endpoints read AWX and Forgejo.
  - Catalog endpoints join YAML catalog entries to NetBox lifecycle state and
    launch AWX deploy/teardown jobs.
- `dmf-cms/src/dmf_cms/catalog.py`
  - Catalog loader and NetBox lifecycle-tag join.

Infra implementation references:

- `dmf-infra/k3s-lab-bootstrap/roles/base/k3s/`
- `dmf-infra/k3s-lab-bootstrap/roles/base/ingress/`
- `dmf-infra/k3s-lab-bootstrap/roles/base/ingress-private/`
- `dmf-infra/k3s-lab-bootstrap/roles/base/cert-manager/`
- `dmf-infra/k3s-lab-bootstrap/roles/base/external-secrets/`
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/`
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/`
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/zot/`
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox/`
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx/`
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo/`
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/cms/`
- `dmf-infra/k3s-lab-bootstrap/roles/base/prometheus/`
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/loki/`
- `dmf-infra/k3s-lab-bootstrap/roles/base/grafana/`
- `dmf-runbooks/`
  - Path A AWX launchers and current NMOS runbook location.
- `dmf-media/catalog/`
  - Catalog metadata source for Layer 4/5 functions.

## Product Shape

The RPi appliance is a **single-node control appliance** with optional offline
agent-node expansion.

Keep on the RPi primary:

- k3s server/control plane
- local Zot registry
- OpenBao
- External Secrets Operator
- Authentik
- NetBox
- AWX
- Forgejo
- dmf-cms
- Prometheus/Alertmanager with reduced retention
- Grafana
- Loki/Promtail with reduced retention

Explicitly omit for v0:

- Longhorn
- cloud load balancers
- provider-specific roles such as Hetzner/Aliyun CCM
- ArgoCD
- LibreNMS
- managed-service callbacks
- automatic phone-home
- multi-node HA claims

Future joined nodes are initially **compute/edge nodes only**. Stateful platform
apps remain pinned to the RPi primary until a real distributed storage model is
chosen.

## Divergence Strategy

The appliance repo should consume upstream, not fork it.

Authoritative repos remain:

- `dmf-infra` for roles, playbooks, Helm rendering, bootstrap logic
- `dmf-cms` for the console app
- `dmf-runbooks` for AWX launcher playbooks
- `dmf-media` for catalog metadata and media-domain sources

Create a thin distribution repo, tentatively:

```text
dmf-flypack/
  manifest.yml
  manifest.lock.yml
  profiles/
    rpi5-16gb-1tb.yml
  bin/
    sync-sources
    render-profile
    build-images-lock
    verify-offline-bundle
    truckctl
  overlays/
    dmf-infra/
    dmf-cms/
    dmf-runbooks/
    dmf-media/
  patches/
    dmf-infra/
    dmf-cms/
  _vendor/
  images/
    images.lock
  docs/
    runbooks/
```

Rules:

- `_vendor/` is generated from `manifest.lock.yml`.
- No hand edits in `_vendor/`.
- Appliance-specific behavior is expressed through profile vars, overlays, or
  explicit patch files.
- If a patch survives more than two upstream bumps, upstream it.
- Upstream changes that are generally useful must land in the source repo first.
- The appliance repo records source SHAs and image digests; it does not become
  the source of truth for copied code.

Example source manifest:

```yaml
sources:
  dmf-infra:
    repo: ../dmf-infra
    ref: <commit-sha-or-tag>
    include:
      - k3s-lab-bootstrap/roles/base/k3s
      - k3s-lab-bootstrap/roles/base/ingress
      - k3s-lab-bootstrap/roles/base/ingress-private
      - k3s-lab-bootstrap/roles/base/cert-manager
      - k3s-lab-bootstrap/roles/base/external-secrets
      - k3s-lab-bootstrap/roles/base/prometheus
      - k3s-lab-bootstrap/roles/base/grafana
      - k3s-lab-bootstrap/roles/stack/operator/openbao
      - k3s-lab-bootstrap/roles/stack/operator/authentik
      - k3s-lab-bootstrap/roles/stack/operator/zot
      - k3s-lab-bootstrap/roles/stack/operator/netbox
      - k3s-lab-bootstrap/roles/stack/operator/awx
      - k3s-lab-bootstrap/roles/stack/operator/forgejo
      - k3s-lab-bootstrap/roles/stack/operator/loki
      - k3s-lab-bootstrap/roles/stack/operator/cms
  dmf-cms:
    repo: ../dmf-cms
    ref: <commit-sha-or-tag>
    image: registry.flypack.local/dmf-cms:<version>
  dmf-runbooks:
    repo: ../dmf-runbooks
    ref: <commit-sha-or-tag>
    include:
      - playbooks
      - roles
  dmf-media:
    repo: ../dmf-media
    ref: <commit-sha-or-tag>
    include:
      - catalog
```

## Upstream Work First

Before creating a large appliance repo, add the missing profile knobs upstream
in `dmf-infra`. The goal is that `dmf-flypack` mostly selects vars rather than
patching role internals.

### 1. Profile Variables

Add a named profile shape for the CMS-capable RPi appliance. Candidate vars:

```yaml
dmf_profile: flypack-rpi-cms
dmf_node_count: 1
dmf_storage_class: local-path
dmf_storage_access_mode: ReadWriteOnce
dmf_stateful_primary_node: <inventory-hostname>
dmf_ingress_mode: nodeport-only
dmf_cloud_lb_enabled: false
dmf_longhorn_enabled: false
dmf_offline_registry_enabled: true
dmf_offline_registry_host: registry.flypack.local
dmf_image_pull_policy: IfNotPresent
dmf_observability_profile: slim
```

Use environment inventory to provide real hostnames, IPs, domains, and secrets.
Do not hardcode operator paths, real domains, or real IP addresses in public
repos.

### 2. Local-Path Storage Support

Current role defaults often assume `longhorn`. Parameterize them without
breaking cloud/site defaults.

Files to inspect and update:

- `roles/stack/operator/openbao/defaults/main.yml`
- `roles/stack/operator/authentik/defaults/main.yml`
- `roles/stack/operator/zot/defaults/main.yml`
- `roles/stack/operator/netbox/defaults/main.yml`
- `roles/stack/operator/awx/defaults/main.yml`
- `roles/stack/operator/forgejo/defaults/main.yml`
- `roles/base/prometheus/defaults/main.yml`
- `roles/stack/operator/loki/defaults/main.yml`
- `roles/base/grafana/defaults/main.yml`

Important single-node storage issue:

- AWX projects storage currently renders `ReadWriteMany`.
- NetBox media persistence currently renders `ReadWriteMany`.
- Longhorn is not present in the RPi profile.
- For v0, set these access modes to `ReadWriteOnce` under the flypack profile
  and pin the pods to the primary node. Single-node RWO is acceptable for the
  prototype; do not claim distributed storage.

Files likely needing access-mode variables:

- `roles/stack/operator/awx/templates/awx-instance.yml.j2`
- `roles/stack/operator/netbox/templates/values.yml.j2`

### 3. Stateful Primary Pinning

Add nodeSelector/affinity support for stateful core apps so future joined agents
do not accidentally receive stateful pods backed by primary-local storage.

Minimum apps to pin:

- OpenBao
- Authentik Postgres
- NetBox/Postgres/Valkey/media PVC users
- AWX/Postgres/projects
- Forgejo
- Zot
- Prometheus
- Loki
- Grafana

The pinning must be optional and off by default for cloud/site profiles.

### 4. Ingress Modes

Add or verify a clean `nodeport-only` or host-local ingress mode:

- no cloud LB objects
- no Hetzner/Aliyun provider tasks
- no MetalLB requirement
- local DNS or static hosts file can map app hostnames to the RPi LAN IP
- all app URLs remain variable-driven

Do not remove existing cloud/site ingress behavior.

### 5. Slim Observability Profile

The current Prometheus and Loki defaults are sized for larger environments and
compliance-oriented retention. For the RPi prototype add a slim profile:

Suggested v0 values:

```yaml
prometheus_storage_size: 10Gi
prometheus_retention: 7d
prometheus_retention_size: 8GB
loki_storage_size: 10Gi
loki_retention: 168h
loki_security_retention: 168h
grafana_storage_size: 1Gi
```

This is a prototype retention profile. It does not satisfy any Mode C
compliance retention claim.

### 6. Zot as Offline Root

The local Zot registry is load-bearing. Current `zot_storage_size: 20Gi` is too
small for a full offline seed including AWX, NetBox, Authentik, Forgejo,
monitoring, k3s runtime images, and execution environments.

Add profile values such as:

```yaml
zot_storage_size: 250Gi
zot_anonymous_read: true
zot_oidc_enabled: false
```

The appliance should use Zot as the local artifact root and configure k3s
containerd to pull through the local registry only.

### 7. Offline Image Lock

Add tooling, preferably upstream in `dmf-infra`, to render the selected profile
and extract every container image reference into `images.lock`.

`images.lock` must include at least:

- k3s required images
- Traefik
- cert-manager
- external-secrets
- OpenBao
- Authentik server/worker/Postgres/Redis or Valkey dependencies
- Zot
- NetBox and its Postgres/Valkey/housekeeping dependencies
- AWX operator, AWX web/task/Postgres/Redis dependencies
- AWX execution environments used by runbooks
- Forgejo
- dmf-cms
- Prometheus, Alertmanager, node-exporter, kube-state-metrics
- Grafana
- Loki and Promtail
- any catalog/NMOS demo images selected for the prototype

Acceptance:

- Rendering the flypack profile produces no image not present in `images.lock`.
- The seed process can populate Zot from an OCI layout or tar bundle.
- A no-internet install does not attempt to pull from Docker Hub, GHCR,
  Quay, or upstream registries.

### 8. Offline Agent Join

Add an agent join path where a freshly prepared node can join without internet.

The joined node needs:

- k3s agent binary/install payload, or a pre-flashed image containing it
- CA trust for the local registry
- containerd registry mirror config pointed at local Zot
- k3s server URL on the RPi LAN IP
- k3s join token
- node labels that keep stateful platform apps off the agent by default

Acceptance:

- agent joins with the WAN unplugged
- agent can pull all required images from Zot
- stateful core pods remain on the primary
- simple stateless test workload can schedule on the agent

## Appliance Repo Implementation

After upstream has the knobs above, create `dmf-flypack` as a thin distribution
repo.

### Phase A - Repository Skeleton

Deliver:

- `manifest.yml`
- `manifest.lock.yml`
- `profiles/rpi5-16gb-1tb.yml`
- `bin/sync-sources`
- `bin/render-profile`
- `bin/build-images-lock`
- `bin/verify-offline-bundle`
- `bin/truckctl`
- `docs/runbooks/provision-rpi.md`
- `docs/runbooks/offline-agent-join.md`
- `docs/runbooks/update-pack.md`
- `docs/runbooks/backup-restore.md`

Guardrails:

- `bin/sync-sources` is deterministic.
- `_vendor/` can be deleted and regenerated.
- CI fails if `_vendor/` differs from `manifest.lock.yml`.
- CI fails if patches do not apply cleanly.

### Phase B - Profile Render

Deliver a profile render that produces the minimal stack:

- k3s single server
- local-path storage
- nodeport/local ingress
- OpenBao + ESO
- Authentik
- Zot
- NetBox
- AWX
- Forgejo
- dmf-cms
- slim Prometheus/Grafana/Loki

Render assertions:

- no `longhorn` StorageClass in rendered manifests
- no cloud provider service type or CCM resources
- no MetalLB dependency
- no real IP/domain/operator path in generated defaults
- all persistent apps use `local-path`
- stateful apps are pinned to the primary

### Phase C - Zot Seed and Registry Lock

Deliver:

- `images/images.lock`
- OCI layout or tar bundle import procedure
- Zot seed command in `truckctl`
- containerd registry mirror config
- local registry CA/trust installation

Acceptance:

- all images in `images.lock` exist in Zot
- all rendered image refs resolve to Zot-local names or digests
- install succeeds with external network disabled after OS provisioning

### Phase D - RPi Install Smoke

Run on the reference RPi:

1. provision host
2. install k3s single-node
3. seed Zot
4. deploy OpenBao and unseal
5. deploy ESO
6. deploy Authentik
7. deploy NetBox, AWX, Forgejo, CMS
8. deploy slim monitoring
9. run verify

Functional acceptance:

- `dmf-cms` login works through Authentik
- `dmf-cms` Workflows page lists AWX templates
- launching a safe AWX verify job succeeds
- Facility page reads NetBox
- Changes page reads Forgejo commits/PRs and AWX recent jobs
- Monitoring page reads Prometheus
- Catalog page reads YAML entries, joins NetBox lifecycle state, and can launch
  an AWX deploy/teardown job if a demo entry is enabled

Resource acceptance:

- idle memory leaves at least 2 GB free on the RPi
- no core pod is CrashLooping
- no pod is Pending due to PVC access mode or node affinity
- reboot recovery is documented, including OpenBao unseal

### Phase E - Offline Agent Join

Join one additional node with WAN disconnected.

Acceptance:

- k3s agent joins
- node labels are applied
- containerd pulls from Zot
- a stateless test workload schedules to the agent
- stateful core apps remain on the RPi primary

### Phase F - Upstream Sync Loop

Add documented upgrade flow:

```text
1. bump dmf-infra/dmf-cms/dmf-runbooks/dmf-media refs in manifest.yml
2. run bin/sync-sources
3. reapply overlays and patches
4. render profile
5. rebuild images.lock
6. verify offline bundle
7. test upgrade on RPi
8. commit manifest.lock.yml + generated artifacts
```

Release rule:

- `dmf-infra` and `dmf-cms` should publish tags first.
- `dmf-flypack` consumes those tags.
- Emergency direct patches are allowed only with a removal condition and an
  upstream issue/plan reference.

## Verification Commands

Run from the umbrella unless a repo-specific README says otherwise.

Read-only checks:

```sh
git status --short
bin/generate-status.sh
rg -n "longhorn|metallb|hcloud|aliyun|LoadBalancer" dmf-flypack
rg -n "docker.io|ghcr.io|quay.io|registry.k8s.io" dmf-flypack/rendered
```

Expected result for the final rendered appliance:

- `longhorn` absent except docs/comments explaining omission
- cloud provider strings absent from rendered manifests
- external registry hostnames absent from rendered runtime manifests
- all images accounted for in `images.lock`

Repo-specific checks are likely to include:

```sh
ansible-playbook --syntax-check <rendered playbook>
helm template <chart> -f <rendered values>
```

When running against a real DMF environment, respect ADR-0010: use the sanctioned
wrapper from the environment repo. Do not run bare `ansible-playbook` against a
live cluster.

## Risks and Design Notes

### RPi Resource Headroom

16 GB is credible but tight. AWX, NetBox, Authentik, Forgejo, Prometheus, Loki,
and Zot together will leave limited memory for media workloads. The prototype
must limit concurrency:

- one operator
- one AWX job at a time initially
- short monitoring retention
- no local image builds
- no HA replicas

### RPi vs Mode C Compliance

ADR-0020 is Proposed at plan time and says a shipping Mode C flypack needs
secrets sealed to local TPM/HSM. A stock RPi 5 does not satisfy that by itself.

Therefore this plan produces a **Mode C prototype/reference appliance**, not a
compliance-ready shipped flypack. A commercial unit needs either:

- CM5 carrier with TPM/HSM,
- external HSM,
- or a superseding Mode C secrets design.

### Local-Path Storage

`local-path` is acceptable for the prototype but not a distributed storage
story. If future agents join, keep stateful platform pods on the primary.

Do not reintroduce Longhorn just to get RWX semantics on the RPi. That defeats
the minimal target.

### Image Bloat

The biggest practical failure mode is an incomplete or overly large image
bundle. AWX and NetBox pull many dependent images through operators/subcharts.
`images.lock` must be generated from rendered manifests, not manually curated.

### TLS and Local Naming

The flypack offline-lane doc discusses factory ACME and customer-provided certs.
For the RPi prototype, pick one explicit mode:

- preloaded cert bundle for a factory-owned test domain, or
- local private CA with operator-installed trust for test clients.

Do not leave browser trust as an implicit afterthought; Authentik/OIDC callback
URLs are sensitive to hostnames and schemes.

### Path A Runbooks

Move 1 uses Path A: AWX launchers call through the control node using SSH
material managed through OpenBao. A fresh agent must not resurrect pre-Path-A
file shapes. Read ADR-0014, ADR-0016, and the latest Move 1 handoffs before
changing runbook integration.

## Open Decisions

1. Final repo name: `dmf-flypack`, `dmf-appliance`, or another name.
2. Whether to make `_vendor/` committed or generated-only in CI artifacts.
3. Prototype TLS mode: factory-preloaded cert bundle or local CA.
4. Whether `dmf-flypack` gets its own ADR as a distribution repo pattern.
5. Exact slim Prometheus/Loki retention defaults.
6. Zot storage reservation on the 1 TB NVMe.
7. RPi prototype secret posture: manual OpenBao unseal only, or test TPM/HSM
   carrier from the start.

## Definition of Done

The first implementation is done when:

- upstream repos have the required flypack profile knobs
- `dmf-flypack` can regenerate its vendor tree from source refs
- the RPi profile renders without Longhorn/cloud-LB/MetalLB dependencies
- Zot can be seeded from a complete `images.lock`
- the RPi installs and boots the full CMS-capable core stack offline
- dmf-cms proves NetBox, AWX, Forgejo, Authentik, and Prometheus integration
- one offline k3s agent can join and run a stateless workload from local Zot
- all divergences are either upstreamed or tracked as named temporary patches
