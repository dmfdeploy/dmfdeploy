# DMF dmf-init Phase 1b Complete + Live-Sandbox Follow-Up Handoff (2026-06-02)

**For:** the next agent picking up dmf-init — the **live `dmf-sandbox` exercise**
of Phase 1b, then **Phase 1c (Manage mode)**. Also continues the
**orchestrator + codex-lifter + qwen-reviewer** loop.
**Supersedes:** `DMF dmf-init Phase 1a + Agentic Orchestration Handoff 2026-06-02.md`
(Phase 1a; this one records Phase 1b *done, hermetically*).

---

## 0. Boot ritual first
Follow [`CLAUDE.md`](../../CLAUDE.md): `git fetch && git pull`,
`bin/generate-status.sh`, read [`STATUS.md`](../../STATUS.md), read **this** file,
skim [`docs/decisions/INDEX.md`](../decisions/INDEX.md) (esp. **ADR-0036**), and
`git status` any sub-repo before touching it. Ask before modifying a dirty sub-repo.

---

## 1. What is done (state as of 2026-06-02)

### Phase 1b (dmf-init) — bootstrap orchestration, built HERMETICALLY
**dmf-init `main` is at `78313bd`** (still **no git remote** — operator creates the
LAN Forgejo repo, then `git push -u`). 3 commits on top of 1a's `c237775`:
- `96fc93f` 1b.1 — orchestration engine core
- `2efba64` 1b.2 — real sandbox step graph + checkpoint #2/#3 (qwen secret-capture gate)
- `78313bd` 1b.3 — React bootstrap view

**Design + slicing (the contract):** `docs/plans/DMF Init Phase 1b Orchestration
Design 2026-06-02.md` — qwen-left-reviewed (CHANGES-NEEDED → all 7 folded). Read
**§2 concurrency, §3 events, §4 step graph, §5 checkpoints, §6 secret hygiene**.

**Scope decision (operator 2026-06-02):** 1b was built **hermetically against a
mock command runner**; the live cluster exercise was deferred (the Lima
`dmf-sandbox` VM was stopped). Everything below the "command executor seam" is
real; only the actual playbook runs are mock-substituted in tests.

### dmf-init Phase 1b module map (`src/dmf_init/`)
- `orchestrate.py` — the engine. Typed steps (`CommandStep`/`CheckpointStep`/
  `PauseStep`), `CommandExecutor` Protocol + `SubprocessExecutor` (the seam the
  mock/live swap on), `BootstrapRun` (**canonical append-only `events` log +
  `threading.Condition` cursor — NO queue.Queue**; single atomic `emit()` that
  redacts under the lock; pre-created pause Events; `wipe_secrets()` on terminal;
  no secret-bearing `__repr__`), `run_worker`, `stream_events(run, start_index)`.
- `bootstrap_steps.py` — the **real DMF sandbox graph** + `make_checkpoint_fn` +
  pause payload builders. `BootstrapContext` holds paths/config but **NOT the
  passphrase** (the run owns it). Checkpoint #2 reads
  `<env_dir>/openbao-keys.json`, adds every secret value to the redaction set
  **before** unseal/seed-bao stream, then `backup()`; **raises (→ terminal error)
  if the keys file is missing.**
- `backup.py` — gained optional `checkpoint:int|None` on the manifest (createnew
  checkpoint #1 sets `checkpoint=1`).
- `main.py` — `/api/bootstrap/start|stream/{run_id}?from=|resume|DELETE` (session-
  protected) + run registry under a lock + lazy TTL GC (`run_ttl_seconds`).
- `redaction.py` — shared `redact_text` (promoted from createnew in 1b.1).
- `frontend/src/BootstrapView.tsx` + `ndjson.ts` — the live console (step rail,
  checkpoint badges, redacted log stream, cursor reconnect, locked pause modal).

### Event vocabulary (NDJSON)
`run_start` · `step_start` · `log` · `step_complete` · `checkpoint` · `pause` ·
`resume` · `error`(terminal) · `complete`(terminal). See design §3.

---

## 2. NEXT — the live `dmf-sandbox` exercise (1b becomes non-hermetic)
This is where 1b stops being hermetic. **Needs the operator + a live env.**
1. Bring up Lima `dmf-sandbox` (was Stopped) + render a wizard env (the 1a
   Create-new flow, or a pre-rendered env under `~/.dmfdeploy/envs/<env>`).
2. Drive the real graph via `/api/bootstrap/start` and **confirm against reality**:
   - **openbao-keys.json path** — the capture contract assumes pre-seed writes
     `<env_dir>/openbao-keys.json` (`DMF_ENV_OPENBAO_KEYS`). Verify the sandbox
     pre-seed actually lands it there; if not, fix `make_checkpoint_fn`'s read path.
   - **unseal** — sandbox tier-3 single-key unseal via `unseal-openbao.sh <env>
     --yes`. Confirm the captured key matches what `unseal` consumes. (Mind the
     `use_pty` class bug — memory `project_unseal_openbao_use_pty_bug`.)
   - **pause payload sources** — CA-cert PEM real location, the
     `get-passkey-enrollment-url.sh` wiring (currently a hint-only stub), the real
     hosts-map subdomains (the `hs.`/`ntfy.` guesses in `build_hosts_map_payload`).
   - **pause ordering** relative to configure/verify.
   - **checkpoint #2/#3 re-backups** actually seal to the two remotes live.
3. Watch the **redaction-ordering invariant** hold with REAL key material in the
   live log stream (the whole point of checkpoint-2-before-unseal).

**Sandbox-lane gotchas to expect** (memories): `sandbox_lane_assumptions`,
`sandbox_standalone_playbook_profile_gap`, `sandbox_sops_config_class_bug`,
`seedbao_bundle_set_bug` (seed-bao may abort at cloud-lane write-back — but sandbox
lane differs; watch it), `adr0032_catalog_teardown_skew`.

## 3. THEN — Phase 1c (Manage mode)
Per the parent plan §1c: restore (age-key-export **before** doctor) →
read-verify-before-lock → remote lock → actions (re-run playbook, upgrade-in-place,
rotate, teardown) → re-backup. `restore()` already exists in `backup.py`
(`RestoreResult.cleanup()` contract). The crypto/lock path warrants another **qwen
adversarial review** like 1a.2 / 1b.2.

**Deferred / tracked:** createnew `run_render`/`stream_render` ~95% duplicated →
DRY. Push dmf-init once the operator creates the LAN Forgejo repo.

---

## 4. The orchestration loop (operator's working model — unchanged from 1a handoff)
- **claude-bottom = ORCHESTRATOR** (`%2`): slices work, writes self-contained
  specs to `/tmp`, **reviews every diff + runs ALL gates** (ruff · `uv run … pytest`
  · gitleaks · `docker build --platform linux/arm64` · `npm run build`), applies
  small well-diagnosed fixes itself, surfaces only operator-worthy decisions.
- **codex = LIFTER** (`%1`): writes the multi-file code. **Offline for python** →
  can't run the real gates (only py_compile/bash -n/gitleaks/npm build). Expect it
  to ship plausible code with bugs the gates catch (every slice had ≥1 — e.g.
  `Protocol` from the wrong module). That's the model working.
- **qwen-left = REVIEWER** (`%0`): plan/design + adversarial crypto/secret reviews.
- **Per-slice rhythm:** `/clear` the pane at each new slice → dispatch the on-disk
  spec → background idle-detector wait → review diff → run gates → bounce or fix →
  qwen review for risky slices → commit on operator go-ahead (dual Co-Authored-By:
  codex + Claude). `agent-bridge` binary: `~/.claude/skills/agent-bridge/bin/agent-bridge`;
  `verify <role>` before sends; idle = pane lacks `esc to interrupt`(codex)/`esc to
  cancel`(qwen) for ~3×15s reads; watch for codex approval prompts.
- **colima**: start it for the docker gate, **stop it when done** (memory
  `feedback_shutdown_tools_after_use`). Keep the Lima `dmf-sandbox` VM for the live
  exercise.

## 5. Key references
- Repo: `dmf-init/` (`main` @ `78313bd`, no remote). Modules in §1.
- Design: `docs/plans/DMF Init Phase 1b Orchestration Design 2026-06-02.md`;
  parent: `docs/plans/DMF Init Phase 1 Implementation Plan 2026-06-02.md` +
  `…Bootstrap Container Plan 2026-06-02.md`. ADR-0036.
- dmf-env `feat/wizard-non-interactive` (`2a75774`) — the wrapped wizard (1b clones
  it at runtime).
- Memories: `project_dmf_init_repo`, `feedback_clear_agents_before_sections`,
  `feedback_codex_dispatch_fresh_context`, `reference_agent_bridge_hardened`,
  `feedback_qwen_left_preferred`, `project_dmf_sandbox_local_vm`,
  `project_sandbox_lane_assumptions`, `project_unseal_openbao_use_pty_bug`.
