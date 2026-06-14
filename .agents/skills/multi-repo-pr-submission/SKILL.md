---
name: multi-repo-pr-submission
description: Protocol for submitting coordinated PRs across multiple repos as a specific GitHub identity — branch creation, DCO-signed commits, push, and PR opening with check monitoring
source: auto-skill
extracted_at: '2026-06-10T08:39:57.165Z'
---

# Multi-Repo PR Submission

When tasked with submitting PRs for coordinated doc-hygiene (or similar) edits across multiple repos, follow this protocol. The key constraint: **edits are already unstaged in the working tree** — you create the branch, commit, push, and open PRs.

## Operating rules

- Work ONLY in the **GitHub clone** (origin = `git@github.com:dmfdeploy/...`). NEVER touch the LAN clone.
- Do each repo fully, then move to the next. If ANY step errors, STOP and report BLOCKED.
- Do NOT use `--force`, `--no-verify`, or `--admin`.
- Sign every commit (`-s`) with DCO. Set author explicitly per task spec.
- Do NOT merge. Just create the PRs.

## Phase 1: Auth verification

Always verify the GitHub identity first:

```bash
gh auth status
```

Must show: `Logged in to github.com account <expected-user> (keyring)`.

If NOT logged in or wrong account, authenticate with the Keychain-stored PAT:

```bash
export GH_TOKEN="$(security find-generic-password -s ghcr.io -a <username> -w)"
gh auth status  # re-check
```

**Never echo, print, commit, or paste the token.** Use it only as `GH_TOKEN` env var for `gh`.

## Phase 2: Per-repo procedure

For each repo R (process in the order specified by the task):

### 2a. Verify working tree

```bash
cd ~/repos/dmfgithub/dmfdeploy/<R>
git status --short
```

Confirm only the expected files show `M` status. If anything unexpected appears, STOP and report BLOCKED.

### 2b. Set git identity

```bash
git config user.name "<display-name>"
git config user.email "<noreply-email>"
```

### 2c. Create branch and commit

```bash
git switch -c <branch-name>
git add -A
git commit -s -F /tmp/commitmsg-<R>.txt
```

The commit message file should be written beforehand using `write_file` to `/tmp/commitmsg-<R>.txt`. Include:
- Conventional commit title (`docs: ...`, `fix: ...`, etc.)
- Body with bullet-point changelog
- `Co-Authored-By:` line if applicable
- DCO sign-off added automatically by `-s` flag

### 2d. Push

```bash
git push -u origin <branch-name>
```

### 2e. Open PR

```bash
gh pr create -R dmfdeploy/<R> --base main --head <branch-name> \
  --title "<TITLE>" --body-file /tmp/prbody-<R>.txt
```

The PR body file (`/tmp/prbody-<R>.txt`) should be the same as the commit body **minus** the `Co-Authored-By:` line, **plus** a final attribution line like:

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### 2f. Check PR status

```bash
gh pr checks <PR#> -R dmfdeploy/<R>
```

Record the results (passed/pending/failing checks) for the final report.

## Phase 3: Final report

When all PRs are open, report via the specified channel with:

1. Each PR's URL and number
2. Check status for each (green/pending/fail, with count)
3. Any BLOCKED items with the specific error

Example:
```
DONE. All 4 PRs opened successfully as <handle>.

1. dmf-central (PR #1): https://github.com/dmfdeploy/dmf-central/pull/1
   Checks: DCO passed, 5 pending. 0 failing.

2. dmf-media (PR #1): https://github.com/dmfdeploy/dmf-media/pull/1
   Checks: 6 pending. 0 failing.
```

## Error handling

- If `git switch -c` fails (branch exists): STOP, report BLOCKED. Do not `--force`.
- If `git commit` fails: STOP, report BLOCKED. Check if files are actually modified.
- If `git push` fails (auth, network, permissions): STOP, report BLOCKED with the error.
- If `gh pr create` fails: STOP, report BLOCKED with the error.
- If `gh pr checks` fails: still report the URL, note failing checks.

## Common pitfalls

- **Wrong clone path**: Always use the GitHub clone (`~/repos/dmfgithub/dmfdeploy/`), not the LAN clone (`~/repos/dmfdeploy/`).
- **Forgot git config**: Set `user.name` and `user.email` before committing — the global config may be different.
- **Token exposure**: Never print `GH_TOKEN` or include it in logs/reports.
- **Missing -s flag**: Every commit must be DCO-signed. The `-s` flag appends `Signed-off-by` automatically.
- **PR body includes Co-Authored-By**: The PR body should NOT include the `Co-Authored-By:` line — that goes only in the commit message.
