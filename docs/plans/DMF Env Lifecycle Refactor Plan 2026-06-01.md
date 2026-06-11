---
status: executed
date: 2026-06-01
executed: 2026-06-01
---
# DMF Env Lifecycle Refactor — self-contained per-env model + wizard-to-plan + teardown/remove (2026-06-01)

**Status:** approved (operator), implementation in flight. Orchestrated by Claude
(orchestrator pane); lifting by the worker pane; qwen-left reviewed the plan.

## Context

Standing up a fresh Hetzner env this session surfaced a cluster of *design*
problems, not just bugs:

- The wizard scatters per-env artifacts across **dmf-env** (committed
  `inventories/<env>/`, `manifests/<env>.yaml`, `terraform/<env>/`, appended
  `.sops.yaml` rules) **and** operator-local dirs (bundle, tfvars, TF state).
  Removing an env is manual git surgery + scattered `rm`s.
- A **shared, `prevent_destroy`'d** SSH key (`k3s-hetzner`) forces a `state rm`
  dance on teardown and a `maybe_import` dance on build; combined with the
  wizard's reuse-by-fingerprint logic it produced cross-env key-name
  contamination and a `prevent_destroy` apply deadlock.
- The wizard writes `ssh_pubkey_path` only to the Ansible inventory, **never to
  the Terraform tfvars**, so TF silently used a *different* default key →
  mismatch → replace → deadlock.
- The wizard renders artifacts but does **not** validate/plan, so errors
  (empty-array under bash 3.2, heredoc metachar expansion, key mismatch)
  surfaced step-by-step across separate commands instead of at wizard time.

**Operator intent (decided):** every env (cloud + sandbox) becomes **fully
self-contained and operator-local**, so dmf-env is a *generic* repo (scripts +
`terraform/modules/` + neutral `tasks/`/`templates/` only). Keys are **per-env**.
The wizard does **everything up to — not including — resource creation** (the
cost/blast-radius gate stays a deliberate operator action). Add a first-class
**teardown + remove env** flow. This completes the ADR-0031 / 2026-05-28
dual-lane consolidation — the sandbox lane already lives entirely under
`~/.dmfdeploy/envs/<env>/`; we extend that "new" layout to cloud via the existing
resolver `bin/lib/_resolve_env_paths.sh`.

## Decisions (settled)

- **Sequencing:** full refactor first, then stand up the Hetzner env on the new model.
- **Per-env SSH keys:** wizard **generates** an ed25519 keypair per env (default); **skippable** bring-your-own-key override remains.
- **Key storage:** **private key in the per-env sops bundle** (encrypted at rest; portable via age/sops; avoids the 0600-on-DrvFS fragility flagged for the WSL2/sandbox lane). Public key as a non-secret per-env file. Privkey materialized to an ephemeral 0600 temp at runtime (mirrors `run-playbook.sh`'s vars-file pattern).
- **Terraform root:** one **generic per-provider root** in dmf-env (`terraform/hetzner/`) reading operator-local manifest + tfvars + per-env state by variable. No per-env `.tf` committed.
- **Legacy envs** (`aliyun*`, `hetzner-arm`, `wobe-9n0c`): **all defunct** — delete in-repo artifacts wholesale and retire the resolver's legacy branch. No migration, no dual-path.

## Outcome

- `dmf-env` working tree stays **clean** through create→apply→bootstrap→teardown.
- `bin/init-wizard.sh <provider>` → validated, **planned**, ready-to-apply env under `~/.dmfdeploy/envs/<env>/`.
- First operator action after the wizard: `tf-apply <env> apply` → `bootstrap pre-seed` → seed-bao → post-seed → configure → verify.
- `bin/init-wizard.sh --remove <env>` (delegates to `bin/remove-env.sh`): tofu destroy + delete per-env Hetzner key + `rm -rf` env dir + clear state — one command.

## Cross-script audit + discipline (qwen-left review folded in)

**New layout only — no legacy dual-path.** All envs are torn down → no live
systems to protect mid-refactor. Scripts adopt the resolver's **new** layout
unconditionally; stale in-repo artifacts are deleted (Phase 8). Implement in a
coherent order (resolver fields + generic root before the wizard flips write
paths) and validate at the end with one fresh env.

**Scripts hardcoding per-env in-repo paths — all move to resolver/new-layout:**
`bin/tf-apply.sh` (`TF_DIR=terraform/<env>`, `inventory_var`, AWX keypair paths
~288-295), `bin/tf-destroy.sh` (own `inventory_var` ~69), `bin/tf-render-inventory.sh`
(~28), `bin/provision-nodes.sh` (~66), `bin/sandbox-workstation-hosts.sh` (~27-28),
`bin/recreate-sandbox-vm.sh` (~48). **Re-grep before implementing:**
`grep -rn 'inventories/\|terraform/\|manifests/' bin/`.

- **sops `--config`:** new-layout envs have a co-located per-env `.sops.yaml` → pass `--config "$DMF_ENV_SOPS_CONFIG"` (also resolves the cloud `bundle_sops_config_file` issue hardened earlier).
- **bash 3.2 / `set -u`:** new array expansions use `${arr[@]+"${arr[@]}"}`; no `set -x` (leaks secrets); secrets stay in stdin, never argv.
- **AWX control-node keypair** path (a hardcoded operator-specific `secure/` path + `$HOME/.config/dmf/...`) is operator-specific — make it resolver-derived / per-env.

## Phases

- **Phase 0** — ADR ("operator-local self-contained envs; dmf-env generic tooling+modules") + role change note. Doc edits deferred to Phase 8.
- **Phase 1** — Resolver: add `DMF_ENV_PROVIDER_TFVARS`, `DMF_ENV_TF_STATE_DIR`, `DMF_ENV_SSH_PUBKEY`, provider hint to `_dmf_env_paths_set_new`. Single source of per-env paths.
- **Phase 3** — New generic `terraform/hetzner/` root, **parameterized** (`manifest_path`, `hosts_ini_output_path`, `ssh_pubkey_path` as input vars — no hardcoded `${path.module}/../../…`; today's `hetzner-arm/main.tf:23` breaks under a shared root). Module `hcloud_ssh_key.k3s`: drop `prevent_destroy`, name `${env_id}-operator`, pubkey from var. `tf-apply.sh`: resolver + generic root + per-env state/tfvars, **remove `maybe_import`**, fix AWX path, materialize pubkey if absent. `tf-destroy.sh`: resolver, **drop the shared-key `state rm`** (keep the LB-detach network-ID fix + route cleanup landed this session).
- **Phase 2** — Wizard per-env keys: generate ed25519 (privkey→`bundle_set <env> ssh.operator_private_key`; pubkey→`<env-root>/ssh/operator.pub`, neutral comment, no operator identity); **skippable BYO override**; **drop reuse-by-fingerprint** (key always `${env_id}-operator`); **render `ssh_pubkey_path` into BOTH tfvars and inventory**.
- **Phase 4** — Wizard renders all artifacts under `~/.dmfdeploy/envs/<env>/` (cloud joins sandbox); stop writing in-repo `inventories/`/`manifests/`/`terraform/<env>/` and stop appending repo `.sops.yaml` (per-env `.sops.yaml` co-located).
- **Phase 5** — New `bin/validate-env.sh <env>` (doctor → `tofu init` → `tofu plan -out=<env-root>/plan.bin`); wizard calls it (cloud only); clean failure semantics.
- **Phase 6** — New `bin/remove-env.sh <env>` (tf-destroy → `hcloud ssh-key delete ${env}-operator` → clear state → `rm -rf` env dir; `--check`/`--yes`; idempotent). Wizard `--remove` delegates.
- **Phase 7** — `run-playbook.sh` + `bootstrap-secrets.sh` (`cmd_export_vars`): materialize `ssh.operator_private_key` to a 0600 temp, set `ansible_ssh_private_key_file`, cleanup on exit; full resolver adoption.
- **Phase 8** — Delete defunct in-repo env artifacts wholesale; resolver-adopt the remaining scripts; retire the resolver legacy branch; update umbrella `CLAUDE.md` (dmf-env role: "private inventory" → "generic env tooling"), `dmf-env/CLAUDE.md`, `STATUS.md`; land the ADR.

## Verification (end-to-end on a real Hetzner env — operator-gated apply)

1. `git -C dmf-env status` clean before. `bin/init-wizard.sh hetzner` (generate-key) → env dir has inventory+manifest+bundle+tfvars+`ssh/operator.pub`+`plan.bin`+co-located `.sops.yaml`; **dmf-env still clean**.
2. `tf-apply <env> apply` → resources created; key `${env}-operator` with the per-env pubkey; **no replace / no prevent_destroy error**.
3. `run-playbook <env> bootstrap-provision-pre-seed.yml` (privkey materialized, SSH works) → `DMF_BUNDLE_SET_DEBUG=1 … seed-bao` → post-seed → configure → `verify-bootstrap-convergence.yml`.
4. CCM/k3s checks (no datacenter panic, providerIDs, Traefik LB).
5. `bin/init-wizard.sh --remove <env>` → resources + key + env dir gone, dmf-env clean; re-run is a clean no-op.

## Notes
- Aliyun/AWS generic roots: mirror the hetzner pattern in a follow-on (hetzner first).
- Builds on this session's landed fixes (CCM v1.31.1 + k3s 1.33; unseal node-local API; `bundle_set` de-mask/hardening + `upgrade-in-place.sh`; the `sops_args` + heredoc wizard fixes). The tfvars `ssh_pubkey_path` gap and the `maybe_import`/`prevent_destroy` machinery are *resolved/removed* by this plan.
