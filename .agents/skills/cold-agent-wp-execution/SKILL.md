---
name: cold-agent-wp-execution
description: Execute work packages (WPs) from a plan document across sibling repos with constrained commits and agent-bridge reply protocol
source: auto-skill
extracted_at: '2026-06-07T19:32:00Z'
---

# Cold-Agent Work Package Execution

When an orchestrator dispatches work packages (WPs) from a plan document and expects you to execute them across multiple sibling repos with local-only commits.

## When to use

- The orchestrator sends a plan spec with numbered work packages (WP0, WP1, WP2, …).
- Each WP targets a different sibling repo (e.g., dmf-env, dmf-infra, dmf-init).
- Hard constraints: main branch only, no push, conventional commits, co-authored-by trailers.
- You must reply DONE/BLOCKED with commit hashes via agent-bridge.

## WP0 — Onboarding (always first)

1. **Boot ritual:** `git fetch && git pull` (umbrella), refresh status doc, read the plan spec + most recent handoff + relevant ADRs.
2. **Repo audit:** For each repo mentioned in the WPs:
   - `git -C <repo> rev-parse --abbrev-ref HEAD` — must be `main` (or the required branch)
   - `git -C <repo> status --short` — must be clean; if dirty, STOP and ask
3. **Note hard constraints:** sandbox-only vs all-lanes, what NOT to touch (e.g., passkey assert, cloud-lane behaviour, ADR changes), push/no-push.

## Execution protocol

### Per WP

1. **Read the spec** — understand what files change, what the acceptance test is.
2. **Read target files** — use absolute paths (Glob may not find sibling repos outside the umbrella working dir).
3. **Make changes** — match existing style, indentation, and guard patterns.
4. **Verify before commit:**
   - `bash -n` for shell scripts
   - `npm run build` or equivalent for frontend changes
   - `python3 -c "import yaml; yaml.safe_load(…)"` for YAML
   - Acceptance test from the spec
5. **Verify repo state again:** branch = required branch, no unexpected dirty files.
6. **Commit:** conventional-commit message, end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
7. **Reply via agent-bridge:** `agent-bridge send <agent> -- "DONE WP<n> <hash>"`

### Cross-repo WPs

Some WPs span multiple repos (e.g., WP2: Python change in dmf-infra + wording updates in dmf-env). Treat these as **one logical WP** but commit separately in each repo. Reply with the commit hash from the primary repo, or both hashes.

## Multi-site value replacement pattern

When a hardcoded value appears at multiple sites in a large script (e.g., `${LABEL}.dmf.test` at 3 locations):

1. **Find all sites:** `grep -n <pattern> <file>` to get line numbers.
2. **Add a derivation function** near the top of the relevant section (after helpers, before `validate_inputs` or equivalent).
3. **Replace each site** with a call to the derivation function.
4. **Handle all input paths:** interactive (`collect_inputs_interactive`), non-interactive (`load_inputs_noninteractive`), and validation (`validate_inputs`).
5. **Wire new answers-file fields** in the non-interactive load path.
6. **Update info copy and summary** to reflect the new default.

### Example structure for derive function

```bash
derive_<thing>() {
    # Explicit override wins
    if [ -n "${EXPLICIT_VAR:-}" ]; then
        RESULT="${EXPLICIT_VAR}"
        return 0
    fi

    # Default path (common case)
    if <condition>; then
        RESULT="<derived-value>"
        return 0
    fi

    # Fallback with warning
    warn "<reason for fallback>"
    RESULT="<fallback-value>"
}
```

## agent-bridge reply rules

- **DONE:** `agent-bridge send <agent> -- "DONE WP<n> <hash>"` (or multiple hashes for cross-repo WPs)
- **BLOCKED:** `agent-bridge send <agent> -- "BLOCKED WP<n> <reason>"` and STOP
- **ALL DONE:** After all WPs: `agent-bridge send <agent> -- "ALL DONE — WP1 <hash1>, WP2 <hash2>, …"`
- **No backticks in message body** — bash interprets them as command substitutions inside double-quoted strings. Use plain text or single quotes.
- **Identity mismatch:** If `agent-bridge` refuses due to version mismatch, add `--force` flag.

## Cross-checking referenced commits

When a plan spec references a specific commit hash (e.g., "cross-check e514bd9"):

1. **`git show <hash> --stat`** — see what files changed.
2. **`git show <hash> -- <file>`** — get the actual diff for the relevant file(s).
3. **Compare current file state** — read the file now to understand if later commits superseded or modified that change.
4. **Align, don't duplicate** — if the referenced commit already addressed part of the problem, build on it rather than re-implementing.
5. **If ambiguous** — if the current state makes the intended fix unclear, reply `BLOCKED <repo> <what-you-found>` and let the orchestrator adjudicate instead of guessing.

This is especially important when the referenced commit is recent and the script has ongoing active development.

## Hard constraints (typical)

| Constraint | Why |
|---|---|
| ALL work on `main` | No feature branches — operator merges as-is |
| Do NOT push | Operator does live verification first |
| Sandbox lane ONLY | Don't touch cloud-lane behaviour |
| Don't touch specific asserts/files | Security-critical (e.g., ≥2 passkey assert) |
| No ADR change | Decision frame is unchanged |
| Conventional commits | Standard commit message format |
| Co-Authored-By trailer | Attribution for orchestrated work |

## Common pitfalls

- **Committing on wrong branch** — always verify `git rev-parse --abbrev-ref HEAD` before committing.
- **Syntax errors in shell scripts** — always run `bash -n` before committing bash changes.
- **Missing answers-file wiring** — when adding new inputs, wire them in both interactive prompts AND non-interactive YAML loading.
- **Inconsistent info copy** — update user-facing messages (prompts, summaries) to match the new default behaviour.
- **Not running the build** — frontend changes must include `npm run build` (or equivalent) so they ship in the image.

## Principles

- **Read the full spec before starting.** Don't execute WPs out of order.
- **Verify before every commit.** Branch, clean state, syntax.
- **One WP, one logical change.** Don't bundle unrelated fixes.
- **Reply after each WP.** Don't wait until all are done — the orchestrator may want to verify incrementally.
- **STOP on unexpected dirty state.** Ask the operator before touching another agent's WIP.
