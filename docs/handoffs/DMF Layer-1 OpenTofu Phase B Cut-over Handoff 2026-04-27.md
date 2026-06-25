# DMF Layer-1 OpenTofu — Phase B Cut-over Handoff (2026-04-27)

> **Read this first.** Self-contained handoff for a fresh Claude Code
> session with no prior chat memory. Scope: finish steps 8 and 9 of the
> locked plan in
> `Projects/DMF Layer-1 OpenTofu Bootstrap Plan 2026-04-26.md`. Phase A
> skeleton + Phase B steps 6-7 (init + import + first apply) are already
> complete and verified — `tofu plan` reports "No changes." Do **not**
> re-run those steps.
>
> Supersedes: `Projects/DMF Layer-1 OpenTofu Implementation Handoff 2026-04-26.md`.

---

## 1. Status snapshot

| Phase | Step | Status | Where |
|---|---|---|---|
| A | 1-5 — local skeleton + module + wrappers | ✅ done | dmf-env commit `b687363` |
| A | wg2-OpenBao doc cleanup | ✅ done | commit `bf1b186` |
| A | preflight corrections (subnet type, README, k3s-vip note) | ✅ done | commit `4841358` |
| B | 6 — init + import 12 resources | ✅ done | commit `34169e0` |
| B | 7 — first apply (1 add, 2 change, 0 destroy; DNS unchanged) | ✅ done | commit `34169e0` |
| B | 8 — cut-over (deprecate provision-nodes.sh, etc.) | ⏳ **this handoff** | — |
| B | 9 — destroy/recreate rehearsal on `k3s-node-03` | ⏳ **this handoff** | — |

`tofu plan` last verified clean: 2026-04-27, returned **"No changes. Your infrastructure matches the configuration."**

## 2. Environment at a glance

- **Operator host:** Mac mini at `<lan-ip>`. Claude Code runs
  here. Never SSH into .117 — you are already on it. Memory:
  `feedback_claude_code_is_on_mac_mini.md`.
- **Cluster:** 3-node Hetzner ARM cax21 in `nbg1`. Bastion / SSH
  target: `k3s-admin@<control-node-public-ip>` (control-plane #1).
- **Public LB:** `<lb-public-ip>` (CCM-managed, name `dmf-traefik`).
- **DNS apex:** `dmf.example.com` via Cloudflare zone `<lan-host>`.
- **In-cluster OpenBao:** `http://openbao.openbao.svc:8200` — ESO inside
  the cluster reads from this. DMF does **not** involve operator-side
  wg2-OpenBao; memory: `project_dmf_no_wg2_openbao.md`.
- **JuiceFS mount:** `<secure-store>/`. All breakglass +
  infrastructure-state artefacts live here, never `$HOME/secure`.
  Memory: `feedback_dmf_secure_path.md`.
- **State file:** `<secure-store>/terraform-states/hetzner-arm/terraform.tfstate`
  (12 KB after Phase B step 7; perms `drwx------`).
- **JuiceFS lock pragma:** flock(2) is unsupported, so every tofu
  write subcommand needs `-lock=false`. Memory:
  `project_tofu_juicefs_lock.md`. The wrapper `bin/tf-apply.sh` does
  **not yet** default this — pass it manually, or update the wrapper
  as a small follow-up.

## 3. What is in tofu state

Run `cd ~/repos/dmf-env/terraform/hetzner-arm && tofu state list` to
re-confirm. Expected (12 managed + 2 data):

```
module.cluster.data.cloudflare_zone.primary
module.cluster.data.hcloud_load_balancer.dmf_traefik
module.cluster.cloudflare_record.cluster_apex          # dmf.example.com → <lb-public-ip>
module.cluster.cloudflare_record.cluster_auth          # auth.dmf.example.com → <lb-public-ip>
module.cluster.hcloud_firewall.k3s                     # name=k3s-nodes; ICMP + SSH/22 + TCP/80 + TCP/443
module.cluster.hcloud_network.k3s_private              # 10.0.0.0/24
module.cluster.hcloud_network_subnet.k3s_private       # 10.0.0.0/28, type=server
module.cluster.hcloud_server.node["k3s-node-01"]       # <control-node-public-ip> / 10.0.0.2
module.cluster.hcloud_server.node["k3s-node-02"]       # <node-public-ip> / 10.0.0.3
module.cluster.hcloud_server.node["k3s-node-03"]       # <node-public-ip> / 10.0.0.4
module.cluster.hcloud_server_network.node["k3s-node-01"]
module.cluster.hcloud_server_network.node["k3s-node-02"]
module.cluster.hcloud_server_network.node["k3s-node-03"]
module.cluster.hcloud_ssh_key.k3s                      # name=k3s-hetzner
local_file.hosts_ini                                   # renders inventories/hetzner-arm/hosts.ini
```

Floating IP `k3s-vip` (<hetzner-floating-ip>, unassigned) is intentionally **not**
in tofu — see `terraform/README.md` "Resources NOT in tofu".

## 4. Repos and current heads

All repos use forgejo as `origin`. As of 2026-04-27:

| Repo | Path | Branch | HEAD |
|---|---|---|---|
| `dmf-infra` | `~/repos/dmf-infra` | `main` | `01df5f1` |
| `dmf-env` | `~/repos/dmf-env` | `main` | `34169e0` |
| `dmf-central` | `~/repos/dmf-central` | `master` | `ddaee5f` |
| `dmf-media` | `~/repos/dmf-media` | `master` | `ff64aa5` |
| `dmf-cms` | `~/repos/dmf-cms` | `feature/dmf-console-release-0-bootstrap` | `c194c6a` |

`dmf-env` HEAD is the Phase B no-op apply commit. **Always re-fetch
and re-check** before starting work — concurrent dmf_cms / awx work has
been landing in this repo (see §9).

## 5. Critical learnings — do not relitigate

These came out of the Phase B import → plan → apply iteration. They are
**already in the module on `main`**; don't try to "fix" them away:

1. **Module reality vs handoff §9.1's worked example:**
   - Firewall name is `k3s-nodes`, not `k3s-firewall`.
   - SSH key name is `k3s-hetzner`, not `<operator>-k3s-hetzner`.
   - Network ip_range is `/24`; subnet ip_range is `/28`; subnet
     `type = "server"` (legacy), **not** `"cloud"`.
2. **Firewall has 4 rules, not 2:** ICMP, SSH/22 (allow-listed),
   TCP/80, TCP/443. The two public TCP rules are "VIP traffic" — public
   ingress lane. Removing them blocks all external traffic. The module
   declares all four.
3. **Cloudflare `name` is relative, not FQDN.** State stores `"lab"`,
   not `"dmf.example.com"`. The module computes the relative form via
   `trimsuffix(spec.domain.cluster_domain, ".${zone_name}")`. Keeping
   FQDN would have forced destroy + recreate of the live A records.
4. **`hcloud_server` lifecycle ignores 8 attributes:** `user_data`,
   `placement_group_id`, `ssh_keys`, `public_net`,
   `allow_deprecated_images`, `ignore_remote_firewall_ids`, `keep_disk`,
   `shutdown_before_deletion`. The last 5 are client-side flags / blocks
   that show as "+" on first plan but reflect no real Hetzner state.
5. **`hcloud_server_network.node`'s `for_each` is the static
   `toset(local.node_names)`, not `hcloud_server.node`.** The latter is
   unknown during `tofu import` against an empty state and produces
   "Invalid for_each argument".
6. **Output `nodes` iterates `sort(keys(hcloud_server.node))`,** not
   `local.node_names`, so partial-state evaluation during import doesn't
   error on missing keys. Private IP comes from
   `hcloud_server_network.node[k].ip` (the deprecated `server.network`
   computed attribute is unreliable post-import).
7. **JuiceFS + flock(2):** unsupported. Pass `-lock=false` on every
   `tofu import|plan|apply|destroy|state mv`. Read-only subcommands
   (`state list`, `output`, `validate`) reject the flag and don't
   need it. Memory: `project_tofu_juicefs_lock.md`.

## 6. Tokens

Tokens come from local config files on the operator host — same shim
`bin/export-openbao-vars.sh` uses today for Ansible. DMF does **not**
involve operator-side wg2-OpenBao (memory:
`project_dmf_no_wg2_openbao.md`).

| `TF_VAR_*`             | Source file                                  |
| ---------------------- | -------------------------------------------- |
| `hcloud_token`         | `~/.config/hcloud/cli.toml` (active context) |
| `cloudflare_api_token` | `~/.config/cf/dns.txt` (whitespace-stripped) |

`bin/tf-apply.sh` reads these and execs `tofu`. Verify presence:

```bash
test -s ~/.config/hcloud/cli.toml && echo "hcloud OK"
test -s ~/.config/cf/dns.txt      && echo "cloudflare OK"
```

If invoking `tofu` directly (not via the wrapper), export them yourself:

```bash
export TF_VAR_hcloud_token="$(python3 -c 'import pathlib,re; t=pathlib.Path.home().joinpath(".config/hcloud/cli.toml").read_text(); a=re.search(r"active_context\s*=\s*\"([^\"]+)\"",t).group(1); print(re.search(rf"\[\[contexts\]\]\s+name\s*=\s*\"{re.escape(a)}\".*?token\s*=\s*\"([^\"]+)\"",t,re.DOTALL).group(1))')"
export TF_VAR_cloudflare_api_token="$(tr -d '[:space:]' < ~/.config/cf/dns.txt)"
```

## 7. Phase B Step 8 — cut-over

Operator confirmation **required before each file deletion or function
swap**. Order matters; dependencies first.

### 7.1 dmf-env — break the old path safely

1. **Banner `bin/provision-nodes.sh` as deprecated** (don't delete yet —
   keep for one cycle per plan §16.3 until §11.9 rehearsal succeeds):
   ```bash
   #!/usr/bin/env bash
   echo "DEPRECATED: use bin/tf-apply.sh; this script will be removed"
   echo "after the first successful tofu-driven destroy + recreate cycle."
   echo "See terraform/README.md and DMF Layer-1 OpenTofu Bootstrap Plan."
   exit 1
   ```
   Keep the existing body below the `exit 1` for reference if needed.

2. **Remove the `harden_cloud_firewall_tasks` reference** in
   `inventories/hetzner-arm/group_vars/all/main.yml` (line ~76) — this
   var points at a file we're about to delete:
   ```diff
   -# Hetzner Cloud Firewall — provider-specific task, lives in dmf-env/tasks/
   -harden_cloud_firewall_tasks: "{{ inventory_dir }}/../../tasks/hetzner_firewall.yml"
   ```

3. **Delete `tasks/hetzner_firewall.yml`** — superseded by the
   `hcloud_firewall` resource in tofu. Verify nothing else references
   it first:
   ```bash
   grep -rn 'hetzner_firewall' ~/repos/dmf-env ~/repos/dmf-infra \
     | grep -v '\.git/' | grep -v 'docs/'
   ```
   Should show only doc files (cleaned up below) after step 2 lands.

4. **Verify `tasks/hetzner_ccm.yml`** doesn't reference firewall
   management — already verified, but re-check after the cleanup.

### 7.2 dmf-env — docs

5. **`DEPLOYMENT.md`** Section 5 — replace "run `bin/provision-nodes.sh`"
   with the new Layer-1 step:
   ```bash
   cd ~/repos/dmf-env/terraform/hetzner-arm
   bin/tf-apply.sh apply -lock=false      # Layer 1: Hetzner + DNS
   bin/tf-render-inventory.sh             # writes inventories/hetzner-arm/hosts.ini
   bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/site.yml   # Layers 2+
   ```
   Other Section 5 references to `provision-nodes.sh` → tofu equivalent.

6. **`manifests/README.md`** — note that the manifest now drives both
   `inventories/<env>/` rendering AND `terraform/<env>/`, and that
   drift detection lives in tofu. Cross-link `terraform/README.md`.

7. **`docs/hetzner-provisioning.md`** — supersede the manual `hcloud`
   recipe with a pointer to `terraform/README.md`. Keep the
   "destruction recipe" section but rewrite to use `tofu destroy
   -target=...` instead of `hcloud server delete` etc.

8. **`README.md` line 50** — already cleaned of `wg2:8200` (commit
   `bf1b186`); double-check no other operator-side wg2 references slip
   in.

### 7.3 dmf-infra — playbook docs + teardown

9. **`k3s-lab-bootstrap/playbooks/lifecycle/finalise-teardown.yml:17`**
   currently calls `hcloud server delete`. Replace with a documentation
   block telling the operator to use `tofu destroy -target=...` from
   the `dmf-env/terraform/hetzner-arm/` directory. Don't try to
   shell out to tofu from Ansible — boundary clarity matters.

10. **`k3s-lab-bootstrap/docs/hardening.md`** lines 10, 106-109 —
    rewrite the firewall section. Layer-1 firewall now lives in tofu;
    Ansible only handles OS-level nftables.

11. **`k3s-lab-bootstrap/playbooks/210-harden.yml:11`** — comment
    referencing `hetzner_firewall.yml` is stale. Update or remove.

### 7.4 Operator note store — canonical maps

12. **`Projects/DMF EBU Mapping (2026-04-25).md`** Layer 1 row — note
    that Layer 1 provisioning is now tofu-driven. Add commit reference.

13. **`Projects/DMF Open Questions 2026-04-20.md` §EBU-3** — close the
    "codegen for Layer 1" sub-item (manifest → tofu). Note that
    inventory `group_vars/<env>/` codegen is still open (separate item).

14. **`memory/project_dmf_ebu_realignment.md`** — append the OpenTofu
    commits (`b687363`, `bf1b186`, `4841358`, `34169e0`) to the commit
    list.

### 7.5 Cut-over commit + push

Squash steps 7.1-7.3 into one commit per repo:

```bash
cd ~/repos/dmf-env
git add bin/provision-nodes.sh inventories/hetzner-arm/group_vars/all/main.yml \
        DEPLOYMENT.md manifests/README.md docs/hetzner-provisioning.md \
        README.md
git rm tasks/hetzner_firewall.yml templates/hcloud_firewall_rules.json.j2  # if no other refs
git commit -m "$(cat <<'EOF'
Cut-over: Layer-1 owned by OpenTofu, deprecate provision-nodes.sh

Per DMF Layer-1 OpenTofu Bootstrap Plan §11.8. Phase B steps 6-7
already verified the tofu module faithfully describes the running
cluster (tofu plan = "No changes" against commit 34169e0).

This commit:
- adds deprecation banner to bin/provision-nodes.sh (kept until §11.9
  rehearsal proves tofu-driven destroy + recreate works end-to-end)
- removes harden_cloud_firewall_tasks (the Ansible firewall task is
  superseded by hcloud_firewall in tofu)
- deletes tasks/hetzner_firewall.yml + templates/hcloud_firewall_rules.json.j2
- updates DEPLOYMENT.md, manifests/README.md, docs/hetzner-provisioning.md

Next: §11.9 destroy/recreate rehearsal on k3s-node-03.
EOF
)"
git push origin main
```

```bash
cd ~/repos/dmf-infra
# stage the 3 doc/playbook updates
git commit -m "Update Layer-1 references — tofu owns Hetzner provisioning"
git push origin main
```

## 8. Phase B Step 9 — destroy/recreate rehearsal

This proves the loop is fully captured in tofu. Pick `k3s-node-03`
(least critical — last to join etcd quorum, no Tailscale IP pinning).

**Operator confirmation REQUIRED before this step.** This destroys real
Hetzner state.

### 8.1 Preflight

- All 3 nodes Ready in kubectl: `ssh k3s-admin@<control-node-public-ip> "sudo kubectl get nodes"`
- No Longhorn unhealthy volumes: `ssh k3s-admin@<control-node-public-ip> "sudo kubectl -n longhorn-system get volumes -o wide | grep -v healthy"` should be empty
- Latest cut-over commit (§7.5 above) is on origin/main
- `bin/tf-apply.sh apply -lock=false` reports no drift

### 8.2 Destroy + recreate

```bash
cd ~/repos/dmf-env/terraform/hetzner-arm
bin/tf-apply.sh apply -lock=false -target='module.cluster.hcloud_server.node["k3s-node-03"]' -destroy
# Confirm at the prompt with 'yes' only after operator approval

# Recreate. The hcloud_server_network attachment will follow because of
# the for_each + indexed reference; tofu plans both in the same graph.
bin/tf-apply.sh apply -lock=false -target='module.cluster.hcloud_server.node["k3s-node-03"]' \
                                  -target='module.cluster.hcloud_server_network.node["k3s-node-03"]'

# Verify the new node has assigned IPs
tofu output -json | jq '.nodes.value[] | select(.name=="k3s-node-03")'

# Re-render inventory (public IP likely changed; private IP may differ)
bin/tf-render-inventory.sh
```

### 8.3 Re-converge with Ansible

```bash
cd ~/repos/dmf-env
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/playbooks/200-baseline.yml --limit k3s-node-03
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/playbooks/210-harden.yml --limit k3s-node-03
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/playbooks/300-k3s.yml --limit k3s-node-03
```

### 8.4 Verify rejoin

```bash
ssh k3s-admin@<control-node-public-ip> "sudo kubectl get nodes"
# k3s-node-03 should appear Ready within ~2 minutes of 300-k3s.yml finishing
```

If degraded (etcd quorum lost, Longhorn replica unrecoverable): **stop,
manually recover, do not retry.** Per plan §13.

### 8.5 If green, finalise

- Delete `bin/provision-nodes.sh` entirely (banner-only version from
  §7.1):
  ```bash
  cd ~/repos/dmf-env
  git rm bin/provision-nodes.sh
  git commit -m "Remove provision-nodes.sh — superseded by tofu

  §11.9 destroy/recreate rehearsal on k3s-node-03 verified end-to-end:
  tofu destroy + recreate + Ansible re-converge → kubectl shows node
  Ready. The shell script is no longer the rollback path."
  git push origin main
  ```
- Update `Projects/DMF Open Questions 2026-04-20.md` §EBU-3 — close the
  Layer-1 codegen sub-item.
- Add the rehearsal commit to memory `project_dmf_ebu_realignment.md`.
- Consider opening a follow-up handoff for the medium-aggressive path
  (cloud-init merge of Layer 2 baseline into the tofu provision step).

## 9. Operational notes / known gotchas

1. **Concurrent dmf_cms / awx work in flight.** As of 2026-04-27 the
   dmf-env working tree may have unstaged adds in
   `manifests/hetzner-arm.yaml` (adding `console: console.dmf.example.com`)
   and `inventories/hetzner-arm/group_vars/all/main.yml` (adding
   `dmf_cms_host`). These are **not** Layer-1 changes — leave them out
   of cut-over commits and let whoever's driving dmf_cms commit them
   separately. Always `git pull --rebase` and check `git status` before
   staging.

2. **`bin/tf-apply.sh` does not yet default `-lock=false`.** Pass it
   manually on every invocation, or update the wrapper as a small
   follow-up (set `-lock=false` for `import|plan|apply|destroy` and
   leave read-only subcommands untouched).

3. **Floating IP `k3s-vip`** (`<hetzner-floating-ip>`, unassigned) is
   intentionally out-of-tofu (plan §8). It's legacy from the pre-CCM
   MetalLB era. To retire it later: `hcloud floating-ip delete k3s-vip`
   after confirming nothing references the IP in any inventory or
   role default.

4. **`hcloud_server.node[*]` lifecycle ignores `ssh_keys`.** Rotating
   the SSH key requires a separate manual flow (delete old `hcloud_ssh_key`
   resource, recreate). Don't try to fix this by removing the
   ignore_changes — it'll force-replace every server.

5. **Plan §13 single-node-rehearsal warning.** If the rehearsal in §8
   above leaves the cluster degraded (etcd quorum lost, Longhorn
   replica unrecoverable), **stop, manually recover, do not retry**.

## 10. Memory references

Read these at session start:

- `MEMORY.md` — index. Open it first.
- `project_dmf_ebu_realignment.md` — full EBU canon + commit hashes
- `feedback_dmf_doc_strategy.md` — doc strategy (rewrite canonicals, header-note logs)
- `feedback_dmf_secure_path.md` — JuiceFS path discipline
- `feedback_dmf_hetzner_ingress_metallb.md` — current ingress (CCM, not MetalLB)
- `feedback_claude_code_is_on_mac_mini.md` — operator host topology
- `project_dmf_no_wg2_openbao.md` — DMF excludes wg2-OpenBao; tokens come from local config shim
- `project_tofu_juicefs_lock.md` — pass `-lock=false` to all tofu write subcommands on JuiceFS state
- `feedback_homelab_patience.md` — concurrent-task safety
- `feedback_<operator>_career_push.md` — Forgejo SSH push pattern (general)

## 11. If this handoff is stale

Indicators that something has moved past this doc:

- `bin/provision-nodes.sh` is already a one-liner banner → §7 step 1 done
- `tasks/hetzner_firewall.yml` no longer exists → §7 step 3 done
- `bin/provision-nodes.sh` doesn't exist at all → §8 finalise done; this handoff is obsolete
- `git -C ~/repos/dmf-env log --oneline -5` shows commits beyond
  `34169e0` that touch DEPLOYMENT.md or `tasks/` → cut-over partially
  underway; read those commits before continuing

If `bin/tf-apply.sh` already defaults `-lock=false`: the wrapper
follow-up has been done; ignore §9 item 2.

## 12. Quick verification commands

Before starting any work, sanity check:

```bash
# Tokens present
test -s ~/.config/hcloud/cli.toml && test -s ~/.config/cf/dns.txt && echo "tokens OK"

# Repos clean and synced
for r in dmf-infra dmf-env; do
  echo "$r: $(git -C ~/repos/$r status -sb | head -1)"
done

# tofu state still matches Hetzner reality (no destructive drift)
cd ~/repos/dmf-env/terraform/hetzner-arm
export TF_VAR_hcloud_token="$(python3 -c 'import pathlib,re; t=pathlib.Path.home().joinpath(".config/hcloud/cli.toml").read_text(); a=re.search(r"active_context\s*=\s*\"([^\"]+)\"",t).group(1); print(re.search(rf"\[\[contexts\]\]\s+name\s*=\s*\"{re.escape(a)}\".*?token\s*=\s*\"([^\"]+)\"",t,re.DOTALL).group(1))')"
export TF_VAR_cloudflare_api_token="$(tr -d '[:space:]' < ~/.config/cf/dns.txt)"
tofu plan -lock=false -no-color | tail -8

# Cluster healthy
ssh k3s-admin@<control-node-public-ip> "sudo kubectl get nodes -o wide"
```

If `tofu plan` is **not** "No changes" — surface to the operator before
proceeding. Something has drifted.
