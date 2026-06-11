---
name: github-operations-via-gh-cli
description: Protocol for GitHub repo scaffolding, issue creation, and project board operations via the gh CLI — handling 401s, GraphQL quoting, and API limitations
source: auto-skill
extracted_at: '2026-06-10T17:15:00.000Z'
---

# GitHub Operations via gh CLI

When scaffolding GitHub repos, creating issues, and managing project boards via the `gh` CLI, follow these protocols to avoid common pitfalls.

## When to use

- Creating repos, labels, milestones, discussions via `gh`.
- Bulk issue creation with specific labels and milestones.
- Adding issues to Projects-v2 and setting custom field values via GraphQL.
- Any operation where `gh project` subcommands may not work (401 in org context).

## Auth and 401 handling

**Intermittent 401s are common** even when `gh auth status` reports healthy. They often resolve on retry.

- When running multiple `gh` operations in a loop, **add retry logic** with exponential backoff (2s, 4s) on 401 responses.
- Some operations consistently 401 (e.g., `gh label create` batched with `&&`) while individual calls succeed. **Run operations individually**, not chained with `&&`.
- `gh repo edit`, `gh repo create`, `gh issue create` (REST) generally work fine.
- GraphQL operations (`gh api graphql`) may intermittently 401 — always retry.

## GraphQL operations

**`gh project` subcommands return 401 in org contexts.** Use `gh api graphql` for ALL Projects-v2 operations (add items, set fields, delete items, query items).

### Correct query syntax

**Use stdin with `-F query=@-`** to avoid shell quoting issues with nested braces and quotes:

```bash
echo 'mutation { addProjectV2ItemById(input: { projectId: "PVT_...", contentId: "I_..." }) { item { id } } }' | gh api graphql -F query=@-
```

**Do NOT use `-f query='...'`** with complex mutations — shell quoting breaks on nested braces.
**Do NOT use `--query`** — that flag doesn't exist on `gh api graphql`.
**Do NOT use `@/path/to/file.gql`** with `-f` — that expects a different format and produces "Expected NAME" parse errors.

### Python automation pattern

When automating GraphQL operations from Python, use stdin to avoid all quoting issues:

```python
import subprocess, json

def graphql(query_str):
    result = subprocess.run(
        'gh api graphql -F query=@-',
        input=query_str, shell=True, capture_output=True, text=True
    )
    if result.returncode != 0:
        return None
    return json.loads(result.stdout.strip())
```

### Common GraphQL field availability

- `addProjectV2ItemById` — ✅ exists
- `updateProjectV2ItemFieldValue` — ✅ exists (for single-select fields)
- `deleteProjectV2Item` — ✅ exists
- `pinDiscussion` — ❌ does NOT exist in the standard GraphQL schema (operator must pin via web UI)
- `createDiscussion` — ✅ exists (requires repositoryId, not repo slug)

### Getting repository ID

For mutations that need `repositoryId` (like `createDiscussion`), query it:

```bash
gh api graphql -F owner=dmfdeploy -F repo=dmfdeploy -f query='query($owner: String!, $repo: String!) { repository(owner: $owner, name: $repo) { id } }'
```

Or hardcode from a previous query: `R_kgDOS2oHOQ` for `dmfdeploy/dmfdeploy`.

## Issue creation

### Milestone flag

**`--milestone` takes the milestone TITLE string, not the number.**

```bash
gh issue create -R dmfdeploy/dmfdeploy --title "..." --milestone "v0.1-polish"  # ✅ works
gh issue create -R dmfdeploy/dmfdeploy --title "..." --milestone 1               # ❌ '1' not found
```

### Body files

Use `--body-file <path>` for multi-line bodies. This avoids shell escaping issues with heredocs and special characters.

### Label flag

**Use `--label` (singular flag with comma-separated values), not `--labels`:**

```bash
gh issue create -R dmfdeploy/dmfdeploy --title "..." --label "component:dmf-init,workstream:release"
```

## Project field mapping

Project-v2 single-select fields require the **option ID**, not the display name. These are opaque strings like `f43d9dd7`. There is no safe API to add new single-select options — the operator must add them in the Project UI.

When setting a field, only set it if the corresponding option exists. For labels that have no board option, **leave the field unset** and report which issues were skipped.

## Discussion limitations

- **Discussion categories CANNOT be created via API** — neither REST nor GraphQL has a mutation for this. Operator must add custom categories (like "RFC (pre-ADR)") via web UI: Settings → Discussions → Categories.
- **Discussion pinning** — `pinDiscussion` mutation does not exist in the standard GraphQL schema. Operator must pin via web UI.
- Default categories are seeded automatically: Announcements, General, Ideas, Polls, Q&A, Show and tell.

## Reply format

When reporting completion, include:
- Issue numbers created (in row order, for tracking_issue frontmatter).
- Project item count (verified via GraphQL query).
- Which issues got no Workstream field set (label has no board option).
- Discussion URL and pinned status (note if manual pinning is required).
- Any operations that required manual UI follow-up.
