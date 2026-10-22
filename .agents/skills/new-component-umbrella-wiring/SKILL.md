---
name: new-component-umbrella-wiring
description: Checklist of every umbrella mechanic that must be updated when adding a new component repo to dmfdeploy
source: auto-skill
extracted_at: '2026-06-02T09:59:57.463Z'
type: durable-pattern
scope: umbrella
owner: operator
review_by: '2027-01-14'
---

# New Component Repo — Umbrella Wiring Checklist

When scaffolding a new component repo under the dmfdeploy umbrella, a fixed
set of umbrella-level files enumerate repos by name. Missing any one is a
silent gap (CI won't catch it; the repo just won't participate in that gate).

Apply this checklist before committing the scaffold.

## Files to update (all in the umbrella root)

| File | Array variable | What it controls |
|---|---|---|
| `.gitignore` | (pattern) | Excludes the new dir from the umbrella git tree |
| `CLAUDE.md` / `QWEN.md` | prose | "N component repos" count + component table entry |
| `bin/generate-status.sh` | `COMPONENT_REPOS` | STATUS.local.md generation (gitignored snapshot) |
| `bin/generate-scripts-catalog.sh` | `COMPONENT_REPOS` | SCRIPTS.md generation |
| `bin/scrub-public-repos.sh` | `PUBLIC_REPOS_DEFAULT` | Pre-publish secret/topology scan |
| `bin/check-public-commit-authors.sh` | `PUBLIC_REPOS_DEFAULT` | Author identity gate |
| `bin/check-public-repo-hygiene.sh` | `PUBLIC_REPOS` | Hygiene checks |
| `bin/agentic/install-agentic-hooks.sh` | `PUBLIC_REPOS` | Pre-commit hook installation |
| `bin/sync-to-github.sh` | `PUBLIC_REPOS` + `github_repo_name()` case | GitHub mirror publish gate |
| `bin/agentic/forgejo.env` | `FORGEJO_PUBLIC_REPOS` | Agentic issue scripts |

## Decision: public or private?

- **Public repos** go in all the arrays above. Criteria: no secrets, no real
  IPs, no operator identity, no environment-specific values in any tracked
  file. Passes `scrub-public-repos.sh` and `gitleaks`.
- **Private repos** (like `dmf-env`) are deliberately excluded from all
  `PUBLIC_REPOS` arrays and from `sync-to-github.sh`. They still go in
  `COMPONENT_REPOS` (generate-status, generate-scripts-catalog) and in
  `.gitignore` + CLAUDE.md/QWEN.md.
- If unsure, classify as **private** until the scaffold is proven clean.

## For `sync-to-github.sh` specifically

Two changes are required (this is where misses are most common):

1. Append the repo name to the `PUBLIC_REPOS` array.
2. Add a case arm to `github_repo_name()` mapping the umbrella subdir to the
   GitHub repo name (usually the same, but the umbrella itself is `.` →
   `dmf-platform`).

Also update the `echo "allowed: ..."` line in the whitelist error message.

## For `bin/agentic/forgejo.env` specifically

Append the new repo name to `FORGEJO_PUBLIC_REPOS`. This array must match
the whitelist in `sync-to-github.sh` (minus the `.` umbrella entry).

## Verification

After all updates, run:

```bash
# Regenerate the gitignored local status snapshot (picks up the new repo)
bin/generate-status.sh
# Check no drift in committed generated docs
bin/generate-scripts-catalog.sh --check

# Verify the new repo passes public gates (if classified public)
bin/scrub-public-repos.sh dmf-<newrepo>
bin/check-public-commit-authors.sh dmf-<newrepo>
bin/check-public-repo-hygiene.sh dmf-<newrepo>

# Dry-run the publish gate (if classified public)
bin/sync-to-github.sh dmf-<newrepo> --dry-run
```

## Common pitfalls

- **Adding to `COMPONENT_REPOS` but not `PUBLIC_REPOS`** (or vice versa) —
  these serve different purposes. `COMPONENT_REPOS` = status/doc generation;
  `PUBLIC_REPOS` = public-facing gates.
- **Forgetting the `sync-to-github.sh` case arm** — the array alone isn't
  enough; `github_repo_name()` must resolve it.
- **Count strings** — CLAUDE.md/QWEN.md say "N component repos"; update the
  number to match.
- **forgejo.env** — easy to forget because it lives under `bin/agentic/`.
