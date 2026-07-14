---
name: agent-bridge
description: Send prompts to other AI agents running in tmux panes (Claude, codex, Qwen, gemini, etc.) and read their replies. Use when one agent needs to delegate to or consult another agent in the same tmux session, or when the user asks to "ask claude in the other pane", "send to codex", "talk to qwen", "have the other agent do X", or "let them collaborate". Keeps the conversation visible in the terminal so the user can observe and intervene.
type: operational-procedure
scope: agent-workflow
owner: operator
review_by: '2027-01-14'
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

Roles are bound to panes by a **durable tmux pane marker** (`@ab_role`), set with
`agent-bridge register`. Routing **searches the live panes for that marker every
time** — it never trusts a cached `%id` or a remembered command. A mirror of the
bindings is kept in `~/.config/agent-bridge/panes.json` for display and
down-detection:

```json
{
  "session": "work",
  "roles": {
    "codex":      { "agent": "codex",  "last_pane_id": "%4" },
    "qwen-left":  { "agent": "qwen",   "last_pane_id": "%0" },
    "claude-top": { "agent": "claude", "last_pane_id": "%1" }
  }
}
```

**Why a marker, not a cached pane_id:** a pane_id (`%0`,`%4`,…) is stable for a
pane's lifetime, but **panes outlive the agent inside them** — stop one agent and
start another in the same pane and a cached `%id → role` map silently points at
the wrong agent. (That, plus a coarse `expect_command` like `node`/`2.1.177` that
collides across agents, is the old bug.) The `@ab_role` marker lives on the pane,
survives an agent restarting in place, and does **not** transfer to a different
agent — so resolution stays honest.

**Correctness guarantees (so you never talk to the wrong agent):**
- A role resolves by searching for the live pane whose `@ab_role == <role>`.
  **Fail closed:** zero matches ⇒ the role is `DOWN` and the send is **refused**
  (re-register); two matches ⇒ `COLLISION` ⇒ refused. No silent mis-route.
- **`send` never auto-recovers.** A lost marker stays `DOWN` and the send is
  refused — the bridge will not guess a pane from cached state (that would be
  fail-open). Recovery is an **explicit, conscious** step: `agent-bridge heal
  <role>` (below). This keeps the automatic path strictly fail-closed.
- `@ab_agent` records the agent type at register time; a `send` **refuses** if the
  pane's live program *confidently* contradicts it (the pane was repurposed),
  unless `--force`.
- Every `send` **auto-stamps the sender's own reply address** onto the prompt,
  read from *your* pane's `@ab_role` marker, so the recipient routes its answer
  back to exactly you. The reply instruction carries the **absolute path** of the
  bridge binary (not the bare name `agent-bridge`), so the recipient can run it
  even when the binary is not on its `PATH` (common for sandboxed agents). Opt
  out with `--no-reply-id`.
- `agent-bridge doctor` prints the live marker map and flags drift / unregistered
  agent panes / down roles / collisions. `agent-bridge verify [role]` gives a
  per-role PASS/FAIL.

**Residual limit:** if an agent quits and a *new session of the same agent type*
relaunches in the same pane, the marker still matches but it's a fresh
conversation with no memory. tmux cannot see that. For continuity-critical
exchanges use `agent-bridge ping <role>` (nonce-echo liveness handshake) and/or
restate context.

The CLI works for **any** agent, not just Claude Code — codex, qwen, etc. can call it too if you point them at the binary path.

## Quick start

**Bind each agent to a role.** The reliable way is to run, *from inside each
agent's pane*:

```
agent-bridge register codex          # marks THIS pane as role 'codex'
```

or bind another pane by id from anywhere:

```
agent-bridge register qwen-left %0   # marks pane %0 as 'qwen-left'
```

To bootstrap a whole session at once, `agent-bridge configure` auto-detects every
agent pane and registers it as `<agent>-<index>`; rename any with
`agent-bridge register <name> %pane --force`. Then sanity-check:

```
agent-bridge doctor      # live marker map: roles, registered vs live agent, drift/collisions
```

Re-`register` whenever you stop an agent and start a different one in its pane —
until you do, sends to that role **fail closed** (refuse) rather than mis-route.

If you invoke the bridge from outside the tmux session (or from a shell whose
`$TMUX` points at a different server), set `AGENT_BRIDGE_SESSION=work` so the
script resolves the right session instead of guessing. From inside the panes the
live session is inferred automatically.

For convenience, symlink onto PATH (so other agents in the session can call it too):

```
ln -s ~/.claude/skills/agent-bridge/bin/agent-bridge ~/.local/bin/agent-bridge
```

## Commands

```
agent-bridge register <role> [%pane] [--agent T] [--force]   # bind a role to a pane (durable marker)
agent-bridge unregister <role|%pane|--here>                  # clear a binding
agent-bridge heal <role|--all>                      # explicit recovery of a DOWN role's lost marker
agent-bridge doctor                                 # live marker map + drift/unregistered/down/collision
agent-bridge list                                   # registered roles → live panes
agent-bridge verify [role]                          # identity check; PASS/FAIL/DRIFT per role
agent-bridge panes [session]                        # raw tmux pane listing (id + index)
agent-bridge send  <role|%id> <text...>             # type + Enter (auto reply-id stamp)
agent-bridge send  <role> --no-submit -- <text>     # type only, no Enter
agent-bridge send  <role> --no-reply-id -- <text>   # suppress the reply-id header
agent-bridge send  <role> --force -- <text>         # send despite identity drift
agent-bridge send  <role> -                         # text from stdin
agent-bridge read  <role> [--lines N]               # capture pane output
agent-bridge ask   <role> [--wait S] [--lines N] -- <text>   # send + sleep + read
agent-bridge ping  <role> [--wait S]                # liveness handshake (nonce echo)
agent-bridge configure [session]                    # auto-register every live agent pane
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

- **Doctor first when the layout may have changed:** run `agent-bridge doctor`
  before a send if panes were opened/closed or an agent restarted. `DOWN` means
  the role's pane is gone (re-`register`); `UNREGISTERED` means an agent pane has
  no role yet; `DRIFT` means a pane was repurposed; `COLLISION` means a role name
  is on two panes (`unregister` the wrong one).
- **Reply-id is automatic:** you no longer hand-write "reply to claude". The
  sent prompt already carries `Reply by running: <abs-path>/agent-bridge send
  <you> -- …`, resolved from your own pane's `@ab_role` marker and stamped with
  the bridge's absolute path so it runs even off-`PATH`. Recipients should follow
  it verbatim.
- **Fail-closed, not mis-route:** `send`/`ask` refuse when a role is down,
  ambiguous, or the pane was confidently repurposed to a different agent. That's
  the whole point — re-`register` rather than `--force` (override only when sure).
- **`heal` is a convenience fallback, not a guarantee:** when a role goes `DOWN`
  because its marker was lost but the agent is *still running*, `agent-bridge heal
  <role>` re-stamps the marker from the remembered pane — saving you a trip to
  that pane to `register`. It refuses unless the remembered pane is live, free of
  any other role, and still confidently the recorded agent type. **Residual
  risk:** tmux cannot distinguish the original conversation from a *same-type
  agent restarted in that pane*, so `heal` (like the markers themselves) can bind
  to a fresh session. Follow it with `agent-bridge ping <role>` when continuity
  matters. When unsure, `register` from the live pane instead.
- **Off-PATH replies:** the auto reply-id stamp uses the bridge's **absolute
  path** and offers the sender's raw `%id` as a fallback, because direct pane-id
  routing skips role/session resolution — the leg that fails for a sandboxed
  recipient that can't resolve the session by name. If a `send <role>` reply
  reports `DOWN`/`no session`, use the `send %id` line instead.
- **Wait time:** default `--wait 10s` is for quick lookups. For real work give 30–120s. The user can also `read` again later if needed — output is just scrollback.
- **Multi-line:** bracketed paste preserves newlines correctly in Claude Code, codex TUI, and Qwen. Plain Enter at the end submits.
- **No-submit mode:** `--no-submit` types into the input buffer without pressing Enter — useful for letting the user review and submit themselves.
- **Idle detection:** the script does NOT check whether the target agent is busy. If you paste while it's mid-task, the input goes into its queue. Eyeball the pane (or `read` first) before sending if timing matters.
- **ANSI:** `capture-pane` strips ANSI by default, so the captured output is clean text.
- **Self-pane guard:** if `$TMUX_PANE` matches the resolved target, the script aborts. This makes it safe to drop into PATH without worrying about an agent talking to itself.
- **Other agents calling this skill:** they don't need Claude Code's skill system — they just shell out to the `agent-bridge` binary with the same commands.
- **Canonical path:** the tracked binary is `.agents/skills/agent-bridge/bin/agent-bridge` (per ADR-0042). The `~/.claude/skills` / `~/.qwen/skills` entries are generated symlink views into it — discovery helpers, not the source of truth.
