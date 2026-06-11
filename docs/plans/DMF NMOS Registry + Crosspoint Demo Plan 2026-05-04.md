---
status: superseded
date: 2026-05-04
superseded_by: "dmf-platform-move-1-task-2026-05-04.md"
---
# DMF NMOS Registry + Crosspoint Demo — Plan 2026-05-04
> **Superseded by** [dmf-platform-move-1-task-2026-05-04.md](dmf-platform-move-1-task-2026-05-04.md) — see frontmatter.

> **SUPERSEDED 2026-05-23** by ADR-0025 Lane B. NMOS-cpp now deploys as a
> Helm chart from in-cluster Zot via an AWX EE pod; this plan remains only as
> historical technical reference for image/config shapes and the deferred
> crosspoint/RTP demo path.
>
> **Status (updated 2026-05-23):** fully superseded for implementation. Earlier Phase 3 ("dmf-cms integration deferred") was superseded by [`dmf-platform-move-1-task-2026-05-04.md`](dmf-platform-move-1-task-2026-05-04.md); Phase 1+2 implementation shape is now superseded by ADR-0025 Lane B.
>
> **2026-05-19 update — manifests lift into a Helm chart.** The k8s manifests in this plan's Phase 1 (registry StatefulSet, node Deployments, Services, PVC, ConfigMaps) are the source material for the `dmf-media/charts/nmos-cpp/` Helm chart per the [DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19](./DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md). The Ansible role's k8s tasks (`roles/nmos-cpp/tasks/configure.yml`) get deleted; the chart owns the manifests; the launcher invokes `kubernetes.core.helm`. The Dockerfile, ConfigMap shapes, runtime config, and dmf-env inventory additions remain valid as technical reference. See [ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md).
>
> Specifically:
> - **Phase 1 (nmos-cpp registry + mock nodes)** — reused as-is. The Dockerfile, ConfigMap shapes, and role tasks survive the catalog reframe.
> - **Phase 1 Step 3 (lifecycle registration)** — reframed: `410-nmos-cpp.yml` is split into `410-nmos-cpp-provision.yml` (registers catalog entry, does NOT launch) and `configure-media/launch-nmos-cpp.yml` (launches on operator action via `lifecycle-configure.yml`). See ADR-0012.
> - **Phase 2 (nmos_crosspoint UI)** — deferred from Move 1 + Catalog v1. May fold into a v2 catalog entry or land as Move 1.5.
> - **Phase 3 (dmf-cms integration)** — fully superseded. Read `dmf-platform-move-1-task-2026-05-04.md` Piece 7 instead.
> - **Appendices A–E** — preserved unchanged; technical reference for nmos-cpp build, runtime config, dmf-env inventory additions, and the deferred RTP demo path.
>
> **Date:** 2026-05-04
> **Repos in scope:** `dmf-media` (primary), `dmf-env` (inventory vars), `dmf-cms` (catalog integration per Move 1 + Catalog task)

## 0. One-line summary

Deploy Sony's `nmos-cpp` registry + mock nodes and `3dmedium/nmos_crosspoint` routing UI into the k3s cluster via dmf-media, exposed on the Tailscale private lane, to produce a demo-capable NMOS IS-04/05 environment.

## 1. Why this, why now

ADR-0004 (experiment phase) and the DMF Platform Plan §5–§7a identify NMOS IS-04/05 as the media-domain discovery and routing backbone. The `dmf-media/roles/nmos-cpp/` stub has existed since scaffold. This plan implements it, producing:

- A working NMOS Registration & Discovery System (RDS)
- Mock senders/receisors for testing without real hardware
- A visual routing matrix (crosspoint UI) reachable via Tailscale
- Ansible roles and Helm charts that fit the EBU layer model (Layers 4–5)

## 2. Architecture

### 2.1 Component map

```
┌─────────────────────────────────────────────────┐
│  nmos namespace (k3s cluster)                   │
│                                                 │
│  nmos-cpp-registry  (StatefulSet, 1 replica)    │
│    ↓ IS-04/05 HTTP API                           │
│  nmos-cpp-node ×2  (Deployment, mock senders)   │
│    ↑ mDNS/unicast DNS-SD                         │
│  nmos-crosspoint   (Deployment, Svelte UI)       │
│    ↓ IngressRoute (traefik-private)              │
└─────────────────────────────────────────────────┘
         ↑
    Tailscale tailnet (operator laptop, Mac mini)
    https://nmos-xp.<lan-host>
```

### 2.2 Exposure model

| Component | Exposure | URL / access |
|---|---|---|
| Registry | ClusterIP only | `http://nmos-registry.nmos.svc:80` (internal) |
| Nodes | ClusterIP only | `http://nmos-node-*.nmos.svc:80` (internal) |
| Crosspoint UI | IngressRoute (traefik-private) | `https://nmos-xp.<lan-host>` (tailnet only) |

**Rationale for private-only exposure:** NMOS relies on mDNS/DNS-SD discovery (LAN protocols). Exposing the registry to the public internet is architecturally wrong and unnecessary — the operator console (dmf-cms) and crosspoint UI both reach it via Tailscale.

### 2.3 DNS-SD mode: unicast first, mDNS later

nmos-cpp supports **unicast DNS-SD** as a discovery fallback. For Phase 1, all components are configured with each other's cluster DNS names directly. This avoids the mDNS-repeater complexity (DaemonSet, L2 bridge, Hetzner private network `10.0.0.0/28` constraints) and is sufficient for a demo. mDNS reflection can be added later when testing with real NMOS hardware.

## 3. Implementation plan

### Phase 1 — nmos-cpp registry + mock nodes

#### Step 1: Dockerfile for nmos-cpp

**File:** `dmf-media/roles/nmos-cpp/files/Dockerfile`

Multi-stage build:
- **Stage 1 (build):** Ubuntu 22.04 ARM64 (matches Hetzner CAX21), install Conan 2 + CMake, clone nmos-cpp at a pinned release tag, build `nmos-cpp-registry` and `nmos-cpp-node` binaries
- **Stage 2 (runtime):** Distroless or slim image, copy binaries, expose port 80/443

Build via Colima on Mac mini (same pattern as dmf-cms):
```bash
DOCKER_HOST=unix://$HOME/.colima/docker-build/docker.sock \
  docker build -t registry.<lan-host>/<operator>/nmos-cpp:<tag> -f Dockerfile .
```

#### Step 2: nmos-cpp Ansible role (replace stub)

**Dir:** `dmf-media/roles/nmos-cpp/`

| File | Purpose |
|---|---|
| `tasks/main.yml` | Namespace, ConfigMap, Registry StatefulSet, Node Deployments, Services |
| `defaults/main.yml` | Image tag, replica count, namespace, DNS-SD config |
| `templates/registry-configmap.yaml.j2` | nmos-cpp registry config (hostname, port, unicast DNS-SD peers) |
| `templates/node-configmap.yaml.j2` | nmos-cpp node config (registry hostname, mock sender/receiver types) |
| `templates/registry-statefulset.yaml.j2` | Registry pod spec |
| `templates/node-deployment.yaml.j2` | Node pod spec (looped for N instances) |
| `templates/registry-service.yaml.j2` | ClusterIP for registry |
| `templates/node-service.yaml.j2` | ClusterIP for each node |
| `README.md` | Already exists (stub description) |

**Key ConfigMap fields for nmos-cpp:**
- `hostname` — pod FQDN
- `host_address` / `advertised_ip` — pod IP or service DNS name
- `registries` — list of `{"hostname": "nmos-registry.nmos.svc", "priority": 0, "weight": 0}`
- `logging_level` — debug for demo
- `http_port` / `https_port` — 80 / 443

#### Step 3: Playbook + lifecycle registration

**New playbook:** `dmf-media/playbooks/410-nmos-cpp.yml`

```yaml
- name: Deploy NMOS IS-04/05 registry and mock nodes
  hosts: k3s_control[0]
  become: true
  gather_facts: false
  roles:
    - role: nmos-cpp
```

**Register in:** `dmf-infra/k3s-lab-bootstrap/lifecycle-provision.yml`

Add after the Layer 4xx/5xx reserved comments (before Layer 6xx):

```yaml
# ── Layer 4xx — Media Exchange ───────────────────────────────────────────────
- import_playbook: ../dmf-media/playbooks/410-nmos-cpp.yml
  tags: [layer4, media-exchange, nmos]
```

The playbook lives in dmf-media but is imported from dmf-infra's lifecycle, consistent with the ADR-0003 EBU layer model.

#### Step 4: Build + deploy

```bash
# Build images on Mac mini via Colima
cd dmf-media/roles/nmos-cpp/files/
docker build -t registry.<lan-host>/<operator>/nmos-cpp:registry-v0.1.0 -f Dockerfile.registry .
docker build -t registry.<lan-host>/<operator>/nmos-cpp:node-v0.1.0 -f Dockerfile.node .
docker push registry.<lan-host>/<operator>/nmos-cpp:registry-v0.1.0
docker push registry.<lan-host>/<operator>/nmos-cpp:node-v0.1.0

# Deploy via lifecycle
cd dmf-env
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/lifecycle-provision.yml --tags nmos
```

#### Step 5: Verify

One-shot Ansible playbook to query the registry:

```yaml
# dmf-media/playbooks/419-nmos-verify.yml
- name: Query NMOS registry
  hosts: k3s_control[0]
  become: true
  tasks:
    - command:
        argv:
          - sudo
          - k3s
          - kubectl
          - -n
          - nmos
          - exec
          - deploy/nmos-registry
          - --
          - wget
          - -qO-
          - http://localhost:80/x-nmos/query/v1.3/nodes/
      register: result
    - debug: var=result.stdout
```

Expected: JSON array listing the mock nodes.

### Phase 2 — nmos_crosspoint routing UI

#### Step 1: Dockerfile for nmos_crosspoint

**File:** `dmf-media/roles/media-controllers/files/Dockerfile`

Multi-stage:
- **Stage 1 (build):** Node 20, `npm ci` + `npm run build` for both server (TypeScript) and UI (Svelte)
- **Stage 2 (runtime):** Node 20 slim, copy built server, expose port 80

Config needs `server/config/` directory with registry WebSocket URL and `users.json` (SHA256 password hash).

#### Step 2: media-controllers Ansible role

**Dir:** `dmf-media/roles/media-controllers/` (new)

| File | Purpose |
|---|---|
| `tasks/main.yml` | Namespace (reuse nmos), Deployment, Service, IngressRoute, ConfigMap, Secret |
| `defaults/main.yml` | Image tag, hostname, registry URL |
| `templates/deployment.yaml.j2` | Crosspoint pod spec |
| `templates/service.yaml.j2` | ClusterIP |
| `templates/ingressroute.yaml.j2` | traefik-private IngressRoute |
| `templates/configmap.yaml.j2` | Server config (registry WebSocket URLs) |
| `templates/secret.yaml.j2` | users.json (SHA256 password hashes) |

**IngressRoute:**
```yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: nmos-crosspoint
  namespace: nmos
spec:
  entryPoints:
    - websecure
  routes:
    - match: Host(`nmos-xp.<lan-host>`)
      kind: Rule
      services:
        - name: nmos-crosspoint
          port: 80
  tls:
    secretName: nmos-crosspoint-tls
```

#### Step 3: Playbook

**New playbook:** `dmf-media/playbooks/510-media-controllers.yml`

Same pattern as 410. Register in lifecycle-provision.yml under Layer 5xx.

#### Step 4: Verify

- Open `https://nmos-xp.<lan-host>` from a tailnet device
- Login with seeded credentials
- Confirm registered nodes/senders/receivers appear in the matrix
- Create a crosspoint connection (sender → receiver)

### Phase 3 — dmf-cms integration (deferred)

After Phase 1+2 are working:

1. **NMOS status card** in dmf-cms dashboard (registry health, node count)
2. **Crosspoint embed** — iframe or API proxy to the crosspoint UI
3. **AWX job templates** — "create route", "scan media network"
4. **NetBox media plugin** — SoT for sender/receiver/flow metadata

These require frontend changes to dmf-cms and depend on a working NMOS backend. Deferred until after Phase 2 verification.

## 4. Dependencies

| Dependency | Status | Source |
|---|---|---|
| k3s cluster running | Live | dmf-infra |
| Tailscale private lane | Live | dmf-infra playbooks 311, 321 |
| Container registry (Zot) | Live | playbook 331 |
| Traefik + TLS certs | Live | playbooks 310, 320 |
| Colima on Mac mini | Live | Operator host |
| Ansible + run-playbook.sh | Live | dmf-env |

## 5. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| nmos-cpp Conan build on ARM64 fails | Cannot build images | Pin to a known-good release tag; fall back to Easy-NMOS's Dockerfile |
| Crosspoint auth bug (unauthenticated access broken) | Must seed users.json | Follow README guidance — create SHA256 hash, mount as Secret |
| mDNS doesn't work across pods | Nodes can't discover registry | Use unicast DNS-SD mode (configured via ConfigMap) |
| Registry is single-instance, in-memory | No HA, state lost on restart | Acceptable for experiment phase; add persistence later |
| Crosspoint multi-leg mapping is 1:1 | No intelligent subnet routing | Fine for single-cluster demo; documented limitation |

## 6. File inventory (what will be created/modified)

### dmf-media (new files)

```
roles/nmos-cpp/
  files/
    Dockerfile.registry       # nmos-cpp-registry image
    Dockerfile.node           # nmos-cpp-node image
  tasks/
    main.yml                  # was stub, now real implementation
  defaults/
    main.yml                  # image tags, namespace, DNS-SD config
  templates/
    registry-configmap.yaml.j2
    node-configmap.yaml.j2
    registry-statefulset.yaml.j2
    node-deployment.yaml.j2
    registry-service.yaml.j2
    node-service.yaml.j2

roles/media-controllers/      # new role
  files/
    Dockerfile                # nmos_crosspoint image
  tasks/
    main.yml
  defaults/
    main.yml
  templates/
    deployment.yaml.j2
    service.yaml.j2
    ingressroute.yaml.j2
    configmap.yaml.j2
    secret.yaml.j2

playbooks/
  410-nmos-cpp.yml
  419-nmos-verify.yml
  510-media-controllers.yml
```

### dmf-infra (modified)

```
k3s-lab-bootstrap/lifecycle-provision.yml  # add imports for 410, 510
```

## 7. Success criteria

- [ ] `nmos-cpp-registry` pod running in `nmos` namespace
- [ ] ≥2 `nmos-cpp-node` pods running, registered to the registry
- [ ] Query API returns node list (verified via playbook 419)
- [ ] Crosspoint UI reachable at `https://nmos-xp.<lan-host>` from tailnet
- [ ] Crosspoint shows nodes/senders/receivers and can create a connection
- [ ] All Ansible roles idempotent (--check --diff passes on re-run)

---

## Appendix A — nmos-cpp Dockerfile build strategy

nmos-cpp has **no official Docker image**. The Easy-NMOS kit (`rhastie/easy-nmos`) pulls pre-built images built from a **NVIDIA fork** of nmos-cpp, not the main Sony repo. For our images we build directly from `sony/nmos-cpp`.

### A.1 Build architecture

```
┌─────────────────────────────────────────────────┐
│  Mac mini (Colima, linux/arm64)                 │
│                                                 │
│  Dockerfile.registry (multi-stage):             │
│    stage 1: ubuntu:22.04 (arm64)                │
│      → install Conan 2, CMake 3.22+, g++        │
│      → conan profile detect                     │
│      → clone sony/nmos-cpp@<pinned tag>         │
│      → conan install --build=missing            │
│      → cmake + make nmos-cpp-registry           │
│    stage 2: alpine:3.19 (arm64) or distroless   │
│      → COPY --from=0 nmos-cpp-registry binary   │
│      → EXPOSE 80 443                            │
│      → ENTRYPOINT ["nmos-cpp-registry"]         │
│                                                 │
│  Dockerfile.node (multi-stage, same pattern):   │
│    stage 1: same builder                        │
│      → cmake + make nmos-cpp-node               │
│    stage 2: same runtime                        │
│      → COPY nmos-cpp-node binary                │
│      → EXPOSE 80 443                            │
│      → ENTRYPOINT ["nmos-cpp-node"]             │
└─────────────────────────────────────────────────┘
```

### A.2 Key Conan dependencies (from nmos-cpp CMakeLists.txt)

| Dependency | Version | Purpose |
|---|---|---|
| `boost` | ≥1.74 | Core library (asio, system, thread, regex, json, program_options) |
| `openssl` | 3.x | TLS/HTTPS, BCP-003-02 JWT auth |
| `cpprestsdk` | (via Conan) | HTTP client/server (REST APIs) |
| `websocketpp` | (via Conan) | WebSocket support for IS-07/08 |
| `cmake` | ≥3.22 | Build system |
| `conan` | 2.x | Package manager |

The nmos-cpp CMake project defines two executable targets:
- `nmos-cpp-registry` — the RDS binary
- `nmos-cpp-node` — the reference node binary with mock senders/receivers

Both are built from the same CMake tree; you select which target to build.

### A.3 Pinned release tag

Use the latest stable release tag from `sony/nmos-cpp` (check `git tag -l` on the repo). As of the research date, no specific tag was verified — the first implementation step should `git ls-remote --tags https://github.com/sony/nmos-cpp` and pick the most recent non-RC tag. The Dockerfile should `ARG NMOS_CPP_VERSION` with a default.

### A.4 Build commands (on Mac mini)

```bash
# Start Colima if not running
colima start docker-build

# Wait for docker to be ready
export DOCKER_HOST=unix://$HOME/.colima/docker-build/docker.sock
docker info > /dev/null 2>&1

cd <repos>/dmf-media/roles/nmos-cpp/files/

# Build registry image
docker build \
  --build-arg NMOS_CPP_VERSION=<tag> \
  -t registry.<lan-host>/<operator>/nmos-cpp-registry:<tag> \
  -f Dockerfile.registry .

# Build node image
docker build \
  --build-arg NMOS_CPP_VERSION=<tag> \
  -t registry.<lan-host>/<operator>/nmos-cpp-node:<tag> \
  -f Dockerfile.node .

# Push both
docker push registry.<lan-host>/<operator>/nmos-cpp-registry:<tag>
docker push registry.<lan-host>/<operator>/nmos-cpp-node:<tag>
```

### A.5 ARM64 consideration

Hetzner nodes are ARM64 (CAX21). The Mac mini with Colima also runs linux/arm64 by default, so the build produces the right architecture natively — no cross-compilation or `--platform` flag needed.

### A.6 Fallback plan

If the Conan build from the Sony repo fails (dependency incompatibility, missing ARM64 wheels), fall back to the **Easy-NMOS approach**: use the NVIDIA fork's Dockerfiles as a starting point, or pull their pre-built images and retag them. The NVIDIA fork is functionally compatible but diverged for GPU-accelerated encoding use cases we don't need.

---

## Appendix B — nmos-cpp runtime configuration schema

nmos-cpp binaries accept configuration via **command-line arguments** and/or a **JSON config file**. The key settings:

### B.1 Registry binary (`nmos-cpp-registry`)

| Flag / Config key | Default | Purpose |
|---|---|---|
| `--host=<ip>` | auto-detect | The IP/hostname the registry binds to |
| `--port=<n>` | 80 | HTTP port |
| `--https-port=<n>` | 443 | HTTPS port (requires TLS config) |
| `--domain=<name>` | empty | NMOS domain ID (optional, for multi-domain setups) |
| `--logging=<level>` | info | Debug, info, warning, error |
| `--registries=<json>` | empty | For a registry-of-registries (HA mode); empty for single instance |

For our single-instance demo, only `--host`, `--port`, and `--logging` matter. The registry auto-discovers nodes via mDNS/DNS-SD on the local network.

### B.2 Node binary (`nmos-cpp-node`)

| Flag / Config key | Default | Purpose |
|---|---|---|
| `--host=<ip>` | auto-detect | The IP/hostname the node advert |
| `--port=<n>` | 80 | HTTP port for the node's API |
| `--https-port=<n>` | 443 | HTTPS port |
| `--registries=<json>` | auto-discover | JSON array of registry endpoints. Format: `[{"hostname": "reg.example.com", "priority": 0, "weight": 0}]` |
| `--domain=<name>` | empty | NMOS domain ID |
| `--logging=<level>` | info | Log verbosity |
| `--label=<name>` | auto | Human-readable node label |
| `--description=<text>` | auto | Node description |

**Critical for k3s:** The `--registries` flag is how we wire nodes to the registry **without mDNS**. In unicast mode, we set:

```json
--registries=[{"hostname": "nmos-registry.nmos.svc.cluster.local", "priority": 0, "weight": 0}]
```

This bypasses DNS-SD entirely — the node directly POSTs to the registry's IS-04 API.

### B.3 ConfigMap payload for the registry

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nmos-registry-config
  namespace: nmos
data:
  registry.json: |
    {
      "host": "0.0.0.0",
      "port": 80,
      "logging": "debug"
    }
```

### B.4 ConfigMap payload for each node

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: nmos-node-1-config
  namespace: nmos
data:
  node.json: |
    {
      "host": "0.0.0.0",
      "port": 80,
      "registries": [
        {"hostname": "nmos-registry.nmos.svc.cluster.local", "priority": 0, "weight": 0}
      ],
      "label": "nmos-mock-node-1",
      "description": "Mock NMOS node with video/audio/data senders",
      "logging": "debug"
    }
```

The ConfigMap is mounted as a volume at `/config/` in the container, and the entrypoint is `nmos-cpp-node --config=/config/node.json`.

### B.5 Pod entrypoint pattern

Both Dockerfiles should set up the binary to accept either CLI flags or a `--config` JSON file. The entrypoint in the pod spec:

```yaml
command: ["nmos-cpp-node"]
args: ["--config=/config/node.json"]
```

For the registry:
```yaml
command: ["nmos-cpp-registry"]
args: ["--config=/config/registry.json"]
```

---

## Appendix C — nmos_crosspoint config details

### C.1 Config directory structure

Per the repo README:

```
server/
  config/              # rename from config_example/
    nmos.json          # Registry connection settings
    users.json         # Auth (SHA256 password hashes)
```

### C.2 `nmos.json` format

```json
{
  "registries": [
    {
      "host": "nmos-registry.nmos.svc.cluster.local",
      "port": 80,
      "protocol": "http"
    }
  ],
  "interfaces": []     # empty = all interfaces; specify for multi-leg
}
```

The server auto-discovers registries on all interfaces and subscribes to their Query API via WebSocket. The `host` above is the k8s internal DNS name — this works when crosspoint runs as a pod in the same cluster.

### C.3 `users.json` format

```json
{
  "admin": "5e884898da28047151d0e56f8dc6292773603d0d6aabbdd62a11ef721d1542d8"
}
```

The value is the **SHA256 hash** of the plaintext password. `5e884...` above is the hash of `"password"` — a demo-only value. Generate real hashes with:

```bash
echo -n "your-password" | shasum -a 256
```

### C.4 ConfigMap + Secret mapping in k8s

```yaml
# ConfigMap for nmos.json
apiVersion: v1
kind: ConfigMap
metadata:
  name: nmos-crosspoint-config
  namespace: nmos
data:
  nmos.json: |
    {
      "registries": [{"host": "nmos-registry.nmos.svc.cluster.local", "port": 80, "protocol": "http"}]
    }

# Secret for users.json
apiVersion: v1
kind: Secret
metadata:
  name: nmos-crosspoint-auth
  namespace: nmos
type: Opaque
stringData:
  users.json: |
    {"admin": "<sha256-hash>"}
```

Mounted into the container at `/app/server/config/`.

---

## Appendix D — dmf-env inventory additions

### D.1 New variables in `inventories/hetzner-arm/group_vars/all/main.yml`

```yaml
# --- NMOS (dmf-media) ---
nmos_namespace: nmos
nmos_registry_image: "registry.<lan-host>/<operator>/nmos-cpp-registry:v0.1.0"
nmos_node_image: "registry.<lan-host>/<operator>/nmos-cpp-node:v0.1.0"
nmos_crosspoint_image: "registry.<lan-host>/<operator>/nmos-crosspoint:v0.1.0"
nmos_crosspoint_host: nmos-xp.<lan-host>
nmos_node_count: 2
```

### D.2 Secrets (via OpenBao)

The crosspoint admin password hash should be computed at deploy time and injected from OpenBao (ADR-0007):

```yaml
# In dmf-env manifest (not git-tracked):
nmos_crosspoint_admin_password: "<plaintext, from OpenBao secret/apps/nmos/crosspoint/admin>"
```

The Ansible role computes the SHA256 hash at runtime and puts it into the Secret — the plaintext never hits git or logs.

### D.3 Registry auth (if Zot requires OIDC)

If the container registry at `registry.<lan-host>` requires authentication (Zot OIDC from playbook 331), the build/push step needs credentials. This is handled by the operator's existing docker login before the build — not part of the Ansible role itself.

---

## Appendix E — Real RTP sender/receiver demo path (post-Phase-2)

To go beyond mock nodes and demonstrate actual RTP traffic:

### E.1 Minimum additional components

| Component | Purpose | Notes |
|---|---|---|
| **PTP grandmaster** | ST 2110 requires PTP sync (ST 2059) | `linuxptp` (`ptp4l` + `phc2sys`) in a container with `--cap-add=NET_RAW` and `--cap-add=SYS_TIME`, or on the host |
| **RTP sender** | Generates actual ST 2110-20/30/40 streams | `ffmpeg` or `gstreamer` with `rtpsink` elements, registered via IS-04 |
| **RTP receiver** | Consumes RTP streams | `ffmpeg`/`gstreamer` with `rtpbin`, or `vlcrtp` |
| **Multicast routing** | k3s CNI must pass multicast UDP | Flannel supports it; verify `net.ipv4.ip_forward=1` and IGMP settings |
| **SDP generator** | Creates SDP files for each flow | nmos-cpp node generates these automatically |

### E.2 Sender container example (conceptual)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: rtp-sender-camera-1
  namespace: nmos
spec:
  template:
    spec:
      containers:
        - name: sender
          image: gstreamer:1.22
          command: ["gst-launch-1.0"]
          args:
            - videotestsrc
            - ! rtpst2110pay pt=96
            - ! udpsink host=239.10.1.1 port=5004 ttl=5 auto-multicast=true
          # Plus an nmos-cpp-node sidecar that registers this sender via IS-04
```

### E.3 Why this is deferred

- PTP on virtualized Hetzner ARM nodes is questionable — they may not have access to a hardware PTP clock
- Multicast UDP through Flannel VXLAN needs testing
- Real senders/receivers add significant complexity (codec config, SDP generation, flow binding)
- The mock nodes are sufficient to prove: registry works, discovery works, crosspoint routing works
- Real RTP comes in Phase 3+ when testing on bare-metal or a site/facility profile
