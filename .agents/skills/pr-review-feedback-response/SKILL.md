---
name: pr-review-feedback-response
description: Protocol for reading PR review feedback, finding the PR branch (including in worktrees), applying targeted fixes, and pushing updates
source: auto-skill
extracted_at: '2026-06-13T05:43:58.499Z'
---

# PR Review Feedback Response

When a PR has review feedback (especially `CHANGES_REQUESTED`) and you need to apply fixes, follow this protocol.

## Step 1: Fetch PR details and reviews

```bash
# Get PR metadata
gh pr view <N> --json title,body,state,url

# Reviews are NOT available via --reviews flag (it doesn't exist).
# Use the REST API instead:
gh api repos/<owner>/<repo>/pulls/<N>/reviews \
  --jq '.[] | {state: .state, body: .body, user: .user.login, submitted_at: .submitted_at}'

# Get the PR diff to see file paths:
gh pr view <N> --json files --jq '.files[].path'
gh pr diff <N>  # full diff
```

**Key gotcha:** `gh pr view --reviews` does not exist — use `gh api repos/.../pulls/N/reviews` instead.

## Step 2: Find the PR branch

```bash
gh pr view <N> --json headRefName,baseRefName \
  --jq '{head: .headRefName, base: .baseRefName}'
```

Check if the branch exists locally:

```bash
git branch | grep <headRefName>
git branch -r | grep <headRefName>
```

### Branch in a worktree

If `git checkout <branch>` fails with `"already checked out at '<path>'"`, the branch lives in a **worktree** (common for handoff/PR scaffolding). You have two options:

**Option A — work in the worktree directly:**
```bash
cd <worktree-path>
# edit files, commit, push there
```

**Option B — copy files into the worktree:**
```bash
cp <fixed-file> <worktree-path>/<relative-path>
cd <worktree-path>
git add <file>
git commit -s -m "fix: <message>"
git push
```

**Do NOT** try to `git checkout` a branch that's already checked out in a worktree — it will fail.

## Step 3: Apply the fix

1. Read the review body to understand the requested change.
2. Read the relevant file at the referenced line (e.g., `file.md:48`).
3. Make the minimal targeted change.
4. Verify the diff before committing:

```bash
git diff -- <file>
```

## Step 4: Commit and push

```bash
git add -- <file>
git commit -s -m "<conventional-title>

<detailed-body explaining what changed and why>"
git push
```

**Rules:**
- DCO sign-off (`-s`) on every commit.
- Conventional commit title.
- Reference the issue/PR in the body if applicable.

## Step 5: Verify

```bash
# Confirm the push landed:
gh pr view <N> --json commits --jq '.commits[-1].oid'

# Optionally open the PR to confirm:
gh pr view <N> --web
```

## Common pitfalls

- **`--reviews` flag doesn't exist** on `gh pr view` — use `gh api` for reviews.
- **PR branch in a worktree** — `git checkout` will fail with "already checked out". Use the worktree directory directly.
- **Editing the wrong file** — the PR diff may show files that don't exist on disk yet (new files). The diff is the source of truth; apply the fix to whatever version is in the PR branch.
- **Shared umbrella checkout** — if the PR is from the umbrella repo's main branch and shared with other agents, work in the dedicated worktree, not the shared checkout.
