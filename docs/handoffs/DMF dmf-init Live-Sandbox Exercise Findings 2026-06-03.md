# DMF dmf-init Live-Sandbox Exercise — Findings (2026-06-03)

**What:** the first **live** run of the dmf-init Phase 1b+1c flow (previously only
hermetic) against a real `dmf-sandbox` Lima VM (`<sandbox-node-ip>`, `*.dmf.test`,
user `<operator>`). Drove Create-new → full bootstrap → Manage via the FastAPI app run
locally (`uv run python -m dmf_init.main`, host toolchain), repos sourced from
local checkouts via `file://`, backups to two local rclone `alias` remotes.
**Supersedes the "NEXT" section of** `DMF dmf-init Phase 1c Complete + Live-Sandbox
Follow-Up Handoff 2026-06-02.md`.

**Headline:** dmf-init's orchestration is sound — it drove the VM from blank
Debian through a *fully installed platform* (k3s, cert-manager, OpenBao, ESO,
authentik, netbox, forgejo, AWX, dmf-cms, prometheus, loki, grafana) and 333
configure tasks, plus the full Manage restore/doctor/lock/drift cycle. Ten issues
surfaced; 3 fixed+committed, the rest diagnosed below.

---

## Validated LIVE (pass)
- Loopback bind + **one-shot launch token** (reuse → 403), session enforcement.
- Runtime **repo-fetch** (`file://`, provenance recorded).
- **Create-new render** against the live VM (SSH key redacted in the stream).
- **Checkpoint #1** dual-remote passphrase backup (validate-overwrite + upload).
- **pre-seed**: full infra (k3s 1.33, cert-manager, OpenBao, external-secrets) —
  309 tasks clean.
- **Checkpoint #2**: OpenBao-key capture at the exact expected path
  (`$DMF_DATA_ROOT/envs/<env>/openbao-keys.json`), redaction-set seeded before
  later steps, dual-remote re-backup. *(The single biggest §2 unknown — holds.)*
- **unseal** (after fix #6), **seed-bao** (sandbox lane; the cloud
  `seedbao_bundle_set_bug` did not bite).
- **post-seed**: full app stack (after fix #8).
- **configure**: 333 tasks (tail failure is platform, #9).
- **Manage (1c)**: restore (inner-sha **verified**, env relocated, render.json
  reconstructed) → **doctor** (12/12 checks) → **lock acquire** (drift-fresh;
  `MANAGE.lock` written with the **non-identifying `container` tag**, not the
  hostname — qwen P2 fix confirmed) → lock state/release → **drift DETECTION**
  (planted a newer backup → re-acquire correctly refused with 409). The corrected
  list-prefix→newest→compare-`inner_sha256` primitive works against a real remote.

## NOT live-tested (blocked)
- Bootstrap **pauses** (ca-cert / hosts-map / passkey) resume + **verify** +
  **checkpoint #3** — gated behind configure (#9, platform).
- Manage **action** (playbook re-run / upgrade / rotate / teardown) — gated behind
  #10 (SSH key absent from the backup).

---

## Findings

### ✅ #1 — dmf-env `_resolve_env_paths.sh` ignored `DMF_DATA_ROOT` — FIXED
`init-wizard.sh` honors `DMF_DATA_ROOT` (renders into the tmpfs) but the shared
resolver hard-coded `~/.dmfdeploy`, so every `bin/` script (run-playbook, unseal,
seed-bao) failed with "<env> is not a known env". **Fixed + committed:** dmf-env
`feat/wizard-non-interactive` `437b8af` (one line, mirrors the wizard's pattern).

### ✅ #6 — unseal step treated exit 2 (already-unsealed) as fatal — FIXED
The sandbox Tier-3 self-recovering unseal already unseals OpenBao during pre-seed,
so `unseal-openbao.sh` returns exit 2 ("already unsealed", documented
callers-may-treat-as-success). dmf-init's plain CommandStep treated it as fatal.
**Fixed + committed:** dmf-init `main` `f5616c2` (wrap so exit 2 → success).

### ✅ #8 — bootstrap didn't set `RUNBOOK_TIMEOUT` → 900s kill — FIXED
`run-playbook.sh` caps at 900s; post-seed (AWX readiness alone) exceeds it. The
wizard's own guidance uses `RUNBOOK_TIMEOUT=5400`. **Fixed + committed:** dmf-init
`main` `f5616c2` (set it in `command_env`). Post-seed then completed fully.

### ✅ #2 + #3 + #10 — createnew SSH-key handling — FIXED (2026-06-03)
**Fixed + committed:** dmf-init `main` `51a64e7`. The operator key is now
materialized into the **env dir** (`envs/<id>/ssh/sandbox-node.key`, 0600) with a
derived `.pub` (`ssh-keygen -y`, 0644) in both render paths; the inventory
`ansible_ssh_private_key_file` + answers `ssh_private_key_path` are rewritten to the
env-dir path (survives the `work_dir→runs/<id>` move), and Manage restore rewrites
both to the **relocated** env dir on restore-into-a-different-`DMF_DATA_ROOT`. Because
`backup.py` tars `envs/<id>/`, the key + `.pub` now ride the backup (proven by the new
restore round-trip test). Full suite 41 passed / 2 skipped; qwen-reviewed. Original
diagnosis (kept for the record):
Three facets of one root cause; were **fixed together**:
- **#2** the rendered inventory bakes the **pre-move temp** key path
  (`runs/create-new-XXXX/ssh/sandbox-node.key`); createnew `shutil.move`s the work
  dir to `runs/<env_id>/` afterwards → "Identity file not accessible."
- **#3** createnew writes only the private key; bootstrap `219-host-verify`
  requires `<key>.pub` (`stat … + '.pub'`) → fails. createnew never derives it.
- **#10** the SSH key lives under `runs/<id>/ssh/` (NOT `envs/<id>/`), referenced
  by an **absolute** original-container path. The backup only contains the env
  dir + age key + answers, so **the SSH key is not in the backup** → a Manage
  restore into a fresh container has no node SSH key → actions can't authenticate.

**Proposed fix:** write the operator key **into the env dir** (`envs/<id>/ssh/
sandbox-node.key` + derived `.pub` via `ssh-keygen -y`) so it is (a) backed up,
(b) survives the move, (c) restored portably; reference it from the inventory by a
path that survives restore (rewrite to the restored env's absolute path during
the Manage relocation, or use a deterministic `$DMF_DATA_ROOT`-relative resolution).
Add createnew tests for: `.pub` present, inventory path resolvable post-move,
key present in the backup, key resolvable after a restore into a *different* root.

### ✅ #5 — dmf-env `unseal-openbao.sh` ignored the env SSH key — FIXED (2026-06-03)
**Fixed + committed:** dmf-env `feat/wizard-non-interactive` `d078c67`. Derives
`SSH_KEY` from the inventory `ansible_ssh_private_key_file` (mirrors
`get-admin-cred.sh`), honors an `OPENBAO_SSH_KEY` override, and threads `-i` through a
single `ssh_opts` array at all four ssh sites (guarded by non-empty key, so the
agent-based path still works). seed-bao audited — its `remote_kubectl` already passes
`-i`, no change needed. Bonus: a latent jq bug (`.sealed // "?"` maps `false`→`"?"`)
fixed via a `has("sealed")` guard. shellcheck-clean + regression test; qwen-reviewed.
Original diagnosis (kept for the record):
`resolve_openbao_pod_ip`/`remote_bao_status_json`/`feed_share_via_stdin` run bare
`ssh "$SSH_TARGET" …` with **no `-i`**, relying on the operator's default
identity/agent. In the dmf-init/stateless-container flow the identity is the
rendered `sandbox-node.key`, which the script never uses → "could not resolve
OpenBao pod IP (cluster unreachable)". (The script header even notes this path is
"UNTESTED against a live cluster.") **Workaround used:** `ssh-add` the key +
launch the app with `SSH_AUTH_SOCK` — but a real stateless container has no agent,
so this MUST be fixed. **Proposed fix:** derive `ansible_ssh_private_key_file`
from the inventory and pass `-i` (or honor an `OPENBAO_SSH_KEY`/SSH-config
override). Check `bootstrap-secrets.sh seed-bao` for the same assumption.

### ✅ #7 — dmf-init repo-fetch was missing repos (`dmf-cms` AND `dmf-media`) — FIXED (2026-06-03)
**Fixed + committed:** dmf-init `main` `a1bfe4c`. `REPO_NAMES` + `DEFAULT_REFS` now
include `dmf-cms` and `dmf-media` (both ref `main`); provenance + tests cover all five.
qwen-reviewed. *(forgejo-bootstrap pushing dmf-media from the fetched copy is still to
be confirmed on the next live re-run.)* Original diagnosis (kept for the record):
`repos.py` `REPO_NAMES` only fetched dmf-env/dmf-infra/dmf-runbooks. Two gaps:
- **dmf-cms** — `post-seed` `630-zot-seed-platform.yml` reads `../../../dmf-cms/
  VERSION` to pick the image tag to mirror GHCR→Zot. **Workaround:** manually
  cloned dmf-cms into `repos/dmf-cms`.
- **dmf-media (the whole catalog repo)** — the **DMF Console facility/workflow/
  catalog page is fed by dmf-media**: `dmf-media/catalog/*.yaml` → pushed to the
  cluster Forgejo by forgejo-bootstrap → AWX SCM project `dmf-media`
  (awx-integration `defaults/main.yml:142`) → AWX job templates → NetBox SoT →
  dmf-cms Console. With dmf-media unfetched, forgejo-bootstrap has nothing to
  push → the catalog source is absent → **the Console catalog/workflow page is
  empty of the real catalog (incl. the merged MXL entries
  `mxl-videotestsrc.yaml`/`mxl-videotest-view.yaml`/`mxl-hello.yaml`).**

**Proposed fix (ADR-0036-aligned):** add **both** `dmf-cms` and `dmf-media` to
`REPO_NAMES`/`DEFAULT_REFS`, surface their refs in provenance, and confirm
forgejo-bootstrap pushes dmf-media from the fetched copy. *(Audit the full
post-seed/configure role set for any other sibling-repo assumption.)*

### ⛔ #11 — MXL catalog additions absent from the Console (compound) — UNFIXED
Why a from-scratch dmf-init bootstrap does **not** show the recently-merged MXL
additions on the Console facility/workflow/catalog page — three compounding
causes: (a) **#7** dmf-media (where the MXL catalog entries live) isn't fetched;
(b) **#9** configure fails creating the MXL catalog AWX JT
(`media-launch-mxl-videotestsrc` → 400, launcher playbook missing in the synced
project); (c) post-seed deploys **released dmf-cms `0.9.2`**, but the MXL Console
features ride a **dev-image override** (`dmf-infra … 915-mxl-cms-override:
temp-deploy dmf-cms MXL Flows dev image (SPIKE)`) that standard post-seed never
applies. Local canonical repos were verified **up to date with origin/main**
(not a staleness issue). To surface MXL in the Console: fetch+push dmf-media,
ensure the MXL launcher playbooks resolve in the AWX project, complete configure,
and deploy the MXL dmf-cms dev image. (MXL is still SPIKE — see
[[project_mxl_spike_state]].)

### ℹ️ #9 — configure AWX catalog JT 400 (PLATFORM, not dmf-init)
`configure` (333 tasks) failed only at the end: `media-launch-mxl-videotestsrc`
AWX job-template create → 400 ("playbook … doesn't exist"). The mxl launcher is a
**feature-branch artifact not present in dmf-runbooks@main**, but the catalog
references it. Not a dmf-init bug. To reach the pauses/verify/checkpoint-3 live,
either point dmf-runbooks at a ref that has the launcher, or drop the
mxl-videotestsrc catalog entry for a main-only bootstrap.

---

## Roadmap — #12: targeted env teardown completeness (sandbox node decommission)
dmf-init **does** have targeted env teardown (Phase 1c.3 manage `teardown` action
→ `remove-env.sh --yes`, re-backup-before-destroy + lock release; not yet
live-tested — gated by #10). **Gap:** `remove-env.sh` only removes **local env
state + cloud (TF/hcloud) resources** — for the **sandbox / bare-metal lane it
does NOT decommission the node**: k3s + the entire installed platform keep
running on the box after teardown. A truly "targeted env teardown" for those
lanes should also, over SSH to the node(s): run `k3s-uninstall.sh` (or
`k3s-killall.sh` + data wipe), remove `/etc/rancher`, `/var/lib/rancher`,
`/var/lib/longhorn`, the local-CA trust, and the openbao state — leaving the node
reusable. **Roadmap options:** (a) add a node-decommission step to
`remove-env.sh` for the sandbox/bare-metal lanes (SSH + k3s-uninstall + wipe),
gated behind an explicit `--purge-node`/confirm; or (b) for ephemeral VM
sandboxes, document that teardown = destroy/recreate the VM (the bare-metal case
still needs (a)). Surface it as a distinct dmf-init Manage action (`teardown`
vs `teardown --purge-node`) so the operator chooses state-only vs full
decommission. Pairs with the createnew SSH-key fix (#2/#3/#10) so the Manage
flow has the node key needed to SSH for the decommission.

## How to resume the live exercise
1. Recreate the VM: `dmf-env/bin/recreate-sandbox-vm.sh`; clear stale host key
   (`ssh-keygen -R <sandbox-node-ip>`). VM = blank Debian arm64, user `<operator>`, key
   `~/.lima/_config/user`, iface `lima0`, node_ip `<sandbox-node-ip>`.
2. Stage repo source: `/tmp/dmf-init-reposrc/<repo>.git` symlinks → local
   checkouts (incl. **dmf-cms** until #7 is fixed).
3. Launch: `cd dmf-init && SSH_AUTH_SOCK=$SSH_AUTH_SOCK DMF_DATA_ROOT=/tmp/<root>
   DMF_REPO_BASE_URL=file:///tmp/dmf-init-reposrc DMF_BIND_PORT=8090 …
   uv run python -m dmf_init.main` (long TTLs). `ssh-add` the lima key until #5 is
   fixed. Token on stdout → `GET /?token=…` for the session cookie.
4. Drive via curl: `/api/repos/fetch` → `/api/render` → `/api/backup` →
   `/api/bootstrap/start` + stream → resume pauses → `/api/manage/*`.
5. Fix order to unblock full completion: **#5** (unseal/seed ssh key) so no agent
   is needed; **#7** (fetch dmf-cms); **#9** (catalog ref) to reach pauses+verify+
   checkpoint #3; **#2/#3/#10** (createnew ssh key in env dir) to make Manage
   actions work on a true fresh-container restore.

## Commits from this exercise
- dmf-env `feat/wizard-non-interactive` `437b8af` — #1 resolver `DMF_DATA_ROOT`.
- dmf-init `main` `f5616c2` — #6 unseal exit-2 + #8 RUNBOOK_TIMEOUT.
- (umbrella docs: this findings handoff + STATUS update.)

### Fix batch 2026-06-03 (orchestrated: codex lift → Claude verify → qwen review)
Work order: `docs/plans/DMF dmf-init Live-Sandbox Fix Batch Plan 2026-06-03.md`.
All pushed to the LAN Forgejo (`<lan-ip>`).
- dmf-init `main` `a1bfe4c` — **#7** fetch dmf-cms + dmf-media.
- dmf-env `feat/wizard-non-interactive` `d078c67` — **#5** unseal honors env SSH key
  (`-i`/`OPENBAO_SSH_KEY`) + latent jq `.sealed` bug fix.
- dmf-init `main` `51a64e7` — **#2/#3/#10** SSH key in env dir + `.pub` + backup +
  restore-relocation rewrite.
Remaining UNFIXED: **#9** (catalog AWX JT 400) + **#11** (MXL Console) — platform/data,
need a main-only catalog ref + MXL dmf-cms dev image, not dmf-init code. Follow-up nit
DONE: duplicated `_rewrite_yaml_scalar` harmonized into a shared `dmf_init/yaml_utils.py`
(dmf-init `9e95694` + regression-fix `5b41950`); both paths quoted; the skip-gated
createnew e2e render path was run for real and passes.
</content>
