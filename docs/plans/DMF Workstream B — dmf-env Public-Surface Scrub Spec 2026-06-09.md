---
status: executed
date: 2026-06-09
executed: 2026-06-09
---
# DMF Workstream B — dmf-env Public-Surface Scrub Spec (rev 3)

**Date:** 2026-06-09 · **Status:** Ready to execute (after codex re-review of rev3)
**Parent plan:** `docs/plans/DMF First Public Release Plan 2026-06-09.md` (Workstream B)
**Split:** **B1 = qwen-left** (mechanical + logic edits per exact spec). **B2 = claude** (doc rewrites).
**Cross-check:** codex (rev1+rev2 folded; marked **[codex]**).

> **Operator decisions (2026-06-09):** (1) public only if **completely scrubbed**
> of non-generic/env-specific code; (2) **no env files kept — all envs retired**
> (ADR-0035 operator-local); (3) **provider scope = Hetzner + sandbox only**;
> (4) **full clean — rip out the legacy dual-layout resolver fallback now.**
> No live env exists → validation = codex review + the 4 unit tests + claude review.

## Phase B1 — qwen

### 1. REMOVE entirely (`git rm -r`)
```
inventories/  manifests/  agentic/  k3s-infra-lab/  .qwen/  DEPLOYMENT.md
docs/handover.md  docs/hetzner-provisioning.md  docs/initial-data-gathering.md
docs/integration-sot-interim-report.md  docs/project-review-2026-04.md  docs/qwen-review-2026-04-17.md
.forgejo/workflows/ci.yml          # remove .forgejo/ if it becomes empty
bin/mxl-media-init-creds.sh  bin/mxl-media-join.sh         # retired aliyun-media spike
terraform/aliyun-media/  terraform/aws-sample/  terraform/modules/aliyun/  terraform/modules/aws/  tasks/aliyun/
```
Survivors: `terraform/{hetzner,modules/hetzner,README.md}`, `tasks/hetzner`,
`docs/answers-file-schema.md`, `bin/*` (minus mxl-media), `bin/lib/*`,
`templates/`, `tests/`, `README.md CLAUDE.md QWEN.md .gitignore .sops.yaml`.

### 2. FULL-CLEAN the legacy dual-layout resolver [codex] — new-layout only

`bin/lib/_resolve_env_paths.sh`:
- Delete `_dmf_env_paths_set_legacy()` (the whole function).
- `dmf_resolve_env_paths()`: delete the legacy branch (`if [ -d "${repo_dir}/inventories/${env_id}" ]…`) and the trailing legacy-placeholder fallback; when neither new-layout artifact exists, call `_dmf_env_paths_set_new "$env_id"` (placeholders) and `return 1`.
- `dmf_list_known_envs()`: delete the `${repo_dir}/inventories` loop — list only `${_DMF_DATA_ROOT}/envs/*`.
- `dmf_env_exists()`: delete the `${repo_dir}/inventories/${env_id}` check.
- Header comments: rewrite to describe ONLY the new layout. `DMF_ENV_LAYOUT` is now always `"new"`.
- The optional `[repo_dir]` arg may stay accepted-but-unused (avoids touching every caller); note it as vestigial. Do NOT delete callers' `REPO_DIR` setup.

`bin/bootstrap-secrets.sh` (full-clean [codex]):
- Delete the `if [ "$DMF_ENV_LAYOUT" = "legacy" ]; then … fi` branch at ~line 91 (keep the `"new"` path exactly).
- Replace the `cmd_init` body (~:601-905, the stale old-schema/Aliyun bundle creator — superseded by init-wizard.sh per its own :607-610 comment) with a **self-contained hard-error stub** (`bootstrap-secrets.sh` has NO `die` helper [codex] — use echo+return, not `die`):
  ```bash
  cmd_init() {
    echo "ERROR: bootstrap-secrets init is removed — create envs with bin/init-wizard.sh" >&2
    return 1
  }
  ```
  Remove the old body so no stale aliyun/manifests strings remain.
- Delete now-dead legacy helpers: `require_legacy_bundle_dir()` (~:45-73) and the legacy/repo-level fallback inside `bundle_sops_config_file()` (~:127-155).

`bin/b2-diag.sh` (old-layout, bypasses resolver [codex]):
- Refactor to source `bin/lib/_resolve_env_paths.sh` and read `${DMF_ENV_TFVARS_DIR}/object-storage.tfvars` (mirror `bin/b2-buckets.sh:72-81`), instead of `$DMF_BOOTSTRAP_BUNDLE_DIR/${ENV_NAME}/object-storage.tfvars`. (If a clean refactor is unclear, REMOVE b2-diag.sh from the public surface and note it.)

### 3. Scrub retired ENV-IDs + old-layout refs in ALL kept files — **grep is the contract [codex]**

The list of stale references is broader than any hand-enumeration. **Forcing
function:** scrub every kept file until the acceptance sweep (retired-env-IDs +
old repo-rooted `inventories/`/`manifests/` + identity/IP) reports **ONLY the 4
B2 docs** (README/CLAUDE/QWEN/terraform-README). Genericize to `<env-id>` /
`~/.dmfdeploy/envs/<env>/…` / `example.com`; keep comments meaningful; never key
behavior on a retired env-id.

**Known starting hotspots (NOT exhaustive — the grep is authoritative):**
`.gitignore:51-54` (inventories/manifests ignores — delete),
`bin/b2-buckets.sh:20,34`, `bin/b2-diag.sh:135`,
`bin/bootstrap-operator-approle.sh:117`, `bin/get-admin-cred.sh:14-19`,
`bin/get-passkey-enrollment-url.sh:19,124,132`, `bin/run-playbook.sh:8,18,58`,
`bin/tf-apply.sh:8`, `bin/tf-render-inventory.sh:2`, `bin/unseal-openbao.sh:32`,
`bin/bootstrap-secrets.sh:706` (drop the `hetzner-arm)` case key → generic default),
`bin/bootstrap-secrets.sh:1516`, `bin/init-wizard.sh:1522,1807`,
`bin/lib/_resolve_env_paths.sh` (legacy comments/body — handled in §2),
`terraform/modules/hetzner/cluster/templates/hosts.ini.tftpl:2`,
`terraform/modules/hetzner/cluster/variables.tf:2`.
Most are help-text / comments describing the old repo-rooted `inventories/<env>` →
rewrite to the new `~/.dmfdeploy/envs/<env>/…` model.

### 4. Token-scrub IPs/domains
- `terraform/modules/hetzner/cluster/main.tf` — comment `<lan-host>` → `example.com`.
- `tests/wizard-noninteractive-parity.sh` — BOTH occurrences of the operator `<lan-ip>` (the `interactive_answers` string ~L55 and `node_ip:` ~L76) → `203.0.113.10`.
- `docs/answers-file-schema.md` — example `node_ip: <lan-ip>` → `203.0.113.10`.

### 5. Wizard provider-trim + runtime guard [codex]
- `bin/init-wizard.sh:402` `sandbox|hetzner|aliyun|aws)` → `sandbox|hetzner)`.
- `bin/init-wizard.sh:525` `prompt_choice "Provider" hetzner aliyun aws sandbox` → `prompt_choice "Provider" hetzner sandbox`.
- `bin/init-wizard.sh:15` comment `hetzner/aliyun/aws.tfvars` → `hetzner.tfvars`.
- **Runtime guard [codex] — hetzner ONLY** (not sandbox; `terraform/sandbox` does not exist and tf-destroy is Hetzner-specific): in `bin/tf-apply.sh` and `bin/tf-destroy.sh`, after `DMF_PROVIDER` is resolved, fail early BEFORE touching `terraform/${DMF_PROVIDER}` (`tf-apply.sh:215`) or credential paths — `die` if provider != `hetzner`; for `sandbox` give a specific message (`"sandbox has no Terraform/cloud destroy path"`).
- `tests/wizard-noninteractive-parity.sh:55` — provider menu changed (sandbox is now option **2**, not 4): change the leading `4` in the canned `interactive_answers` to `2`. **Run the test.**

### 6. answers-file-schema.md provider surface [codex]
- Provider enum (~L26) → `sandbox`, `hetzner`.
- Remove the `aliyun.access_key` / `aliyun.secret_key` / `aws.access_key_id` / `aws.secret_access_key` / `aws.region` field docs (~L92-101) — unsupported in v0.1.

### 7. .gitignore [codex]
- Remove the `inventories/*/…` / `manifests/` ignore patterns (~L51-54) — those dirs no longer exist. Keep all secret/tfstate/key ignores.

### 8. Build the gate: `bin/dmf-env-public-surface-gate.sh` (UMBRELLA bin/)
Fail-closed. Arg = dmf-env tree (default `dmf-env`). Model on `bin/scrub-public-repos.sh`.
1. **Positive allowlist via path-depth regex (NOT shell globs) [codex]:** allow
   `^bin/[^/]+$` (but exclude `^bin/mxl-media-`), `^bin/lib/[^/]+$`,
   `^terraform/hetzner/`, `^terraform/modules/hetzner/`, `^terraform/README\.md$`,
   `^tasks/hetzner/`, `^templates/[^/]+$`, `^tests/[^/]+$`,
   `^docs/answers-file-schema\.md$`, `^(README|CLAUDE|QWEN)\.md$`, `^\.gitignore$`, `^\.sops\.yaml$`.
   Any tracked path not matched → FAIL. (Flat dirs use `[^/]+$` so future nested
   fixtures fail closed [codex].)
2. **Ban list:** `inventories/`, `manifests/`, `envs/`, `agentic/`, `.qwen/`,
   `*.tfstate*`, `*.tfvars`, `*.pem`, `*.key`, `secret_id*`, `openbao-*`, `*shamir*`, `.env`, `.env.*`, non-empty SOPS bundle.
3. **Retired-name content scan:** FAIL on `aliyun-media|hetzner-arm|g2r6-foa9|aliyun-123|aws-sample|mxl-media` or path strings `inventories/`/`manifests/`.
4. **Content scan, deterministic [codex]:** (a) run the three umbrella custom
   regexes (`dmf-operator-identity`, `dmf-internal-topology`, `dmf-dev-changeme`,
   copied verbatim from `<umbrella>/.gitleaks.toml`) via `rg` over the tree;
   (b) run default `gitleaks detect --no-git --source <tree>` **without** the
   umbrella config (its global allowlist skips sub-repos) for high-entropy/default rules. Any hit → FAIL file:line.
   **`gitleaks` (or `rg`) missing → HARD FAIL, never skip [codex].**
5. Exit 0 + `OK — dmf-env tree is public-safe` only if all pass.

### B1 acceptance — reply via agent-bridge with ACTUAL output
`~/.claude/skills/agent-bridge/bin/agent-bridge send claude -- "<reply>"`
- [ ] `git -C dmf-env status --short` (paste): removals `D`, edits `M`, new gate file.
- [ ] top level: `git -C dmf-env ls-files | awk -F/ '{print $1}' | sort -u` → ONLY `.gitignore .sops.yaml CLAUDE.md QWEN.md README.md bin docs tasks templates terraform tests`.
- [ ] `git -C dmf-env ls-files docs terraform tasks | sort` → docs=only answers-file-schema.md; terraform=hetzner/+modules/hetzner/+README.md; tasks=hetzner/.
- [ ] `bash -n` on every edited script (`_resolve_env_paths.sh` via `bash -n bin/lib/_resolve_env_paths.sh`, bootstrap-secrets.sh, init-wizard.sh, tf-apply.sh, tf-destroy.sh) → all clean.
- [ ] **Run ALL FOUR tracked tests [codex]** — `tests/wizard-noninteractive-parity.sh`,
      `tests/bundle-set-roundtrip.sh`, `tests/remove-env-data-root.sh`,
      `tests/unseal-openbao-ssh-key.sh`. Each must **PASS** (or explicitly SKIP only
      for a missing external dep, with the skip reason). Paste output. (The resolver
      full-clean can affect unseal/remove path resolution — this is the only safety
      net with no live env.)
- [ ] retired-name + identity sweep (**iterate §3 until this reports ONLY the 4 B2 docs** [codex]):
  `git -C dmf-env grep -nIE 'aliyun-media|hetzner-arm|g2r6-foa9|aliyun-123|aws-sample|mxl-media|inventories/|manifests/|<identity-and-topology-pattern-set: assemble from bin/scrub-public-repos.sh categories 2+3>|dev:changeme'`
  → must show ONLY README.md / CLAUDE.md / QWEN.md / terraform/README.md (the 4 B2 docs claude rewrites). Flag anything else.
- [ ] gate: `bin/dmf-env-public-surface-gate.sh dmf-env` → paste; the ONLY failures may be those 4 B2 docs.
- [ ] **Do NOT commit.** Flag anything ambiguous.

## Phase B2 — claude (after B1): rewrite the 4 docs
`README.md`, `terraform/README.md`, `CLAUDE.md`, `QWEN.md` → public generic-tool
posture (generic env tooling; sandbox+hetzner; operator-local envs `~/.dmfdeploy`
per ADR-0035; nothing per-env committed; OpenBao-injected secrets at runtime).

## Final acceptance (claude verifies, codex cross-checks, THEN claude commits)
Gate passes clean; identity+retired-name sweep fully empty; `bash -n` clean +
all offline tests pass; codex reads the final dmf-env tree + the gate tool and agrees.
