# DMF Working Model — GitHub + documentation rules (canonical)

This is the **single canonical statement** of how work is tracked, decided,
and documented across all DMF repos. Agent files (`CLAUDE.md` / `AGENTS.md` /
`QWEN.md`) in every repo carry a generated pointer block; the Claude Code
SessionStart hook injects the digest below at session start. If anything else
contradicts this file, this file wins — fix the other artifact.

Enforced by: `bin/check-working-model-sync.sh` (block copies can't drift),
`bin/check-docs.sh` (plan frontmatter), the PR-gate CI (issue linkage), and
the backlog-hygiene detector. Plan:
[`docs/plans/DMF Working-Model Enforcement Plan 2026-06-11.md`](plans/DMF%20Working-Model%20Enforcement%20Plan%202026-06-11.md).

<!-- WM-DIGEST-START -->
**DMF working model digest** (canonical: umbrella `docs/WORKING-MODEL.md`):

1. **Work starts at an issue** in the canonical backlog
   <https://github.com/dmfdeploy/dmfdeploy/issues> — claim one or open one
   (milestone + `component:*` + `workstream:*` labels; it lands on org
   Project #1). Non-trivial work also gets a plan doc in umbrella
   `docs/plans/` with `tracking_issue` frontmatter.
2. **The completing PR closes the issue and flips the plan's frontmatter in
   the same change.** From a *component* repo, reference umbrella issues
   **fully qualified** — `Closes dmfdeploy/dmfdeploy#N` — a bare `#N` points
   at that repo's own issue and silently misses.
3. **Never invent a local backlog** (TODO files, ad-hoc trackers, stale
   `docs/agentic/` queues). Issues are canonical for *liveness*, plan
   frontmatter for *design state*, ADRs for *decisions* (propose via a
   Discussions RFC first), STATUS.md for *cross-repo now*.
<!-- WM-DIGEST-END -->

## 1. Source-of-truth map

| Question | Canonical home |
|---|---|
| Is anyone working on X? Is it scheduled? | [GitHub Issues](https://github.com/dmfdeploy/dmfdeploy/issues) + [org Project #1](https://github.com/orgs/dmfdeploy/projects/1) |
| What's the design/decision state of a plan? | The plan doc's frontmatter in umbrella `docs/plans/` |
| What architectural rules bind me? | ADRs in umbrella `docs/decisions/` ([INDEX](decisions/INDEX.md)) |
| What's happening across repos right now? | umbrella [STATUS.md](../STATUS.md) (regenerate via `bin/generate-status.sh`) |
| Where do questions/proposals go? | [Discussions](https://github.com/dmfdeploy/dmfdeploy/discussions) |

**Split-brain precedence:** on disagreement, the issue wins for liveness and
the frontmatter must be flipped; frontmatter wins for design content.

## 2. Issues

- **The umbrella repo (`dmfdeploy/dmfdeploy`) hosts the canonical backlog** —
  including work whose code lives in a component repo (that's what the
  `component:*` label is for). TODOS.md was retired into Issues 2026-06-10.
- Every scheduled issue carries: a **milestone**, one **`component:*`** label
  (`dmf-cms` … `dmf-promsd`, `umbrella`, `cross-repo`) and one
  **`workstream:*`** label (`release`, `compliance`, `monitoring`,
  `infra-debt`, `scaffold`, `hygiene`, `ADR`, `catalog`, `identity-secrets`,
  `hardening`, `entrance`), and sits on org Project #1.
- **Milestones:** `v0.1-polish` — items gating the v0.1 claim; `v0.2` —
  post-v0.1 scope. New milestones need an operator decision.
- **Component-repo issues are drive-by intake only** (bug reports from
  outsiders landing where the code is). Triage within ~7 days: either close,
  or open/link the canonical umbrella issue and continue there. Don't grow a
  second backlog.

## 3. Project board (org Project #1 "DMF Platform")

- Fields: **Status** (Todo / In Progress / Done), **Component**, **Workstream**
  (single-select, mirroring the label taxonomy). Set Component + Workstream
  when adding an item.
- Tooling gotcha: `gh project` subcommands may 401 — use raw `gh api graphql`
  (project node id `PVT_kwDOENb9uM4BaPY-`).

## 4. Discussions

- **Q&A** — questions; **Ideas** — early proposals not yet RFC-shaped;
  **Announcements** — one thread per merged ADR (back-catalog covered by the
  pinned "Decision record" index thread, #27); **RFC** — the pre-ADR pipeline.
- **RFC → ADR:** substantial cross-cutting decisions start as an RFC thread →
  converge → ADR PR (copy `docs/decisions/0000-template.md`, next free number,
  reciprocal supersession links) → announcement thread on merge. Small
  single-repo decisions stay in their issue.

## 5. Plans + documentation rules

- New work: **issue first**, then (if non-trivial) an on-disk spec in umbrella
  `docs/plans/` named `DMF <Topic> Plan YYYY-MM-DD.md`, frontmatter:
  `status:` (`active` | `draft` | `executed` | `superseded` | `historical`),
  `date:`, `tracking_issue:` (issue URL), `executed:` / `superseded_by:` when
  applicable. `bin/check-docs.sh` (pre-commit + CI) rejects unparseable
  frontmatter and checks INDEX consistency.
- The PR that completes a plan **closes the issue and flips the frontmatter in
  the same change**.
- Doc filenames are preserved verbatim (docs cross-reference by display name);
  don't rename without sweeping callers. Doc edits go in the umbrella; code
  edits in component repos.
- Public-safety rules apply to *all* artifacts including issues/PRs/CI logs:
  placeholder syntax for IPs/DNS/identity (`<control-node-public-ip>`,
  `dmf.example.com`, `<handle>`); secrets never leave OpenBao.

## 6. PRs

- GitHub PRs against `main` only; Conventional Commits; DCO sign-off;
  rebase-merge; CODEOWNERS review; CI green (`guard.yml` + `ci.yml` + DCO).
- **Reference the tracking issue in the PR body** — qualified
  (`Closes dmfdeploy/dmfdeploy#N`) from component repos, `Closes #N` in the
  umbrella. Trivial changes may carry the `no-issue` label instead.
- **Cross-repo batches:** one umbrella issue for the batch; every per-repo PR
  references it qualified.

## 7. How this is enforced (mechanics map)

| Mechanism | Scope | Mode |
|---|---|---|
| This doc + digest | all | canonical source |
| Working-model block in CLAUDE/AGENTS/QWEN (generated from `docs/templates/working-model-block.md`) | all 9 repos | context auto-load (codex/qwen forcing mechanism) |
| `bin/check-working-model-sync.sh` | umbrella CI/pre-commit; component CI `--strict` | fails on block drift |
| SessionStart hook → `bin/working-model-digest.sh` | Claude Code, per repo (trust-gated) | injects digest at session start |
| PR-gate issue-linkage job (`guard.yml`) | all 9 repos | fails unqualified/missing reference |
| `bin/check-docs.sh` | umbrella | fails bad frontmatter; W2 → fail after backfill |
| `bin/check-backlog-hygiene.sh` (scheduled) | umbrella + component intake | weekly drift report |
