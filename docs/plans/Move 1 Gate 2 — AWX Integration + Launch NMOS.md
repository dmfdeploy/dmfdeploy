---
status: superseded
date: 2026-05-04
superseded_by: "Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md"
---
# Move 1 Gate 2 — Run 693-awx-integration + Launch from AWX UI
> **Superseded by** [Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md](Move%201%20Gate%202%20-%20Pivot%20to%20Path%20A%20for%20Catalog%20Launchers%202026-05-06.md) — see frontmatter.

> **SUPERSEDED 2026-05-23** by ADR-0025 Lane B. `media-launch-nmos-cpp`
> now runs in-cluster via the AWX EE pod + Helm chart, not Path A control-node SSH.
>
> **GATE PASSED 2026-05-06** via the Path A pivot. The original SA-mount approach
> documented below was abandoned; final execution model was Path A (control-node SSH
> via OpenBao, ADR-0016). See [`Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md`](Move%201%20Gate%202%20-%20Pivot%20to%20Path%20A%20for%20Catalog%20Launchers%202026-05-06.md)
> for what shipped. AWX job 285 (`media-launch-nmos-cpp`) succeeded end-to-end.
>
> **2026-05-19 re-pivot for catalog launchers.** Path A is fully superseded
> for `media-*` JTs by [ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md)
> and the [Cluster-Internal Ansible Execution + Catalog Helm Pivot Plan 2026-05-19](./DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md).
> Path A remains canonical for 693-class infrastructure plays.

**Date:** 2026-05-05
**Type:** Execution gate (human-verified checkpoint between Piece 6 and Piece 7)
**Purpose:** Run the 693 playbook to push launchers to Forgejo, create AWX projects + job templates, then launch `media-launch-nmos-cpp` from the AWX UI and verify the workload is up.

---

## Context

This gate sits between Piece 6 (AWX job templates + dmf-runbooks) and Piece 7 (dmf-cms catalog page). The goal is to prove that:

1. The 693 playbook pushes dmf-runbooks thin launchers to in-cluster Forgejo
2. AWX projects are created for dmf-runbooks, dmf-media, dmf-infra
3. AWX job templates `media-launch-nmos-cpp` and `media-finalise-nmos-cpp` exist
4. Launching `media-launch-nmos-cpp` from the AWX UI deploys the NMOS registry + mock nodes
5. NetBox tag flips from `lifecycle:bootstrapped` to `lifecycle:active`

If any of these fail, stop and investigate before proceeding to Piece 7.

---

## Architecture reference

- Task spec: `docs/plans/dmf-platform-move-1-task-2026-05-04.md` — Pieces 5, 6
- ADR-0012 (Configure vs Provision): `docs/decisions/0012-configure-stage-distinct-from-provision.md`
- ADR-0013 (Media function catalog model): `docs/decisions/0013-media-function-catalog-model.md`
- ADR-0014 (AWX project layout): `docs/decisions/0014-awx-project-layout.md`
- Gate 1 results: `docs/plans/Move 1 Gate 1 — Build NMOS + Run Provision.md`

---

## Pre-flight checks

### 1. Gate 1 must have passed

- [ ] `nmos` namespace exists
- [ ] ConfigMaps present: `nmos-registry-config`, `nmos-node-config`
- [ ] Zero workloads in `nmos` namespace
- [ ] NetBox `ipam.Service` named `nmos-cpp` with `lifecycle:bootstrapped` tag
- [ ] NMOS images in Zot: `nmos-cpp-registry:0.1.0`, `nmos-cpp-node:0.1.0`

### 2. SSH access to control node

```bash
ssh k3s-admin@<control-node-public-ip> "sudo k3s kubectl version --short"
```

### 3. Clean git state in affected repos

```bash
cd ~/repos/dmfdeploy/dmf-infra && git status
```

No uncommitted changes should block the playbook run.

### 4. Forgejo reachable

```bash
curl -sk https://forgejo.dmf.example.com/api/v1/repos/forgejo-svc/dmf-runbooks
# Expected: 404 (repo not yet created) or 200 (already exists)
```

### 5. AWX reachable

```bash
curl -sk https://awx.dmf.example.com/api/v2/ping/
# Expected: {"version": "...", "active_node": "...", ...}
```

---

## Step 1: Run 693-awx-integration playbook

```bash
cd ~/repos/dmfdeploy/dmf-env
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/
```

**What this playbook does (relevant catalog pieces):**

1. **Pushes thin launchers to Forgejo** — `playbooks/runbooks/media-launch-nmos-cpp.yml` and `media-finalise-nmos-cpp.yml` are pushed to `forgejo-svc/dmf-runbooks` repo
2. **Creates AWX projects** — `dmf-runbooks`, `dmf-media`, `dmf-infra` with correct SCM URLs pointing at in-cluster Forgejo
3. **Sets GIT_SSL_NO_VERIFY** on all AWX projects (lab CA is self-signed)
4. **Creates AWX job templates** — `media-launch-nmos-cpp` and `media-finalise-nmos-cpp` pointing at the dmf-runbooks project

**What this playbook does NOT do:**
- Run any playbooks against the cluster
- Deploy any workloads
- Modify NetBox records directly

---

## Step 2: Verify Forgejo has dmf-runbooks repo

```bash
curl -sk https://forgejo.dmf.example.com/api/v1/repos/forgejo-svc/dmf-runbooks
# Expected: 200 OK with repo info
```

Check that playbooks exist:

```bash
# Check launch playbook
curl -sk https://forgejo.dmf.example.com/api/v1/repos/forgejo-svc/dmf-runbooks/contents/playbooks/launch-nmos-cpp.yml
# Expected: 200 OK with file metadata

# Check teardown playbook
curl -sk https://forgejo.dmf.example.com/api/v1/repos/forgejo-svc/dmf-runbooks/contents/playbooks/teardown-nmos-cpp.yml
# Expected: 200 OK with file metadata
```

---

## Step 3: Verify AWX projects exist

Navigate to **Resources → Projects** in the AWX UI and confirm:

- **dmf-runbooks** — SCM URL pointing at Forgejo, sync status = successful
- **dmf-media** — SCM URL pointing at Forgejo, sync status = successful
- **dmf-infra** — SCM URL pointing at Forgejo, sync status = successful

Or via API:

```bash
# Login to AWX first
export AWX_HOST="https://awx.dmf.example.com"
export AWX_ADMIN="awx-local-admin"
export AWX_PASSWORD="<get-from-openbao>"

curl -sk "${AWX_HOST}/api/v2/projects/?name=dmf-runbooks" \
  -u "${AWX_ADMIN}:${AWX_PASSWORD}" | jq '.results[].name'

curl -sk "${AWX_HOST}/api/v2/projects/?name=dmf-media" \
  -u "${AWX_ADMIN}:${AWX_PASSWORD}" | jq '.results[].name'

curl -sk "${AWX_HOST}/api/v2/projects/?name=dmf-infra" \
  -u "${AWX_ADMIN}:${AWX_PASSWORD}" | jq '.results[].name'
```

---

## Step 4: Verify AWX job templates exist

Navigate to **Resources → Templates** in the AWX UI and confirm:

- **media-launch-nmos-cpp** — project = dmf-runbooks, playbook = `playbooks/launch-nmos-cpp.yml`
- **media-finalise-nmos-cpp** — project = dmf-runbooks, playbook = `playbooks/teardown-nmos-cpp.yml`

Or via API:

```bash
curl -sk "${AWX_HOST}/api/v2/job_templates/?name=media-launch-nmos-cpp" \
  -u "${AWX_ADMIN}:${AWX_PASSWORD}" | jq '.results[0].name, .results[0].playbook'

curl -sk "${AWX_HOST}/api/v2/job_templates/?name=media-finalise-nmos-cpp" \
  -u "${AWX_ADMIN}:${AWX_PASSWORD}" | jq '.results[0].name, .results[0].playbook'
```

---

## Step 5: Launch `media-launch-nmos-cpp` from AWX UI

1. Open AWX UI → Resources → Templates → **media-launch-nmos-cpp**
2. Click **Launch** (rocket icon)
3. Watch the job output — it should:
   - Include the `nmos-cpp` role (configure stage)
   - Create PVC, StatefulSet, Services, Deployments
   - Flip NetBox tag to `lifecycle:active`
   - Report endpoint at the end

**Expected job output (key lines):**

```
PLAY [NMOS-CPP configure — launch workloads] ...

TASK [Include nmos-cpp role (configure stage)] ...

TASK [nmos-cpp : Ensure registry PVC exists] ...
TASK [nmos-cpp : Deploy registry StatefulSet] ...
TASK [nmos-cpp : Deploy registry Service] ...
TASK [nmos-cpp : Deploy node workloads] ... (2 items)
TASK [nmos-cpp : Deploy node Services] ... (2 items)
TASK [nmos-cpp : Ensure health probe ConfigMap exists] ...
TASK [nmos-cpp : Flip NetBox tag to lifecycle:active] ...

PLAY RECAP: ok=10 changed=8 unreachable=0 failed=0
```

---

## Step 6: Verify workload state

### 6.1 Check workloads are running

```bash
ssh k3s-admin@<control-node-public-ip> << 'EOF'
echo "=== All resources in nmos namespace ==="
sudo k3s kubectl get all -n nmos

echo "=== PVC status ==="
sudo k3s kubectl get pvc -n nmos

echo "=== Pod status ==="
sudo k3s kubectl get pods -n nmos -o wide

echo "=== Service endpoints ==="
sudo k3s kubectl get svc -n nmos

echo "=== ConfigMaps ==="
sudo k3s kubectl get configmap -n nmos
EOF
```

**Expected results:**

| Resource | Name | Status |
|---|---|---|
| PVC | `nmos-registry-data` | Bound |
| StatefulSet | `nmos-cpp-registry` | 1/1 ready |
| Service | `nmos-cpp-registry` | ClusterIP, port 80 |
| Deployment | `nmos-cpp-node-1` | 1/1 ready |
| Deployment | `nmos-cpp-node-2` | 1/1 ready |
| Service | `nmos-cpp-node-1` | ClusterIP, port 80 |
| Service | `nmos-cpp-node-2` | ClusterIP, port 80 |
| ConfigMap | `nmos-health-probe` | present |

### 6.2 Verify registry is responding

```bash
ssh k3s-admin@<control-node-public-ip> << 'EOF'
# Test registry health endpoint from within the cluster
sudo k3s kubectl exec -n nmos deploy/nmos-cpp-node-1 -- \
  wget -qO- http://nmos-cpp-registry.nmos.svc.cluster.local/x-nmos/query/v1.3/nodes/ 2>&1 | head -20
EOF
```

**Expected:** HTTP 200 response, JSON with nodes array (empty initially, or with registered nodes).

### 6.3 Verify NetBox tag flip

```bash
curl -sk "https://netbox.dmf.example.com/api/ipam/services/?name=nmos-cpp" \
  -H "Authorization: Token <netbox-api-token>" | jq '.results[0].tags'
```

**Expected:** Tags include `lifecycle:active` (NOT `lifecycle:bootstrapped`).

### 6.4 Verify health probe ConfigMap

```bash
ssh k3s-admin@<control-node-public-ip> << 'EOF'
sudo k3s kubectl get configmap nmos-health-probe -n nmos -o yaml
EOF
```

**Expected:** `data.path: /x-nmos/query/v1.3/nodes/`, `data.expect_status: "200"`, `data.kind: "http"`.

---

## Gate 2 success criteria

All of these must be true before proceeding to Piece 7:

- [ ] `dmf-runbooks` repo exists in Forgejo with both playbooks
- [ ] AWX projects: `dmf-runbooks`, `dmf-media`, `dmf-infra` all synced
- [ ] AWX job templates: `media-launch-nmos-cpp`, `media-finalise-nmos-cpp` exist
- [ ] `media-launch-nmos-cpp` job ran successfully from AWX UI
- [ ] Registry StatefulSet running (1/1 ready)
- [ ] Node Deployments running (2/2 ready)
- [ ] Services created and reachable
- [ ] NetBox tag flipped to `lifecycle:active`
- [ ] Health probe ConfigMap present

---

## Gate 2 failure modes

| Symptom | Likely cause | Investigation |
|---|---|---|
| Forgejo repo creation fails | `forgejo-svc` user token missing | Check `691-netbox-sot.yml` ran first; verify token in OpenBao |
| AWX project sync fails | Git SSL cert error | Check GIT_SSL_NO_VERIFY env var set on project |
| AWX job template creation fails | dmf-runbooks project not found | Check project creation order in awx-integration tasks (projects before templates) |
| NMOS launch fails — image pull error | Images not in Zot | Verify Step 2 from Gate 1 (image push); check Zot repo listing |
| NMOS launch fails — PVC not bound | Storage class issue | `kubectl get storageclass`; check local-path-provisioner |
| NMOS launch fails — readiness probe | Registry not starting | `kubectl logs deploy/nmos-cpp-registry -n nmos` |
| NetBox tag flip fails | Service record not found | Check `ipam.Service` was created in Gate 1; verify name matches |
| AWX project sync stuck | SCM credential invalid | Check `awx_catalog_project_ids` fact is populated before job template creation |

---

## Post-gate: teardown test (optional but recommended)

After Gate 2 passes, test the teardown flow:

1. AWX UI → Templates → **media-finalise-nmos-cpp** → Launch
2. Verify workloads removed: `kubectl get all -n nmos` (should show only ConfigMaps, PVC)
3. Verify NetBox tag reset: `lifecycle:bootstrapped` (NOT `lifecycle:active`)

This proves the full lifecycle loop works before adding the catalog UI layer (Piece 7).

---

## Post-gate: proceed to Piece 7

Once Gate 2 passes, the agent executing Piece 7 will:
1. Read existing dmf-cms patterns and components
2. Create a catalog page component that reads from a ConfigMap (v1)
3. Render catalog entries as a table/grid with status indicators
4. Wire to the `nmos-cpp` catalog entry from Piece 1

---

## References

- Move 1 task spec: `docs/plans/dmf-platform-move-1-task-2026-05-04.md`
- NMOS plan (technical reference): `docs/plans/DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md`
- Catalog entry: `dmf-media/catalog/nmos-cpp.yaml`
- ADR-0012 (Configure vs Provision): `docs/decisions/0012-configure-stage-distinct-from-provision.md`
- ADR-0013 (Media function catalog model): `docs/decisions/0013-media-function-catalog-model.md`
- ADR-0014 (AWX project layout): `docs/decisions/0014-awx-project-layout.md`
- Handoff: `docs/handoffs/DMF Function Catalog + Move 1 Planning Handoff 2026-05-04.md`
