#!/usr/bin/env bash
# pre-gate-check-selftest — discriminating test for pre-gate-check.sh.
#
# Correctness model: each scenario starts from a fresh copy of a throwaway git
# repo (never the real repo), applies one working-tree edit, writes a report that
# is either clean or broken in exactly one way, and asserts BOTH the exit code
# and the specific result line. A check that stopped discriminating shows up as a
# FAIL for the scenario that targets it. The symlink, escape and empty-command
# scenarios assert the exit status and the specific refusal line.
#
# Exit codes: 0 all scenarios passed, 1 at least one failed.
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CHECK="$HERE/pre-gate-check.sh"
[ -x "$CHECK" ] || { echo "SELFTEST: FAIL (missing $CHECK)"; exit 1; }

S=$(mktemp -d)
trap 'rm -rf "$S"' EXIT
T="$S/work/t"        # the repo under test; $S/work/outside.txt sits beside it
mkdir -p "$S/base" "$S/work"

git -C "$S/base" init -q
git -C "$S/base" config user.name selftest
git -C "$S/base" config user.email selftest@example.invalid
git -C "$S/base" config commit.gpgsign false
mkdir -p "$S/base/src" "$S/base/docs"
printf '#!/usr/bin/env bash\n# cap of 0 means unlimited\necho app\n' >"$S/base/src/app.sh"
printf '#!/usr/bin/env bash\n# cap of 0 means unlimited\necho other\n' >"$S/base/src/other.sh"
printf '# Guide\n\n## Limits\n\nText.\n' >"$S/base/docs/guide.md"
printf 'def f():\n    """Summary line.\n\n    Body one.\n    Body two.\n    """\n    return 1\n' >"$S/base/src/mod.py"
# A file outside the repo, reached through a tracked symlink and a tracked file list.
printf 'outside-proof\n' >"$S/outside-proof.txt"
ln -s "$S/outside-proof.txt" "$S/base/link"
ln -s src/app.sh "$S/base/inlink"
ln -s src "$S/base/dirlink"
AE=$(printf '\303\244')
printf 'a\n' >"$S/base/$AE.txt"
printf '#!/usr/bin/env bash\necho tab\n' >"$S/base/tab"$'\t'"name.sh"
git -C "$S/base" add -A
git -C "$S/base" commit -q -m base

# --- report builder ----------------------------------------------------------

S1="" S2="" S3="" S4="" S4RAW="" OMIT4=0 DUP2="" UNCLOSED2=0 NOSEP=0 S4EXTRA="" CRLF=0 INFO=0
defaults() {
  S1=$'src/app.sh: # cap of 0 means disabled\nsrc/new.sh: # new helper'
  S2=$'$ count \'disabled\' src/app.sh\n1'
  S3=$'pattern: cap of 0\nsrc/app.sh:2: pass\nsrc/other.sh:2: fail left for a follow-up issue'
  S4='| docs/guide.md §Limits |'
  S4RAW="" OMIT4=0 DUP2="" UNCLOSED2=0 NOSEP=0 S4EXTRA="" CRLF=0 INFO=0
}

write_report() {
  local fo='```'
  [ "$INFO" -eq 0 ] || fo='```text'
  {
    printf '# WO report\n\nDONE\n\n'
    printf '## Comment fidelity\n\n%s\n%s\n```\n\n' "$fo" "$S1"
    printf '## Counts\n\n%s\n%s\n' "$fo" "$S2"
    [ "$UNCLOSED2" -eq 1 ] || printf '```\n'
    printf '\n'
    if [ -n "$DUP2" ]; then printf '## Counts\n\n```\n%s\n```\n\n' "$DUP2"; fi
    printf '## Sibling sweep\n\n%s\n%s\n```\n\n' "$fo" "$S3"
    if [ -n "$S4RAW" ]; then
      printf '## Premise table\n\n%s\n' "$S4RAW"
    elif [ "$OMIT4" -eq 0 ]; then
      printf '## Premise table\n\n| premise | source | check performed | result |\n'
      [ "$NOSEP" -eq 1 ] || printf '|---|---|---|---|\n'
      printf '| the limit is documented %s checked | ok |\n' "$S4"
      if [ -n "$S4EXTRA" ]; then printf '\n%s\n' "$S4EXTRA"; fi
    fi
  } >"$S/report.md"
  if [ "$CRLF" -eq 1 ]; then
    awk '{ printf "%s\r\n", $0 }' "$S/report.md" >"$S/report.crlf" && mv "$S/report.crlf" "$S/report.md"
  fi
}

fresh() {
  rm -rf "$T" "$S/work/outside.txt"
  cp -R "$S/base" "$T"
  sed -i.bak 's/means unlimited/means disabled/' "$T/src/app.sh"
  rm -f "$T/src/app.sh.bak"
  printf '#!/usr/bin/env bash\n# new helper\n' >"$T/src/new.sh"
}

# --- assertions --------------------------------------------------------------

OUT="" RC=0 FAILED=0 COUNT=0
run_case() {
  write_report
  RC=0
  OUT=$("$CHECK" --report "$S/report.md" --repo "$T" --base HEAD 2>&1) || RC=$?
}

# section N — the text of section N of the last output.
section() { printf '%s\n' "$OUT" | awk -v n="## $1 " 'index($0, n) == 1 { on = 1; next } /^## / { on = 0 } on'; }

verdict() {
  local id=$1 want_rc=$2 want_verdict=$3 why=""
  COUNT=$((COUNT + 1))
  [ "$RC" -eq "$want_rc" ] || why="exit $RC, want $want_rc"
  [ -n "$why" ] || [ "$(printf '%s\n' "$OUT" | sed -n 2p)" = "$want_verdict" ] || why="verdict line is '$(printf '%s\n' "$OUT" | sed -n 2p)', want '$want_verdict'"
  VERDICT_WHY=$why
  CASE_ID=$id
}

# finish — print the result line for the current scenario; WHY may carry extra failures.
finish() {
  local why=${1:-}
  [ -z "$VERDICT_WHY" ] || why="$VERDICT_WHY${why:+; $why}"
  if [ -z "$why" ]; then
    echo "ok $CASE_ID"
  else
    echo "FAIL $CASE_ID: $why"
    FAILED=1
  fi
}

# need N REGEX — empty if section N has a line matching REGEX, else a reason.
need() { section "$1" | grep -Eq -- "$2" || printf 'section %s lacks /%s/' "$1" "$2"; }

# --- scenarios ---------------------------------------------------------------

OK_CMD=$'$ count \'disabled\' src/app.sh\n1'
STAT=$'$ git diff --stat HEAD\n src/app.sh | 2 +-\n 1 file changed, 1 insertion(+), 1 deletion(-)'

defaults; fresh; S2="$OK_CMD"$'\n'"$STAT"; run_case
verdict clean 0 "PRE-GATE: PASS"
w=""
if printf '%s\n' "$OUT" | grep -q '^fail: '; then w="a fail: line is present"; fi
finish "$w"

defaults; S1='src/app.sh: # cap of 0 means unlimited'; fresh; run_case
verdict stale-comment 1 "PRE-GATE: FAIL (sections: 1)"
finish "$(need 1 '^fail: not in tree')"

defaults; S1='src/app.sh: cap of 0 means disabled'; fresh; run_case
verdict stale-substring 1 "PRE-GATE: FAIL (sections: 1)"
finish "$(need 1 '^fail: not in tree')"

defaults; S1='none'; fresh; run_case
verdict uncovered-comment 1 "PRE-GATE: FAIL (sections: 1)"
finish "$(need 1 '^fail: uncovered: src/app.sh:\+2: ')"

defaults; S1='src/app.sh: # cap of 0 means disabled'; fresh; run_case
verdict untracked-uncovered 1 "PRE-GATE: FAIL (sections: 1)"
finish "$(need 1 '^fail: uncovered: src/new.sh:\+2: ')"

defaults; fresh
sed -i.bak 's/Body two\./Body two, changed./' "$T/src/mod.py"; rm -f "$T/src/mod.py.bak"
run_case
verdict docstring-body 1 "PRE-GATE: FAIL (sections: 1)"
finish "$(need 1 '^fail: uncovered: src/mod.py:\+5: ')"

defaults; S2=$'$ count \'disabled\' src/app.sh\n2'; fresh; run_case
verdict count-mismatch 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: ')$(need 2 '^  expected:')$(need 2 '^  actual:')"

defaults; S2=$'$ count \'disabled\' src/app.sh'; fresh; run_case
verdict empty-expected 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: empty expected output')"

defaults; fresh; S2="$OK_CMD"$'\n```\n\nSecond block:\n\n```\n$ lines src/app.sh\nincorrect'; run_case
verdict second-block 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: more than one fenced block')"

defaults; fresh; S2="$OK_CMD"$'\n$ lines src/app.sh\n3'; run_case
verdict lines-ok 0 "PRE-GATE: PASS"
finish ""

defaults; fresh; S2="$OK_CMD"$'\n$ ls src\napp.sh\nmod.py\nnew.sh\nother.sh'; run_case
verdict ls-ok 0 "PRE-GATE: PASS"
finish ""

defaults; fresh; S2="$OK_CMD"$'\n$ count \'cap of 0\' src/other.sh\n1'; run_case
verdict count-ok 0 "PRE-GATE: PASS"
finish ""

defaults; fresh; S2="$OK_CMD"$'\n$ git ls-files src\nsrc/app.sh\nsrc/mod.py\nsrc/other.sh'; run_case
verdict ls-files-ok 0 "PRE-GATE: PASS"
finish ""

defaults; fresh; S2="$OK_CMD"$'\n$ grep -c x src/app.sh\nx'; run_case
verdict form-unknown 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: not a supported count form')"

defaults; fresh; S2="$OK_CMD"$'\n$ lines src/app.sh | head\nx'; run_case
verdict form-pipeline 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: not a supported count form')"

defaults; fresh; S2="$OK_CMD"$'\n$ lines src/app.sh extra\nx'; run_case
verdict form-extra-arg 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: not a supported count form')"

defaults; fresh; S2="$OK_CMD"$'\n$ grep -flinkf data\nchanged'; run_case
verdict form-grep-attached 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: not a supported count form')"

defaults; fresh; S2="$OK_CMD"$'\n$ git grep -flinkf -- data\ndata:changed'; run_case
verdict form-git-grep 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: not a supported count form')"

defaults; fresh; S2="$OK_CMD"$'\n$ git diff --stat -x\nx'; run_case
verdict git-bad-ref 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: not a supported count form')"

defaults; fresh; S2="$OK_CMD"$'\n$ git diff --stat HEAD@{0}\nx'; run_case
verdict git-ref-syntax 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: not a supported count form')"

defaults; fresh; S2="$OK_CMD"$'\n$ count x link\n0'; run_case
verdict count-symlink 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: path outside the repo or a symlink')"

defaults; fresh; S2="$OK_CMD"$'\n$ lines inlink\n3'; run_case
verdict lines-symlink-inside 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: path outside the repo or a symlink')"

defaults; fresh; S2="$OK_CMD"$'\n$ ls dirlink\napp.sh'; run_case
verdict ls-dir-symlink 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: path outside the repo or a symlink')"

defaults; fresh; printf 'secret\n' >"$S/work/outside.txt"
S2="$OK_CMD"$'\n$ ls ../\nt'; run_case
verdict ls-escape 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: path outside the repo or a symlink')"

defaults; fresh; S2="$OK_CMD"$'\n$ git ls-files ../x\nx'; run_case
verdict git-ls-files-outside 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: path outside the repo or a symlink')"

defaults; fresh; S2="$OK_CMD"$'\n$ count \'(\' src/app.sh\n0'; run_case
verdict count-bad-regex 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: invalid regex')"

defaults; fresh
printf '[core]\n\tquotePath = false\n' >"$T/.gitconfig"
printf 'b\n' >"$T/$AE.txt"
S2=$'$ git diff --name-status HEAD\nM\tsrc/app.sh\nM\t"\\303\\244.txt"'; run_case
verdict git-config-isolated 0 "PRE-GATE: PASS"
finish ""

defaults; S3=$'pattern: cap of 0\nsrc/app.sh:2: pass'; fresh; run_case
verdict unlisted-sibling 1 "PRE-GATE: FAIL (sections: 3)"
finish "$(need 3 '^fail: unlisted match src/other.sh:')"

defaults; S3=$'pattern: cap of 0\nsrc/app.sh:2: pass\nsrc/other.sh:2: fail'; fresh; run_case
verdict sibling-fail-no-reason 1 "PRE-GATE: FAIL (sections: 3)"
finish "$(need 3 '^fail: declared fail without a reason: src/other.sh:2')"

defaults; S3='n o n e'; fresh; run_case
verdict none-spaced 1 "PRE-GATE: FAIL (sections: 3)"
w="$(need 3 '^fail: ')"
if section 3 | grep -q '^note: no pattern declared'; then w="$w the spaced none was accepted as none"; fi
finish "$w"

defaults; S4='| docs/guide.md §Quotas |'; fresh; run_case
verdict bad-premise 1 "PRE-GATE: FAIL (sections: 4)"
finish "$(need 4 '^fail: ')"

defaults; S4='| https://example.invalid/issue/1 |'; fresh; run_case
verdict premise-urls-only 1 "PRE-GATE: FAIL (sections: 4)"
finish "$(need 4 '^fail: no premise resolved against the tree')"

defaults; fresh; printf 'secret\n' >"$S/work/outside.txt"
S4=$'| /etc/hosts | c | r |\n| second premise | ../outside.txt |'; run_case
verdict premise-escape 1 "PRE-GATE: FAIL (sections: 4)"
w=""
if [ "$(section 4 | grep -c '^fail: path outside the repo')" -ne 2 ]; then w="want two 'path outside the repo' lines"; fi
finish "$w"

defaults; OMIT4=1; fresh; run_case
verdict missing-section 1 "PRE-GATE: FAIL (sections: 4)"
finish "$(need 4 '^fail: section missing')"

defaults; fresh; S1=$'src/app.sh: # cap of 0 means disabled\nsrc/new.sh: # new helper\nlink: outside-proof'; run_case
verdict symlink-comment 1 "PRE-GATE: FAIL (sections: 1)"
finish "$(need 1 '^fail: path outside the repo or a symlink')"

defaults; fresh; S4='| link:1 |'; run_case
verdict symlink-premise 1 "PRE-GATE: FAIL (sections: 4)"
finish "$(need 4 '^fail: path outside the repo or a symlink')"

defaults; fresh; ln -s "$S/outside-proof.txt" "$T/untracked-link"; run_case
verdict untracked-symlink-outside 1 "PRE-GATE: FAIL (sections: 1)"
finish "$(need 1 '^fail: untracked symlink is not allowed in the coverage scan')"

defaults; fresh; ln -s src/app.sh "$T/untracked-inlink"; run_case
verdict untracked-symlink-inside 1 "PRE-GATE: FAIL (sections: 1)"
finish "$(need 1 '^fail: untracked symlink is not allowed in the coverage scan')"

defaults; fresh; touch -t 202001010000 "$T/src/other.sh"
tree_hash() { (cd "$T" && find . -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}'); }
h1=$(tree_hash)
run_case
h2=$(tree_hash)
verdict index-untouched 0 "PRE-GATE: PASS"
w=""
if [ "$h1" != "$h2" ]; then w="a file under the repo changed during the run (.git included)"; fi
finish "$w"

defaults; fresh; DUP2=$'$ count \'disabled\' src/app.sh\n99'; run_case
verdict duplicate-section 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: duplicate section heading')"

defaults; fresh; UNCLOSED2=1; run_case
verdict unterminated-fence 1 "PRE-GATE: FAIL (sections: 2,3,4)"
finish "$(need 2 '^fail: unterminated fenced block')"

defaults; fresh; NOSEP=1; run_case
verdict table-no-separator 1 "PRE-GATE: FAIL (sections: 4)"
finish "$(need 4 '^fail: table has no header separator row')"

defaults; fresh; S3=$'pattern: none\nsrc/app.sh:2: pass'; run_case
verdict none-mixed-sweep 1 "PRE-GATE: FAIL (sections: 3)"
finish "$(need 3 '^fail: none must be the only line')"

defaults; fresh; S1=$'none\nsrc/app.sh: # cap of 0 means disabled'; run_case
verdict none-mixed-comments 1 "PRE-GATE: FAIL (sections: 1)"
finish "$(need 1 '^fail: none must be the only line')"

defaults; fresh; S4EXTRA=none; run_case
verdict none-plus-table 1 "PRE-GATE: FAIL (sections: 4)"
finish "$(need 4 '^fail: none must be the only content')"

defaults; fresh; S4RAW=$'none\nadditional premise: absent-source'; run_case
verdict none-plus-prose 1 "PRE-GATE: FAIL (sections: 4)"
finish "$(need 4 '^fail: none must be the only content')"

defaults; fresh; S2=$'Some prose before the command.\n'"$OK_CMD"; run_case
verdict text-before-command 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: content before the first command')"

defaults; fresh; CRLF=1 INFO=1; run_case
verdict crlf-info-string 0 "PRE-GATE: PASS"
finish ""

defaults; fresh; S2="$OK_CMD"$'\n$ '; run_case
verdict empty-command-last 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: not a supported count form: \$ \(empty command\)')"

defaults; fresh; S2="$OK_CMD"$'\n$ \n$ lines src/app.sh\n3'; run_case
verdict empty-command-between 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: not a supported count form: \$ \(empty command\)')"

defaults; fresh; S2="$OK_CMD"$'\n$ \npasted output of nothing'; run_case
verdict empty-command-with-output 1 "PRE-GATE: FAIL (sections: 2)"
w="$(need 2 '^fail: not a supported count form: \$ \(empty command\)')"
if section 2 | grep -q '^fail: content before the first command'; then w="$w; the output under an empty command was reported as text before the first command"; fi
finish "$w"

defaults; fresh; S2="$OK_CMD"$'\n$    '; run_case
verdict whitespace-command 1 "PRE-GATE: FAIL (sections: 2)"
finish "$(need 2 '^fail: not a supported count form: \$ \(empty command\)')"

defaults; fresh; S1=$'src/app.sh: # cap of 0 means disabled\nsrc/new.sh: # new helper\ninlink: # cap of 0 means disabled'; run_case
verdict comment-path-inside-symlink 1 "PRE-GATE: FAIL (sections: 1)"
finish "$(need 1 '^fail: path outside the repo or a symlink: inlink')"

defaults; fresh; S1=$'src/app.sh: # cap of 0 means disabled\nsrc/new.sh: # new helper\ndirlink/app.sh: # cap of 0 means disabled'; run_case
verdict comment-path-symlink-parent 1 "PRE-GATE: FAIL (sections: 1)"
finish "$(need 1 '^fail: path outside the repo or a symlink: dirlink/app.sh')"

defaults; fresh; S4='| inlink:1 |'; run_case
verdict premise-path-inside-symlink 1 "PRE-GATE: FAIL (sections: 4)"
finish "$(need 4 '^fail: path outside the repo or a symlink: inlink')"

defaults; fresh; S1=$'src/app.sh: # cap of 0 means disabled\nsrc/new.sh: # new helper\n~/x: text'; run_case
verdict comment-path-tilde 1 "PRE-GATE: FAIL (sections: 1)"
finish "$(need 1 '^fail: path outside the repo or a symlink: ~/x')"

defaults; fresh; printf 'cap of 0 here\n' >"$T/src:part.sh"; printf 'cap of 0\0\n' >"$T/blob.bin"
git -C "$T" add 'src:part.sh'; git -C "$T" commit -q -m colon
run_case
verdict sweep-colon-path 1 "PRE-GATE: FAIL (sections: 3)"
finish "$(need 3 '^fail: unlisted match src:part.sh:1')"

defaults; fresh; printf 'cap of 0\0\n' >"$T/blob.bin"
git -C "$T" add blob.bin; git -C "$T" commit -q -m binary
run_case
verdict sweep-binary 1 "PRE-GATE: FAIL (sections: 3)"
finish "$(need 3 '^fail: binary file matches')"

defaults; fresh
printf 'def g():\n    """Summary.\n\n    Details.\n    """\n    return 2\n' >"$T/src/new.py"
S1=$'src/app.sh: # cap of 0 means disabled\nsrc/new.sh: # new helper\nsrc/new.py: """Summary.\nsrc/new.py: Details.\nsrc/new.py: """'; run_case
verdict docstring-blank-line 0 "PRE-GATE: PASS"
finish ""

defaults; fresh; S4RAW=$'| premise | source |\n|---|---|\n| the limit is documented | docs/guide.md §Limits |'; run_case
verdict premise-two-columns 1 "PRE-GATE: FAIL (sections: 4)"
finish "$(need 4 '^fail: table header must have exactly the four columns premise, source, check performed and result')"

defaults; fresh; S4RAW=$'| premise | source | check performed | result |\n|---|---|---|---|\n| | docs/guide.md §Limits | read | ok |\n| the limit is documented | docs/guide.md §Limits | read | ok |'; run_case
verdict premise-row-incomplete 1 "PRE-GATE: FAIL (sections: 4)"
finish "$(need 4 '^fail: premise row 1 incomplete')"

defaults; fresh; printf '# Guide\n\nThe Imaginary word appears only here in a paragraph.\n' >"$T/docs/guide.md"
S4='| docs/guide.md §Imaginary |'; run_case
verdict premise-section-mention-only 1 "PRE-GATE: FAIL (sections: 4)"
finish "$(need 4 '^fail: section heading not found: docs/guide.md §Imaginary')"

defaults; fresh; printf 'def broken(:\n' >"$T/src/bad.py"; run_case
verdict py-parse-failure 1 "PRE-GATE: FAIL (sections: 1)"
finish "$(need 1 '^fail: src/bad.py: not parsed as Python; docstring coverage cannot be established')"

defaults; fresh; printf '# edited\n' >>"$T/tab"$'\t'"name.sh"; run_case
verdict tab-in-filename 1 "PRE-GATE: FAIL (sections: 1)"
finish "$(need 1 '^fail: unsupported file name \(control character, quote or backslash\)')"

defaults; fresh
printf '#!/usr/bin/env bash\nvalue=1\n' >"$T/val.sh"; git -C "$T" add val.sh; git -C "$T" commit -q -m val
sed -i.bak 's/^value=1$/value=1 # always unlimited/' "$T/val.sh"; rm -f "$T/val.sh.bak"
run_case
verdict inline-comment-uncovered 1 "PRE-GATE: FAIL (sections: 1)"
finish "$(need 1 '^fail: uncovered: val.sh:\+2: value=1 # always unlimited')"

defaults; fresh; printf 'echo "a # b"\n' >>"$T/src/new.sh"; run_case
verdict inline-comment-in-string 0 "PRE-GATE: PASS"
finish ""

defaults; fresh; S4RAW=$'| premise source check performed result |\n|---|\n| a.txt |'; run_case
verdict premise-impersonated-columns 1 "PRE-GATE: FAIL (sections: 4)"
finish "$(need 4 '^fail: table header must have exactly the four columns premise, source, check performed and result')"

defaults; fresh; S4RAW=$'| premise | source | check performed | result |\n|-|\n| the limit is documented | docs/guide.md §Limits | read | ok |'; run_case
verdict premise-bad-separator 1 "PRE-GATE: FAIL (sections: 4)"
finish "$(need 4 '^fail: table separator row is malformed')"

defaults; fresh; S4RAW=$'| premise | source | check performed | result |\n|---|---|---|---|\n| the limit is documented | docs/guide.md §Limits | read |\n| the limit is documented | docs/guide.md §Limits | read | ok |'; run_case
verdict premise-row-cell-count 1 "PRE-GATE: FAIL (sections: 4)"
finish "$(need 4 '^fail: premise row 1 has 3 cells, want 4')"

defaults; fresh; printf '# Document\n\n```\n## Imaginary\n```\n' >"$T/docs/guide.md"
S4='| docs/guide.md §Imaginary |'; run_case
verdict heading-in-fence 1 "PRE-GATE: FAIL (sections: 4)"
finish "$(need 4 '^fail: section heading not found: docs/guide.md §Imaginary')"

defaults; fresh; mkdir "$T/hid"; : >"$T/hid/.hidden"; printf 'x\n' >"$T/hid/visible"
S2="$OK_CMD"$'\n$ ls hid\nvisible'; run_case
verdict ls-hidden 0 "PRE-GATE: PASS"
finish ""

if [ "$FAILED" -eq 0 ]; then
  echo "SELFTEST: PASS ($COUNT scenarios)"
  exit 0
fi
echo "SELFTEST: FAIL"
exit 1
