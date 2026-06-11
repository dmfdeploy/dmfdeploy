---
status: executed
date: 2026-05-22
executed: 2026-05-23
---
# DMF ADR-0025 Lane B Implementation Plan

**Date:** 2026-05-22
**Authors:** Claude (Opus 4.7) + codex (gpt-5.5 xhigh) synthesis
**Status:** Approved by operator — assigned to codex (pane 3) for implementation
**Scope:** Move 5 of the 2026-05-22 forward plan. Closes the
decision-to-code gap for Lane B of the convergence plan
(`docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`).

## Context

ADR-0025 (Proposed, 2026-05-19) documents the architectural shift to
in-cluster Ansible execution with catalog functions deploying as Helm
charts. Lane A (shared EE image + Stage 4b infrastructure) largely
landed 2026-05-19 (four DMF images on GHCR). Lane C (runner-pod
Phases 2–4) is independent and tracked separately. **Lane B — the
catalog-launcher half — is not yet implemented.** Code still SSHes to
the control node with a hardcoded Hetzner private-IP map.

**Why now:** g2r6-foa9 bootstrapped green end-to-end on 2026-05-22. The
hardcoded Hetzner private-IP map at
`dmf-runbooks/playbooks/launch-nmos-cpp.yml:28-34` is a per-env
band-aid that will break on every new cloud. Lane B deletes the
band-aid by removing the SSH hop entirely; NMOS-cpp deploys as a Helm
chart from an in-cluster AWX EE pod.

**Trigger reference:** AWX job 44 on `aliyun-123` (2026-05-17),
`media-launch-nmos-cpp`, `UNREACHABLE!` at "Fetch existing NetBox tags."

**After Lane B verifies:** ADR-0025 promotes Proposed→Accepted;
ADR-0016 promotes partial-supersession→full-supersession **for
`media-*` JTs only** (693-class infra plays keep Path A).

## Operator decisions (locked 2026-05-22)

1. **Chart distribution:** GHCR canonical + Stage 4b mirror. New
   umbrella `bin/publish-chart-to-ghcr.sh` symmetric with
   `bin/publish-image-to-ghcr.sh`. Stage 4b mirrors via skopeo, same
   pattern as images.
2. **AWX-integration hygiene:** Folded into Lane B PR. Duplicate
   OpenBao SSH-key read at
   `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml:1271-1290`
   gets removed in the same refactor that adds EE registration +
   Container Group wiring.
3. **Retirement scope:** Final phase of the same Lane B PR. ADR-0025
   promoted, ADR-0016 amended, superseded plans archived, stale TODOs
   cleared. One handoff closes the whole story.

Also already-answered (from ADR-0025 plan §8, batch 2026-05-19):
- §8.1 Stage 4b mechanism: workstation Ansible playbook (`630-zot-seed-platform.yml`).
- §8.6 Zot anonymous read on `dmf/*`: yes.
- §8.7 AWX pod placement: **(b) SA-in-target-namespace + Container Group with namespace override.**

## Pre-flight (Move 1 dependencies)

Before Lane B implementation starts, the implementer MUST:

1. **Park dirty g2r6-foa9 bundle.** `dmf-env` has 4 uncommitted files
   (`.sops.yaml`, `inventories/g2r6-foa9/`, `manifests/g2r6-foa9.yaml`).
   Commit with subject `chore(g2r6-foa9): commit wizard bundle` ONLY
   if operator authorizes; otherwise stash with
   `git stash push -m 'g2r6-foa9 bundle pre-Lane-B'`. Do NOT modify
   or discard the bundle.
2. **Push unpushed clean commits** in `dmf-cms` (2), `dmf-central` (1),
   `dmf-media` (1) — confirmed clean per STATUS; operator authorizes
   push.
3. **Refresh STATUS.md** via `bin/generate-status.sh` to baseline.

These are not Lane B work; they establish a trustworthy baseline.
Skipping them risks Lane B PR conflicting with in-flight state.

---

## Phase 1 — Helm chart at `dmf-media/charts/nmos-cpp/`

**Goal:** lift all k8s manifests out of the Ansible role into a Helm
chart. Chart deploys equivalently to current behavior.

**Files to create:**
- `dmf-media/charts/nmos-cpp/Chart.yaml` — `apiVersion: v2`,
  `name: nmos-cpp`, `version: 0.1.0`, `appVersion: 0.1.0`, type
  `application`, kubeVersion `>=1.28.0-0`. Description references
  ADR-0025.
- `dmf-media/charts/nmos-cpp/values.yaml` — surface the role's existing
  templated values (read from `dmf-runbooks/roles/nmos-cpp/defaults/main.yml`):
  - `namespace: nmos`
  - `registry.image.repository: registry.dmf.example.com/dmf/nmos-cpp-registry`
  - `registry.image.tag: "0.1.0"`
  - `registry.image.pullPolicy: Always`
  - `registry.resources.{requests,limits}` mirroring current values
    (128Mi/100m request, 256Mi/500m limit)
  - `node.image.repository: registry.dmf.example.com/dmf/nmos-cpp-node`
  - `node.image.tag: "0.1.0"`
  - `node.count: 2`
  - `node.labels: { "1": "nmos-mock-node-1", "2": "nmos-mock-node-2" }`
  - `node.resources.{requests,limits}` mirroring current values
    (64Mi/50m request, 128Mi/250m limit)
  - `nmosConfig.httpPort: 80`
  - `nmosConfig.serverAddress: "0.0.0.0"`
  - `nmosConfig.loggingLevel: 0`
  - `nmosConfig.registryAddress: "nmos-cpp-registry.{{ .Values.namespace }}.svc.cluster.local"`
  - `createNamespace: true`
- `dmf-media/charts/nmos-cpp/templates/_helpers.tpl` — standard
  fullname/labels helpers; `nmosLabels` includes
  `dmf.function: nmos-cpp`.
- `dmf-media/charts/nmos-cpp/templates/namespace.yaml` — gated by
  `.Values.createNamespace`; labels `dmf.layer: "5"`,
  `dmf.function: nmos-cpp`.
- `dmf-media/charts/nmos-cpp/templates/configmap-registry.yaml` — lifts
  `roles/nmos-cpp/tasks/provision.yml:129-152` `nmos-registry-config`.
- `dmf-media/charts/nmos-cpp/templates/configmap-node.yaml` — lifts
  `provision.yml:154-181` per-node `nmos-node-config-{N}` ConfigMaps,
  using `range` over `.Values.node.labels` (preserves key→label mapping).
- `dmf-media/charts/nmos-cpp/templates/configmap-health-probe.yaml` —
  lifts `configure.yml:198-214` `nmos-health-probe`.
- `dmf-media/charts/nmos-cpp/templates/pvc-registry.yaml` — lifts
  `configure.yml:7-24`.
- `dmf-media/charts/nmos-cpp/templates/statefulset-registry.yaml` —
  lifts `configure.yml:27-92`.
- `dmf-media/charts/nmos-cpp/templates/service-registry.yaml` — lifts
  `configure.yml:95-115`.
- `dmf-media/charts/nmos-cpp/templates/deployment-node.yaml` — one
  Deployment, `range $i, $label := .Values.node.labels` (preserves
  numeric key for naming + ConfigMap reference). Lifts `configure.yml:118-172`.
- `dmf-media/charts/nmos-cpp/templates/service-node.yaml` — `range` per
  node, lifts `configure.yml:175-196`.
- `dmf-media/charts/nmos-cpp/.helmignore` — standard.
- `dmf-media/charts/nmos-cpp/README.md` — purpose, values reference,
  install example. Three paragraphs max.

**Pattern reference for chart shape:** `dmf-cms/charts/dmf-cms/` and
`dmf-infra/k3s-lab-bootstrap/charts/netbox/`. Do NOT introduce a new
chart style; mirror dmf-cms.

**Verification gate (Phase 1):**
- `helm lint dmf-media/charts/nmos-cpp/` → no errors.
- `helm template nmos-cpp dmf-media/charts/nmos-cpp/ --namespace nmos`
  → renders without error. Diff resulting manifests against current
  role output (extract via `ansible-playbook --check --diff` against
  the existing role on a scratch namespace) — equivalence within
  trivial label/annotation drift.
- `helm install --dry-run --debug nmos-cpp dmf-media/charts/nmos-cpp/
  --namespace nmos --create-namespace` → all resources visible.

**Commit:** `feat(charts/nmos-cpp): initial Helm chart for ADR-0025
Lane B` in `dmf-media`.

---

## Phase 2 — Chart publish pipeline

**Goal:** GHCR-canonical chart artifact + symmetric publish script.

**Files to create / modify:**
- `dmfdeploy/bin/publish-chart-to-ghcr.sh` — new. Mirrors
  `bin/publish-image-to-ghcr.sh` ergonomics (token via stdin, isolated
  HELM_REGISTRY_CONFIG, cleanup trap, ADR-0007 compliant). Usage:
  `publish-chart-to-ghcr.sh <chart-dir> <ghcr-repo>` →
  `helm package` → `helm registry login ghcr.io` → `helm push <.tgz>
  oci://ghcr.io/dmfdeploy/charts`.
- `dmf-media/bin/publish-chart-to-ghcr.sh` — thin wrapper that delegates
  to the umbrella script for `dmf-media/charts/nmos-cpp/`. Mirrors the
  per-repo `publish-to-ghcr.sh` pattern established for NMOS images +
  AWX EE.

**Then execute (operator runs, not implementer):**
- `bin/publish-chart-to-ghcr.sh dmf-media/charts/nmos-cpp ghcr.io/dmfdeploy/charts/nmos-cpp`
- Confirms chart is public at
  `oci://ghcr.io/dmfdeploy/charts/nmos-cpp:0.1.0`.

**Verification gate (Phase 2):**
- `helm pull oci://ghcr.io/dmfdeploy/charts/nmos-cpp --version 0.1.0`
  from a clean workstation succeeds.
- Public visibility verified: anonymous pull from empty
  `HELM_REGISTRY_CONFIG`.

**Commit:** `feat(bin): publish-chart-to-ghcr.sh for ADR-0025 Lane B`
in `dmfdeploy` umbrella; mirror in `dmf-media`.

---

## Phase 3 — Stage 4b extension

**Goal:** NMOS images + chart land in cluster-internal Zot on fresh
bootstrap.

**File to modify:**
- `dmf-infra/k3s-lab-bootstrap/playbooks/630-zot-seed-platform.yml` —
  extend the `zot_seed_images` loop variable (currently 2 entries:
  awx-ee, dmf-cms) with two new image rows:
  - `nmos-cpp-registry` → `dmf/nmos-cpp-registry`, tag from new var.
  - `nmos-cpp-node` → `dmf/nmos-cpp-node`, tag from new var.
- Add a new `zot_seed_charts` loop block in the same playbook. Reuses
  the existing skopeo+authfile pattern (skopeo handles OCI Helm chart
  artifacts identically to images). One row:
  - `nmos-cpp` chart → `oci://ghcr.io/dmfdeploy/charts/nmos-cpp:0.1.0`
    → `zot.zot.svc.cluster.local:5000/dmf/charts/nmos-cpp:0.1.0`.

**Files to update (variable plumbing):**
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml`
  — add:
  ```yaml
  nmos_cpp_registry_image: "registry.dmf.example.com/dmf/nmos-cpp-registry"
  nmos_cpp_registry_tag: "0.1.0"
  nmos_cpp_node_image: "registry.dmf.example.com/dmf/nmos-cpp-node"
  nmos_cpp_node_tag: "0.1.0"
  nmos_cpp_chart_repo: "oci://zot.zot.svc.cluster.local:5000/dmf/charts"
  nmos_cpp_chart_name: "nmos-cpp"
  nmos_cpp_chart_version: "0.1.0"
  ```
  (Comments note: defaults reference Zot URLs; source-of-truth tags
  match GHCR pushes.)

**Verification gate (Phase 3):**
- On g2r6-foa9, manual re-run:
  `bin/run-playbook.sh g2r6-foa9 ../dmf-infra/k3s-lab-bootstrap/playbooks/630-zot-seed-platform.yml`
- Idempotent (HEAD-check shortcut for already-mirrored images).
- Zot UI / CLI: `oras repo list zot.zot.svc.cluster.local:5000` shows
  `dmf/nmos-cpp-registry`, `dmf/nmos-cpp-node`, `dmf/charts/nmos-cpp`.

**Commit:** `feat(630-zot-seed-platform): seed NMOS images + chart for
ADR-0025 Lane B` in `dmf-infra`.

---

## Phase 4 — AWX integration: Container Group + EE + JT pinning + hygiene

**Goal:** AWX-spawned `media-*` JT pods run in `nmos` namespace under
`nmos-cpp-launcher` SA, using the DMF EE image from Zot. Duplicate
OpenBao SSH-key read removed.

**File to modify (large refactor):**
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml`

### 4a — Namespace + RBAC pre-creation

Add a task block (before AWX API calls) that creates `nmos` namespace,
SA `nmos-cpp-launcher`, Role + RoleBinding granting CRUD on
Deployments, Services, ConfigMaps, PVCs, StatefulSets in the `nmos`
namespace. Use `kubernetes.core.k8s`; ADR-0007 compliant (no creds in
argv).

Pattern reference: dmf-cms RBAC creation in the same role (search
codebase for existing `kind: RoleBinding` blocks).

### 4b — Custom EE registration

Add task: POST `/api/v2/execution_environments/` with:
- `name: "{{ awx_ee_catalog_display_name }}"`
- `image: "{{ awx_ee_catalog_image }}:{{ awx_ee_catalog_tag }}"`
  → resolves to `registry.dmf.example.com/dmf/awx-ee:0.1.0` per defaults.
- `pull: missing` (so Zot is queried only when image not cached).
- Credential: none (Zot anonymous read on `dmf/*` per §8.6).

Register response ID as `awx_dmf_ee_id` (fact).

### 4c — Container Group creation

Add task: POST `/api/v2/instance_groups/` with:
- `name: "dmf-catalog-cg"`
- `is_container_group: true`
- `pod_spec_override: |`
  ```yaml
  apiVersion: v1
  kind: Pod
  metadata:
    namespace: nmos
  spec:
    serviceAccountName: nmos-cpp-launcher
    containers:
      - name: worker
        image: "{{ awx_ee_catalog_image }}:{{ awx_ee_catalog_tag }}"
        # rest of pod spec from AWX defaults
  ```
- Register response ID as `awx_dmf_catalog_cg_id`.

Note: per §8.7 decision (b), the Container Group's pod_spec sets
`metadata.namespace: nmos`. Future media functions either share this
CG (if same SA works) or get their own (one CG per namespace).

### 4d — Catalog JT pinning

Modify existing catalog JT creation block (currently ~lines 1083-1117,
verify line refs at execution time) to set:
- `execution_environment: "{{ awx_dmf_ee_id }}"` (was `awx_default_ee_id`)
- `instance_groups: ["{{ awx_dmf_catalog_cg_id }}"]` (new field)

Both `media-launch-nmos-cpp` and `media-finalise-nmos-cpp` JTs pinned.

### 4e — Hygiene: remove duplicate OpenBao SSH-key read

Delete lines 1271-1290 (`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml`).
The earlier block at 1249-1269 is canonical. Implementer must verify
after edit that only ONE `name: Read AWX control-node SSH privkey from
OpenBao` task remains. The `failed_when: false` from the canonical
version stays (Path A is still valid for 693-class — the SSH credential
remains needed for those JTs).

### 4f — Defaults update

`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml`:
- Add `awx_dmf_catalog_cg_display_name: "DMF Catalog Container Group"`.
- Document the new pinning fields with a comment block above
  `awx_ee_catalog_*` referencing ADR-0025 §8.7(b).

**Verification gate (Phase 4):**
- On g2r6-foa9, re-run the awx-integration role.
- AWX UI shows the DMF EE registered, the Container Group present, and
  both `media-*` JTs pinned to both.
- Single `Read AWX control-node SSH privkey from OpenBao` task remains
  in main.yml (grep + assert in implementer's reply).
- `bin/run-playbook.sh g2r6-foa9 ../dmf-infra/k3s-lab-bootstrap/playbooks/693-awx-integration.yml`
  is idempotent.

**Commit:** `feat(awx-integration): EE registration + Container Group
for ADR-0025 Lane B; remove duplicate OpenBao SSH read` in `dmf-infra`.

---

## Phase 5 — Launcher + role rewrite

**Goal:** Launcher targets localhost; role does NetBox only; chart
owns all k8s.

### 5a — Rewrite `dmf-runbooks/playbooks/launch-nmos-cpp.yml`

Replace entire file content. New shape:

```yaml
---
# NMOS IS-04/05 — Configure: Launch (ADR-0012, ADR-0014, ADR-0025)
# Runs in-cluster via custom AWX EE (Container Group dmf-catalog-cg).
# Deploys NMOS Helm chart + flips NetBox tag.
- name: NMOS-CPP configure — launch workloads
  hosts: localhost
  connection: local
  gather_facts: false
  tasks:
    - name: Include nmos-cpp role (provision stage — NetBox catalog entry)
      ansible.builtin.include_role:
        name: nmos-cpp
      vars:
        nmos_stage: provision

    - name: Deploy NMOS Helm chart from Zot
      kubernetes.core.helm:
        name: nmos-cpp
        chart_ref: "{{ nmos_cpp_chart_repo }}/{{ nmos_cpp_chart_name }}"
        chart_version: "{{ nmos_cpp_chart_version }}"
        release_namespace: "{{ nmos_namespace }}"
        create_namespace: false  # SA RBAC didn't grant namespace creation
        wait: true
        wait_timeout: 5m

    - name: Include nmos-cpp role (configure stage — flip NetBox tag to active)
      ansible.builtin.include_role:
        name: nmos-cpp
      vars:
        nmos_stage: configure
```

**Deletes:**
- Hardcoded Hetzner private-IP `set_fact` block (current lines 28-34).
- TODO comment about `k3s_node_ip` custom field (current lines 22-27)
  — obsolete; no SSH, no per-host IP override.
- `hosts: device_roles_k3s-control-plane[0]`, `become: true`,
  `environment: KUBECONFIG` — all Path A artifacts.

### 5b — Rewrite `dmf-runbooks/playbooks/teardown-nmos-cpp.yml`

Symmetric: `hosts: localhost`, `connection: local`. Calls
`kubernetes.core.helm` with `state: absent`, then includes nmos-cpp
role with `nmos_stage: finalise` for NetBox tag flip back.

### 5c — Slim `dmf-runbooks/roles/nmos-cpp/tasks/configure.yml`

Delete lines 7-214 (all `kubernetes.core.k8s` tasks). Keep lines 217-268
(NetBox tag-flip block + report).

### 5d — Slim `dmf-runbooks/roles/nmos-cpp/tasks/provision.yml`

Delete lines 117-181 (Namespace + ConfigMap creation; chart owns these
now). Keep lines 1-115 (NetBox tag taxonomy + service registration).

### 5e — Slim `dmf-runbooks/roles/nmos-cpp/tasks/finalise.yml`

Delete lines 7-48 (k8s delete tasks). Keep lines 50-101 (NetBox tag
flip back + report). The `helm uninstall` now runs in
`teardown-nmos-cpp.yml`, not the role.

### 5f — Update `dmf-runbooks/roles/nmos-cpp/defaults/main.yml`

Variables that mapped to k8s manifest fields (resource limits, image
refs at the role level, node labels) are now ONLY consumed by the
chart. Drop the duplicated defaults that no longer have a consumer at
role level:
- `nmos_registry_image`, `nmos_node_image` — move to chart values.yaml
  (already there per Phase 1); remove from role defaults UNLESS some
  other consumer references them (implementer must grep first; preserve
  any remaining references).
- `nmos_node_count`, `nmos_node_labels`, `nmos_http_port`,
  `nmos_server_address`, `nmos_logging_level`, `nmos_registry_address`
  — same check; remove if grep returns only the chart consumer.
- Keep `nmos_namespace` — used by the launcher to pass through to
  `release_namespace`.
- Keep all `netbox_*` variables — still consumed by role.

**Verification gate (Phase 5):**
- `ansible-lint dmf-runbooks/playbooks/launch-nmos-cpp.yml` → no errors.
- Role `tasks/main.yml` dispatcher still works for provision/configure/finalise.
- `grep -rn 'ansible_host' dmf-runbooks/playbooks/launch-nmos-cpp.yml`
  → no matches.

**Commit:** `feat(launch-nmos-cpp): in-cluster Helm execution for
ADR-0025 Lane B` in `dmf-runbooks`.

---

## Phase 6 — End-to-end verification on g2r6-foa9

Implementer runs (or operator runs and reports back):

1. `bin/run-playbook.sh g2r6-foa9
   ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml` →
   `failed=0`. Re-runs Stage 4b (seeds new NMOS images + chart) and
   Phase 4 (AWX integration creates EE + CG + pins JTs).
2. From dmf-cms UI catalog page, trigger `media-launch-nmos-cpp`. Job
   succeeds.
3. Verify checks (each is a single `kubectl` or `helm` command;
   implementer must report actual output back, not just a checkmark):
   - `kubectl -n awx get pod -l job_id=<id> -o yaml | grep -E
     'serviceAccountName|namespace:|image:'`
     → Pod runs in `nmos` namespace, `serviceAccountName:
     nmos-cpp-launcher`, image is the Zot URL (not quay.io).
   - `helm list -n nmos` → `nmos-cpp` release at chart version `0.1.0`.
   - `kubectl -n nmos get statefulset,deployment,svc,configmap,pvc`
     → matches expected count: 1 STS, 2 Deps, 3 Svcs, 4 CMs, 1 PVC.
   - `curl -k https://<g2r6-foa9-ingress>/api/catalog/nmos-cpp` →
     `lifecycle: active` in NetBox.
   - `kubectl -n nmos exec deploy/nmos-cpp-node-1 -- curl -s
     http://nmos-cpp-registry/x-nmos/query/v1.3/nodes/` → 200 OK with
     registered nodes.
4. Run `media-finalise-nmos-cpp`. Helm release removed; NetBox tag flips
   to `lifecycle:bootstrapped`. Namespace + image refs preserved.
5. Re-run `media-launch-nmos-cpp`. Same end state; idempotent.

**Verification gate (Phase 6):** all 5 checks PASS. Implementer captures
outputs in the handoff doc.

---

### Phase 6 amendment (2026-05-23) — containerd image-pull DNS

**Finding during Phase 6 execution.** The original plan assumed pods
would pull EE / NMOS images from
`zot.zot.svc.cluster.local:5000/dmf/...` per ADR-0023 cluster-internal
service DNS. Two issues surfaced during live runs against g2r6-foa9:

1. **The role default `awx_ee_catalog_image` was the example placeholder
   `registry.dmf.example.com/dmf/awx-ee`** rather than the
   cluster-internal Zot URL. Fixed in `dmf-infra@efa9cd3` by aligning
   the three image defaults with the chart_repo pattern (which already
   correctly used internal DNS).

2. **The k3s nodes had no `/etc/rancher/k3s/registries.yaml` or
   `certs.d/` containerd config**, so containerd defaulted to HTTPS
   when pulling `zot.zot.svc.cluster.local:5000`. Fixed in
   `dmf-infra@d0831cb` — added a task to the `base/k3s` role that
   creates
   `/var/lib/rancher/k3s/agent/etc/containerd/certs.d/zot.zot.svc.cluster.local:5000/hosts.toml`
   with plain-HTTP override on every node.

After both fixes, the pull still failed with
`dial tcp: lookup zot.zot.svc.cluster.local: no such host`.

**Root cause (the architectural finding):** containerd performs image
pulls in the **node's host network namespace**, before the pod exists.
It uses the node's `/etc/resolv.conf` (which points at the cloud
provider's public DNS), NOT cluster DNS. The `*.svc.cluster.local`
zone is only resolvable from inside the pod network via CoreDNS.
ADR-0023 ("cluster-internal service DNS, not public URLs") applies
correctly to **pod-to-pod HTTP wiring** (e.g. the helm chart pull
inside the EE pod, which DOES go via pod-network DNS), but NOT to
container image pull URLs that containerd processes on the node side.

**Resolution path (operator-locked 2026-05-23):** option (a) — **pin
Zot Service `clusterIP:` + node-side `/etc/hosts` entries**:

1. Zot Service spec sets `clusterIP:` to a fixed value (`10.43.165.105`
   on g2r6-foa9, the current allocation; pin to avoid drift on Service
   recreation).
2. A task in `base/k3s` writes `<pinned-clusterIP>
   zot.zot.svc.cluster.local` to `/etc/hosts` on every node, sourced
   from a `zot_cluster_ip` role variable.
3. Containerd's `certs.d/hosts.toml` provides the plain-HTTP override
   (already landed in `d0831cb`).

This is robust to single-node failure (every node has its own
`/etc/hosts` entry and its own kube-proxy; the ClusterIP routes via
local kube-proxy regardless of which node hosts the Zot pod). No
node-01 dependency. No MetalLB needed for this fix; MetalLB remains a
separate future workstream for the broader "expose apps on LAN" use
case.

Implementation commits land under Lane B (subjects suggested in the
dispatch). Phase 6 verification checks remain the same.

---

## Phase 7 — Retirement + ADR-0025 promotion (final phase, same PR)

This phase is gated on Phase 6 PASS. Implementer must NOT execute
Phase 7 before Phase 6 verifies.

### 7a — ADR-0025 promotion

`docs/decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md`:
replace the Proposed placeholder with full ADR text (Context /
Decision / Consequences / Alternatives / Enforcement). Status:
**Accepted**. Date: 2026-05-22. Includes the Phase 6 verification
outputs as the "implemented" evidence.

`docs/decisions/INDEX.md`: flip ADR-0025 from Proposed to Accepted.

### 7b — ADR-0016 amendment

`docs/decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md`:
extend the existing Amendment section. Add:
> **2026-05-22 — Fully superseded for `media-*` JTs (ADR-0025).**
> All catalog launchers now execute in-cluster via the AWX EE pod.
> SSH-to-control-node remains canonical for 693-class infra plays
> only. Removed Lane B band-aid at launch-nmos-cpp.yml:28-34.

### 7c — Plan supersession + archival

Each of the following plans gets a 2-line "SUPERSEDED 2026-05-22 by
Lane B implementation" banner inserted at the top (don't move/delete
the files — `docs/plans/` history is searchable):

- `docs/plans/Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md`
  — promote partial-supersession to full.
- `docs/plans/Move 1 Gate 2 — AWX Integration + Launch NMOS.md` — full.
- `docs/plans/Move 1 Gate 2 Fix - AWX EE Pod Service Account Mount.md`
  — full (the SA-mount work is now Container Group, not pod_spec_override fragment).
- `docs/plans/Move 1 Gate 2 — Trials and Tribulations 2026-05-05.md` —
  full.
- `docs/plans/DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md`
  — Phase 3 already noted superseded; extend to full.

**Do NOT supersede:**
- `DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`
  — this is the parent plan; Lane B closes ONE of its three lanes.
  Lane C still in flight. Mark Lane B as ✅ in §5; keep plan otherwise.
- `DMF In-Cluster Ansible Runner Pod Implementation Plan 2026-05-14.md`
  — Lane C plan; independent.

### 7d — Code retirement (no orphans)

Implementer grep-sweeps and either fixes or notes-in-PR:
- `grep -rn 'launch-nmos-cpp' dmf-runbooks/ dmf-infra/ dmf-media/` —
  every reference should be valid post-rewrite.
- `grep -rn 'Path A' dmf-runbooks/ dmf-infra/ dmf-media/` — every
  match must be either a qualified "693-class" reference or a
  historical reference in a banner/comment block.
- `grep -rn 'ansible_host' dmf-runbooks/playbooks/` — zero matches in
  `media-*` playbooks.

### 7e — Doc CLAUDE.md banner updates

- `dmf-runbooks/CLAUDE.md` — change "2026-05-19 pivot in flight" block
  to historical landing record:
  > **2026-05-22 — ADR-0025 Lane B landed.** Catalog launchers now
  > execute in-cluster via the AWX EE pod + Helm chart. SSH-to-control-
  > node retained for AWX→infrastructure (693-class) plays only.
- `dmf-media/CLAUDE.md` — replace "in flight; first chart" with
  "landed 2026-05-22 (Lane B)."

### 7f — STATUS.md operator notes

Add a `<!-- HUMAN-START -->` block entry at the top:
> ### ✅ ADR-0025 Lane B landed (2026-05-22)
> Catalog launcher migration complete. NMOS-cpp deploys as Helm chart
> from in-cluster Zot via AWX EE pod in `nmos` ns. Hardcoded Hetzner
> private-IP map deleted. ADR-0025 Accepted; ADR-0016 fully superseded
> for `media-*` JTs (Path A retained for 693-class). Verified on
> g2r6-foa9 (job <id>, helm release `nmos-cpp@0.1.0`).

### 7g — TODOS.md sweep

Search `TODOS.md` and `.claude/plans/` for entries referring to:
- `k3s_node_ip` custom field on NetBox device — obsolete.
- "Phase 5 cleanup of the pivot plan — remove broken `spec.ee_pod_spec_override` fragment" — superseded by Container Group decision.
- "NetBox inventory CIDR fix" launcher band-aid — obsolete.

Either delete or move to a `Completed-2026-05-22` section with a
1-line referencing Lane B.

**Verification gate (Phase 7):** Implementer runs the three grep
sweeps in 7d, presents the output as part of the handoff. Operator
reviews; zero orphan Path-A references in current-state docs.

---

## Phase 8 — Handoff packaging

After Phase 7 verifies:
1. Squash + commit per-repo with the suggested subjects above
   (one commit per repo; do NOT mix repos in one commit).
2. Write
   `docs/handoffs/DMF ADR-0025 Lane B Landed Handoff 2026-05-22.md` —
   captures: what shipped, verification outputs (kubectl/helm outputs
   from Phase 6), open items rolled forward (Lane C, retired-cluster
   ref cleanup which is Move 2), and the next-session pickup signal.
3. Refresh STATUS.md via `bin/generate-status.sh`.
4. Push all repos (operator-authorized per Pre-flight #2).

---

## Critical files inventory (at-a-glance)

| File | What |
|---|---|
| `dmf-media/charts/nmos-cpp/` (new) | Helm chart |
| `dmf-runbooks/playbooks/launch-nmos-cpp.yml` (rewrite) | localhost + helm |
| `dmf-runbooks/playbooks/teardown-nmos-cpp.yml` (rewrite) | localhost + helm uninstall |
| `dmf-runbooks/roles/nmos-cpp/tasks/{configure,provision,finalise}.yml` (slim) | NetBox only |
| `dmf-runbooks/roles/nmos-cpp/defaults/main.yml` (prune) | drop chart-only vars |
| `dmf-infra/k3s-lab-bootstrap/playbooks/630-zot-seed-platform.yml` (extend) | seed NMOS + chart |
| `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml` (refactor) | EE + CG + JT pin + hygiene |
| `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml` (extend) | new var block |
| `dmfdeploy/bin/publish-chart-to-ghcr.sh` (new) | symmetric publish |
| `dmf-media/bin/publish-chart-to-ghcr.sh` (new) | thin wrapper |
| `docs/decisions/0025-...md` (full ADR) | promotion |
| `docs/decisions/0016-...md` (amend) | full supersession for media-* |
| `docs/decisions/INDEX.md` | flip statuses |
| `docs/plans/Move 1 Gate 2 *.md` (5 banners) | supersession banners |
| `dmf-runbooks/CLAUDE.md`, `dmf-media/CLAUDE.md` | banner updates |
| `STATUS.md` (HUMAN section) | landing entry |
| `TODOS.md` | sweep |

---

## Implementer instructions (codex, pane 3)

**How codex picks this up:**

1. Read this plan in full FIRST. No shortcuts; the file/line refs are
   load-bearing.
2. Read the boot ritual files (CLAUDE.md, STATUS.md, the 2026-05-22
   handoffs).
3. Execute Pre-flight (commit g2r6-foa9 bundle if operator authorized;
   push the 4 clean unpushed commits; refresh STATUS).
4. Execute Phases 1–8 in order. Do NOT parallelize phases — gates
   matter. Within a phase, parallelize file edits where independent.
5. After each phase, run that phase's verification gate. If a gate
   fails, STOP and report to claude (pane 2) via agent-bridge:

   ```
   ~/.claude/skills/agent-bridge/bin/agent-bridge send claude - <<'REPLY_END'
   Phase <N> gate failed: <one-line summary>
   <evidence>
   REPLY_END
   ```

6. After Phase 6 PASSES, send a status reply BEFORE starting Phase 7:

   ```
   ~/.claude/skills/agent-bridge/bin/agent-bridge send claude - <<'REPLY_END'
   Phase 6 passed. Outputs: <kubectl/helm captures>. Starting Phase 7
   retirement.
   REPLY_END
   ```

7. After Phase 8, final reply with the handoff doc path + commit hashes.

**Working directory:** `$DMFDEPLOY_UMBRELLA` (the umbrella).
Sub-repos as siblings.

**Authority bounds:**
- May commit per the suggested subjects.
- May NOT push to GitHub mirrors — operator-authorized only.
- May NOT modify `dmf-env` beyond the Pre-flight commit if authorized
  — that repo is private and operator-managed.
- May NOT alter ADRs other than 0025 + 0016 in this plan.
- May NOT skip the Phase 6 verification on the live cluster.

**Where to look for context:**
- The convergence parent plan: `docs/plans/DMF Cluster-Internal
  Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`
- The trigger handoff: `docs/handoffs/DMF dmf-runbooks Path A Public
  Publish Completion Handoff 2026-05-22.md`
- The latest accepted ADR pattern: ADR-0024 (landed 2026-05-22).

**End-state success condition (single sentence):**
On g2r6-foa9, `media-launch-nmos-cpp` succeeds end-to-end via an
in-cluster AWX EE pod (no SSH, no hardcoded IPs), `helm list -n nmos`
shows `nmos-cpp@0.1.0`, ADR-0025 is Accepted, ADR-0016 fully
superseded for `media-*` JTs, and STATUS.md records the landing.
