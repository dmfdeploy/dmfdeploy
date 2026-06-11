# DMF Agentic Harness — Issue Templates

> **Authority**: Canonical issue body shape + label taxonomy + worker
> reply-token grammar. Enforced by `bin/agentic/issue-open.sh` validation
> (K4 deliverable; not yet implemented). Constitution Rules 11–13 bind agents
> to this file.
>
> **Source spec**:
> [`DMF Agentic Harness Plan`](../plans/DMF%20Agentic%20Harness%20Plan%202026-05-11.md)
> §Layer 4 "Issue substrate".

---

## Label taxonomy

All labels enforced at submit-time by `issue-open.sh`. Missing/extra → reject.

| Label | Cardinality | Values |
|---|---|---|
| `agent-opened` | always | (fixed; distinguishes from operator-opened) |
| `type:<kind>` | exactly 1 | `workaround` \| `feature` \| `bug` \| `decision-requested` |
| `scope:<repo>` | ≥ 1 | `umbrella` \| `dmf-cms` \| `dmf-infra` \| `dmf-central` \| `dmf-media` \| `dmf-runbooks` (`dmf-env` **forbidden** per Constitution Rule 13) |
| `pickup:<state>` | exactly 1 | `ready` \| `blocked` \| `in-progress` \| `deferred` |
| `effort:<size>` | exactly 1 | `S` \| `M` \| `L` |
| `public-safe` | optional | set *only* by `issue-migrate-to-github.sh` after re-scrub; **never** at open time |

Type semantics:

- `type:workaround` — agent bodged to keep moving; needs proper fix later.
  Body MUST include a `## Proper fix` section.
- `type:feature` — queued feature work for later pickup. Body MUST include
  acceptance criteria.
- `type:bug` — observed defect, not yet diagnosed. Body MUST include repro
  steps + observed/expected.
- `type:decision-requested` — ADR-worthy fork that surfaced mid-work, but
  work itself isn't blocked. (Use `decisions-open.md` when work IS blocked.)

Pickup semantics:

- `pickup:ready` — has all context; another agent can take it without
  asking. This is the only state from which `issue-promote.sh` will promote
  into `backlog.yaml`.
- `pickup:blocked` — depends on an open decision or another issue. Body
  MUST link the blocker in §Related.
- `pickup:in-progress` — promoted to `backlog.yaml`; entry there has
  `status: in-progress`.
- `pickup:deferred` — explicitly out of scope for current phase.

---

## Issue body template

All six sections REQUIRED. Empty sections → reject. Cross-repo scope → reject
with instruction to file per-repo issues + a tracker.

```markdown
## Context
What the agent was doing, why this came up. Reference plans/ADRs/handoffs.

## Acceptance
Explicit, testable criteria. What does "done" look like? Use a checklist
when there are multiple gates.

## Scope
- repo: <repo-name from the scope: label set>
- files: <path1>, <path2>, ...
- skill (if any): <skill-name from CLAUDE.md "skill-guarded operations">

## Constraints
Things the picker-upper MUST NOT change. ADR refs that bind the work.

## Decision points
Any ADR-worthy gates ahead (or "none"). If non-empty, this issue likely
needs `type:decision-requested` and a corresponding entry in
`decisions-open.md`.

## Related
- ADR: <id-or-none>
- Plan: <path-or-none>
- Handoff: <path-or-none>
- Issues: #<id> (related/blocks/blocked-by — use Forgejo's native cross-link
  syntax)
```

---

## Worker reply tokens

Qwen panes never call `issue-open.sh` directly (Constitution Rule 11).
Instead, the reply to the orchestrator's `agent-bridge ask` carries a
structured token that the orchestrator parses, scrub-validates, and opens.

If a reply doesn't parse cleanly, the orchestrator sends it back to the
worker for refinement — never improvises the missing fields.

### Token 1 — `WORKAROUND`

Use when: worker had to bodge to keep moving; needs a proper fix later.

```
WORKAROUND: <one-line summary>
RATIONALE: <why the bodge was needed>
PROPER-FIX: <what should happen later>
SCOPE: repo=<repo>, files=<...>
RELATED: ADR=<id-or-none>, plan=<path-or-none>
```

Produces: `type:workaround` issue. Backlog entry continues (workaround
applied); issue links from the entry.

### Token 2 — `BLOCKED`

Use when: worker cannot proceed without external input.

```
BLOCKED: <one-line summary>
BLOCKER-KIND: missing-dependency | unknown-state | upstream-bug | needs-decision
DETAILS: <free text; MUST use placeholder syntax for IPs/hostnames>
SCOPE: repo=<repo>, files=<...>
RELATED: ADR=<id-or-none>, plan=<path-or-none>
```

Produces: `type:workaround` (kind != needs-decision) **or** entry to
`decisions-open.md` (kind == needs-decision). Backlog entry → `blocked`;
issue is the blocker.

### Token 3 — `FEATURE-GAP`

Use when: worker noticed missing functionality while doing unrelated work.

```
FEATURE-GAP: <one-line>
DISCOVERED-WHILE: <backlog task id>
WHY-DEFERRED: not-in-v0.1.0-scope | needs-design | external-dependency
SCOPE: repo=<repo>, files=<...>
RELATED: ADR=<id-or-none>, plan=<path-or-none>
```

Produces: `type:feature` issue with `pickup:deferred` (default) or
`pickup:ready` (if WHY-DEFERRED is `not-in-v0.1.0-scope` but otherwise
shovel-ready). Backlog entry continues; issue is filed as deferred
discovery.

### Token 4 — `BUG`

Use when: worker observed a defect (in code or in cluster state).

```
BUG: <one-line>
OBSERVED: <what happened>
EXPECTED: <what should have happened>
REPRO: <minimal steps; placeholder syntax mandatory>
SCOPE: repo=<repo>, files=<...>
```

Produces: `type:bug` issue. Backlog entry status depends on severity:
- Bug is in the path of the current task → backlog → `blocked`, issue is
  the blocker.
- Bug is adjacent (noticed but not blocking) → backlog continues; issue is
  filed for later triage.

### Token 5 — `DECISION-NEEDED`

Use when: worker hit a fork the orchestrator should not resolve.

```
DECISION-NEEDED: <one-line>
OPTIONS: A: <description>; B: <description>; C: <description>
RECOMMENDATION: <which option, or "no preference">
SCOPE: repo=<repo>, files=<...>
```

Produces: entry in [`decisions-open.md`](decisions-open.md) **and**
`type:decision-requested` issue if the decision benefits from a Forgejo
discussion thread. Backlog entry → `blocked`; decisions-open.md is the
operator's halt-surface.

---

## Drift firebreaks (all enforced by `issue-open.sh`)

1. **Title regex**: `^[A-Za-z][A-Za-z0-9 :_/.\-]{4,80}$`. No `<placeholder>`
   syntax in titles (placeholders allowed in body only; titles must be
   self-describing).
2. **Scrub gate**: full body + title piped through
   `bin/scrub-public-repos.sh --stdin` + `gitleaks detect --no-git --pipe`.
   Any hit → reject; agent rewrites with placeholder syntax per
   Constitution Rule 8.
3. **Dup-check**: fuzzy-match title against open `agent-opened` issues
   (Levenshtein ≤ 5 OR ≥ 80% token-overlap) → reject with the candidate's
   `#<id>` cited so the agent comments on the existing issue instead.
4. **Stale-ref check**: every commit hash in the body must resolve via
   `git cat-file -e <sha>`. Amended/rebased-away hashes → reject.
5. **Cross-repo enforcement**: `scope:` label set spanning > 1 repo → reject
   with instruction to file one issue per repo plus a tracker issue
   (`type:feature`) linking them.
6. **Required body sections**: Context / Acceptance / Scope / Constraints /
   Decision points / Related. Each must be non-empty.
7. **Label-set validation**: exactly 1 `type:`, ≥ 1 `scope:` (none being
   `dmf-env`), exactly 1 `pickup:`, exactly 1 `effort:`, plus
   `agent-opened`.
8. **Body length cap**: 8 KB. Larger → reject (issue is the index, not the
   document — link to a handoff or plan if more context is needed).

---

## Migration to GitHub at v0.1.0 publish

Operator-invoked, never by the loop:

```
bin/agentic/issue-migrate-to-github.sh --dry-run
```

Re-runs scrub on each `agent-opened` issue body + comments. Issues that pass
get `public-safe`; the operator approves the migration list; approved issues
mirror to GitHub via `gh issue create`. Forgejo issue stays open as the
canonical work record with `Mirror: gh#<id>` line in the body; GitHub is the
public face.

This script does not exist yet (K4 deliverable). Until it does, the
`public-safe` label is reserved and unused.
