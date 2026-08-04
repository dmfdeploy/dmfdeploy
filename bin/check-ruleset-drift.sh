#!/usr/bin/env bash
# check-ruleset-drift.sh — assert the live branch ruleset against a committed
# expectation (umbrella issue #368).
#
# Why this exists: the ruleset is what makes every other gate binding — required
# checks, code-owner review, linear history. Nothing asserted it. Drop a
# required check or turn off code-owner review and nothing would notice.
# Anti-degradation belongs in a deterministic assertion, not in a role.
#
# ── CREDENTIAL-FREE BY DESIGN, AND WHY ──────────────────────────────────────
# This reads the PUBLIC ruleset endpoint with no credential at all — no PAT and
# no GITHUB_TOKEN. Verified: the unauthenticated response yields a projection
# IDENTICAL to the authenticated one for every field compared here, so
# authenticating buys nothing and only creates custody to get wrong.
#
# An earlier revision took an Administration-scoped PAT so it could also assert
# bypass_actors. That was withdrawn for two independent reasons:
#
#   1. FAIL-OPEN. The ruleset endpoint returns 200 while OMITTING bypass_actors
#      for an insufficiently privileged caller. The projection used
#      `.bypass_actors | length`, and in jq `null | length` is 0 — so an
#      unreadable field rendered as a verified-empty one. Not hypothetical: a
#      run printed "OK: ruleset matches the committed expectation" seventeen
#      minutes BEFORE the PAT existed, certifying zero bypass actors with a
#      token that cannot see them.
#   2. ADR-0007 (Accepted) forbids secrets in environment variables, which is
#      how a PAT reaches a workflow step. Note that GITHUB_TOKEN is a secret
#      too — a GitHub App installation token — so exporting it as GH_TOKEN
#      would sit under the same ban. Calling that arrangement "token-free"
#      while exporting a secret was the wording this file previously used, and
#      it was wrong. Nothing is exported now.
#
# So this covers exactly the fields any authenticated caller can read, and does
# NOT claim to cover bypass actors. That gap is printed rather than hidden — a
# check that silently covers less than it claims is the defect it exists to
# prevent.
#
# Usage:
#   bin/check-ruleset-drift.sh              # assert against .github/expected-ruleset.json
#   bin/check-ruleset-drift.sh --write      # re-record the expectation (review the diff!)
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

command -v curl >/dev/null 2>&1 || { echo "FAIL(2): curl not available — cannot read the ruleset" >&2; exit 2; }
command -v jq   >/dev/null 2>&1 || { echo "FAIL(2): jq not available" >&2; exit 2; }

# Unauthenticated, public endpoint. Status is checked explicitly: a non-200 must
# fail closed rather than let a body like {"message":"Not Found"} flow into the
# comparison.
API="${DMF_RULESET_API:-https://api.github.com}"
# mktemp, not a PID-derived name. $$ is predictable, so on a shared host another
# user can pre-create it as a symlink and turn curl's write into a same-user
# file clobber. The body is public, so this is not secret leakage — it is a
# write-target hazard. Creation failing must abort rather than fall through to a
# guessable path, and the trap is installed BEFORE curl so an interrupt cannot
# leave residue.
tmp="$(mktemp "${TMPDIR:-/tmp}/dmf-ruleset.XXXXXX" 2>/dev/null)" || {
    echo "FAIL(2): could not create a temporary file — refusing to use a predictable path." >&2
    exit 2
}
trap 'rm -f "$tmp"' EXIT INT TERM
http_code="$(curl -sS -o "$tmp" -w '%{http_code}' \
             -H 'Accept: application/vnd.github+json' \
             "$API/repos/$REPO/rulesets/$RULESET_ID" 2>/dev/null || echo 000)"
live_raw="$(cat "$tmp" 2>/dev/null || true)"
if [ "$http_code" != "200" ]; then
    echo "FAIL(2): could not read the ruleset for $REPO ($RULESET_ID) — HTTP $http_code." >&2
    printf '%s\n' "$live_raw" | head -3 | sed 's/^/  /' >&2
    exit 2
fi

# Every field compared must be PRESENT, not merely truthy. A missing key must
# fail closed rather than project to a benign-looking default — that is exactly
# how an omitted bypass_actors became "0".
for k in name target enforcement conditions rules; do
    printf '%s' "$live_raw" | jq -e --arg k "$k" 'has($k)' >/dev/null 2>&1 || {
        echo "FAIL(2): the ruleset response is missing '$k' — refusing to compare a partial view." >&2
        exit 2
    }
done
printf '%s' "$live_raw" | jq -e '.rules | type == "array"' >/dev/null 2>&1 || {
    echo "FAIL(2): .rules is not an array — refusing to compare a partial view." >&2; exit 2; }
for t in pull_request required_status_checks; do
    printf '%s' "$live_raw" | jq -e --arg t "$t" 'any(.rules[]; .type == $t)' >/dev/null 2>&1 || {
        echo "FAIL(2): the ruleset response has no '$t' rule — refusing to compare a partial view." >&2
        exit 2; }
done

# The authority-bearing projection, limited to publicly readable fields.
# bypass_actors is deliberately ABSENT — see the header.
project() {
    jq -S '{
      name, target, enforcement,
      conditions,
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

# The expectation must not carry a field this check cannot actually read —
# otherwise it would appear to verify something it never looks at.
if printf '%s' "$expected" | jq -e 'has("bypass_actor_count")' >/dev/null 2>&1; then
    echo "FAIL(2): the expectation carries bypass_actor_count, which this check does NOT read." >&2
    echo "  Remove it. Bypass actors are audited separately — see the header." >&2
    exit 2
fi

if [ "$live" = "$expected" ]; then
    echo "OK: ruleset matches the committed expectation ($REPO ruleset $RULESET_ID)"
    echo "NOTE: bypass actors are NOT covered by this check (credential-free by design)."
    echo "      Audit them manually: Settings → Rules → main-protection → Bypass list."
    exit 0
fi

echo "FAIL(1): the live ruleset has drifted from the committed expectation." >&2
echo "  repo=$REPO ruleset=$RULESET_ID  expectation=$EXPECTED" >&2
echo "  < expected / > live" >&2
diff <(printf '%s\n' "$expected") <(printf '%s\n' "$live") | sed 's/^/    /' >&2
echo "  If the change was intended, re-record with --write and land it in a reviewed PR." >&2
exit 1
