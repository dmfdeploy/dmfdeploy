#!/usr/bin/env bash
# voice-changed-links.sh: regression for bin/check-voice-changed.sh (#682).
#
# Vale before 3.25.1 decoded each link target and masked the decoded text in
# the source. A target with '%20' or '+' decodes to words the source does not
# hold at that spot, so Vale masked those words wherever they first occurred,
# and an em dash on a later line could go unreported (vale-cli/vale#1218).
# The ratchet worked around that by rewriting the targets; with the fix in
# Vale, it lints the files as they are. Cases:
#
#   vale     The installed Vale reports every em dash in a page with
#            percent-encoded or '+' targets, the same count as with plain
#            targets. Fails on Vale 3.24.0.
#
# Then, in a throwaway repo:
#
#   encoded  BASE has percent-encoded link targets; HEAD has the same prose
#            with plain targets. Expect exit 0.
#   plus     The same with '+' in the BASE targets. Expect exit 0.
#   hidden   BASE has plain targets; HEAD encodes them and adds one em dash.
#            Expect exit 1, with the file named. Guards the HEAD side.
#   added    Both sides have encoded targets; HEAD adds one em dash. Expect 1.
#
# Needs vale and python3, like the script. Override the script under test with
# VOICE_SCRIPT=path (used to run this test against an older copy).
set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPT="${VOICE_SCRIPT:-$UMBRELLA_DIR/bin/check-voice-changed.sh}"
pass=0; fail=0
ok()  { echo "  ok: $1"; pass=$((pass + 1)); }
bad() { echo "  FAIL: $1" >&2; fail=$((fail + 1)); }

command -v vale >/dev/null || { echo "voice-changed-links: vale is not installed" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dmf-voice-links.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
dash="$(printf '\xe2\x80\x94')"

# page <target> [extra line]: a README whose second em dash Vale before
# 3.25.1 missed when <target> is percent-encoded.
page() {
  printf '%s\n' '# Title' '' "See [Shell Plan]($1)." '' \
    "- The bell moves $dash see the plan." \
    "- The LED stays $dash see [Shell Plan]($1)." ${2:+"$2"}
}

# vale: count the Voice.EmDash alerts in each page directly.
V="$WORK/vale"
mkdir -p "$V"
printf '%s\n' "StylesPath = $UMBRELLA_DIR/.vale/styles" 'MinAlertLevel = error' \
  '[*.md]' 'BasedOnStyles = Voice' >"$V/.vale.ini"
dashes() { # dashes <target>: the Voice.EmDash alerts Vale reports for page <target>
  page "$1" >"$V/page.md"
  (cd "$V" && vale --no-exit --output=line --config .vale.ini page.md) \
    | grep -c 'Voice.EmDash'
}
want="$(dashes 'the-shell-plan.md')"
[[ "$want" -eq 2 ]] && ok "vale: plain targets give 2 em dash alerts" \
  || bad "vale: plain targets give $want em dash alerts, want 2"
for t in 'The%20Shell%20Plan.md' 'The+Shell+Plan.md'; do
  got="$(dashes "$t")"
  [[ "$got" -eq "$want" ]] && ok "vale: $t gives the same count" \
    || bad "vale: $t gives $got em dash alerts, want $want ($(vale --version); needs 3.25.1 or later)"
done

R="$WORK/repo"
mkdir -p "$R/bin"
cp "$UMBRELLA_DIR/.vale.ini" "$R/"
cp -R "$UMBRELLA_DIR/.vale" "$R/.vale"
cp "$SCRIPT" "$R/bin/check-voice-changed.sh"
g() { git -C "$R" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false "$@"; }
g init -q -b main
printf '%s\n' '# Title' '' 'The base page is plain.' >"$R/README.md"
g add -A && g commit -q -m init
INIT="$(g rev-parse HEAD)"

commit() { # commit <branch> <from>: commit README.md from stdin, print the SHA
  g checkout -q -b "$1" "$2"
  cat >"$R/README.md"
  g commit -q -am "$1"
  g rev-parse HEAD
}
run() { out="$(cd "$R" && bash bin/check-voice-changed.sh "$1" "$2" 2>&1)"; rc=$?; }

ENC="$(page 'The%20Shell%20Plan.md' | commit enc "$INIT")"
PLUS="$(page 'The+Shell+Plan.md' | commit plus "$INIT")"
PLAIN="$(page 'the-shell-plan.md' | commit plain "$INIT")"

# encoded: only the link targets change, from encoded to plain.
run "$ENC" "$(page 'the-shell-plan.md' | commit enc-fixed "$ENC")"
[[ $rc -eq 0 ]] && ok "encoded: plain targets at HEAD only, exit 0" || bad "encoded: exit $rc, want 0: $out"

# plus: the same with '+' in the BASE targets.
run "$PLUS" "$(page 'the-shell-plan.md' | commit plus-fixed "$PLUS")"
[[ $rc -eq 0 ]] && ok "plus: plain targets at HEAD only, exit 0" || bad "plus: exit $rc, want 0: $out"

# hidden: HEAD encodes the targets and adds an em dash.
run "$PLAIN" "$(page 'The%20Shell%20Plan.md' "- A new line $dash with a pause." | commit hidden "$PLAIN")"
[[ $rc -eq 1 ]] && ok "hidden: an em dash added at HEAD exits 1" || bad "hidden: exit $rc, want 1: $out"
grep -q 'README.md' <<<"$out" && ok "hidden: README.md is named" || bad "hidden: README.md not named"

# added: both sides encoded; HEAD adds an em dash.
run "$ENC" "$(page 'The%20Shell%20Plan.md' "- A new line $dash with a pause." | commit added "$ENC")"
[[ $rc -eq 1 ]] && ok "added: an em dash added at HEAD exits 1" || bad "added: exit $rc, want 1: $out"

echo "voice-changed-links: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
