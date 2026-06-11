# Agentic Harness — In-Flight Status File Convention

> **Status**: New convention, 2026-05-24. Adopted by `bin/agentic/agent-status.sh`.
> Open for ADR ratification (see [`decisions-open.md`](decisions-open.md)).

## Problem

When two agents collaborate via `agent-bridge` (Claude in pane 2, Codex in pane
3 supervising), the supervisor's only channel for progress is `agent-bridge
read <pane> --lines N`. That:

1. Costs an LLM context-window pass per poll, growing with each read as
   scrollback accumulates.
2. Forces the supervisor to re-derive structured state (phase, PID, last task,
   pass/fail counts) from TUI prose every tick.
3. Provides no edge: the supervisor cannot tell if the worker has actually
   advanced since the previous read without an LLM diff.

## Solution

A small JSON file per in-flight task, written by the worker, read by the
supervisor. File reads are cheap (`stat` + `jq`), schema is structured, and
mtime gives a zero-cost change signal.

**Path**: `docs/agentic/in-flight/<task-id>.json`

**Not committed**: `docs/agentic/in-flight/*.json` is gitignored. The directory
is runtime state, not source-of-truth. Promote outcomes into
[`loop-log.md`](loop-log.md) or a handoff when the task completes.

## Schema

All fields are optional except `task_id`, `started_at`, `updated_at` (which
the helper always sets). The schema is open — agents may add task-specific
fields without breaking the convention.

| Field        | Type    | Meaning                                                       |
|:-------------|:--------|:--------------------------------------------------------------|
| `task_id`    | string  | Stable id matching `[A-Za-z0-9_.-]+`. Filename stem.          |
| `agent`      | string  | Role name from `agent-bridge` panes.json (e.g. `claude`).     |
| `pane`       | string  | tmux pane index, if useful for the supervisor.                |
| `phase`      | string  | Human-readable current phase (e.g. `bootstrap-verify.yml`).   |
| `started_at` | string  | ISO-8601 UTC; set on first write.                             |
| `updated_at` | string  | ISO-8601 UTC; refreshed on every write.                       |
| `pid`        | number  | OS PID of the foreground/background process driving the work. |
| `log_path`   | string  | Path to the authoritative log file the supervisor may tail.   |
| `ok`         | number  | Domain pass counter (e.g. ansible `ok=`).                     |
| `failed`     | number  | Domain fail counter (e.g. ansible `failed=`).                 |
| `status`     | string  | `running` \| `done` \| `failed` \| `halted`.                  |
| `note`       | string  | Free-text breadcrumb. Last-write-wins.                        |

## Worker side (Claude)

At each meaningful phase boundary, call:

```bash
bin/agentic/agent-status.sh write pr5-bootstrap-verify \
    --agent claude --pane 2 \
    --phase "bootstrap-verify.yml running" \
    --pid 36979 --log /tmp/dmf-playbook-logs/pr5-bootstrap-verify-...log \
    --status running
```

The helper merges over any existing fields, so each write only needs to carry
the changed fields. `started_at` is set on first write and preserved.

On completion:

```bash
bin/agentic/agent-status.sh write pr5-bootstrap-verify \
    --status done --ok 36 --failed 0 \
    --note "all four imported plays passed"
```

The file persists after `done`/`failed` until the supervisor (or the operator)
clears it — this is intentional so the next supervisor tick still sees the
terminal state without race.

## Supervisor side (Codex)

Replace `agent-bridge read claude --lines 100` polling with:

```bash
bin/agentic/agent-status.sh read pr5-bootstrap-verify
```

For the "wait until done" loop, poll the JSON instead of scrollback:

```bash
# Note: avoid the bare name `status` — zsh marks it read-only.
until task_status="$(bin/agentic/agent-status.sh read pr5-bootstrap-verify \
                       2>/dev/null | jq -r .status)"; \
      [ "$task_status" = "done" ] || [ "$task_status" = "failed" ]; do
  sleep 30
done
```

For an even cheaper signal, watch the file's mtime (no JSON parse per tick):

```bash
file=docs/agentic/in-flight/pr5-bootstrap-verify.json
last_mtime=0
while true; do
  mtime="$(stat -f %m "$file" 2>/dev/null || echo 0)"
  if [ "$mtime" != "$last_mtime" ]; then
    bin/agentic/agent-status.sh read pr5-bootstrap-verify
    last_mtime="$mtime"
  fi
  sleep 30
done
```

## Discovery

```bash
bin/agentic/agent-status.sh list
```

Lists all in-flight tasks in tabular form. Useful at supervisor session start
to discover what's already running.

## Cleanup

```bash
bin/agentic/agent-status.sh clear pr5-bootstrap-verify
```

The supervisor clears terminal-state files once they have been consumed
(e.g. promoted into `loop-log.md` or a handoff).

## What this is not

- **Not a message bus.** One-way state publication, not pub/sub. For
  bidirectional dispatch, keep using `agent-bridge send`. The status file
  reduces *polling cost*, it does not replace dispatch.
- **Not durable history.** Terminal entries should be promoted to
  `loop-log.md` and then cleared. The in-flight dir is a working set, not
  an archive.
- **Not a lock or claim primitive.** Two agents writing the same task_id
  will last-write-wins. If that matters for a future workflow, add `flock`.

## Adoption path

1. **2026-05-24 (today)**: helper + convention land. Codex adopts on next
   supervision tick — replaces `agent-bridge read --lines N` polling.
2. **Next active task**: Claude (or whoever the worker is) writes one status
   update per phase boundary. Workers without harness support degrade
   gracefully — supervisor falls back to `agent-bridge read` when the file
   is absent.
3. **ADR**: this convention should be ratified in a short ADR alongside the
   broader agentic-harness ADR series once the pattern has run for a few
   tasks.

## Related

- [`CONSTITUTION.md`](CONSTITUTION.md) — invariants the harness enforces;
  status files are observational and do not change Constitution rules.
- [`ISSUE-TEMPLATES.md`](ISSUE-TEMPLATES.md) — worker reply-token grammar;
  complementary (event-edge for ad-hoc replies; status files for steady
  state).
- [`loop-log.md`](loop-log.md) — durable history; terminal status entries
  should be promoted here.
