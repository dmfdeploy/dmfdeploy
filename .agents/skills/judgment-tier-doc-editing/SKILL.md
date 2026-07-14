---
name: judgment-tier-doc-editing
description: Protocol for executing judgment-tier doc edits from a detailed spec — block rewrites, banner insertions, path neutralization, strict STOP-on-mismatch rules, and conditional no-ops
source: auto-skill
extracted_at: '2026-06-10T10:19:11.702Z'
type: durable-pattern
scope: docs
owner: operator
review_by: '2027-01-14'
---

# Judgment-Tier Doc Editing

When tasked with judgment-tier doc-hygiene edits from a detailed exec spec, follow this protocol. Unlike mechanical string replacements, these edits involve **block rewrites**, **banner insertions**, **path neutralization**, and **contextual rewrites** — each requiring verification before applying.

## Operating rules

- **EDITS ONLY**: Do NOT git add, commit, branch, or push. Leave all changes unstaged.
- **Verbatim OLD→NEW**: Apply each OLD→NEW replacement exactly as specified. If an OLD string doesn't match exactly, STOP that item and report BLOCKED — do NOT improvise.
- **Touch ONLY named files**: If a file listed in the spec doesn't exist, that sub-item is a no-op — report it but continue with remaining items.
- **No collateral damage**: Do NOT touch any .forgejo/ workflow, any feat/* spike doc, or any .sh/.yaml/Dockerfile (unless explicitly listed).

## Procedure

### Phase 1: Read the spec in full

The exec spec is the single source of truth. It contains:
- Exact OLD→NEW text for each item
- File lists per item
- Any hard rules or scope exclusions

Read it completely before starting any edits.

### Phase 2: Verify OLD strings exist

For each item, grep or read-file to confirm the OLD string exists in the target file(s):

```bash
grep -n "exact-old-string" path/to/file
```

Or read the context around the expected line. If the OLD string doesn't match verbatim, STOP that item — report BLOCKED with which file and why the mismatch occurred.

### Phase 3: Apply edits per item type

#### Block rewrite (e.g., section replacement)

Replace an entire section block. Include enough surrounding context in `old_string` to uniquely identify the block boundary:

```
edit(
  file_path="...",
  old_string="## Section Title\n\nparagraph 1\n\nparagraph 2\n",
  new_string="## New Section Title\n\nnew paragraph 1\n\nnew paragraph 2\n"
)
```

#### Single-line field update

For a single field within a table or list, match the entire line:

```
edit(
  file_path="...",
  old_string="| Loki | `<external_base_url>/loki` | — |\n",
  new_string="| Loki | `<external_base_url>/loki` (log API — no web UI) | — |\n"
)
```

#### Fenced block replacement (e.g., code/tree blocks)

Replace the entire fenced block from opening ``` to closing ```:

```
edit(
  file_path="...",
  old_string="```\nblock content...\n```\n",
  new_string="```\nnew block content...\n```\n"
)
```

#### Banner insertion (superseded/historical)

Insert a blockquote banner after the H1 heading. For files where `# Title` is on line 1:

```
edit(
  file_path="...",
  old_string="# Document Title\n\n**Status:** ...",
  new_string="# Document Title\n\n> **⚠️ HISTORICAL / SUPERSEDED.** Banner text.\n\n**Status:** ..."
)
```

For numbering-historical banners, use the standard text:
```
> **⚠️ Numbering/commands may be historical.** Parts of this document reference an
> earlier playbook-numbering scheme (e.g. `31-forgejo`, `40-netbox-sot`, `05-harden`)
> and the pre-OpenBao `--vault-password-file` workflow. The current tree uses the
> `200/300/600` + `vertical-*` layout and the `dmf-env/bin/run-playbook.sh` OpenBao
> wrapper. Cross-check against the live `k3s-lab-bootstrap/playbooks/` tree before running.
```

#### Path neutralization

Replace hardcoded operator-local paths with environment-variable equivalents:

```
edit(
  file_path="...",
  old_string="cd ~/repos/dmf-env",
  new_string="cd $DMFDEPLOY_UMBRELLA/dmf-env"
)
```

Do this for all occurrences in the file if specified (`replace_all: true`), or surgically per occurrence.

### Phase 4: Grep-proof verification

After all edits, verify each item:

1. **Old strings removed**: `grep -rn "old-string" target/files` → no matches
2. **New strings present**: `grep -n "new-string" target/files` → expected matches
3. **Banner counts correct**: `grep -rln "HISTORICAL / SUPERSEDED" dir/` → correct number of files
4. **No ~/repos/ paths remain**: `grep -rn "~/repos/" target/files` → no matches

### Phase 5: Git status

Show working tree state for each affected repo:

```bash
git -C dmf-infra status --short
git -C dmf-cms status --short
```

Confirm files show `M` (modified), not `A` (added) or `??` (untracked).

## Common edit patterns

### Past-tense conversion
Convert "incoming additions per ADR-XXXX" to "landed YYYY-MM-DD" blocks. Match the full blockquote including surrounding blank lines.

### Two-repo model → umbrella model
Replace sections describing a private/public two-repo model with umbrella + operator-local-state language (ADR-0035). The entire block changes — title, paragraphs, and any code blocks.

### Tree/directory listing updates
Replace an entire fenced tree block. The new tree may add/remove branches, renumber ranges, and add new directories. Match from opening ``` to closing ```.

### URL/hostname placeholder update
Replace example hostnames with the canonical placeholder (e.g., `cluster.example.net` → `dmf.example.com`).

### Playbook number corrections
Fix stale playbook numbers in both link text and href on the same line.

## Error handling

- **OLD string not found**: STOP that item, report BLOCKED with the file and what was searched for. Continue with remaining items.
- **File doesn't exist**: No-op for that sub-item. Report it in the final summary. Continue.
- **OLD string matches multiple locations**: Read context to determine which is the correct one. If ambiguous, STOP and report.
- **New string already present**: The edit may have already been applied. Report and continue — don't double-apply.

## Report format

When reporting DONE, include:

```
DONE. All N items applied, unstaged.

Item 1 (description): file(s) — grep proof result.
Item 2 (description): file(s) — grep proof result.
...
Item 7 (path neutralization): 4 of 6 named files existed and edited;
  X and Y do not exist — no-ops.

Git status (all modified, NOT committed):
dmf-infra:  M file1.md  M file2.md
dmf-cms:    M file3.md
```

## Pitfalls to avoid

- **Don't improvise on mismatched OLD strings**. The spec is authoritative — if it doesn't match, report BLOCKED.
- **Don't edit files that don't exist**. Report them as no-ops, don't create them.
- **Don't touch .forgejo/ or feat/ docs** unless explicitly listed in the spec.
- **Don't forget banner formatting**. Blockquote banners must use `> **⚠️ ...**` syntax with proper line breaks.
- **Don't miss multiple occurrences**. Some OLD strings appear in multiple files — grep all targets before editing.
- **Don't apply the same banner twice**. If a file already has a superseded banner, skip it.
