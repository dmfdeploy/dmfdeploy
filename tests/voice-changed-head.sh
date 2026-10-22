#!/usr/bin/env bash
# voice-changed-head.sh — regression for bin/check-voice-changed.sh (#672).
#
# The script lists the changed files from BASE..HEAD. It must also read the
# content of each head file, and HEAD's Vale rules, from the HEAD commit and
# never from the working tree. Two cases in a throwaway repo:
#
#   side  the working tree is at BASE; HEAD is a side commit that adds an em
#         dash. Expect exit 1, with the file named.
#   dirty the working tree has an em dash that HEAD does not. Expect exit 0.
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

echo "voice-changed-head: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
