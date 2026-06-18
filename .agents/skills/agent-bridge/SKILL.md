---
name: agent-bridge
description: Send prompts to other AI agents running in tmux panes (Claude, codex, Qwen, gemini, etc.) and read their replies. Use when one agent needs to delegate to or consult another agent in the same tmux session, or when the user asks to "ask claude in the other pane", "send to codex", "talk to qwen", "have the other agent do X", or "let them collaborate". Keeps the conversation visible in the terminal so the user can observe and intervene.
---

# agent-bridge

Cross-pane agent orchestration via tmux. One agent sends a prompt to another and (optionally) reads the response, while the user watches it happen in real time and can interrupt at any moment.

## When to use

- The user has multiple AI agents running in tmux panes and wants them to collaborate.
- They ask things like "ask codex to review this", "send that to the qwen pane", "let claude in the other pane try", "have them coordinate".
- You want a second opinion from a sibling agent (e.g., codex for adversarial review) and the user prefers visible terminal collaboration over silent API calls.

Do NOT use:
- For one-off subagent work — use the `Agent` tool (TaskCreate-style) instead.
- To send to your own pane (the script refuses via `$TMUX_PANE` check).

## How it works

`bin/agent-bridge` wraps three tmux primitives:

- `tmux load-buffer` + `tmux paste-buffer -p` → bracketed paste, multi-line safe.
- `tmux send-keys ... Enter` → submits the prompt.
- `tmux capture-pane -p -S -<lines>` → reads scrollback to see the reply.

Roles map to **stable tmux `pane_id`s** (not positional indexes) in
`~/.config/agent-bridge/panes.json`, each with the program it should be running:

```json
{
  "session": "work",
  "roles": {
    "claude":    { "pane_id": "%3", "expect_command": "claude" },
    "codex":     { "pane_id": "%1", "expect_command": "codex" },
    "qwen-left": { "pane_id": "%0", "expect_command": "node" }
  }
}
```

**Why pane_id, not index:** tmux renumbers pane *indexes* (`0`,`1`,…) whenever
panes are created or closed, and the same index can point at a different agent
after a restart. `pane_id` (`%0`,`%3`,…) is assigned once and stable for the
pane's lifetime. The legacy string form (`"claude": "2"`) still works but is
**unverified** — re-pin with `agent-bridge configure --enrich`.

**Correctness guarantees (so you never talk to the wrong agent):**
- Targets resolve to a stable `pane_id`.
- Before every `send`/`ask`, the target's running program is asserted against
  `expect_command`; a mismatch (wrong agent / a shell / a crashed pane)
  **refuses** the send unless `--force`.
- Every `send` **auto-stamps the sender's own reply address** onto the prompt
  (reverse-looked-up from `$TMUX_PANE`), so the recipient routes its answer back
  to exactly you — no manual "reply to X", no wrong-pane replies. Opt out with
  `--no-reply-id`.
- `agent-bridge verify [role]` prints the live truth + PASS/FAIL.

**Residual limit:** if an agent quits and a *new* session of the same program
relaunches in the same pane, `pane_id` + `expect_command` still match but it's a
fresh conversation with no memory. tmux cannot see that. For continuity-critical
exchanges use `agent-bridge ping <role>` (nonce-echo liveness handshake) and/or
restate context.

The CLI works for **any** agent, not just Claude Code — codex, qwen, etc. can call it too if you point them at the binary path.

## Quick start

First time on a machine:

```
~/.claude/skills/agent-bridge/bin/agent-bridge configure
```

That detects panes in the `work` session, writes a starter config, and prints both the config and the live pane listing. Edit role names in the JSON afterwards (the auto-named roles use `<command>-<pane>` like `node-0`, `claude-2`, `codex-aarch64-a-3`).

For convenience, symlink onto PATH (so other agents in the session can call it too):

```
ln -s ~/.claude/skills/agent-bridge/bin/agent-bridge ~/bin/agent-bridge
```

## Commands

```
agent-bridge list                                  # roles + live status (OK/WRONG/GONE)
agent-bridge verify [role]                          # identity check; PASS/FAIL per role
agent-bridge panes [session]                        # raw tmux pane listing (id + index)
agent-bridge send  <role|%id> <text...>             # type + Enter (auto reply-id stamp)
agent-bridge send  <role> --no-submit -- <text>     # type only, no Enter
agent-bridge send  <role> --no-reply-id -- <text>   # suppress the reply-id header
agent-bridge send  <role> --force -- <text>         # send despite identity mismatch
agent-bridge send  <role> -                         # text from stdin
agent-bridge read  <role> [--lines N]               # capture pane output
agent-bridge ask   <role> [--wait S] [--lines N] -- <text>   # send + sleep + read
agent-bridge ping  <role> [--wait S]                # liveness handshake (nonce echo)
agent-bridge configure [session]                    # fresh config, pinned to pane_id
agent-bridge configure --enrich                     # keep role names; re-pin live pane_id+command
```

Roles may also be a raw `%id` (e.g. `agent-bridge send %3 -- "…"`) — used by the
auto reply-id stamp so a reply is routable even when the sender has no named role.

## Examples

Send a prompt to codex and let the user watch the reply land:

```
agent-bridge send codex "Review the diff on the current branch and call out anything risky."
```

Multi-line via heredoc:

```
agent-bridge send claude - <<'EOF'
Read docs/handoffs/<latest>.md and summarise the open questions.
Reply in <=5 bullets.
EOF
```

Round-trip: send a question, wait 30s, capture the reply:

```
agent-bridge ask codex --wait 30 --lines 300 -- "What's wrong with this regex: ^[a-z]+\$"
```

Just peek at what another pane is doing:

```
agent-bridge read qwen-left --lines 50
```

## Tips

- **Verify first when the layout may have changed:** run `agent-bridge verify`
  (or `list`) before a send if panes were opened/closed or an agent restarted.
  A `WRONG`/`GONE` status means re-pin with `configure --enrich`.
- **Reply-id is automatic:** you no longer hand-write "reply to claude". The
  sent prompt already carries `Reply by running: agent-bridge send <you> -- …`,
  resolved from your own `$TMUX_PANE`. Recipients should follow it verbatim.
- **Identity refusal:** `send`/`ask` abort if the target isn't running its
  `expect_command`. Override only when you're sure: `--force`. Fix properly with
  `configure --enrich`.
- **Wait time:** default `--wait 10s` is for quick lookups. For real work give 30–120s. The user can also `read` again later if needed — output is just scrollback.
- **Multi-line:** bracketed paste preserves newlines correctly in Claude Code, codex TUI, and Qwen. Plain Enter at the end submits.
- **No-submit mode:** `--no-submit` types into the input buffer without pressing Enter — useful for letting the user review and submit themselves.
- **Idle detection:** the script does NOT check whether the target agent is busy. If you paste while it's mid-task, the input goes into its queue. Eyeball the pane (or `read` first) before sending if timing matters.
- **ANSI:** `capture-pane` strips ANSI by default, so the captured output is clean text.
- **Self-pane guard:** if `$TMUX_PANE` matches the resolved target, the script aborts. This makes it safe to drop into PATH without worrying about an agent talking to itself.
- **Other agents calling this skill:** they don't need Claude Code's skill system — they just shell out to the `agent-bridge` binary with the same commands.
