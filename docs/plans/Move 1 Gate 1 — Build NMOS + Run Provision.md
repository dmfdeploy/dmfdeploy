---
status: executed
date: 2026-05-04
---
# Move 1 Gate 1 — Build NMOS images + Run Provision

> **GATE PASSED 2026-05-06; image-build flow superseded 2026-05-19.**
> The provision-side outcomes (namespace + ConfigMaps + NetBox `lifecycle:bootstrapped`
> tag) were validated on the original cluster; the Path Y redeploy preserved
> the same architecture. The **image-build-and-push step is superseded** by
> the canonical GHCR-first / Zot-mirror flow defined in the
> [DMF Public Container Registry Publishing Plan 2026-05-19](./DMF%20Public%20Container%20Registry%20Publishing%20Plan%202026-05-19.md)
> and Lane A of the
> [Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19](./DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md):
> images are built on the operator workstation, pushed to `ghcr.io/dmfdeploy/*`,
> then mirrored into in-cluster Zot via Stage 4b (playbook `630-zot-seed-platform`).
> The original "build on Mac mini, push directly to Zot" path documented below
> is no longer the sanctioned flow. Retained for historical reference.

**Date:** 2026-05-05
**Type:** Execution gate (human-verified checkpoint between Piece 4 and Piece 5)
**Purpose:** Build nmos-cpp images on Mac mini via Colima, push to Zot, run lifecycle-provision, verify artifacts are registered without workloads deployed.

---

## Context

This gate sits between Piece 4 (NMOS provision-side implementation) and Piece 5 (NMOS configure-side launch playbooks). The goal is to prove that:

1. The nmos-cpp binaries build cleanly from Sony upstream on ARM64
2. Images land in Zot
3. The provision playbook creates namespace + ConfigMaps without deploying any workload
4. NetBox gets an `ipam.Service` record tagged `lifecycle:bootstrapped`

If any of these fail, stop and investigate before proceeding to Piece 5.

---

## Architecture reference

- NMOS plan (Phase 1, Appendix A/B): `docs/plans/DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md`
- Catalog entry schema: `dmf-media/catalog/nmos-cpp.yaml`
- ADR-0012 (Configure vs Provision): `docs/decisions/0012-configure-stage-distinct-from-provision.md`
- ADR-0006 (Cluster is the truth): `docs/decisions/0006-cluster-is-truth.md`

---

## Pre-flight checks

### 1. Colima on Mac mini

```bash
colima list
# Expected: docker-build  Running
```

If not running:
```bash
colima start docker-build
# Wait until ready:
export DOCKER_HOST=unix://$HOME/.colima/docker-build/docker.sock
docker info > /dev/null 2>&1 && echo "Docker ready"
```

### 2. SSH access to control node

```bash
ssh k3s-admin@<control-node-public-ip> "sudo k3s kubectl version --short"
# Expected: Server Version and Client Version output
```

### 3. Clean git state in dmf-media

```bash
cd ~/repos/dmfdeploy/dmf-media && git status
```

No uncommitted changes should exist in the source tree. If dirty, the images built from source will reflect untracked modifications.

### 4. NetBox API reachable

```bash
curl -sk https://netbox.dmf.example.com/api/
# Expected: {"_meta":{"version":"..."}, ...}
```

---

## Step 1: Build NMOS images

**Source:** `~/repos/dmfdeploy/dmf-media/roles/nmos-cpp/files/`

Two Dockerfiles:
- `Dockerfile.registry` — builds `nmos-cpp-registry` from `sony/nmos-cpp` upstream (Conan 2 + CMake)
- `Dockerfile.node` — builds `nmos-cpp-node` from same upstream

Both use `NMOS_CPP_VERSION=4.1.0` (ARG default, no `v` prefix).

```bash
export DOCKER_HOST=unix://$HOME/.colima/docker-build/docker.sock
cd ~/repos/dmfdeploy/dmf-media/roles/nmos-cpp/files/

# Build registry image
docker build \
  --build-arg NMOS_CPP_VERSION=4.1.0 \
  -t registry.dmf.example.com/<operator>/nmos-cpp-registry:0.1.0 \
  -f Dockerfile.registry .

# Build node image
docker build \
  --build-arg NMOS_CPP_VERSION=4.1.0 \
  -t registry.dmf.example.com/<operator>/nmos-cpp-node:0.1.0 \
  -f Dockerfile.node .
```

**Expected:** Both builds complete in ~30-60 minutes each (Conan dependency resolution + CMake compilation).

**Verify:**
```bash
docker images | grep nmos-cpp
# Expected:
# registry.dmf.example.com/<operator>/nmos-cpp-registry   0.1.0   <id>   <size>
# registry.dmf.example.com/<operator>/nmos-cpp-node        0.1.0   <id>   <size>

# Verify binaries exist in the images
docker run --rm registry.dmf.example.com/<operator>/nmos-cpp-registry:0.1.0 --help 2>&1 | head -5
docker run --rm registry.dmf.example.com/<operator>/nmos-cpp-node:0.1.0 --help 2>&1 | head -5
```

---

## Step 2: Push images to Zot

> **DONE 2026-05-07** — images `nmos-cpp-registry:0.1.0` and `nmos-cpp-node:0.1.0`
> are in Zot. Pods reach Running on launch. The canonical script for re-pushing
> after a rebuild is `dmf-runbooks/roles/nmos-cpp/scripts/push-nmos-images.sh`
> (uses `get-admin-cred.sh` + isolated `DOCKER_CONFIG`). See the closure handoff
> [`DMF Item 15 NMOS ConfigMap Schema Fix Closure 2026-05-07.md`](../handoffs/DMF%20Item%2015%20NMOS%20ConfigMap%20Schema%20Fix%20Closure%202026-05-07.md).

**IMPORTANT:** Zot requires authentication. Do NOT use `docker login` with global `~/.docker/config.json`. Use the playbook path (recommended) or obtain credentials from OpenBao.

### Option A (recommended): Use playbook 650 pattern

The dmf-cms deploy playbook (650) handles registry auth automatically. For standalone push:

```bash
# 1. Get Zot admin credentials from OpenBao
bao login            # authenticate with operator credentials
bao kv get secret/apps/zot/admin

# 2. Use isolated docker config
export DOCKER_CONFIG=$(mktemp -d)
docker login -u <zot-admin-user> -p <zot-admin-password> registry.dmf.example.com

# 3. Push
docker push registry.dmf.example.com/<operator>/nmos-cpp-registry:0.1.0
docker push registry.dmf.example.com/<operator>/nmos-cpp-node:0.1.0

# 4. Clean up
rm -rf "$DOCKER_CONFIG"
unset DOCKER_CONFIG
```

### Option B: Verify images are in Zot after playbook run

If pushing manually is blocked by auth, skip push for now. The `lifecycle-provision.yml` playbook (next step) doesn't require the images to be in Zot — it only creates namespace + ConfigMaps. The image push can happen as part of the configure-stage launch (Piece 5).

---

## Step 3: Run lifecycle-provision playbook

```bash
cd ~/repos/dmfdeploy/dmf-env
bin/run-playbook.sh hetzner-arm \
  ../dmf-infra/k3s-lab-bootstrap/lifecycle-provision.yml \
  --tags nmos-cpp
```

**What this playbook does:**
1. Connects to `k3s_control[0]` via SSH
2. Runs the `nmos-cpp` role (`dmf-media/roles/nmos-cpp/tasks/main.yml`)
3. Creates the `nmos` namespace (if not present)
4. Creates `nmos-registry-config` ConfigMap in `nmos` namespace
5. Creates `nmos-node-config` ConfigMap in `nmos` namespace
6. Does **NOT** create any Deployments, StatefulSets, or Services

**What this playbook does NOT do:**
- Deploy any workload
- Register NetBox `ipam.Service` (that happens in the configure-stage, Piece 5)
- Push or pull images

---

## Step 4: Verify provision state

### 4.1 Verify namespace and ConfigMaps (from control node)

```bash
ssh k3s-admin@<control-node-public-ip> << 'EOF'
echo "=== Namespace ==="
sudo k3s kubectl get namespace nmos -o wide

echo "=== ConfigMaps in nmos ==="
sudo k3s kubectl get configmaps -n nmos -l dmf.function=nmos-cpp -o wide

echo "=== Workloads in nmos (should be empty) ==="
sudo k3s kubectl get all -n nmos

echo "=== Registry ConfigMap content ==="
sudo k3s kubectl get configmap nmos-registry-config -n nmos -o yaml

echo "=== Node ConfigMap content ==="
sudo k3s kubectl get configmap nmos-node-config -n nmos -o yaml
EOF
```

**Expected results:**
- `nmos` namespace exists with labels `dmf.layer=5`, `dmf.function=nmos-cpp`
- Two ConfigMaps: `nmos-registry-config`, `nmos-node-config`
- **Zero** workloads (no pods, deployments, services, statefulsets)

### 4.2 Verify no workloads (the critical gate assertion)

```bash
ssh k3s-admin@<control-node-public-ip> "sudo k3s kubectl get all -n nmos --no-headers"
```

**Expected:** Empty output or "No resources found in nmos namespace."

If any workload exists, the provision/conflate boundary is broken — investigate which task deployed it and fix before proceeding.

### 4.3 Verify images in Zot (if pushed in Step 2)

```bash
# Query Zot API
curl -sk https://registry.dmf.example.com/v2/<operator>/nmos-cpp-registry/tags/list \
  -u <zot-admin-user>:<zot-admin-password>
# Expected: {"name":"<operator>/nmos-cpp-registry","tags":["0.1.0"]}

curl -sk https://registry.dmf.example.com/v2/<operator>/nmos-cpp-node/tags/list \
  -u <zot-admin-user>:<zot-admin-password>
# Expected: {"name":"<operator>/nmos-cpp-node","tags":["0.1.0"]}
```

---

## Step 5: NetBox service record

**Note:** The provision playbook does **NOT** create a NetBox `ipam.Service` record. That happens in Piece 5 (configure-side launch) when the workload is actually deployed. The provision stage only registers artifacts (namespace + ConfigMaps).

If you want to pre-create the NetBox record manually to validate the catalog flow:

```bash
# Get NetBox API token from OpenBao
bao kv get secret/apps/netbox/runtime

# Create ipam.Service record
curl -sk https://netbox.dmf.example.com/api/ipam/services/ \
  -H "Authorization: Token <netbox-api-token>" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "nmos-cpp",
    "protocol": "tcp",
    "port": 80,
    "tags": [
      {"name": "dmf"},
      {"name": "app:nmos-cpp"},
      {"name": "exposure:private"},
      {"name": "lifecycle:bootstrapped"}
    ]
  }'
```

**Expected:** `201 Created` response with the service object.

If the service already exists (from a prior run), you'll get `400` — that's fine for v1.

---

## Gate 1 success criteria

All of these must be true before proceeding to Piece 5:

- [ ] `nmos-cpp-registry:0.1.0` image built successfully on ARM64
- [ ] `nmos-cpp-node:0.1.0` image built successfully on ARM64
- [ ] Both images pushed to Zot (or push deferred with auth note)
- [ ] `nmos` namespace exists with correct labels
- [ ] Two ConfigMaps present: `nmos-registry-config`, `nmos-node-config`
- [ ] **Zero** workloads in `nmos` namespace (no pods, deployments, services)
- [ ] ConfigMap contents correct (registry.json has host/port/logging, node.json has registries array)

## Gate 1 failure modes

| Symptom | Likely cause | Investigation |
|---|---|---|
| Conan build fails | Dependency incompatibility on ARM64 | Check error log; fall back to Easy-NMOS (NVIDIA fork) per NMOS plan §A.6 |
| CMake target not found | Wrong NMOS_CPP_VERSION | `git ls-remote --tags https://github.com/sony/nmos-cpp` to find valid tag |
| Colima runs out of memory | Conan build is memory-intensive | Increase Colima RAM: `colima stop && colima start docker-build --memory 8` |
| Push to Zot fails | Auth not configured | Use Option B (defer push); Piece 5 will handle it via playbook |
| Workloads appear after provision | Role deploys something unexpectedly | Check `dmf-media/roles/nmos-cpp/tasks/main.yml` for unexpected resource creation |
| Namespace already exists | Prior failed run | `kubectl get namespace nmos` — inspect existing ConfigMaps before re-running |

## Post-gate: proceed to Piece 5

Once Gate 1 passes, the agent executing Piece 5 will:
1. Create `dmf-media/playbooks/configure-media/launch-nmos-cpp.yml` (deploys registry + nodes)
2. Create `dmf-media/playbooks/configure-media/teardown-nmos-cpp.yml` (removes workload)
3. Wire them into `lifecycle-configure.yml` via tags
4. Flip NetBox tag from `lifecycle:bootstrapped` to `lifecycle:active` on launch

---

## References

- Move 1 task spec: `docs/plans/dmf-platform-move-1-task-2026-05-04.md`
- NMOS plan (technical reference): `docs/plans/DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md`
- Catalog entry: `dmf-media/catalog/nmos-cpp.yaml`
- Build rules: `dmf-cms/docs/DEVELOPMENT-AND-BUILD-RULES.md`
- ADR-0012 (Configure vs Provision): `docs/decisions/0012-configure-stage-distinct-from-provision.md`
- ADR-0006 (Cluster is truth): `docs/decisions/0006-cluster-is-truth.md`
- Handoff: `docs/handoffs/DMF Function Catalog + Move 1 Planning Handoff 2026-05-04.md`
