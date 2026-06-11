# DMF Aliyun Frankfurt — Rollout Next Steps Handoff

**Date:** 2026-05-08
**Author:** Qwen (rollout session)
**Audience:** Next session — assume zero prior context.
**Current state:** Layer 1 (OpenTofu) ✅ complete. Layer 2+3 pending.

---

## 0. Boot for a freshly cleared agent

```bash
cd <repos>/dmfdeploy
git fetch && git pull
cd dmf-env && git fetch && git pull
cd dmf-infra && git fetch && git pull
export DMF_BOOTSTRAP_BUNDLE_DIR=<secure-store>/dmf-bootstrap
```

Then read, in order:

1. **This file** — current state and next actions.
2. `docs/reviews/dmf-aliyun-frankfurt-readiness-review-2026-05-08.md` — full readiness review (Phase A resolved, Phase B pending).
3. `docs/questions/aliyun-frankfurt-rollout-open-2026-05-08.md` — resolved open questions (Q1–Q4 + N1–N3).
4. `docs/handoffs/DMF Aliyun Frankfurt Audit + Phase A Handoff 2026-05-08.md` — prior session's Phase A audit findings.
5. `STATUS.md` — workspace state across all repos.

`git status` in each sub-repo before touching anything.

---

## 1. What was accomplished this session

### Layer 1 — OpenTofu ✅ (18 resources created)

| Resource | Status | Details |
|---|---|---|
| VPC `dmf-vpc` | ✅ Created | `vpc-gw8gqk3seakwtjcmjciel`, CIDR 10.0.0.0/16 |
| VSwitch `dmf-vswitch-private` | ✅ Created | `vsw-gw8o9jrtiynhlpuu451lp`, CIDR 10.0.0.0/24 |
| Security Group `k3s-nodes` | ✅ Created | 5 rules: SSH×IPv4, SSH×IPv6, HTTP, HTTPS, ICMP, intra-subnet |
| SSH Key Pair `k3s-aliyun` | ✅ Created | ed25519, uploaded to Alicloud |
| 3× ECS instances `k3s-node-{01,02,03}` | ✅ Running | `ecs.g8y.large` (2 vCPU, 8GB ARM/Yitian 710), Debian 13.4, 80GB cloud_essd |
| Cloudflare DNS records | ⏸ Guarded | `count=0` — awaiting SLB creation by CCM after cluster comes up |
| `hosts.ini` rendered | ✅ Generated | See `inventories/aliyun-frankfurt/hosts.ini` |

**Node inventory:**

| Node | Public IP | Private IP | SSH verified? |
|---|---|---|---|
| `k3s-node-01` | 47.87.135.133 | 10.0.0.223 | ✅ `k3s-admin` login works |
| `k3s-node-02` | 8.211.29.238 | 10.0.0.224 | — (expected same key, untested) |
| `k3s-node-03` | 47.87.142.151 | 10.0.0.225 | — (expected same key, untested) |

**State file:** `<secure-store>/terraform-states/aliyun-frankfurt/terraform.tfstate`

---

## 2. Blockers resolved during this session (for context)

| Issue | Fix |
|---|---|
| SOPS 3.12.x requires temp file to match creation rule | `mktemp -d)/${env_name}.sops.yaml` naming |
| SOPS doesn't auto-detect age key | Added `export SOPS_AGE_KEY_FILE` |
| `vpc:DescribeRouteTableList` account-level permission | Granted `AdministratorAccess` to dmfdeploy RAM user |
| `cloud_ssd` not supported for ARM64 in eu-central-1 | Changed to `cloud_essd` |
| IPv6 CIDR rejected by Alicloud security group API | Split IPv4/IPv6 rules; use `ipv6_cidr_ip` attribute |
| Alicloud SLB data source uses `.address` not `.ip_address` | Updated provider compat |
| `EXTRA_ARGS` unbound on `tofu init` | `${EXTRA_ARGS[@]+"${EXTRA_ARGS[@]}"}` guard |
| Duplicate `metadata:` block in YAML heredoc | Merged into single block |

---

## 3. Next steps — ordered rollout

> All commands run from `<umbrella-path>/dmf-env`.

### Step 1: Pre-seed provision (Layer 2+3)

Bootstraps k3s + OpenBao on the 3 fresh Aliyun nodes.

```bash
export DMF_BOOTSTRAP_BUNDLE_DIR=<secure-store>/dmf-bootstrap
bin/run-playbook.sh aliyun-frankfurt \
  <umbrella-path>/dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml
```

**Estimated:** 15–30 minutes (k3s HA etcd install, OpenBao deployment, network policies, ESO, Authentik break-glass verify).

**If it fails:** Check `/tmp/dmf-playbook-logs/bootstrap-provision-pre-seed-*.log`. The playbook is idempotent — re-run is safe.

### Step 2: Initialize + unseal in-cluster OpenBao

After Step 1 completes, find the OpenBao pod and initialize Shamir:

```bash
# Find the OpenBao pod
kubectl --context aliyun-frankfurt -n openbao get pods \
  -l app.kubernetes.io/name=openbao -o jsonpath='{.items[0].metadata.name}'

# Initialize Shamir (5 shares, threshold 3)
kubectl --context aliyun-frankfurt -n openbao exec <bao-pod-name> -- \
  bao operator init -key-shares=5 -key-threshold=3
```

**Capture the 5 unseal shares and root token.** Distribute per manifest's `share_distribution`:

| Share | Location | Command |
|---|---|---|
| Share 1 | JuiceFS | `echo "<share-1>" > <secure-store>/openbao-breakglass/aliyun-frankfurt/share-1.txt` |
| Share 2 | JuiceFS | `echo "<share-2>" > <secure-store>/openbao-breakglass/aliyun-frankfurt/share-2.txt` |
| Share 3 | macOS Keychain | `security add-generic-password -s openbao-breakglass-aliyun-frankfurt-share-3 -a share -w` |
| Share 4 | USB OPENBAO_A | Write to removable drive |
| Share 5 | USB OPENBAO_A | Write to removable drive |

**Unseal the pod:**

```bash
mkdir -p <secure-store>/openbao-breakglass/aliyun-frankfurt
# Then run the unseal skill (parametrization pending per Q2 decision)
# For now: manually unseal with 3 shares:
kubectl --context aliyun-frankfurt -n openbao exec <bao-pod-name> -- bao operator unseal
```

### Step 3: Seed pre-Bao bundle into OpenBao

```bash
export DMF_BOOTSTRAP_BUNDLE_DIR=<secure-store>/dmf-bootstrap
bin/bootstrap-secrets.sh seed-bao aliyun-frankfurt

# Seed AWX SSH key for control-node access
DMF_AWX_CONTROL_NODE_SSH_PATH=<secure-store>/awx-control-node.privkey \
  bin/bootstrap-secrets.sh seed-awx-control-node-ssh aliyun-frankfurt
```

**Important:** Before running, update `openbao_secrets.yml` with the real values (Q1/N1 resolution):

1. **`openbao_url`** → Tailscale IP of an aliyun node running OpenBao (after `321-tailscale.yml` runs)
2. **`openbao_role_id`** → mint a new AppRole via:
   ```bash
   bin/bootstrap-operator-approle.sh dmf-infra openbao-aliyun-frankfurt secret-id k3s-aliyun
   ```
   Then update `inventories/aliyun-frankfurt/group_vars/all/openbao_secrets.yml` with the new role_id.

### Step 4: Post-seed provision (monitoring + apps)

```bash
export DMF_BOOTSTRAP_BUNDLE_DIR=<secure-store>/dmf-bootstrap
bin/run-playbook.sh aliyun-frankfurt \
  <umbrella-path>/dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml
```

Installs Prometheus, Loki, Grafana, landing page, NetBox, Forgejo, AWX, LibreNMS, Zot, DMF CMS.

### Step 5: Tofu pass 2 — publish DNS records

After the ingress playbook creates the SLB:

```bash
bin/tf-apply.sh aliyun-frankfurt apply
```

This triggers `count = local.has_slb ? 1 : 0` → Cloudflare A records for `aliyun.<lan-host>` + `auth.aliyun.<lan-host>`.

### Step 6: Configure stage

```bash
export DMF_BOOTSTRAP_BUNDLE_DIR=<secure-store>/dmf-bootstrap
bin/run-playbook.sh aliyun-frankfurt \
  <umbrella-path>/dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml
```

Authentik OIDC, NetBox SoT, Forgejo bootstrap, AWX integration, CMS tokens.

### Step 7: Verify

```bash
bin/run-playbook.sh aliyun-frankfurt \
  <umbrella-path>/dmf-infra/k3s-lab-bootstrap/bootstrap-verify.yml

# Quick smoke tests
curl -sS https://aliyun.<lan-host>/
curl -sS https://auth.aliyun.<lan-host>/.well-known/openid-configuration
```

---

## 4. Known issues / pending decisions

### N1: `openbao_url` placeholder (Phase A #7a)
Currently `PLACEHOLDER — update after 321-tailscale.yml`. After Tailscale registers the nodes, find the node IP and update `inventories/aliyun-frankfurt/group_vars/all/openbao_secrets.yml`.

### N2: AppRole needs minting (Q1 decision B)
Per-env isolation: run `bin/bootstrap-operator-approle.sh dmf-infra openbao-aliyun-frankfurt secret-id k3s-aliyun` after OpenBao is unsealed.

### N3: `bin/unseal-openbao.sh` parametrization (Q2 decision A)
Decision: parametrize, not fork. Phase B item. For now, unseal manually via `bao operator unseal` × 3 shares.

### S6: SSH user keypair auto-generation
`bin/tf-apply.sh` auto-generates the AWX keypair but NOT the user SSH keypair (`~/.ssh/id_ed25519_k3s_aliyun`). This was created manually during this session. For future env creation, add a check to `tf-apply.sh`.

### Phase B backlog
1. Parametrize `bin/unseal-openbao.sh` for env argument
2. Implement `tasks/aliyun_security_group.yml` for runtime drift reconciliation
3. Add aliyun section to `DEPLOYMENT.md`
4. Remove ephemeral password lookups from `inventories/aliyun-frankfurt/group_vars/all/bootstrap.yml` once seed-bao is canonical

---

## 5. Reference: key files and commands

### Credentials (never commit)
| Secret | Location |
|---|---|
| Alicloud AK/SK | `~/.secure/aliyun/.ay-dmfdeploy` |
| Cloudflare DNS token | `~/.config/cf/dns.txt` |
| SOPS age key | `~/.config/sops/age/keys.txt` |
| Aliyun SSH key | `~/.ssh/id_ed25519_k3s_aliyun{,.pub}` |
| AWX control-node key | `~/.config/dmf/awx-control-node.pub` + `<secure-store>/awx-control-node.privkey` |
| OpenBao breakglass | `<secure-store>/openbao-breakglass/aliyun-frankfurt/` (after init) |

### Scripts
| Script | Purpose |
|---|---|
| `bin/tf-apply.sh aliyun-frankfurt <subcmd>` | Tofu wrapper — loads Alicloud creds automatically |
| `bin/run-playbook.sh aliyun-frankfurt <playbook>` | Ansible wrapper — loads SOPS bundle + secrets |
| `bin/bootstrap-secrets.sh init aliyun-frankfurt` | Create encrypted SOPS bundle |
| `bin/bootstrap-secrets.sh doctor aliyun-frankfurt` | Validate bundle health |
| `bin/bootstrap-secrets.sh seed-bao aliyun-frankfurt` | Seed bundle into OpenBao |
| `bin/tf-render-inventory.sh aliyun-frankfurt` | Re-render hosts.ini from Tofu state |

### Environment variables
```bash
export DMF_BOOTSTRAP_BUNDLE_DIR=<secure-store>/dmf-bootstrap
```

### Aliyun CLI (for troubleshooting)
```bash
# List instances
. ~/.secure/aliyun/.ay-dmfdeploy
aliyun --profile dmfdeploy --region eu-central-1 ecs DescribeInstances
```

---

## 6. Decision tree on entry

- **No steps done yet** → Start at Step 1. Each step depends on the previous completing successfully.
- **Step 1 in progress / failed** → Check playbook logs in `/tmp/dmf-playbook-logs/`. Re-run is safe (idempotent).
- **Step 1 complete, Step 2 pending** → Ensure OpenBao pod is running, then init + unseal.
- **Step 2 complete, Step 3 pending** → Update `openbao_secrets.yml` with real URL + role_id first.
- **Any step fails** → Cluster state is the truth. `kubectl --context aliyun-frankfurt get pods --all-namespaces` to diagnose.

---

_This handoff is authoritative for the Aliyun Frankfurt rollout. After completing all steps, update `STATUS.md` HUMAN-START section and write a new handoff in `docs/handoffs/`._
