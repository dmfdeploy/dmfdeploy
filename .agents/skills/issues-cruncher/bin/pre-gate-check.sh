#!/usr/bin/env bash
# pre-gate-check — mechanically re-verify an implementer report against the working tree.
#
# Correctness model (why you can trust the verdict):
#   - The report is UNTRUSTED input (anti-churn rule 5). The script reads claims
#     from it and checks each one against the working tree; it never believes a
#     claim because the report states it.
#   - The checker writes only to its own temporary directory, removed on exit,
#     and leaves every file under the repository, including .git/index, byte
#     for byte unchanged (git runs against a private copy of the index).
#   - The Counts section (2) never runs a report-supplied command. Each "$ "
#     line must match one of six fixed forms: git diff --stat REF, git diff
#     --name-status REF, git ls-files [PATH], ls DIR, lines PATH, and count
#     REGEX PATH. ls, lines and count are computed inside the checker in
#     Python; the three git forms (diff --stat, diff --name-status, ls-files)
#     run git with fixed arguments. There is no
#     shell, no pipeline and no option parsing, so no external tool has options
#     that could write a file, start a program or read a name from a file.
#   - Containment: every PATH must exist, must not be absolute, contain "..",
#     start with "~" or "$", or be a symlink or sit below one, and must resolve
#     inside the repository. Quoted comment paths and premise paths get the same
#     resolved-path test.
#   - The three git forms run with an empty HOME and no global or system config, so
#     a .gitconfig in the tree has no effect. The repository's own .git/config
#     is trusted: the check defends against the report, not against a hostile
#     working tree.
#   - Every result line starts with "pass: ", "fail: " or "note: ", and report
#     text only ever appears after that prefix or indented below it. Quoted text
#     therefore cannot forge the verdict line or the BEGIN/END markers.
#   - Fail closed: a section whose heading, fenced block or table is missing,
#     duplicated or malformed (an unclosed fence, a table without a separator
#     row, text before the first command) fails. The only way to declare
#     "nothing here" is the literal line `none`, as the sole content of its
#     block or section (sections 1, 3 and 4).
#   - Added lines come from `git diff BASE` (working tree against BASE), so
#     staged and unstaged edits count. Untracked, non-ignored text files count
#     as fully added (they are not in that diff, so they are read separately).
#     Paths come from NUL-separated listings and each diff runs for one literal
#     path; a name with a control character, quote or backslash fails.
#   - Comment coverage detects single-line comment markers and, in .py files,
#     docstring bodies. It does not detect block-comment bodies in other
#     languages or text inside heredocs. It never asks for a blank line, and a
#     .py file that does not parse fails.
#   - The sibling sweep reads NUL-separated `git grep` output, so a colon in a
#     file name is safe; a binary match or an unparseable line fails.
#   - The premise table needs the premise, source, check performed and result
#     columns, all filled in every row; `PATH §HEADING` needs a real heading.
#
# Checks: 1 comment fidelity (rule 1), 2 counts (rule 3), 3 sibling sweep
# (rule 4), 4 premise sources (rule 5). Rule 2 stays a review criterion.
#
# Exit codes: 0 PASS, 1 FAIL, 2 usage or I/O error.
set -euo pipefail
export GIT_OPTIONAL_LOCKS=0

usage() {
  cat <<'EOF'
pre-gate-check — re-verify a work-order report against the working tree

Usage:
  pre-gate-check.sh --report FILE --repo DIR [--base REF]
  pre-gate-check.sh --help

  --report FILE  the WO report (markdown) to check
  --repo DIR     repository root (a git working tree) the report is about
  --base REF     ref the working tree is diffed against (default: origin/main)

Report sections (level-2 headings, exact text):
  ## Comment fidelity   fenced block: "PATH: literal line" per touched comment, or none
  ## Counts             fenced block: "$ <form>" then its pasted output
  ## Sibling sweep      fenced block: "pattern: ERE" then "PATH:LINE: pass|fail", or none
  ## Premise table      markdown table: premise, source, check performed, result; or none

Each "$ " line under ## Counts must be one of six forms; nothing else is run:
  git diff --stat REF         git diff --name-status REF
  git ls-files [PATH]         ls DIR
  lines PATH                  count REGEX PATH
There is no shell, no pipeline and no option parsing. REF and PATH are checked
before anything runs; PATH may not be absolute, contain "..", or be or sit below
a symlink.

Output: one PRE-GATE-CHECK block on stdout; the first line inside it is
"PRE-GATE: PASS" or "PRE-GATE: FAIL (sections: N,...)".

Exit codes: 0 PASS, 1 FAIL, 2 usage or I/O error.
EOF
}

die() {
  printf 'pre-gate-check: %s\n' "$*" >&2
  exit 2
}

REPORT=""
DIR=""
BASE="origin/main"

while [ $# -gt 0 ]; do
  case $1 in
    --report) [ $# -ge 2 ] || die "--report needs a value"; REPORT=$2; shift 2 ;;
    --repo)   [ $# -ge 2 ] || die "--repo needs a value";   DIR=$2;    shift 2 ;;
    --base)   [ $# -ge 2 ] || die "--base needs a value";   BASE=$2;   shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
  esac
done

[ -n "$REPORT" ] || { usage >&2; die "--report is required"; }
[ -n "$DIR" ] || { usage >&2; die "--repo is required"; }
command -v python3 >/dev/null 2>&1 || die "python3 is required"
[ -f "$REPORT" ] && [ -r "$REPORT" ] || die "report not readable: $REPORT"
git -C "$DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not a git work tree: $DIR"
[ -z "$(git -C "$DIR" rev-parse --show-prefix)" ] || die "--repo must be the repository root: $DIR"
git -C "$DIR" rev-parse --verify -q "${BASE}^{commit}" >/dev/null || die "base does not resolve: $BASE"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

# Every git call, here and in the command helper, reads a private copy of the
# index: git diff and git status refresh the index they are given, and the
# repository's own .git/index must stay byte for byte unchanged.
idx="$(git -C "$DIR" rev-parse --absolute-git-dir)/index"
if [ -f "$idx" ]; then cp "$idx" "$W/index"; fi
export GIT_INDEX_FILE="$W/index"

# --- output plumbing ---------------------------------------------------------

CUR=0
for n in 1 2 3 4; do : >"$W/out.$n"; done

ok()   { printf 'pass: %s\n' "$*" >>"$W/out.$CUR"; }
note() { printf 'note: %s\n' "$*" >>"$W/out.$CUR"; }
bad()  { printf 'fail: %s\n' "$*" >>"$W/out.$CUR"; : >"$W/failed.$CUR"; }

# show_block LABEL FILE — an indented expected/actual block under a fail line.
show_block() {
  printf '  %s:\n' "$1" >>"$W/out.$CUR"
  sed 's/^/    /' "$2" >>"$W/out.$CUR"
}

trim() {
  local s=$1
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# --- report parsing ----------------------------------------------------------

# section_body HEADING — body of the level-2 section; headings inside fenced
# blocks do not count. Exit 3: heading absent. 4: heading appears twice. 5: a
# fence is still open when the section ends.
section_body() {
  tr -d '\r' <"$REPORT" | awk -v h="## $1" '
    function rtrim(s) { sub(/[ \t]+$/, "", s); return s }
    /^```/ {
      if (!fence) fence = 1
      else if ($0 ~ /^```[ \t]*$/) fence = 0
      if (insec) print
      next
    }
    !fence && /^## / {
      insec = 0
      if (rtrim($0) == h) { count++; if (count == 1) insec = 1 }
      next
    }
    insec { print }
    END {
      if (count == 0) exit 3
      if (count > 1) exit 4
      if (insec && fence) exit 5
    }'
}

# block_count — stdin: a section body; prints the number of fenced blocks.
block_count() {
  awk '/^```/ { if (!fence) { fence = 1; n++ } else if ($0 ~ /^```[ \t]*$/) fence = 0 } END { print n + 0 }'
}

# first_block — stdin: a section body; prints the lines of its first fenced block.
first_block() {
  awk '/^```/ { if (!fence) { fence = 1; next } else if ($0 ~ /^```[ \t]*$/) exit } fence { print }'
}

# load_section NAME — load a section body into BODY. Returns 1 (after recording
# a failure) when the heading is missing or duplicated or a fence is unclosed.
BODY=""
load_section() {
  local rc=0
  BODY=$(section_body "$1") || rc=$?
  case $rc in
    0) return 0 ;;
    3) bad "section missing" ;;
    4) bad "duplicate section heading: ## $1" ;;
    5) bad "unterminated fenced block" ;;
    *) bad "could not read the section (status $rc)" ;;
  esac
  return 1
}

# fenced_block NAME — load the one fenced block of a section into BLOCK.
# Returns 1 (after recording a failure) when it cannot.
BLOCK=""
fenced_block() {
  local n
  load_section "$1" || return 1
  n=$(printf '%s\n' "$BODY" | block_count)
  if [ "$n" -eq 0 ]; then
    bad "no fenced block under the heading"
    return 1
  fi
  if [ "$n" -gt 1 ]; then
    bad "more than one fenced block under the heading (one block per section)"
    return 1
  fi
  BLOCK=$(printf '%s\n' "$BODY" | first_block)
}

is_none() { [ "$(trim "$(printf '%s\n' "$1" | sed '/^[[:space:]]*$/d')")" = none ]; }

# none_exclusive BLOCK — `none` (or `pattern: none`) must be the only non-empty
# line. Returns 1 (after recording a failure) when it shares the block.
none_exclusive() {
  local nonempty has_none
  nonempty=$(printf '%s\n' "$1" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')
  has_none=$(printf '%s\n' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -cx -e none -e 'pattern: none' || true)
  if [ "$has_none" -gt 0 ] && [ "$nonempty" -gt 1 ]; then
    bad "none must be the only line in the block"
    return 1
  fi
}

# inside_repo PATH — true when no component of PATH is a symlink and PATH
# resolves inside the repository (a path that does not exist yet counts as
# inside). Failure message used everywhere: "path outside the repo or a symlink".
inside_repo() {
  python3 -I -c 'import os, sys
repo, p = sys.argv[1], sys.argv[2]
root = os.path.realpath(repo)
cur = repo
for part in [c for c in p.split("/") if c not in ("", ".")]:
    cur = os.path.join(cur, part)
    if os.path.islink(cur):
        sys.exit(1)
real = os.path.realpath(os.path.join(repo, p))
sys.exit(0 if real == root or real.startswith(root + os.sep) else 1)' "$DIR" "$1"
}

# --- section 1: comment fidelity ---------------------------------------------

COMMENT_RE='^[[:space:]]*(#|//|/\*|\*([[:space:]]|/|$)|<!--|"""|'"'''"')'

# odd_name PATH — true when PATH holds a control character, a double quote or a
# backslash. Git quotes such names in its diff headers, and the report cannot
# spell them, so they fail instead of being sliced.
odd_name() {
  local LC_ALL=C
  case $1 in
    *[[:cntrl:]]*|*'"'*|*\\*) return 0 ;;
  esac
  return 1
}

# added_lines — PATH<TAB>N<TAB>TEXT for every line the working tree adds
# relative to BASE, plus every line of each untracked, non-ignored text file.
# Paths come from NUL-separated listings and each diff runs for one literal
# path, so no header is ever parsed for a name.
added_lines() {
  local f
  while IFS= read -r -d '' f; do
    if odd_name "$f"; then
      bad "unsupported file name (control character, quote or backslash): $(printf '%q' "$f")"
      continue
    fi
    git -C "$DIR" --literal-pathspecs diff --no-color --no-ext-diff --no-renames -U0 "$BASE" -- "$f" |
      awk -v p="$f" '
        !seen && /^@@ / { seen = 1 }
        !seen { next }
        /^@@ / {
          if (match($0, /\+[0-9]+/)) ln = substr($0, RSTART + 1, RLENGTH - 1) + 0
          next
        }
        /^\+/ { printf "%s\t%d\t%s\n", p, ln, substr($0, 2); ln++ }'
  done < <(git -C "$DIR" diff --name-only -z --no-renames "$BASE" --)
  while IFS= read -r -d '' f; do
    if odd_name "$f"; then
      bad "unsupported file name (control character, quote or backslash): $(printf '%q' "$f")"
      continue
    fi
    if [ -L "$DIR/$f" ]; then
      bad "untracked symlink is not allowed in the coverage scan: $f"
      continue
    fi
    if ! inside_repo "$f"; then
      bad "untracked path resolves outside the repo (symlink): $f"
      continue
    fi
    grep -Iq '' "$DIR/$f" || continue
    awk -v p="$f" '{ printf "%s\t%d\t%s\n", p, NR, $0 }' "$DIR/$f"
  done < <(git -C "$DIR" ls-files --others --exclude-standard -z)
}

# py_docstrings FULLPATH RELPATH — "REL<TAB>first<TAB>last" for each docstring
# line range in a Python file, or "NOPARSE<TAB>REL" if the file does not parse.
py_docstrings() {
  python3 -I - "$1" "$2" <<'PYEOF'
import ast, sys

full, rel = sys.argv[1], sys.argv[2]
try:
    with open(full, encoding="utf-8") as fh:
        tree = ast.parse(fh.read())
except (OSError, SyntaxError, ValueError):
    print("NOPARSE\t" + rel)
    sys.exit(0)
kinds = (ast.Module, ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)
for node in ast.walk(tree):
    if isinstance(node, kinds) and ast.get_docstring(node, clean=False) is not None:
        body = node.body[0]
        print("%s\t%d\t%d" % (rel, body.lineno, body.end_lineno))
PYEOF
}

# in_docstring PATH N — true when line N of PATH is inside a docstring range.
in_docstring() {
  awk -F'\t' -v p="$1" -v n="$2" '$1 == p && n >= $2 + 0 && n <= $3 + 0 { f = 1 } END { exit !f }' "$W/docranges"
}

# collect_docstrings — fill $W/docranges for the .py files among the added lines.
collect_docstrings() {
  local f
  : >"$W/docranges"
  : >"$W/doc.raw"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    py_docstrings "$DIR/$f" "$f" >>"$W/doc.raw"
  done < <(cut -f1 "$W/added" | LC_ALL=C sort -u | grep '\.py$' || true)
  while IFS= read -r f; do
    bad "$f: not parsed as Python; docstring coverage cannot be established"
  done < <(awk -F'\t' '$1 == "NOPARSE" { print $2 }' "$W/doc.raw")
  awk -F'\t' '$1 != "NOPARSE"' "$W/doc.raw" >"$W/docranges"
}

check_comments() {
  CUR=1
  fenced_block "Comment fidelity" || return 0
  none_exclusive "$BLOCK" || return 0
  : >"$W/quoted"
  local line path text
  while IFS= read -r line; do
    line=$(trim "$line")
    [ -n "$line" ] || continue
    [ "$line" = none ] && continue
    case $line in
      *': '*) ;;
      *) bad "malformed line (want PATH: TEXT): $line"; continue ;;
    esac
    path=${line%%: *}
    text=$(trim "${line#*: }")
    case $path in
      /*|*..*|'~'*|'$'*) bad "path outside the repo or a symlink: $path"; continue ;;
    esac
    if ! inside_repo "$path"; then
      bad "path outside the repo or a symlink: $path"
    elif [ ! -f "$DIR/$path" ]; then
      bad "file missing: $path: $text"
    elif [ -z "$text" ]; then
      bad "empty quote: $path"
    else
      sed 's/^[[:space:]]*//; s/[[:space:]]*$//' "$DIR/$path" >"$W/trimmed"
      if grep -qxF -- "$text" "$W/trimmed"; then
        printf '%s\t%s\n' "$path" "$text" >>"$W/quoted"
        ok "$path: $text"
      else
        bad "not in tree: $path: $text"
      fi
    fi
  done <<<"$BLOCK"

  added_lines >"$W/added"
  collect_docstrings
  local p n t tt total=0 uncovered=0 is_comment
  while IFS=$'\t' read -r p n t; do
    case ${p##*.} in
      md|rst|txt|adoc|MD|RST|TXT|ADOC) continue ;;
    esac
    tt=$(trim "$t")
    [ -n "$tt" ] || continue
    case $tt in '#!'*) continue ;; esac
    is_comment=0
    if [[ $tt =~ $COMMENT_RE ]]; then
      is_comment=1
    elif [ "${p##*.}" = py ] && in_docstring "$p" "$n"; then
      is_comment=1
    fi
    [ "$is_comment" -eq 1 ] || continue
    total=$((total + 1))
    if ! grep -qxF -- "$p"$'\t'"$tt" "$W/quoted"; then
      uncovered=$((uncovered + 1))
      bad "uncovered: $p:+$n: $tt"
    fi
  done <"$W/added"
  if [ "$uncovered" -eq 0 ]; then
    ok "coverage: $total added comment line(s), all quoted"
  fi
}

# --- section 2: counts -------------------------------------------------------

# cmd_helper LINE — evaluate one Counts line. LINE must match one of six fixed
# forms (see the header). Prints "REJECT <message>" and exits 3 when it does not,
# or when a path, ref or regex fails validation; otherwise prints the count or
# listing. git runs with fixed arguments and an isolated environment.
cmd_helper() {
  python3 -I - "$1" "$DIR" "$W" <<'PYEOF'
import os, re, shlex, signal, subprocess, sys

line, repo, work = sys.argv[1], sys.argv[2], sys.argv[3]
ROOT = os.path.realpath(repo)
REF_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/~^-]*$")


def reject(msg):
    print("REJECT " + msg)
    sys.exit(3)


def unsupported():
    reject("not a supported count form: $ " + line)


def on_alarm(signum, frame):
    reject("timeout: $ " + line)


signal.signal(signal.SIGALRM, on_alarm)
signal.alarm(60)


def run_git(argv):
    home = os.path.join(work, "home")
    os.makedirs(home, exist_ok=True)
    env = {"PATH": os.environ.get("PATH", ""), "LC_ALL": "C", "HOME": home,
           "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
           "GIT_OPTIONAL_LOCKS": "0", "GIT_LITERAL_PATHSPECS": "1",
           "GIT_INDEX_FILE": os.path.join(work, "index")}
    try:
        p = subprocess.run(argv, cwd=repo, env=env, stdin=subprocess.DEVNULL,
                           stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=60)
    except subprocess.TimeoutExpired:
        reject("timeout: $ " + line)
    except OSError as e:
        reject("cannot start git: " + str(e))
    return p.returncode, p.stdout


def check_ref(ref):
    if not REF_RE.match(ref) or ".." in ref:
        unsupported()
    rc, _ = run_git(["git", "rev-parse", "--verify", "-q", ref + "^{commit}"])
    if rc != 0:
        unsupported()


def check_path(p, kind):
    def bad():
        reject("path outside the repo or a symlink: " + p)

    if not p or p.startswith(("/", "~", "$")) or ".." in p or "\0" in p:
        bad()
    full = os.path.join(repo, p)
    if not os.path.lexists(full):
        bad()
    cur = repo
    for part in [c for c in p.split("/") if c not in ("", ".")]:
        cur = os.path.join(cur, part)
        if os.path.islink(cur):
            bad()
    real = os.path.realpath(full)
    if not (real == ROOT or real.startswith(ROOT + os.sep)):
        bad()
    if kind == "file" and not os.path.isfile(full):
        bad()
    if kind == "dir" and not os.path.isdir(full):
        bad()
    return full


def out(text):
    sys.stdout.write(text)
    if text and not text.endswith("\n"):
        sys.stdout.write("\n")


try:
    toks = shlex.split(line, posix=True)
except ValueError:
    unsupported()
n = len(toks)
if n == 4 and toks[:3] in (["git", "diff", "--stat"], ["git", "diff", "--name-status"]):
    check_ref(toks[3])
    rc, data = run_git(["git", "diff", toks[2], toks[3]])
    if rc != 0:
        reject("git exited %d: $ %s" % (rc, line))
    out(data.decode("utf-8", "replace"))
elif n in (2, 3) and toks[:2] == ["git", "ls-files"]:
    argv = ["git", "ls-files"]
    if n == 3:
        check_path(toks[2], "any")
        argv += ["--", toks[2]]
    rc, data = run_git(argv)
    if rc != 0:
        reject("git exited %d: $ %s" % (rc, line))
    out(data.decode("utf-8", "replace"))
elif n == 2 and toks[0] == "ls":
    full = check_path(toks[1], "dir")
    out("\n".join(sorted(os.listdir(full))))
elif n == 2 and toks[0] == "lines":
    full = check_path(toks[1], "file")
    with open(full, "rb") as fh:
        raw = fh.read()
    print(raw.count(b"\n") + (1 if raw and not raw.endswith(b"\n") else 0))
elif n == 3 and toks[0] == "count":
    try:
        rx = re.compile(toks[1])
    except re.error:
        reject("invalid regex: $ " + line)
    full = check_path(toks[2], "file")
    with open(full, "rb") as fh:
        text = fh.read().decode("utf-8", "replace")
    rows = text.split("\n")
    if rows and rows[-1] == "":
        rows.pop()
    print(sum(1 for r in rows if rx.search(r)))
else:
    unsupported()
PYEOF
}

# normalize — strip trailing whitespace per line; drop trailing empty lines.
normalize() {
  sed 's/[[:space:]]*$//' | awk '{ a[NR] = $0 } END { n = NR; while (n > 0 && a[n] == "") n--; for (i = 1; i <= n; i++) print a[i] }'
}

CMD=""
CMD_COUNT=0
flush_cmd() {
  [ -n "$CMD" ] || return 0
  local cmd rc=0
  cmd=$(trim "$CMD")
  CMD=""
  CMD_COUNT=$((CMD_COUNT + 1))
  normalize <"$W/exp" >"$W/exp.n"
  cmd_helper "$cmd" >"$W/act.raw" || rc=$?
  if [ "$rc" -eq 3 ]; then
    bad "$(sed -n '1s/^REJECT //p' "$W/act.raw")"
    return 0
  elif [ "$rc" -ne 0 ]; then
    bad "helper failed (exit $rc): \$ $cmd"
    return 0
  fi
  if [ ! -s "$W/exp.n" ]; then
    bad "empty expected output: \$ $cmd (paste the command's output; if it prints nothing, use a count form)"
    return 0
  fi
  normalize <"$W/act.raw" >"$W/act.n"
  if cmp -s "$W/exp.n" "$W/act.n"; then
    ok "\$ $cmd"
  else
    bad "\$ $cmd"
    show_block expected "$W/exp.n"
    show_block actual "$W/act.n"
  fi
}

check_counts() {
  CUR=2
  fenced_block "Counts" || return 0
  local line
  CMD=""
  CMD_COUNT=0
  : >"$W/exp"
  while IFS= read -r line; do
    case $line in
      '$ '*|'$')
        flush_cmd
        : >"$W/exp"
        if [ -z "$(trim "${line#\$}")" ]; then
          CMD_COUNT=$((CMD_COUNT + 1))
          bad "not a supported count form: \$ (empty command)"
        else
          CMD=${line#\$ }
        fi ;;
      *)
        if [ -n "$CMD" ]; then
          printf '%s\n' "$line" >>"$W/exp"
        elif [ "$CMD_COUNT" -eq 0 ] && [ -n "$(trim "$line")" ]; then
          bad "content before the first command: $line"
        fi ;;
    esac
  done <<<"$BLOCK"
  flush_cmd
  if [ "$CMD_COUNT" -eq 0 ]; then
    bad "no commands declared (a line starting with \"\$ \")"
  fi
}

# --- section 3: sibling sweep ------------------------------------------------

# sweep_matches FILE — FILE is `git grep -nE --null` output. Prints PATH:LINE for
# every match on stdout and one failure message per line that is not a match on
# stderr. A line splits at its first NUL into the path and the rest, so a colon
# in a file name is harmless. Nothing is dropped without a message.
sweep_matches() {
  python3 -I - "$1" <<'PYEOF'
import re, sys

with open(sys.argv[1], "rb") as fh:
    data = fh.read()
rest_re = re.compile(rb"^([0-9]+)[\0:]")
for raw in data.split(b"\n"):
    if not raw:
        continue
    name, sep, rest = raw.partition(b"\0")
    if not sep:
        if raw.startswith(b"Binary file "):
            shown = raw[len(b"Binary file "):]
            if shown.endswith(b" matches"):
                shown = shown[: -len(b" matches")]
            sys.stderr.write("binary file matches the sibling pattern (binary files cannot be declared; narrow the pattern or remove the file from the sweep): "
                             + shown.decode("utf-8", "replace") + "\n")
        else:
            sys.stderr.write("unparseable sweep output: " + raw.decode("utf-8", "replace") + "\n")
        continue
    m = rest_re.match(rest)
    if not m:
        sys.stderr.write("unparseable sweep output: " + raw.decode("utf-8", "replace").replace("\0", "<NUL>") + "\n")
        continue
    sys.stdout.write(name.decode("utf-8", "replace") + ":" + m.group(1).decode() + "\n")
PYEOF
}

PAT=""
PAT_SET=0
flush_pattern() {
  [ "$PAT_SET" -eq 1 ] || return 0
  PAT_SET=0
  if [ "$PAT" = none ]; then
    note "no pattern declared"
    return 0
  fi
  local rc=0 e
  git -C "$DIR" grep -nE --untracked --null -e "$PAT" >"$W/grep.raw" 2>"$W/grep.err" || rc=$?
  if [ "$rc" -gt 1 ]; then
    bad "pattern does not run: $PAT ($(head -n 1 "$W/grep.err"))"
    return 0
  fi
  sweep_matches "$W/grep.raw" >"$W/matches.raw" 2>"$W/matches.err" || {
    bad "sweep output could not be read"
    return 0
  }
  LC_ALL=C sort -u "$W/matches.raw" >"$W/matches"
  while IFS= read -r e; do
    [ -n "$e" ] && bad "$e"
  done <"$W/matches.err"
  LC_ALL=C sort -u "$W/decl" >"$W/decl.s"
  local bad_before=0
  [ ! -e "$W/failed.3" ] || bad_before=1
  while IFS= read -r e; do
    [ -n "$e" ] && bad "unlisted match $e"
  done < <(LC_ALL=C comm -23 "$W/matches" "$W/decl.s")
  while IFS= read -r e; do
    [ -n "$e" ] && bad "stale entry $e"
  done < <(LC_ALL=C comm -13 "$W/matches" "$W/decl.s")
  while IFS= read -r e; do
    [ -n "$e" ] && note "declared fail: $e"
  done <"$W/declfail"
  if [ "$bad_before" -eq 0 ] && [ ! -e "$W/failed.3" ]; then
    ok "pattern $PAT ($(wc -l <"$W/matches" | tr -d ' ') matches, all declared)"
  fi
}

check_sweep() {
  CUR=3
  fenced_block "Sibling sweep" || return 0
  none_exclusive "$BLOCK" || return 0
  if is_none "$BLOCK"; then
    note "no pattern declared"
    return 0
  fi
  local line reason ep re='^(.+):([0-9]+):[[:space:]]*(pass|fail)([[:space:]].*)?$'
  PAT="" PAT_SET=0
  : >"$W/decl"
  : >"$W/declfail"
  while IFS= read -r line; do
    line=$(trim "$line")
    [ -n "$line" ] || continue
    case $line in
      'pattern: '*)
        flush_pattern
        PAT=$(trim "${line#pattern: }")
        PAT_SET=1
        : >"$W/decl"
        : >"$W/declfail" ;;
      *)
        if [ "$PAT_SET" -eq 0 ]; then
          bad "entry before any pattern: $line"
        elif [[ $line =~ $re ]]; then
          ep="${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
          printf '%s\n' "$ep" >>"$W/decl"
          if [ "${BASH_REMATCH[3]}" = fail ]; then
            reason=$(trim "${BASH_REMATCH[4]}")
            if [ -z "$reason" ]; then
              bad "declared fail without a reason: $ep"
            else
              printf '%s (%s)\n' "$ep" "$reason" >>"$W/declfail"
            fi
          fi
        else
          bad "malformed entry (want PATH:LINE: pass|fail): $line"
        fi ;;
    esac
  done <<<"$BLOCK"
  flush_pattern
  if [ ! -e "$W/failed.3" ] && ! grep -q . "$W/out.3"; then
    bad "no pattern declared (use \"pattern: none\" or none)"
  fi
}

# --- section 4: premise table ------------------------------------------------

lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

PREM_PASS=0
okp() { PREM_PASS=$((PREM_PASS + 1)); ok "$@"; }

# has_heading FILE HEADING — true when a line of FILE is an ATX heading whose
# text equals HEADING (case-insensitive) or, outside Markdown files, a line that
# consists of HEADING alone. A mention inside a paragraph does not count.
has_heading() {
  python3 -I - "$1" "$2" <<'PYEOF'
import re, sys

path, want = sys.argv[1], sys.argv[2].strip().lower()
markdown = path.lower().endswith((".md", ".markdown"))
atx = re.compile(r"^#{1,6}[ \t]+(.*?)[ \t]*#*[ \t]*$")
atx_raw = re.compile(r"^#{1,6}[ \t]+(.*?)[ \t]*$")
with open(path, encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line = line.rstrip("\r\n")
        for rx in (atx, atx_raw):
            m = rx.match(line)
            if m and m.group(1).strip().lower() == want:
                sys.exit(0)
        if not markdown and line.strip().lower() == want:
            sys.exit(0)
sys.exit(1)
PYEOF
}

resolve_source() {
  local s path rev heading n lines
  s=$(trim "$1")
  s=${s#\`}
  s=${s%\`}
  s=$(trim "$s")
  [ -n "$s" ] || { bad "empty source"; return 0; }
  local re_tracker='^(#|[A-Za-z0-9._/-]+#)[0-9]+$'
  local re_line='^(.+):([0-9]+)$'
  case $s in
    http://*|https://*) note "URL not checked: $s"; return 0 ;;
  esac
  if [[ $s =~ $re_tracker ]]; then
    note "tracker ref not checked: $s"
    return 0
  fi
  case $s in
    *§*) path=$(trim "${s%%§*}") ;;
    *@*) path=${s%%@*} ;;
    *) if [[ $s =~ $re_line ]]; then path=${BASH_REMATCH[1]}; else path=$s; fi ;;
  esac
  case $path in
    /*|'~'*|'$'*|*..*) bad "path outside the repo or a symlink: $s"; return 0 ;;
  esac
  if ! inside_repo "$path"; then
    bad "path outside the repo or a symlink: $path"
    return 0
  fi
  case $s in
    *§*)
      path=$(trim "${s%%§*}")
      heading=$(trim "${s#*§}")
      heading=${heading#"${heading%%[!#[:space:]]*}"}
      if [ -z "$path" ] || [ -z "$heading" ]; then
        bad "unparseable source: $s"
      elif [ ! -f "$DIR/$path" ]; then
        bad "$s: file missing"
      elif has_heading "$DIR/$path" "$heading"; then
        okp "$s"
      else
        bad "section heading not found: $path §$heading"
      fi
      return 0 ;;
    *@*)
      path=${s%%@*}
      rev=${s#*@}
      if [ -z "$path" ] || [ -z "$rev" ] || [[ $rev == -* ]]; then
        bad "unparseable source: $s"
      elif git -C "$DIR" cat-file -e "$rev:$path" 2>/dev/null; then
        okp "$s"
      else
        bad "$s does not resolve"
      fi
      return 0 ;;
  esac
  if [[ $s =~ $re_line ]]; then
    path=${BASH_REMATCH[1]}
    n=${BASH_REMATCH[2]}
    if [ ! -f "$DIR/$path" ]; then
      bad "$s: file missing"
    else
      lines=$(grep -c '' "$DIR/$path" || true)
      if [ "$n" -ge 1 ] && [ "$n" -le "$lines" ]; then
        okp "$s"
      else
        bad "$s: line out of range (file has $lines)"
      fi
    fi
    return 0
  fi
  case $s in
    *[[:space:]]*) bad "unparseable source: $s" ;;
    *)
      if [ -e "$DIR/$s" ]; then okp "$s"; else bad "$s: path missing"; fi ;;
  esac
}

check_premises() {
  CUR=4
  local body table
  load_section "Premise table" || return 0
  body=$BODY
  table=$(printf '%s\n' "$body" | awk '/^[[:space:]]*\|/ { t = 1; print; next } t { exit }')
  local tables
  tables=$(printf '%s\n' "$body" | awk '/^[[:space:]]*\|/ { if (!t) n++; t = 1; next } { t = 0 } END { print n + 0 }')
  if [ "$tables" -gt 1 ]; then
    bad "more than one table under the heading (one table per section)"
    return 0
  fi
  local row cells=() c i src_idx=-1 prem_idx=-1 chk_idx=-1 res_idx=-1 data=0 first=1 cell expect_sep=0 has_none=0 others
  if printf '%s\n' "$body" | grep -qx '[[:space:]]*none[[:space:]]*'; then has_none=1; fi
  if [ "$has_none" -eq 1 ]; then
    others=$(printf '%s\n' "$body" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -cvx -e '' -e none || true)
    if [ "$others" -gt 0 ]; then
      bad "none must be the only content in the section"
      return 0
    fi
  fi
  local srcs=() s
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    row=$(trim "$row")
    row=${row#|}
    row=${row%|}
    if [ "$first" -eq 1 ]; then
      first=0
      IFS='|' read -r -a cells <<<"$row"
      i=0
      for c in "${cells[@]}"; do
        c=$(lower "$(trim "$c")")
        case $c in *premise*) prem_idx=$i ;; esac
        case $c in *source*) src_idx=$i ;; esac
        case $c in *"check performed"*) chk_idx=$i ;; esac
        case $c in *result*) res_idx=$i ;; esac
        i=$((i + 1))
      done
      if [ "$prem_idx" -lt 0 ] || [ "$src_idx" -lt 0 ] || [ "$chk_idx" -lt 0 ] || [ "$res_idx" -lt 0 ]; then
        bad "table header must contain premise, source, check performed and result columns"
        return 0
      fi
      expect_sep=1
      continue
    fi
    if [ "$expect_sep" -eq 1 ]; then
      expect_sep=0
      if ! [[ $row =~ ^[|:[:space:]-]+$ ]]; then
        bad "table has no header separator row"
        return 0
      fi
      continue
    fi
    [[ $row =~ ^[|:[:space:]-]+$ ]] && continue
    data=$((data + 1))
    IFS='|' read -r -a cells <<<"$row"
    if [ -z "$(trim "${cells[$prem_idx]:-}")" ] || [ -z "$(trim "${cells[$src_idx]:-}")" ] ||
      [ -z "$(trim "${cells[$chk_idx]:-}")" ] || [ -z "$(trim "${cells[$res_idx]:-}")" ]; then
      bad "premise row $data incomplete (premise, source, check performed and result are all required)"
      continue
    fi
    cell=$(trim "${cells[$src_idx]}")
    IFS=';' read -r -a srcs <<<"$cell"
    for s in "${srcs[@]}"; do
      resolve_source "$s"
    done
  done <<<"$table"
  if [ "$data" -gt 0 ] && [ "$PREM_PASS" -eq 0 ]; then
    bad "no premise resolved against the tree (URLs and tracker refs are not checked; cite a path, path@rev, path:N or path §heading as well)"
  fi
  if [ "$data" -eq 0 ]; then
    if [ "$has_none" -eq 1 ]; then
      note "no premises declared (none)"
    else
      bad "no premises declared"
    fi
  fi
}

# --- run and report ----------------------------------------------------------

check_comments
check_counts
check_sweep
check_premises

failed_list=""
for n in 1 2 3 4; do
  if [ -e "$W/failed.$n" ]; then
    failed_list="${failed_list:+$failed_list,}$n"
  fi
done

if [ -n "$failed_list" ]; then
  verdict="PRE-GATE: FAIL (sections: $failed_list)"
  status=1
else
  verdict="PRE-GATE: PASS"
  status=0
fi

if command -v shasum >/dev/null 2>&1; then
  sha=$(shasum -a 256 "$REPORT" | awk '{print $1}')
else
  sha=$(sha256sum "$REPORT" | awk '{print $1}')
fi
head_sha=$(git -C "$DIR" rev-parse --short HEAD)
dirty=$(git -C "$DIR" status --porcelain | wc -l | tr -d ' ')

printf '<!-- PRE-GATE-CHECK-BEGIN -->\n'
printf '%s\n' "$verdict"
printf 'repo: %s head: %s base: %s dirty-files: %s report-sha256: %s\n' "$DIR" "$head_sha" "$BASE" "$dirty" "$sha"
printf '## 1 Comment fidelity\n'; cat "$W/out.1"
printf '## 2 Counts\n';           cat "$W/out.2"
printf '## 3 Sibling sweep\n';    cat "$W/out.3"
printf '## 4 Premise table\n';    cat "$W/out.4"
printf '<!-- PRE-GATE-CHECK-END -->\n'
exit "$status"
