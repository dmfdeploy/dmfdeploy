# Code principles

These principles are guidelines, and none of them is binding. They guide how a change is written.
They don't decide whether a change is made, they aren't a review gate, and
they are never on their own a reason to refactor. A reviewer may point to a
principle, but a principle alone is never a blocking finding, and a reviewer
doesn't ask for refactoring outside the change's scope.

They are a working-model convention set by the operator, so no RFC was
needed. For how work is tracked and reviewed, see
[WORKING-MODEL.md](WORKING-MODEL.md).

## The principles

The operator's text, as given:

<!-- vale off -->
- Single responsibility
- Reviewability (functions under 30 to 40 lines and files under 300 lines where practical; guidelines, not limits)
- Low complexity
- Cohesion
- Explicit contracts
- Minimal dependencies
- Operational safety
- Testability
- Consistency
- Documentation
- Continuous simplification
- The closing check: could a competent engineer unfamiliar with the code understand, test and safely modify it without excessive investigation?
- The limit: these are persistent objectives, not a reason for large unsolicited refactoring. Prefer small, independently reviewable changes with clear verification.
<!-- vale on -->

## How a change uses them

- A codex review brief asks one extra question: could an engineer new to the
  code understand, test and safely change it?
- A PR body says what the change simplified and how it was verified.
- A PR body says how the change fits the size guidelines.

### What CI checks for size and structure

- No CI check fails a PR on a line count. When a PR changes a file of more
  than 400 lines, CI shows a warning on that file and the check still passes.
- In Python (`*.py` files, plus any script that a repo names in ruff's
  `extend-include`), CI fails a function that breaks one of four ruff rules at
  ruff's default limits: `C901` (complexity), `PLR0912` (branches), `PLR0913`
  (arguments) and `PLR0915` (statements).
- A function that broke a rule when the check was switched on carries a
  `# noqa` mark with the rule code. A PR may remove a mark, and must remove it
  when the function no longer breaks the rule. A PR can't add a mark, and a
  file-wide `noqa` without rule codes fails.
- When a rule doesn't fit a case, say why in the PR. A maintainer can then
  change that repo's ruff settings, and the change shows in the diff. A new
  `# noqa` mark never passes.
- To run the check locally, use `ruff check .` (in dmf-promsd,
  `scripts/check.sh`). Each repo's CONTRIBUTING file says where to run it.
