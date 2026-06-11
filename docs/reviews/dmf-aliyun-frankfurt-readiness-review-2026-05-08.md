# Aliyun Frankfurt — Fresh Cluster Readiness Review

**Date:** 2026-05-08
**Author:** Claude (audit pass)
**Audience:** Next session — assume zero prior context.
**Verdict:** 🛑 **Not ready to roll out.** Manifest, Tofu module and inventory are sound, but four blockers in the bootstrap path will halt a fresh build before the cluster reaches a usable state. Phase A fixes below unblock; estimated 3–4 hours.

---

## 0. Boot for a freshly cleared agent

Before reading the rest of this doc:

```bash
cd <repos>/dmfdeploy
git fetch && git pull
bin/generate-status.sh --no-fetch
```

Then read, in order:

1. `STATUS.md` — workspace state across all 6 component repos.
2. `CLAUDE.md` — boot ritual + workspace map.
3. `docs/handoffs/DMF Bootstrap Implementation Progress Handoff 2026-05-08.md` — what landed in the Tier 1 bootstrap split (the refactor referenced in this review).
4. `docs/decisions/INDEX.md` — relevant ADRs:
   - **0007** secrets-never-in-argv
   - **0008** openbao-secrets-architecture
   - **0009** shamir-dr-model
   - **0010** run-playbook-as-sanctioned-entry
   - **0012** configure-stage-distinct-from-provision
   - **0016** awx-control-node-ssh-via-cloud-init-and-openbao

`git status` in any sub-repo before you touch it. The umbrella's `.gitignore` excludes the 6 component dirs; each is an independent git repo (see `CLAUDE.md` §"Git topology").

---

## 1. Scope

The user added an `aliyun-frankfurt` environment (Alibaba Cloud ECS, ARM64 Yitian 710, eu-central-1) on 2026-05-08, after the bootstrap provision/configure split landed. Goal: deploy a fresh k3s cluster on Aliyun using the new pre-seed/post-seed/configure split.

This review covers:

- Sanity check: does the environment provision end-to-end with no manual fixups?
- Security check: secrets posture, SSH allowlist, SOPS recipients, role-id reuse.
- Rollout procedure: ordered steps once the blockers are cleared.

Out of scope: rolling forward day-2 operations, Layer 4/5 media-domain work (manifest disables both — `media_exchange.enabled: false`, `media_functions.enabled: false`).

---

## 2. What's already in place (working pieces)

| Area | File | Status |
|---|---|---|
| Resource Profile manifest | `dmf-env/manifests/aliyun-frankfurt.yaml` | Complete — declares 3-node g8y.large ARM cluster, eu-central-1a, VPC `dmf-vpc`, VSwitch `dmf-vswitch-private`, SLB `dmf-traefik-slb`, public+private ingress lanes, Authentik/Forgejo/Grafana/NetBox/AWX/CMS/LibreNMS/Zot apps, prometheus+loki+grafana monitoring, ESO orchestration, OpenBao secrets backend, breakglass shamir 3-of-5. |
| Tofu module | `dmf-env/terraform/aliyun-frankfurt/{main,outputs,versions}.tf` + `dmf-env/terraform/modules/aliyun-cluster/` | Complete — VPC + VSwitch + Security Group (SSH from allowlist, 80/443 wide, ICMP, intra-subnet) + 3 ECS instances (g8y.large, Debian 13.4 ARM64) + cloud-init user-data + Cloudflare A records for `aliyun.<lan-host>` + `auth.aliyun.<lan-host>`. State on JuiceFS at `<secure-store>/terraform-states/aliyun-frankfurt/`. |
| Tofu provider creds path | `dmf-env/bin/tf-apply.sh` lines 69–90 | Aliyun branch wired — reads `~/.secure/aliyun/.ay-dmfdeploy` (ALIYUN_ACCESS_KEY_ID / ALIYUN_ACCESS_KEY_SECRET), exports as `TF_VAR_alicloud_*`. ADR-0007 satisfied. |
| Inventory `main.yml` | `dmf-env/inventories/aliyun-frankfurt/group_vars/all/main.yml` | Complete — eth1 private NIC, cloud-native ingress mode, Cloudflare DNS-01 wildcard, harden allowlist matches Vultr operator VPS, Longhorn replica 2, host vars for all apps. |
| `.sops.yaml` scaffold | `dmf-env/.sops.yaml` | Has block for `aliyun-frankfurt.sops.yaml` recipient — but value is **`# TODO: replace…`** (see §4 S1). |

---

## 3. Sanity check — findings

### 3.1 BLOCKER: `219-host-verify.yml` is hard-coded to Hetzner Cloud CLI

**File:** `dmf-infra/k3s-lab-bootstrap/playbooks/219-host-verify.yml` lines 36–73.

This is the bootstrap-preflight playbook (tagged `bootstrap-preflight` per the Tier 1 refactor) and the very first thing `bootstrap-provision-pre-seed.yml` runs. It unconditionally invokes:

```yaml
- name: Check hcloud CLI is available
  ansible.builtin.command: which hcloud
- name: Verify Hetzner API connectivity
  ansible.builtin.command: hcloud server list
- name: Verify Hetzner private network exists
  ansible.builtin.command: hcloud network list
- name: Check SSH keys in Hetzner
  ansible.builtin.command: hcloud ssh-key list
- name: Check Hetzner Load Balancer state
  ansible.builtin.command: hcloud load-balancer list
```

On `aliyun-frankfurt`, `which hcloud` may pass (the operator has hcloud installed for hetzner-arm) but `hcloud server list` will return Hetzner servers that have nothing to do with this environment, and the assertion at line 53 will misleadingly report "will be destroyed before rebuild." If hcloud is *not* installed, task 36 fails-closed and the entire pre-seed pipeline aborts.

**Fix:** environment-aware preflight. Either:
- (a) Split the hcloud block into `playbooks/preflight/hetzner.yml`, add a sibling `aliyun.yml` (using `aliyun ecs DescribeInstances` via the `alicloud` collection, or accept "no preflight" for now), and dispatch via an inventory var like `cloud_provider`; or
- (b) Gate the hcloud block with `when: cluster_ingress_provider_tasks is search('hetzner_ccm')`.

(b) is the smaller change and matches the convention already used for `harden_cloud_firewall_tasks` / `cluster_ingress_provider_tasks`.

### 3.2 BLOCKER: `tasks/aliyun_slb.yml` is a `debug:` stub

**File:** `dmf-env/tasks/aliyun_slb.yml` (13 lines, all comment + a single `debug: msg=…` task).

`inventories/aliyun-frankfurt/group_vars/all/main.yml:24` sets `cluster_ingress_provider_tasks: "{{ inventory_dir }}/../../tasks/aliyun_slb.yml"`. The generic ingress role calls into this, expecting it to install the Alibaba Cloud Cloud Controller Manager (CCM) so that the public-ingress `Service: LoadBalancer` for Traefik gets an SLB IP.

Without it:
- Traefik LoadBalancer Service stays in `Pending` indefinitely
- `terraform/modules/aliyun-cluster/main.tf:156–158` (`data "alicloud_slbs" "dmf_traefik"`) returns zero results
- Cloudflare A-records at lines 165–183 reference `data.alicloud_slbs.dmf_traefik.slbs[0].ip_address` → **Tofu panics with index-out-of-range**

**Fix:** mirror `dmf-env/tasks/hetzner_ccm.yml` (use it as a template — the comment on line 8 says so). Implement steps:

1. Create the `cloud-controller-manager` namespace + ServiceAccount + ClusterRoleBinding.
2. Create a Secret holding the Alicloud AccessKey/Secret (sourced from `vault_alicloud_access_key` / `vault_alicloud_secret_key` — see §3.4 — never from argv).
3. Apply the upstream Alicloud CCM manifest pinned to a specific version (latest stable as of audit: check https://github.com/kubernetes/cloud-provider-alibaba-cloud/releases).
4. Configure with `--cloud-config` referencing the Secret, region `eu-central-1`, VPC ID, VSwitch ID — all from inventory vars or Tofu outputs.
5. Wait for the CCM Deployment to become Ready before exiting.

Until this is wired, **also wrap the Cloudflare resources in Tofu in a two-pass guard**, e.g. with `count = length(data.alicloud_slbs.dmf_traefik.slbs) > 0 ? 1 : 0`. First-pass apply provisions infra without DNS; second-pass after the ingress playbook publishes A-records.

### 3.3 MEDIUM: `tasks/aliyun_security_group.yml` is a `debug:` stub

**File:** `dmf-env/tasks/aliyun_security_group.yml`.

`harden_cloud_firewall_tasks` points at it. The Tofu module already declares the SG inline in `terraform/modules/aliyun-cluster/main.tf:51–110`, so this is non-blocking for the first apply, but re-running `210-harden.yml` on a live cluster won't reconcile drift (e.g., if the SSH allowlist changes in inventory). Acceptable for experiment phase — flag for follow-up.

### 3.4 BLOCKER: `bootstrap-secrets.sh` has no Aliyun branch

**File:** `dmf-env/bin/bootstrap-secrets.sh`.

Three places reject `aliyun-frankfurt`:

- **Line 235** `validate_bundle_schema`: `if not hcloud.get('token'): print('ERROR: providers.hcloud.token is required'); sys.exit(1)`. Hard-codes hcloud as required.
- **`cmd_init` lines 324–353**: only collects `providers.hcloud.token` (reads from `~/.config/hcloud/cli.toml`). No prompt for Alicloud AK/SK.
- **`cmd_seed_bao` lines 743–754**: only writes `secret/platform/hetzner` from `providers.hcloud.token`. Nothing for Alicloud, no `secret/platform/aliyun` path.

The manifest at `dmf-env/manifests/aliyun-frankfurt.yaml:76–78` declares the seed paths the cluster will read from:

```yaml
tokens:
  cloud_api: "openbao:secret/k3s-aliyun/credentials#alicloud_access_key"
  dns_api:   "openbao:secret/k3s-aliyun/credentials#cloudflare_dns_token"
```

…but no operator-side code writes to `secret/k3s-aliyun/credentials` (or `secret/platform/aliyun`).

**Fix:** make the bundle provider-section env-aware.

1. In `validate_bundle_schema`: require *one of* `providers.hcloud.token` or `providers.alicloud.access_key`+`.secret_key`, dispatched on `data.metadata.environment` prefix (`aliyun-*` vs `hetzner-*`).
2. In `cmd_init`: read AK/SK from `~/.secure/aliyun/.ay-dmfdeploy` (same source `bin/tf-apply.sh:74–78` already uses; format is shell-style `KEY=VALUE` lines). Mirror the hcloud prompt-on-fallback pattern so the bundle can still be hand-built if the file is missing. Optionally store `aliyun_vswitch_id` here too (or read it from Tofu output — see §3.5).
3. In `cmd_seed_bao`: add an aliyun branch writing `secret/platform/aliyun` with `access_key`, `secret_key`, `vswitch_id` (and any other Tofu-derived fields the CCM needs).
4. In `cmd_export_vars`: add mappings `vault_alicloud_access_key`, `vault_alicloud_secret_key`, `vault_alicloud_vswitch_id`. Mirror the existing `vault_hcloud_token` pattern.

Per ADR-0007, all three of these must use stdin/file transport — never argv.

### 3.5 BLOCKER: `export-openbao-vars.sh` has no Aliyun branch

**File:** `dmf-env/bin/export-openbao-vars.sh`.

This is the legacy wrapper that `bin/run-playbook.sh:85` still calls. It reads only `~/.config/hcloud/cli.toml` and emits `vault_hcloud_token`. Nothing for `vault_alicloud_*`.

The `aliyun_vswitch_id` referenced by `inventories/aliyun-frankfurt/group_vars/all/main.yml:29` is therefore an empty string at runtime → SLB annotation `service.beta.kubernetes.io/alibaba-cloud-loadbalancer-vswitch-id: ""` → the Alicloud CCM rejects the Service.

**Fix path A (cleanest):** retire `export-openbao-vars.sh` entirely and switch `bin/run-playbook.sh:85` to call `bin/bootstrap-secrets.sh export-vars "$ENV_NAME" "$TMP_VARS_FILE"`. This was the eventual plan per the 2026-05-08 handoff. Once §3.4 is fixed, this is a one-line wrapper change.

**Fix path B (additive):** add an aliyun branch to `export-openbao-vars.sh` mirroring the hetzner one. Smaller diff, but doubles the surface area to maintain.

Recommend path A — the legacy wrapper is now superseded by the SOPS+age bundle flow.

Also: `outputs.tf` does not currently expose `vswitch_id`. Add:

```hcl
output "vswitch_id" {
  description = "VSwitch ID for the Alicloud CCM SLB annotation."
  value       = module.cluster.vswitch_id
}
```

…and a matching output in `terraform/modules/aliyun-cluster/outputs.tf`. The seed-bao step then reads it via `tofu -chdir=terraform/aliyun-frankfurt output -raw vswitch_id`.

### 3.6 HIGH: `openbao_secrets.yml` schema mismatch

**File:** `dmf-env/inventories/aliyun-frankfurt/group_vars/all/openbao_secrets.yml`.

Current contents:

```yaml
openbao_secrets_role_id: "85e58ff2-7388-b9cf-2fed-ea52869d8603"
openbao_url: "https://<wg-mesh-ip>:8200"
openbao_keychain_service: "openbao-aliyun-frankfurt"
```

Compare to the canonical hetzner-arm (`dmf-env/inventories/hetzner-arm/group_vars/all/openbao_secrets.yml`):

```yaml
openbao_url: "https://<wg-mesh-ip>:8200"
openbao_role_id: "85e58ff2-7388-b9cf-2fed-ea52869d8603"
openbao_secret_path: "secret/data/k3s-hetzner/credentials"
openbao_keychain_service: "openbao-approle-dmf-infra"
openbao_keychain_account: "secret-id"
```

Issues:

1. Var name inconsistency — `openbao_secrets_role_id` vs `openbao_role_id`. Roles look up `openbao_role_id`; aliyun's name will resolve to nothing.
2. Missing `openbao_secret_path` (the kv-v2 doc the legacy wrapper fetches).
3. Missing `openbao_keychain_account`.

**Fix:** rewrite `dmf-env/inventories/aliyun-frankfurt/group_vars/all/openbao_secrets.yml` to:

```yaml
openbao_url: "https://<wg-mesh-ip>:8200"
openbao_role_id: "<aliyun-specific role_id>"   # see security S2 below — confirm whether to reuse or mint new
openbao_secret_path: "secret/data/k3s-aliyun/credentials"
openbao_keychain_service: "openbao-aliyun-frankfurt"
openbao_keychain_account: "secret-id"
```

### 3.7 LOW: `bootstrap.yml` uses ephemeral password lookups

**File:** `dmf-env/inventories/aliyun-frankfurt/group_vars/all/bootstrap.yml`.

`lookup('password', '/dev/null length=…')` mints a fresh value every Ansible run because `/dev/null` is the persistence target. These are overridden by `vault_*` vars from main.yml/seed-bao when present, but they're still loaded. Cosmetic; leave for cleanup once seed-bao is the single source.

### 3.8 LOW: DEPLOYMENT.md has zero aliyun mentions

**File:** `dmf-env/DEPLOYMENT.md`.

Greps to `hetzner-arm` only. After Phase A fixes, append an aliyun section mirroring the generic quickstart.

### 3.9 OK: Tofu module otherwise sane

`terraform/modules/aliyun-cluster/main.tf` is a clean port of the hetzner pattern — VPC + VSwitch + SG + 3 ECS instances, cloud-init user-data renders both `id_ed25519_k3s_aliyun.pub` and `awx-control-node.pub` into `ssh_authorized_keys`, `lifecycle.ignore_changes = [user_data, security_groups, key_name]` matches the hetzner convention. Image pinned to `debian_13_4_arm64_20G_alibase_20260414.vhd` (queried 2026-05-08 — verify still available before apply, Alicloud rotates these).

---

## 4. Security check — findings

### S1. HIGH: `.sops.yaml` recipient is a TODO placeholder

**File:** `dmf-env/.sops.yaml` lines 14, 22.

Both `hetzner-arm.sops.yaml` and `aliyun-frankfurt.sops.yaml` blocks have:

```yaml
age: >-
  # TODO: replace with your age public key (output of age-keygen -y <keyfile>)
  # e.g. age1q6...xyz
```

`bootstrap-secrets.sh cmd_init` (line 446) bypasses creation_rules by passing `--age "${pub_key}"` explicitly, so initial encryption works. But any `sops --encrypt --in-place` (e.g., the rotation path at line 187, line 446 of `bundle_set`, the metadata-update path at line 857) reads the recipient from `.sops.yaml` and will fail.

**Fix:** before first `init aliyun-frankfurt`:

```bash
age-keygen -y ~/.config/sops/age/keys.txt   # prints the pubkey
```

…then paste into both blocks of `dmf-env/.sops.yaml`. The same age keypair covers both envs.

### S2. MEDIUM: AppRole role_id reused across environments

**Both** `inventories/hetzner-arm/group_vars/all/openbao_secrets.yml` and `aliyun-frankfurt/group_vars/all/openbao_secrets.yml` carry `openbao_role_id: 85e58ff2-7388-b9cf-2fed-ea52869d8603`.

The `openbao_keychain_service` values differ (`openbao-approle-dmf-infra` vs `openbao-aliyun-frankfurt`), suggesting *different secret IDs* but the *same role*. Either:
- Intentional: a single AppRole `dmf-infra` whose policy permits `secret/data/k3s-hetzner/*` AND `secret/data/k3s-aliyun/*`. One role, per-env secret_id rotation. Acceptable.
- Copy-paste leak: aliyun should have its own role with policy scoped to `secret/data/k3s-aliyun/*` only.

**Action:** confirm intent with operator before rollout. If new role is needed, generate via `bin/cluster-bootstrap-operator-approle.sh` or similar and update both `openbao_secrets.yml` and the `manifests/aliyun-frankfurt.yaml:135-137` block.

### S3. INFO: <wg-mesh-ip> reachability

`openbao_url: https://<wg-mesh-ip>:8200` is the operator-side OpenBao reached via Tailscale. Operator-side scripts (`bin/run-playbook.sh`, `bin/bootstrap-secrets.sh seed-bao`) need a route. Confirm Tailscale is up before seed-bao runs (standard hetzner workflow already assumes this).

### S4. OK: Tofu provider creds clean

`bin/tf-apply.sh:74–90` reads `~/.secure/aliyun/.ay-dmfdeploy` (mode 0400, outside any git tree) and exports as `TF_VAR_alicloud_*`. No argv leak, no transcript leak, no repo leak. Mirrors the hetzner pattern. ADR-0007 satisfied.

### S5. OK: SSH allowlist matches operator posture

`harden_ssh_allow_ipv4: ["140.82.39.12/32"]` (Vultr operator VPS, confirmed 2026-04-16 per inline comment).
`harden_ssh_allow_ipv6: ["2a05:f480:1800:b82:5400:5ff:fed9:a4ae/128"]`.
TCP 80/443 from 0.0.0.0/0, ICMP from 0.0.0.0/0 — expected for public ingress; matches the experiment-phase stance per ADR-0004.

### S6. MEDIUM: SSH user keypair must exist before tofu apply

`terraform/modules/aliyun-cluster/main.tf:33` reads `file(pathexpand(var.ssh_pubkey_path))` (default `~/.ssh/id_ed25519_k3s_aliyun.pub`). `bin/tf-apply.sh:152–160` auto-generates the AWX SSH keypair via `bin/generate-awx-control-node-keypair.sh` if missing, but **does not** auto-generate the user SSH keypair.

**Fix:** add a check at the top of `tf-apply.sh` (or document as a prerequisite). One-liner:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_k3s_aliyun -C "k3s-admin@aliyun-frankfurt" -N ""
```

### S7. INFO: SSH key-pair name collision risk

`var.ssh_key_pair_name = "k3s-aliyun"` (default). Tofu apply will fail if a stale Alicloud key-pair with that name exists in the account. Run `aliyun ecs DescribeKeyPairs` (or check the console) before first apply.

### S8. OK: Tofu state on JuiceFS

`<secure-store>/terraform-states/aliyun-frankfurt/terraform.tfstate`. State will contain the access key as a `sensitive` attribute — acceptable, JuiceFS-only, never to git.

### S9. HIGH: OpenBao breakglass + unseal flow not wired for aliyun

The manifest declares Shamir 3-of-5 with shares 1+2 on JuiceFS, share 3 on macos-keychain (`manifests/aliyun-frankfurt.yaml:138-148`). But:

- `<secure-store>/openbao-breakglass/aliyun-frankfurt/` directory does not yet exist.
- `bin/unseal-openbao.sh` (per skill `dmf-openbao-unseal`) is hetzner-arm-specific. Confirm it accepts an environment argument or fork it for aliyun.
- The keychain entry for the aliyun OpenBao needs to be created (likely via `security add-generic-password` keyed on `openbao-aliyun-frankfurt` keychain service after `bao operator init`).

**Fix:** before seed-bao step in the rollout, the operator must run `bao operator init` against the freshly-deployed in-cluster OpenBao, capture the 5 unseal shares, distribute per the manifest. Document this step explicitly in the rollout playbook.

### S10. LOW: Docker socket path in committed env

`dmf_cms_host` block: `cms_docker_socket: unix://$HOME/.colima/docker-build/docker.sock` (line 119 of main.yml). Not a secret leak, but operator-mac specific; same as hetzner. Flag for cleanup in a future "make env CI-friendly" pass.

### S11. OK: gitleaks + scrub coverage

`gitleaks` pre-commit + `bin/scrub-public-repos.sh` cover the 5 public repos. `dmf-env` has no remote so nothing leaves the local clone. Inventory commit on 2026-05-08 (ae46a6a → 5783c1f) only contains role IDs + non-secret metadata; verified clean.

---

## 5. Phase A — must-fix before any apply

Estimated 3–4 hours for an experienced Ansible/Tofu operator.

| # | File | Change | Verify with |
|---|---|---|---|
| 1 | `dmf-infra/k3s-lab-bootstrap/playbooks/219-host-verify.yml` | Gate hcloud block with `when: cluster_ingress_provider_tasks is search('hetzner_ccm')`. Optionally add a parallel aliyun block (or skip preflight for aliyun until §2 implemented). | `bin/run-playbook.sh aliyun-frankfurt ../dmf-infra/k3s-lab-bootstrap/playbooks/219-host-verify.yml --check` (after Tofu apply so localhost has an inventory to load) |
| 2 | `dmf-env/tasks/aliyun_slb.yml` | Implement Alicloud CCM install — namespace, ServiceAccount, ClusterRoleBinding, Secret with AK/SK from `vault_alicloud_*`, upstream CCM manifest pinned, wait for Ready. Mirror `dmf-env/tasks/hetzner_ccm.yml`. | After §3 implemented: `bin/run-playbook.sh aliyun-frankfurt ../dmf-infra/k3s-lab-bootstrap/playbooks/310-ingress-public.yml`; check `kubectl -n kube-system get deploy cloud-controller-manager` Ready and `kubectl -n traefik get svc traefik -o jsonpath='{.status.loadBalancer.ingress[0].ip}'` returns an IP. |
| 3 | `dmf-env/bin/bootstrap-secrets.sh` | Add aliyun branch to `validate_bundle_schema` (require alicloud OR hcloud based on `metadata.environment` prefix), `cmd_init` (read `~/.secure/aliyun/.ay-dmfdeploy`), `cmd_seed_bao` (write `secret/platform/aliyun` with access_key, secret_key, vswitch_id), `cmd_export_vars` (emit `vault_alicloud_*`). | `DMF_BOOTSTRAP_BUNDLE_DIR=$HOME/secure/dmf-bootstrap bin/bootstrap-secrets.sh init aliyun-frankfurt && bin/bootstrap-secrets.sh doctor aliyun-frankfurt` — all checks PASS. |
| 4 | `dmf-env/bin/run-playbook.sh:85` | Replace `"$SCRIPT_DIR/export-openbao-vars.sh" "$ENV_NAME" "$TMP_VARS_FILE"` with `"$SCRIPT_DIR/bootstrap-secrets.sh" export-vars "$ENV_NAME" "$TMP_VARS_FILE"`. (After §3 makes export-vars provider-aware.) Optional: delete `export-openbao-vars.sh` once hetzner-arm flow re-tested. | `bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/playbooks/200-baseline.yml --check` (regression-test hetzner) and same for aliyun. |
| 5 | `dmf-env/terraform/aliyun-frankfurt/main.tf` lines 165–183 + `outputs.tf` | Wrap `cloudflare_record.cluster_apex` and `cloudflare_record.cluster_auth` in `count = length(data.alicloud_slbs.dmf_traefik.slbs) > 0 ? 1 : 0`. Add `output "vswitch_id"` to both `outputs.tf` and the module's `outputs.tf`. This permits a two-pass apply (infra first, ingress second, DNS via re-apply). | `bin/tf-apply.sh aliyun-frankfurt plan` — should produce a plan even when SLB doesn't exist yet. |
| 6 | `dmf-env/.sops.yaml` lines 14, 22 | Replace both TODO placeholders with `age-keygen -y ~/.config/sops/age/keys.txt` output. | `sops --encrypt --in-place /tmp/throwaway.yaml` (where the file matches a `path_regex`) — should succeed. |
| 7 | `dmf-env/inventories/aliyun-frankfurt/group_vars/all/openbao_secrets.yml` | Rename `openbao_secrets_role_id` → `openbao_role_id`. Add `openbao_secret_path: "secret/data/k3s-aliyun/credentials"` and `openbao_keychain_account: "secret-id"`. Confirm role_id intent (S2) — either keep shared `85e58ff2-…` or mint new. | `ansible-inventory -i inventories/aliyun-frankfurt --list 2>&1 | jq '.["_meta"].hostvars[][\"openbao_role_id\"]'` returns the value (not null). |

---

## 6. Phase B — nice-to-have before first prod-style use

| # | Item |
|---|---|
| 1 | Implement (or fork) `bin/unseal-openbao.sh` to accept `aliyun-frankfurt` and read shares from the manifest-declared paths. Confirm JuiceFS share 1+2 + keychain share 3 are stored after `bao operator init`. |
| 2 | Implement `dmf-env/tasks/aliyun_security_group.yml` for runtime drift reconciliation (mirror `tasks/hetzner_firewall.yml`). |
| 3 | Add aliyun section to `dmf-env/DEPLOYMENT.md` quickstart. |
| 4 | Remove the now-defunct `lookup('password', '/dev/null …')` lines from `inventories/aliyun-frankfurt/group_vars/all/bootstrap.yml` once seed-bao is the canonical path. |
| 5 | Add post-rollout entry to `STATUS.md` HUMAN-START section + a session handoff. |

---

## 7. Rollout procedure (after Phase A complete)

> All commands run from `<umbrella-path>/dmf-env`. The rollout is **two-pass for Tofu** (infra → ingress → DNS).

```bash
# 0. Boot ritual
cd <repos>/dmfdeploy && git fetch && git pull && bin/generate-status.sh
cd dmf-env

# 1. Operator-machine prerequisites — fail fast if any are missing
ls -la ~/.ssh/id_ed25519_k3s_aliyun{,.pub}             # if missing: ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_k3s_aliyun -N ""
test -f ~/.secure/aliyun/.ay-dmfdeploy                  # ALIYUN_ACCESS_KEY_ID + ALIYUN_ACCESS_KEY_SECRET, mode 0400
test -f ~/.config/cf/dns.txt                            # Cloudflare zone-edit token for <lan-host>
test -f ~/.config/sops/age/keys.txt                     # age private key, mode 0600
age-keygen -y ~/.config/sops/age/keys.txt               # paste pubkey into dmf-env/.sops.yaml under aliyun-frankfurt block (S1)
ls <secure-store>/                                 # JuiceFS mounted

# 2. Pre-seed bundle (encrypted SOPS+age)
export DMF_BOOTSTRAP_BUNDLE_DIR=$HOME/secure/dmf-bootstrap
bin/bootstrap-secrets.sh init aliyun-frankfurt           # interactive — collects admin creds + AK/SK + Cloudflare token
bin/bootstrap-secrets.sh doctor aliyun-frankfurt         # all PASS expected
bin/bootstrap-secrets.sh status aliyun-frankfurt

# 3. Layer 1 — Tofu pass 1 (infra only; DNS guarded behind length check per fix #5)
bin/tf-apply.sh aliyun-frankfurt init
bin/tf-apply.sh aliyun-frankfurt plan
bin/tf-apply.sh aliyun-frankfurt apply
# This generates inventories/aliyun-frankfurt/hosts.ini

# 4. Layer 2+3 — pre-seed provision (host hardening, k3s, OpenBao install, network policies, ESO, Authentik break-glass-verify)
bin/run-playbook.sh aliyun-frankfurt ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml \
    --tags bootstrap-preflight                            # smoke-test the env-aware preflight first
bin/run-playbook.sh aliyun-frankfurt ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml

# 5. Initialize + unseal the in-cluster OpenBao
#    Captures unseal shares 1-5; distribute per manifest's share_distribution
bao_pod=$(kubectl --context aliyun-frankfurt -n openbao get pods -l app.kubernetes.io/name=openbao -o jsonpath='{.items[0].metadata.name}')
kubectl --context aliyun-frankfurt -n openbao exec "$bao_pod" -- bao operator init -key-shares=5 -key-threshold=3
# Save shares per manifest paths:
#   share 1 → <secure-store>/openbao-breakglass/aliyun-frankfurt/share-1.txt
#   share 2 → <secure-store>/openbao-breakglass/aliyun-frankfurt/share-2.txt
#   share 3 → security add-generic-password -s openbao-aliyun-frankfurt -a unseal-share-3 -w
#   shares 4,5 → USB OPENBAO_A
# Unseal:
bin/unseal-openbao.sh aliyun-frankfurt                    # follow skill dmf-openbao-unseal §0

# 6. Seed pre-Bao bundle into OpenBao (platform paths + per-app admin paths)
bin/bootstrap-secrets.sh seed-bao aliyun-frankfurt
DMF_AWX_CONTROL_NODE_SSH_PATH=<secure-store>/awx-control-node.privkey \
  bin/bootstrap-secrets.sh seed-awx-control-node-ssh aliyun-frankfurt

# 7. Layer 6 — post-seed provision (monitoring + landing/netbox/forgejo/awx/cms)
bin/run-playbook.sh aliyun-frankfurt ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml

# 8. Tofu pass 2 — now that the SLB exists, publish Cloudflare A-records
bin/tf-apply.sh aliyun-frankfurt apply

# 9. Configure stage (Authentik OIDC, NetBox SoT, Forgejo bootstrap, AWX integration, CMS tokens)
bin/run-playbook.sh aliyun-frankfurt ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml

# 10. Verify
bin/run-playbook.sh aliyun-frankfurt ../dmf-infra/k3s-lab-bootstrap/bootstrap-verify.yml
curl -sS https://aliyun.<lan-host>/                             # landing page → 200
curl -sS https://auth.aliyun.<lan-host>/.well-known/openid-configuration   # Authentik

# 11. Update STATUS.md HUMAN-START + write handoff
$EDITOR <umbrella-path>/STATUS.md
$EDITOR <umbrella-path>/docs/handoffs/DMF\ Aliyun\ Frankfurt\ Rollout\ $(date +%Y-%m-%d).md
```

---

## 8. Decision tree on entry

If you (the next agent) are picking this up cold:

- **No fixes applied yet** → start at §5 Phase A, item 1. Each item is independent until items 4 & 5 (sequencing matters: 4 depends on 3, 5 is independent).
- **Phase A items 1-3 done, 4-7 pending** → keep going down §5; do not start the rollout.
- **All Phase A items done, no apply yet** → §7 step 1, sanity-check prerequisites first.
- **Apply started, hit a failure** → check `/tmp/dmf-tofu-logs/aliyun-frankfurt-*.log` and `/tmp/dmf-playbook-logs/*.log`. Cluster state is the truth — if Tofu state diverges from reality, run `tofu state list` and reconcile via `tofu import` / `tofu state rm`. Do NOT run `tofu destroy` without operator confirmation (per CLAUDE.md "Executing actions with care").

---

## 9. Why this matters for the platform

This is the first multi-cloud rollout. Hetzner-arm worked because every script implicitly assumed Hetzner. The aliyun rollout exposes the seams. After Phase A, `bin/bootstrap-secrets.sh` and `bin/run-playbook.sh` become genuinely environment-aware, which sets up future environments (`flypack-01` per `dmf-env/CLAUDE.md` example, or another cloud) with no further provider-special-casing in the bootstrap path.

The bootstrap provision/configure split (Tier 1, 2026-05-08) was intentionally agnostic — it just imports the existing numbered playbooks. The provider-specific bits live in `dmf-env/tasks/<provider>_*.yml` and the env-specific `manifests/<env>.yaml` + `inventories/<env>/`. The four blockers above are the remaining hardcoded-Hetzner spots that need the same agnostic treatment.

---

## 10. Open questions for the operator

These should be answered before Phase A starts:

1. **Role ID intent (S2):** is `85e58ff2-…` shared on purpose (one role, two policies, two secret_ids) or should aliyun mint its own role?
2. **Unseal flow ownership:** is `bin/unseal-openbao.sh` going to be parametrized for env, or forked? Affects skill `dmf-openbao-unseal` updates.
3. **Two-pass Tofu acceptable?** Alternative is a separate `terraform/aliyun-frankfurt-dns/` workspace that runs after the cluster is up. Two-pass is simpler.
4. **Prefer fix-then-apply or apply-then-fix?** Implementing items 1-3 of Phase A is ~3h work; user may want to start ECS spend ASAP and patch in flight. Recommend fix-first — failed Tofu apply with partial cluster is more painful than the wait.

---

**End of review.** Last verified against repo state at commit umbrella `a0c697c`, dmf-env `5783c1f`, dmf-infra `00baca6` (all 2026-05-08).
