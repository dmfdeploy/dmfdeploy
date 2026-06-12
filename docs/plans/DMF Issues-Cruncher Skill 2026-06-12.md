---
status: active
date: 2026-06-12
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/46
---
# DMF Issues-Cruncher Skill 2026-06-12

> **Goal:** capture the repeatable multi-agent loop for taking a backlog issue
> end-to-end (scope → branch → implement → cross-check → verify → PR → land) as a
> reusable **`issues-cruncher`** skill, so a fresh trio can start on the backlog
> cold. **Flagship instance** of the canonical cross-agent skills effort
> ([umbrella issue #46](https://github.com/dmfdeploy/dmfdeploy/issues/46)).

## Origin

Derived from the session that landed #44, #20, and #19 with a trio: a **Claude
orchestrator** (scope + verify + git/PR), **qwen implementer** (precise lifting),
**codex adversary** (conditional cross-check), with an external reviewer as the real
correctness gate. The #19 rounds (a surviving subprocess, then surviving
*descendants*, caught by the reviewer) motivated the verification discipline baked
in here.

## What shipped (v1)

`skills/issues-cruncher/` — a **thin `SKILL.md`** (8-phase engine + 7 hard gates +
a reference router) over conditionally-loaded `references/`:

- `repo-profile.md` — detect→confirm→cache conventions with **evidence +
  confidence + expiry**; unknown ⇒ block/ask, never default; *absence ≠ policy*;
  **probe** close-keyword behavior.
- `github-adapter.md` — CI + tracker seams: `gh run view` = truth (not lagging
  aggregations); required checks from branch protection, not YAML; admin-bypass /
  auto-merge guard.
- `dmf-profile.md` — this environment's confirmed facts (umbrella backlog, sibling
  repos, qualified refs, DCO/no-co-author, cross-repo close gap #47, shared-checkout
  hazard, trio-suitable issue filter).
- `tiers.md` — **risk-signal** tiers as stop-the-line checkpoint gates (with
  concrete triggers + negative examples); escalate-only mid-run.
- `guardrails.md` — the hard-gate checklist (lease, claim, scope-freeze,
  verify-on-disk, discrimination + **independent regression design**,
  fresh-checkout verify, evidence bundle, re-verify each round, hung-agent policy,
  human gates, redaction).
- `harness-ops.md` — agent-bridge operation + hung-agent policy.
- role primers, each authored in its own lane: `orchestrator-primer.md` (Claude),
  `implementer-primer.md` (qwen), `adversary-primer.md` (codex).

## Design decisions

- **Reuse-first.** Composes existing `.qwen/skills/` fragments
  (`orchestrated-lifter-workflow`, `fix-round-verification-protocol`,
  `clean-tree-verification-protocol`, `multi-repo-pr-submission`,
  `work-order-commit-review`, `adversarial-infra-crosscheck`) by reference, not
  duplication.
- **DMF-concrete v1 with clean seams** — engine/adapter/profile separation so other
  repos/trackers slot in later; not a fully generic framework yet.
- **codex design cross-check incorporated** — evidence/confidence/expiry profile
  model; independent regression design; stop-the-line tier gates; the expanded
  guardrail set; layered packaging (thin SKILL.md + conditional references).

## Deferred (follow-ups, not in this slice)

- **Dogfood + negative fixtures** — run the loop on a fresh issue end-to-end; build
  the conflicting-docs / cross-repo-close / missing-branch-protection /
  non-discriminating-test fixtures. (The real validation.)
- **Canonical sync mechanism + CI drift check** (`bin/sync-skills.sh`) — #46's core
  deliverable; v1 ships the skill in the canonical location, role copies manual.
- Generic CI/tracker adapters beyond GitHub + DMF.

## Verification (when dogfooded)

1. End-to-end crunch of one fresh single-repo, offline-verifiable issue → PR with
   the evidence bundle, all hard gates honored.
2. Negative fixtures behave: conflicting docs → engine **asks**; cross-repo close →
   no auto-close assumed; missing/403 branch-protection → **UNKNOWN** gate; a
   passing-but-non-discriminating test → caught by the independent-regression gate.
3. Profile cache: a changed workflow SHA → **revalidate** before PR.
