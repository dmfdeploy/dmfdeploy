---
name: discriminating-test-design
description: Design tests that FAIL on old code and PASS on new code; use real-data dry-runs as independent verification for extractors/Matchers
source: auto-skill
extracted_at: '2026-06-12T15:30:00Z'
type: durable-pattern
scope: verification
owner: operator
review_by: '2027-01-14'
---

# Discriminating Test Design

When adding a regression test for a guard, validator, or matcher, the test must **discriminate**: it must FAIL on the old code and PASS on the new code. A test that passes vacuously (identical result on both old and new code) is worse than no test — it gives false confidence.

## The discrimination question

Before writing a test, ask: **"What would the OLD code do differently under this test?"**
If the answer is "nothing," the test is not discriminating.

## Pattern: descendant-spawning regression test

When the fix involves killing subprocesses (e.g., process-group termination on client disconnect), a single-process fake is not enough. The OLD code killed only the parent; the NEW code kills the whole group. A test that spawns only one process would pass on both.

**Discriminating design:** the fake spawns a BACKGROUND DESCENDANT that performs a side-effect (writes a sentinel file) after a delay, while the parent stays alive:

```bash
#!/bin/sh
echo 'starting'           # parent yields one line
sh -c 'sleep 2; touch SENTINEL' &  # descendant
sleep 60                   # parent stays alive
```

Test: advance the generator once (wizard running), close it (GeneratorExit), wait 3s, assert sentinel NOT written.
- OLD code: kills parent only → descendant survives → writes sentinel at t=2 → **FAIL**
- NEW code: kills entire process group → descendant dies → no sentinel → **PASS**

## Pattern: regex/matcher false-positive test

When building an extractor or matcher (e.g., GitHub close-keyword regex), the naive version often over-matches. Tests must include cases that the OLD regex wrongly accepts:

| Input | Expected | Naive regex catches it? |
|-------|----------|------------------------|
| `"Closes #20"` | 20 | yes |
| `"Closes dmfdeploy/dmfdeploy#20"` (component PR) | 20 | yes |
| `"Closes #5"` (component PR, bare) | {} | often wrongly matches |
| `"Refs dmfdeploy/dmfdeploy#20"` | {} | often wrongly matches |
| `"Closes dmfdeploy/dmf-env#3"` (wrong repo) | {} | often wrongly matches |
| `"review fixed 5 bugs"` (no `#`) | {} | often wrongly matches |

The last case caught a real false-close in production dry-run: `"fixed 5"` matched as `"fixed #5"` because the `#` was optional in the regex (`#?[0-9]+`).

## Independent verification: real-data dry-run

Self-tests alone are not enough. Always run the tool against **real data** (a dry-run) as an independent check. The real-data dry-run on #47 caught the false-close on umbrella #5 (via "review fixed 5 bugs") that all self-test cases missed — because the self-tests all used `#N` forms, never testing bare numbers.

**Rule:** for any tool that scans real data and takes action, the first run MUST be a dry-run. Review the dry-run output for false positives before enabling apply mode.

## Flagging self-authored tests

If you (the implementer) authored both the fix and its discrimination test, flag this in your DONE report so the orchestrator can route the test for independent review. Self-authored tests can have blind spots — a second pair of eyes catches vacuous assertions.

## Common false-positive patterns

| Bug | What the extractor did wrong | Fix |
|-----|----------------------------|-----|
| Bare number match | `#?[0-9]+` matched "fixed 5 bugs" | Require `#`: `#[0-9]+` |
| Refs treated as closes | `"refs"` keyword extracted issue numbers | Only match close-keywords (close\|closes\|closed\|fix\|fixes\|fixed\|resolve\|resolves\|resolved) |
| Bare #N in component PRs | `"#5"` in a component-repo PR mapped to umbrella #5 | Bare #N only counts for umbrella-repo PRs; component PRs need qualified form `org/repo#N` |
| Wrong repo qualified | `"org/dmf-env#3"` mapped to umbrella #3 | Only `org/dmfdeploy#N` maps to umbrella |
| Unbounded substring match | `"unresolved #47"` matched because "unresolved" contains "resolved" | LEFT word boundary: keyword must be at line start or preceded by non-alphanumeric char `(^|[^[:alnum:]])(keyword)` |
| Negation bypass via sed slashes | `sed "s/${ref}//i"` failed silently on `dmfdeploy/dmfdeploy#5` (slashes broke sed delimiter) | Use bash literal prefix strip: `${body%%"$ref"*}` |
