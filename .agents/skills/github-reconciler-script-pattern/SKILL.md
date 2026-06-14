---
name: github-reconciler-script-pattern
description: Build safe, dry-run-default bash reconciler scripts that query GitHub APIs, extract issue/PR references, and perform idempotent state changes — with self-test, shellcheck, actionlint, and real-data dry-run as independent checks
source: auto-skill
extracted_at: '2026-06-12T16:27:40.107Z'
---

# GitHub Reconciler Script Pattern

When building bash scripts that query GitHub APIs to detect and reconcile state mismatches (e.g., auto-closing orphan-open issues, syncing labels, detecting drift), follow this pattern.

## When to use

- Auto-closing tracking issues whose completing PRs merged but GitHub didn't auto-close them
- Detecting stale or drifted state across repos/boards
- Batch-closing, labeling, or editing issues/PRs based on API query results
- Any script that reads GitHub data and performs mutations via `gh` CLI

## Safety defaults

- **Default to dry-run.** The script MUST NOT mutate state without an explicit `--apply` flag.
- **`--dry-run` is the default mode** (no flag needed). `--apply` must be explicit.
- **Idempotent:** running multiple times produces the same result; skip already-correct state.
- **No mutations in self-test mode.** `--self-test` runs unit tests only, no API calls.

## Structure

```
bin/reconciler.sh
  |-- Constants (ORG, repos, patterns)
  |-- Helpers (gh_json wrapper, extraction functions)
  |-- Self-test (--self-test subcommand)
  |-- Argument parsing (--dry-run/--apply/--self-test/--help)
  |-- Core logic: find_candidates() -> act on candidates
```

## Extractor function — unit-testable

Factor the body-to-reference extraction into a standalone function that takes `(body, context)` and prints one reference per line. This makes it unit-testable without API calls.

```bash
extract_references() {
    local body="$1"
    local context="$2"  # e.g. PR repo slug, for disambiguation

    # grep -ioE to find patterns, while/sed to classify, echo to stdout
    # One reference per line, deduplicated by caller (sort -u)
}
```

## Critical extraction rules (learned from false-close incidents)

### Require the # prefix — never #?[0-9]+

GitHub's issue reference syntax requires `#`. A bare digit after a close-keyword in prose ("fixed 5 bugs") will falsely match as "fixed #5" with `#?`.

```bash
# WRONG — matches bare numbers in prose
grep -ioE "(fixes)[[:space:]]*#?[0-9]+"

# CORRECT — requires #
grep -ioE "(fixes)[[:space:]]*#?[a-zA-Z0-9._-]+?#[0-9]+"
```

### Per-match negation, not per-line

A line like "do not fix #3 but closes #5" has both a negated and a positive reference. Check negation per-match: for each candidate keyword+ref pair, check only whether THAT specific keyword is negated.

```bash
# CORRECT — bash literal prefix strip, no regex, works with refs containing slashes
NEGATION_RE="(not|n'?t|won'?t|can'?t|cannot|will[[:space:]]+not|do[[:space:]]+not)[[:space:]]+"
before="${body%%"$ref"*}"        # literal prefix match, no regex escaping needed
before_line="$(printf '%s' "$before" | awk 'END{print}')"  # text on the ref's own line
if [ -n "$before_line" ] && echo "$before_line" | grep -iqE "(${NEGATION_RE})$"; then
    continue  # negated — skip this match
fi
```

**WRONG:** `sed "s/${ref}//i"` — when `$ref` contains slashes (qualified refs like `dmfdeploy/dmfdeploy#5`), sed errors out (suppressed by `2>/dev/null`), `before` is empty, and the negation check is silently skipped → false close. Eliminate regex substitution entirely; use bash literal prefix strip.

### LEFT word boundary — require real boundary before close-keywords

Close-keywords are matched as UNBOUNDED SUBSTRINGS by default. "unresolved #47" contains "resolved #47" → becomes a close candidate; same for "unfixed #3" (contains "fixed"), "hotfixes #9" (contains "fixes"). GitHub would not close on any of these.

Use a portable LEFT word boundary (do NOT rely on `\b` — BSD vs GNU grep differ):

```bash
# CORRECT — keyword must be at line start or preceded by a non-alphanumeric char
refs="$(echo "$body" | grep -ioE "(^|[^[:alnum:]])(${CLOSE_KEYWORDS})[[:space:]]*#[0-9]+")"
# grep -o includes the boundary char; strip it downstream:
ref="$(echo "$ref" | sed 's/^[^[:alnum:]]//')"
```

### Repo-qualified references disambiguation

A bare `#N` in a component-repo PR refers to that repo's issues, not the umbrella's. Only accept `dmfdeploy/dmfdeploy#N` (qualified form) from component repos.

## Reopen guard — don't re-close deliberately reopened issues

When closing an issue based on a PR that merged at time M, check the issue timeline for a `reopened` event NEWER than M. If the issue was reopened after that PR merged, a human deliberately reopened it — skip it.

```bash
reopened_at="$(gh api -R "$REPO" repos/$REPO/issues/$N/events \
    --jq '[.[]|select(.event=="reopened")]|last|.created_at' 2>/dev/null || true)"
if [ -n "$reopened_at" ] && [ "$reopened_at" \> "$pr_merged_at" ]; then
    echo "  · SKIP #$N (reopened after PR merged)"
    continue
fi
```

Apply this guard in BOTH `--dry-run` and `--apply` modes so the dry-run output reflects actual behavior.

## Self-test subcommand

Include a `--self-test` mode that runs the extractor function against discriminating test cases (cases that FAIL on the old/naive regex, PASS on the correct one):

```bash
run_self_test() {
    assert() {
        local actual="$(extract_references "$2" "$3" | sort -un | tr '\n' ' ' | sed 's/ *$//')"
        [ "$actual" = "$4" ] && echo "  PASS  $1" || echo "  FAIL  $1: expected '$4', got '$actual'"
    }
    assert "bare #N in umbrella repo"     "Closes #20"              "dmfdeploy/dmfdeploy"   "20"
    assert "bare #N in component repo"    "Closes #5"               "dmfdeploy/dmf-infra"   ""
    assert "bare number in prose"         "fixed 5 bugs"            "dmfdeploy/dmfdeploy"   ""
    assert "negated close"                "do not fix #5"           "dmfdeploy/dmfdeploy"   ""
    assert "refs keyword (not a close)"   "Refs dmfdeploy/dmfdeploy#20" "dmfdeploy/dmf-cms" ""
}
```

## Real-data dry-run as independent check

Unit tests can't catch all false-match patterns. Always run `--dry-run` against real API data as an independent check — this is what caught the `#?` false-close bug that all self-test cases missed (because every self-test case included `#`).

## Verification gate

Before reporting DONE:

1. `bash bin/reconciler.sh --self-test` — all PASS
2. `shellcheck bin/reconciler.sh` — clean
3. `actionlint .github/workflows/reconciler.yml` — clean (if a workflow exists)
4. `bash bin/reconciler.sh --dry-run` — review proposed actions, confirm correct

## Workflow pattern

Mirror existing workflow conventions (like `backlog-hygiene.yml`):

```yaml
on:
  schedule:
    - cron: "0 6 * * *"
  workflow_dispatch:
  pull_request:
    types: [closed]

permissions:
  contents: read
  issues: write

jobs:
  reconcile:
    if: github.event_name != 'pull_request' || github.event.pull_request.merged == true
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@<sha>
        with:
          persist-credentials: false
      - run: bin/reconciler.sh --apply
        env:
          GH_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

The merged-gate on `pull_request` ensures the workflow only runs on actual merges, not on PRs that were simply closed without merging.

## Common pitfalls

| Pitfall | Symptom | Fix |
|---------|---------|-----|
| `#?[0-9]+` regex | "fixed 5 bugs" matches as issue #5 | Require `#[0-9]+` |
| Unbounded substring match | "unresolved #47" matches "resolved" keyword | LEFT word boundary: `(^|[^[:alnum:]])(keyword)` |
| Per-line negation | "do not fix #3 but closes #5" drops both | Per-match negation check |
| sed with slash-containing ref | `sed "s/${ref}//i"` fails silently on `dmfdeploy/dmfdeploy#5` | Bash literal prefix strip: `${body%%"$ref"*}` |
| No reopen guard | Re-closing deliberately reopened issues | Check timeline events, compare timestamps |
| dry-run/apply drift | Different candidate sets in each mode | Single `find_candidates()` function, called identically |
| Unquoted `${var}` in gh api | Glob/word-splitting errors | Quote all variable expansions |
| `set -e` with `[ "$x" -gt 0 ] && echo` | Exit 1 when x=0 | Use `if` blocks instead of `&&` chains |
