---
status: executed
date: 2026-06-03
executed: 2026-06-03
---
# DMF dmf-init Live-Sandbox Fix Batch — Work Order (2026-06-03)

**Source of truth:** `docs/handoffs/DMF dmf-init Live-Sandbox Exercise Findings 2026-06-03.md`
(findings #2/#3/#5/#7/#10). This doc is the *work order* derived from those findings:
what to change, where, the existing pattern to mirror, the tests to add, and the
per-item report protocol.

**Orchestration:** Claude (`claude-bottom`, `%2`) orchestrates + verifies; **codex**
(`%1`) does the lifting; **qwen-left** (`%0`) reviews each item before it's accepted.
Workers reply via agent-bridge (`~/.claude/skills/agent-bridge/bin/agent-bridge`) —
see §Reply protocol.

**Repos / branches (verify HEAD before committing — shared checkouts):**
- `dmf-init/` @ `main` (HEAD `f5616c2`).
- `dmf-env/` @ `feat/wizard-non-interactive` (HEAD `437b8af`, ahead 1, unpushed).

Out of scope here: **#9** (catalog AWX JT 400) and **#11** (MXL Console) are platform/
data, not code fixes — a clean main-only live re-run drops the `mxl-videotestsrc`
catalog entry; tracked in the findings doc, not actioned in this batch.

---

## Item A — #7: repo-fetch missing `dmf-cms` and `dmf-media` (SMALL, do first)

**File:** `dmf-init/src/dmf_init/repos.py`
- `REPO_NAMES = ("dmf-env", "dmf-infra", "dmf-runbooks")` → add `"dmf-cms"`, `"dmf-media"`.
- `DEFAULT_REFS` → add `"dmf-cms": "main"`, `"dmf-media": "main"`.

**Why both:** post-seed `630-zot-seed-platform.yml` reads `../../../dmf-cms/VERSION`
to pick the image tag; forgejo-bootstrap pushes `dmf-media/catalog/*.yaml` (the catalog
SoT feeding the Console). With them unfetched the operator hand-clones them.

**Tests:** extend the existing repos test (find it: `dmf-init/tests/ -k repo`) to assert
all five names are fetched and each has a default ref. Confirm provenance recording
covers the two new repos (whatever `repo_fetch` writes to render/provenance metadata).

**Acceptance:** `uv run pytest tests/ -k repo` green; `REPO_NAMES` has 5 entries; every
name has a `DEFAULT_REFS` entry (a fetch with no override must not KeyError).

---

## Item B — #5: `unseal-openbao.sh` (and seed-bao audit) ignore the env SSH key (SMALL)

**File:** `dmf-env/bin/unseal-openbao.sh`. The three remote calls run **bare** `ssh`
with no `-i`: `remote_bao_status_json` (~L174), `resolve_openbao_pod_ip` (~L188),
`feed_share_via_stdin` (~L212), plus the curl-presence check (~L373). In the stateless
container there is no ssh-agent, so they fail with "could not resolve OpenBao pod IP".

**Mirror the existing pattern** — sibling scripts already do exactly this:
- `dmf-env/bin/get-admin-cred.sh:118` and `bootstrap-operator-approle.sh:139`:
  `DERIVED_SSH_KEY="$(parse_yaml_scalar_anywhere "$GROUP_VARS_DIR" ansible_ssh_private_key_file …)"`
- `dmf-env/bin/bootstrap-secrets.sh:469` already builds `ssh_args+=(-i "$KEY")`.

**Change:** derive `SSH_KEY` from the inventory's `ansible_ssh_private_key_file`
(same group_vars parse the siblings use), allow an `OPENBAO_SSH_KEY` env override
(parallel to the existing `OPENBAO_SSH_TARGET`), and add `-i "$SSH_KEY"` to every ssh
invocation **only when `$SSH_KEY` is non-empty** (preserve agent-based behavior when no
key is resolved). Build an `ssh_opts` array once and reuse it; do not hand-edit four
call sites divergently.

**seed-bao audit:** `bootstrap-secrets.sh` remote_kubectl already passes `-i` (L469) —
confirm there's no *other* bare `ssh` in the seed-bao path that needs the same. Note in
your report whether any change was needed there.

**Tests:** dmf-env is bash. Add/extend a shellcheck-clean check; if there's a bats/
script test harness use it, else provide a minimal assertion that `-i` is emitted when
`OPENBAO_SSH_KEY` is set (e.g. a dry-run/echo path) and absent when unset. Run
`uvx --from shellcheck-py shellcheck dmf-env/bin/unseal-openbao.sh` (colima/local binary
may be down — uvx is the sanctioned path). `bash -n` is NOT sufficient.

**Acceptance:** shellcheck clean; `-i` present at all four ssh sites guarded by non-empty
key; `OPENBAO_SSH_KEY` override honored; agent-only path (no key) still works.

---

## Item C — #2 + #3 + #10: createnew SSH key must live in the env dir (BIG, do last)

One root cause, three symptoms (all in `dmf-init/src/dmf_init/createnew.py`):
- **#2** inventory bakes the **pre-move** temp key path (`runs/create-new-XXXX/ssh/…`);
  `shutil.move(work_dir → runs/<env_id>)` (L276 / L371) strands it → "Identity file not
  accessible."
- **#3** only the **private** key is written; bootstrap `219-host-verify` does
  `stat <key>.pub` → fails. The `.pub` is never derived.
- **#10** the key ends under `runs/<env_id>/ssh/`, but `backup.py` only tars
  `envs/<env_id>/` (walks env_dir, L168–174). So the key is **not in the backup** → a
  Manage restore into a fresh container has no node key → actions can't authenticate.

**Current shape (trace before editing):**
- Two render paths: `run_render_create_new` (~L195) and `stream_render_create_new`
  (~L285). Both: write key → `work_dir/ssh/sandbox-node.key`; `_answers_file_contents`
  (L101) bakes `ssh_private_key_path` into the answers the wizard reads; move
  `work_dir → runs/<env_id>`; re-point `state.ssh_private_key_path` to
  `runs/<env_id>/ssh/sandbox-node.key`.
- Env dir is `data_root/"envs"/request.env_id` (referenced ~L407 in backup request).
- `backup.py` tars `envs/<env_id>/` + bundles `age.key` + `answers.yaml`.

**Required fix:**
1. Write the operator key into the **env dir**: `envs/<env_id>/ssh/sandbox-node.key`
   (mode 0600) and derive `envs/<env_id>/ssh/sandbox-node.key.pub` via
   `ssh-keygen -y -f <privkey>` (mode 0644). Do this for **both** render paths.
2. Make the rendered **inventory** reference a key path that survives (a) the
   `work_dir → runs/<env_id>` move and (b) a Manage **restore into a different
   `DMF_DATA_ROOT`**. Prefer the env-dir absolute path computed from `data_root` +
   `env_id` (stable, backed up). If the Manage restore relocates the env dir, the
   inventory's `ansible_ssh_private_key_file` must be rewritten to the restored env
   dir's absolute path during relocation — check `manage.py` / `manage_actions.py`
   restore/relocation code and wire the rewrite there if it isn't already path-agnostic.
3. Ensure `state.ssh_private_key_path` (and anything downstream, e.g. the backup request)
   points at the **env-dir** copy so the key is included in the tar.
4. Keep the existing tmpfs-0600 discipline; never log key contents (the render stream
   already redacts — preserve that).

**Tests (add to `dmf-init/tests/`):**
- `.pub` is generated and present alongside the private key.
- After the `work_dir → runs/<env_id>` move, the inventory's
  `ansible_ssh_private_key_file` resolves to an existing file.
- The key + `.pub` are present **inside the backup tar** (round-trip via `backup.py`).
- After a restore into a **different** `DMF_DATA_ROOT`, the key resolves and the
  inventory path is valid (mirror the existing Manage restore test).

**Acceptance:** `uv run pytest tests/` green (whole suite); all four new assertions pass;
no key material in logs.

---

## Reply protocol (workers → Claude `%2`)

agent-bridge auto-stamps Claude's reply address on each dispatch. On finishing an item,
reply via:
```
~/.claude/skills/agent-bridge/bin/agent-bridge send claude-bottom -- "<STATUS> Item <A|B|C>: <one-line> | commit <sha-or-none> | tests <result>"
```
`<STATUS>` ∈ `DONE` / `BLOCKED:<reason>` / `HALTED:<reason>`. Report after **each** item
so qwen can review incrementally. Do **not** push; commit on the listed branch only after
verifying `git branch --show-current` matches. Co-author trailer:
`Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## Order
A (#7) → B (#5) in parallel-ok (different repos) → C (#2/#3/#10) last. qwen reviews each;
Claude verifies (pytest / shellcheck / inventory-path resolution) before accepting.
</content>
</invoke>
