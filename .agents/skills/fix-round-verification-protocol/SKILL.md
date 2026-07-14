---
name: fix-round-verification-protocol
description: Protocol for implementing ranked defect reviews where the orchestrator verifies DONE report claims before accepting; includes verification requirements for the worker
source: auto-skill
extracted_at: '2026-06-08T16:11:57.721Z'
type: durable-pattern
scope: agent-workflow
owner: operator
review_by: '2027-01-14'
---

# Fix Round Verification Protocol

When a DONE report is submitted and the orchestrator finds defects, the fix round follows this protocol. The key insight: **the orchestrator will re-verify every claim in the second DONE report, so only report what actually landed.**

## Orchestrator side
1. Review the worker's diff (not just the commit message).
2. Verify each claim from the DONE report against actual code.
3. Find real defects (including things the DONE report claimed but did not land).
4. Rank defects: P0 (safety/correctness), P1 (security/crash), P2 (lint/polish).
5. Send fix round with explicit verification requirements — tell the worker what greps/assertions to run and include in the reply.
6. After the second DONE: re-verify each claim again before accepting.

## Worker side — fix round
1. Read all defects; do NOT restart from scratch — fold into existing work.
2. Fix P0 first (concurrency races, path traversal, missing validation), then P1, then P2.
3. For each defect:
   - Understand the root cause (not just the symptom).
   - Apply the minimal correct fix.
   - Add a **discriminating test** if the defect was a missing guard (e.g., env_id validation, symlink rejection, concurrent reject). A discriminating test FAILS on the old code and PASSES on the new code. See the `discriminating-test-design` skill for the pattern. If you authored both the fix and its discrimination test, flag it for independent review.
4. Build frontend, run pytest, run ruff — all must pass before reporting DONE.
5. Amend the commit (`git commit --amend`) — do not create a separate fix commit.

## Worker side — DONE report requirements
When reporting DONE after a fix round:
- **Do NOT assert claims — paste the grep output.** The orchestrator will re-verify.
- Example: `grep -rn certutil frontend/src` shows the Windows command (3 lines of actual output).
- Example: `grep -rn 'api/ca-cert' frontend/src` shows the completion card fetching it (1 line of actual output).
- Include the build result (e.g., `✓ 39 modules transformed. ✓ built in 765ms`).
- List what actually changed, file by file, with the specific fix applied.
- Do NOT report something as landed unless you verified it is in the code.

## Common defect categories
### P0 — Safety/correctness
- **Concurrency race**: Check-then-act patterns where two requests both pass the check before either reserves. Fix: atomic check+reserve under the same lock, with cleanup on any exception.
- **Concurrency leak**: Reserving a sentinel (`__pending__`) but only clearing on specific exception types (HTTPException, ManageError). Other exceptions (ValueError, FileNotFoundError, JSONDecodeError) leave the sentinel stuck, blocking that resource until restart. Fix: `except Exception` catches ALL pre-spawn failures; use `isinstance` to re-map to the right HTTP status before re-raising.
- **Spawn-wrap leak**: After a successful build, the `active_runs[env_id]=run_id` assignment and `worker.start()` happen outside the build try/except — if thread creation raises, the reservation is stuck with no cleanup. Fix: wrap the "set run_id + spawn" tail in `try/except`; on Exception, under lock pop both `active_runs[env_id]` and `bootstrap_runs[run_id]`; in manage_action_start ALSO roll back `session.last_checkpoint` to its prior value.
- **Path traversal**: User-controlled values (env_id, artifact_name) used in path construction. Fix: validate with regex BEFORE any path use.
- **Symlink bypass**: resolve() then is_symlink() check — resolved target is never a symlink. Fix: check is_symlink() on UNRESOLVED path first.

### P1 — Security/crash
- **Type mismatch after refactor**: Backend returns fewer fields but frontend still renders them. Fix: remove from both types and all render sites.
- **Missing endpoint**: Commit message claims an endpoint exists but it does not. Fix: add the endpoint AND the frontend that uses it.
- **Shared component duplication**: Same JSX appears in two places. Fix: factor into a shared component in ui.tsx and use in both sites.
- **Stale UI data**: Component fetches data too early (before the data exists). Fix: (a) add a Refresh/retry button so the user can re-fetch when data becomes available; (b) ALSO render the component at a later lifecycle stage where the data reliably exists.

### P2 — Lint/polish
- **TLS reuse missing chmod**: Generation path enforces permissions but reuse path does not. Fix: enforce on both branches.
- **E501 line length**: Long lines in comments or return statements. Fix: break into multiple lines.
- **Dead code**: Removed module still exists (e.g., manage_lock.py after lock removal). Fix: delete module and its test.
- **Dead config**: Settings fields and env var parsing for removed features. Fix: delete from Settings dataclass AND load_settings().
- **Validate before reservation**: User-controlled env_id validated AFTER the active_runs reserve — so a bad env_id reserves a sentinel before hitting validation. Fix: call `validate_env_id(payload.env_id)` immediately before the reserve block (NOT inside the build try/except). Map ValueError to 400 HTTPException so it stays a proper API error.

## Atomic concurrency guard pattern (P0)
When guarding against concurrent operations on the same resource (env_id):
```python
# WRONG: check and reserve in separate lock acquisitions
with lock:
    if env_id in active: raise 409
# ... gap: another request checks and passes ...
with lock:
    active[env_id] = run_id

# WRONG: only clearing on specific exception types
try:
    # ... build run ...
except HTTPException:
    _clear_active()
    raise
# ValueError, FileNotFoundError, JSONDecodeError leak the sentinel!

# CORRECT: atomic check+reserve, Exception catch with type-specific re-mapping
with lock:
    if env_id in active: raise 409
    active[env_id] = "__pending__"  # reserve immediately
try:
    # ... build run, may raise anything ...
except Exception as exc:
    _clear_active()
    if isinstance(exc, SpecificError):
        raise HTTPException(status=409, detail=str(exc)) from exc
    raise  # re-raise non-matching exceptions (HTTPException, etc.)
with lock:
    active[env_id] = run_id  # overwrite sentinel with real run_id
```
Apply to all entry points that mutate the same resource (bootstrap_start, manage_doctor, manage_action_start).

## Path traversal validation pattern (P0)
When user-controlled env_id flows into artifact names or paths:
```python
_ENV_ID_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$")

def validate_env_id(env_id: str) -> None:
    if not _ENV_ID_RE.match(env_id):
        raise ValueError(f"env_id must match ..., got {env_id!r}")

# Call in backup() BEFORE building artifact_name
validate_env_id(manifest_meta.env_id)

# Call in manage.py AFTER reading manifest.env_id, BEFORE any rmtree/copytree
validate_env_id(env_id)
```

## Env_id validation at entry points (P1-2)
Don't just validate env_id at leaf functions (backup, restore). Also validate at **entry points** where env_id is first used to build paths:
- `BootstrapContext.from_data_root()` — validates before building `runs/<env_id>`, `envs/<env_id>`
- `run_backup_create_new()` — validates before building `render_dir`, `env_dir`
- `run_render_create_new()` / `stream_render_create_new()` — validate IMMEDIATELY after wizard-derived env_id is discovered, BEFORE `data_root / "runs" / env_id` or `shutil.rmtree`

Centralizing validation at these entry points covers all callers transitively (including bootstrap_start).
