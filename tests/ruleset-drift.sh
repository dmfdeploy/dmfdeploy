#!/usr/bin/env bash
# ruleset-drift.sh — regressions for the ruleset assertion (umbrella #368).
#
# THE CASE THAT MATTERS MOST is E. The original design was mutation-tested
# across eight cases and still shipped a fail-open, because every one of those
# cases mutated the EXPECTATION FILE and none degraded the API RESPONSE. The
# endpoint returns 200 while omitting fields a low-privilege caller may not
# read; `.bypass_actors | length` then yielded 0 for an absent field, so an
# unreadable value rendered as a verified-empty one and the check passed.
#
#   A  drift in a required check is detected
#   B  an unmutated expectation passes
#   C  a malformed expectation fails (not passes)
#   D  an unreadable ruleset exits 2, never 0
#   E  a PARTIAL API response exits 2 — never compares a subset and calls it OK
#   F  an expectation carrying a field the check does not read exits 2
#
# Hermetic: stubs `gh` on PATH so no network or token is involved.
set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
GATE="$UMBRELLA_DIR/bin/check-ruleset-drift.sh"
pass=0; fail=0
ok()  { echo "  ✓ $1"; pass=$((pass + 1)); }
bad() { echo "  ✗ $1" >&2; fail=$((fail + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dmf-ruleset-drift.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/repo/.github"

FULL='{"name":"main-protection","target":"branch","enforcement":"active",
"conditions":{"ref_name":{"exclude":[],"include":["~DEFAULT_BRANCH"]}},
"bypass_actors":[],
"rules":[{"type":"deletion"},{"type":"required_linear_history"},
{"type":"pull_request","parameters":{"required_approving_review_count":1,"require_code_owner_review":true}},
{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"ci"},{"context":"dco"}]}}]}'

# gh stub: emits whatever fixture the test selected.
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
[ -f "$GH_STUB_BODY" ] || { echo "stub: no body" >&2; exit 1; }
[ "${GH_STUB_FAIL:-0}" = "1" ] && { echo '{"message":"Not Found"}' >&2; exit 1; }
cat "$GH_STUB_BODY"
STUB
chmod +x "$WORK/bin/gh"

run() { PATH="$WORK/bin:$PATH" UMBRELLA_DIR="$WORK/repo" GH_STUB_BODY="$1" GH_STUB_FAIL="${2:-0}" \
        "$GATE" >/dev/null 2>&1; echo $?; }

printf '%s' "$FULL" > "$WORK/full.json"
PATH="$WORK/bin:$PATH" UMBRELLA_DIR="$WORK/repo" GH_STUB_BODY="$WORK/full.json" "$GATE" --write >/dev/null 2>&1

echo "ruleset-drift regressions (issue #368)"

[ "$(run "$WORK/full.json")" = "0" ] && ok "B: unmutated expectation passes" || bad "B: false positive"

# A: live gains a required check the expectation does not have.
printf '%s' "$FULL" | jq '.rules |= map(if .type=="required_status_checks"
  then .parameters.required_status_checks += [{"context":"extra"}] else . end)' > "$WORK/drifted.json"
[ "$(run "$WORK/drifted.json")" = "1" ] && ok "A: required-check drift detected" || bad "A: drift missed"

# C: malformed expectation.
cp "$WORK/repo/.github/expected-ruleset.json" "$WORK/exp-good.json"
echo '{ not json' > "$WORK/repo/.github/expected-ruleset.json"
[ "$(run "$WORK/full.json")" = "2" ] && ok "C: malformed expectation exits 2" || bad "C: malformed expectation not caught"
cp "$WORK/exp-good.json" "$WORK/repo/.github/expected-ruleset.json"

# D: cannot read at all.
[ "$(run "$WORK/full.json" 1)" = "2" ] && ok "D: unreadable ruleset exits 2" || bad "D: did not fail closed"

# E: THE ORIGINAL FAIL-OPEN, restated for the token-free design.
# A response omitting bypass_actors is now EXPECTED — the check does not read
# that field. What must never happen is the check passing while *claiming* to
# have verified it. So: it may pass, but the output must say the field is not
# covered. Silence here would reproduce the original defect exactly.
printf '%s' "$FULL" | jq 'del(.bypass_actors)' > "$WORK/nobypass.json"
rc="$(run "$WORK/nobypass.json")"
out="$(PATH="$WORK/bin:$PATH" UMBRELLA_DIR="$WORK/repo" GH_STUB_BODY="$WORK/nobypass.json" "$GATE" 2>&1)"
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -qi 'bypass actors are NOT covered'; then
    ok "E: omitted bypass_actors passes but coverage gap is STATED, not implied"
elif [ "$rc" = "0" ]; then
    bad "E: FAIL-OPEN — passed without disclosing that bypass actors are unchecked"
else
    bad "E: unexpected exit $rc for a field the check does not read"
fi
printf '%s' "$FULL" | jq 'del(.conditions)' > "$WORK/nocond.json"
[ "$(run "$WORK/nocond.json")" = "2" ] && ok "E2: response missing a compared key exits 2" \
                                       || bad "E2: partial view compared anyway"

# F: expectation claiming a field the check does not read.
jq '. + {bypass_actor_count: 0}' "$WORK/exp-good.json" > "$WORK/repo/.github/expected-ruleset.json"
[ "$(run "$WORK/full.json")" = "2" ] && ok "F: expectation with an unread field exits 2" \
                                     || bad "F: unread field silently compared"
cp "$WORK/exp-good.json" "$WORK/repo/.github/expected-ruleset.json"

echo "ruleset-drift: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
