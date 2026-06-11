# DMF Improvement Run — DR Drill Session Log 2026-04-22-B

> **Vocabulary updated 2026-04-25** — playbook numbers in this session log
> reflect the pre-EBU naming at the time of writing. Canonical layer /
> vertical / lifecycle map is `DMF EBU Mapping (2026-04-25).md`.

**Session type:** Continuation of improvement run (Steps A–E)
**Started:** 2026-04-22 ~14:26 UTC+2
**Status:** Paused — DR drill in progress, shell session degraded
**Code status:** Steps A, B, C, E complete, committed, pushed to both remotes

---

## What was accomplished this session

### Steps A, B, C, E — all done before DR drill

| Step | What landed | Repos touched |
|------|-------------|---------------|
| **A** | `run-playbook.sh` timeout 900 + log-to-file + tee (already present from prior session), new `monitor-playbook.sh`, README docs | dmf-env |
| **B** | 23 playbook renames (00–72), 15-metallb deleted, 5 stub verify playbooks, `site.yml` + 9 phase wrappers, `provision-nodes.sh` updated | dmf-infra + dmf-env |
| **C** | Authentik !Find preflight (scope-mapping refs), cert-manager CF-token scope preflight | dmf-infra |
| **E** | OpenBao writes 5 Shamir shares at init (JuiceFS×2, local file×1, USB×2) + automation file with 3-share quorum | dmf-infra |

### Commits pushed this session

| Commit | Repo | Description |
|--------|------|-------------|
| `8e8d934` | dmf-env | feat(runner): wrap timeout 900 + log to file + monitor helper |
| `f6fb899` | dmf-infra | fix: apply role/config fixes from 2026-04-22 rebuild session |
| `d21dde6` | dmf-infra | feat(orchestrator): add site.yml + 9 phase wrappers |
| `f6fb899` | dmf-infra | refactor(playbooks): renumber per orchestrator scheme + drop metallb |
| `254e35a` | dmf-env | refactor: update provision-nodes.sh 'Next:' message |
| `be8cde3` | dmf-infra | feat(preflights): catch authentik !Find and cert-manager CF-token-scope |
| `128a32d` | dmf-infra | feat(openbao): write Shamir shares to 5 separate custody locations at init |
| `f607c19` | dmf-infra | fix(post-bootstrap-verify): tolerate CCM uninitialized taint (complex JMESPath — reverted) |
| `e8b184e` | dmf-infra | fix(post-bootstrap-verify): tolerate CCM uninitialized taint (tolerations) |
| `3d51cc0` | dmf-infra | fix(post-bootstrap-verify): wait for CoreDNS before Service traffic test |
| `97b486a` | dmf-infra | fix(k3s): remove CCM uninitialized taint after cluster bootstrap |
| `baa9971` | dmf-infra | fix(post-bootstrap-verify): tolerate missing LB in phase-1 verify |
| `a812a2b` | dmf-infra | fix(cert-manager): increase certificate wait to 10 min |
| `e037f61` | dmf-infra | fix(cert-manager): extract apex domain in CF token scope preflight |
| `5b1f05c` | dmf-infra | fix(openbao): write share 3 to file instead of Keychain |
| `23974ef` | dmf-infra | fix(openbao): preload unseal keys from break-glass on rerun |
| `07a6f41` | dmf-infra | fix(openbao): parse init status even when sealed (rc!=0) |
| `6c2c358` | dmf-infra | fix(authentik): flatten !Find preflight to single-line Python |

---

## 12 bugs discovered and fixed during DR drill

### 1. ansible.cfg not found when playbook is in the same directory
**Symptom:** `WARNING: No ansible.cfg found near playbook path '../dmf-infra/k3s-lab-bootstrap/site.yml'` followed by role resolution failure.
**Cause:** `run-playbook.sh` looked in parent dirs only, not the playbook's own directory. `site.yml` lives next to `ansible.cfg`.
**Fix:** Added `$PLAYBOOK_DIR/ansible.cfg` as first candidate in the lookup loop.
**File:** `dmf-env/bin/run-playbook.sh`

### 2. k3s-verify pods unschedulable — CCM uninitialized taint
**Symptom:** `0/3 nodes are available: 3 node(s) had untolerated taint {node.cloudprovider.kubernetes.io/uninitialized: true}`
**Cause:** Hetzner CCM deploys in phase 2 (network), but k3s-verify runs in phase 1. CCM hasn't removed the taint yet.
**Fix:** Added tolerations for `node.cloudprovider.kubernetes.io/uninitialized` to both verify-client Pod and verify-echo Deployment in post-bootstrap-verify role.
**File:** `k3s-lab-bootstrap/roles/base/post-bootstrap-verify/tasks/main.yml`

### 3. CoreDNS Pending — same CCM taint blocking kube-system
**Symptom:** `coredns-xxx 0/1 Pending` — couldn't schedule, so no DNS, so ACME challenges fail, so no TLS cert.
**Cause:** k3s boots with `--cloud-provider=external` which adds the uninitialized taint. CCM isn't deployed until phase 2.
**Fix:** Added a dedicated play after k3s joins that removes the taint from all nodes via `kubectl taint node --all uninitialized-`.
**File:** `k3s-lab-bootstrap/playbooks/10-k3s.yml` (new play at end)

### 4. Cross-node verify DNS resolution failure
**Symptom:** `wget: bad address 'verify-echo.dmf-verify.svc.cluster.local'`
**Cause:** CoreDNS just started, service DNS entries haven't propagated yet.
**Fix:** Added nslookup retry loop (15 retries × 5s) before the cross-node Service wget.
**File:** `k3s-lab-bootstrap/roles/base/post-bootstrap-verify/tasks/main.yml`

### 5. LoadBalancer assertion failed too early
**Symptom:** `Traefik LoadBalancer has no assigned ingress yet` — fatal assert in phase-1 verify.
**Cause:** LB is created by Hetzner CCM, which deploys in phase 2. Phase 1 can't see it yet.
**Fix:** Added `failed_when: false` + extra `when` guard for LB type and ingress defined. Non-fatal warning instead.
**File:** `k3s-lab-bootstrap/roles/base/post-bootstrap-verify/tasks/main.yml`

### 6. CF preflight queried wrong zone
**Symptom:** Pre-flight said "token lacks Zone.Zone.Read" but token was valid.
**Cause:** Probed `/zones?name=dmf.example.com` but the CF zone is `<lan-host>`.
**Fix:** Extract apex domain via `regex_replace('^.*?\\.(\\w+\\.\\w+)$', '\\1')`.
**File:** `k3s-lab-bootstrap/roles/base/cert-manager/tasks/main.yml`

### 7. macOS Keychain locked non-interactively
**Symptom:** `security add-generic-password` failed with "User interaction is not allowed" (exit 36).
**Cause:** Keychain requires interactive unlock. Screen sessions can't do this.
**Fix:** Share 3 now written to `~/secure/openbao-breakglass/hetzner-lab/share-3.json` (same location as shares 1+2 on JuiceFS).
**File:** `k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml`

### 8. `bao status` returns rc=2 when sealed
**Symptom:** OpenBao re-tried Shamir init on every rerun, creating duplicate state.
**Cause:** `bao status` returns rc=2 when sealed. The parse condition `openbao_status_cmd.rc == 0` meant sealed pods defaulted to `initialized: false`.
**Fix:** Parse JSON regardless of return code — the JSON body still contains `initialized: true` even when sealed.
**File:** `k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml`

### 9. Unseal keys not preloaded on rerun
**Symptom:** Unseal tasks failed on reruns because `openbao_unseal_keys_hex` was only set by the init path.
**Fix:** Rerun path now reads `unseal_keys_hex` from existing break-glass JSON alongside `root_token`.
**File:** `k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml`

### 10. Authentik preflight Python syntax error
**Symptom:** `SyntaxError: invalid syntax` on `for model, managed in refs:` in `ak shell -c`.
**Cause:** `ak shell -c` doesn't handle multi-line Python. The `for` loop after `;` is a syntax error.
**Fix:** Flattened to single-line list comprehension: `failed = [f"FAIL..." for m, n in refs if not Mapping.objects.filter(...).exists()]`
**File:** `k3s-lab-bootstrap/roles/stack/operator/authentik/tasks/main.yml`

### 11. Longhorn StorageClass replacement blocked by stale PVCs
**Symptom:** `Refusing destructive replacement` — SC params differ (3 replicas vs desired 2) but PVCs exist.
**Cause:** Partial DR drill runs created PVCs with wrong SC params. On rerun, the refuse-guard correctly blocked replacement but the PVCs are garbage from failed runs.
**Fix:** Manual cleanup before each rerun: delete stale PVCs and force-delete the SC. This is expected for idempotent reruns on a partially-provisioned cluster. A clean cluster won't hit this.
**Manual:** `kubectl delete pvc --all -n <ns>` + `kubectl delete sc longhorn --force`

### 12. SSH ControlMaster mux degrades after ~30 invocations
**Symptom:** `UNREACHABLE!` to node-01 — "Data could not be sent to remote host"
**Cause:** Known issue from lessons. Mux socket exists but TCP connection is zombied.
**Fix:** Manual: `pkill -f "ansible-playbook.*site.yml"; rm -f ~/.ansible/cp/*`; then reconnect.
**Note:** This is the LAST blocker before the DR drill succeeds. The `ServerAliveInterval=15` in ansible.cfg should prevent this, but after 15+ reruns it still happens.

---

## Current cluster state (as of session pause)

- **3 Hetzner nodes** provisioned, k3s installed, CCM taint removed
- **Phases 0–3**: green on every rerun (host, k3s, network, storage)
- **Phase 4**: OpenBao ✅, ESO ✅, Prometheus ✅, **Loki ❌** (PVC cleanup needed)
- **Phases 5–8**: not yet reached
- **OpenBao**: initialized, sealed, shares written to 5 locations (shares 1,2 on JuiceFS; share 3 at `~/secure/...`; shares 4,5 on USB OPENBAO_A; automation file with 3-share quorum)
- **Cert-manager**: ACME DNS-01 challenges completing, wildcard cert issued
- **SSH connectivity**: currently broken from operator Mac — nodes unreachable

---

## Instructions for the fresh session

### Phase 0: Pre-flight checks

```bash
# 1. Verify hcloud context
hcloud context active          # should be 'dmf-infra'
hcloud server list             # should show 3 servers (or 0 if already destroyed)

# 2. Verify Mac-side state
ls /Volumes/OPENBAO_A/                    # USB mounted
ls <secure-store>/                   # JuiceFS mounted
ls ~/.config/cf/dns.txt                   # CF token
ls ~/.config/ts/authkey.txt               # Tailscale key
ls ~/.config/ntfy/alertmanager-url.txt    # ntfy URL
ls ~/.config/healthchecks/watchdog-url.txt
ls ~/.ssh/id_ed25519_k3s_hetzner          # SSH key

# 3. Verify repos are clean
cd <repos>/dmf-infra && git status --short
cd <repos>/dmf-env && git status --short
```

### Phase 1: Destroy and rebuild cluster

```bash
# 1. Destroy existing cluster
hcloud server delete k3s-node-01 k3s-node-02 k3s-node-03
# Confirm all gone:
hcloud server list

# 2. Clean SSH mux (critical — prevents hanging)
rm -f ~/.ansible/cp/*

# 3. Provision fresh nodes
cd <repos>/dmf-env
bin/provision-nodes.sh

# 4. Verify nodes reachable
ssh -o ConnectTimeout=10 -i ~/.ssh/id_ed25519_k3s_hetzner k3s-admin@<node-01-ip> 'echo OK'
```

### Phase 2: Run site.yml

```bash
cd <repos>/dmf-env
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/site.yml
# Monitor in another terminal:
bin/monitor-playbook.sh /tmp/dmf-playbook-logs/site-<timestamp>.log
```

**Expected wall-clock:** ~45–60 min on clean cluster.

### Phase 3: Troubleshooting policy

If a phase fails, **do not improvise**. The bugs below are already fixed in-tree — they should NOT recur on a clean cluster. If something NEW breaks:

1. Document the error (copy from log)
2. Find the root cause
3. Commit fix to appropriate repo
4. Push to both remotes
5. Re-run from the failing phase:
   ```bash
   bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/phaseN-*.yml
   ```

### Known issues that should NOT recur on clean cluster

| Issue | Why it won't recur |
|-------|-------------------|
| Longhorn SC replacement blocked | Clean cluster has no stale PVCs |
| OpenBao re-init on sealed pod | Bug #8 fixed — parses rc=2 correctly |
| Authentik !Find syntax error | Bug #10 fixed — single-line Python |
| CF preflight wrong zone | Bug #6 fixed — extracts apex domain |
| CCM taint blocks CoreDNS | Bug #3 fixed — taint removed in phase 1 |
| k3s-verify unschedulable | Bug #2 fixed — tolerations added |
| DNS not ready for verify Service | Bug #4 fixed — nslookup wait added |
| LB assertion in phase 1 | Bug #5 fixed — non-fatal |
| Keychain locked | Bug #7 fixed — share 3 is file-based |
| Unseal keys missing on rerun | Bug #9 fixed — preloaded from break-glass |

### Potential issues that MAY still occur

| Issue | Recovery |
|-------|----------|
| SSH ControlMaster mux hangs (bug #12) | `pkill -f "ansible-playbook.*site.yml"; rm -f ~/.ansible/cp/*`; reconnect |
| ACME DNS-01 challenge slow | Certificate wait is now 10 min (60 retries × 10s). Should be enough. |
| Helm module stalls on broken mux | Same recovery as SSH hang. Helm pods may already be deployed. |
| Loki PVC not bound | Check if SC was replaced mid-run. Clean SC + PVC + rerun phase 3. |

### Phase 4: Post-run verification

After `site.yml` reports clean (exit code 0, PLAY RECAP shows `failed=0` for all hosts):

```bash
# 1. All nodes Ready
kubectl get nodes   # (via SSH to any node: ssh k3s-admin@<ip> sudo k3s kubectl get nodes)

# 2. Hetzner LB healthy
hcloud load-balancer list

# 3. Wildcard DNS matches tailnet IPs
dig +short *.dmf.example.com A

# 4. OpenBao unsealed
ls -la ~/secure/openbao-breakglass/hetzner-lab/share-{1,2,3}.json
ls -la /Volumes/OPENBAO_A/share-{4,5}.json
ls -la ~/secure/openbao-breakglass/hetzner-lab/openbao-keys-automation.json

# 5. Alertmanager Watchdog
# Check healthchecks.io dashboard — should show recent pings

# 6. Authentik reachable
curl -sk https://auth.dmf.example.com/ | head -5
```

### Phase 5: Clean up

```bash
# Shred old combined break-glass file (dead artifact)
shred -u ~/secure/openbao-breakglass/hetzner-lab/openbao-keys.json

# Write DR drill report
# Create `<note-store>/Projects/DMF DR Drill Report 2026-04-22-B.md`
# Include: start/end times, per-phase timings, failures+resolutions, verdict
```

---

## Exit criteria

- `site.yml` runs end-to-end unattended (phase 0 through phase 8) in under 90 minutes
- All playbooks pass with `failed=0` in PLAY RECAP
- 5 Shamir shares present at 5 destinations; automation file present with 3-share quorum
- Old `openbao-keys.json` shredded
- DR Drill Report written with timings + verdict (green/yellow/red)

---

## Key file locations

| Path | Purpose |
|------|---------|
| `dmf-infra/k3s-lab-bootstrap/site.yml` | Top-level orchestrator |
| `dmf-infra/k3s-lab-bootstrap/phase{0-8}-*.yml` | Phase wrappers |
| `dmf-infra/k3s-lab-bootstrap/playbooks/00-72-*.yml` | Individual playbooks (renumbered) |
| `dmf-env/bin/run-playbook.sh` | Wrapper with timeout + logging |
| `dmf-env/bin/monitor-playbook.sh` | Streaming log monitor |
| `/tmp/dmf-playbook-logs/` | All playbook logs |
| `~/secure/openbao-breakglass/hetzner-lab/` | OpenBao break-glass files |

## Critical operational rules (carry forward)

1. **Never use `| tail -N`** on ansible-playbook output — always write to file + stream-tail
2. **If playbook hangs >2× expected time**: SSH mux is degraded → kill process, remove cp socket, rerun
3. **Commit every fix** before rerunning — no hot-patches that don't end up in git
4. **Push to BOTH remotes** for every commit:
   - dmf-infra: `origin` (GitHub) + `forgejo` (homelab Forgejo)
   - dmf-env: `origin` (homelab Forgejo)
