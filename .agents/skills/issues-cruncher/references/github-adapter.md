# GitHub Adapter (CI + tracker)

Concrete adapter for GitHub. The engine talks to it through two seams so other
platforms (GitLab CI, Jira/Linear trackers, manual) can slot in later: a **CI
adapter** (run status, required checks, merge state) and a **tracker adapter**
(issues, claim, close).

## CI truth

- **`gh run view <run-id> --json status,conclusion,jobs` is truth.**
  `gh pr checks` aggregates and **lags** — it showed `pending` for minutes after a
  job had already gone `completed/success` this session. Always confirm a
  red/green at the run/job level before reporting.
- **Required checks come from branch protection / rulesets**, not the workflow
  YAML. A job in CI may not be required; a required check may be a status name no
  local YAML produces. Get them from the protection API.
- A new required job can appear *after* others finish (e.g. a `docker-build-smoke`
  gated on the test job) — "all green" isn't final until the run is `completed`.

## Merge-state guard

- `mergeStateStatus=BLOCKED` with all checks green usually means
  `REVIEW_REQUIRED` — a push does **not** clear a standing `CHANGES_REQUESTED`;
  the reviewer must re-review. Re-request review explicitly.
- **Green ≠ mergeable** if rulesets allow admin bypass or skip required checks.
  Never auto-merge on green alone; respect the protection model.
- Approval-driven rebase auto-merge **rebases**, which can sever the PR→issue
  keyword auto-close. Don't rely on it to close the tracker item.

## Tracker (issues) — GitHub

- **Claim** the issue before work (assignee / a claim comment) to prevent two
  orchestrators colliding.
- PR body references the tracking issue per the profile's **ref style**. In a
  multi-repo org the canonical backlog may be a *different* repo — use the
  fully-qualified `owner/repo#N` form so the link resolves (a bare `#N` targets the
  PR's own repo).
- **Close behavior is a detected capability** (`repo-profile.md`). If the merge
  won't auto-close (cross-repo, or rebase-merge severed it), close manually with a
  comment linking the merge commit + PR. Don't assume.

## Useful commands

```
gh run view <id> --json status,conclusion,jobs --jq '.jobs[]|"\(.name): \(.status)/\(.conclusion)"'
gh api repos/<o>/<r>/branches/<b>/protection            # required checks (may 403 → UNKNOWN)
gh pr view <n> --json mergeStateStatus,reviewDecision,reviewRequests,statusCheckRollup
gh pr edit <n> --add-reviewer <login>                   # re-request after a fix round
```
