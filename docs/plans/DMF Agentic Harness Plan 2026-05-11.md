---
status: historical
date: 2026-05-11
---
# DMF Agentic Harness Plan 2026-05-11

> **Status**: Proposed
> **Scope**: Umbrella + all 6 component repos
> **Target**: First public GitHub release (v0.1.0), operator-pushed
> **Audience**: All DMF agents (Claude orchestrator, qwen-left, qwen-right) and human operator
> **Authority**: Constitution in `docs/agentic/CONSTITUTION.md` (created by this plan) governs day-to-day agent behavior; this plan governs how the constitution and supporting machinery get built.

## Context

The DMF Platform is in *experiment phase* and approaching first public GitHub release.
The foundation for safe automation already exists — 20 ADRs, pre-commit gitleaks,
`bin/sync-to-github.sh` push gate, `bin/scrub-public-repos.sh`, STATUS.md auto-refresh,
10 Claude subagent personas, 3 DMF skills, structured `docs/handoffs/` continuity ritual.
What is missing is a **regimented loop** that lets agents grind through the remaining
~5–7 days of release-prep + Move 1 work without an operator at the keyboard, while
provably not drifting, leaking secrets, or making decisions that should reach a human.

This plan adds three thin layers on top of the existing automation: a **constitution
+ backlog** (data), **guards + gates** (enforcement), and a **tick runner with Qwen
delegation** (execution). The loop terminates short of the GitHub push — the operator
performs that step manually as the final gate. Decision-surfacing is limited to
ADR-worthy architectural forks; everything else is agent-decidable.

**Topology**: Claude (this pane) orchestrates. Two Qwen panes (`qwen-left` top-left,
`qwen-right` top-right) execute implementation work in parallel via the existing
`agent-bridge` skill. **No Codex.** No autonomous cron — ticks run within a live
Claude session via `/loop` so the operator can interrupt at any time.

**Decisions captured upstream of this plan**:

*2026-05-11 session:*
- Loop driver: multi-agent panes via agent-bridge (qwen-left, qwen-right)
- Terminal state: Move 1 + Release prep complete, GitHub push is operator-only
- Decision threshold: surface ADR-worthy architectural forks only
- Hermes (nousresearch/hermes-agent): evaluated and deferred to post-v0.1.0 (see Out-of-scope §)

*2026-05-12 session — issue substrate added (Layer 4):*
- Agent-opened issues live on Forgejo (LAN, private) pre-v0.1.0; curation pass migrates public-safe issues to GitHub at publish
- Two-tier work model: `backlog.yaml` holds the v0.1.0 sprint queue; Forgejo issues hold deferred work, workarounds, feature backlog, post-release pickups
- Orchestrator-only authors issues; Qwen workers report via structured reply tokens (`WORKAROUND:`, `BLOCKED:`, `FEATURE-GAP:`) and Claude validates + opens
- Scrub gate on issue bodies is strict: ANY gitleaks/scrub hit hard-fails the script; agent must rewrite using `<placeholder-name>` syntax (same posture as `.githooks/pre-commit`)

---

## Architecture (3 layers)

### Layer 1 — Data: constitution + backlog + decision queue

Four new files under `docs/agentic/` (umbrella):

| File | Role | Mutability |
|---|---|---|
| `CONSTITUTION.md` | Non-negotiable rules agents must obey | Read-only during loop; updated only by operator |
| `backlog.yaml` | Work-unit queue with deps, gates, scope, status | Mutated only by tick state machine |
| `decisions-open.md` | Operator's inbox — ADR-worthy questions surfaced by the loop (forward queue) | Agent writes; operator answers |
| `autonomous-decisions.md` | Append-only log of orchestrator-resolved non-ADR-worthy choices (retrospective record) | Append-only |
| `loop-log.md` | Append-only tick history (who did what, guards, halts) | Append-only |

`backlog.yaml` schema (one entry per work unit):

```yaml
- id: rel-phase0-license-cms
  scope: dmf-cms
  kind: rote          # rote | taste | decision | review
  worker: qwen-right  # qwen-left | qwen-right | claude | operator
  deps: []
  decision_gate: null
  acceptance:
    - file_exists: dmf-cms/LICENSE
    - file_exists: dmf-cms/NOTICE
    - guard: scrub-public-repos.sh dmf-cms
  status: pending     # pending | in-progress | blocked | done
```

### Layer 2 — Enforcement: guards + gates

| Script | When | What it checks |
|---|---|---|
| `bin/agentic/preflight.sh` | Start of every tick | Constitution unchanged hash, STATUS.md fresh (<30min), no dirty sub-repo unless current task expects it, no orphan handoffs |
| `bin/agentic/postflight.sh` | End of every tick | gitleaks clean, scrub clean, STATUS.md regenerated, loop-log entry written, handoff written if state changed |
| `bin/check-public-repo-hygiene.sh` | Per repo, on demand + every tick | LICENSE/NOTICE/VERSION/.gitignore/CODEOWNERS present; gitleaks hook installed; identity sweep clean (Tier A.6 + A.8) |
| `.claude/settings.json` (tightened) | Always | Bash allowlist excludes `git push`, `kubectl apply`, `rm -rf`, raw `helm` outside scripts; require `bin/sync-to-github.sh` for any GitHub push |
| Per-repo `.githooks/pre-push` | Every push attempt | Refuses unless `SYNC_TO_GITHUB=1` env set by `bin/sync-to-github.sh` |

The existing `bin/sync-to-github.sh` (6 gates) and umbrella pre-commit (gitleaks +
STATUS) stay as-is. The new scripts wrap, not replace.

### Layer 3 — Execution: tick runner + Qwen delegation

Two new skill commands at `.claude/commands/`:

- `/agentic-tick` — one iteration: preflight → pick next eligible task → delegate
  to assigned worker → wait for completion via `agent-bridge` → postflight → log.
- `/agentic-run` — orchestrator entry. Calls `/loop /agentic-tick` with self-paced
  cadence (default ~20 min between ticks, immediate on completion).

**Delegation map** (encoded in `backlog.yaml` `worker:` field, summarized here):

| Task kind | Worker | Examples |
|---|---|---|
| Ansible playbooks/roles | `qwen-right` | Move 1 Pieces 2, 3, 5, 6, 8 |
| FastAPI + React | `qwen-left` | Move 1 Piece 7 (dmf-cms catalog page) |
| Docker/Helm build, build-image | `qwen-right` | Move 1 Piece 4 (NMOS provision) |
| Schema, YAML, rote file generation | `qwen-left` | Release Phase 0 (LICENSE/NOTICE/VERSION × 6 repos) |
| Cross-cutting docs (handoffs, ADRs, write-ups) | `claude` | Move 1 Piece 9, ADR drafts |
| Taste calls, secret-touching, cluster ops | `claude` | Anything matching ADR-0019/0011 (secrets) or skill guards |
| ADR-worthy decisions | `operator` | D1–D4, ADR-0020 promotion, GitHub org name |

Qwen pane handoff uses the existing `agent-bridge` skill: orchestrator sends a
self-contained prompt (task id, scope path, acceptance checklist, "report DONE
when guards pass"); waits for the pane's reply; verifies the diff before
postflight. Trust-but-verify is enforced — Claude reads the actual changes
before marking the task complete.

#### Qwen context hygiene (`/clear` protocol)

Stale Qwen context is a primary drift vector — a pane that just finished an Ansible
role will subconsciously apply Ansible idioms to the next React task unless reset.
The orchestrator issues `/clear` to a Qwen pane via `agent-bridge` *before* sending
the next task prompt when **any** of the following triggers fire:

| Trigger | Why |
|---|---|
| Scope changes repo (e.g. `dmf-infra` → `dmf-cms`) | Different conventions, different CLAUDE.md |
| Task kind changes (`rote` ↔ `taste`, Ansible ↔ React, schema ↔ playbook) | Different tooling + review bar |
| Backlog group boundary crossed (A → B → C → D) | Different acceptance shape; group D may touch secret-adjacent scope |
| Task touches a skill-guarded scope (`dmf-cluster-access`, `dmf-openbao-unseal`, `dmf-cms-build-and-release`) | Skill §0 must be re-read fresh |
| Previous task in same pane halted on guard failure or error budget | Avoid carrying error state into retry |
| Pane has executed ≥ 5 tasks since last clear | Bounded context window; prevents creeping bloat |
| First tick of a new `/agentic-run` invocation | Cold start |

Conversely, the orchestrator **keeps** Qwen context across consecutive tasks when
all of: same repo, same kind, same group, no halt, no skill guard, count < 5.
This is the common case for Group B (six LICENSE files in a row) — the second through
sixth tasks reuse the priming from the first.

Per-task prompt template the orchestrator sends after `/clear`:

```
You are operating as worker {pane} for the DMF agentic loop.

TASK ID: {id}
SCOPE: {repo path}
KIND: {rote|taste|...}
CONSTITUTION: $DMFDEPLOY_UMBRELLA/docs/agentic/CONSTITUTION.md
SKILL (if applicable): {skill name} — read §0 before any tool call in scope.

WORK:
{specific instruction or backlog acceptance items}

REPORT FORMAT:
- Reply with "DONE: {id}" + paths of files changed, OR
- Reply with "BLOCKED: {id}" + the obstacle (do not improvise).
Do not run any push, deploy, or cluster mutation. Do not edit other repos.
```

Clear logs go into `loop-log.md` as `clear: qwen-right (reason: scope-change)`
so the operator can audit context boundaries post-hoc.

#### Autonomous decision routing (halt-vs-proceed rubric)

Most tick-time choices don't need the operator. The orchestrator decides locally
and logs why; the operator audits on return. The discriminator that separates
"halt + surface" from "pick + log" has two layers.

**Layer A — explicit worker signal.** A Qwen reply token of `DECISION-NEEDED:` or
`BLOCKED: needs-decision` always halts; the worker has explicitly named a fork the
orchestrator should not resolve. These flow to `decisions-open.md`.

**Layer B — orchestrator self-classification.** Even when the worker hasn't named
a fork explicitly, the orchestrator halts autonomously when **any** of the
following hold (canonical rubric — referenced by Constitution rule 5):

| Rule | Condition |
|---|---|
| a | The choice changes a public surface or contract (Secret name, API path, config-file location, label key, exported variable, public README behavior) |
| b | The choice touches more than one repo |
| c | The choice contradicts or supersedes an existing ADR |
| d | The choice removes an option already considered in a plan doc |
| e | The choice crosses a skill-guarded boundary (cluster ops, OpenBao, dmf-cms release) |

None of (a–e) hold → proceed and log rationale. The rubric is intentionally
conservative: false-positive halts cost ~one operator nudge; false-negative
proceeds cost an ADR-worthy decision being made silently.

##### Rationale log: `docs/agentic/autonomous-decisions.md`

Append-only, one line per decision:

```
<ISO-timestamp> | <task-id> | <one-line decision> | <rationale ≤140ch> | <commit-sha or file-path>
```

NOT `decisions-open.md` (forward queue, distinct semantics). NOT issue comments
(issues are forward-looking work, not retrospective log). Inline code comments
allowed *only* when the choice is truly local to one file and the WHY is
non-obvious at the call site — the standing comment rule still applies. Single
grep target for "what did the harness decide?".

##### Budgets (bounded autonomy)

Three tiers prevent unbounded autonomy:

| Budget | Limit | Behavior on hit |
|---|---|---|
| Per-task | 2 consecutive `WORKAROUND:` tokens on the same backlog entry | Promote to issue + halt that entry |
| Per-tick | ≤1 autonomous decision per tick | Bounds context creep; keeps loop-log entry granular |
| Per-shift | 10 autonomous decisions per `/agentic-run` invocation (operator-raisable via `--autonomy-budget=N`) | **Soft pause**: write summary block, halt for review. Operator resumes with `--continue-after-summary` — no `/agentic-run` restart needed. |

The per-shift budget is what prevents the failure mode where operator returns to
a 200-line decision log and review takes as long as the work did. Soft semantics
keep the operator round-trip cheap when the auto-decisions look fine on glance.

##### Operator audit artifact

The "ready-for-operator-push" handoff (and per-shift pause summaries) open with a
§"Autonomous decisions taken" section grouping decisions by category (file-layout,
dependency-pick, commit-message wording, error-handling shape, etc.) with counts
and a pointer to the log line range. **Handoff = the index. Log = the detail.**
5-minute scan target: the §block fits on one screen; operator drills into the log
only for line items they want to ack or revert. Operator responses
(`ack` / `revert <line>`) land in the same handoff to keep the round-trip in one
file rather than three.

---

### Layer 4 — Issue substrate (deferred work + workarounds)

`backlog.yaml` is the v0.1.0 sprint queue: small, time-boxed, every entry has explicit
acceptance and dependencies. It does not absorb open-ended or post-release work without
losing its character. **Forgejo issues** are the second pillar: a durable, queryable
store for tech-debt workarounds, deferred features, observed bugs, and post-v0.1.0
pickups. Pre-publish they live on LAN Forgejo (private, leak-safe); at v0.1.0 publish
a curation pass migrates public-safe issues to GitHub.

#### Issue types

| Type label | Meaning | Source |
|---|---|---|
| `type:workaround` | Agent bodged to keep moving; needs proper fix later | Worker reply `WORKAROUND:` |
| `type:feature` | Queued feature work for later pickup | Worker reply `FEATURE-GAP:` or operator-seeded |
| `type:bug` | Observed defect, not yet diagnosed | Worker reply `BUG:` or operator-seeded |
| `type:decision-requested` | ADR-worthy fork that surfaced mid-work, work isn't blocked by it (use `decisions-open.md` when work IS blocked) | Worker reply `DECISION-NEEDED:` |

#### Label taxonomy (all enforced by `issue-open.sh`)

- `agent-opened` — always; distinguishes from operator-opened
- `type:<workaround|feature|bug|decision-requested>` — exactly one
- `scope:<dmf-cms|dmf-infra|dmf-central|dmf-media|dmf-runbooks|umbrella>` — at least one; `dmf-env` forbidden (private, never has agent issues)
- `pickup:<ready|blocked|in-progress|deferred>` — exactly one
- `effort:<S|M|L>` — rough sizing
- `public-safe` — set later by `issue-migrate-to-github.sh` after re-scrub; never set at open

#### Authorship rule (constitution-bound)

Only the orchestrator (Claude) runs `bin/agentic/issue-open.sh`. Qwen workers never
touch the Forgejo API directly. Workers communicate via structured reply tokens in
their `agent-bridge` reply. The orchestrator parses, validates, runs scrub, and opens.

#### Worker reply formats (expanded grammar over the Layer 3 DONE/BLOCKED set)

```
WORKAROUND: <one-line summary>
RATIONALE: <why the bodge was needed>
PROPER-FIX: <what should happen later>
SCOPE: repo=<repo>, files=<...>
RELATED: ADR=<id-or-none>, plan=<path-or-none>
```

```
BLOCKED: <one-line summary>
BLOCKER-KIND: missing-dependency | unknown-state | upstream-bug | needs-decision
DETAILS: <free text; MUST use placeholder syntax for IPs/hostnames>
SCOPE: repo=<repo>, files=<...>
RELATED: ADR=<id-or-none>, plan=<path-or-none>
```

```
FEATURE-GAP: <one-line>
DISCOVERED-WHILE: <backlog task id>
WHY-DEFERRED: not-in-v0.1.0-scope | needs-design | external-dependency
SCOPE: repo=<repo>, files=<...>
RELATED: ADR=<id-or-none>, plan=<path-or-none>
```

```
BUG: <one-line>
OBSERVED: <what happened>
EXPECTED: <what should have happened>
REPRO: <minimal steps; placeholder syntax mandatory>
SCOPE: repo=<repo>, files=<...>
```

```
DECISION-NEEDED: <one-line>
OPTIONS: <A: ..., B: ..., C: ...>
RECOMMENDATION: <which and why, or "no preference">
SCOPE: repo=<repo>, files=<...>
```

If a reply doesn't parse cleanly, orchestrator sends it back to the worker for
refinement — never improvises the missing fields.

#### Control scripts

| Script | Purpose | Gates |
|---|---|---|
| `bin/agentic/issue-open.sh` | Open new issue on Forgejo | scrub + gitleaks on full body+title; title regex; dup-check; required fields; label-set validation |
| `bin/agentic/issue-list.sh` | List agent-opened issues by label (JSON or table) | read-only |
| `bin/agentic/issue-promote.sh <id>` | Promote a `pickup:ready` issue into `backlog.yaml` | requires all template sections filled; sets backlog entry's `issue:` field |
| `bin/agentic/issue-close.sh <id>` | Close an issue with structured reason | requires `--reason=<resolved\|superseded\|deferred\|declined>` + `--ref=<commit-sha-or-handoff-path>` |
| `bin/agentic/issue-migrate-to-github.sh` | At v0.1.0 publish: scrub + mirror `public-safe` issues to GitHub | dry-run default; operator approves the migration list |
| `bin/agentic/forgejo.env` | Sourced config: host (`<forgejo-host>` placeholder), token path, default labels | read-only; token never echoed |

The scripts are thin wrappers around the Forgejo REST API + `curl` / `tea` (whichever
is already installed). They do not introduce a new dependency surface beyond
`bin/agentic/forgejo.env` and the gates already used by `sync-to-github.sh`.

#### Issue body template (enforced by `issue-open.sh`)

```markdown
## Context
What the agent was doing, why this came up. Reference plans/ADRs/handoffs.

## Acceptance
Explicit, testable criteria. What does "done" look like?

## Scope
- repo: <repo-name>
- files: <path1>, <path2>
- skill (if any): <skill-name from CLAUDE.md "skill-guarded operations">

## Constraints
Things the picker-upper MUST NOT change. ADR refs that bind the work.

## Decision points
Any ADR-worthy gates ahead (or "none").

## Related
- ADR: <id-or-none>
- Plan: <path-or-none>
- Handoff: <path-or-none>
- Issues: #<id> (related/blocks/blocked-by — use Forgejo's native cross-link syntax)
```

Missing any section → reject. Sections present but empty → reject.

#### Drift firebreaks specific to issues

1. **Title regex**: `^[A-Za-z][A-Za-z0-9 :_/.\-]{4,80}$`. No `<placeholder>` syntax in titles (placeholders allowed in body only; titles must be self-describing).
2. **Scrub gate**: full body + title piped through `bin/scrub-public-repos.sh --stdin` + `gitleaks detect --no-git --pipe`. Any hit → reject; agent rewrites with `<placeholder-name>` syntax and resubmits. Same posture as `.githooks/pre-commit`.
3. **Dup-check**: fuzzy-match title against open agent-opened issues (Levenshtein ≤ 5 OR 80%+ token-overlap) → reject with the candidate's `#id` so agent can comment on existing issue instead.
4. **Stale-ref check**: every commit hash in body must resolve via `git cat-file -e`. Amended hashes → reject.
5. **Cross-repo enforcement**: if `scope:` resolves to multiple repos, reject with instruction to file one issue per repo plus a tracker issue with `type:feature` linking them.
6. **Label-set validation**: ≥1 `scope:`, exactly 1 `type:`, exactly 1 `pickup:`, exactly 1 `effort:`, plus `agent-opened`. Missing/extra → reject.
7. **Body length cap**: 8 KB. Larger → reject (issue is the index, not the document — link to a handoff or plan if more is needed).

#### Backlog ↔ issue linkage

A `backlog.yaml` entry may now carry an `issue:` field:

```yaml
- id: move1-piece3-forgejo-mirror
  scope: dmf-infra
  kind: rote
  worker: qwen-right
  issue: forgejo#147        # the work originated as an issue
  status: in-progress
```

And an issue's body `Related: Plan:` line points back to the backlog entry by id.
This is the only allowed cross-reference shape — no other coupling between the two
stores. Promote moves an issue → backlog; close removes the backlog entry (or marks
it `done`) and updates the issue with `--ref`.

#### Local mirror state

`docs/agentic/issues.yaml` (new) holds a thin local mirror of agent-opened issues
(id, title, type, scope, pickup, sha-of-body-at-last-sync). Postflight runs
`bin/agentic/issue-list.sh --json` and reconciles drift between local mirror and
Forgejo. Mismatch → halt with a handoff (someone edited issues outside the loop).

#### Migration to GitHub at v0.1.0 publish

`bin/agentic/issue-migrate-to-github.sh` is a separate, operator-invoked script:

1. For each agent-opened issue without `public-safe`, run scrub on body + comments.
2. Issues that pass → tag `public-safe`, queue for migration.
3. Issues that fail → tag `stay-private`, list reasons.
4. Operator reviews the queue (`--dry-run` shows the would-be migration list).
5. On approval, script creates GitHub issues via `gh issue create`, mirrors body, adds
   `Mirror: forgejo#<id>` line; comments on Forgejo issue with `migrated: gh#<id>`.
6. Forgejo issue stays open as the canonical work record; GitHub is the public face.

This is operator-only and runs *after* v0.1.0 push, not as part of the loop.

Loop halts and writes a handoff under any of:

1. **Decision gate hit** — task has `decision_gate: D1` (or similar) → write entry to
   `decisions-open.md` with context + options + recommendation; mark task blocked.
2. **Guard failed** — gitleaks/scrub/hygiene non-zero → write failure handoff with
   exact failing rule; task back to pending; halt.
3. **Backlog exhausted at current dependency layer** — write progress handoff; halt.
4. **Error budget exceeded** — same task fails postflight 2× in a row → halt.
5. **Constitution hash changed mid-loop** — operator edited the rules → halt; reload
   on next manual `/agentic-run`.
6. **Dirty sub-repo not expected by current task** — another agent/session has
   in-progress work → halt per CLAUDE.md boot ritual.
7. **Terminal state reached** — all Move 1 + Release Phases 0–2 + Tier A blocking
   subsections (A.1, A.3, A.4, A.5, A.6, A.8, A.9) `done`; loop writes
   "ready-for-operator-push" handoff and exits.
8. **Scrub blocked issue creation 2× on same content** — agent cannot produce a
   placeholder-safe rewrite → halt and surface to operator with the offending pattern.
9. **Forgejo API unreachable** — workaround/feature discoveries would otherwise be
   silently dropped → halt; do not continue without the issue substrate available.
10. **Local issue-mirror reconciliation failed** — `docs/agentic/issues.yaml` diverges
    from Forgejo (someone edited issues outside the loop) → halt; operator decides
    whether to accept their edits or revert.

The loop does *not* run `bin/sync-to-github.sh` and does *not* run
`bin/agentic/issue-migrate-to-github.sh`. Both are operator-only.

---

## Initial backlog (seeded for v0.1.0)

Three groups, sequenced by dependency:

### Group A — Foundation (must complete first)

| id | scope | kind | worker | gate |
|---|---|---|---|---|
| adr-0020-promote | umbrella docs | decision | operator | Tier A.1 |
| constitution-install | umbrella | rote | claude | — |
| backlog-seed | umbrella | rote | claude | — |
| github-org-name | umbrella docs | decision | operator | Release Phase 2 |

### Group B — Release & Contribution Phases 0–2 (6 repos × small artifacts)

Generated from `docs/plans/DMF Release and Contribution Model Implementation Plan 2026-05-11.md`:

- **Phase 0** (6 repos × 5 artifacts = 30 rote tasks): LICENSE, NOTICE, VERSION, `.gitignore` baseline, CONTRIBUTING.md stub. Worker: `qwen-left`. Acceptance per task: file exists + scrub clean.
- **Phase 1** (1 task per repo + 1 generalization): per-repo gitleaks pre-commit hook install via extended `bin/install-hooks.sh`. Worker: `qwen-right`.
- **Phase 2** (build + dry-run): `bin/check-public-repo-hygiene.sh`, `bin/sync-to-github.sh --dry-run` for all 6 repos. Worker: `claude` (script build), `qwen-right` (dry-run execution).

Group B is roughly **35 tasks**, all `kind: rote`, no decision gates. Should burn down in 1–2 loops.

### Group C — Move 1 (9 pieces, gated by D1–D4)

Direct copy from `docs/plans/dmf-platform-move-1-task-2026-05-04.md`:

| Piece | Worker | Gate |
|---|---|---|
| 1 — Catalog schema + first entry | `qwen-left` | — |
| 2 — `lifecycle-configure.yml` wrapper | `qwen-right` | D2 |
| 3 — Forgejo mirroring + AWX project | `qwen-right` | D3 |
| 4 — NMOS provision-side (Ansible + Docker + Helm) | `qwen-right` | D1 |
| 5 — NMOS configure-side launch playbook | `qwen-right` | — (depends on D2) |
| 6 — AWX job templates + launcher | `qwen-right` | — (depends on D3) |
| 7 — dmf-cms catalog page (FastAPI + React) | `qwen-left` | D4 |
| 8 — Drift-detector smoke test | `qwen-right` | — |
| 9 — Write-up | `claude` | — |

D1–D4 are surfaced to `decisions-open.md` at loop start so the operator can answer
them before Group C begins (each has a recommended default already in the task spec).

### Group D — Tier A finish (parallel with Group C where independent)

From `docs/plans/DMF Pre-Release Compliance Readiness Plan 2026-05-11.md`:

- A.3 SELF-HOST-DISCLAIMER.md × 6 repos — `qwen-left`, rote
- A.4 Audit-log retention policy doc — `claude`, taste
- A.5 Cosign bootstrap doc — `claude`, taste (secret-adjacent)
- A.6 Identity sweep close-out — `qwen-right`, rote (runs scrub script)
- A.8 dmf-env-off-GitHub re-verify — `qwen-right`, rote
- A.9 Supplier register stub — `qwen-left`, rote

A.7 already done. A.2 covered by Group B.

---

## Critical files to create or modify

**New (this plan creates them)**:
- `docs/agentic/CONSTITUTION.md`
- `docs/agentic/backlog.yaml`
- `docs/agentic/decisions-open.md`
- `docs/agentic/autonomous-decisions.md` (append-only retrospective log of non-ADR-worthy auto-resolved choices)
- `docs/agentic/loop-log.md`
- `docs/agentic/issues.yaml` (local mirror of agent-opened Forgejo issues)
- `docs/agentic/ISSUE-TEMPLATES.md` (canonical issue body templates + label taxonomy)
- `bin/agentic/preflight.sh`
- `bin/agentic/postflight.sh` (extended to reconcile `issues.yaml`)
- `bin/agentic/issue-open.sh`
- `bin/agentic/issue-list.sh`
- `bin/agentic/issue-promote.sh`
- `bin/agentic/issue-close.sh`
- `bin/agentic/issue-migrate-to-github.sh` (operator-only; runs at v0.1.0 publish)
- `bin/agentic/forgejo.env` (sourced config; token path, host placeholder)
- `bin/check-public-repo-hygiene.sh` (already referenced in compliance checklist)
- `.claude/commands/agentic-tick.md`
- `.claude/commands/agentic-run.md`
- `.githooks/pre-push` (in each public repo, gated on `SYNC_TO_GITHUB=1`)

**Modified (existing files extended)**:
- `bin/install-hooks.sh` — extend to install per-repo gitleaks + pre-push hooks
- `.claude/settings.json` — tighten Bash allowlist; explicitly deny direct `git push`, raw `kubectl apply`, broad `rm -rf`
- `CLAUDE.md` — add §"Agentic loop" pointing at `docs/agentic/CONSTITUTION.md` and at this plan

**Untouched (existing automation stays as-is)**:
- `bin/sync-to-github.sh` (already correct; loop never invokes it)
- `bin/scrub-public-repos.sh` (called from postflight + hygiene check)
- `bin/generate-status.sh` (called from postflight)
- `.githooks/pre-commit` (already installed; gitleaks + STATUS refresh)
- All 10 `.claude/agents/*.md` persona cards (referenced by `agentic-tick` for in-pane delegation)
- All 3 DMF skills (called by loop when scope matches)

---

## Constitution highlights (full text in CONSTITUTION.md)

Codified from CLAUDE.md, ADRs, hooks, and the public-release handoff. The agent
references this file at the start of every tick.

1. **Push gate**: Never run `git push` to a `github` remote. Use `bin/sync-to-github.sh`,
   which is operator-only. Pre-push hook blocks direct pushes.
2. **Secret gate**: gitleaks + scrub must pass before any commit. If either fails,
   the agent fixes the leak or halts — never disables the rule.
3. **Sub-repo dirty rule**: If a sub-repo has uncommitted changes the agent didn't make,
   halt and surface to operator (per CLAUDE.md boot ritual §5).
4. **Skill-guarded operations**: Cluster ops (`dmf-cluster-access`), OpenBao
   (`dmf-openbao-unseal`), dmf-cms release (`dmf-cms-build-and-release`) require
   reading §0 of the relevant skill before any tool call in that scope.
5. **Decision surface**: A choice is ADR-worthy (halt + surface to
   `decisions-open.md`) when worker emits `DECISION-NEEDED:` or `BLOCKED:
   needs-decision`, OR when **any** of Layer 3's canonical rubric holds:
   (a) changes a public surface/contract; (b) touches >1 repo; (c) contradicts or
   supersedes an existing ADR; (d) removes an option already considered in a plan
   doc; (e) crosses a skill-guarded boundary. None of those → orchestrator resolves
   and appends to `autonomous-decisions.md` (one line: timestamp | task-id |
   decision | rationale ≤140ch | commit-or-path). Defaults from existing plan docs
   (D1–D4) are pre-populated but require operator confirmation.
6. **Handoff hygiene**: If the agent changes shared state, it writes a handoff in
   `docs/handoffs/` before halting. STATUS.md auto-refreshes via pre-commit.
7. **Trust-but-verify on Qwen output**: Orchestrator reads the actual diff before
   marking a delegated task complete. Never trust the worker's "done" message alone.
8. **No public-IP/identity exposure**: Use `<placeholder-name>` syntax + `dmf.example.com`
   per CLAUDE.md "No specific IPs or DNS in public repos."
9. **Branch discipline**: All work on `main` per current convention; loop never creates
   long-lived branches without an open `decisions-open.md` entry approving it.
10. **VERSION SSOT**: Per ADR-0005, `VERSION` file is the source of truth for
    dmf-cms releases; extend to other repos in Phase 0 (Group B).
11. **Issue authorship**: Only the orchestrator (Claude) runs `bin/agentic/issue-open.sh`.
    Qwen workers communicate workarounds, blockers, feature-gaps, bugs, and
    decision-requests via the structured reply-token grammar (Layer 4); orchestrator
    parses, scrub-validates, and opens. Workers never touch the Forgejo API directly.
12. **Issue scrub gate**: Issue body + title pass through `bin/scrub-public-repos.sh`
    and gitleaks before submit. Any hit hard-fails the script; agent rewrites with
    `<placeholder-name>` syntax. No exceptions — same posture as commit-time scrub.
13. **No dmf-env issues**: `dmf-env` is private and never accepts agent-opened
    issues. `scope:dmf-env` is forbidden in the label set.
14. **Autonomy budgets**: ≤1 autonomous decision per tick; ≤10 per `/agentic-run`
    shift (operator-raisable via `--autonomy-budget=N`). On the per-shift cap,
    soft-pause: write a §"Autonomous decisions taken" summary block in the active
    handoff, halt for operator review, resume with `--continue-after-summary`.
    Per-task: 2 consecutive `WORKAROUND:` tokens on the same backlog entry → promote
    to issue + halt that entry. The handoff is the index; `autonomous-decisions.md`
    is the detail.

---

## Verification

End-to-end smoke test before turning the loop on:

1. **Dry preflight**: `bin/agentic/preflight.sh` — exits 0 on clean repo, non-zero
   on injected dirty state.
2. **Dry postflight**: `bin/agentic/postflight.sh` after a no-op tick — exits 0,
   writes one loop-log entry, regenerates STATUS.md.
3. **Hygiene script**: `bin/check-public-repo-hygiene.sh dmf-cms` — currently fails
   (missing LICENSE/NOTICE per audit); should fail cleanly with structured output
   the loop can route into `backlog.yaml`.
4. **Qwen pane handshake**: `agent-bridge` send a trivial echo task to `qwen-left`,
   then `qwen-right`. Verify reply round-trip + diff visibility.
5. **Qwen `/clear` protocol**: send task A (scope `dmf-infra`, kind `rote`) to
   `qwen-right`; immediately send task B (scope `dmf-cms`, kind `taste`) to the
   same pane. Verify orchestrator issued `/clear` between them and logged it in
   `loop-log.md`. Then send task C (same scope/kind as B) and verify no `/clear`
   was issued (context-keep path exercised).
6. **Decision-gate surface**: Seed one fake decision into `decisions-open.md`; run
   `/agentic-tick`; verify loop halts and writes handoff naming the open decision.
7. **Pre-push lockout**: From inside dmf-cms, run `git push github main` — must be
   blocked by `.githooks/pre-push`. Then run `SYNC_TO_GITHUB=1 git push github main`
   — must succeed (or fail on the actual `sync-to-github.sh` gates if invoked
   without the wrapper).
8. **Live tick on rote task**: Take one Phase 0 LICENSE task; run `/agentic-tick`;
   verify Qwen pane creates the file, postflight passes, STATUS refreshes,
   backlog moves entry to `done`.
9. **Halt-on-failure**: Inject a fake secret into a staged file; run a tick;
   verify gitleaks halts the loop, secret is unstaged, handoff is written.
10. **Issue scrub-gate**: Run `bin/agentic/issue-open.sh` with a body containing a
    private IP (e.g. `192.168.x.y` literal) and a hostname. Script must reject and
    name the offending pattern. Rewrite with `<control-node-public-ip>` and
    `<forgejo-host>` placeholders, resubmit — must succeed.
11. **Issue dup-check**: Open issue with title "Catalog schema needs second-level
    indexing"; immediately open second issue with title "catalog schema needs
    second level indexing" — must reject with `#<first-id>` cited.
12. **Worker reply protocol**: From `qwen-right`, send a reply containing
    `WORKAROUND: chrony not restarting cleanly` with all required fields. Orchestrator
    must parse, run scrub, open Forgejo issue, link it from the current backlog entry,
    write a `loop-log.md` line. Confirm via `bin/agentic/issue-list.sh --json`.
13. **Issue → backlog promote**: Run `bin/agentic/issue-promote.sh <id> --worker
    qwen-right`. Backlog gains a new entry with `issue:` field; issue gains
    `pickup:in-progress` label.
14. **Issue close with structured reason**: Run `bin/agentic/issue-close.sh <id>
    --reason=resolved --ref=<commit-sha>`. Issue must close with body comment citing
    the ref; local mirror reconciles on next postflight.
15. **GitHub migration dry-run**: Tag one clean issue `public-safe`; run
    `bin/agentic/issue-migrate-to-github.sh --dry-run`. Output must list it as
    migration-eligible; tag one issue containing a placeholder hostname (NOT a real
    one but matching a known scrub pattern) — must be flagged `stay-private`.

Once steps 1–15 pass, run `/agentic-run` and let it grind. Operator returns to:
- updated `decisions-open.md` for any surfaced gates,
- completed work in component repos,
- "ready-for-operator-push" handoff when terminal state reached.

The operator's only remaining task at that point is to answer any open decisions,
then run `bin/sync-to-github.sh` for each of the 6 public repos when ready.

---

## Out of scope (deferred to a later loop)

- Release Phases 3–6 (commitlint, GitHub Actions CI, branch protection, pre-receive
  hook, ADR-0018 ratification) — these harden the workflow *after* first public push.
- Tier B (Managed Mode) compliance — only Mode A (OSS self-host) blocks v0.1.0.
- The `LLM-Restricted Git Pipeline` Phase 2 (repo-per-environment) — Phase 1
  (protected branches + token scoping) is folded into Release Phase 5 above and
  also deferred.
- Authentik cross-cluster federation (thesis-killer 2) — separate scope, separate loop.
- **Hermes (nousresearch/hermes-agent) adoption** — evaluated and deferred 2026-05-11.
  Hermes is a persistent agentic runtime with multi-platform notifications, container
  isolation, and self-improving skills. Attractive for *post-v0.1.0 steady-state*
  operation (mobile decision-answering, always-on autonomy), but introducing it during
  the 5–7 day release sprint adds new trust surface and diverges from the existing
  `.claude/` investment. Revisit as a separate plan after first GitHub push. Candidate
  uses then: scheduler + Telegram/Discord notification layer (smallest footprint), or
  full Layer 3 replacement (highest ceiling).

---

## Cross-references

- `CLAUDE.md` — boot ritual + repo conventions this plan codifies
- `docs/plans/dmf-platform-move-1-task-2026-05-04.md` — source of Group C (Move 1 Pieces 1–9, D1–D4)
- `docs/plans/DMF Release and Contribution Model Implementation Plan 2026-05-11.md` — source of Group B (Phases 0–2)
- `docs/plans/DMF Pre-Release Compliance Readiness Plan 2026-05-11.md` — source of Group D (Tier A.1–A.9)
- `docs/plans/LLM-Restricted Git Pipeline — Dev-Testing-Production Isolation Plan 2026-05-09.md` — adjacent push-discipline design
- `docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07.md` — the orphan-rebase + refspec gate this plan must not violate
- `docs/decisions/INDEX.md` — ADR-0005, ADR-0011, ADR-0018, ADR-0020 are load-bearing
- `bin/sync-to-github.sh` — the operator-only push gate this plan strengthens but never bypasses
- `bin/scrub-public-repos.sh`, `bin/generate-status.sh`, `.githooks/pre-commit` — existing automation reused as-is
