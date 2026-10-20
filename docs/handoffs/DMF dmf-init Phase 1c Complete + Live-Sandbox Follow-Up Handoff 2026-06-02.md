# DMF dmf-init Phase 1c Complete + Live-Sandbox Follow-Up Handoff (2026-06-02)

**For:** the next agent picking up dmf-init — the **live `dmf-sandbox` exercise**
of Phase 1b+1c (operator-gated), then **Phase 2 (cloud)**. Also continues the
**orchestrator + codex-lifter + qwen-reviewer** loop.
**Supersedes:** `DMF dmf-init Phase 1b Complete + Live-Sandbox Follow-Up Handoff 2026-06-02.md`
(this one records Phase 1c *done, hermetically* — the Phase-1 container is now
feature-complete for the sandbox lane).

---

## 0. Boot ritual first
Follow [`CLAUDE.md`](../../CLAUDE.md): `git fetch && git pull`,
`bin/generate-status.sh`, read [`STATUS.md`](../../STATUS.md), read **this** file,
skim [`docs/decisions/INDEX.md`](../decisions/INDEX.md) (esp. **ADR-0036**), and
`git status` any sub-repo before touching it. Ask before modifying a dirty sub-repo.

---

## 1. What is done (state as of 2026-06-02)

### Phase 1c (dmf-init) — Manage mode, built HERMETICALLY
**dmf-init `main` is at `b5fa77b`** (still **no git remote** — operator creates the
LAN Forgejo repo, then `git push -u`). 4 commits on top of 1b's `78313bd`:
- `56678df` 1c.1 — restore + doctor backend
- `ba36f8f` 1c.2 — remote lock + drift detection (double-reviewed)
- `e9a989c` 1c.3 — manage actions + re-backup + lock wiring
- `b5fa77b` 1c.4 — frontend Manage view

**Design + slicing (the contract):** `docs/archive/plans/DMF Init Phase 1c Manage Mode
Design 2026-06-02.md` — qwen-left reviewed **twice** (design CHANGES-NEEDED → all
folded; the 1c.2 lock/crypto **code** CHANGES-NEEDED → all folded). Read **§2
restore ordering, §3 lock + drift, §4 actions + teardown ordering**.

**Scope (operator, mirrors 1b):** 1c built **hermetically against the mock
`CommandExecutor` + two local rclone remotes**. Everything below the executor seam
is real; only the playbook/`bin/` runs are mock-substituted in tests. The live
cluster exercise is deferred (§2 below).

### dmf-init Phase 1c module map (`src/dmf_init/`)
- `manage.py` — `ManageRestoreRequest/Result`, `ManageSession` (holds env_id,
  manifest, dest_remotes, age key/answers paths, passphrase, **lock_holder/
  config/work_dir + locked + last_checkpoint + restored_artifact_name**),
  `run_manage_restore` (pull → `backup.restore()` → relocate **by copy BEFORE
  `cleanup()`** to `envs/<id>` + `runs/<id>` → reconstruct `render.json` from the
  manifest, node_ip/base_domain null), `build_doctor_run` (reuses the orchestrate
  engine; seeds redactions from openbao-keys.json). Best-effort tmpfs WARN.
- `manage_lock.py` — advisory lock on **dest_remotes[0]** `MANAGE.lock`:
  `acquire_lock` (read → 5-min-skew expiry → copyto → **3s settle** → read-back
  refuse-on-different-holder), `release_lock`/`revalidate_lock` (only-if-ours),
  `lock_state` (expired=None when malformed), `find_newest_remote_artifact` +
  `check_drift` (**list-prefix → newest-by-stamp → decrypt-manifest → compare
  inner_sha256**). Malformed-lock auto-recovery via **remote mtime** (rclone
  lsjson, tz-correct parse) only past ttl+tolerance.
- `manage_actions.py` — `build_action_argv` (rerun-playbook path-guarded /
  upgrade-in-place / rotate / teardown), `build_action_run` (mutating =
  `[command, rebackup]`; **teardown = `[rebackup, remove-env]`**),
  `make_manage_checkpoint_fn` (re-seed redactions → `backup()` both remotes),
  `run_action_then_release` (thread wrapper: release lock on terminal, success OR
  failure; teardown finalizes + wipes session).
- `main.py` — `/api/manage/restore|doctor`, `/api/manage/lock/{acquire,release,
  state}`, `/api/manage/action/start`, DELETE session. Lock acquire runs the
  **drift check then acquire** (DriftError/contended → 409). Action runs stream
  over the existing `/api/bootstrap/stream/{run_id}`.
- `frontend/src/ManageView.tsx` + `ui.tsx` — Create/Manage mode switch (Create-new
  preserved), 3-phase restore→restored→managing, lock banner, action buttons,
  type-to-confirm teardown, streamed `ManageConsole` (no pause handling). Shared
  UI primitives extracted to `ui.tsx` (used by both views).

### settings
`DMF_MANAGE_LOCK_TTL_SECONDS` (default 3600) added.

---

## 2. NEXT — the live `dmf-sandbox` exercise (1b + 1c become non-hermetic) — OPERATOR-GATED
This is the long-standing deferred item. **Needs the operator + a live env.** Bring
up Lima `dmf-sandbox` (was Stopped) + render/restore a real env, then:
- **1b path** (still unexercised live): confirm `openbao-keys.json` path, tier-3
  single-key unseal (mind `project_unseal_openbao_use_pty_bug`), real CA-cert PEM
  location, `get-passkey-enrollment-url.sh` wiring, real hosts-map subdomains,
  pause ordering, checkpoint #2/#3 re-backups sealing live, redaction-ordering
  invariant with REAL key material.
- **1c path** (new): restore from a real dual-remote backup → relocate → `doctor`
  against the live bundle; **lock + drift against a real rclone remote** (B2/the
  sandbox remote — confirm `rclone lsjson` ModTime parsing on that backend, and
  `lsf`/`copyto`/`deletefile` semantics); run a real action (e.g. re-run a
  playbook) → re-backup checkpoint → lock release; teardown ordering live.
- **Sandbox-lane gotchas** (memories): `sandbox_lane_assumptions`,
  `sandbox_standalone_playbook_profile_gap`, `sandbox_sops_config_class_bug`,
  `seedbao_bundle_set_bug`, `adr0032_catalog_teardown_skew`.

## 3. THEN — Phase 2 (cloud / Hetzner) + cleanups
Per the parent plan: add provider creds + B2 + **TF state** to the backup payload;
decide Shamir-collapse-into-passphrase (lab) vs stay-distributed (new ADR). The
TF-state-in-backup + the remote lock together are the single-operator-safety story.
**Deferred / tracked:** createnew `run_render`/`stream_render` ~95% duplicated →
DRY; **push dmf-init** once the operator creates the LAN Forgejo repo; a sidecar
`*.sha256` next to backups (would make drift detection a cheap `cat` vs
decrypt-manifest — decided against in 1c.2b to avoid touching `backup.py`).

---

## 4. The orchestration loop (operator's working model — unchanged)
- **claude-bottom = ORCHESTRATOR** (`%2`): slices work, writes self-contained
  specs to `/tmp`, reviews every diff + runs ALL gates (ruff · `uv run --extra dev
  pytest` · gitleaks · `npm run build` · arm64 docker for dep/Dockerfile-touching
  slices), applies small well-diagnosed fixes itself, surfaces only operator
  decisions.
- **codex = LIFTER** (`%1`): writes the multi-file code. **Now has `uv`/`npm`
  available** and may try to self-validate → it hits an **approval prompt**; just
  decline (it's not needed — the orchestrator runs gates). Its agent-bridge reply
  intermittently fails on the "claude-bottom %2 not live" check — read its pane
  directly; the work is on disk regardless.
- **qwen-left = REVIEWER** (`%0`): plan/design + adversarial crypto/secret reviews.
  **Its agent-bridge reply breaks on backticks/`$()` in the arg** → have it
  **write the review to a file** (`/tmp/qwen-*.md`) and reply with a plain
  one-liner; read the file.
- **Per-slice rhythm:** `/clear` codex → dispatch the on-disk spec → background
  idle-detector wait → review diff → run gates → fix/bounce → qwen review for
  risky slices → commit on operator go-ahead (dual Co-Authored-By: codex + Claude).
  `agent-bridge`: `~/.claude/skills/agent-bridge/bin/agent-bridge`; `verify <role>`
  before sends.
- **Gates note:** the arm64 docker build was **batched/skipped for pure-python,
  no-dep slices** (1c.1–1c.3 changed no `pyproject`/`Dockerfile`, so the image is
  structurally identical to the green 1b build; setuptools `packages.find`
  auto-picks-up new modules). Run it again whenever a slice touches deps or the
  Dockerfile.

## 5. Key references
- Repo: `dmf-init/` (`main` @ `b5fa77b`, no remote). Modules in §1.
- Design: `docs/archive/plans/DMF Init Phase 1c Manage Mode Design 2026-06-02.md`;
  parents: `…Phase 1 Implementation Plan…` + `…Bootstrap Container Plan…`. ADR-0036.
- Reviews on disk: `/tmp/qwen-1c-review.md` (design), `/tmp/qwen-1c2-codereview.md`
  (code).
- Memories: `project_dmf_init_repo`, `feedback_clear_agents_before_sections`,
  `feedback_codex_dispatch_fresh_context`, `reference_agent_bridge_hardened`,
  `feedback_qwen_left_preferred`, `project_dmf_sandbox_local_vm`,
  `project_sandbox_lane_assumptions`, `project_unseal_openbao_use_pty_bug`.
</content>
