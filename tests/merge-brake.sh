#!/usr/bin/env bash
# merge-brake.sh tests: the hold predicate behind the merge-brake check
# (umbrella #439). Each case feeds a label list to the script and asserts its
# exit status: 0 lets the PR merge, 1 holds it, 2 rejects the input.
#
#   A  no labels                                -> 0
#   B  other labels only                        -> 0
#   C  hold                                     -> 1
#   D  hold among other labels                  -> 1
#   E  labels that only contain the word hold   -> 0
#   F  labels key missing                       -> 2
#   G  labels is not an array                   -> 2
#   H  a label is not a string                  -> 2
#   I  empty input                              -> 2
#   J  input is not JSON                        -> 2
#   K  two JSON documents                       -> 2
#
# Hermetic: no network or credential. Set BRAKE to test another copy of the
# script, which is how the mutation check runs.
set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
BRAKE="${BRAKE:-$UMBRELLA_DIR/.github/scripts/merge-brake.sh}"
pass=0; fail=0

# check NAME WANT INPUT
check() {
  local name="$1" want="$2" input="$3" got
  printf '%s' "$input" | bash "$BRAKE" >/dev/null 2>&1
  got=$?
  if [ "$got" -eq "$want" ]; then
    echo "  ok   $name (exit $got)"
    pass=$((pass + 1))
  else
    echo "  FAIL $name: want exit $want, got $got" >&2
    fail=$((fail + 1))
  fi
}

check "A no labels" 0 '{"labels":[]}'
check "B other labels only" 0 '{"labels":["workstream:hygiene","component:umbrella"]}'
check "C hold" 1 '{"labels":["hold"]}'
check "D hold among other labels" 1 '{"labels":["workstream:hygiene","hold","component:umbrella"]}'
check "E labels that only contain the word hold" 0 '{"labels":["on-hold","hold-off","Hold "]}'
check "F labels key missing" 2 '{}'
check "G labels is not an array" 2 '{"labels":"hold"}'
check "H a label is not a string" 2 '{"labels":["hold",1]}'
check "I empty input" 2 ''
check "J input is not JSON" 2 'hold'
check "K two JSON documents" 2 '{"labels":[]} {"labels":["hold"]}'

echo "merge-brake: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
