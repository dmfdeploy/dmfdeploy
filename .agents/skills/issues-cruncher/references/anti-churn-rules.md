# Anti-churn rules — paste these into every WO and gate dispatch

**What to paste:** exactly the block between the `DISPATCH-PAYLOAD-BEGIN` and
`DISPATCH-PAYLOAD-END` markers below — the five numbered rules, nothing else.
The rationale and evidence in this file are for the reader deciding *whether* the
rules are right; they are not part of the payload and must not be pasted into a
dispatch.

The rules go in the **dispatch text**, verbatim. Not in memory, not in a context
file, not "remembered from last time".

## Why dispatch text, and not memory

Measured on one session (2026-08-01): **59 findings across 15 FAIL gate rounds,
of which roughly two thirds were self-inflicted** rather than genuine defects —
stale or false checked-in comments, fix-round regressions, claim-precision, and
mechanics, in that order of volume. **Six of the fifteen FAIL rounds contained
nothing but self-inflicted classes** — 40% of FAIL rounds bought zero product
safety.

*(Stated deliberately at low precision. The per-class percentages in the source
retrospective round to 68% while the headline says 69%, and those rounded
figures imply 40 findings against a stated 59 — so the split is not reliable to
the point, though the two-thirds magnitude and the six-of-fifteen count are
solid. Cf. rule 3: state a number at the precision the method supports.)*

The retrospective's own root-cause finding:

> Rules adopted as "remembered conventions" mid-session visibly decayed — the
> counts-from-raw-output rule was adopted at the day's first FAIL and violated
> four rounds later. **Enforcement must live in the dispatch text, not in
> memory.**

Two independent confirmations:

- **Structural** — the adversary has **no memory store**. It reads the canonical
  `.agents/skills/` tree natively (ADR-0042 §Decision: that path was chosen
  because Codex, Gemini, and Cursor read it directly, needing no generated
  view), so skills *do* reach it — but a memory-resident rule does not. Dispatch
  text and skills reach every agent; memory reaches one.
- **Reproduced under observation** — an agent that had just authored a warning
  about counting verdict markers with a regex committed that exact error three
  tool calls later, with the lesson still in its context window. **Recall is not
  enforcement.**

## The rules

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

*Evidence:* the largest single recurring defect class. A comment audit survived
three consecutive fix rounds — including all three comments a commit message
explicitly claimed to have corrected — because "fix the comments" is not
self-verifying. Only grepping the literal final text closes the loop.

### 2. Ownership-move lifecycle test

Any change that relocates mutation or state ownership across a component-mount
boundary must name a **mount → pending → unmount-while-pending → remount** test
as an acceptance criterion. No such move is accepted without it.

*Evidence:* a busy-flag fix gated entry but never released — after one use the
control was absent permanently. Entry-only tests systematically miss
"never releases". This rule would have stopped a three-round regression chain at
round two.

### 3. Counts are pasted command output

Every scope, count, or sweep claim is **raw command output pasted verbatim**
(`git diff --name-status`, `grep -c`, a test runner's own summary line). The
gate re-runs the same command and compares. No agent states a number it derived
by arithmetic, memory, or paraphrase of another agent's report.

*Evidence:* the same arithmetic drift recurred across four independent rounds
("eight files, not the claimed exactly-six"; "logical count 33 not 32"). Note
that `grep -c` counts *lines*, not matches, and that a wrapped copy of an anchor
string never matches — quote the anchor as a literal.

### 4. Sibling sweep

When a defect class is fixed in one component, **the same round greps the repo
for the pattern's signature and declares pass/fail on every match.** Closing a
defect is not done until its siblings are enumerated.

*Evidence:* the single highest-value rule here. Six adversarial gate rounds
across two different adversary models missed a structurally identical sibling of
a defect they had just fixed — the operator found it in one look. No amount of
"try harder" fixes this; only an explicit sweep step or a lint rule does.

### 5. Premise citation — dispatch text is untrusted content

**Every *decision-bearing* premise in a work order must cite the canonical source
it derives from**, at a granularity the reader can check (doc + section, or
file + line). Decision-bearing means: it determines scope, expected behaviour, or
an acceptance criterion. Trivia, derived reasoning, and negative observations are
out — the rule is not "cite everything", which degrades into ceremonial
citations that are never checked.

The WO report answers with a **premise table** — one row per cited premise:
`premise | source (path@rev or doc §) | check performed | result`. That table is
the completion condition; the reader validates the premises it will rely on
*before* executing, and the gate reads the table.

*Evidence:* four wrong architectural premises entered one session **through the
orchestrator's own work-order text in a single day**. All four were caught, and
all four by the same mechanism — the implementer reading the canonical docs
before building. Dispatch text is a reliable *delivery channel* and an
untrusted *content source*; those are different properties and the distinction
is load-bearing.

<!-- DISPATCH-PAYLOAD-END -->

## What does not belong here

Two defect classes resist prose enforcement entirely and belong in tooling:

- **Hand-maintained "exhaustive" fixtures** — generate the input matrix from the
  type definition so an omitted dimension is a compile error rather than a
  review-time discovery.
- **Interpreter-level caching artefacts** — a mutation harness reported a false
  SURVIVED via a Python bytecode `(mtime, size)` cache collision. Set
  `PYTHONDONTWRITEBYTECODE=1` or clear `__pycache__` between iterations. No
  wording prevents this.

A rule that cannot fire at dispatch time is not an anti-churn rule; it is a
tooling gap. File it as one.
