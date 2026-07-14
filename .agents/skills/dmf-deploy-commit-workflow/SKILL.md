---
name: dmf-deploy-commit-workflow
description: Conventional commit + DCO requirements and PR procedure for dmfdeploy/dmfdeploy
source: auto-skill
extracted_at: '2026-06-13T17:38:16.578Z'
type: operational-procedure
scope: umbrella
owner: operator
review_by: '2027-01-14'
---

# DMF Deploy Commit & PR Workflow

## Conventional Commit Format (enforced by commitlint)

All commit messages must follow:

```
type(scope): description (Closes #N)
```

- `type`: one of `docs`, `feat`, `fix`, `chore`, etc.
- `scope`: parenthesised area, e.g. `plans`, `status`, `skills`, `hooks`
- `description`: imperative, lowercase first letter, no period
- Reference issues: `(Closes #N)` or `(refs #N)`

**Good:**
```
docs(plans): fix 10 check-docs.sh warnings (Closes #59)
```

**Bad (will fail commitlint):**
```
Fix 10 check-docs.sh warnings: cross-repo URLs, broken paths
```

## DCO Sign-Off (enforced by DCO bot)

Every commit must include a `Signed-off-by` line. Use `-s` flag:

```bash
git commit -s -m "docs(plans): description (Closes #N)"
```

When amending: `git commit --amend -s --no-edit`

## check-docs.sh False-Positive Handling

When a plan doc needs to **quote** or **template** broken link syntax (e.g. documenting a broken link found during cleanup), do NOT use markdown link syntax — the checker regex `[text](target)` will match it:

```markdown
# Bad — checker catches this even in code backticks
`[CLAUDE.md](../CLAUDE.md)`

# Good — plain text, no link syntax
quoted broken ref to `../CLAUDE.md`

# Good — ADR placeholder
`ADR-XXXX (TBD)`  instead of [ADR-XXXX](../XXXX-...md)
```

## Per-Repo Template Blocks

When a plan doc contains template text meant to be copied into component repos (e.g. CONTRIBUTING.md templates), references like `SECURITY.md` are relative to the **component repo root**, not the umbrella. Do not resolve these to `../../SECURITY.md`. Use plain code text instead to avoid the checker:

```markdown
# In a per-repo template block — use plain text
See `SECURITY.md` at repo root.
```

## PR Procedure

1. Work starts at an issue — create one if none exists
2. Create a branch: `git checkout -b fix-something`
3. Commit with conventional format + DCO: `git commit -s -m "type(scope): ..."`
4. Push: `git push -u origin <branch>`
5. Create PR: `gh pr create --title "..." --body "..."`
6. If checks fail, amend + force-push:
   - commitlint failure → amend message to `type(scope): description`
   - DCO failure → amend with `-s` flag
   - `git commit --amend -s -m "..." && git push --force-with-lease`
7. Address reviewer feedback, force-push again if needed
