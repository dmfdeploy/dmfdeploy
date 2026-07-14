---
name: shared-checkout-task-impl
description: Implement a single assigned task from a multi-task plan in a shared component checkout — verify branch, scope to your files only, build-verify, then commit
source: auto-skill
extracted_at: '2026-06-05T16:01:00Z'
type: durable-pattern
scope: agent-workflow
owner: operator
review_by: '2027-01-14'
---

# Single-Task Implementation in a Shared Checkout

When an orchestrator assigns you **one specific task** (e.g. "Task 2 ONLY") from a multi-task plan document, and the target repo is a **shared checkout** (other agents or humans may have uncommitted work), follow this discipline.

## When to use

- You receive a worker task scoped to a single repo (e.g. dmf-init, dmf-cms, dmf-infra)
- The plan doc lists multiple independent tasks — you are assigned only one
- The repo may have pre-existing uncommitted changes from other sessions

## Procedure

### 1. Read the plan, isolate your task

Read the full plan document. Identify **only** your assigned task. Note:
- The acceptance criteria for your task
- Which repo(s) your task touches
- Any gotchas or constraints specific to your task
- **Ignore other tasks completely** — they are for other agents

### 2. Verify repo state before editing

```bash
# Check you are on main (or the expected branch)
git -C <repo> rev-parse --abbrev-ref HEAD

# Check dirty state
git -C <repo> status --short
```

**STOP and report** if the branch is not what was expected (e.g. not `main`). Ask the user before proceeding on a non-standard branch.

If there are uncommitted changes:
- Note which files are modified/untracked
- Your task should only touch files it logically owns
- Pre-existing dirty files are **not yours** to commit unless your task explicitly requires modifying them

### 3. Implement your change

- Read the relevant source files top-to-bottom before editing
- Follow any referenced design docs (e.g. UX Constitution, ADRs)
- For UI changes: prefer the smallest dependency footprint that satisfies the requirement
- Keep your change **additive and scoped** — don't refactor unrelated code

### 4. Build-verify before commit

Run the repo's build or compile step and confirm **zero errors**:

```bash
# For a React/TS frontend:
cd <repo>/frontend && npm run build
# Confirm: no tsc errors, no vite compile errors

# For Python:
cd <repo> && uv run python -m compileall .

# For Ansible:
ansible-playbook <playbook>.yml --syntax-check
```

Do NOT proceed to commit if the build fails.

### 5. Selective staging and commit

```bash
# Stage ONLY the files your task changed
git -C <repo> add <file1> <file2> ...

# Verify what will be committed
git -C <repo> diff --cached --stat

# Commit on main with a clear message
git -C <repo> commit -m "<type>: <one-line summary>

<Body: what changed, why, key decisions>"
```

**Rules for selective staging:**
- Only `git add` files that are part of your task's logical change
- If your task modifies a file that was already dirty from a prior session, stage only the relevant hunks (or ask the user)
- Do NOT bundle pre-existing dirty files into your commit
- Do NOT bundle untracked files that belong to other tasks or sessions
- One task = one commit. Don't split a small task into multiple commits, don't bundle unrelated changes

### 6. Do NOT push

Leave the push decision to the operator/orchestrator. Report:
- The commit SHA
- What changed (files + summary)
- Build result
- Any blockers or notes

## Anti-patterns to avoid

| Anti-pattern | Why it's bad |
|---|---|
| Committing all dirty files | Bundles other agents' or humans' incomplete work into your commit |
| Skipping build verification | A broken build in the commit is invisible to the next agent who fetches from `.git` |
| Implementing multiple tasks | Cross-contaminates git history, makes rollback impossible, blocks other agents |
| Pushing without operator approval | May trigger unintended CI/CD or cluster reconciliation |
| Assuming branch is correct | Always verify — a stale branch means your commit lands on the wrong lineage |

## Example commit message

```
feat(ui): QR code for passkey enrollment URL in bootstrap pause

Add qrcode.react (SVG mode, minimal dep) and render a scannable QR
of payload.enrollment_url alongside the existing copyable URL +
confirmed N/2 status in the passkey pause modal. Include a one-line
caveat that .test domains won't resolve off-network.
```
