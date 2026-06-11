#!/usr/bin/env bash
# MOTHBALLED 2026-06-04 (historical, fails closed): bin/agentic/issue-close.sh — close an agent-opened Forgejo issue with
# a structured reason and ref.
#
# Constitution Rule 6 (handoff hygiene) — closure isn't just state change;
# it's an audit-trail event. The --reason and --ref fields are mandatory
# and land in a closing comment so the issue history reads as a complete
# decision log.
#
# Usage:
#   bin/agentic/issue-close.sh --repo <repo> --id <n> \
#                              --reason resolved|superseded|deferred|declined \
#                              --ref <commit-sha-or-handoff-path> \
#                              [--note "<optional free-text>"] \
#                              [--dry-run]
#
# Exit codes:
#   0 — closed (comment posted + state flipped + issues.yaml updated)
#   1 — validation failed
#   2 — usage error
#   3 — Forgejo API error
#
# Refs:
#   docs/plans/DMF Agentic Harness Plan 2026-05-11.md §Layer 4
#   docs/agentic/CONSTITUTION.md (Rule 6 handoff hygiene)

set -euo pipefail

if [[ "${DMF_AGENTIC_OVERRIDE:-}" != "1" ]]; then
    echo "mothballed 2026-06-04 — set DMF_AGENTIC_OVERRIDE=1 to run" >&2
    exit 1
fi

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=/dev/null
. "${UMBRELLA_DIR}/bin/agentic/forgejo.env"

REPO=""
ID=""
REASON=""
REF=""
NOTE=""
DRY_RUN=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo)    REPO="$2"; shift 2 ;;
        --id)      ID="$2"; shift 2 ;;
        --reason)  REASON="$2"; shift 2 ;;
        --ref)     REF="$2"; shift 2 ;;
        --note)    NOTE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help)
            sed -n '2,21p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$REPO" ] || [ -z "$ID" ] || [ -z "$REASON" ] || [ -z "$REF" ]; then
    echo "missing required: --repo --id --reason --ref" >&2
    exit 2
fi

case "$REASON" in
    resolved|superseded|deferred|declined) ;;
    *) echo "invalid --reason: $REASON (allowed: resolved|superseded|deferred|declined)" >&2; exit 2 ;;
esac

forgejo_validate_config || exit 2

# Build closing comment.
ISO_TS=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
COMMENT_BODY="Closing — **${REASON}** @ ${ISO_TS}
Ref: \`${REF}\`"
if [ -n "$NOTE" ]; then
    COMMENT_BODY="${COMMENT_BODY}

${NOTE}"
fi

COMMENT_PAYLOAD=$(python3 -c '
import json, sys
print(json.dumps({"body": """'"$COMMENT_BODY"'"""}))
')

CLOSE_PAYLOAD='{"state":"closed"}'

if [ "$DRY_RUN" = 1 ]; then
    cat <<DRY
── dry-run: would close ${REPO}#${ID}
  reason: ${REASON}
  ref:    ${REF}
  comment payload:
$(echo "$COMMENT_PAYLOAD" | python3 -m json.tool | sed 's/^/    /')
  PATCH payload:
    ${CLOSE_PAYLOAD}
DRY
    exit 0
fi

TOKEN="$(cat "$FORGEJO_TOKEN_PATH")"
API="https://${FORGEJO_HOST}/api/v1/repos/${FORGEJO_OWNER}/${REPO}/issues/${ID}"

# Post the closing comment first, then PATCH state. Order matters: if the
# state change succeeds but the comment fails, we lose the audit context.
curl -fsS \
    -X POST \
    -H "Authorization: token ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$COMMENT_PAYLOAD" \
    "${API}/comments" >/dev/null 2>&1 || {
    echo "Forgejo API error posting closing comment on ${REPO}#${ID}" >&2
    exit 3
}

curl -fsS \
    -X PATCH \
    -H "Authorization: token ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$CLOSE_PAYLOAD" \
    "$API" >/dev/null 2>&1 || {
    echo "Forgejo API error closing ${REPO}#${ID}" >&2
    echo "  comment posted but state change failed; retry close manually" >&2
    exit 3
}
unset TOKEN

echo "✓ closed ${REPO}#${ID} — ${REASON} (ref: ${REF})"

# Note: issues.yaml mirror update is left to postflight reconciliation.
# Trying to edit YAML in-place reliably from bash is error-prone; the
# next postflight tick will pick up the state change via issue-list.sh.
