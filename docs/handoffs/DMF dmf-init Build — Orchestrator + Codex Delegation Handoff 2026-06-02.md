# DMF dmf-init Build — Orchestrator + Codex Delegation Handoff (2026-06-02)

**For:** the next (freshly cleared) Claude agent picking up this workspace.
**Your stance:** **orchestrator** — you plan, delegate the heavy lifting, and
**verify**. You do *not* hand-write large multi-file implementations yourself;
you dispatch them to **codex** (the middle-right pane) via the `agent-bridge`
skill and review what comes back.

---

## 0. Boot ritual first (do not skip)

Follow the umbrella boot ritual in [`CLAUDE.md`](../../CLAUDE.md): `git fetch &&
git pull`, run `bin/generate-status.sh`, read [`STATUS.md`](../../STATUS.md),
read **this** handoff (it's the most recent), skim
[`docs/decisions/INDEX.md`](../decisions/INDEX.md), and `git status` any sub-repo
before touching it. **Ask the operator before modifying any sub-repo that is
dirty** — that's another session's work.

---

## 1. What just landed (state as of 2026-06-02)

A new **7th component repo, `dmf-init`**, was created and wired in:

- **`dmf-init/`** — a Day-0 **stateless** Docker container (React + FastAPI)
  that wraps `dmf-env`'s `init-wizard.sh` + `bin/` toolchain behind a
  localhost-only web UI, with a **passphrase-wrapped, dual-remote backup/restore**
  lifecycle so the operator can commission a sandbox cluster and then delete the
  container with nothing left behind. **Scaffold only** — no app code yet.
  Initial commit `1f1cbe7` (approved noreply identity), **not pushed** (no remote
  yet).
- **Canonical spec:** [`docs/plans/DMF Init Bootstrap Container Plan 2026-06-02.md`](../plans/DMF%20Init%20Bootstrap%20Container%20Plan%202026-06-02.md)
  — qwen-left-reviewed; locked decisions at the top (stateless; passphrase wraps
  the age key; two backups = redundancy, passphrase = confidentiality; manual
  paste; sandbox-first; full orchestration; **wrap the bash via a new
  `init-wizard.sh --non-interactive` answers mode** — keep the CLI first-class).
- **Umbrella wiring** committed `bb497d7`: `dmf-init` added to every repo-list
  (`generate-status`, `generate-scripts-catalog`, scrub/hygiene/commit-authors
  PUBLIC_REPOS, `install-agentic-hooks`, `forgejo.env`, `sync-to-github`
  whitelist, `issue-open` scope, `preflight` loop) + `.gitignore` + `CLAUDE.md`.
  `dmf-env` stays absent from public lists (Constitution Rule 13).
- **`agent-bridge` skill was hardened** (see §3) — pane_id pinning + identity
  assertion + auto reply-id. Use it; trust it.

See memories [[project_dmf_init_repo]] and [[reference_agent_bridge_hardened]].

---

## 2. Your role: orchestrator (delegate lifting to codex, then verify)

**Division of labour:**
- **You (Claude, orchestrator):** read context, decide approach, write the small
  glue, **dispatch multi-file / heavy implementation to codex**, then **review
  every diff codex produces** before it's trusted or committed. Run the guards
  (gitleaks, shellcheck, the public gates). Surface only ADR-worthy decisions to
  the operator.
- **codex (middle-right pane, role `codex`, `%1`):** does the lifting — writes
  the code/files you spec, reports back.

> ⚠️ **Directive change (2026-06-02):** the operator now wants **codex** to be
> the lifting delegate. (A prior note said "do not use the codex pane" — that is
> superseded for this work.) qwen panes remain available, but codex is the
> primary lifter here.

---

## 3. How to delegate to codex via the hardened `agent-bridge`

Binary: `~/.claude/skills/agent-bridge/bin/agent-bridge` (skill: `agent-bridge`).
The skill was rebuilt so you **always hit the right agent**:

1. **Verify before you send** — panes/agents can change:
   ```bash
   ~/.claude/skills/agent-bridge/bin/agent-bridge verify codex
   ```
   Expect `OK  id=%1  cmd=codex-aarch64-a`. If `WRONG`/`GONE`, re-pin:
   `agent-bridge configure --enrich`.
2. **codex is a SHARED pane** (it has been running mxl-spike work). Confirm it's
   idle / not in active operator use, then **clear it** before a fresh dispatch
   — and because `/clear` is a slash command, suppress the auto reply-id stamp:
   ```bash
   agent-bridge send codex --no-reply-id -- "/clear"
   ```
3. **Dispatch self-contained context.** codex starts cold — restate the full
   task, the exact files/paths, the spec doc, and the constraints (don't assume
   it shares your context). Every normal `send` **auto-stamps the reply route**
   (`Reply by running: agent-bridge send claude-bottom -- "…"`) resolved from
   your `$TMUX_PANE`, so codex knows exactly how to answer you — you no longer
   hand-write the reply instruction.
   ```bash
   agent-bridge send codex - <<'EOF'
   <full self-contained task: goal, files, spec path, acceptance, constraints>
   When done, reply DONE/BLOCKED/HALTED with a one-line summary + the files you changed.
   EOF
   ```
4. **Collect the reply.** Either codex follows the stamped reply command (lands
   in your pane), or poll: `agent-bridge read codex --lines 150`. For a quick
   round-trip use `agent-bridge ask codex --wait 60 -- "…"`.
5. **Verify before trusting.** Read codex's actual diff (`git -C <repo> diff`),
   run shellcheck / the relevant tests, and the public gates
   (`bin/check-public-repo-hygiene.sh --repo dmf-init`, `bin/scrub-public-repos.sh`)
   before anything is committed. Codex output is a draft until you've checked it.

See memory [[feedback_codex_dispatch_fresh_context]] for the cold-dispatch rule
and [[feedback_agent_bridge_reply_back]] (reply routing is now automatic).

---

## 4. Next work — dmf-init Phase 0 (the obvious starting point)

Per the plan, Phase 0 lands **in `dmf-env`** (a component repo — branch
`<initials>/<slug>`, don't work on `main` directly there):

- Add **`--non-interactive`** (answers-file) mode to
  `dmf-env/bin/init-wizard.sh` (currently purely interactive `read`-driven; 0
  non-interactive support today). The answers-file is **inputs-only**; the
  10+ generated secrets stay wizard-internal/random (see the plan's "Answers-file
  contract"). The wizard owns SSH-privkey base64 encoding.
- Add a **parity test** (fake-data, like the wizard's existing E2E) asserting the
  non-interactive path produces a *structurally* equivalent bundle to interactive.

**This is an ideal first codex delegation:** spec it from the plan doc, dispatch
to codex, then review the diff + run shellcheck/tests yourself.

---

## 5. Open items / gotchas

- **Nothing is pushed.** Umbrella commits `bb497d7` (+ earlier) are local; the
  operator pushes on their cadence. `dmf-init`'s scaffold commit `1f1cbe7` has
  **no remote** — the operator must create the LAN Forgejo repo first
  (canonical push target is the LAN Forgejo, not the cluster one — see
  [[project_forgejo_topology]]).
- **Platform-wide hooks gap:** every component repo tracks an older
  `.githooks/pre-commit` than `bin/agentic/templates/pre-commit`, and none deploy
  `.githooks/pre-push` (the hygiene gate's pre-push check fails everywhere until
  `bin/agentic/install-agentic-hooks.sh` is run per-clone). `dmf-init` matches its
  siblings; fixing this is a separate platform decision.
- **`awk: towc: multibyte conversion failure`** prints during
  `generate-scripts-catalog.sh` / `generate-status.sh` — non-fatal (files still
  refresh + stage); an awk-locale hiccup on a multibyte glyph. Harden separately
  if it bothers you.
- **`.qwen/skills/`** is untracked in the umbrella (a qwen artifact) — leave it
  unless the operator wants it gitignored.
- **agent-bridge identity:** this session is `claude-bottom` (`%2`). The `claude`
  role is `%3` (a *different* Claude). Replies meant for *you* must target
  whatever role maps to *your* `$TMUX_PANE` — the auto reply-id stamp handles
  this for you.

---

## 6. Key references

- Spec: `docs/plans/DMF Init Bootstrap Container Plan 2026-06-02.md`
- Repo: `dmf-init/` (README, CONTRIBUTING, CLAUDE.md, docs/ARCHITECTURE.md)
- Wizard being wrapped: `dmf-env/bin/init-wizard.sh` + `dmf-env/bin/` toolchain
- Agentic rules: `docs/agentic/CONSTITUTION.md`
- Skill: `~/.claude/skills/agent-bridge/` (run `agent-bridge --help`)
