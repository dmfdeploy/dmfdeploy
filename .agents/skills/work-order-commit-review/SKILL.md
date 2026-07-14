---
name: work-order-commit-review
description: Review committed diffs against a work order's acceptance criteria — check correctness, test quality, scope creep, and edge cases before accepting
source: auto-skill
extracted_at: '2026-06-03T15:30:00Z'
type: durable-pattern
scope: review-workflow
owner: operator
review_by: '2027-01-14'
---

# Work-Order Commit Review

A structured review of committed diffs against a work order's acceptance criteria. The goal is to catch correctness bugs, missing requirements, divergent implementations, and meaningless tests *before* the orchestrator accepts the item.

## When to use

- Another agent has committed a work-order item and asked for review.
- You need to verify a diff against explicit acceptance criteria before merging.
- An item has "bonus" changes beyond the work order scope that need scrutiny.

## Procedure

### 1. Ground yourself

Read these in order:
1. **The work order** — the plan doc specifying what to change, where, acceptance criteria, and test requirements.
2. **The commit diff** — `git -C <repo> show <sha>`. Read top-to-bottom.
3. **The cited existing pattern** — if the work order says "mirror X", read X to verify the mirror is faithful.

### 2. Check each acceptance criterion

For every item in the work order's "Acceptance:" line, verify the diff satisfies it. Be explicit:

| Criterion type | What to check |
|---|---|
| **Code correctness** | No KeyError paths, no missing dict entries, no off-by-one, no race conditions |
| **Test quality** | Tests assert *behavior*, not just that code runs. `assert 5 == len(names)` is better than `assert result`. Round-trip tests should actually round-trip. |
| **Pattern fidelity** | If work order says "mirror X", verify the same variable derivation, same guard conditions, same error handling |
| **Guard coverage** | All call sites updated uniformly (no divergent hand-edits). Build the option array once, reuse it. |
| **Backward compatibility** | Agent-only path (no key) still works. Unset env vars fall through gracefully. |
| **Test execution** | Confirm tests were run and passed. `pytest -k <filter>` green, shellcheck clean, `bash -n` at minimum. |

### 3. Scrutinize bonus changes

Items often include changes *beyond* the work order scope. Evaluate each:

1. **Is it correct?** Does it fix a real bug or improve code quality?
2. **Does it change behavior on the live path?** If yes, flag it — the orchestrator should decide.
3. **Does it introduce new dependencies or complexity?** Flag if yes.
4. **Is it orthogonal to the work order?** If it's a valid improvement but out of scope, note it but don't block unless it's risky.

Examples from a real review:
- `TLS_OPT` string → `curl_opts` array: **APPROVE** — fixes word-splitting bug on unquoted string, no behavior change on live path.
- `jq '.sealed // "?"'` → `jq 'if has("sealed") then …'`: **APPROVE** — `//` alternative operator fires on `false`/`null`, masking a missing key; `has()` correctly distinguishes absent from present-but-false.
- Cosmetic if/else split: **NOTE** — no semantic change, neither approve nor block.

### 4. Audit sibling paths

If the work order says "audit path Y for the same issue," verify:
- All call sites in path Y were checked.
- The audit result is reported (e.g., "no bare ssh found" or "fixed N sites").
- No related files were missed.

### 5. Produce the verdict

Reply concisely per item:

```
Item <X> — APPROVE
- <criterion 1 met> ✓
- <criterion 2 met> ✓
- <bonus change 1: correct, no behavior change> ✓
- <audit result> ✓

Item <Y> — CHANGES-NEEDED
- <specific bullet: what's wrong, where, what to fix>
- <specific bullet>
```

**APPROVE** only when all acceptance criteria are met and no risky bonus changes are present.
**CHANGES-NEEDED** with specific, actionable bullets — cite file + line or function name.

### 6. Backend API endpoints (if applicable)

When the diff adds or modifies API endpoints:

| Check | What to look for |
|---|---|
| **Auth/session guard** | `Depends(require_session)` or equivalent on every new endpoint |
| **Error paths tested** | Every `HTTPException` (404, 409, 502, etc.) needs a test, not just the 200 path |
| **Thread safety** | Shared state access (`app.state`, condition variables) inside `bootstrap_lock` or equivalent |
| **Input validation** | Pydantic models or explicit validation on request params |
| **Defensive casting** | `int(payload.get("confirmed", 0) or 0)` — guards against None/missing keys |

### 7. Frontend React/TypeScript (if applicable)

When the diff modifies `.tsx` files:

| Check | What to look for |
|---|---|
| **`shellQuote` / POSIX escaping** | `'${value.replaceAll("'", "'\\''")}'` — must escape single quotes for safe interpolation |
| **External link safety** | `target="_blank"` **must** have `rel="noopener noreferrer"` |
| **Poll-gate logic** | If a button polls an API to gate an action: (a) `confirmed >= required` threshold correct (no off-by-one), (b) no infinite poll loop (single-shot per click), (c) button disabled during check + action (`disabled={checking || busy}`), (d) status reset on re-entry |
| **Error-path UI** | Does the frontend handle 404/409/502 from the API gracefully? `readError` → user-visible error state |
| **Secret exposure in DOM** | Enrollment URLs are fine to show; tokens/keys must not be rendered in DOM, attributes, or copy commands |
| **`present:false` fallback** | When a payload's `present` field is false, show an error note + retry hint — not just blank UI |

### 8. Secrets discipline in live-fetch builders

When builders fetch secrets (CA PEM, enrollment tokens, keys) over SSH or subprocess:

| Check | What to look for |
|---|---|
| **No logging of key material** | CA PEM, private keys, tokens must not appear in `logger.info/debug` or `note` fields on error |
| **Error notes safe** | `note` strings contain generic messages ("could not fetch…") or exception type — not the raw PEM/token |
| **subprocess capture** | `capture_output=True` on `subprocess.run` — stderr/stdout not printed or logged |
| **Redaction** | Known secrets added to the redaction set before any log output |

## Principles

- **Work order is the contract.** Don't invent new criteria; check what's written.
- **Tests must be meaningful.** `assert True` or "file exists" without content checks are not sufficient.
- **Guarded changes > unconditional changes.** Adding `-i "$KEY"` unconditionally breaks agent-based auth; guard by `[ -n "$KEY" ]`.
- **Arrays > strings for option building.** `ssh_opts+=(-i "$KEY")` is safer than `SSH_OPTS="$SSH_OPTS -i $KEY"` (word-splitting, quoting bugs).
- **jq `has()` > `//` for presence checks.** The `//` alternative operator treats `false` and `null` as falsy, which masks the difference between "key absent" and "key present but false."
- **Bonus changes are fine if correct and non-disruptive.** Don't block valid improvements, but flag them so the orchestrator knows.
- **Every HTTPException needs a test.** 200-only test coverage on an API endpoint is incomplete — each error path (404, 409, 502) is a distinct user-facing state.
- **External links must have `rel="noopener noreferrer"`.** Missing this is a security gap (tabnabbing).
- **Poll gates must be single-shot.** No infinite retry loops; operator retries manually.
