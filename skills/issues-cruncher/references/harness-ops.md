# Harness Ops — driving the trio over agent-bridge

Operational notes for orchestrating panes via
`~/.claude/skills/agent-bridge/bin/agent-bridge`. These are *harness reference*, not
core method — a different harness (subagents, CI bots) swaps this file out.

## Liveness & identity
- `agent-bridge list` shows pane/role/status; `agent-bridge ping <role>` does a
  nonce handshake. **Verify before dispatch** if panes may have changed.
- A pane passing `expect_command` can still be a *fresh* session with no memory —
  restate context for continuity-critical exchanges.

## Dispatch & read
- `agent-bridge send <role> - <<'EOF' … EOF` for multi-line briefs (bracketed paste
  is newline-safe). Replies auto-stamp your reply address.
- **The recipient's reply lands in *your* input** (it runs `agent-bridge send
  claude …`), arriving as a turn. You can also `read <role>` the pane scrollback.
- **codex's spinner is unreadable in capture** — its "Working 30s" frame doesn't
  refresh in `capture-pane`, so you can't gauge progress that way. Ask it to signal
  done explicitly; judge by the file/disk result, not the spinner.

## Known gotchas (paid for this session)
- **Queued messages:** a prompt sent while a pane is mid-task queues behind it. If
  it's wedged and a message is stuck "to be submitted after next tool call", send
  `tmux send-keys -t <pane_id> Escape` to flush, then re-send a clean instruction.
- **codex PATH on reply:** `agent-bridge` is often not on codex's shell PATH; it
  must reply via the full binary path. Expect a first failed attempt.
- **Directory trust:** codex re-prompts a trust gate when moved to a new repo dir;
  it blocks silently until answered.
- **ECONNRESET mid-commit:** an agent's API can drop mid-action. The on-disk work is
  usually intact — verify disk, then have it re-run just the failed step (don't
  blind-retry the whole generation).
- **Files outside the trusted dir:** when the target repo is outside an agent's
  trusted root, paste the relevant **inline diff** instead of relying on it to read
  the files.

## Hung-agent policy
Don't poll a spinner forever. Define a timeout; on exceed, `Escape`/interrupt,
capture the pane transcript, restate context, and resume from the last verified
on-disk state. A liveness ping proving the *process* is up does **not** prove the
*task* is progressing.

## Polling discipline
Don't over-poll CI or panes — it burns turns and (on this harness) the session
clock can run ahead of real/UTC time, making elapsed estimates misleading. Use the
adapter's authoritative status (`gh run view`) and back off between checks.
