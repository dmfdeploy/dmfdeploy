---
name: mechanical-multi-repo-doc-editing
description: Protocol for performing coordinated mechanical doc edits across multiple repos with verification — edits-only mode, no git operations, surgical replacements with grep-proof
source: auto-skill
extracted_at: '2026-06-10T07:58:58.524Z'
---

# Mechanical Multi-Repo Doc Editing

When tasked with mechanical doc-hygiene edits across multiple component repos (e.g., string replacements, link fixes, description updates), follow this protocol. The key constraint: **edits only, no git operations** — leave changes unstaged for the orchestrator to handle via PRs.

## Operating rules

- **EDITS ONLY**: Do NOT git add, commit, branch, or push. Leave all changes as unstaged modifications in the working trees.
- **Surgical replacements only**: Verify each target string exists in each file before editing. Do NOT touch anything not listed in the task.
- **No collateral damage**: Each edit must be a precise string replacement with sufficient context to uniquely identify the target.

## Procedure

### Phase 1: Discovery

For each task, grep to find all occurrences of the target string in the specified files:

```bash
grep -rn "target-string" path/to/repo/files
```

- Confirm the string exists in each target file
- Note line numbers and surrounding context
- Check that the string does NOT appear in files you should NOT modify (avoid false positives)

### Phase 2: Context reading

Before editing, read the context around each target line (3-5 lines before and after):

```
read_file(file_path, offset=line-3, limit=8)
```

This ensures you have enough context to construct a unique `old_string` for the edit tool.

### Phase 3: Surgical edits

For each replacement, use the `edit` tool with:
- `file_path`: absolute path to the file
- `old_string`: the exact text to replace, including at least 2-3 lines of surrounding context
- `new_string`: the replacement text with same surrounding context
- `replace_all`: set to `true` only if you want to replace ALL occurrences of the same pattern in one file

**Context requirement**: Include enough surrounding lines (typically 3-5) to uniquely identify the target and avoid accidental matches. Match whitespace and indentation exactly.

### Phase 4: Grep-proof verification

After all edits, run grep to confirm:

1. **Old strings removed**: `grep -rn "old-string" target/files` should return exit code 1 (no matches)
2. **New strings present**: `grep -rn "new-string" target/files` should return the expected matches
3. **No collateral changes**: verify that files NOT in the edit list still contain their original content

```bash
# Example verification suite:
grep -rn "all 6 repos" dmf-infra dmf-cms dmf-central dmf-media dmf-runbooks  # expect: no matches
grep -rn "lkirc" dmf-infra/docs/repo-strategy.md  # expect: no matches
grep -n "cluster.example.net" dmf-infra/README.md  # expect: no matches
```

### Phase 5: Git status report

Show the working tree state for each affected repo:

```bash
git -C dmf-infra status --short
git -C dmf-cms status --short
# ... for each repo
```

Confirm all files show `M` (modified) status, not `A` (added) or `??` (untracked). No commits should have been made.

## Report format

When reporting DONE to the orchestrator, include:

1. **Task summary**: what was changed, how many files, which repos
2. **Grep-proof output**: paste the actual grep results (not just "no matches found")
3. **Git status**: short status for each affected repo
4. **Specifics**: line numbers and file paths for each change

Example:
```
DONE. All edits applied, unstaged.

T1 'old' -> 'new' (11 files): grep returns 0 matches.
T2 'broken-link' -> 'fixed-link': grep shows new link at line 47.

Git status (all repos, modified not committed):
dmf-infra:  M CLAUDE.md  M AGENTS.md
dmf-cms:    M CLAUDE.md
```

## Common edit types

### String replacement across agent files
Replace a phrase in CLAUDE.md, AGENTS.md, QWEN.md across multiple repos. Same pattern in each file, same context structure.

### Link fix
Update a broken relative path in a markdown link. Change only the link target, not the link text (unless specified).

### URL/hostname update
Replace an example URL with the correct one. Usually a single occurrence.

### Description update
Update a bullet point or paragraph describing a component. Replace the entire bullet line.

## Pitfalls to avoid

- **Don't edit the same pattern in docs/ files** if the task only targets agent files (CLAUDE.md, AGENTS.md, QWEN.md). The same string may appear in historical docs — those are out of scope.
- **Don't use replace_all unless intended**. If the pattern appears in multiple contexts, some may need different replacements.
- **Don't forget to verify before editing**. A string that moved or was already changed will cause the edit to fail.
- **Don't create commits**. The orchestrator handles git workflow — leave changes unstaged.
