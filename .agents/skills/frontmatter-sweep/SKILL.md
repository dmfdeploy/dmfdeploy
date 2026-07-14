---
name: frontmatter-sweep
description: Protocol for applying YAML frontmatter to a large set of markdown files based on a triage table — single-source parsing, Python for reliability, reciprocal banners, and strict verification
source: auto-skill
extracted_at: '2026-06-10T17:00:00.000Z'
type: incident-residue
scope: docs
owner: operator
review_by: '2026-10-14'
---

# Frontmatter Sweep Over Markdown Files

When tasked with inserting YAML frontmatter as the first bytes of many markdown files based on a structured triage table, follow this protocol.

## When to use

- A triage table has been approved as the **single source of truth** for file statuses.
- You must insert YAML frontmatter into N files (often 100+) with status, date, and optional fields (executed, superseded_by).
- Superseded files need banners under their H1 pointing at successors, and successors need reciprocal "Supersedes:" links.
- Filenames contain special characters (em-dashes, spaces, ampersands, parentheses).

## Core rules

- **Never infer status from prose.** The triage table is the only input — if a file is missing from it, STOP and report.
- **Frontmatter must be the literal first bytes.** If a file starts with HTML comments or banners, frontmatter goes ABOVE them.
- **Touch nothing beyond the specified scope.** No file renames, no content edits beyond frontmatter + banners.
- **Use `git -c core.quotepath=false ls-files -z`** for enumeration — filenames with special characters will be miscounted otherwise.

## Procedure

### Phase 1: Parse the triage table

Read the triage table and build a structured mapping: filename → {status, date, executed?, superseded_by?}.

**Date cleaning rules:**
- Strip `(import)` and `(assigned)` annotations from the date column.
- Keep only ISO date (`YYYY-MM-DD`).

**Executed date extraction:**
- The executed column may contain `YYYY-MM-DD`, `YYYY-MM-DD — note`, or non-date text like `⚠ delivered via dmf-init`.
- Use regex `^(\d{4}-\d{2}-\d{2})` — if it matches, take the date; otherwise omit the `executed:` key entirely.

**Superseded_by extraction:**
- Strip surrounding quotes from the cell value.
- Use the exact filename (not the bare name) for the `superseded_by:` YAML value.

### Phase 2: Use Python for reliable processing

**Do NOT use bash for TSV parsing or frontmatter composition.** Bash `read` collapses consecutive tab delimiters, shifting fields when empty values exist. Move the entire composition logic into Python:

```python
import os, re, subprocess, urllib.parse

# Enumerate files via git
result = subprocess.run(
    ["git", "-c", "core.quotepath=false", "ls-files", "-z", "docs/plans/*.md"],
    capture_output=True, text=True
)
files = [f for f in result.stdout.split("\0") if f]

# Parse frontmatter for each file
for filepath in files:
    base = os.path.basename(filepath)
    with open(filepath) as fh:
        head = fh.read(1024)
    if not head.startswith("---"):
        continue  # no existing frontmatter — safe to prepend
    m = re.match(r"^---\n(.*?)\n---", head, re.DOTALL)
    if not m:
        continue
    block = m.group(1)
    # Extract fields with regex...
```

**Build the superseded_by / supersedes cross-links:**
- For each superseded file: record `filename → superseded_by_target`.
- For each target (successor): collect list of files that it supersedes (multiple files may supersede into the same successor).

### Phase 3: Apply frontmatter

For each target file (skip files that already have frontmatter):

1. Build the YAML block:
```yaml
---
status: <status>
date: <date>
executed: <date>          # only if executed date exists
superseded_by: "<target>" # only for superseded files
---
```

2. Prepend to file content: `new_content = frontmatter + original_content`

3. Add superseded-by banner (for superseded files):
```markdown
> **Superseded by** [<target filename>](<URL-encoded target>) — see frontmatter.
```
Insert directly under the H1 title line.

4. Add supersedes link (for successor files):
```markdown
> Supersedes: [<old1>](<URL-encoded old1>), [<old2>](<URL-encoded old2>)
```
If multiple files supersede into the same successor, comma-separate them. If the successor already has a "Supersedes:" line, append rather than duplicate.

### Phase 4: Verification

**Must pass all checks:**

```bash
# 1. File count matches expectation
git -c core.quotepath=false ls-files 'docs/plans/*.md' | wc -l

# 2. Every file starts with ---
git -c core.quotepath=false ls-files 'docs/plans/*.md' | while IFS= read -r f; do head -1 "$f"; done | grep -c '^---$'
# Should equal total count

# 3. Status values in allowed set
# All status: values must be one of: active, draft, executed, superseded, historical
# Per-status counts should match the triage table

# 4. All superseded files have superseded_by in frontmatter
# 5. All superseded files have "> **Superseded by**" banner under H1
# 6. All successor files have "> Supersedes:" banner under H1

# 7. git diff --stat touches exactly the intended files + nothing else
git diff --stat
```

## Common pitfalls

- **Bash `read` with tabs:** `IFS=$'\t' read -r a b c d` collapses empty fields between consecutive tabs. If field 3 is empty, field 4's value shifts into variable c. Use Python for TSV processing.
- **macOS `head -n -1`:** This GNU syntax for "all but last line" doesn't work on macOS. Use `sed '$d'` instead.
- **URL-encoding filenames:** Markdown links need `%20` for spaces, `%E2%80%94` for em-dashes, `&` → `%26`, `(` → `%28`. Use `urllib.parse.quote(filename, safe='')` in Python.
- **Frontmatter already present:** Some files may already have frontmatter (the triage table file, the umbrella plan). Skip them — do not double-insert.
- **Superseded chain:** A file can be both superseded AND a successor (e.g., Gate 2 Fix → Gate 2 Pivot → Cluster-Internal Pivot). Handle both directions independently.
- **Quoted vs bare filenames in YAML:** `superseded_by:` values with spaces should be quoted in YAML. Use `"filename with spaces.md"` syntax.
