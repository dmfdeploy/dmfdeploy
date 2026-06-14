---
name: orchestrated-lifter-workflow
description: Execute precise code edits from a spec file in a multi-agent orchestrated workflow — verify, report DONE/BLOCKED via agent-bridge, no commits
source: auto-skill
extracted_at: '2026-06-05T12:50:00Z'
---

# Orchestrated Lifter Workflow

When working as the LIFTER in a multi-agent orchestrated setup (another agent writes the spec and verifies; you execute), follow this protocol.

## When to use

- The orchestrator sends a task via agent-bridge with a spec file path (e.g., `/tmp/slice-N-spec.md`).
- You're told to execute only what's in the spec and reply DONE/BLOCKED via agent-bridge.
- You're doing authoring work across multiple repos with no commits (orchestrator reviews diffs before commit).

## Procedure

### 1. Read the spec in full

- Read the entire spec file from the given path (usually `/tmp/slice-N-spec.md`).
- Note ALL tasks (A, B, C, etc.) and their verify commands.
- Note the repo paths — they're usually absolute paths to sibling repos outside the umbrella working dir (your Glob may not find them; use Read/edit directly with absolute paths).
- Note the branch instruction (usually `main`, no feature branches).
- Note the commit instruction (usually "no commits" — the orchestrator reviews diffs).

### 2. Execute each task precisely

- **Do ONLY what's specified.** Don't fix adjacent issues, don't refactor, don't touch unrelated files.
- Match existing indentation and style exactly — these are usually whitespace-sensitive YAML docs.
- If the spec says "mirror the existing X entry", copy that entry's structure exactly (same keys, same indentation, same var-reference patterns).
- When the spec gives exact YAML/Go template snippets, use them verbatim.

### 3. Verify after each task

- Run the verify commands specified in the spec (e.g., `helm template | grep`, `ansible-playbook --syntax-check`, `ruby -ryaml -e "YAML.load_file(...)"`, `grep -n`).
- If a verify tool isn't available (e.g., pyyaml not installed), find an equivalent (ruby YAML, node YAML, or fallback grep-based structural check).
- If verification fails, diagnose and fix BEFORE reporting DONE.

### 4. Report via agent-bridge

Reply using exactly:

```
agent-bridge send <agent> -- "DONE sliceN: A=<result summary> B=<result summary>; <any concerns or 'no concerns'>"
```

Or if blocked:

```
agent-bridge send <agent> -- "BLOCKED sliceN: <task> because <specific reason>"
```

Include:
- Verification results (exit codes, grep matches, template renders)
- Concerns if you spotted potential issues
- "No concerns" if everything checks out

### 5. Do NOT

- Commit anything
- Touch files not specified in the spec
- Fix unrelated issues you notice (flag them in the DONE reply, but don't fix)
- Skip verification steps
- Reply without running agent-bridge (the orchestrator may not read pane output)

## Patterns observed

### Common verification tools

| Tool | Use | Fallback |
|------|-----|----------|
| `helm template` | Chart syntax + rendering | N/A |
| `ansible-playbook --syntax-check` | Playbook syntax | python3/ruby YAML parse |
| `python3 -c "import yaml; yaml.safe_load(...)"` | YAML validation | `ruby -ryaml -e "YAML.load_file(...)"` |
| `grep -n` | Confirm entries present | manual inspection |

### Common edit types

- **Helm chart values** — replace image blocks, add resource limits
- **Helm templates** — change image refs to consolidated, add resource blocks to each container
- **AWX integration defaults** — add new job template dicts to the `awx_catalog_job_templates` list
- **Catalog YAML** — update `provision.image` block with real digest
- **Playbook creation** — copy existing playbook, simplify (drop vars/tasks not needed), adjust vars
- **Seed playbook vars + list entries** — add vars block entries + corresponding list entries

### Agent-bridge quoting

- **Never use backticks inside the outer double-quoted message** — bash interprets them as command substitutions.
- Use single quotes or plain text for technical terms inside the message.
- The agent-bridge binary receives the full text regardless; bash warnings are cosmetic but noisy.

## Principles

- **Precision over completeness.** Execute the spec exactly; don't fix adjacent issues.
- **Verify before reporting.** Never say DONE without running the verification commands.
- **No commits until the orchestrator reviews.** You're the lifter, not the merger.
- **Mirror existing patterns exactly.** When the spec says "mirror X", copy X's structure verbatim (same indentation, same key order, same var-reference style).
