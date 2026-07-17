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
2. **The completing PR auto-closes its issue; flipping the plan's frontmatter
   stays a manual step in that PR.** From a *component* repo, reference umbrella
   issues **fully qualified** — `Closes dmfdeploy/dmfdeploy#N` — a bare `#N`
   points at that repo's own issue and silently misses. The daily issue-close
   reconciler closes from that qualified ref (cross-repo included); manual close
   is a fallback (§6).
3. **Never invent a local backlog** (TODO files, ad-hoc trackers, stale
   `docs/agentic/` queues). Issues are canonical for *liveness*, plan
   frontmatter for *design state*, ADRs for *decisions* (propose via a
   Discussions RFC first), STATUS.md for committed operator notes, and
   STATUS.local.md for the generated live repo snapshot.
<!-- WM-DIGEST-END -->

## 1. Source-of-truth map

| Question | Canonical home |
|---|---|
| Is anyone working on X? Is it scheduled? | [GitHub Issues](https://github.com/dmfdeploy/dmfdeploy/issues) + [org Project #1](https://github.com/orgs/dmfdeploy/projects/1) |
| What's the design/decision state of a plan? | The plan doc's frontmatter in umbrella `docs/plans/` |
| What architectural rules bind me? | ADRs in umbrella `docs/decisions/` ([INDEX](decisions/INDEX.md)) |
| What's happening across repos right now? | `STATUS.local.md` (generated locally via `bin/generate-status.sh`; gitignored). Committed [STATUS.md](../STATUS.md) keeps hand-edited operator notes only. |
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
  `hardening`, `entrance`). Labels are the single source of truth for
  component/workstream classification; board membership is **not** a filing
  requirement (see §3).
- **Milestones:** `v0.1-polish` — items gating the v0.1 claim; `v0.2` —
  post-v0.1 scope. New milestones need an operator decision.
- **Component-repo issues are drive-by intake only** (bug reports from
  outsiders landing where the code is). Triage within ~7 days: either close,
  or open/link the canonical umbrella issue and continue there. Don't grow a
  second backlog.

## 3. Project board (org Project #1 "DMF Platform")

- The board is a **human curation surface** — people add the issues that carry
  significance (something everyone's been asking to add or resolve) and track
  them through **Status** (Todo / In Progress / Done). It is **not** an
  automation target: there is no requirement that every issue land on the board,
  and nothing reconciles it. Labels remain canonical; the board is a view people
  choose to maintain.
- The `Component` / `Workstream` single-select fields merely mirror the
  `component:*` / `workstream:*` labels and are an optional convenience. Because
  the labels are canonical and the board is human-curated, any field↔label drift
  is cosmetic — these custom fields may be dropped in favour of the board's
  native **Labels** field if they stop earning their keep (operator's call).
- Tooling gotcha: `gh project` subcommands may 401 — use raw `gh api graphql`
  (project node id `PVT_kwDOENb9uM4BaPY-`).

## 4. Discussions

- **Q&A** — questions; **Ideas** — early proposals *and* RFC threads (the
  pre-ADR pipeline; no separate RFC category exists — see #246);
  **Announcements** — one thread per merged ADR (back-catalog covered by the
  pinned "Decision record" index thread, #27).
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
- The PR that completes a plan **auto-closes the issue** (the reconciler honors
  its qualified `Closes` reference — see §6) **and must flip the plan frontmatter
  in the same change**. The close is automated; the frontmatter flip is the
  manual half and is never done for you.
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
- **Issue close is automated — including cross-repo.** GitHub's native
  auto-close never fires here (cross-repo closing references never fire, and our
  bot-actor rebase auto-merge suppresses even same-repo keyword closes), so the
  `bin/close-completed-issues.sh` reconciler — run by the `issue-close-reconciler`
  workflow daily at 06:00 UTC (plus on-demand `workflow_dispatch`) — closes
  umbrella issues from exactly the closing references GitHub itself parsed
  (`closedByPullRequestsReferences`, cross-repo included). So **automated close
  is the norm; manual close is a fallback** — for when you need it closed before
  the next daily run, the reconciler missed it, or the reference wasn't qualified
  (so GitHub never parsed it as a closing ref). The reconciler never touches plan
  frontmatter: **flipping the frontmatter stays a manual duty in the completing
  PR.**
- **Approval = landing.** Every PR is armed with GitHub-native **rebase
  auto-merge** at open (`automerge.yml`); it merges the moment CODEOWNERS
  approval + all required status checks are satisfied, and the branch is
  auto-deleted. There is no post-approval hold window — use *Comment* /
  *Request changes* for non-landing feedback, or add the **`hold`** label to
  disarm auto-merge. Required-check lists live in each repo's branch ruleset;
  when CI job names change, update the ruleset in the same change.

### Adversarial review gates (codex)

Every non-trivial change is adversarially reviewed by an independent agent
(codex) **before its PR opens** (PRs are final at open — auto-merge is armed).
Two sanctioned forms:

- **Interactive bridge** (agent-bridge tmux pane): for design and
  implementation reviews that take multiple rounds — findings get fixed and
  re-verified in delta rounds, and the reviewer may need approvals for its
  own scratch reproductions. Reset the reviewer's session between rounds.
- **One-shot `codex exec --sandbox read-only`** (R6,
  [#229](https://github.com/dmfdeploy/dmfdeploy/issues/229)): for **routine**
  gates — bounded, single-verdict reviews (a docs change, a mechanical sweep,
  a small fix against a clear acceptance condition). Requirements, all
  mandatory:
  1. the sandbox is **read-only** (the reviewer proves, never mutates);
  2. the prompt names an explicit acceptance condition and requires a final
     standalone `CODEX GATE: PASS` / `CODEX GATE: FAIL <reason>` line — and
     every acceptance item must be **verifiable under the read-only sandbox**
     (diff inspection, grep, read-only git); checks that need to *execute*
     tooling belong to CI, and the prompt cites their status instead of
     asking the reviewer to run them (learned on this rule's own first use);
  3. **reproducible capture**: the exact prompt, the repo SHA under review
     (`git rev-parse HEAD`), the full command line, and the complete output
     are retained together in the operator's review records (operator-local,
     like all session records — public artifacts reference the verdict, not
     the store).

  A FAIL from a one-shot gate escalates to the interactive form for the fix
  rounds; one-shot gates are never used to re-review their own findings.

## 7. How this is enforced (mechanics map)

| Mechanism | Scope | Mode |
|---|---|---|
| This doc + digest | all | canonical source |
| Working-model block in CLAUDE/AGENTS/QWEN (generated from `docs/templates/working-model-block.md`) | all 9 repos | context auto-load (codex/qwen forcing mechanism) |
| `bin/check-working-model-sync.sh` | umbrella CI/pre-commit; component CI `--strict` | fails on block drift |
| SessionStart hook → `bin/working-model-digest.sh` | Claude Code, per repo (trust-gated) | injects digest at session start |
| PR-gate issue-linkage job (`guard.yml`) | all 9 repos | fails unqualified/missing reference |
| `bin/check-docs.sh` | umbrella | fails bad frontmatter; W2 → fail after backfill |
| Branch ruleset: approval + CODEOWNERS + required status checks + rebase-only, stale approvals dismissed on push | all 9 repos | merge is impossible otherwise |
| `automerge.yml` + `required_status_checks` ruleset | all 9 repos | approval-driven rebase auto-merge + branch auto-delete (`hold` label disarms) |
| `bin/close-completed-issues.sh` via `issue-close-reconciler.yml` (daily 06:00 UTC + `workflow_dispatch`) | umbrella issues with a merged completing PR | auto-closes from GitHub-parsed closing refs (`closedByPullRequestsReferences`, cross-repo included); manual close is fallback; `--self-test` gated in CI |
| `bin/check-backlog-hygiene.sh` (scheduled) | umbrella + component intake | weekly drift report |
| Codex adversarial gate (§6: interactive bridge or one-shot `codex exec --sandbox read-only`) | non-trivial changes, pre-PR | operator discipline; prompt/SHA/command/output retained in operator-local review records |

## 8. New-repo bootstrap checklist

The enforcement net — commit/push hooks (`bin/install-hooks.sh`), branch
rulesets, required status checks, `bin/scrub-public-repos.sh` (gitleaks +
secret scrub), `bin/check-working-model-sync.sh` (block sync),
`bin/check-docs.sh` (frontmatter), CI gates — is **per-repo** and **not
inherited** from the org `.github` defaults. A new repo starts outside the
model, so spinning one up means running this checklist. The `.github` defaults
(fallback CODE_OF_CONDUCT, SUPPORT, GOVERNANCE, profile README) only soften
the gap; they do not enforce.

1. **Agent files** — add `CLAUDE.md`, `AGENTS.md`, `QWEN.md` with the
   working-model block from `docs/templates/working-model-block.md` (umbrella).
   Register the repo in `bin/check-working-model-sync.sh`'s sibling scan so the
   block stays synced across copies.
2. **CODEOWNERS** — `* @dmfdeploy/maintainers` (per-repo overrides for
   repo-specific paths).
3. **LICENSE** — Apache-2.0.
4. **SECURITY.md** — private vulnerability reporting via GitHub Advisories
   (Security → Report a vulnerability); see umbrella `SECURITY.md` for the
   template.
5. **Pre-commit hooks** — run `bin/install-hooks.sh` to wire `.githooks/`;
   the hook suite includes gitleaks + `bin/scrub-public-repos.sh` guards.
   Add `bin/check-working-model-sync.sh --strict` to the repo's `ci.yml`
   (WP4 batch) and the umbrella `check-docs.sh` to the umbrella pre-commit.
6. **Branch ruleset** — require PR + 1 approval + linear history; set
   required status checks to the CI jobs this repo actually runs (e.g. `dco`,
   `guard` incl. `issue-link`, per-stack `ci` incl. `working-model`). If the
   repo has no CI, leave required checks empty so auto-merge isn't blocked.
7. **Auto-merge + branch auto-delete** — enable
   `allow_auto_merge` + `delete_branch_on_merge` in repo settings; arm
   `automerge.yml` (WP8 pattern: `pull_request_target`, `hold` label disarms).
8. **Labels + project** — adopt `component:*` / `workstream:*` label usage;
   land the repo on org Project #1 so issues appear on the canonical board.
9. **Default branch** — `main`; disallow force-pushes; require signed commits
   (DCO enforced by CI).
