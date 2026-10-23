<!-- ADR doc convention: every ADR carries a top-of-doc **Rule:** line — the binding
constraint in one imperative sentence — directly under the metadata block. See
docs/decisions/README.md → "ADR conventions". -->
# ADR-NNNN: Short title in imperative or declarative form

**Status:** Proposed | Accepted | Superseded by ADR-NNNN | Deprecated
**Date:** YYYY-MM-DD
**Deciders:** @<handle>
**Rule:** The single binding constraint, as one imperative sentence — what a reader must do or not do. (The decision in brief; the full rationale is below.)

## Context

What's the problem? What constraints apply? What forces are at play?
Two to four sentences. Name the *real* tension, not the obvious one.

## Decision

What we decided. One paragraph. Make it crisp. State the rule, not the rationale.

## Consequences

- **Positive** — what gets easier, what's now enforceable, what stops happening
- **Negative** — what we accept as cost
- **Neutral** — what changes that's neither pro nor con

### Enforcement

How this decision is kept honest: which script checks it, which skill
references it, which CI gate fails on violation. If "discipline only,"
say so explicitly.

## Status

The status value from the metadata block, plus one line per amendment or
supersession, with its date.

Keep the ADR near 80 lines. Alternatives considered, deliberation, review
notes and implementation plans go in a companion file at
`docs/archive/decisions/<same-file-name>`. End this section with the sentence
"Alternatives, deliberation and implementation detail for this decision are
in the archive record." and make "archive record" a link to that file.
