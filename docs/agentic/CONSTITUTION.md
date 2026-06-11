# DMF Agentic Harness — Constitution

> **⚠️ Status: HISTORICAL (mothballed 2026-06-04).** The agentic harness ran its
> K1–K4 scaffolding + K5 ticks on 2026-05-12 (through tick 16) and has been
> unused since; real orchestration now flows through dmf-init + manual codex/qwen
> dispatch. The live backlog is [`TODOS.md`](../../TODOS.md), **not**
> `backlog.yaml`. This file is preserved for provenance; it no longer governs any
> running loop.

> **Authority**: This file is the non-negotiable rule set every agent (Claude
> orchestrator, qwen-left, qwen-right, future agents) must obey while operating
> under the agentic harness. Read-only during loop operation. Only the operator
> amends.
>
> **Source**: Codified from the canonical
> [`DMF Agentic Harness Plan`](../plans/DMF%20Agentic%20Harness%20Plan%202026-05-11.md)
> §Constitution highlights (rules 1–14) + the umbrella
> [`CLAUDE.md`](../../CLAUDE.md) boot ritual.
>
> **Self-hash**: Agents compute and remember the SHA-256 of this file at the
> start of every `/agentic-run`. If the hash changes mid-loop the loop halts
> (canonical plan §Halt conditions rule 5).

---

## Rule 1 — Push gate

**Never** run `git push` to a `github` remote. Use `bin/sync-to-github.sh`,
which is operator-only. Direct pushes are blocked by the per-repo
`.githooks/pre-push` hook unless `SYNC_TO_GITHUB=1` is set by the wrapper.

**Why**: The 6 gates inside `sync-to-github.sh` (whitelist, scrub, identity,
gitleaks ×2, github remote exists) and the orphan-rebase posture from
`DMF Public Publish Readiness Handoff 2026-05-07.md` together prevent leaks
of pre-publish history. Bypassing them risks publishing internal state.

**Refs**: `bin/sync-to-github.sh`,
[`docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07.md`](../handoffs/DMF%20Public%20Publish%20Readiness%20Handoff%202026-05-07.md).

---

## Rule 2 — Secret gate

`gitleaks` and `bin/scrub-public-repos.sh` must pass before any commit. The
agent **fixes the leak or halts** — never disables the rule, never edits the
allowlist mid-loop.

**Why**: Pre-commit gitleaks + scrub already enforce this on every umbrella
commit; the harness must operate inside that envelope. Disabling the rule
silently to land a commit defeats the whole posture.

**Refs**: `.githooks/pre-commit`, `bin/scrub-public-repos.sh`, `.gitleaks.toml`.

---

## Rule 3 — Sub-repo dirty rule

If a component repo (`dmf-cms`, `dmf-infra`, `dmf-env`, `dmf-central`,
`dmf-media`, `dmf-runbooks`) has uncommitted changes **not made by the current
agent in the current run**, halt and surface to operator. Do not modify a
dirty sub-repo.

**Why**: Dirty state means another session/agent has work in flight. Touching
it risks lost work and silent merge of unrelated intent. The boot ritual makes
this explicit (CLAUDE.md §Boot ritual step 5).

**Refs**: [`CLAUDE.md`](../../CLAUDE.md) §"Boot ritual".

---

## Rule 4 — Skill-guarded operations

The following operations require reading **§0 of the relevant skill** before
any tool call inside that scope:

- Cluster operations → `.claude/skills/dmf-cluster-access/SKILL.md`
- OpenBao operations → `.claude/skills/dmf-openbao-unseal/SKILL.md`
- `dmf-cms` releases → `.claude/skills/dmf-cms-build-and-release/SKILL.md`

**Why**: These skills encode mandatory pre-flight discipline (auth context
verification, Shamir-quorum procedure, VERSION SSOT sync) that has prevented
real incidents. The §0 read primes the agent's context with the safety
preamble before any mutation.

**Refs**: `.claude/skills/`.

---

## Rule 5 — Decision surface (canonical halt rubric)

A choice is **ADR-worthy** (halt + surface to `decisions-open.md`) when:

- **Worker signal**: a Qwen reply token of `DECISION-NEEDED:` or
  `BLOCKED: needs-decision`; **OR**
- **Orchestrator self-classification** (any of):
  - (a) the choice changes a public surface or contract (Secret name, API
    path, config-file location, label key, exported variable, public README
    behavior);
  - (b) the choice touches more than one repo;
  - (c) the choice contradicts or supersedes an existing ADR;
  - (d) the choice removes an option already considered in a plan doc;
  - (e) the choice crosses a skill-guarded boundary (Rule 4).

If none of the above hold, the orchestrator **resolves locally and appends**
a single line to `autonomous-decisions.md`. Format:

```
<ISO-timestamp> | <task-id> | <one-line decision> | <rationale ≤140ch> | <commit-sha or file-path>
```

**Why**: Most tick-time choices are local and don't need the operator. The
rubric is conservative on purpose — false-positive halts cost one operator
nudge; false-negative proceeds cost an ADR-worthy decision being made silently.

**Refs**: [`DMF Agentic Harness Plan`](../plans/DMF%20Agentic%20Harness%20Plan%202026-05-11.md)
§Layer 3 "Autonomous decision routing".

---

## Rule 6 — Handoff hygiene

If the agent changes shared state (cross-repo decisions, in-flight work
another agent might trip over), **write a handoff** in `docs/handoffs/`
before halting or pausing. The umbrella's pre-commit hook auto-refreshes
`STATUS.md`; the handoff is the narrative companion that won't be regenerated.

**Why**: Every prior session has left a handoff; absence is silent context
loss for the next agent. Handoffs are how cross-session continuity actually
works in this workspace.

**Refs**: [`docs/handoffs/`](../handoffs/), `bin/generate-status.sh`.

---

## Rule 7 — Trust-but-verify on worker output

The orchestrator **reads the actual diff** before marking a delegated task
complete. Never trust the worker's `DONE:` message alone. `git diff`,
`git status`, `kubectl diff`, or the appropriate inspection tool runs after
every Qwen pane handoff and before the postflight gates.

**Why**: Workers can claim success and have produced different work than
asked. Verification catches intent-vs-implementation drift at the smallest
possible unit (one task) before it compounds.

**Refs**: [`DMF Agentic Harness Plan`](../plans/DMF%20Agentic%20Harness%20Plan%202026-05-11.md)
§Layer 3 "Trust-but-verify".

---

## Rule 8 — No public-IP / identity exposure

In any artifact destined for a public repo (everything except `dmf-env`):

- Real IPs → use placeholder syntax: `<control-node-public-ip>`,
  `<node-public-ip>`, `<lb-public-ip>`, `<lan-ip>`, `<wg-mesh-ip>`,
  `<headscale-host>`, etc.
- Real DNS → use the fictitious example domain `dmf.example.com`.
- Operator usernames, device hostnames, real B2 keyIDs, real cluster names
  outside the project's published set → never written.

**Why**: Pre-commit gitleaks + `scrub-public-repos.sh` enforce this
mechanically. The constitution restates it so the agent produces
placeholder-safe content **first time** rather than getting bounced by the
gate.

**Refs**: [`CLAUDE.md`](../../CLAUDE.md) §"Conventions" (last bullet).

---

## Rule 9 — Branch discipline

All work happens on `main` per current convention. The loop **never creates
long-lived branches** without an open `decisions-open.md` entry approving it.

**Why**: The project is in experiment phase (strategic review 2026-04-30);
branching adds coordination overhead without commensurate gain at this stage.
Returning to feature branches is a future decision worth its own ADR.

**Refs**: [`CLAUDE.md`](../../CLAUDE.md) §"Git topology",
[`docs/reviews/dmf-platform-strategic-review-2026-04-30.md`](../reviews/dmf-platform-strategic-review-2026-04-30.md).

---

## Rule 10 — VERSION as SSOT

Per ADR-0005, the `VERSION` file is the single source of truth for `dmf-cms`
releases. The harness extends this convention to all public repos in
Group B Phase 0 (LICENSE/NOTICE/VERSION rollout). Any agent that changes
release-tagged artifacts in a repo with a `VERSION` file must update the
`VERSION` file in the same commit.

**Why**: `dmf-cms`'s build pipeline (`sync-version.sh`, `build-image.sh`,
`release.sh`) refuses to operate if VERSION drifts from chart / image / docs.
The bundled discipline prevents whole classes of release-time confusion.

**Refs**: [`docs/decisions/0005-`](../decisions/) (VERSION SSOT for dmf-cms),
`dmf-cms/scripts/sync-version.sh`.

---

## Rule 11 — Issue authorship

Only the **orchestrator** (Claude) runs `bin/agentic/issue-open.sh`. Qwen
workers communicate workarounds, blockers, feature-gaps, bugs, and
decision-requests via the structured reply-token grammar (see
[`ISSUE-TEMPLATES.md`](ISSUE-TEMPLATES.md) §"Worker reply tokens"). The
orchestrator parses, scrub-validates, and opens.

**Why**: Single audit point. Workers never touch the Forgejo API directly →
authorship and scrub responsibility live in one place where they can be
reasoned about.

**Refs**: [`ISSUE-TEMPLATES.md`](ISSUE-TEMPLATES.md),
[`DMF Agentic Harness Plan`](../plans/DMF%20Agentic%20Harness%20Plan%202026-05-11.md)
§Layer 4 "Authorship rule".

---

## Rule 12 — Issue scrub gate

Issue body + title pass through `bin/scrub-public-repos.sh` and `gitleaks`
**before submit**. Any hit hard-fails the script; the agent rewrites with
placeholder syntax (Rule 8) and resubmits. No exceptions — same posture as
commit-time scrub.

**Why**: Forgejo issues are private today but migrate to public GitHub at
v0.1.0 (`issue-migrate-to-github.sh`). Maintaining commit-equivalent hygiene
from day one means the migration is mechanical, not a forensic sweep.

**Refs**: [`DMF Agentic Harness Plan`](../plans/DMF%20Agentic%20Harness%20Plan%202026-05-11.md)
§Layer 4 "Drift firebreaks specific to issues".

---

## Rule 13 — No `dmf-env` issues

`dmf-env` is private; agent-opened issues **never** carry `scope:dmf-env`.
The label is forbidden in the validation set.

**Why**: `dmf-env` is never public, never has GitHub issues; tracking work
there happens via handoffs and direct commits, not the issue substrate.
Allowing the label would create issues that cannot migrate at publish time.

**Refs**: [`CLAUDE.md`](../../CLAUDE.md) §"Component repos" (dmf-env is private).

---

## Rule 14 — Autonomy budgets

Three tiers bound autonomous activity per `/agentic-run`:

| Budget | Limit | Behavior on hit |
|---|---|---|
| Per-task | 2 consecutive `WORKAROUND:` tokens on the same backlog entry | Promote to Forgejo issue + halt that entry |
| Per-tick | ≤ 1 autonomous decision per tick | Bounds context creep + keeps `loop-log.md` granular |
| Per-shift | ≤ 10 autonomous decisions per `/agentic-run` invocation (operator-raisable via `--autonomy-budget=N`) | **Soft pause**: write §"Autonomous decisions taken" summary block in active handoff, halt for operator review. Resume with `--continue-after-summary` — no `/agentic-run` restart needed. |

**Why**: Without budgets, "bounded" devolves into "bounded only by token
limit." The per-shift cap prevents the failure mode where operator returns to
a 200-line decision log and review takes as long as the work did.

**Refs**: [`DMF Agentic Harness Plan`](../plans/DMF%20Agentic%20Harness%20Plan%202026-05-11.md)
§Layer 3 "Budgets".

---

## Amendment procedure

This file is constitution-class — agents treat it as read-only. The operator
amends by:

1. Editing this file directly on a working tree.
2. Updating the "Source" frontmatter line if the canonical plan section was
   the source of the change.
3. Committing on the umbrella `main`. The next `/agentic-run` will detect
   the hash change and require a fresh start (cannot resume mid-loop across
   a constitution change).

Rule additions, removals, and material changes warrant an ADR; trivial
clarifications (typos, link fixes, formatting) do not.
