---
name: agent-conversation-recording
description: Format spec for writing an agent-to-agent exchange down as a record — turn-header grammar, authoritative-outcome placement, record metadata schema, and conversation boundaries. Use whenever an orchestrator dispatches to another agent (work order, adversarial gate, consult) and the exchange is written down.
type: operational-procedure
scope: agent-workflow
owner: operator
review_by: '2027-02-03'
source_ref: https://github.com/dmfdeploy/dmfdeploy/issues/355
---

# Agent conversation recording — format

**Scope: this skill specifies a text format and nothing else.** What is done
with a record after it is written, and any tooling around one, is out of scope
by design — see § Pointer direction.

Schema version: **1**. A record states `**Schema:** 1` so a later reader knows
which grammar to apply.

## Why a fixed grammar

Without one, records drift within weeks — turn headers acquire several
incompatible shapes, outcome wording varies by author, classification is skipped,
and the boundary of "one conversation" moves. The cost is not aesthetic: a reader
who cannot tell a binding result from a quoted one cannot trust any result they
read, and the ambiguity is silent — nothing about a drifted record looks wrong.

## Record metadata

Every record opens with exactly these keys, one per line, in this order:

```
**Schema:** 1
**Date:** YYYY-MM-DD
**Participants:** <role> (<model>) ↔ <role> (<model>)
**Mechanism:** bridge-pane | one-shot-exec | subagent
**Type:** review | implementation | consult | orchestration
**Work item:** <full URL> | none
**Outcome:** <see § Outcome> | pending
**Turns:** <integer>
```

Rules, all mandatory:

- **`Mechanism` and `Type` are closed enums.** Exactly one value, no prose.
- **`Turns`** must equal the number of turns actually present.

### Work-item grammar — one form only

**One work item per record.** A record carries exactly one `**Work item:**` line,
holding one full URL or the literal `none`.

- The key appears **once**. Never repeated, never a comma- or space-separated
  list — a second work item means a **second record**, by the boundary rule
  below.
- A bare `#N` or `repo#N` is **forbidden**: it silently re-targets to wherever the
  record is read, which is the failure the full URL exists to prevent.

This is the same fact as the conversation boundary, stated from the metadata
side: if the work item changes, the record ends. A record listing two work items
would contradict its own boundary.

## Outcome

`Outcome` is a closed enum, and **which values are legal depends on `Type`**. A
single vocabulary across all four types was the gap in schema 1's first draft:
gates conclude PASS/FAIL, but a work order concludes DONE/BLOCKED and a consult
concludes with no verdict at all, so one shared enum forced authors to either
misreport or invent wording.

| `Type` | Terminal `Outcome` — the complete permitted set |
|---|---|
| `review` | `PASS` / `FAIL` / `ABANDONED` |
| `implementation` | `DONE` / `BLOCKED` / `ABANDONED` |
| `consult` | `ANSWERED` / `ABANDONED` |
| `orchestration` | `ACCEPTED` / `ABANDONED` |

Each row is the **complete** set for that `Type`; a value outside its row is
invalid. `ABANDONED` appears in every row deliberately — an exchange that
stopped without concluding is abandoned, not failed, and recording it as `FAIL`
(or `BLOCKED`) asserts a result nobody reached.

Meanings: `review` is a gate, so its result is a merge decision. `implementation`
is a work order — the work landed, or it could not proceed. `consult` is
advisory: it carries no verdict and gates nothing. `orchestration` is a
coordination exchange that concluded or was dropped.

**Other vocabularies stay in the turn body.** Protocols in use elsewhere say
"green / gaps / blocked", "CHANGES-NEEDED", and similar. Those are free-form turn
content and remain verbatim — the author maps to the enum above when filling in
metadata. That is safe precisely because turn bodies carry no authority
(§ The authoritative outcome).

### Lifecycle: `pending` → exactly one terminal

- A record is created with `**Outcome:** pending`.
- When the exchange concludes, `pending` is **replaced** by exactly one terminal
  value from the row matching its `Type`. Never appended to, never two values.
- A record whose exchange has ended **must not remain `pending`**. A stale
  `pending` is indistinguishable from an exchange still in flight.
- After a terminal value is set the record is closed. If work resumes, that is a
  **new record** — by the boundary rule below, resumption implies either a
  changed work item or a context reset, and both start a record.

**A gate that reaches a verdict is binary, not graded.** When a `review`
concludes, `Outcome` is `PASS` or `FAIL` — never "changes needed", never a
"narrow pass". A gate is a merge decision and merge is binary. Severity belongs
in the *ranked findings* inside the turn, where it is actionable: a FAIL
carrying only low-severity findings is still a FAIL, and the ranking says how
cheaply it clears.

`ABANDONED` is not an exception to that rule, because it is **not a verdict**.
It records that the exchange stopped before any verdict was reached — the gate
did not return a lenient result, it returned none. So for a `review` the three
legal values are exactly: `PASS`, `FAIL` (a verdict was reached, and it is
binary) or `ABANDONED` (no verdict was reached). A validator needs no special
case: the row in the table above is the complete permitted set for every
`Type`, and the binary rule constrains only which *verdicts* exist, not whether
one was reached at all.

## Turn grammar

One turn per entry, chronological. Each opens with exactly this line — unicode
arrow, all three fields, ISO-8601 timestamp with offset:

```
**[<sender> → <recipient>]** <mechanism>, <model>, <YYYY-MM-DDTHH:MM:SS±HH:MM>
```

Then the verbatim content. **No editing, no summarising.** One mechanical
normalization is required: rewrite every issue/PR reference to a full URL.

## The authoritative outcome lives in metadata, never in a turn

A gate's binding result is the record's `**Outcome:**` field. **Turn bodies are
verbatim content and carry no authority**, even when they contain something that
looks like a verdict.

This is structural, not stylistic. Turn bodies routinely quote earlier results —
a dispatch cites the round it answers — so identifying "the result" by scanning
bodies finds both the real one and every quotation of it, and nothing in the text
distinguishes them. Putting the binding result in one metadata field removes the
ambiguity rather than asking each reader to resolve it:

> **Read `Outcome` for the result. Never derive a result, or a count of results,
> by pattern-matching turn bodies.**

Fencing a quotation does not solve this — a fenced quotation still contains a
verdict-shaped line. Result wording inside a turn is free-form precisely because
it is non-binding; the enum in `Outcome` is what must be exact.

## Conversation boundaries

**One record per conversation**, delimited objectively:

> A new record starts when the **work item changes**, or when the exchange
> resumes after the receiving agent's context was reset.

Both are observable facts, not judgement calls. A long unbroken exchange on one
work item is one record however many turns it runs to; two work items are two
records even if minutes apart. Do not batch a day's exchanges into one record —
"same day" is not a conversation boundary.

## Pointer direction (hard)

**A record may cite public work items. No public artifact cites a record.**

Records are written to a local transcript repo, and that sentence is the full
extent of what a public artifact may say about it — by operator ruling. No
name, host, path, platform, tooling, size, or any other specifics, and no
prose from which a reader could recover them. "It is only described, not
named" is no defence — describing and naming say the same thing.

The direction is one-way by design, and it binds this skill too: this file says
how a record is written, plus the one sentence above, and nothing else about
what is done with one afterwards. The same boundary holds for every public
artifact — issues, PRs, commit messages, ADRs, plan docs, this skills tree.
They carry **outcomes and findings only**: "adversarial review returned FAIL
with four findings" is a fact about the work and is fine; anything beyond the
permitted sentence about records is not.

> **Scrub before publishing, never after.** Platforms retain edit revisions and
> expose them to anyone who can read the artifact, so editing a published artifact
> does not unpublish what it said. If something should not have been written, the
> artifact has to go — not just its current text.

**A PR body and a commit message are public artifacts under this rule**, exactly
like the diff is. Check them before opening, not after.

**Check the property the rule names.** This rule is semantic: it is about what a
reader can *infer*. A word-boundary search for individual tokens answers a
different, narrower question, and passing it says nothing about this one. A
green check on the easier property is not evidence about the harder one.

## Related

- `agent-bridge` — the transport this records.
- `issues-cruncher` — the orchestration loop whose exchanges get recorded; its
  `references/anti-churn-rules.md` covers what a dispatch must contain.
