#!/usr/bin/env bash
# check-ruleset-drift.sh — assert the live branch ruleset against a committed
# expectation (umbrella issue #368).
#
# Why this exists: the ruleset is what makes every other gate binding — required
# checks, code-owner review, linear history, no bypass actors. Nothing asserted
# it. Drop a required check, add a bypass actor, or turn off code-owner review
# and nothing would notice. Anti-degradation belongs in a deterministic
# assertion, not in a role: a check cannot forget, a role decays with attention.
#
# Compares only the fields that carry authority. Cosmetic fields (ids,
# timestamps, _links) are deliberately ignored so the check does not cry wolf.
#
# Usage:
#   bin/check-ruleset-drift.sh              # assert against .github/expected-ruleset.json
#   bin/check-ruleset-drift.sh --write      # re-record the expectation from live (review the diff!)
#
# Exit: 0 no drift, 1 drift, 2 could not run (fail closed — never reports clean
# when it could not actually look).
set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
REPO="${DMF_RULESET_REPO:-dmfdeploy/dmfdeploy}"
RULESET_ID="${DMF_RULESET_ID:-17551295}"
EXPECTED="$UMBRELLA_DIR/.github/expected-ruleset.json"
MODE="check"
[ "${1:-}" = "--write" ] && MODE="write"

command -v gh  >/dev/null 2>&1 || { echo "FAIL(2): gh not available — cannot read the live ruleset" >&2; exit 2; }
command -v jq  >/dev/null 2>&1 || { echo "FAIL(2): jq not available" >&2; exit 2; }

live_raw="$(gh api "repos/$REPO/rulesets/$RULESET_ID" 2>&1)" || {
    echo "FAIL(2): could not read the live ruleset for $REPO ($RULESET_ID)." >&2
    echo "  This needs a token with repository administration READ." >&2
    echo "  In Actions the default GITHUB_TOKEN may not carry it — supply a PAT." >&2
    printf '%s\n' "$live_raw" | head -3 | sed 's/^/  /' >&2
    exit 2
}

# The authority-bearing projection. Sorted so ordering never causes a false alarm.
project() {
    jq -S '{
      name, target, enforcement,
      conditions,
      bypass_actor_count: (.bypass_actors | length),
      rule_types: [.rules[].type] | sort,
      pull_request: (.rules[] | select(.type=="pull_request") | .parameters),
      required_status_checks: ([.rules[] | select(.type=="required_status_checks")
                                | .parameters.required_status_checks[].context] | sort)
    }'
}

live="$(printf '%s' "$live_raw" | project)" || { echo "FAIL(2): could not project the live ruleset" >&2; exit 2; }

if [ "$MODE" = "write" ]; then
    printf '%s\n' "$live" > "$EXPECTED"
    echo "wrote $EXPECTED — review the diff before committing"
    exit 0
fi

[ -f "$EXPECTED" ] || { echo "FAIL(2): no committed expectation at $EXPECTED (record one with --write)" >&2; exit 2; }
expected="$(jq -S . "$EXPECTED")" || { echo "FAIL(2): $EXPECTED is not valid JSON" >&2; exit 2; }

if [ "$live" = "$expected" ]; then
    echo "OK: ruleset matches the committed expectation ($REPO ruleset $RULESET_ID)"
    exit 0
fi

echo "FAIL(1): the live ruleset has drifted from the committed expectation." >&2
echo "  repo=$REPO ruleset=$RULESET_ID  expectation=$EXPECTED" >&2
echo "  < expected / > live" >&2
diff <(printf '%s\n' "$expected") <(printf '%s\n' "$live") | sed 's/^/    /' >&2
echo "  If the change was intended, re-record with --write and land it in a reviewed PR." >&2
exit 1
