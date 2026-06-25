# DMF Layer-1 OpenTofu Implementation Handoff — 2026-04-26

> **Superseded 2026-04-27.** Phase A and Phase B steps 6-7 (init +
> import + first apply, with `tofu plan` showing "No changes") are
> complete. For the next-session pickup prompt covering the remaining
> step 8 cut-over and step 9 rehearsal, use
> `Projects/DMF Layer-1 OpenTofu Phase B Cut-over Handoff 2026-04-27.md`.
> This document is preserved for historical context only.

> **Read this first.** Self-contained handoff for a fresh Claude Code
> session with no prior chat memory. Scope: execute the locked plan in
> `Projects/DMF Layer-1 OpenTofu Bootstrap Plan 2026-04-26.md`. Nothing
> else.

> The plan replaces `dmf-env/bin/provision-nodes.sh` (a shell script)
> with a thin OpenTofu module for Hetzner Layer-1 only. **Ansible Layer
> 2 and Layer 3 stay untouched.** Conservative path; no GitOps; no
> cloud-init merge; no opinionated `kube-hetzner` module.

---

## 1. Scope and shape

The work splits into two phases by blast radius:

| Phase | Steps in plan §11 | What touches | Safe to batch? |
|---|---|---|---|
| **Phase A** — local skeleton + module | 1, 2, 3, 4, 5 | Files in `dmf-env/` only. Zero Hetzner contact. | Yes — single commit at the end |
| **Phase B** — cluster contact | 6, 7, 8, 9 | Real Hetzner API. State file. **Mutates infrastructure on first non-no-op apply.** | No — explicit operator confirmation before every `tofu apply` |

**Critical gate between A and B:** §11.6 `tofu import` must fully
populate state from the running cluster, then `tofu plan` must report
**"No changes"**. If plan shows changes after import, the module
description doesn't faithfully match reality — fix the module, do not
apply.

The locked plan is the source of truth for what to build. This handoff
adds operator-context that the plan deliberately does not duplicate.

## 2. Environment at a glance

- **Operator host:** Mac mini at `<lan-ip>`. Claude Code runs
  here. Never SSH into .117 — you are already on it. Memory:
  `feedback_claude_code_is_on_mac_mini.md`.
- **Cluster (target of Layer-1):** 3-node Hetzner ARM cax21 in `nbg1`.
  Bastion / SSH target: `k3s-admin@<control-node-public-ip>` (control-plane #1).
- **Public LB:** `<lb-public-ip>` (CCM-managed, name `dmf-traefik`).
- **DNS apex:** `dmf.example.com` via Cloudflare zone `<lan-host>`.
- **In-cluster OpenBao:** `http://openbao.openbao.svc:8200` — ESO inside
  the cluster reads from this for runtime secret resolution. DMF does not
  involve operator-side wg2-OpenBao; memory:
  `project_dmf_no_wg2_openbao.md`.
- **JuiceFS mount:** `<secure-store>/`. All breakglass +
  infrastructure-state artefacts live here, never `$HOME/secure`.
  Memory: `feedback_dmf_secure_path.md`.
- **State file home (this work):** `<secure-store>/terraform-states/hetzner-arm/terraform.tfstate`
  (peer directory to `openbao-breakglass/`, decision §16.1 of plan).

## 3. Repos and current heads

All repos use forgejo as `origin` (no GitHub mirror anymore — removed
2026-04-26).

| Repo | Path | Branch | HEAD | Notes |
|---|---|---|---|---|
| `dmf-infra` | `~/repos/dmf-infra` | `main` | `5595a46` | Layer 2/3/6 + verticals; do not touch this repo for Phase A |
| `dmf-env` | `~/repos/dmf-env` | `main` | `18c6172` | **All Phase A work lands here** |
| `dmf-central` | `~/repos/dmf-central` | `master` | `ddaee5f` | Untouched |
| `dmf-media` | `~/repos/dmf-media` | `master` | `ff64aa5` | Untouched |
| `dmf-cms` | `~/repos/dmf-cms` | `master` | `5883fa6` | Untouched |

All 5 repos are clean and in sync with `origin` as of plan-locking.

## 4. The locked plan (read in full before step 1)

Canonical reference, locked 2026-04-26:

`Projects/DMF Layer-1 OpenTofu Bootstrap Plan 2026-04-26.md`

Sections that matter most for execution:

- **§3** target architecture diagram
- **§5** directory layout to create
- **§6** state management (local backend, JuiceFS)
- **§8** resource list with manifest field mapping
- **§9** inventory rendering template
- **§10** how to wire `manifests/hetzner-arm.yaml` into tofu
- **§11** the 10 numbered execution steps
- **§13** risks + rollback
- **§16** locked decisions (state path, Cloudflare records IN, keep deprecated `provision-nodes.sh` for one cycle, no `kube-hetzner`)

## 5. Inputs the work consumes

The Resource Profile manifest is the source of truth for what the
Hetzner cluster *should* be:

- `~/repos/dmf-env/manifests/hetzner-arm.yaml` (committed `18c6172`)
- See also `~/repos/dmf-env/manifests/README.md` for schema docs

OpenTofu reads it via `yamldecode(file("../../manifests/hetzner-arm.yaml"))`.
No other inputs needed for the module; tokens come from OpenBao at
runtime via the wrapper script.

## 6. Tokens needed at apply time

Tokens come from local config files on the operator host — same shim
`bin/export-openbao-vars.sh` uses today for Ansible. DMF does **not**
involve operator-side wg2-OpenBao (memory:
`project_dmf_no_wg2_openbao.md`).

| TF_VAR_*               | Source file                                      |
| ---------------------- | ------------------------------------------------ |
| `hcloud_token`         | `~/.config/hcloud/cli.toml` (active context)     |
| `cloudflare_api_token` | `~/.config/cf/dns.txt` (whitespace-stripped)     |

`bin/tf-apply.sh` reads these and execs `tofu` with `TF_VAR_*` populated.
Verify presence quickly:

```bash
test -s ~/.config/hcloud/cli.toml && echo "hcloud OK"
test -s ~/.config/cf/dns.txt      && echo "cloudflare OK"
```

If either is missing, fix locally (e.g. `hcloud context create
dmf-infra`) before running tf-apply.sh — there is no fallback.

## 7. Phase A — local skeleton + module (safe)

Plan steps 1–5. Zero Hetzner contact. **Single commit at the end.**

### 7.1 Step 1 — directory skeleton

```bash
cd ~/repos/dmf-env
mkdir -p terraform/modules/hetzner-cluster/templates
mkdir -p terraform/hetzner-arm
```

Add to `.gitignore`:

```
terraform/*/terraform.tfstate
terraform/*/terraform.tfstate.backup
terraform/*/.terraform/
```

### 7.2 Step 2 — write the module

Files under `terraform/modules/hetzner-cluster/`:

- `versions.tf` — providers per plan §7
- `variables.tf` — accepts `var.spec` (object, the manifest spec)
- `main.tf` — resources per plan §8
- `outputs.tf` — exports node list + control node + LB target
- `templates/hosts.ini.tftpl` — per plan §9

### 7.3 Step 3 — write the env root

Files under `terraform/hetzner-arm/`:

- `versions.tf` — provider config + state backend (`local` backend, path on JuiceFS per §16.1)
- `main.tf` — `yamldecode` the manifest, instantiate the module, declare `local_file.hosts_ini`
- `outputs.tf` — re-export node info

### 7.4 Step 4 — wrapper scripts

Files under `bin/`:

- `tf-apply.sh` — OpenBao read → `TF_VAR_*` → `tofu apply` (mirror `bin/export-openbao-vars.sh` pattern)
- `tf-render-inventory.sh` — `tofu apply -target=local_file.hosts_ini`

Both should be `chmod +x`. Comment headers explaining usage. Echo
"==> Logging" line like `bin/run-playbook.sh` does, for consistency.

### 7.5 Step 5 — OpenBao secret entries

**No new entries needed.** The two tokens already exist (§6 above).
Confirm presence before moving on; do not write new fields.

### 7.6 Phase A commit

After steps 1–5:

```bash
cd ~/repos/dmf-env
git status --short  # expect: new files in terraform/ and bin/, modified .gitignore
git add terraform/ bin/tf-apply.sh bin/tf-render-inventory.sh .gitignore
git commit -m "Add OpenTofu Layer-1 skeleton for hetzner-arm

Conservative path per DMF Layer-1 OpenTofu Bootstrap Plan 2026-04-26.
Zero contact with the running cluster: this commit only adds the
module + env root + wrapper scripts. No tofu apply yet.

Next: import existing Hetzner resources into state, verify tofu plan
shows 'No changes' before any apply runs (plan §11.6).
"
git push origin main
```

**STOP HERE.** Surface to the operator: Phase A landed; ready to begin
Phase B with explicit confirmation per step.

## 8. Phase A → B transition (the gate)

Before touching Hetzner: re-read the locked plan §11.6, §13, and §16.

Confirm with the operator:
- Hetzner state has not changed since plan-lock (no manual server
  changes, no cluster rebuild)
- The state file directory exists on JuiceFS (create it if missing,
  with permissions inherited from peer directories)
- Local token shims present (§6 above)
- No long-running deploy in flight

Only then proceed to Phase B.

## 9. Phase B — cluster contact (per-step confirmation required)

### 9.1 Step 6 — initialise + import

```bash
cd ~/repos/dmf-env/terraform/hetzner-arm
tofu init   # downloads providers; writes .terraform.lock.hcl (commit this!)
```

Then **import existing resources**, one at a time. Get each Hetzner
resource ID via `hcloud` CLI first, then import. Suggested order:

```bash
# SSH key
SSH_KEY_ID=$(hcloud ssh-key list -o noheader -o columns=id,name | awk '$2=="<operator>-k3s-hetzner"{print $1}')
tofu import 'module.cluster.hcloud_ssh_key.k3s' "$SSH_KEY_ID"

# Network
NET_ID=$(hcloud network list -o noheader -o columns=id,name | awk '$2=="k3s-private"{print $1}')
tofu import 'module.cluster.hcloud_network.k3s_private' "$NET_ID"

# Subnet — composite ID per provider docs: <network_id>-<ip_range>
tofu import 'module.cluster.hcloud_network_subnet.k3s_private' "${NET_ID}-10.0.0.0/28"

# Firewall
FW_ID=$(hcloud firewall list -o noheader -o columns=id,name | awk '$2=="k3s-firewall"{print $1}')
tofu import 'module.cluster.hcloud_firewall.k3s' "$FW_ID"

# Servers
for n in 1 2 3; do
  ID=$(hcloud server list -o noheader -o columns=id,name | awk -v n="k3s-node-0$n" '$2==n{print $1}')
  tofu import "module.cluster.hcloud_server.node[\"k3s-node-0$n\"]" "$ID"
done

# Server-network attachments — composite ID: <server_id>-<network_id>
for n in 1 2 3; do
  SID=$(hcloud server list -o noheader -o columns=id,name | awk -v n="k3s-node-0$n" '$2==n{print $1}')
  tofu import "module.cluster.hcloud_server_network.node[\"k3s-node-0$n\"]" "${SID}-${NET_ID}"
done

# Cloudflare records
ZONE_ID=$(curl -s -H "Authorization: Bearer $CF_TOKEN" \
  https://api.cloudflare.com/client/v4/zones?name=<lan-host> | jq -r .result[0].id)
APEX_ID=$(curl -s -H "Authorization: Bearer $CF_TOKEN" \
  "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=dmf.example.com" \
  | jq -r .result[0].id)
tofu import 'module.cluster.cloudflare_record.cluster_apex' "$ZONE_ID/$APEX_ID"
# Same pattern for auth.dmf.example.com
```

After all imports:

```bash
tofu plan
```

**Expected: `No changes. Your infrastructure matches the configuration.`**

If plan shows ANY changes:
- Read the diff carefully. Each diff line is a place where the module
  doesn't faithfully describe Hetzner reality.
- Fix the module (variables.tf / main.tf), not the Hetzner resource.
- `tofu plan` again. Iterate until clean.
- Common causes: default values (e.g. `delete_protection`, `placement_group`,
  Cloudflare `proxied` flag, firewall rule order).

**Do not run `tofu apply` until plan is empty.** Surface the diff to
the operator if it doesn't go to zero after one round.

### 9.2 Step 7 — first apply (must be no-op)

```bash
tofu apply
# Expected: 'No changes. Your infrastructure matches the configuration.'
# Apply complete! Resources: 0 added, 0 changed, 0 destroyed.

# Then render the inventory file once
tofu apply -target=local_file.hosts_ini
diff <(cat ../../inventories/hetzner-arm/hosts.ini) <(cat ../../inventories/hetzner-arm/hosts.ini)
# Compare against the committed hosts.ini before tofu wrote it. Should be byte-equivalent
# (or differ only in trailing newline / whitespace; normalise the template if so).
```

If the rendered `hosts.ini` differs from the committed one, fix the
template. Don't commit the rendered version yet.

### 9.3 Step 8 — cut-over

After the no-op apply succeeds and inventory matches:

1. Add deprecation banner to `bin/provision-nodes.sh`:
   ```bash
   echo "DEPRECATED: use bin/tf-apply.sh; this script will be removed after"
   echo "the first successful tofu-driven destroy + recreate cycle."
   echo "See terraform/ and DMF Layer-1 OpenTofu Bootstrap Plan."
   exit 1
   ```
2. Update `DEPLOYMENT.md` Section 5 — replace "run provision-nodes.sh" with the new Layer-1 step.
3. Update `manifests/README.md` — note that the manifest now drives `tofu`.
4. Update `Projects/DMF EBU Mapping (2026-04-25).md` — Layer 1 row.
5. Delete `tasks/hetzner_firewall.yml` (replaced by `hcloud_firewall` resource).
6. Verify `tasks/hetzner_ccm.yml` doesn't reference firewall management; if it does, prune.
7. Commit all of the above as one "cut-over" commit. Push.

### 9.4 Step 9 — destroy + recreate rehearsal

This proves the loop is fully captured in tofu. Pick `k3s-node-03`
(least critical — last to join etcd quorum, no Tailscale IP pinning).

**Operator confirmation REQUIRED before this step.** This destroys
real Hetzner state.

```bash
cd ~/repos/dmf-env/terraform/hetzner-arm
tofu destroy -target='module.cluster.hcloud_server.node["k3s-node-03"]'
# Confirm at the prompt with 'yes' only after operator approval

# Then recreate
tofu apply
# Expect: 1 to add (the server), 1 to add (the server-network attachment)

# Verify the new node has the same IPs assigned
tofu output -json | jq '.nodes.value[] | select(.name=="k3s-node-03")'

# Re-render inventory (should show the new IPs if they changed)
tofu apply -target=local_file.hosts_ini

# Re-converge with Ansible
cd ~/repos/dmf-env
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/playbooks/200-baseline.yml --limit k3s-node-03
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/playbooks/210-harden.yml --limit k3s-node-03
bin/run-playbook.sh ../dmf-infra/k3s-lab-bootstrap/playbooks/300-k3s.yml --limit k3s-node-03

# Verify rejoin
ssh k3s-admin@<control-node-public-ip> "sudo kubectl get nodes"
# k3s-node-03 should appear Ready within ~2 minutes
```

If everything is green:
- Delete `bin/provision-nodes.sh` entirely (not just deprecated banner)
- Commit + push
- Update `Projects/DMF Open Questions 2026-04-20.md` §EBU-3 — close the codegen sub-item for Layer 1

## 10. Verification checklist

| Gate | Command | Expected |
|---|---|---|
| Phase A skeleton parses | `cd terraform/hetzner-arm && tofu init && tofu validate` | `Success! The configuration is valid.` |
| Manifest reads | `tofu console` then `> yamldecode(file("../../manifests/hetzner-arm.yaml"))` | Object dump |
| Phase B import is faithful | `tofu plan` after all imports | `No changes.` |
| First apply is no-op | `tofu apply` after import | `0 added, 0 changed, 0 destroyed` |
| Inventory render matches | `diff` rendered vs committed | empty |
| Single-node rehearsal | §9.4 sequence | `kubectl get nodes` shows all 3 Ready |
| Drift detection | manually delete firewall in Hetzner console, run `tofu plan` | shows firewall as needing recreation |

## 11. Risks and stop conditions

**Stop and surface to operator if:**

- `tofu plan` after import shows changes that aren't obvious provider
  defaults (e.g. shows server type changing, IP changing, network
  range changing). Do not iterate blindly — these indicate a real
  mismatch worth understanding.
- Any resource fails to import (wrong ID format, missing field). Do
  not fall back to creating a new resource — that destroys the
  running one.
- The state file path on JuiceFS doesn't exist or isn't writable.
- OpenBao read fails. Tokens are required for the `tofu apply` to
  work, but should not block `tofu init` or `tofu validate` —
  validate without tokens first.
- The single-node rehearsal in §9.4 leaves the cluster degraded (etcd
  quorum lost, Longhorn replica unrecoverable). At that point: stop,
  manually recover, do not retry.

**Rollback while `provision-nodes.sh` still exists:** ignore the tofu
state, run the old script. The state file becomes orphaned but is
re-importable from existing Hetzner resources via §11.6 of the plan.

## 12. Memory references

Read these at session start for context:

- `MEMORY.md` — the index. Open it first.
- `project_dmf_ebu_realignment.md` — full EBU canon + commit hashes for the 2026-04-25–26 work
- `feedback_dmf_doc_strategy.md` — doc strategy (rewrite canonicals, header-note logs)
- `feedback_dmf_secure_path.md` — JuiceFS path discipline
- `feedback_dmf_hetzner_ingress_metallb.md` — current ingress (CCM, not MetalLB)
- `feedback_claude_code_is_on_mac_mini.md` — operator host topology
- `project_dmf_no_wg2_openbao.md` — DMF does not involve wg2-OpenBao; tokens come from local config shim
- `feedback_homelab_patience.md` — concurrent-task safety
- `feedback_<operator>_career_push.md` — Forgejo SSH push pattern (general)

## 13. Known gotchas (likely to hit)

- **`hcloud_server` `placement_group` defaulting** — provider may set
  `placement_group = null` even if the server has none assigned;
  `tofu plan` may show this as a no-op. Filter it out via `lifecycle
  { ignore_changes = [placement_group] }` if it's noise.
- **Cloudflare record `proxied` field** — defaults vary between provider
  versions. Read existing record state before declaring; `proxied = false`
  for A records pointing at infrastructure (not behind Cloudflare proxy).
- **`hcloud_firewall` rule order matters** — the provider treats rules as
  a set, but display order in the UI can mislead. Pin via
  `apply_to.label_selector` or `apply_to.server` exhaustively.
- **State file lock** — `local` backend does not lock. Single-operator
  homelab is fine, but never run two `tofu apply` against the same env in
  parallel.
- **`tofu destroy` without `-target`** would tear down the entire cluster.
  Always use `-target` for the rehearsal.
- **Provider version drift** — `.terraform.lock.hcl` MUST be committed
  with the Phase-A commit. Without it, `tofu init` may pull a newer
  provider that interprets the config differently.

## 14. After cut-over

When step 9.4 succeeds and `provision-nodes.sh` is deleted:

1. Update `Projects/DMF Open Questions 2026-04-20.md`:
   - §EBU-3 — note Layer-1 codegen done (manifest → tofu); inventory render still hand-tied to a single env (codegen for `inventories/<env>/group_vars/` is a separate item)
2. Update `Projects/DMF EBU Mapping (2026-04-25).md` — Layer 1 row reflects tofu
3. Update memory `project_dmf_ebu_realignment.md` — add the OpenTofu commits to the commit list
4. Consider opening a follow-up handoff for the medium-aggressive path
   (cloud-init merge of Layer 2 baseline into the tofu provision step).
   That's a separate decision, not part of this work.
5. `manifests/README.md` — note that the manifest now drives both
   inventory rendering AND tofu, and that drift detection lives in tofu.

## 15. If this handoff is stale

Check the locked plan file's mtime and section §16 ("Decisions locked
2026-04-26"). If a different plan version exists in
`<note-store>/Projects/`, follow the newer one and produce a fresh handoff
that supersedes this one.

If `provision-nodes.sh` is already deleted from `dmf-env`, this
handoff is obsolete — the cut-over already happened.
