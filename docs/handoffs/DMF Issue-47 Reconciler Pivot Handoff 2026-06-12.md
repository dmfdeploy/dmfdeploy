# DMF Issue-47 Reconciler Pivot Handoff — 2026-06-12

> **Mission for the fresh session:** finish [PR #51](https://github.com/dmfdeploy/dmfdeploy/pull/51)
> (the #47 issue-close reconciler) by **refactoring it onto GitHub's native
> `closingIssuesReferences`** instead of the hand-rolled regex extractor, fix the
> two open round-4 review findings, get it approved + merged, then run the
> post-merge cleanup. Use the **issues-cruncher skill** (`skills/issues-cruncher/`,
> on `main` since PR #50) — this work *is* its dogfood.

## 1. Where things stand

| Thing | State |
|---|---|
| **PR #51** | OPEN, `CHANGES_REQUESTED` (lkirc round 4), head `bbc917b`, CI 8/8 green, `Closes #47` |
| Branch / worktree | `znerol2/issue-47-close-reconciler` in worktree `../dmfdeploy-issue47` (sibling of the umbrella checkout) |
| **PR #50** (issues-cruncher skill) | MERGED (`bb9a57c`) — skill lives at `skills/issues-cruncher/` on main |
| Umbrella shared checkout | on `main` (older `f37ddac` at handoff time) — **shared with other agents; do not switch its branch; work in worktrees** |
| Issues | #47 OPEN (this work). #46 OPEN (canonical skills; skill is its flagship; qwen-learnings stash@{0} parked for its promote-flow). #48 OPEN (idempotency follow-up). #52 OPEN (board reconciler, filed today) |
| Org board (Project #1, `PVT_kwDOENb9uM4BaPY-`) | #46/#47/#48/#52 backfilled today; #47 = In Progress. **`gh issue create` does NOT board-add — separate GraphQL step** (that's #52's subject) |
| Agent trio | tmux panes via `agent-bridge` (`~/.claude/skills/agent-bridge/bin/agent-bridge`): `qwen-left` = implementer, `codex` = adversary, `claude` = orchestrator. Verify with `agent-bridge list` / `ping` before dispatching |

## 2. The strategic decision (made with the operator — do not relitigate)

**Stop regex-parsing PR bodies. Use GitHub's own parsed result.**

Five lkirc review rounds found real false-close bugs, *all but one inside the
hand-rolled close-keyword extractor* (substring boundaries → negation → sed
delimiter bypass → wrong-number-from-line-tail). The platform already runs this
parser and stores the result — **including cross-repo refs**. Empirical proof
(run today):

```
gh api graphql -f query='query{ repository(owner:"dmfdeploy",name:"dmf-env"){
  pullRequest(number:4){ closingIssuesReferences(first:10){
    nodes{ number state repository { nameWithOwner } } } } } }'
→ {"number":20,"repository":{"nameWithOwner":"dmfdeploy/dmfdeploy"},"state":"CLOSED"}
```

New semantics: **close exactly what GitHub itself parsed as a closing reference**
(i.e., what native auto-close *would* have closed had it fired). Most defensible
spec; kills the entire extractor bug class.

### Refactor spec for `bin/close-completed-issues.sh`

- **Drop:** `extract_umbrella_issues()` entirely (both `#N` and URL paths),
  `CLOSE_KEYWORDS`, `NEGATION_RE`, the boundary/negation machinery, and the
  ~20 extractor self-test cases.
- **Replace:** in `find_candidates()`, query merged PRs **with**
  `closingIssuesReferences` exhausting the connection — paginate via
  `pageInfo{hasNextPage,endCursor}` + `after:$cursor` in a loop until
  `hasNextPage == false`, collecting all `nodes{ number repository{nameWithOwner} }`.
  This must be in the same GraphQL call that already fetches `number,url,mergedAt`
  per repo. Filter nodes to `repository.nameWithOwner == "dmfdeploy/dmfdeploy"`.
- **Keep (still load-bearing):** merged-PRs-only enumeration; only-close-if-OPEN;
  **reopen guard** (timeline `reopened` newer than PR `mergedAt` ⇒ skip;
  **API-error ⇒ skip**, never close on unknown); dry-run default + `--apply`
  closing exactly the dry-run candidate set; explicit `-R dmfdeploy/dmfdeploy`
  on all gh calls; idempotency; the workflow (`issue-close-reconciler.yml`:
  schedule + dispatch + `pull_request:closed` gated on `merged == true`,
  `permissions: contents: read + issues: write`).
- **Self-test:** shrink to what's still testable locally (reopen-guard timestamp
  comparison helper, candidate-set plumbing) — most coverage moves to "GitHub is
  the parser". Keep the **CI self-test step** in umbrella `ci.yml` (added this
  session) pointing at whatever remains; **remove it only if nothing pure-local
  is left** (then also remove the step — don't leave a step calling a missing flag).

### Round-4 findings (must be addressed; refactor covers the first)

1. `:153` — URL path takes `grep -oE '[0-9]+$'` **of the whole line**:
   `Closes https://…/issues/9 for milestone 2026` → emits `2026` (wrong-issue
   close). **Made moot by the refactor** (no URL parsing). If for any reason the
   refactor is rejected, fix by extracting from each matched URL, not the line.
2. `:419` — reopen guard reads `/issues/N/events` **unpaginated** (30-event page);
   a newer `reopened` beyond page 1 is missed. **Survives the refactor — must be
   fixed**: paginate (`--paginate`) or query the issue's
   `timelineItems(itemTypes:[REOPENED_EVENT], last:1)` via GraphQL (cleaner), and
   keep the fail-safe (error ⇒ skip).

### Also file (follow-up issue, agreed with operator)

**Automerge-actor investigation:** native auto-close likely doesn't fire because
`automerge.yml` enables auto-merge via the repo-scoped `GITHUB_TOKEN` bot actor
(bot-attributed merges suppress keyword-close; repo-scoped token can't close
cross-repo anyway). An org-scoped GitHub App doing the merges could make native
close work for future PRs, demoting the reconciler to a backstop. File as
umbrella issue (`component:cross-repo`, `workstream:release`, v0.2, sibling of
#47/#52) — **and board-add it** (see #52).

## 3. Review ledger (lkirc, PR #51) — all findings were real

| Round | Finding | Status |
|---|---|---|
| 1 | reopen race (historical PRs re-close reopened issues) | fixed: timeline guard + fail-safe-on-error |
| 1 | URL path skipped negation | fixed (moot after refactor) |
| 1 | workflow missing `contents: read` | fixed |
| 2 | close-keywords matched as unbounded substrings (`unresolved #47`) | fixed via boundary group (moot after refactor) |
| 3 | negation guard sed-delimiter bypass on qualified refs | fixed via literal bash prefix-strip (moot after refactor) |
| 4 | line-tail digit extraction closes wrong issue | **OPEN — moot if refactored** |
| 4 | reopen guard unpaginated events | **OPEN — must fix** |

Reply to round 4 on the PR explaining the refactor (a holding comment was posted
2026-06-12 saying the next push pivots to `closingIssuesReferences`), then
re-request `lkirc` (`gh pr edit 51 --add-reviewer lkirc`). A force-push amend onto
the single commit is the established pattern (`--force-with-lease`).

## 4. Process rules in force (from the merged skill — follow them)

- **Orchestrator owns all git** (commit/amend/push after verify); implementer
  (qwen) stages/verifies/reports, never commits. lkirc made us codify this.
- **Verify on disk, never agent reports** (qwen's reports were wrong twice today:
  a phantom line-count, a garbled diff paste). Re-run everything yourself.
- **Discrimination testing**: any remaining test must fail on the old code.
  **Real-data `--dry-run` before any push** — it caught what self-tests missed
  (`fixed 5 bugs` → would have closed live #5).
- **Commit hygiene:** DCO `-s`; **no Co-Authored-By / no "Generated with"**;
  conventional subject; `Closes #47` stays in the subject/body. Use
  `STATUS_HOOK_SKIP=1` to keep the volatile STATUS.md out of commits.
- **Umbrella gotchas:** plans-INDEX regen if touching `docs/plans/`; `gh pr checks`
  lags — `gh run view <id>` is CI truth; cross-repo PRs don't auto-close umbrella
  issues (that's #47 itself); `gh project` may 401 — raw GraphQL with the node id.
- **agent-bridge gotchas:** codex replies need the full binary path; codex spinner
  unreadable in capture; `tmux send-keys -t <pane> Escape` flushes a wedged queue;
  qwen tends to omit tests unless the brief demands them; ECONNRESET mid-command
  leaves disk work intact — verify and resume, don't re-run blindly.

## 5. Post-merge duties (once #51 lands)

1. **Close #47 manually** with a comment linking the merge commit (the very gap
   the PR fixes — fittingly its last manual close), set board Status → Done.
2. Remove the worktree: `git worktree remove ../dmfdeploy-issue47`, delete local
   + remote branch, `git worktree prune`.
3. Consider a first supervised real run: `workflow_dispatch` the reconciler,
   inspect the dry-run-equivalent log, only then trust the schedule.
4. This handoff's own worktree (`../dmfdeploy-handoff`) can be removed once the
   handoff PR merges.

## 6. Skill-improvement note (for #46, optional)

Add to `skills/issues-cruncher/references/orchestrator-primer.md`: *before
re-parsing platform data, check whether the platform already exposes the parsed
result* (this pivot), and to `dmf-profile.md`: *filing an umbrella issue includes
the Project-#1 board-add step* (#52). Small PR, `Refs #46`.
