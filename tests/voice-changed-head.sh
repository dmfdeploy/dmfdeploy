#!/usr/bin/env bash
# voice-changed-head.sh — regression for bin/check-voice-changed.sh (#672).
#
# The script lists the changed files from BASE..HEAD. It must also read the
# content of each head file, and HEAD's Vale rules, from the HEAD commit and
# never from the working tree. Cases in a throwaway repo, each one with a
# working tree that differs from HEAD on the input under test, so that
# reverting that one read in the script makes its case fail:
#
#   side    the working tree is at BASE; HEAD adds an em dash. Expect exit 1,
#           with the file named. Guards the content read.
#   dirty   the working tree has an em dash that HEAD does not. Expect 0.
#   rules   HEAD has the EmDash rule; the working tree lacks it. Expect 1.
#   config  HEAD's .vale.ini lints README.md; the working tree's does not.
#           Expect 1. Guards the .vale.ini read.
#   exists  HEAD adds a file that the working tree lacks. Expect 1. Guards
#           the existence check.
#   scope   HEAD's .vale.ini lints a file that the working tree's does not.
#           Expect 1. Guards the .vale.ini read and the scope probe.
#   probe   the working-tree copy of a file turns Vale off. Expect 1. Guards
#           the scope probe, which must lint the HEAD copy.
#   scope-out  The reverse: the working tree's .vale.ini lints a file that
#           HEAD's does not. Expect 0.
#
# Needs vale and python3, like the script. Override the script under test with
# VOICE_SCRIPT=path (used to run this test against an older copy).
set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPT="${VOICE_SCRIPT:-$UMBRELLA_DIR/bin/check-voice-changed.sh}"
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1" >&2; fail=$((fail + 1)); }

command -v vale >/dev/null || { echo "voice-changed-head: vale is not installed" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dmf-voice-head.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
dash="$(printf '\xe2\x80\x94')"

# A fixture repo with the rules, the script under test, and a linted README.
R="$WORK/repo"
mkdir -p "$R/bin"
cp "$UMBRELLA_DIR/.vale.ini" "$R/"
cp -R "$UMBRELLA_DIR/.vale" "$R/.vale"
cp "$SCRIPT" "$R/bin/check-voice-changed.sh"
g() { git -C "$R" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
g init -q -b main
printf '%s\n' '# Title' '' 'The base page is plain.' >"$R/README.md"
cp "$R/README.md" "$R/NOTES.md"; cp "$R/README.md" "$R/CONTRIBUTING.md"
g add -A && g commit -q -m base
BASE="$(g rev-parse HEAD)"

# side: the em dash exists only on a side commit; the checkout stays at BASE.
g checkout -q -b side
printf '%s\n' '# Title' '' "The side page adds a pause $dash like this." >"$R/README.md"
g commit -q -am side
SIDE="$(g rev-parse HEAD)"
g checkout -q main
out="$(cd "$R" && bash bin/check-voice-changed.sh "$BASE" "$SIDE" 2>&1)"; rc=$?
[[ $rc -eq 1 ]] && ok "side commit with an em dash exits 1" || bad "side: exit $rc, want 1"
grep -q 'README.md' <<<"$out" && ok "side: README.md is named" || bad "side: README.md not named"

# dirty: HEAD is clean; only the working tree has an em dash.
g checkout -q -b clean "$BASE"
printf '%s\n' '# Title' '' 'The clean page stays plain.' >"$R/README.md"
g commit -q -am clean
CLEAN="$(g rev-parse HEAD)"
printf '%s\n' '# Title' '' "A stray $dash in the working tree." >"$R/README.md"
out="$(cd "$R" && bash bin/check-voice-changed.sh "$BASE" "$CLEAN" 2>&1)"; rc=$?
[[ $rc -eq 0 ]] && ok "dirty working tree is ignored, exit 0" || bad "dirty: exit $rc, want 0: $out"

reset() { g checkout -q -f main && g clean -q -fd; }
run() { out="$(cd "$R" && bash bin/check-voice-changed.sh "$1" "$2" 2>&1)"; rc=$?; }
dashline() { printf '%s\n' '# Title' '' "A page with a pause $dash here."; }

# rules: HEAD keeps the EmDash rule; the working tree has lost it.
reset
g checkout -q -b rules "$BASE"
dashline >"$R/README.md"; g commit -q -am rules
RULES="$(g rev-parse HEAD)"; reset
rm "$R/.vale/styles/Voice/EmDash.yml"
run "$BASE" "$RULES"
[[ $rc -eq 1 ]] && ok "rules: HEAD's rules apply, exit 1" || bad "rules: exit $rc, want 1: $out"
reset

# config: HEAD's .vale.ini lints README.md; the working tree's does not.
sed -i.bak 's/^BasedOnStyles = .*/BasedOnStyles =/' "$R/.vale.ini"; rm -f "$R/.vale.ini.bak"
run "$BASE" "$RULES"
[[ $rc -eq 1 ]] && ok "config: HEAD's .vale.ini applies, exit 1" || bad "config: exit $rc, want 1: $out"
reset

# exists: HEAD adds ROADMAP.md; the working tree (at main) has no such file.
g checkout -q -b exists "$BASE"
dashline >"$R/ROADMAP.md"; g add -A; g commit -q -m exists
EXISTS="$(g rev-parse HEAD)"; reset
run "$BASE" "$EXISTS"
[[ $rc -eq 1 ]] && ok "exists: a file only in HEAD is checked, exit 1" || bad "exists: exit $rc, want 1: $out"

# scope: HEAD's .vale.ini lints NOTES.md; the working tree's does not. The file
# exists in both, so only the scope differs.
g checkout -q -b scope "$BASE"
printf '\n[NOTES.md]\nBasedOnStyles = Voice\n' >>"$R/.vale.ini"
dashline >"$R/NOTES.md"; g commit -q -am scope
SCOPE="$(g rev-parse HEAD)"; reset
run "$BASE" "$SCOPE"
[[ $rc -eq 1 ]] && ok "scope: in scope at HEAD only, exit 1" || bad "scope: exit $rc, want 1: $out"

# scope-out: the reverse. HEAD's .vale.ini drops CONTRIBUTING.md; the working
# tree's still lints it.
g checkout -q -b scopeout "$BASE"
sed -i.bak '/^\[CONTRIBUTING.md\]/,+1d' "$R/.vale.ini"; rm -f "$R/.vale.ini.bak"
dashline >"$R/CONTRIBUTING.md"; g commit -q -am scopeout
SCOPEOUT="$(g rev-parse HEAD)"; reset
run "$BASE" "$SCOPEOUT"
[[ $rc -eq 0 ]] && ok "scope-out: out of scope at HEAD only, exit 0" || bad "scope-out: exit $rc, want 0: $out"
reset

# probe: the file exists in both, but the working-tree copy turns Vale off, so
# a probe run on the working tree would skip it. The HEAD copy must decide scope.
g checkout -q -b probe "$BASE"
dashline >"$R/CONTRIBUTING.md"; g commit -q -am probe
PROBE="$(g rev-parse HEAD)"; reset
printf '%s\n' '<!-- vale off -->' 'Hidden from Vale.' >"$R/CONTRIBUTING.md"
run "$BASE" "$PROBE"
[[ $rc -eq 1 ]] && ok "probe: the HEAD copy decides scope, exit 1" || bad "probe: exit $rc, want 1: $out"
reset

echo "voice-changed-head: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
