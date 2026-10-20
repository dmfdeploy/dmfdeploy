---
status: executed
date: 2026-08-04
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/355
executed: 2026-08-04
---
# DMF Agent Conversation Recording Format Plan

> **STATUS: EXECUTED.** Deliverable of umbrella
> [#355](https://github.com/dmfdeploy/dmfdeploy/issues/355).

## Outcome

Two things shipped, both under `.agents/skills/`:

1. **`agent-conversation-recording`** — a format specification for writing an
   agent-to-agent exchange down. It fixes a schema version, a closed metadata
   schema, one turn-header grammar, and objective conversation boundaries. Its
   structural decision is that the binding result lives in record metadata and
   never in a turn body, because turn bodies routinely quote earlier results and
   nothing in the text distinguishes a quotation from the thing itself.

2. **Five anti-churn rules** in `issues-cruncher/references/anti-churn-rules.md`,
   wired into hard gate 8 and phases 3–4 as an explicitly delimited payload so
   "paste verbatim" has one meaning. Each rule is justified by the failure mode
   it prevents.

**Scope, deliberately:** the format specification is format-only, and this
document observes the same rule — public artifacts carry outcomes and findings
only; records themselves are not their subject.

## Why the rules travel in dispatch text

A rule an agent is expected to recall is enforced by attention, which degrades
as a session lengthens. Recall is not enforcement. A rule that must survive a
long session belongs in the text of each dispatch, re-read at the moment of use.

## What is not here

An earlier attempt at this work was reverted. The cause was not that it had a
plan document — it was that the document said things a public artifact must not
say. The format specification itself was never at fault and returns unchanged
in substance.

Four design gaps found during that review are closed in this delivery: the
terminal-outcome vocabulary is now per-record-type rather than one shared enum;
the pending-to-terminal lifecycle is defined; the work-item grammar admits one
form only; and a format-only scope claim no longer mandates label management.

**Deferred, and not part of this plan:** the larger mechanism the format was
originally drafted to serve is not approved and is not being built. Nothing here
depends on it.

## Verification

- `bin/sync-skills.sh --check` — canonical-only invariant holds.
- `bin/check-docs.sh` — clean.
- Public-surface check run as the semantic question the rule names, not only as a
  literal search, because the two answer different questions.
