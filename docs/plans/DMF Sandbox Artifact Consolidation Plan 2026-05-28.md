---
status: executed
date: 2026-05-28
---
# DMF Sandbox Artifact Consolidation Plan (2026-05-28)

**Status:** PLAN — not yet implemented. Operator approved scope + name 2026-05-28;
asked to plan-only for now.

**Scope:** consolidate all per-env artifacts the wizard creates for a **sandbox**
env into one user-home dir, and rename it from `~/.secure` to `~/.dmfdeploy`.
Cloud envs (`g2r6-foa9`, `wobe-9n0c`, future cloud) are **out of scope** — they
keep the current layout.

**Migration:** new sandbox envs created after this lands use the new layout.
`zy9q-1015` (in-flight at plan time, created under the old layout) is **left
alone** and rolls forward to teardown on its own.

---

## 1. Problem (current state, sandbox env)

A single sandbox env scatters artifacts across **five distinct locations** —
three in the dmf-env repo, two in operator-private storage:

1. `dmf-env/inventories/<env_id>/` — ansible inventory tree
2. `dmf-env/manifests/<env_id>.yaml` — Resource Profile
3. `dmf-env/.sops.yaml` — mutated to add a per-env `path_regex` rule
4. `$DMF_BOOTSTRAP_BUNDLE_DIR/<env_id>.sops.yaml` *(file)* + `$DMF_BOOTSTRAP_BUNDLE_DIR/<env_id>/` *(dir for tfvars; sandbox doesn't use the dir but the file-vs-dir split is in the codebase)*
5. `~/.secure/<env_id>/openbao-keys.json` — break-glass, written by the OpenBao role at pre-seed using the path the wizard wrote into `openbao_secrets.yml`

Plus an operator config file at `~/.config/dmf/env` (sets `DMF_BOOTSTRAP_BUNDLE_DIR`).

**Pain:**
- **Teardown is multi-step** (proven painful yesterday — five `rm`s + a tracked-file edit).
- **Operator confusion:** five places to remember; easy to half-clean.
- **Cross-platform friction:** `~/.config/` is a Linux XDG convention; macOS uses
  `~/Library/Application Support/`; Windows uses `%APPDATA%`. A single dot-dir
  under `$HOME` sidesteps this.
- **`~/.secure` is a name that describes the storage tier, not what's in it** —
  a user with multiple secure-storage projects has no way to know which subdir
  is DMF's.

## 2. Target layout (sandbox env, after this lands)

```
~/.dmfdeploy/
├── env                                  # operator config (was ~/.config/dmf/env)
└── envs/
    └── <env_id>/                        # the entire env — one rm -rf wipes it
        ├── .sops.yaml                   # per-env creation rule (sops walks up to discover)
        ├── bundle.sops.yaml             # encrypted secrets bundle
        ├── openbao-keys.json            # break-glass (was ~/.secure/<env>/openbao-keys.json)
        ├── manifest.yaml                # Resource Profile
        └── inventory/                   # ansible inventory tree
            ├── hosts.ini
            └── group_vars/all/
                ├── main.yml
                └── openbao_secrets.yml
```

**Teardown** for a sandbox env becomes: `rm -rf ~/.dmfdeploy/envs/<env_id>` —
that's the whole list. No `.sops.yaml` mutation in the repo, no `manifests/`
to half-clean, no separate `~/.secure/`.

### 2.1 What stays put

- **Age key** (`AGE_KEY_FILE`, default `~/.config/sops/age/keys.txt`) — operators
  often share it across projects per sops convention. Leave alone.
- **Cloud-env layout** — out of scope. `dmf-env/inventories/`, `dmf-env/manifests/`,
  `dmf-env/terraform/`, `dmf-env/.sops.yaml` rules, `$DMF_BOOTSTRAP_BUNDLE_DIR/`,
  `$TERRAFORM_STATE_ROOT/` all unchanged for cloud envs. A future "cloud
  consolidation" plan can apply the same idea to those if desired.
- **Sandbox VM substrate** (Lima on macOS / multipass on Linux / WSL2-Hyper-V on
  Windows / bare metal) — operator brings it, wizard just renders the node IP
  into `hosts.ini`. No wizard-side platform branching.

## 3. Cross-platform fit

The wizard is a bash script. Windows operators run it under **WSL2 or Git Bash**
(same assumption as today — `age`, `sops`, `yq`, `jq`, `ssh-keygen` are not
native Win32). Within that, `~/.dmfdeploy/` is cross-platform:

| Concern | Linux | macOS | Win (WSL2 / Git Bash) |
|---|---|---|---|
| `$HOME` resolution | native | native | WSL2 home (ext4) / Git Bash home (NTFS) |
| `chmod 0600` | enforced | enforced | enforced on ext4 (WSL2); recorded as DrvFS metadata on NTFS |
| `mkdir -p` | POSIX | POSIX | POSIX (Git Bash + WSL2 both ship coreutils) |
| Path separators | `/` | `/` | `/` in bash; never need backslashes |
| Hidden by default | `.` prefix | `.` prefix | `.` prefix (treated as normal dir on NTFS; harmless) |

Single `$HOME/.dmfdeploy/` avoids the per-OS XDG/Library/AppData mess by
not using any of those conventions — just one operator-private dot-dir.

## 4. Touchpoints (concrete edits when implementation runs)

1. **`dmf-env/bin/init-wizard.sh`**
   - Compute `env_root="${HOME}/.dmfdeploy/envs/${env_id}"` early in the sandbox
     render path.
   - Render bundle to `${env_root}/bundle.sops.yaml` (rename: drop the `<env_id>`
     prefix; the dir is already env-scoped).
   - Render per-env `.sops.yaml` to `${env_root}/.sops.yaml` with a single
     creation rule `path_regex: '.*/bundle\.sops\.yaml$'`. sops walks up to find
     it; no need to mutate the repo's `dmf-env/.sops.yaml`.
   - Render inventory tree to `${env_root}/inventory/...`.
   - Render manifest to `${env_root}/manifest.yaml`.
   - Render OpenBao paths (`openbao_key_path`, `eso_openbao_breakglass_file`) as
     `${env_root}/openbao-keys` and `${env_root}/openbao-keys.json` — under the
     new dir, not `~/.secure/`.
   - Default the operator config file to `~/.dmfdeploy/env`; the wizard reads
     either `~/.dmfdeploy/env` or `~/.config/dmf/env` (one-time fallback).
   - **Stop** mutating `dmf-env/.sops.yaml` for sandbox envs.
   - **Stop** writing into `dmf-env/inventories/` and `dmf-env/manifests/` for
     sandbox envs.
   - Print the "next steps" with the new paths (`-i ~/.dmfdeploy/envs/<env>/inventory`
     is what the wrapper resolves, so the printed `run-playbook.sh <env>` form
     doesn't change — the wrapper hides the resolution).
2. **`dmf-env/bin/run-playbook.sh`**
   - Env resolution: look for `${HOME}/.dmfdeploy/envs/<env_id>/inventory/` first;
     fall back to `${REPO_DIR}/inventories/<env_id>/` (for retained cloud envs).
   - Bundle resolution: `${HOME}/.dmfdeploy/envs/<env_id>/bundle.sops.yaml`
     first; fall back to `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env_id>.sops.yaml`.
3. **`dmf-env/bin/bootstrap-secrets.sh`** — same dual-path resolution as the
   wrapper for `init` / `doctor` / `seed-bao` / `export-vars`.
4. **`dmf-env/bin/unseal-openbao.sh` + `bin/get-admin-cred.sh` + the rest of
   the `bin/` scripts** — accept the new path via the same dual-path resolver
   shared in a small `_resolve_env_paths.sh` source-able include (already a
   pattern in `bin/` per yesterday's STATUS hygiene note).
5. **`dmf-env/CLAUDE.md` + `dmf-env/README.md`** — document the new sandbox
   layout. Cloud layout unchanged.
6. **No changes to `dmf-infra/` roles** — they consume what the inventory says.

## 5. Risks / edge cases

- **sops rule discovery:** sops walks from the file upward looking for `.sops.yaml`.
  A per-env `.sops.yaml` at `${env_root}/.sops.yaml` is found correctly when
  encrypting `${env_root}/bundle.sops.yaml`. **No conflict** with the repo's
  `dmf-env/.sops.yaml` because they're in different parent trees.
- **`zy9q-1015` rolls forward on the old layout** (operator's decision). The dual-
  path resolver in (2) + (3) + (4) keeps it working. When that env is torn down
  the old paths can be deprecated.
- **WSL2 path normalization** — `~/.dmfdeploy/` resolves to the WSL2 user's home
  (`/home/<user>/`), not the Windows-side `C:\Users\<user>\`. That's what we want;
  WSL2 ext4 honors POSIX modes. Operators who try to point bash at
  `/mnt/c/Users/...` would lose `chmod 0600` semantics — document the WSL2-home
  expectation in `CLAUDE.md`.
- **Operator with both old and new layouts at once** (during the rollout): dual-
  path resolution handles it; the wizard never accidentally writes to the old
  paths for new envs.
- **`~/.dmfdeploy/env` config file** — if it doesn't exist (fresh operator), the
  wizard defaults everything under `${HOME}/.dmfdeploy/`. The config file becomes
  optional rather than required.

## 6. Acceptance criteria (when impl runs)

1. `dmf-env/bin/init-wizard.sh` for a fresh sandbox env produces only files
   under `${HOME}/.dmfdeploy/envs/<env_id>/` — `git status` in dmf-env is clean
   (no inventory/manifest/.sops.yaml diff).
2. `bin/run-playbook.sh <new_env> <playbook>` resolves the inventory and bundle
   correctly from `~/.dmfdeploy/envs/<env>/`.
3. `bin/bootstrap-secrets.sh doctor <new_env>` passes (sops decrypts via the
   per-env `.sops.yaml`).
4. `bin/run-playbook.sh g2r6-foa9 …` still works (cloud env continues using
   the old paths via fallback).
5. `bin/run-playbook.sh zy9q-1015 …` still works (old sandbox env on old paths
   via fallback).
6. Teardown of a NEW sandbox env: `rm -rf ~/.dmfdeploy/envs/<env_id>` and
   nothing else — verified by re-running init-wizard.sh and checking git status
   in dmf-env stays clean.

## 7. Open items (future, not in this scope)

- **Cloud consolidation:** apply the same idea to cloud envs — single
  `~/.dmfdeploy/envs/<env_id>/` with `terraform/` and `terraform-state/` subdirs
  + tfvars in the same tree. Separate plan, after the sandbox lane proves out.
- **Symlink-from-repo for cloud-committed inventories:** if you want the
  inventory still committed (e.g. for the lab), an option is `dmf-env/inventories/<env>`
  being a symlink into `~/.dmfdeploy/envs/<env>/inventory`. Not relevant for
  sandbox (sandbox inventories aren't committed).
- **`bin/` script hygiene follow-up** (STATUS 2026-05-26 "TRACKED FOLLOW-UP"):
  several `bin/` scripts hardcode `/Volumes/<operator>/secure/...` — this
  consolidation would naturally retire those by routing everything through the
  new resolver.
- **A `dmf-env env teardown <env_id>` subcommand** that does the `rm -rf` and
  reports — makes the consolidation feel like a feature, not a discipline.

## 8. Related

- `[[reference_sandbox_standalone_playbook_profile_gap]]`
- `[[project_dmf_sandbox_local_vm]]`
- `[[feedback_plans_as_project_docs]]` (this plan lives where qwen + future agents can find it)
- STATUS 2026-05-27 §A "Sandbox test envs PURGED" — the teardown pain this plan addresses
- STATUS 2026-05-28 §🧹 "Sandbox env 9y6o-zn0t torn down" — the proof-of-pain from
  the most recent teardown (5 separate `rm`s + tracked-file edit)
