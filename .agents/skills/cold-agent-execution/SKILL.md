---
name: cold-agent-execution
description: Execute orchestrator-dispatched work (spec slices, work packages, or a large multi-file feature) as the implementer in an agent-bridge workflow — verify before reporting, DONE/BLOCKED protocol, commit policy per mode
type: durable-pattern
scope: agent-workflow
owner: operator
review_by: '2027-01-14'
source: auto-skill
extracted_at: '2026-07-14T00:00:00Z'
source_ref: https://github.com/dmfdeploy/dmfdeploy/issues/225
merged_from:
  - cold-agent-wp-execution
  - cold-agent-multi-file-implementation
  - orchestrated-lifter-workflow
---

# Cold-Agent Execution

You are the IMPLEMENTER in an agent-bridge orchestrated workflow: another
agent writes the spec and verifies; you execute precisely and report. Three
modes share one discipline and differ only in scope and **commit policy** —
identify your mode from the dispatch before touching anything.

| Mode | Shape of the work | Commit policy |
|---|---|---|
| **Lifter** | precise edits from a spec file (e.g. `/tmp/slice-N-spec.md`) | **NO commits** — orchestrator reviews diffs |
| **WP executor** | numbered work packages across sibling repos | commit locally per WP, **never push** |
| **Feature implementer** | one large multi-file feature (backend+frontend+tests) in one repo | commit locally; fix rounds **amend** |

## Shared discipline (all modes)

1. **Boot:** verify branch (`git rev-parse --abbrev-ref HEAD`, usually `main`)
   and clean state in every repo you will touch. **STOP on unexpected dirty
   state** — it is another agent's WIP; ask, don't clobber.
2. **Read the spec in full before any edit.** Note every task, its verify
   command, the branch/commit instructions, and what is explicitly out of
   bounds (security asserts, ADRs, cloud-lane behavior).
3. **Sibling repos need absolute paths** — Glob/search may not see outside
   the working dir; Read/edit directly.
4. **Do ONLY what the spec says.** No adjacent fixes, no refactors; flag
   anything you notice in the DONE reply instead. When the spec says "mirror
   entry X", copy X's structure verbatim (indentation, key order,
   var-reference style).
5. **Verify BEFORE reporting** — run the spec's verify commands (`bash -n`,
   `--syntax-check`, YAML parse, `helm template | grep`, `npm run build`,
   `pytest`); if a tool is missing, use an equivalent (ruby/node YAML parse,
   structural grep). Diagnose failures before DONE, never after.
6. **Reply via agent-bridge, always** (the orchestrator may not read pane
   output):
   - `agent-bridge send <agent> -- "DONE <id> <hashes/summary>; <concerns or 'no concerns'>"`
   - `agent-bridge send <agent> -- "BLOCKED <id> <specific reason>"` — then STOP.
   - **No backticks in the message body** (bash substitutes them inside
     double quotes); single quotes or plain text.
   - Reply per unit of work, not once at the end — the orchestrator verifies
     incrementally.
7. **Commit hygiene** (modes that commit): conventional-commit message +
   DCO sign-off (`git commit -s`). **NO Co-Authored-By / agent trailers** —
   operator policy strips them everywhere.

## Mode notes

### Lifter
- Typical edits: Helm values/templates, AWX job-template dicts, catalog
  YAML, playbook copies, seed vars. Whitespace-sensitive — match exactly.
- Include verification evidence (exit codes, grep matches, rendered
  template lines) in the DONE reply.

### WP executor
- **WP0 = onboarding, always first:** umbrella boot ritual, read plan spec +
  relevant ADRs, audit every target repo (branch + clean), note hard
  constraints (sandbox-only, no-push, untouchable files).
- One WP = one logical change = one commit (cross-repo WPs: one commit per
  repo, report all hashes).
- When a spec references a commit ("cross-check e514bd9"): `git show <hash>
  --stat` + the file diffs; align with it, don't re-implement; if current
  state makes the intent unclear, BLOCKED with what you found.
- Multi-site value replacement in big scripts: `grep -n` all sites first;
  add one derivation function (explicit override → default → warned
  fallback); replace each site with the call; wire EVERY input path
  (interactive prompt, non-interactive/answers-file load, validation) and
  update user-facing copy to match.

### Feature implementer
- **Layer order:** models/settings → routes/endpoints → business logic →
  frontend → tests → build (`npm run build`, `pip install .` if packaging)
  → verify (`ruff`, `pytest`) iteratively.
- **Mid-flight review:** don't restart — fold P0 (concurrency, path/file
  safety) then P1 (TLS, trust) then P2 into the live todo list; commit
  together.
- **Fix rounds:** the orchestrator re-verifies DONE claims. Fix ALL ranked
  defects, `git commit --amend` (no separate fix commit), and paste actual
  grep/build output for every claim in the second DONE — assertions without
  evidence get bounced (see `fix-round-verification-protocol`).
- Ripple rules: model/signature changes → update every constructor/caller
  (`grep -n` the symbol across tests first); removed UI component/prop →
  update definition AND all call sites; build the frontend after each batch.
- Known traps: `Settings(tls_enabled=True)` sets Secure cookies that HTTP
  test transports drop (tests need `tls_enabled=False`); bulk `sed` on JSX
  leaves dangling `||`/fragment mismatches — targeted edits only; ruff
  F401/F821 catch stale imports after symbol removals.

## Hard-constraint table (read from the dispatch, typical set)

| Constraint | Why |
|---|---|
| Work on `main` (or named branch) only | operator merges as-is |
| No push | operator verifies live first |
| Sandbox lane only | cloud-lane behavior is out of bounds |
| Named files/asserts untouchable | security-critical |
| No ADR changes | decision frame is fixed |
