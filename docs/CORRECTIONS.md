# Corrections log

This is the public, dated record of what the project said that was wrong, and
what is right instead. It covers anything that speaks for the project in
public: the READMEs, the runbooks, the docs in this repository, and anything
else published in the project's name.

The project corrects itself in place as a matter of course. This log makes
those corrections visible, so a reader can check what changed and when
without reading the commit history.

## The rule for an entry

Add an entry when a public statement turns out to be wrong in a way a reader
could have relied on. A typo or a broken link doesn't need an entry; a wrong
claim about what the platform does, or doesn't do, does.

Each entry gives:

- **Date** — the day the correction landed.
- **Where** — the file, section or video where the claim was made.
- **What was wrong** — the claim as it stood.
- **What is right** — the corrected statement, with how it was established.
- **What changed** — the PR or commit that made the correction.

An entry describes a correction. It never introduces a new claim: if the
corrected statement needs evidence, the evidence is cited where the statement
lives, and the entry links to it.

Entries are added and never rewritten. If an entry itself turns out to be
wrong, a later entry corrects it.

## Entries

### 2026-09-19 — demo-journey runbook, §6b

- **Where:** [`docs/runbooks/dmf-demo-journey.md`](runbooks/dmf-demo-journey.md),
  §6b, the presenter guidance for the activity record.
- **What was wrong:** the runbook told the presenter, in bold, *"Do not tell an
  audience that every row now carries its outcome"*, and cited
  [#560](https://github.com/dmfdeploy/dmfdeploy/issues/560) as open. #560 had
  closed on 2026-09-10, so the guidance described a gap the code no longer had.
- **What is right:** since dmf-cms 0.39.0, automatic-rollback rows carry an
  outcome, like deploy and teardown rows. Two cases still never resolve: an
  automatic rollback that attaches to an earlier *manual* rollback never joins
  an outcome, and an operator-initiated rollback is not on the record at all.
  This was read from the 0.39.0 source; no automatic-rollback row was observed
  live in the 2026-09-19 pass, and the runbook marks the beat that way.
- **What changed:** [#581](https://github.com/dmfdeploy/dmfdeploy/pull/581)
  (tracking issue [#579](https://github.com/dmfdeploy/dmfdeploy/issues/579)).
