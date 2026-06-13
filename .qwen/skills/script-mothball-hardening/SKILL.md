---
name: script-mothball-hardening
description: Mothball legacy script systems by classifying scripts as MUTATING vs READ-ONLY, inserting fail-closed guards, updating catalog metadata, and verifying
source: auto-skill
extracted_at: '2026-06-10T15:28:28.548Z'
---

# Script Mothball & Fail-Closed Hardening

When a legacy script harness is retired but preserved for provenance, harden the mutating scripts so they fail closed by default.

## When to use

- A script system (e.g., agentic harness, legacy deploy pipeline) is superseded but its files must remain for historical provenance.
- The task: prevent accidental execution of scripts that mutate repo state or external APIs.
- Read-only scripts that only gather/display information may remain usable without override.

## Classification protocol

**Read every script's code.** Do NOT trust comment claims like "Read-only" — verify by inspecting what the script actually does.

A script is **MUTATING** if it does ANY of:
- Writes, creates, or deletes files in the repo (including JSON, YAML, markdown, log files).
- Mutates git state (git config, git hooks, commits, branches).
- Calls external mutation APIs (POST, PATCH, DELETE, PUT) — Forgejo, GitHub, Cloudflare, etc.
- Runs other scripts that mutate state (e.g., `generate-status.sh` which writes STATUS.local.md).

A script is **READ-ONLY** if it:
- Only reads files and prints to stdout.
- Only makes GET requests to external APIs.
- Only aggregates data in memory and displays it.

**Edge case to watch:** A script described as a "status file helper" or "read helper" may have `write` or `clear` subcommands that mutate files. The presence of any mutating subcommand makes the whole script MUTATING.

Environment files (`*.env`) are not scripts — leave them alone.

## Guard insertion pattern

For every MUTATING script, insert this block immediately after the `set -euo pipefail` line (or after all `set -...` lines if there are multiple):

```bash
if [[ "${DMF_AGENTIC_OVERRIDE:-}" != "1" ]]; then
    echo "mothballed YYYY-MM-DD — set DMF_AGENTIC_OVERRIDE=1 to run" >&2
    exit 1
fi
```

**Placement rules:**
- Must come AFTER `set -euo pipefail` (so `exit 1` behaves correctly).
- Must come BEFORE any sourcing of env files or variable assignments.
- The date in the message should match the mothball decision date.
- The message goes to stderr (`>&2`) so it doesn't pollute stdout consumers.

## Catalog metadata update

For scripts that appear in a generated catalog (e.g., `docs/SCRIPTS.md`), prefix the first descriptive comment line of each MUTATING script with:

```
# MOTHBALLED YYYY-MM-DD (historical, fails closed): <original first-line description>
```

The catalog generator extracts the first non-shebang comment paragraph — this prefix ensures the generated catalog entry shows the mothball status.

After editing headers, re-run the catalog generator (e.g., `bin/generate-scripts-catalog.sh`) and verify with `--check` mode.

## Verification protocol

Three steps, all must pass:

### 1. Syntax check
```bash
bash -n bin/agentic/<script>.sh
```
Must exit 0 for every touched script.

### 2. Shellcheck
```bash
uvx --from shellcheck-py shellcheck bin/agentic/<script>.sh ...
```
Must be clean. Pre-existing warnings in lines you didn't touch are acceptable — report them separately.

### 3. Runtime guard test
```bash
bin/agentic/<guarded-script>.sh
# Expected: exit 1, stderr contains "mothballed YYYY-MM-DD"
```

With override (only if safe to interrupt immediately — otherwise skip):
```bash
DMF_AGENTIC_OVERRIDE=1 bin/agentic/<guarded-script>.sh
```

## Reply format

When reporting completion, include:
- Per-script classification (MUTATING or READ-ONLY) with brief justification.
- Note any disagreements with expected classification (e.g., "expected READ-ONLY but writes files").
- List of files created and modified.
- Shellcheck results (flag any pre-existing findings).
- Guard test result (exit code + message).
