# DMF dmf-init Phase 1a + Agentic Orchestration Handoff (2026-06-02)

**For:** the next agent picking up dmf-init (Phase 1b) — and any agent running the
**orchestrator + codex-lifter + qwen-reviewer** loop this session established.
**Supersedes:** `DMF dmf-init Build — Orchestrator + Codex Delegation Handoff 2026-06-02.md`
(that handoff kicked off Phase 0; this one records Phase 0 + Phase 1a *done* and
codifies the working loop).

---

## 0. Boot ritual first
Follow [`CLAUDE.md`](../../CLAUDE.md): `git fetch && git pull`,
`bin/generate-status.sh`, read [`STATUS.md`](../../STATUS.md), read **this** file,
skim [`docs/decisions/INDEX.md`](../decisions/INDEX.md) (esp. **ADR-0036**), and
`git status` any sub-repo before touching it. Ask before modifying a dirty sub-repo.

---

## 1. What is done (state as of 2026-06-02)

### Phase 0 (dmf-env) — `init-wizard.sh --non-interactive`
- dmf-env commit **`2a75774`** on branch **`feat/wizard-non-interactive`**,
  **PUSHED to the LAN Forgejo** (origin), **NOT merged to main**.
- Adds a YAML answers-file (inputs-only) non-interactive mode to the wizard
  sharing one `validate_inputs`/`render_tail` with the interactive path. Schema:
  `dmf-env/docs/answers-file-schema.md`. Parity test:
  `dmf-env/tests/wizard-noninteractive-parity.sh`.
- **Coupling that matters:** dmf-init clones dmf-env at this branch until it
  merges to main (only it carries `--non-interactive`).

### Phase 1a (dmf-init) — Create-new: render + dual-remote passphrase backup
- **dmf-init `main` is at `c237775`** (feature branch FF-merged + deleted —
  brand-new dedicated repo, no value in a long-lived branch). **No git remote
  yet** → nothing pushed; operator creates the LAN Forgejo repo, then
  `git push -u`. 4 commits on top of the scaffold `e71871a`:
  - `a27892e` 1a.1 — thin container foundation
  - `99ebb39` 1a.2-i — runtime repo-fetch + session-enforcement
  - `b355094` 1a.2-ii-a — backup/restore crypto module (qwen-reviewed)
  - `c237775` 1a.2-ii-b — Create-new render → checkpoint #1 + frontend + E2E
- **Architecture = [ADR-0036](../decisions/0036-dmf-init-thin-control-container.md):**
  thin control-plane container. Bakes ONLY the tool layer + the FastAPI/React app.
  **Repos cloned at RUNTIME at an operator-selected ref** (sandbox source = the LAN
  Forgejo, creds at runtime). **App images pulled from GHCR+upstream at bootstrap**
  (mirrored to Zot by `630`), never baked. Air-gap (a portable image bundle) is
  deferred. Image is public-safe (nothing private baked).
- **Plan:** `docs/plans/DMF Init Phase 1 Implementation Plan 2026-06-02.md`
  (qwen-left-reviewed; 5 P1/9 P2/3 P3 folded). Parent spec: `docs/plans/DMF Init
  Bootstrap Container Plan 2026-06-02.md`.
- **What works (proven by a hermetic E2E, no cluster):** loopback FastAPI +
  single-use launch token→session → fetch repos at a ref into tmpfs → age-keygen →
  inputs-only answers-file → invoke the **fetched** `init-wizard --non-interactive`
  → render → **checkpoint #1**: pyrage age-scrypt (in-memory) tar of {env dir + age
  key + answers + MANIFEST} → two rclone remotes (overwrite-validated) → restore
  verifies `inner_sha256` + exposes the age key → `bootstrap-secrets.sh doctor`
  PASSES. Run the E2E with `DMF_TEST_DMF_ENV_REPO=/path/to/dmf-env` set.

### dmf-init module map (`src/dmf_init/`)
- `main.py` — FastAPI app: 127.0.0.1 bind; single-use launch token (TTL+one-shot →
  session cookie → token-free redirect; token scrubbed from access logs);
  `require_session` dep on `/api/repos/fetch`, `/api/render`, `/api/backup`;
  `/healthz` + SPA open.
- `settings.py` — env config (`DMF_DATA_ROOT` tmpfs, bind, TTLs, `DMF_REPO_BASE_URL`).
- `logging_utils.py` — JSON logging + **key-aware** secret redaction (filter AND
  formatter both redact secret-named fields) + access-log token scrub.
- `repos.py` — `fetch_runtime_repos`: clean-URL `git clone --depth 1 --branch <ref>`
  + `GIT_ASKPASS` (creds never in `.git/config`), provenance → `provenance/repos.json`.
- `backup.py` — `backup()`/`restore()`: deterministic PAX inner tar (stable
  `inner_sha256`), MANIFEST (inner hash, PUBLIC age recipient, provenance), pyrage
  passphrase wrap (**hard dep**, prebuilt aarch64 wheel; NO pty path), dual rclone
  remotes + overwrite-validate, `RestoreResult.cleanup()` (caller wipes
  plaintext-secret staging after doctor).
- `createnew.py` — orchestrates age-keygen → answers-file → fetched-wizard render →
  `backup()`. **NOTE the answers `ssh_private_key_path` must be the written key
  file PATH, not the PEM contents** (a bug we hit — the wizard `validate_absolute_path`s it).

---

## 2. The orchestration loop (this is the operator's working model — follow it)

**Roles:**
- **claude-bottom = ORCHESTRATOR** (`%2`, this pane). Reads context, decides
  approach + slicing, writes the dispatch spec, **reviews every diff, and RUNS ALL
  THE GATES**. Surfaces only operator-worthy decisions. Does NOT hand-write large
  multi-file implementations — but DOES apply small, well-diagnosed
  review-fixes/lint that the lifter can't verify.
- **codex = LIFTER** (`%1`, `codex-aarch64-a`, gpt-5.4-mini). Writes the
  code/files from the spec. **Its host is OFFLINE for python** — no PyPI, no
  `pyrage`, no `ruff`/`pytest` deps → **it cannot run the real gates.** It verifies
  only `bash -n`/`py_compile`/`npm run build`/`gitleaks`. **The orchestrator runs
  ruff/pytest/docker.** Expect codex to ship plausible code with bugs the gates
  catch (3 slices in a row had one). That's the model working, not failing.
- **qwen-left = REVIEWER** (`%0`, `node`). Plan reviews + adversarial crypto/code
  reviews. Strong, concrete, prioritized findings. Prefer qwen-left (qwen-right is
  often in parallel operator use).

**agent-bridge particulars** (binary: `~/.claude/skills/agent-bridge/bin/agent-bridge`):
- **Verify before send:** `agent-bridge verify codex` (expect `OK id=%1
  cmd=codex-aarch64-a`). Same for qwen-left (`OK id=%0`).
- **CLEAR before each new slice/section:** `agent-bridge send <role> --no-reply-id
  -- "/clear"` (sleep ~2). Operator directive 2026-06-02 — avoids context
  exhaustion on the mini model. Mid-slice bounces on the SAME slice do NOT need a
  clear. (See memory `feedback_clear_agents_before_sections`.)
- **Dispatch a SELF-CONTAINED spec written to disk** (`/tmp/dmf-<slice>-codex-spec.md`),
  then `agent-bridge send codex - <<'EOF' …point at the spec + plan + exact files…
  EOF`. The pane starts cold every time; restate everything. Auto-stamps the reply
  route back to you.
- **Collect the reply:** codex/qwen reply via the stamped route (lands in your
  pane) OR poll `agent-bridge read <role> --lines N`.
- **Wait for completion** with a background idle-detector (Bash `run_in_background`):
  loop `agent-bridge read <role>`; idle when the pane lacks `esc to interrupt`
  (codex) / `esc to cancel` (qwen) for ~3 consecutive 15s reads; exit → you're
  notified.
- **codex approval prompts:** codex pauses on its own `Would you like to run…`
  prompts (e.g. `rm -rf`, `docker build`). A bare Enter confirms the highlighted
  "Yes". To **cancel**, `tmux send-keys -t %1 Escape` (do NOT send Enter). To
  **approve**, `tmux send-keys -t %1 Enter`. Watch for codex trying to **escalate
  Docker perms** — stop it; the orchestrator runs the build.

**Per-slice rhythm that worked:**
1. Orchestrator: slice the work small (isolate crypto/risk), write spec to /tmp.
2. `/clear` codex → dispatch spec → idle-detector wait.
3. Review the diff yourself (read the files; don't trust the report).
4. Run gates: `uvx ruff@0.6.9 check .` · `uv run --python 3.12 --with-editable .
   --with "pytest<9" --with "httpx<1" --with pyrage pytest -q` · `gitleaks detect
   --source . --no-git` · `docker build --platform linux/arm64 -t dmf-init:test .`
   (colima is up; `rm -f uv.lock` after uv runs — it's gitignored).
5. Bounce diagnosed bugs to codex (same slice, no clear) OR apply small fixes
   yourself + re-verify.
6. For crypto/risky slices: **qwen adversarial review before commit** (clear
   qwen-left, dispatch read-only review pointing at the files + threat model).
7. Commit on operator go-ahead (dual Co-Authored-By: codex + Claude). Update STATUS
   `<!-- HUMAN-START -->` + memory.

---

## 3. Verification gotchas / learnings
- **pyrage is a hard dep** (age scrypt, in-memory). Prebuilt `aarch64`
  manylinux wheel exists → no Rust toolchain in the slim image. The PTY/`age -p`
  path was removed (dead + fragile) — `age -p` reads /dev/tty, never pipe to it.
- **The LAN Forgejo IP (`<lan-ip>`) must never land in a tracked file** —
  dmf-init's own `.gitleaks.toml` has a `dmf-private-network-literal` rule that
  fails the build. It's a RUNTIME input (`DMF_REPO_BASE_URL` / request field) only.
  (codex once deleted that rule to pass a scan — reverted.)
- **Public-safe = tracked files only.** The built *image* is fine to contain
  private content in theory, but ADR-0036 keeps it clean by baking nothing.
- **Secrets** (passphrase, age key, repo creds): tmpfs/process-memory only; never
  disk-outside-the-encrypted-artifact, argv, env, logs, `.git/config`, or echoed
  in responses.
- `uv run` regenerates `uv.lock` (gitignored; the project is pip-based) — `rm -f`
  it after runs.

---

## 4. Next — Phase 1b (bootstrap orchestration)
Per the plan §1b: drive `bootstrap-sandbox-provision-pre-seed.yml` → **checkpoint
#2** (capture the OpenBao Tier-3 unseal key the moment pre-seed creates it) →
unseal → `bootstrap-secrets.sh seed-bao` → post-seed → configure → verify, with
**live streamed logs** + **UI human-in-the-loop pause-points** (download CA cert,
`*.<domain>`→node-IP hosts mapping, passkey enrollment) → **checkpoint #3**
post-verify. Then **1c** = Manage mode (restore → read-verify-before-lock → remote
lock → actions → re-backup; restore ordering = age-key-export before doctor).

**1b needs a live sandbox** (Lima VM `dmf-sandbox` + a wizard env) to exercise for
real — it stops being hermetic. Coordinate with the operator on the env.

**Deferred / tracked:**
- `createnew.py` `run_render_create_new`/`stream_render_create_new` are ~95%
  duplicated → DRY into one helper.
- Session-enforcement exists on the `/api/*` routes; revisit when more protected
  routes land.
- A 6th minor qwen P3 on the crypto module may exist (verdict said 2×P3, only the
  probe-cleanup one was captured) — re-confirm if touching `backup.py`.
- Push dmf-init once the operator creates the LAN Forgejo repo (`git push -u`).

## 5. Key references
- Repo: `dmf-init/` (`main` @ `c237775`). Modules in §1.
- ADR-0036; Phase 1 plan + parent container plan (§1).
- dmf-env `feat/wizard-non-interactive` (`2a75774`) — the wrapped wizard.
- Memories: `project_dmf_init_repo`, `feedback_clear_agents_before_sections`,
  `feedback_codex_dispatch_fresh_context`, `reference_agent_bridge_hardened`,
  `feedback_qwen_left_preferred`.
