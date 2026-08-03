---
name: agent-conversation-recording
description: Format spec for recording an agent-to-agent exchange as a durable record — turn-header grammar, authoritative-verdict placement, record metadata schema, and conversation boundaries. Use whenever an orchestrator dispatches to another agent (work order, adversarial gate, consult) and the exchange is written down.
type: operational-procedure
scope: agent-workflow
owner: operator
review_by: '2027-02-03'
source_ref: https://github.com/dmfdeploy/dmfdeploy/issues/355
---

# Agent conversation recording — format

**Scope: this skill specifies a text format and nothing else.** Where records
are written, how they are transported, and how they are later read are all out
of scope by design — see § Pointer direction.

Schema version: **1**. A record states `**Schema:** 1` so a later reader knows
which grammar to apply.

## Why a fixed grammar

Without one, records drift within weeks — turn headers acquire several
incompatible shapes, verdict wording varies by author, classification is
skipped, and the boundary of "one conversation" moves. The cost is not
aesthetic: it makes records unreadable in bulk, and makes any count derived from
them wrong in a direction nobody notices.

## Record metadata

Every record opens with exactly these keys, one per line, in this order:

```
**Schema:** 1
**Date:** YYYY-MM-DD
**Participants:** <role> (<model>) ↔ <role> (<model>)
**Mechanism:** bridge-pane | one-shot-exec | subagent
**Type:** review | implementation | consult | orchestration
**Work item:** <full URL> | none
**Outcome:** PASS | FAIL | ACCEPTED | ABANDONED | pending
**Turns:** <integer>
```

Rules, all mandatory:

- **`Mechanism` and `Type` are closed enums.** Exactly one value, no prose.
- **`Work item`** is a single full URL, or the literal `none`. For more than one,
  repeat the key on consecutive lines. A bare `#N` or `repo#N` is forbidden — it
  silently re-targets wherever the record happens to live.
- **`Outcome`** is a closed enum. `pending` until the exchange concludes.
- **`Turns`** must equal the number of turns actually present.
- Apply the label matching `Type`. **The four labels must exist before they can
  be applied** — create them once. An unlabelled corpus is usually a missing
  prerequisite, not author negligence.

## Turn grammar

One turn per entry, chronological. Each opens with exactly this line — unicode
arrow, all three fields, ISO-8601 timestamp with offset:

```
**[<sender> → <recipient>]** <mechanism>, <model>, <YYYY-MM-DDTHH:MM:SS±HH:MM>
```

Then the verbatim content. **No editing, no summarising.** One mechanical
normalization is required: rewrite every issue/PR reference to a full URL.

## The authoritative verdict lives in metadata, never in a turn

A gate's binding result is the record's `**Outcome:**` field. **Turn bodies are
verbatim content and carry no authority**, even when they contain something that
looks like a verdict.

This is structural, not stylistic. Turn bodies routinely quote earlier verdicts —
a dispatch cites the round it answers — so identifying "the verdict" by scanning
bodies double-counts, by a factor that varies per conversation. Putting the
binding result in one metadata field removes the ambiguity rather than asking
each reader to resolve it:

> **Read `Outcome` for the result. Never derive a result, or a count of results,
> by pattern-matching turn bodies.**

Verdict wording inside a turn is free-form precisely because it is non-binding;
the enum in `Outcome` is what must be exact.

**Binary, not graded.** For a gate, `Outcome` is `PASS` or `FAIL`. There is no
"changes needed" and no "narrow pass": a gate is a merge decision, and merge is
binary. Severity belongs in the *ranked findings* inside the turn, where it is
actionable — a FAIL carrying only low-severity findings is still a FAIL, and the
ranking says how cheaply it clears.

## Conversation boundaries

**One record per conversation**, delimited objectively:

> A new record starts when the **work item changes**, or when the exchange
> resumes after the receiving agent's context was reset.

Both are observable facts, not judgement calls. A long unbroken exchange on one
work item is one record however many turns it runs to; two work items are two
records even if minutes apart. Do not batch a day's exchanges into one record —
"same day" is not a conversation boundary.

## Pointer direction (hard)

**A record may link out to public work items. No public artifact may point back
at where records are kept.**

The asymmetry is deliberate, and it binds this skill too: this file is
public-trajectory content, which is why it specifies a format and says nothing
about storage, transport, retrieval, or tooling. A pointer to a non-public
location is itself the disclosure — it leaks even when the content does not, and
"the location is not named, only described" is not a defence.

Public artifacts — issues, PRs, commit messages, ADRs, plan docs, this skills
tree — carry **outcomes and findings only**. "Adversarial review returned FAIL
with four P1 findings" is a fact about the work and is fine. Anything
characterising where or how the exchange was retained is not.

> **Scrub before publishing, never after.** Platforms retain edit revisions and
> expose them to anyone who can read the artifact, so editing a published
> artifact does not unpublish what it said. If something should not have been
> written, the artifact has to go — not just its current text.

## Related

- `agent-bridge` — the transport this records.
- `issues-cruncher` — the orchestration loop whose exchanges get recorded; its
  `references/anti-churn-rules.md` covers what a dispatch must contain.
