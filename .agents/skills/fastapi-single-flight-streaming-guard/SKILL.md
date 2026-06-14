---
name: fastapi-single-flight-streaming-guard
description: Pattern for adding server-side single-flight concurrency guards to FastAPI streaming endpoints that perform side-effects (e.g., creating resources) to prevent duplicate work from concurrent/retried requests.
source: auto-skill
extracted_at: '2026-06-12T14:00:00.000Z'
---

## When to apply

Use this pattern when:
- A FastAPI endpoint performs a side-effect (creates files, mints IDs, writes to disk)
- The endpoint returns a `StreamingResponse` (NDJSON, file download, etc.)
- A duplicate request (double-click, browser retry, refresh) would create duplicate/orphan resources
- No entity ID exists at submit time to key a per-entity lock on, so a global lock is required
- You need to mirror an existing active-run guard pattern (e.g., `bootstrap_lock` + `active_runs`)

## Implementation

### 1. Initialize state on the app

Alongside any existing state (e.g., `bootstrap_lock`, `active_runs`), add a lock and boolean flag:

```python
app.state.<name>_lock = threading.Lock()
app.state.<name>_active = False
```

### 2. Eagerly acquire in the endpoint body

**Critical**: the lock acquire and flag check must happen in the endpoint body, NOT inside the stream generator. If done inside the generator, concurrent requests will both pass the check before either starts yielding.

```python
with app.state.<name>_lock:
    if app.state.<name>_active:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT,
            detail="a <operation> is already in progress")
    app.state.<name>_active = True
```

### 3. Release in the generator's finally block

The `finally` block fires on: success, application errors (e.g., `CreateNewError`), AND `GeneratorExit` from client disconnect.

```python
def stream() -> Iterator[str]:
    try:
        yield from <actual_stream_logic>(...)
    except <AppError> as exc:
        yield error_event(exc)
    finally:
        with app.state.<name>_lock:
            app.state.<name>_active = False
```

### 4. Wrap response construction (prevent latch on pre-stream failure)

If anything between the eager acquire and the `return StreamingResponse(...)` raises, the generator never runs and its `finally` can't clear the flag — creating a permanent 409 latch.

```python
try:
    return StreamingResponse(stream(), media_type="application/x-ndjson")
except BaseException:
    # Construction failed before the generator could own cleanup — release.
    with app.state.<name>_lock:
        app.state.<name>_active = False
    raise
```

### 5. Terminate side-effect processes on GeneratorExit (including descendants)

If the streaming generator starts a subprocess (or any long-lived side-effect), the `finally` block that clears the flag will fire on `GeneratorExit` (client disconnect) **before** the side-effect is done. This reopens the race: the slot is cleared while the subprocess still mutates state.

**Critical**: a naive `proc.kill()` only kills the direct child. If that child has spawned descendants (e.g., `terraform`, `ansible`, background `sh -c`), those **survive** and keep mutating state after the flag is cleared — the race is not actually closed.

**Fix**: run the subprocess in its own session, then kill the entire process group on cancellation:

```python
proc: subprocess.Popen | None = None
try:
    proc = subprocess.Popen(
        [...],
        start_new_session=True,  # proc.pid becomes session/group leader
    )
    for line in proc.stdout:
        yield json.dumps({"event": "log", "line": line})
    proc.wait()
finally:
    # On GeneratorExit (client disconnect) the wizard AND ALL descendants
    # must be terminated before the outer flag-clear runs.
    if proc is not None and proc.poll() is None:
        try:
            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
        try:
            proc.wait()
        except Exception:
            pass
```

This ensures the entire process tree is dead **before** the outer `finally` clears the flag, so a retry cannot start a second render while any descendant from the first wizard still lives.

**Why `killpg` over `proc.kill`**: `proc.kill()` sends SIGKILL only to the direct child PID. Any grandchildren it forked (common for shell scripts, terraform providers, ansible forks) are reparented to init and continue running. `start_new_session=True` puts the process in its own session (pgid == pid), so `os.killpg(pgid, SIGKILL)` kills every process in that group simultaneously.

**Platform note**: `start_new_session=True` and `os.killpg` are POSIX-only. This is acceptable for Linux containers and macOS dev environments. If cross-platform support is needed, a different approach (e.g., tracking PIDs, process trees) is required.

### 6. Document residual edge case

Add a comment noting that if the ASGI server never iterates the body (e.g., client disconnect before streaming starts), the `finally` may not run. For short-lived localhost containers this is acceptable (restart-recoverable); an idempotency key would close it fully for production.

## Testing

### Test 1: Concurrent request returns 409

Set the flag directly to simulate in-flight, then assert the endpoint rejects:

```python
def test_<endpoint>_409_when_active(tmp_path):
    app = create_app(Settings(...))
    client = TestClient(app)
    with app.state.<name>_lock:
        app.state.<name>_active = True
    response = client.post("/api/<endpoint>", json=payload)
    assert response.status_code == 409
    assert "already in progress" in response.text
```

### Test 2: Flag resets after stream completes (proves finally fires)

Run a full render that completes (even with an error), then assert the flag is False and a subsequent request is allowed:

```python
def test_<endpoint>_flag_resets_after_stream(tmp_path):
    app = create_app(Settings(...))
    client = TestClient(app)
    with client.stream("POST", "/api/<endpoint>", json=payload) as resp:
        assert resp.status_code == 200
        # consume stream...
    assert app.state.<name>_active is False
    # Second request must not get 409
    with client.stream("POST", "/api/<endpoint>", json=payload) as resp2:
        assert resp2.status_code == 200
```

### Test 3: Cancellation terminates the subprocess tree (regression test)

Use a fake subprocess that **spawns a background descendant** that writes a sentinel after a delay, while the parent stays alive. Advance the generator once (subprocess is running), call `gen.close()`, wait longer than the descendant's delay, and assert the sentinel was NOT written.

**Critical**: the test MUST use a descendant, not a single-process fake. A single-process test (sleep 30s then touch sentinel) would PASS even with the old parent-only `proc.kill()`, making it a vacuous guard — it doesn't prove descendants die.

```python
def test_inner_generator_kills_wizard_on_close(tmp_path):
    sentinel = data_root / "SENTINEL"
    # Parent prints one line, spawns background descendant, sleeps forever.
    # The descendant writes the sentinel at t=2 if it survives.
    wizard.write_text(
        '#!/bin/sh\n'
        'echo "starting"\n'
        'sh -c \'sleep 2; touch "$DMF_DATA_ROOT/SENTINEL"\' &\n'
        'sleep 60\n'
    )
    gen = _stream_render_create_new_inner(data_root, request)
    first = next(gen)  # starts wizard, yields first line
    assert json.loads(first)["event"] == "log"
    gen.close()        # GeneratorExit -> killpg kills parent + descendant
    time.sleep(3)      # must exceed the descendant's 2s sleep
    assert not sentinel.exists(), "descendant wrote sentinel after generator was closed"
```

**Why this works**: With the OLD parent-only kill, the backgrounded descendant survives (reparented to init) and writes the sentinel at t=2 → the assertion FAILS. With the group-kill (`os.killpg`), the descendant dies with its parent at t=0 → no sentinel → the assertion PASSES.

**Proving the test discriminates**: A thorough verification temporarily reverts to the parent-only kill and confirms the test FAILS. If the test passes with both implementations, it is not guarding the right behavior.

## Verification

- `python -m pytest tests/ -q` — all tests pass, no new failures
- `ruff check src/ tests/` — lint clean
- Verify the pattern matches any existing guard in the codebase (e.g., `bootstrap_start` active-run guard) for consistency
