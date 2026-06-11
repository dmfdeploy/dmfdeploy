---
status: executed
date: 2026-06-02
---
# DMF Init Phase 1b — Bootstrap Orchestration Design (2026-06-02)

Implementation design + slicing for **Phase 1b** of dmf-init: drive the full
sandbox bootstrap from a rendered+backed-up env (end of 1a) through to a
**verified** cluster, with **live streamed logs**, **mid-run human-in-the-loop
pause-points**, and **two more passphrase-wrapped checkpoints** (#2 capture the
OpenBao unseal key the moment pre-seed creates it; #3 post-verify).

Parent: [`DMF Init Phase 1 Implementation Plan 2026-06-02`](DMF%20Init%20Phase%201%20Implementation%20Plan%202026-06-02.md) §1b.
Builds on 1a modules (`createnew.py` streaming pattern, `backup.py`).
**Scope decision (operator 2026-06-02):** build the orchestration engine + the
real step graph **hermetically against a MOCK command runner** now; the live
end-to-end exercise against Lima `dmf-sandbox` is a **later session** (the VM is
stopped; 1b stops being hermetic at that point).

---

## 1. What's new vs the 1a render flow

`stream_render_create_new` (1a) is a **single subprocess, single request,
run-to-completion** NDJSON stream. 1b adds two things a render never needs:

1. **Mid-run pause/resume** — the bootstrap must *suspend* awaiting an
   out-of-band operator action (download CA cert, add `*.<domain>`→node-IP hosts
   entry, complete passkey enrollment), then continue. A single
   run-to-completion request can't express that.
2. **Mid-run secret capture + re-backup** — checkpoint #2 must read the OpenBao
   unseal key **the instant pre-seed produces it**, fold it into the env dir,
   add it to the **log redaction set before any later step streams**, and
   re-invoke `backup()`. Checkpoint #3 re-backups post-verify.

Everything else (subprocess spawn, line-buffered stdout→redacted NDJSON,
secret-list redaction, env from the fetched repos) is the 1a pattern reused.

---

## 2. Concurrency model — worker + canonical append-log + condition-var cursor

*(Revised per qwen-left review 2026-06-02 — see §10. The earlier queue+replay
sketch had a duplicate-on-reconnect race and a lost-terminal-event race; the
canonical-log-with-cursor model below removes both, and there is no `queue.Queue`.)*

A run-to-completion stream can't block mid-flight for an out-of-band POST, so the
**worker and the stream are decoupled** — but the stream reads from a **canonical
append-only event log**, not a consumable queue, so any number of (re)connecting
consumers see a consistent, non-duplicated, terminal-safe event sequence.

`BootstrapRun` object, stored in `app.state.bootstrap_runs[run_id]`:
- a worker **`threading.Thread`** executing the ordered step list;
- **`events: list[dict]`** — the **canonical, append-only** log of every
  (already-redacted) event. There is **no queue**; the list *is* the conduit.
- a **`threading.Condition` `cond`** guarding `events`, the `terminal` flag, and
  the `secrets` set. Producers append + `cond.notify_all()`; each consumer holds
  its own integer **cursor** into `events` and `cond.wait(timeout)`s for growth.
- `pauses: dict[pause_id, threading.Event]` — **all pre-created at `start`**
  (the step graph is known upfront), + captured resume payloads. (Fixes the
  lost-wakeup race: resume can arrive before the worker reaches the pause; it
  sets the pre-created Event, so the worker's later `wait()` returns at once.)
- a **`secrets: set[str]`** redaction set (mutable — the unseal key is *added at
  checkpoint #2*, before the unseal step logs), **read/written only under `cond`**.
- `terminal: bool` + `final_status` (`complete` | `error`).
- `passphrase` + `remotes` for re-backups (process memory only; **wiped after
  checkpoint #3 / on terminal**; never logged, never echoed; **no `__repr__`/
  `__str__` exposes them** — see §6).

**The single emit invariant (P1-2 fix):** all events go through one method —
```
def emit(event, *, terminal=False):
    with self.cond:
        self.events.append(redact(event, self.secrets))  # redact under the lock
        if terminal: self.terminal, self.final_status = True, event["event"]
        self.cond.notify_all()
```
Append + terminal-flag set happen **atomically under `cond`**, so no consumer can
ever observe `terminal=True` with the terminal event missing from `events`.

**Stream generator (sync, threadpool — matches 1a style):** holds a cursor `i`;
loops `with cond: cond.wait_for(lambda: len(events) > i or terminal, timeout=0.5)`;
yields `events[i:]`, advances `i`; **breaks immediately after yielding a terminal
event** (no post-terminal silent gap — P2-1). On `ClientDisconnect` it just exits;
nothing is lost because `events` is canonical and a reconnect resumes from `?from=i`.

Endpoints (all `Depends(require_session)`):
- `POST /api/bootstrap/start` → validates env_id has a render + a checkpoint-#1
  backup, builds the step graph, **pre-creates all pause Events**, launches the
  worker, returns `{run_id}`. Body carries passphrase (held in the run, never
  logged) + remotes + env_id.
- `GET  /api/bootstrap/stream/{run_id}?from=<n>` → `application/x-ndjson`; replays
  `events[n:]` then follows live via the cursor. Reconnect-safe, multi-consumer
  safe, **no duplicates** (cursor is per-consumer; the log is append-only — P1-1).
- `POST /api/bootstrap/resume` `{run_id, pause_id, payload?}` → stashes payload +
  sets the **pre-created** pause Event. 409 if that pause already resumed / not
  in the graph; 404 unknown run.
- `DELETE /api/bootstrap/runs/{run_id}` → wipe + drop the run from `app.state`
  (also a `run_ttl` sweeper drops terminal runs after N min — passphrase GC, P2-3).

---

## 3. Event vocabulary (NDJSON, extends 1a's `{event:…}`)

```
{"event":"run_start","run_id":"…","steps":["pre-seed","checkpoint-2",…]}
{"event":"step_start","step":"pre-seed","index":0,"kind":"command"}
{"event":"log","step":"pre-seed","line":"<redacted>"}
{"event":"step_complete","step":"pre-seed","status":"ok"}
{"event":"checkpoint","n":2,"artifact_name":"…","remotes":["a","b"]}
{"event":"pause","pause_id":"ca-cert","title":"Download CA certificate","payload":{…}}
{"event":"resume","pause_id":"ca-cert"}
{"event":"error","step":"unseal","error":"…"}        # terminal
{"event":"complete","run_id":"…","checkpoints":[2,3]} # terminal
```

`error` and `complete` are the only terminal events. `log` lines are redacted
through the run's (growing) secret set exactly as `createnew._redact_text` does.

---

## 4. Step graph (the real sandbox bootstrap — 1b.2)

Steps are typed: **command** (spawn subprocess, stream), **checkpoint** (capture
+ re-backup), **pause** (emit + block). Commands run from the fetched
`repos/dmf-env` against the rendered env, mirroring 1a's env wiring
(`DMF_DATA_ROOT`, `SOPS_AGE_KEY_FILE`, `NO_COLOR`, `TERM=dumb`).

| # | id | kind | invocation (modeled; mock-substituted in tests) |
|---|----|------|--------------------------------------------------|
| 0 | `pre-seed`    | command    | `run-playbook.sh <env> …/bootstrap-sandbox-provision-pre-seed.yml` |
| 1 | `checkpoint-2`| checkpoint | capture OpenBao unseal key → env_dir → `backup()` |
| 2 | `unseal`      | command    | `unseal-openbao.sh <env> --yes` |
| 3 | `seed-bao`    | command    | `bootstrap-secrets.sh seed-bao` |
| 4 | `post-seed`   | command    | `run-playbook.sh <env> …/bootstrap-sandbox-provision-post-seed.yml` |
| 5 | `configure`   | command    | `run-playbook.sh <env> …/bootstrap-sandbox-configure.yml` |
| 6 | `ca-cert`     | pause      | payload = CA cert PEM (public; operator trusts it) |
| 7 | `hosts-map`   | pause      | payload = `*.<domain>` → node-IP mapping lines |
| 8 | `passkey`     | pause      | payload = enrollment URL (`get-passkey-enrollment-url.sh`) |
| 9 | `verify`      | command    | `run-playbook.sh <env> …/bootstrap-sandbox-verify.yml` |
|10 | `checkpoint-3`| checkpoint | `backup()` post-verify |

Exact pause placement relative to configure/verify is a live-cluster detail the
deferred live session refines; the hermetic build proves the **structure**
(ordering, blocking, capture, redaction), not live semantics.

---

## 5. Checkpoint mechanics

`backup()` already tars the **entire `env_dir`** + age key + answers + manifest.
So a checkpoint is: *ensure the new secret is inside `env_dir`* → `backup()`.

- **Checkpoint #2:** pre-seed writes the unseal key to a known path; the
  checkpoint reads it, (a) **adds its value to the run's redaction set** *before*
  the unseal step can log, (b) ensures the file lives under `env_dir` so the tar
  captures it, (c) re-invokes `backup()`. Emits `checkpoint n=2`.
- **Checkpoint #3:** plain `backup()` re-run post-verify. Emits `checkpoint n=3`.
- **backup.py change (small, backward-compatible):** add an optional
  `checkpoint: int | None = None` to `BackupManifestMeta` + `BackupManifest`
  (default `None` keeps 1a artifacts/tests valid) so each artifact records which
  checkpoint produced it. No other backup.py behavior changes.

Re-backups reuse the checkpoint-#1 passphrase + remotes held in the run.

---

## 6. Secret hygiene (qwen adversarial-review targets)

- **OpenBao unseal key = crown jewel.** Captured the instant pre-seed emits it;
  added to the redaction set **before** any later step streams; persisted **only**
  inside the age-passphrase artifact; the plaintext copy lives on tmpfs `env_dir`
  and is wiped with the run's scratch. Never logged, never in an event, never in
  a response body.
- **Passphrase:** run-object/process memory only; excluded from request-body
  logging (D3); never echoed; re-used for #2/#3 from memory (not re-prompted, to
  avoid a second secret entry mid-bootstrap). **Wiped from the run object the
  moment checkpoint #3 completes (and on any terminal `error`)**; `BootstrapRun`
  defines **no `__repr__`/`__str__` that exposes `passphrase`/`secrets`** so an
  error handler that logs the run can't leak it; a `run_ttl` sweeper + the
  `DELETE` endpoint guarantee the run (and any residual secret material) is GC'd
  rather than living in process memory indefinitely. *(qwen P2-3)*
- **Pause payloads:** CA cert PEM is public. Enrollment URL is single-use/short
  — shown to the operator over loopback only, not logged. Hosts mapping carries
  the node IP (a runtime input, never a tracked file).
- **Redaction-set race:** the single most important ordering invariant — capture
  must complete (and the key join the set) before the `unseal` step's first byte
  is streamed. The step graph enforces this by making `checkpoint-2` a hard
  predecessor of `unseal`; **the `secrets` set is read/written only under `cond`**
  and redaction is applied inside `emit` (under the lock), so a later lazy
  consumer can never read a pre-mutation snapshot. *(qwen P1-3)*

---

## 7. Slicing (verify between each; codex lifts, claude gates, qwen reviews risk)

### 1b.1 — Orchestration engine core (hermetic) ← FIRST DISPATCH
`orchestrate.py`: typed `Step`s, `BootstrapRun` (worker thread + queue + events
replay-log + pauses + mutable redaction set), the three endpoints, a **pluggable
command executor** (the seam the mock substitutes). Reuse `createnew._redact_text`
(promote it to a shared helper). NDJSON event vocabulary (§3).
- **Tests (hermetic):** a fake step list using a tiny mock command script (emits
  N lines + exit code) + one checkpoint (mock backup) + one pause. Assert: event
  ordering; `log` redaction; **pause blocks until resume**; reconnect replay from
  offset; error is terminal + stops the graph; command non-zero exit → `error`.
- **qwen review:** the concurrency model (thread/queue/Event, no deadlock on
  client disconnect, no lost terminal event, redaction-set mutation visibility).

### 1b.2 — Real DMF step graph + checkpoint #2/#3 + pause payloads
Wire the §4 graph to real invocations (still mock-substituted in tests via the
1b.1 executor seam), the §5 checkpoint mechanics (incl. the `backup.py`
`checkpoint` field), and pause payload builders (CA cert read, hosts mapping,
enrollment URL).
- **Tests (hermetic):** full graph with mock commands + a fake pre-seed that
  writes a fake unseal key; assert checkpoint #2 captures it, **it is in the
  redaction set before `unseal` logs**, both re-backups fire with `checkpoint`
  set, all three pauses block+resume in order.
- **qwen adversarial review:** secret capture/redaction ordering (§6) — this is
  the crypto/secret gate for 1b, mirroring 1a.2-ii.

### 1b.3 — Frontend bootstrap view
React: live log console consuming the NDJSON stream (auto-reconnect with
`?from=`), step progress rail, checkpoint badges, and pause modals (download CA /
copy hosts mapping / open enrollment URL → "I've done this → Resume"). Built into
`src/dmf_init/static/app`.

---

## 8. Acceptance (hermetic — no cluster)
- `start`→`stream`→three `pause`/`resume` cycles→`complete` with `checkpoints:[2,3]`.
- Unseal key captured at #2, in the redaction set before `unseal` streams, only
  in the age artifacts; both re-backups carry the `checkpoint` field.
- Stream survives a mid-run reconnect (`?from=i` cursor; no duplicate/lost events,
  terminal event always delivered); passphrase wiped + run GC'd after #3 / on error.
- Command non-zero exit → terminal `error`, graph halts, no further steps.
- ruff clean · pytest green · gitleaks clean (incl. the private-IP rule) · arm64
  image builds · frontend builds.
- **Deferred to the live session:** real pre-seed→verify against Lima
  `dmf-sandbox`; real unseal-key path + tier-3 handling; pause-point ordering
  refinement; createnew run/stream DRY (tracked from 1a).

## 9. Resolved questions (qwen-left 2026-06-02)
- **Replay-log memory:** keep in memory (redacted events only; bound ~1 MB per
  run). Note the bound; future spool only if the model is reused at scale.
- **`start`→`{run_id}` + separate `stream` GET:** confirmed correct — a `start`
  that streams directly would hold the HTTP response open for the whole bootstrap,
  leaving no way for the client to POST a resume. Two-endpoint model stands.
- **Passphrase re-use from memory for #2/#3:** confirmed correct — re-prompting
  mid-bootstrap is a UX hazard + a new entry point. Holding on loopback for the
  run is acceptable **provided it is wiped after checkpoint #3** (§6).

## 10. Review trail
- Design qwen-left-reviewed 2026-06-02 — verdict **CHANGES-NEEDED** (3 P1 / 3 P2 /
  1 P3), all folded:
  - **P1-1** duplicate-on-reconnect → canonical append-log + per-consumer cursor,
    no `queue.Queue` (§2).
  - **P1-2** lost terminal event → single atomic `emit()` under `cond` (§2).
  - **P1-3** redaction-set thread-safety → `secrets` guarded by `cond`, redaction
    inside `emit` (§2/§6).
  - **P2-1** post-terminal stream hang → break immediately after a terminal event;
    short `wait_for` timeout (§2).
  - **P2-2** resume-before-pause lost wakeup → pre-create all pause Events at
    `start` (§2).
  - **P2-3** passphrase GC/leak → wipe after #3 + `run_ttl` sweeper + `DELETE`
    endpoint + no secret-bearing `__repr__` (§2/§6).
  - **P3-1** re-tar perf → documented: each checkpoint is a full independent
    artifact; env_dir <1 MB, ~2–3 s/backup, fine (§5).
