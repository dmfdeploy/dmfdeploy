---
status: historical
date: 2026-04-29
---
# DMF Staged Release — Phase 2-3 Plan (2026-04-29)

> **SUPERSEDED 2026-04-30** by the strategic review and the Move 1 / Move 2
> task specs. Kept for historical record. See
> [`docs/reviews/dmf-platform-strategic-review-2026-04-30.md`](../reviews/dmf-platform-strategic-review-2026-04-30.md),
> [`dmf-platform-move-1-task-2026-05-04.md`](dmf-platform-move-1-task-2026-05-04.md),
> [`dmf-platform-move-2-task-2026-04-30.md`](dmf-platform-move-2-task-2026-04-30.md).

> **Read this first.** Comprehensive handoff for gstack workflow. Orchestrates
> three concurrent streams of work across three repos over 4 weeks: Layer-1
> OpenTofu cut-over (dmf-env), Layers 2-3 + verticals playbook landing
> (dmf-infra), and dmf-cms operator control plane canary (dmf-cms on
> feature/dmf-console-release-0-bootstrap).
>
> **Decision:** Baseline-only staged release (Option C) — decouples
> infrastructure cut-over from application deployment; no federation planning,
> no operator automation expansion. **Supersedes all prior CEO reviews.**

---

## 1. Status snapshot

| Phase | Work Stream | Status | Where |
|---|---|---|---|
| **1: OpenTofu Cut-over** | Infrastructure provisioning | ✅ **step 8 DONE, step 9 DONE early** | dmf-env main |
| | Step 8: deprecate provision-nodes.sh, update DEPLOYMENT.md | ✅ **landed** `b81e0a1` | — |
| | Step 9: destroy/recreate rehearsal on k3s-node-03 | ✅ **DONE early** — all 3 servers recreated by tofu | — |
| | k3s-vip floating IP verification | ⏳ **still pending** — VIP 195.201.251.7 not yet assigned to new nodes | terraform/README.md |
| **2: Playbooks** | 650-dmf-cms.yml landing | ⏳ **drafted, test gap** | dmf-infra main |
| | 694-born-inventory.yml landing | ⏳ **drafted, role review pending** | dmf-infra main |
| | 695-zot-oidc.yml landing | ⏳ **drafted, Authentik provider validation missing** | dmf-infra main |
| | Layer 2-3 integration tests (test-layer6.yml) | ⏳ **CRITICAL gap — does not exist** | dmf-infra roles/tests/ |
| **3: dmf-cms** | Operator console canary | ⏳ **feature branch ready** | feature/dmf-console-release-0-bootstrap |
| | Authentik v3 passkey enrollment | ✅ **fixed in feature branch** | dmf-cms commit c194c6a |
| | Concurrent apply locking | ⏳ **CRITICAL design decision** | dmf-cms deploy role |

**As of 2026-04-29 (after Step 8 execution):**
- dmf-env: HEAD `b81e0a1` (Phase B step 8 complete, servers recreated, tofu plan clean)
- dmf-infra: HEAD `881d7df` (no playbooks 650/694/695 on main yet)
- dmf-cms: HEAD `5b80de2` on feature/dmf-console-release-0-bootstrap (Authentik v3 + pk field ready)

---

## 2. Environment snapshot

**Operator host:** Mac mini at `<lan-ip>`.
- Never SSH into .117 — you are already on it.
- Memory: `feedback_claude_code_is_on_mac_mini.md`
- All JuiceFS artifacts live at `<secure-store>/`, never `$HOME/secure`.
- Memory: `feedback_dmf_secure_path.md`

**Hetzner 3-node cluster (nbg1):**
- Control-plane #1: `k3s-node-01` at `<control-node-public-ip>` / `10.0.0.2`
- Worker #1: `k3s-node-02` at `<node-public-ip>` / `10.0.0.3`
- Worker #2 (rehearsal target): `k3s-node-03` at `<node-public-ip>` / `10.0.0.4`
- Bastion/SSH: `k3s-admin@<control-node-public-ip>`

**Network:** 10.0.0.0/28 (k3s-private), provider-public /28.
- Floating IP `k3s-vip` (<lb-floating-ip>): **NOT in tofu state** (by design).
- Public LB: `<lb-public-ip>` (CCM-managed, name `dmf-traefik`).
- DNS apex: `dmf.example.com` → `<lb-public-ip>` (Cloudflare).

**In-cluster OpenBao:**
- Endpoint: `http://openbao.openbao.svc:8200`
- ESO inside cluster reads from this.
- DMF does **not** use operator-side wg2-OpenBao.
- Memory: `project_dmf_no_wg2_openbao.md`

**Terraform state:**
- Path: `<secure-store>/terraform-states/hetzner-arm/terraform.tfstate`
- Size: ~12 KB (after Phase B step 7)
- Lock pragma: flock(2) unsupported on JuiceFS; pass `-lock=false` on every write subcommand.
- Memory: `project_tofu_juicefs_lock.md`

---

## 3. Four repos and current heads

| Repo | Path | Branch | HEAD | Notes |
|---|---|---|---|---|
| `dmf-env` | `~/repos/dmf-env` | `main` | `b81e0a1` | **Phase B step 8 COMPLETE** — provision-nodes.sh deprecated, tofu plan clean. Servers recreated (IPs shifted: node-01→<node-public-ip>, node-02→<control-node-public-ip>). |
| `dmf-infra` | `~/repos/dmf-infra` | `main` | `881d7df` | No playbooks 650/694/695 on main yet. Concurrent awx + cms work in flight. |
| `dmf-cms` | `~/repos/dmf-cms` | `feature/dmf-console-release-0-bootstrap` | `5b80de2` | Authentik v3 API fixes (passkey enrollment, endpoints, pk invite field). Ready for operator testing. |
| `dmf-central` | `~/repos/dmf-central` | `master` | `ddaee5f` | Container images; unchanged during Phase 2-3. |

**Always re-fetch and re-check before starting work** — concurrent awx/cms/operator work has been landing.

---

## 4. Decision: Baseline-only staged release (Option C)

**Three alternatives were evaluated:**

| Option | Scope | Infrastructure | Application | Automation | Trade-off |
|---|---|---|---|---|---|
| **A: Full Expansion** | Maximal | Cut-over + Phase 1 federation | dmf-cms + Layer 5 media functions | Day-1 operator automation | Complexity + timeline risk |
| **B: Scope Reduction** | Minimal | Cut-over only | Defer all apps | Manual ops only | Operational friction, low modernization velocity |
| **C: Baseline (SELECTED)** | Staged | Cut-over, then layers 2–3 playbooks | dmf-cms canary then production | No Day-1 automation; layer in post-cutover | Clear gates, measurable progress, low risk per phase |

**Why C?** Baseline staged release balances:
- **Risk isolation:** Each phase has a single gate (infrastructure readiness, playbook correctness, operator acceptance).
- **Velocity:** Landing infrastructure, playbooks, and operator console sequentially means each can be validated independently.
- **Clarity:** Teams see concrete progress (infrastructure live → playbooks working → console operators confident).
- **Future-proof:** Post-Phase-3 decision on federation, Layer 4–5 media functions, automation, based on operational experience.

---

## 5. Four CRITICAL GAPS — design decisions required

These must be resolved **before** Phase 1 production gate. Highlighted from error & rescue map.

### 5.1 Floating IP k3s-vip verification (Phase 1 gate blocker)

**Gap:** Floating IP 195.201.251.7 is intentionally **not** in tofu state (see `terraform/README.md`
"Resources NOT in tofu"). But k3s-vip is critical for multi-zone failover. Rehearsal on
k3s-node-03 cannot verify vip reachability unless it's pre-assigned before destroy/recreate.

**Current state:** Manual step; no automation to verify assignment or fail-safe.

**Design decision required:**
- Option A: Automate vip assignment in `terraform/hetzner-arm/` module, then keep it **outside** state (import + remove from management).
- Option B: Keep vip manual but add preflight check in rehearsal wrapper (ssh to node-03, run `ip addr show` to verify vip bound before destroy).
- Option C: Skip vip verification in rehearsal; verify post-production cutover only (higher risk).

**Recommendation:** **Option A + B** — Automate assignment in tofu (repeatable), add preflight check to rehearsal (observable). Test on k3s-node-03; rollback: manually release vip via hcloud CLI if destroy fails.

**Shell command (Phase 1 step 9 preflight, after step 8 lands):**
```bash
# Verify k3s-vip is bound to k3s-node-03
ssh -i ~/.ssh/id_ed25519 root@10.0.0.4 ip addr show | grep -q 195.201.251.7 \
  || { echo "ERROR: k3s-vip not bound to k3s-node-03"; exit 1; }
echo "✓ k3s-vip preflight OK"
```

---

### 5.2 etcd quorum safety (Phase 1 gate blocker)

**Gap:** Destroy/recreate rehearsal on k3s-node-03 will temporarily remove 1 of 3 nodes. If k3s-node-01
or k3s-node-02 fails **during** the rehearsal window, etcd loses quorum (only 2 nodes remain: 1 destroyed, 1 up, 1 down = no quorum).

**Current state:** No safeguard in rehearsal wrapper; no monitoring during destroy/recreate cycle.

**Design decision required:**
- Option A: Single-node rehearsal only — destroy/recreate k3s-node-03, but require k3s-node-01 and k3s-node-02 to be healthy **before and after** (no concurrent failures allowed).
- Option B: Run rehearsal during maintenance window with oncall escalation (pagerduty/email alert if quorum is lost).
- Option C: Rehearse on a 4th temporary node (expensive, not in scope).

**Recommendation:** **Option A** — Single-node rehearsal with pre/post quorum verification. Add health check before rehearsal start.

**Shell commands (Phase 1 step 9 preflight):**
```bash
# Pre-rehearsal: verify etcd has 3 healthy members
kubectl exec -n kube-system -it etcd-k3s-node-01 -- etcdctl member list | grep -c isLeader \
  || { echo "ERROR: etcd quorum check failed"; exit 1; }
echo "✓ etcd 3-member quorum verified"

# During rehearsal: drain k3s-node-03, then destroy/recreate
kubectl drain k3s-node-03 --ignore-daemonsets --delete-emptydir-data

# Post-rehearsal: re-join node, verify quorum restored
cd ~/repos/dmf-env/terraform/hetzner-arm && tofu apply -lock=false
kubectl uncordon k3s-node-03
sleep 30

# Final check: etcd 3-member quorum
kubectl exec -n kube-system -it etcd-k3s-node-01 -- etcdctl member list | grep -c isLeader \
  || { echo "ERROR: post-rehearsal etcd quorum lost"; exit 1; }
echo "✓ etcd quorum restored"
```

---

### 5.3 Integration test playbook for Layer 2-3 (Phase 2 blocker)

**Gap:** dmf-infra has **no** formal integration tests for playbooks 650-dmf-cms, 694-born-inventory, 695-zot-oidc.
Playbooks call complex roles:
- `650-dmf-cms.yml` → `cluster-ready` + `cms` role (179 lines, k8s module calls)
- `694-born-inventory.yml` → `cluster-ready` + `dmf-born-inventory` role (1046 lines, OpenBao + NetBox REST calls)
- `695-zot-oidc.yml` → `cluster-ready` + `zot-oidc` role (105 lines, kubectl exec into Authentik pod)

**Current state:** Each role tested in isolation; no end-to-end verification that roles compose correctly.

**Design decision required:**
- Option A: Create `test-layer6.yml` playbook that runs against a staging cluster (dmf-central?), verifies dmf-cms deployment + NetBox registration + Zot OIDC provider config, then report pass/fail.
- Option B: Manual operator checklist after 650/694/695 land (lower assurance).
- Option C: Defer testing to Phase 3 (higher production risk).

**Recommendation:** **Option A** — Create `test-layer6.yml` as gating artifact for Phase 2. Template:

```yaml
# dmf-infra/playbooks/test-layer6.yml
---
- name: Integration test — Layer 2-3 playbooks + dmf-cms
  hosts: k3s-node-01
  vars:
    # Sourced from dmf-central or staging
    cluster_name: "test-dmf-cms"
  tasks:
    - name: Deploy Layer 2 (cluster-ready)
      include_role:
        name: cluster-ready
    
    - name: Deploy Layer 3 (dmf-cms + born-inventory + zot-oidc)
      include_tasks:
        file: ../playbooks/650-dmf-cms.yml
        apply:
          tags:
            - layer6
    
    - name: Verify dmf-cms Deployment exists
      kubernetes.core.k8s_info:
        kind: Deployment
        namespace: dmf-cms
        name: dmf-cms
      register: cms_deploy
      failed_when: cms_deploy.resources | length == 0
    
    - name: Verify NetBox registration (born-inventory post-check)
      uri:
        url: "https://netbox.dmf.example.com/api/dcim/devices/?name=k3s-node-01"
        headers:
          Authorization: "Token {{ netbox_api_token }}"
      register: netbox_result
      failed_when: netbox_result.json.count == 0
    
    - name: Verify Zot OIDC provider configured
      kubernetes.core.k8s_info:
        kind: ConfigMap
        namespace: zot
        name: zot-config
      register: zot_config
      failed_when: "'oidc' not in zot_config.resources[0].data.config"
    
    - name: Report test success
      debug:
        msg: "✓ Layer 2-3 integration test passed"
```

**Execution (Phase 2 gate):**
```bash
cd ~/repos/dmf-infra
ansible-playbook -i inventories/hetzner-arm/hosts.ini \
  playbooks/test-layer6.yml \
  --tags layer6 \
  -vvv
```

---

### 5.4 dmf-cms concurrent apply locking (Phase 3 gate blocker)

**Gap:** dmf-cms deploy role (roles/stack/operator/cms/) uses `kubernetes.core.k8s` module to apply manifests.
No locking mechanism prevents concurrent applies from different operators or runbooks. If two operators
run Ansible at the same time, manifests may conflict or leave cluster in dirty state.

**Current state:** No file lock, no distributed lock, no state guard.

**Design decision required:**
- Option A: File-based lock (flock on `<secure-store>/dmf-cms.lock`) checked at role start, held for duration of apply.
- Option B: Kubernetes-native lock (LeaseObject in dmf-cms namespace) using k8s leader-election pattern.
- Option C: Single-operator rule (document in runbook, no technical guard).

**Recommendation:** **Option A** — File lock is sufficient for single-operator environment; durable across restarts.

**Implementation (add to roles/stack/operator/cms/main.yml):**
```yaml
---
- name: Acquire dmf-cms apply lock
  file:
    path: <secure-store>/dmf-cms.lock
    state: touch
  register: lock_file

- name: Lock file for duration of apply
  block:
    - name: Deploy dmf-cms manifests
      kubernetes.core.k8s:
        state: present
        namespace: dmf-cms
        definition: "{{ lookup('template', 'manifest.yml.j2') }}"
      register: apply_result
  
  always:
    - name: Release lock
      file:
        path: <secure-store>/dmf-cms.lock
        state: absent
```

**Execution guard (before playbook runs):**
```bash
# Check lock before running 650-dmf-cms
if [ -f <secure-store>/dmf-cms.lock ]; then
  echo "ERROR: dmf-cms apply already in progress. Lock exists: $(stat -f%Sm <secure-store>/dmf-cms.lock)"
  exit 1
fi
```

---

### 5.5 dmf-cms partial apply state recovery (Phase 3 operational)

**Gap:** If Ansible playbook times out mid-apply (network issue, manifest error), dmf-cms may be in
partial state: some manifests deployed, others not. Next operator run blindly re-applies, possibly
conflicting with partial state.

**Current state:** No query of actual cluster state before apply; no dry-run to detect conflicts.

**Design decision required:**
- Option A: Add pre-apply check that queries cluster for dmf-cms resources, compares to intended state in manifest, reports diffs before proceeding.
- Option B: Add idempotency check to each manifest (labels, selectors) so re-apply is always safe.
- Option C: Manual operator review of `kubectl get` output before each apply (process-based, error-prone).

**Recommendation:** **Option A + B** — Pre-apply dry-run + manifest idempotency.

**Implementation (add to roles/stack/operator/cms/main.yml):**
```yaml
---
- name: Dry-run apply to detect conflicts
  kubernetes.core.k8s:
    state: present
    namespace: dmf-cms
    definition: "{{ lookup('template', 'manifest.yml.j2') }}"
    dry_run: client
  register: dry_run_result

- name: Abort if conflicts detected
  fail:
    msg: |
      Dry-run detected conflicts:
      {{ dry_run_result | to_nice_yaml }}
      
      Manual recovery:
      1. kubectl describe deployment dmf-cms -n dmf-cms
      2. Review events for failure reason
      3. Fix manifest or delete conflicting resource
      4. Re-run playbook
  when: dry_run_result.failed or (dry_run_result.warnings | length > 0)

- name: Apply with confidence (dry-run passed)
  kubernetes.core.k8s:
    state: present
    namespace: dmf-cms
    definition: "{{ lookup('template', 'manifest.yml.j2') }}"
  register: apply_result
```

---

## 6. Five WARNINGS — code quality observations

These are **not** blockers but should inform Phase 2-3 planning:

### 6.1 born-inventory role uses OpenBao root token

**Location:** dmf-infra/roles/common/dmf-born-inventory/main.yml, line ~42

**Risk:** Root token can read/write/delete all Bao secrets. Rotation is manual and error-prone.

**Action for Phase 2:** Design narrow-scoped Bao policy (e.g., `policy "netbox-registration"`) and migrate born-inventory to that policy. Reduces blast radius if token leaks.

---

### 6.2 cms and born-inventory roles lack timeout guards

**Location:** dmf-infra/roles/stack/operator/cms/main.yml, roles/common/dmf-born-inventory/main.yml

**Risk:** If external APIs (Authentik, NetBox, OpenBao) hang, playbook blocks indefinitely.

**Action for Phase 2:** Add `timeout_seconds` to all REST module calls. Example:
```yaml
- name: Register in NetBox
  uri:
    url: https://netbox.dmf.example.com/api/dcim/devices/
    timeout: 30
  register: netbox_result
```

---

### 6.3 born-inventory role uses kubectl exec into Authentik pod

**Location:** dmf-infra/roles/common/dmf-born-inventory/main.yml, line ~320

**Risk:** Pod name/namespace hardcoded; if Authentik pod fails, exec fails silently.

**Action for Phase 2:** Use `kubernetes.core.k8s_exec` with pod selector; add retry logic.

---

### 6.4 dmf-cms role lacks rollback automation

**Location:** dmf-infra/roles/stack/operator/cms/main.yml

**Risk:** If dmf-cms Deployment fails to rollout, manual `kubectl rollout undo` required. No automated rollback trigger.

**Action for Phase 3:** Add post-deploy readiness check; auto-rollback if Deployment is not Ready after 5 min.

---

### 6.5 playbook 650/694/695 do not validate Authentik IdP provider config

**Location:** dmf-infra/playbooks/650-dmf-cms.yml, 694-born-inventory.yml, 695-zot-oidc.yml

**Risk:** If Authentik provider (slug `dmf-cms`, redirect URIs, property mappings) is misconfigured, playbooks complete successfully but operator-facing auth fails.

**Action for Phase 2:** Add task to each playbook that queries Authentik API and validates provider shape. Example:
```yaml
- name: Validate dmf-cms OIDC provider in Authentik
  uri:
    url: "https://auth.dmf.example.com/api/v3/core/applications/?slug=dmf-cms"
    headers:
      Authorization: "Bearer {{ authentik_token }}"
  register: authentik_app
  failed_when: |
    authentik_app.json.results | length == 0 or
    authentik_app.json.results[0].provider is not defined
```

---

## 7. Three-phase staged rollout (4 weeks)

### Phase 1: Infrastructure Cut-over (Week 1–2, 2026-04-29 — 2026-05-13)

**Goal:** Migrate k3s from provision-nodes.sh ad-hoc provisioning to OpenTofu IaC. Verify destroy/recreate safety.

**Coordinator:** You (human operator).

**Work items:**

1. **Step 8: Land cut-over changes in dmf-env (Week 1, EOD 2026-05-02)**
   - Deprecate `bin/provision-nodes.sh` (add banner: "DEPRECATED: provisioning moved to OpenTofu").
   - Update `DEPLOYMENT.md` §3 "Infrastructure Layer" to reference `terraform/hetzner-arm/` as source of truth.
   - Update `terraform/README.md` §"Resources NOT in tofu" to explicitly document k3s-vip (195.201.251.7) decision.
   - Verify `tofu plan` is clean (no changes).
   - Commit: `git add -A && git commit -m "chore: k3s Layer-1 cut-over to OpenTofu — deprecate provision-nodes.sh"`
   - **Gate:** Step 8 commit must be reviewed by yourself and merged to main.

2. **Step 9: Destroy/recreate rehearsal on k3s-node-03 (Week 1–2, 2026-05-06 — 2026-05-08)**
   - Pre-flight (2026-05-06):
     ```bash
     cd ~/repos/dmf-env/terraform/hetzner-arm
     
     # Verify tofu plan is clean
     tofu plan -lock=false | grep -q "No changes" \
       || { echo "ERROR: tofu plan reports changes; abort"; exit 1; }
     
     # Verify k3s-vip is bound to k3s-node-03
     ssh -i ~/.ssh/id_ed25519 root@10.0.0.4 ip addr show | grep -q 195.201.251.7 \
       || { echo "ERROR: k3s-vip not bound to k3s-node-03"; exit 1; }
     
     # Verify etcd 3-member quorum
     kubectl exec -n kube-system -it etcd-k3s-node-01 -- \
       etcdctl member list | wc -l | grep -q 3 \
       || { echo "ERROR: etcd quorum not 3"; exit 1; }
     
     echo "✓ Pre-flight checks passed"
     ```
   
   - Rehearsal (2026-05-07 — 2026-05-08):
     ```bash
     # Drain k3s-node-03
     kubectl drain k3s-node-03 --ignore-daemonsets --delete-emptydir-data
     
     # Destroy and recreate k3s-node-03 in tofu
     cd ~/repos/dmf-env/terraform/hetzner-arm
     tofu destroy -lock=false -target='module.cluster.hcloud_server.node["k3s-node-03"]' -auto-approve
     tofu apply -lock=false -target='module.cluster.hcloud_server.node["k3s-node-03"]' -auto-approve
     
     # Wait for node to join cluster
     sleep 60
     kubectl get nodes | grep k3s-node-03 | grep -q "Ready" \
       || { echo "ERROR: k3s-node-03 failed to rejoin"; exit 1; }
     
     # Uncordon and re-join etcd
     kubectl uncordon k3s-node-03
     kubectl get node k3s-node-03 -o wide
     
     echo "✓ Rehearsal complete"
     ```
   
   - Post-flight (2026-05-08):
     ```bash
     # Verify etcd 3-member quorum restored
     kubectl exec -n kube-system -it etcd-k3s-node-01 -- \
       etcdctl member list | wc -l | grep -q 3 \
       || { echo "ERROR: post-rehearsal etcd quorum lost"; exit 1; }
     
     # Verify k3s-vip still bound
     kubectl get nodes -L external-dns.alpha.kubernetes.io/acquire | grep k3s-node-01 | grep -q 195.201.251.7 \
       || { echo "WARNING: k3s-vip not visible in node labels"; }
     
     # Final tofu plan clean
     tofu plan -lock=false | grep -q "No changes" \
       || { echo "ERROR: tofu plan reports changes after rehearsal"; exit 1; }
     
     echo "✓ Post-flight checks passed"
     ```
   
   - **Gate:** Rehearsal completes without etcd loss, node rejoin, or tofu plan changes. Operator signs off.

**Success criteria:**
- `tofu plan` clean (no pending changes).
- k3s-node-03 destroyed and recreated; rejoins cluster within 2 minutes.
- etcd quorum: 3 members before, during drift (2 after drain), 3 after uncordon.
- All workloads reschedule successfully (no pending pods).

**Rollback procedure (if rehearsal fails):**
- If tofu fails mid-apply: `tofu unlock -force` (if lock is stuck), retry `tofu apply -lock=false`.
- If etcd quorum is lost: manually `kubectl delete node k3s-node-03`, then `tofu apply -lock=false` to provision fresh node.
- If k3s-vip is unbound: manually assign via `hcloud floating-ip assign 195.201.251.7 k3s-node-03` (CLI).

---

### Phase 2: Playbooks + Integration Tests (Week 2–3, 2026-05-13 — 2026-05-27)

**Goal:** Land Layers 2–3 playbooks (cluster-ready, dmf-cms, born-inventory, zot-oidc); create and verify integration tests.

**Coordinator:** You + Ansible execution.

**Work items:**

1. **Create test-layer6.yml integration test (Week 2, EOD 2026-05-15)**
   - Add `playbooks/test-layer6.yml` to dmf-infra (see §5.3 template).
   - Add validation tasks:
     - Verify dmf-cms Deployment exists and is Ready.
     - Verify NetBox device registration (born-inventory post-check).
     - Verify Zot OIDC provider config in ConfigMap.
   - Test on dmf-central (staging) cluster first.
   - Commit: `git add playbooks/test-layer6.yml && git commit -m "feat: add Layer 2-3 integration test playbook"`
   - **Gate:** Test runs successfully on dmf-central; operator reviews output.

2. **Land playbook 650-dmf-cms.yml (Week 2, EOD 2026-05-15)**
   - Move from dmf-infra working directory to `playbooks/650-dmf-cms.yml` on main branch.
   - Add timeout guards to all URI/k8s module calls (§6.2).
   - Add concurrent apply lock (§5.4).
   - Add dry-run conflict detection (§5.5).
   - Test against dmf-central first.
   - Commit: `git add playbooks/650-dmf-cms.yml && git commit -m "feat: deploy dmf-cms operator console"`
   - **Gate:** Playbook runs to completion; dmf-cms Deployment is Ready; operator can access UI.

3. **Land playbook 694-born-inventory.yml (Week 2, EOD 2026-05-15)**
   - Move from dmf-infra working directory to `playbooks/694-born-inventory.yml` on main branch.
   - Refactor role to use narrow Bao policy (§6.1) instead of root token.
   - Add timeout guards to NetBox REST calls (§6.2).
   - Test against dmf-central first; verify NetBox device appears.
   - Commit: `git add playbooks/694-born-inventory.yml && git commit -m "feat: register cluster in NetBox (born-inventory)"`
   - **Gate:** Playbook runs to completion; device appears in NetBox API.

4. **Land playbook 695-zot-oidc.yml (Week 2, EOD 2026-05-15)**
   - Move from dmf-infra working directory to `playbooks/695-zot-oidc.yml` on main branch.
   - Add Authentik provider validation task (§6.5).
   - Refactor kubectl exec to use k8s_exec with pod selector (§6.3).
   - Test against dmf-central first; verify Zot redirects to Authentik.
   - Commit: `git add playbooks/695-zot-oidc.yml && git commit -m "feat: wire Zot OIDC against Authentik"`
   - **Gate:** Playbook runs to completion; Zot OIDC provider is configured; manual test redirects to Authentik login.

5. **Run integration test test-layer6.yml (Week 3, EOD 2026-05-20)**
   - Execute against dmf-central staging cluster:
     ```bash
     cd ~/repos/dmf-infra
     ansible-playbook -i inventories/hetzner-arm/hosts.ini \
       playbooks/test-layer6.yml \
       --tags layer6 \
       -vvv
     ```
   - Verify all tasks pass:
     - dmf-cms Deployment exists and Ready.
     - NetBox device registered (query API).
     - Zot OIDC provider configured (query k8s ConfigMap).
   - **Gate:** All integration test tasks pass; operator signs off.

**Success criteria:**
- All three playbooks run to completion without errors.
- dmf-cms Deployment is Ready; console is accessible.
- NetBox device registration verified via API.
- Zot OIDC provider wired and tested.
- Integration test suite passes.

**Rollback procedure (if playbook fails on staging):**
- If dmf-cms deployment fails: `kubectl delete deployment dmf-cms -n dmf-cms && kubectl delete namespace dmf-cms`.
- If NetBox registration fails: `curl -X DELETE https://netbox.dmf.example.com/api/dcim/devices/<id>/ -H "Authorization: Token $NETBOX_TOKEN"`.
- If Zot OIDC fails: `kubectl delete configmap zot-config -n zot && kubectl rollout undo deployment/zot -n zot`.

---

### Phase 3: dmf-cms Canary → Production (Week 3–4, 2026-05-27 — 2026-06-10)

**Goal:** Canary dmf-cms to staging k3s cluster; operator testing and acceptance; production cutover.

**Coordinator:** You + operator (human).

**Work items:**

1. **Merge feature/dmf-console-release-0-bootstrap to main (Week 3, EOD 2026-05-22)**
   - PR review: verify Authentik v3 API fixes (passkey enrollment, endpoints).
   - Test merge-base on dmf-central staging cluster.
   - Merge and tag: `git tag dmf-cms-release-0-bootstrap`.
   - **Gate:** Feature branch tested, operator approves merge.

2. **Deploy dmf-cms canary to staging (Week 3, 2026-05-27 — 2026-05-29)**
   - Run 650-dmf-cms.yml against dmf-central (staging).
   - Operator accesses dmf-cms console UI at `https://dmf-cms.dmf.example.com/`.
   - Operator tests:
     - Authentik SSO login (verify `<operator>` user auto-created and has operator role).
     - Passkey enrollment (verify Authentik v3 flow works).
     - Cluster inventory view (dmf-cms reads NetBox via API).
     - Basic operator actions (start/stop workloads, if applicable).
   - **Gate:** Operator acceptance sign-off on staging.

3. **Deploy dmf-cms to production (Week 4, 2026-06-03 — 2026-06-05)**
   - Pre-flight (2026-06-03):
     ```bash
     # Verify production cluster is healthy
     kubectl get nodes | grep Ready | wc -l | grep -q 3 \
       || { echo "ERROR: Not all nodes Ready"; exit 1; }
     
     # Verify Authentik is running
     kubectl get deployment authentik -n authentik | grep -q "1/1" \
       || { echo "ERROR: Authentik not Ready"; exit 1; }
     
     # Verify NetBox is running
     kubectl get deployment netbox -n netbox | grep -q "1/1" \
       || { echo "ERROR: NetBox not Ready"; exit 1; }
     
     echo "✓ Pre-flight checks passed"
     ```
   
   - Canary: Deploy dmf-cms to production cluster with lock and dry-run guards (§5.4, §5.5):
     ```bash
     cd ~/repos/dmf-infra
     
     # Acquire lock
     if [ -f <secure-store>/dmf-cms.lock ]; then
       echo "ERROR: dmf-cms apply already in progress"
       exit 1
     fi
     
     # Dry-run
     ansible-playbook -i inventories/hetzner-arm/hosts.ini \
       playbooks/650-dmf-cms.yml \
       -e "ansible_check_mode=yes" \
       -vvv
     
     # Proceed to full apply
     ansible-playbook -i inventories/hetzner-arm/hosts.ini \
       playbooks/650-dmf-cms.yml \
       -vvv
     ```
   
   - Post-flight (2026-06-05):
     ```bash
     # Verify dmf-cms Deployment is Ready
     kubectl get deployment dmf-cms -n dmf-cms | grep -q "1/1" \
       || { echo "ERROR: dmf-cms Deployment not Ready"; exit 1; }
     
     # Operator acceptance test (manual)
     echo "Navigate to https://dmf-cms.dmf.example.com/ and verify:"
     echo "  1. Authentik SSO login works"
     echo "  2. Operator role is assigned"
     echo "  3. Cluster inventory is populated from NetBox"
     
     echo "✓ Production cutover complete"
     ```
   
   - **Gate:** dmf-cms Deployment Ready; operator manually verifies UI and SSO; rollback procedure documented and verified.

4. **Finalize and document (Week 4, EOD 2026-06-10)**
   - Commit playbooks to dmf-infra main branch (if not already done).
   - Tag dmf-cms release: `git tag dmf-cms-production-v0`.
   - Update dmf-infra README.md with Phase 2-3 completion summary.
   - Archive this plan to `<note-store>/Projects/DMF Staged Release Phase 2-3 Plan 2026-04-29 [COMPLETE].md`.
   - **Gate:** Operator signs off on Phase 3 completion.

**Success criteria:**
- dmf-cms Deployment is Ready in production.
- Operator can login via Authentik SSO.
- Operator console shows cluster inventory (populated from NetBox).
- All playbooks 650/694/695 run to completion without errors.

**Rollback procedure (if production deployment fails):**
- Immediate: `kubectl delete deployment dmf-cms -n dmf-cms && kubectl rollout undo statefulset/authentik -n authentik`.
- Verify: `kubectl get pods -n dmf-cms` (should be empty).
- Restore: Revert dmf-infra main branch to pre-Phase-3 commit, re-run playbook with previous manifest.

---

## 8. Pending decisions before Phase 1 production

1. **k3s-vip floating IP:** Decide on Option A (automate in tofu) vs Option B (manual check) vs combined approach.
2. **etcd quorum safety:** Confirm single-node rehearsal is acceptable (Option A) vs requesting maintenance window.
3. **Integration test framework:** Confirm test-layer6.yml template is suitable; assign owner for implementation.
4. **dmf-cms apply locking:** Confirm file-lock approach (Option A) is acceptable; assign lock file path.
5. **Born-inventory policy scope:** Confirm Bao policy refactor (§6.1) is in scope for Phase 2.

---

## 9. Repos, branches, and next steps

**To pick up this plan in a future session:**
1. Read this document (DMF Staged Release Phase 2-3 Plan 2026-04-29.md).
2. Run: `cd ~/repos/dmf-env && git fetch && git status`
3. Run: `cd ~/repos/dmf-infra && git fetch && git status`
4. Check current heads against §3 "Four repos and current heads".
5. Identify which phase and step you're resuming; jump to that section in §7.
6. Execute pre-flight checks and proceed.

**Gstack compatibility:**
- This plan is suitable for `/plan-eng-review` (architecture), `/qa` (integration testing), `/ship` (landing playbooks).
- Sections §5 (CRITICAL GAPS) and §6 (WARNINGS) should be addressed before using `/ship` to land changes.
- §7 step gates are explicit shell commands that can be automated or delegated to CI/CD post-Phase-1.

---

## 10. References

- **EBU architecture:** `~/Downloads/EBU_White_Paper_The_Dynamic_Media_Facility_Reference_Architecture.pdf`
- **Prior plans:** `<note-store>/Projects/DMF Layer-1 OpenTofu Phase B Cut-over Handoff 2026-04-27.md` (Phase B steps 8–9 detail)
- **Infrastructure state:** `<secure-store>/terraform-states/hetzner-arm/terraform.tfstate`
- **Authentik plan:** `<note-store>/Projects/DMF AWX Authentik SAML Plan 2026-04-27.md`
- **Memory:** feedback_claude_code_is_on_mac_mini.md, feedback_dmf_secure_path.md, project_dmf_no_wg2_openbao.md, project_tofu_juicefs_lock.md
