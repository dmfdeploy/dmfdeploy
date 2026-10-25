#!/usr/bin/env python3
"""closing_refs.py — find negated closing keywords in a PR body (#548).

GitHub's closing-keyword parser ignores negation: "This PR does not close
#496" creates a real closing link, and bin/close-completed-issues.sh closes
what GitHub linked. This module is the ONE matcher for that hazard, shared by
the guard.yml issue-link gate (rejects the PR body) and the reconciler
(refuses to close when the linking PR body negates the reference).

What counts:
  - a closing keyword (close/closes/closed, fix/fixes/fixed,
    resolve/resolves/resolved, any case), an optional colon, then an issue
    reference: #N, owner/repo#N, or https://github.com/owner/repo/issues/N;
  - preceded in the same clause by a negation (not, never, no, no longer,
    nor, without, cannot, any "n't" contraction) with at most two words
    between the negation and the keyword, none of them a conjunction.

What does not count: text inside fenced code blocks and inline code spans,
which GitHub does not parse for references, so documenting the hazard in
code does not trip the gate. Blockquote lines (> ...) DO count: GitHub parses
references there, and #531's first rewording, which quoted the phrase in a
blockquote, recreated the closing link.

Usage:
  closing_refs.py check [--file PATH] [--default-repo OWNER/REPO]
                        [--issue OWNER/REPO#N]
      Reads the body from PATH (default stdin). Prints each negated closing
      reference with its safe rewrite. --default-repo resolves bare #N;
      --issue reports only references that can resolve to that issue (a bare
      #N with no --default-repo counts — fail closed).
      Exit: 0 none found, 1 found, 2 usage or read error.
  closing_refs.py --self-test
"""
import re
import sys

KEYWORD = r"(?:close[sd]?|fix(?:e[sd])?|resolve[sd]?)"
NAME = r"[A-Za-z0-9_.-]+"
REF = (rf"(?:https://github\.com/(?P<u_owner>{NAME})/(?P<u_repo>{NAME})/issues/(?P<u_num>\d+)"
       rf"|(?:(?P<owner>{NAME})/(?P<repo>{NAME}))?#(?P<num>\d+))")
# Emphasis markers may sit between keyword and reference ("close **#496**").
CLOSING_RE = re.compile(
    rf"(?<![\w-])(?P<kw>{KEYWORD})\b[*_]*(?:[ \t]*:[ \t]*|[ \t]+)[*_]*(?P<ref>{REF})(?![\w])",
    re.IGNORECASE)

# A clause ends at sentence or clause punctuation, a dash, or a line break.
CLAUSE_BREAK_RE = re.compile(r"[.!?;,:\n—–]|\s-\s")
WORD_RE = re.compile(r"[A-Za-z']+")
NEGATIONS = {"not", "never", "no", "nor", "without", "cannot"}
CONJUNCTIONS = {"and", "but", "or", "so", "then", "yet", "also", "while"}
MAX_GAP_WORDS = 2

FENCE_OPEN_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
QUOTE_PREFIX_RE = re.compile(r"^(?:[ \t]{0,3}>[ \t]?)+")
INLINE_CODE_RE = re.compile(r"(?<!`)(`+)(?!`)((?:(?!\n[ \t]*\n).)+?)(?<!`)\1(?!`)",
                            re.DOTALL)


def strip_code(text):
    """Blank fenced code blocks and inline code spans, keeping line numbers.
    Blockquote markers are removed so quoted text is parsed like any other
    text (GitHub links references inside blockquotes)."""
    out = []
    fence = None
    for line in text.replace("\r\n", "\n").split("\n"):
        line = QUOTE_PREFIX_RE.sub("", line)
        if fence is None:
            m = FENCE_OPEN_RE.match(line)
            if m:
                fence = m.group(1)
                out.append("")
                continue
            out.append(line)
        else:
            stripped = line.strip()
            if (stripped and set(stripped) == {fence[0]}
                    and len(stripped) >= len(fence)):
                fence = None
            out.append("")
    joined = "\n".join(out)
    # Keep the newlines inside a span so later line numbers stay right.
    return INLINE_CODE_RE.sub(lambda m: " code " + "\n" * m.group(0).count("\n"),
                              joined)


def _is_negation(word):
    w = word.lower()
    return w in NEGATIONS or w.endswith("n't")


def _negated(prefix):
    """True when the clause text before a keyword ends in a negation
    followed by at most MAX_GAP_WORDS non-conjunction words."""
    clause = CLAUSE_BREAK_RE.split(prefix)[-1]
    words = WORD_RE.findall(clause.replace("’", "'"))
    gap = []
    for word in reversed(words):
        if _is_negation(word):
            return True
        if word.lower() == "longer" and not gap:
            gap.append(word)  # "no longer close": "no" is the negation
            continue
        if word.lower() in CONJUNCTIONS or len(gap) >= MAX_GAP_WORDS:
            return False
        gap.append(word)
    return False


class Finding:
    def __init__(self, line, phrase, owner, repo, num):
        self.line = line
        self.phrase = phrase
        self.owner = owner
        self.repo = repo
        self.num = num

    def target(self, default_repo=None):
        if self.owner:
            return f"{self.owner}/{self.repo}#{self.num}"
        if default_repo:
            return f"{default_repo}#{self.num}"
        return f"#{self.num}"

    def rewrite(self, default_repo=None):
        return f"leaves {self.target(default_repo)} open, deliberately."


def find_negated(text):
    clean = strip_code(text)
    findings = []
    for m in CLOSING_RE.finditer(clean):
        prefix = clean[:m.start()]
        if not _negated(prefix):
            continue
        clause = CLAUSE_BREAK_RE.split(prefix)[-1]
        phrase = " ".join((clause + clean[m.start():m.end()]).split())
        phrase = phrase.strip("*_ ")
        owner = m.group("u_owner") or m.group("owner")
        repo = m.group("u_repo") or m.group("repo")
        num = m.group("u_num") or m.group("num")
        findings.append(Finding(prefix.count("\n") + 1, phrase, owner, repo, int(num)))
    return findings


def matches_issue(finding, issue_repo, issue_num, default_repo=None):
    """Can this finding resolve to issue_repo#issue_num? A bare #N resolves
    against default_repo; with no default_repo it counts (fail closed)."""
    if finding.num != issue_num:
        return False
    repo = f"{finding.owner}/{finding.repo}" if finding.owner else default_repo
    return repo is None or repo.lower() == issue_repo.lower()


def _cmd_check(args):
    path, default_repo, issue = None, None, None
    it = iter(args)
    for arg in it:
        if arg in ("--file", "--default-repo", "--issue"):
            try:
                value = next(it)
            except StopIteration:
                print(f"closing_refs: {arg} needs a value", file=sys.stderr)
                return 2
            if arg == "--file":
                path = value
            elif arg == "--default-repo":
                default_repo = value
            else:
                m = re.fullmatch(rf"({NAME}/{NAME})#(\d+)", value)
                if not m:
                    print(f"closing_refs: --issue wants OWNER/REPO#N, got {value!r}",
                          file=sys.stderr)
                    return 2
                issue = (m.group(1), int(m.group(2)))
        else:
            print(f"closing_refs: unknown argument {arg!r}", file=sys.stderr)
            return 2
    try:
        if path:
            with open(path, "r", encoding="utf-8") as fh:
                text = fh.read()
        else:
            text = sys.stdin.read()
    except OSError as exc:
        print(f"closing_refs: cannot read the body: {exc}", file=sys.stderr)
        return 2
    findings = find_negated(text)
    if issue:
        findings = [f for f in findings if matches_issue(f, issue[0], issue[1], default_repo)]
    for f in findings:
        print(f"line {f.line}: negated closing keyword: \"{f.phrase}\"")
        print(f"  GitHub ignores the negation and links {f.target(default_repo)} "
              "as closed by this PR.")
        print(f"  Safe rewrite: \"{f.rewrite(default_repo)}\"")
    return 1 if findings else 0


# ── self-test fixtures ────────────────────────────────────────────────────
# (body, expected count of negated refs). The #531 wording is verbatim.
FENCE = "`" * 3
FIXTURES = [
    ("#531 wording", "**This PR does not close #496**, deliberately.", 1),
    ("qualified, fix", "This does not fix dmfdeploy/dmfdeploy#12.", 1),
    ("genuine close", "Closes dmfdeploy/dmfdeploy#12", 0),
    ("#531 wording in a fenced block",
     f"Example:\n\n{FENCE}text\n**This PR does not close #496**, deliberately.\n{FENCE}\n", 0),
    ("tilde fence", "~~~\nmust not close #3\n~~~\n", 0),
    ("inline code span", "Never write `does not close #496` in a body.", 0),
    ("double-backtick span", "Avoid ``does not close #496`` here.", 0),
    ("blockquote counts", "> this sentence previously read \"does not close #496\".", 1),
    ("must not + colon", "This PR must not close: #7", 1),
    ("never closes", "It never closes #8.", 1),
    ("don't, any case", "We DON'T FIX #9 here.", 1),
    ("curly apostrophe", "This doesn’t resolve #10.", 1),
    ("won't", "Merging won't resolve dmfdeploy/dmf-cms#11.", 1),
    ("no longer", "This no longer fixes #12.", 1),
    ("one word between", "This does not fully close #13.", 1),
    ("URL form", "Does not close https://github.com/dmfdeploy/dmfdeploy/issues/14", 1),
    ("bold ref", "does not close **#15**", 1),
    ("negation in an earlier clause", "Not a hotfix, but closes #16.", 0),
    ("conjunction between", "Not urgent and closes #17", 0),
    ("too far", "Not in any way at all does it close #18", 0),
    ("leaves-open rewrite", "This PR leaves dmfdeploy/dmfdeploy#496 open, deliberately.", 0),
    ("refs is not a closing keyword", "Does not refs #19", 0),
    ("mixed", "Closes #20. It does not close #21.", 1),
    ("closed past tense", "Hasn't closed #22", 1),
    ("unclosed fence hides the rest", f"{FENCE}\ndoes not close #23\n", 0),
]


def run_self_test():
    passed = failed = 0
    for label, body, want in FIXTURES:
        got = len(find_negated(body))
        if got == want:
            passed += 1
            print(f"  PASS  {label}")
        else:
            failed += 1
            print(f"  FAIL  {label}: expected {want} negated ref(s), got {got}")
    # The issue filter used by the reconciler.
    f = find_negated("**This PR does not close #496**, deliberately.")[0]
    checks = [
        ("bare ref + umbrella default repo matches",
         matches_issue(f, "dmfdeploy/dmfdeploy", 496, "dmfdeploy/dmfdeploy"), True),
        ("bare ref + component default repo does not match",
         matches_issue(f, "dmfdeploy/dmfdeploy", 496, "dmfdeploy/dmf-cms"), False),
        ("bare ref + no default repo matches (fail closed)",
         matches_issue(f, "dmfdeploy/dmfdeploy", 496), True),
        ("other number does not match",
         matches_issue(f, "dmfdeploy/dmfdeploy", 495, "dmfdeploy/dmfdeploy"), False),
        ("rewrite text",
         f.rewrite("dmfdeploy/dmfdeploy") == "leaves dmfdeploy/dmfdeploy#496 open, deliberately.",
         True),
    ]
    for label, got, want in checks:
        if got == want:
            passed += 1
            print(f"  PASS  {label}")
        else:
            failed += 1
            print(f"  FAIL  {label}: expected {want}, got {got}")
    print(f"closing_refs self-test: {passed} passed, {failed} failed")
    return 0 if failed == 0 else 1


def main(argv):
    if argv[:1] == ["--self-test"]:
        return run_self_test()
    if argv[:1] == ["check"]:
        return _cmd_check(argv[1:])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
