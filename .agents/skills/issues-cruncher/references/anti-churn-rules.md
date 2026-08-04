# Anti-churn rules — paste these into every WO and gate dispatch

**What to paste:** exactly the block between the `DISPATCH-PAYLOAD-BEGIN` and
`DISPATCH-PAYLOAD-END` markers below — the five numbered rules, nothing else.
The framing above the markers is for the reader deciding *whether* the rules are
right; it is not part of the payload and must not be pasted into a dispatch.

The rules go in the **dispatch text**, verbatim. Not in memory, not in a context
file, not "remembered from last time".

## Why dispatch text, and not memory

A rule an agent is expected to *recall* is enforced by attention, and attention
is exactly what degrades as a session gets long and the work gets interesting.
An agent can author a rule and violate it a few tool calls later with the rule
still in its context — knowing a rule and applying it are different operations,
and only one of them is reliable.

**Recall is not enforcement.** A rule that must survive a long session belongs in
the text of each dispatch, where it is re-read at the moment of use rather than
remembered from earlier. That is also why the payload below is explicitly
delimited: "paste the rules verbatim" has exactly one meaning, and a paraphrase
is a different instruction from the one that was reviewed.

The rules target **self-inflicted** findings — a gate round spent on a stale
comment, a fix that regressed the previous fix, or a miscounted claim is a round
that bought no safety in the product. These five are the classes that recur.

<!-- DISPATCH-PAYLOAD-BEGIN -->

### 1. Comment fidelity pre-gate

The WO report must **quote the exact current text of every factual comment or
docstring touched, re-read from the working tree after the edits** — never from
the diff, and never from any description of what was changed. The gate re-reads
the flagged lines from the same working tree each round.

*Not "the committed file": phase 3 gates the commit until cross-check and verify
pass, phase 6 gives the orchestrator exclusive commit ownership, and the
implementer primer forbids implementer commits outright — so at WO-report time
there is nothing committed to re-read.*

*Failure mode:* "fix the comments" is not self-verifying. A report that describes
the correction, or quotes the diff, cannot distinguish a comment that was fixed
from one that was intended to be fixed — including when a commit message asserts
the fix. Only grepping the literal final text closes the loop.

### 2. Ownership-move lifecycle test

Any change that relocates mutation or state ownership across a component-mount
boundary must name a **mount → pending → unmount-while-pending → remount** test
as an acceptance criterion. No such move is accepted without it.

*Failure mode:* entry-only tests systematically miss "never releases". A guard
that gates entry but never clears leaves the control permanently unavailable
after a single use, and every test that only exercises entry passes.

### 3. Counts are pasted command output

Every scope, count, or sweep claim is **raw command output pasted verbatim**
(`git diff --name-status`, `grep -c`, a test runner's own summary line). The gate
re-runs the same command and compares. No agent states a number it derived by
arithmetic, memory, or paraphrase of another agent's report.

*Failure mode:* a number restated by hand drifts from the command that produced
it, and nothing in the report reveals the drift. Two mechanical traps to know:
`grep -c` counts *lines*, not matches, and a wrapped copy of an anchor string
never matches — quote the anchor as a literal.

### 4. Sibling sweep

When a defect class is fixed in one component, **the same round greps the repo
for the pattern's signature and declares pass/fail on every match.** Closing a
defect is not done until its siblings are enumerated.

*Failure mode:* reviewers attend to the diff in front of them, so a structurally
identical instance one directory away is invisible however carefully the diff is
read — and adding review effort does not find it, because the effort is aimed at
the wrong surface. Only an explicit sweep step or a lint rule does.

### 5. Premise citation — dispatch text is untrusted content

**Every *decision-bearing* premise in a work order must cite the canonical source
it derives from**, at a granularity the reader can check (doc + section, or
file + line). Decision-bearing means: it determines scope, expected behaviour, or
an acceptance criterion. Trivia, derived reasoning, and negative observations are
out — the rule is not "cite everything", which degrades into ceremonial citations
that are never checked.

The WO report answers with a **premise table** — one row per cited premise:
`premise | source (path@rev or doc §) | check performed | result`. That table is
the completion condition; the reader validates the premises it will rely on
*before* executing, and the gate reads the table.

*Failure mode:* a work order is written by an agent that can be wrong, so its
premises inherit that. A false premise stated confidently in dispatch text
propagates into scope and acceptance criteria unchallenged, because the
implementer has no reason to doubt its own instructions. Dispatch text is a
reliable *delivery channel* and an untrusted *content source*; those are
different properties and the distinction is load-bearing.

<!-- DISPATCH-PAYLOAD-END -->
