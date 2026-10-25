---
name: github-operations-via-gh-cli
description: Protocol for GitHub repo scaffolding, issue creation, and project board operations via the gh CLI: handling 401 errors, GraphQL quoting, and API limitations
source: auto-skill
extracted_at: '2026-06-10T17:15:00.000Z'
type: durable-pattern
scope: github
owner: operator
review_by: '2027-01-14'
---

# GitHub Operations via gh CLI

When scaffolding GitHub repos, creating issues, and managing project boards via the `gh` CLI, follow these protocols to avoid common pitfalls.

## When to use

- Creating repos, labels, milestones, discussions via `gh`.
- Bulk issue creation with specific labels and milestones.
- Adding issues to Projects-v2 and setting custom field values via GraphQL.
- Any operation where `gh project` subcommands may not work (401 in org context).

## Auth and 401 handling

**Intermittent 401 errors are common** even when `gh auth status` reports healthy. They often resolve on retry.

- When running multiple `gh` operations in a loop, **add retry logic** with exponential backoff (2 seconds, 4 seconds) on 401 responses.
- Some operations consistently 401 (for example, `gh label create` batched with `&&`) while individual calls succeed. **Run operations individually.**
- `gh repo edit`, `gh repo create`, `gh issue create` (REST) generally work fine.
- GraphQL operations (`gh api graphql`) may intermittently 401; always retry.

## GraphQL operations

**`gh project` subcommands return 401 in org contexts.** Use `gh api graphql` for ALL Projects-v2 operations (add items, set fields, delete items, query items).

### Correct query syntax

**Use stdin with `-F query=@-`** to avoid shell quoting issues with nested braces and quotes:

```bash
echo 'mutation { addProjectV2ItemById(input: { projectId: "PVT_...", contentId: "I_..." }) { item { id } } }' | gh api graphql -F query=@-
```

**Do NOT use `-f query='...'`** with complex mutations. Shell quoting breaks on nested braces.
**Do NOT use `--query`.** That flag doesn't exist on `gh api graphql`.
**Do NOT use `@/path/to/file.gql`** with `-f`. That expects a different format and produces "Expected NAME" parse errors.

### Python automation pattern

When automating GraphQL operations from Python, use stdin to avoid all quoting issues:

```python
import subprocess, json

def graphql(query_str):
    result = subprocess.run(
        ["gh", "api", "graphql", "-F", "query=@-"],
        input=query_str, capture_output=True, text=True
    )
    if result.returncode != 0:
        return None
    return json.loads(result.stdout.strip())
```

### Common GraphQL field availability

- `addProjectV2ItemById`: ✅ exists
- `updateProjectV2ItemFieldValue`: ✅ exists (for single-select fields)
- `deleteProjectV2Item`: ✅ exists
- `pinDiscussion`: ❌ does not exist in the standard GraphQL schema (operator must pin via web UI)
- `createDiscussion`: ✅ exists (requires repositoryId; repo slug is not accepted)

### Getting repository ID

For mutations that need `repositoryId` (like `createDiscussion`), query it:

```bash
gh api graphql -F owner=dmfdeploy -F repo=dmfdeploy -f query='query($owner: String!, $repo: String!) { repository(owner: $owner, name: $repo) { id } }'
```

Or hardcode from a previous query: `R_kgDOS2oHOQ` for `dmfdeploy/dmfdeploy`.

## Issue creation

### Milestone flag

**`--milestone` requires the milestone TITLE string.**

```bash
gh issue create -R dmfdeploy/dmfdeploy --title "..." --milestone "v0.1-polish"  # ✅ works
gh issue create -R dmfdeploy/dmfdeploy --title "..." --milestone 1               # ❌ '1' not found
```

### Body files

Use `--body-file <path>` for multi-line bodies. This avoids shell escaping issues with heredocs and special characters.

### Label flag

**Use `--label` (singular flag with comma-separated values):**

```bash
gh issue create -R dmfdeploy/dmfdeploy --title "..." --label "component:dmf-init,workstream:release"
```

## Project field mapping

Project-v2 single-select fields require the **option ID** (an opaque string like `f43d9dd7`). There is no safe API to add new single-select options; the operator must add them in the Project UI.

When setting a field, only set it if the corresponding option exists. For labels that have no board option, **leave the field unset** and report which issues were skipped.

## Discussion limitations

- **Discussion categories cannot be created via API.** Neither REST nor GraphQL has a mutation for this. Operator must add custom categories (like "RFC (pre-ADR)") via web UI: Settings → Discussions → Categories.
- **Discussion pinning:** `pinDiscussion` mutation does not exist in the standard GraphQL schema. Operator must pin via web UI.
- Default categories are seeded automatically: Announcements, General, Ideas, Polls, Q&A, Show and tell.

## PR creation and CI guard pitfalls

### The issue-link guard needs a QUALIFIED reference from a component repo

The `guard / issue-link` job greps the PR **body** for a tracking-issue
reference, and the two regexes differ:

| Repo | Accepted | Bare `#N` |
|---|---|---|
| umbrella (`dmfdeploy/dmfdeploy`) | `(dmfdeploy/dmfdeploy)?#N` (slug optional) | passes |
| every component repo | `dmfdeploy/dmfdeploy#N` (slug required) | **fails** |

So from a component repo `Closes #20` fails the gate and silently targets that
repo's own issue #20. Always write
`Closes dmfdeploy/dmfdeploy#N` / `Refs dmfdeploy/dmfdeploy#N` in a component PR
body. `dmfdeploy/dmf-env#20` also fails: it is not the umbrella backlog.

Trivial change with no issue? Add the `no-issue` label, which the job honours
before it ever reads the body.

### Editing the PR body re-runs the check in the umbrella only

In the umbrella, `issue-link` runs from `.github/workflows/issue-link.yml`. It
triggers on `pull_request_target` with `edited`, `labeled`, and `unlabeled`
besides the default types, and it reads the current body and labels from the
API. So `gh pr edit --body`, or adding the `no-issue` label, re-runs the check
on the PR as it is now, and no push or close and reopen is needed. A re-run of
the job reads the live body too.

Component repos still run the check from `guard.yml` under `pull_request`
with **no `types:`**, which gets the GitHub defaults: `opened`,
`synchronize`, and `reopened`. **`edited` isn't among them**, and the job reads
the body from the event payload. There, `gh pr edit --body` alone never re-runs
the check, and a re-run replays the old body. Two ways to re-fire, both
default types:

- **Close and reopen**: fires `reopened`.
- **Push any commit**: fires `synchronize`, and the new event payload carries
  the *current* body, so a body fix and a content fix land in one run.

Prefer the push when the PR needs a content change anyway. Verified on umbrella
#360 (2026-08-04), before the umbrella moved to the trusted workflow: the body
was edited to add the missing reference, then a content commit pushed. The
`synchronize` run read the updated body and `issue-link` passed.

Labels behave the same way in a component repo: `labeled` and `unlabeled`
aren't default types, so adding `no-issue` to a failed PR needs the same
re-fire.

## Reply format

When reporting completion, include:
- Issue numbers created (in row order, for tracking_issue frontmatter).
- Project item count (verified via GraphQL query).
- Which issues got no Workstream field set (label has no board option).
- Discussion URL and pinned status (note if manual pinning is required).
- Any operations that required manual UI follow-up.
