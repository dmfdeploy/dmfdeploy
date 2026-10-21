#!/usr/bin/env bash
# merge-brake.sh tests: the decision logic behind the merge-brake check
# (umbrella #544, #439). Each case feeds a label list and a review list to the
# script and asserts its exit status: 0 lets the PR merge, 1 holds it.
#
#   A  no hold, approved                                  -> 0
#   B  hold label                                         -> 1
#   C  latest review is CHANGES_REQUESTED                 -> 1
#   D  CHANGES_REQUESTED, then APPROVED by the same login -> 0
#   E  CHANGES_REQUESTED, then dismissed                  -> 0
#   F  CHANGES_REQUESTED by one login, APPROVED by another -> 1
#   G  CHANGES_REQUESTED, then COMMENTED by the same login -> 1
#   H  CHANGES_REQUESTED from a non-collaborator          -> 0
#   I  reviews out of order: the later submitted_at wins  -> 0
#   J  malformed input                                    -> 2
#   K  CHANGES_REQUESTED, then a later one dismissed      -> 0
#   L  same second: id 101 CHANGES_REQUESTED, 102 APPROVED, either input order -> 0
#   M  same second: id 101 APPROVED, 102 CHANGES_REQUESTED, either input order -> 1
#
# Hermetic: no network or credential. Set BRAKE to test another copy of the
# script, which is how the mutation check runs.
set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
BRAKE="${BRAKE:-$UMBRELLA_DIR/.github/scripts/merge-brake.sh}"
pass=0; fail=0

# review LOGIN STATE TIME [ASSOCIATION] [ID]
review() {
  printf '{"id":%s,"user":{"login":"%s"},"state":"%s","submitted_at":"%s","author_association":"%s"}' \
    "${5:-0}" "$1" "$2" "$3" "${4:-MEMBER}"
}

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

t1=2026-10-01T10:00:00Z
t2=2026-10-01T11:00:00Z
t3=2026-10-01T12:00:00Z

check "A no hold, approved" 0 \
  "{\"labels\":[\"workstream:hygiene\"],\"reviews\":[$(review alice APPROVED $t1)]}"

check "B hold label" 1 \
  "{\"labels\":[\"workstream:hygiene\",\"hold\"],\"reviews\":[$(review alice APPROVED $t1)]}"

check "C latest review is CHANGES_REQUESTED" 1 \
  "{\"labels\":[],\"reviews\":[$(review alice APPROVED $t1),$(review alice CHANGES_REQUESTED $t2)]}"

check "D CHANGES_REQUESTED then APPROVED, same login" 0 \
  "{\"labels\":[],\"reviews\":[$(review alice CHANGES_REQUESTED $t1),$(review alice APPROVED $t2)]}"

check "E CHANGES_REQUESTED, dismissed" 0 \
  "{\"labels\":[],\"reviews\":[$(review alice DISMISSED $t1),$(review bob APPROVED $t2)]}"

check "F CHANGES_REQUESTED by one, APPROVED by another" 1 \
  "{\"labels\":[],\"reviews\":[$(review alice CHANGES_REQUESTED $t1),$(review bob APPROVED $t2)]}"

check "G CHANGES_REQUESTED then COMMENTED, same login" 1 \
  "{\"labels\":[],\"reviews\":[$(review alice CHANGES_REQUESTED $t1),$(review alice COMMENTED $t2),$(review bob APPROVED $t3)]}"

check "H CHANGES_REQUESTED from a non-collaborator" 0 \
  "{\"labels\":[],\"reviews\":[$(review mallory CHANGES_REQUESTED $t1 NONE),$(review bob APPROVED $t2)]}"

check "I out of order, later submitted_at wins" 0 \
  "{\"labels\":[],\"reviews\":[$(review alice APPROVED $t2),$(review alice CHANGES_REQUESTED $t1)]}"

check "J malformed input" 2 '{"labels":"hold"}'

check "K CHANGES_REQUESTED, then a later one dismissed" 0 \
  "{\"labels\":[],\"reviews\":[$(review alice CHANGES_REQUESTED $t1),$(review alice DISMISSED $t2)]}"

cr101=$(review alice CHANGES_REQUESTED $t1 MEMBER 101)
ap102=$(review alice APPROVED $t1 MEMBER 102)
check "L1 same second, CR 101 then APPROVED 102" 0 "{\"labels\":[],\"reviews\":[$cr101,$ap102]}"
check "L2 same second, APPROVED 102 then CR 101" 0 "{\"labels\":[],\"reviews\":[$ap102,$cr101]}"

ap101=$(review alice APPROVED $t1 MEMBER 101)
cr102=$(review alice CHANGES_REQUESTED $t1 MEMBER 102)
check "M1 same second, APPROVED 101 then CR 102" 1 "{\"labels\":[],\"reviews\":[$ap101,$cr102]}"
check "M2 same second, CR 102 then APPROVED 101" 1 "{\"labels\":[],\"reviews\":[$cr102,$ap101]}"

echo "merge-brake: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
