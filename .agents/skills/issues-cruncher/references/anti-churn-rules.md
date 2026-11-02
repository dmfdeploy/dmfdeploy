# Anti-churn rules — paste these into every WO and gate dispatch

**What to paste:** exactly the block between the `DISPATCH-PAYLOAD-BEGIN` and
`DISPATCH-PAYLOAD-END` markers below — the six numbered rules, nothing else.
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

Every scope, count, or sweep claim is **raw output pasted verbatim**: one of the
six count forms of rule 6, which the pre-gate check recomputes and compares, or a
test runner's own summary line, which the reviewer re-runs. No agent states a
number it derived by arithmetic, memory, or paraphrase of another agent's
report.

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

### 6. Pre-gate report sections

The WO report carries four level-2 sections, with these exact headings:

- `## Comment fidelity`: a fenced block with one `PATH: literal line` entry for
  every comment or docstring line touched, or the single line `none`. A
  comment that follows code on the same line counts: quote the whole line.
- `## Counts`: a fenced block of `$ <form>` lines, each followed by its pasted
  output, where `<form>` is one of `git diff --stat <ref>`,
  `git diff --name-status <ref>`, `git ls-files [<path>]`, `ls <dir>`,
  `lines <path>` or `count <regex> <path>`. No other command is re-run. The
  `ls <dir>` form lists the entry names that do not start with a dot, sorted by
  code point, one per line; paste the output of `LC_ALL=C ls -1 <dir>`.
- `## Sibling sweep`: a fenced block with `pattern: ERE`, then one
  `PATH:LINE: pass|fail` entry for every match, or `pattern: none`.
- `## Premise table`: the table from rule 5, with exactly the four columns
  `premise`, `source`, `check performed` and `result`, or the single line
  `none` when the work order carries no decision-bearing premise.

The orchestrator runs `bin/pre-gate-check.sh` on the report before any gate
request. A report the script cannot parse is returned unread.

*Failure mode:* a report in free prose cannot be re-checked by a machine, so
every claim in it waits for a reviewer to find the one that is wrong.

<!-- DISPATCH-PAYLOAD-END -->

## Mechanical pre-gate check

This section is not part of the payload.

The script `bin/pre-gate-check.sh` re-verifies, against the working tree, the
parts of a report that the rules make checkable: rule 1 (quoted comments), rule 3
(pasted counts), rule 4 (sibling sweep) and the source resolution of rule 5.
Rule 2 (the ownership-move lifecycle test) stays a review criterion.

Run it by path from the skill directory:

```
bin/pre-gate-check.sh --report <WO report> --repo <tree> [--base REF]
```

`--base` defaults to `origin/main`. The script diffs the working tree against
that ref, so staged and unstaged edits both count.

The output is one block between `<!-- PRE-GATE-CHECK-BEGIN -->` and
`<!-- PRE-GATE-CHECK-END -->`. The first line inside it is the verdict:
`PRE-GATE: PASS`, or `PRE-GATE: FAIL (sections: 1,3)`. Every result line starts
with `pass:`, `fail:` or `note:`.

Exit codes: 0 for PASS, 1 for FAIL, 2 for a usage or I/O error (missing file,
`--repo` is not a git repository, unresolvable `--base`).

Refusal rule: paste the block, verbatim, at the top of every gate request. The
adversary refuses a request without it. A `PRE-GATE: FAIL` block goes back to the
implementer as a fix round, and no gate request is sent.

To confirm the script itself still discriminates, run the self-test:

```
bin/pre-gate-check-selftest.sh
```

It prints `SELFTEST: PASS (<n> scenarios)` on success.

Limits:

- The `## Counts` section does not run report-supplied commands. Each `$ ` line
  must be one of the six forms in rule 6, and anything else fails with
  `not a supported count form`. `ls`, `lines` and `count` are computed inside the
  checker (`ls` lists the entry names that do not start with a dot, sorted by
  code point, one per line, which is what `LC_ALL=C ls -1 <dir>` prints;
  `lines` counts lines; `count` counts lines where the regular expression
  matches). The three git forms run git with fixed
  arguments, in an isolated environment (empty home, no global or system
  config, a private copy of the index). The two `git diff` forms take a ref that
  must resolve to a commit; `git ls-files` takes an optional contained path.
  There is no shell, no pipeline and no option parsing, and an empty `$ ` line
  fails like any other unsupported form.
- Every git call reads attributes from git's empty tree and runs with the
  filesystem monitor off and external diff and text conversion disabled, so a
  repository's own diff drivers, text converters, clean or smudge filters and
  monitor hooks never run during a check. Git 2.40 or newer is required. The
  repository's `.git/config` is otherwise trusted: apart from those helpers, a
  setting in it still takes effect.
- The `count` form arms a 60-second in-process alarm. A pathological pattern was
  interrupted after about 60 seconds on macOS; no cross-platform guarantee is
  claimed.
- Paths in the forms, in quoted comment paths and in premise sources are
  contained on the resolved path: not absolute, no `..`, no `~` or `$` prefix,
  and no symlink in the path, whatever it points to. The one message for a
  refused path is `path outside the repo or a symlink`. Counts paths must also
  exist, and `lines` and `count` need a regular file.
- The report structure fails closed: each of the four headings appears once,
  every fence is closed, a section holds one fenced block (one table for the
  premise section), the table has a header separator row, and `## Counts` has no
  text before its first command.
- `none` is the literal trimmed line, and it must be the sole content of its
  block or section in every section that allows it.
- Output normalization: counts are compared after stripping trailing whitespace
  on each line and trailing blank lines, and expected output may not be empty.
  Quoted comment lines are compared as whole lines after trimming leading and
  trailing whitespace.
- Comment coverage detects single-line comment markers and Python docstring
  bodies. It does not detect block-comment bodies in other languages or text
  inside heredocs. Any untracked symlink fails the coverage scan.
- Coverage also detects a comment that follows code on the same line. In a file
  with a `sh`, `bash`, `zsh`, `py`, `rb`, `pl`, `yaml`, `yml`, `toml`, `ini`,
  `cfg`, `conf` or `mk` extension, or named `Makefile`, a ` #` counts. In a file
  with a `js`, `ts`, `jsx`, `tsx`, `go`, `rs`, `c`, `h`, `cpp`, `hpp`, `java`,
  `kt`, `swift` or `cs` extension, a ` //` counts. The marker needs whitespace
  before it, and the text before it needs an even number of unescaped single
  quotes and an even number of unescaped double quotes, so a marker inside a
  string literal does not count. The quote count is a heuristic, not a parser:
  a quote inside a here-document, a regular expression or a multi-line string
  can misclassify a line in either direction. Shebang lines are skipped, and the
  quoted text for such a line is the whole trimmed line.
- Coverage never asks for a blank line to be quoted, inside a docstring or
  outside one, because a report cannot quote an empty line.
- A `.py` file among the added files that does not parse fails with `not parsed
  as Python; docstring coverage cannot be established`.
- A changed or untracked file whose name contains a control character, a double
  quote or a backslash fails with `unsupported file name`, because the report
  cannot spell it. The checker lists names with NUL-separated git output and
  runs one diff per literal path, so it never slices a quoted diff header.
- The sweep reads `git grep` output split at NUL, so a colon in a file name is
  safe. A binary file that matches the pattern fails, and so does any output
  line the checker cannot parse. Nothing is dropped without a message.
- Doc files (`.md`, `.rst`, `.txt`, `.adoc`) are prose. The script checks their
  quoted lines but does not require every added line to be quoted.
- The premise table has exactly four columns. The header row has four cells
  whose text, ignoring case, is `premise`, `source`, `check performed` and
  `result`, each once, in any order. The separator row has four cells that each
  match `:?---+:?`. Every data row has four cells with a value in each; a pipe
  inside a cell splits it, so a row with an extra pipe fails with a cell count.
  URL and tracker-ref premise sources are noted, not resolved. At least one
  source in the table must resolve against the tree.
- A `PATH §HEADING` source resolves only when a line of the file is a Markdown
  heading whose text equals the heading, ignoring case, and that is not inside a
  fenced code block (a fence opens with three or more backticks or tildes and
  closes with the same character, at least as many times). In a file that is not
  Markdown, a line that consists of the heading alone also counts. A mention in
  a paragraph does not.
- A sibling declared `fail` needs a reason after the word `fail`.
- The checker writes only to its own temporary directory, removed on exit, and
  leaves every file under the repository, including `.git/index`, byte for byte
  unchanged.
- The check trusts the working tree and its repository config; it defends
  against the report.
- `none` is the implementer's declaration that nothing relevant exists. The
  check cannot verify that, so the reviewer confirms it independently.
