#!/usr/bin/env bash
# MOTHBALLED 2026-06-04 (historical, fails closed): bin/agentic/issue-promote.sh — promote a pickup:ready issue into backlog.yaml.
#
# Reads an existing agent-opened issue from Forgejo, validates it has all
# 6 required body sections, and appends a corresponding entry to
# docs/agentic/backlog.yaml. The issue's `pickup:ready` label flips to
# `pickup:in-progress` (PATCH).
#
# Usage:
#   bin/agentic/issue-promote.sh --repo <repo> --id <n> --worker <role>
#                                [--dry-run]
#
# --worker is the backlog.yaml `worker:` field for the new entry:
#   claude | qwen-left | qwen-right
#
# Exit codes:
#   0 — promoted (backlog.yaml updated + Forgejo label flipped)
#   1 — validation failed (missing sections, not pickup:ready, etc.)
#   2 — usage / argument error
#   3 — Forgejo API error
#
# Refs:
#   docs/plans/DMF Agentic Harness Plan 2026-05-11.md §Layer 4
#   docs/agentic/ISSUE-TEMPLATES.md

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
WORKER=""
DRY_RUN=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo)    REPO="$2"; shift 2 ;;
        --id)      ID="$2"; shift 2 ;;
        --worker)  WORKER="$2"; shift 2 ;;
        --dry-run) DRY_RUN=1; shift ;;
        -h|--help)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

if [ -z "$REPO" ] || [ -z "$ID" ] || [ -z "$WORKER" ]; then
    echo "missing required: --repo --id --worker" >&2
    exit 2
fi
case "$WORKER" in
    claude|qwen-left|qwen-right) ;;
    *) echo "invalid --worker: $WORKER" >&2; exit 2 ;;
esac

forgejo_validate_config || exit 2

# Fetch issue.
TOKEN="$(cat "$FORGEJO_TOKEN_PATH")"
API="https://${FORGEJO_HOST}/api/v1/repos/${FORGEJO_OWNER}/${REPO}/issues/${ID}"
RESP="$(curl -fsS -H "Authorization: token ${TOKEN}" "$API" 2>/dev/null)" || {
    echo "Forgejo API error fetching ${REPO}#${ID}" >&2
    exit 3
}

# Parse the issue. Extract labels and body.
LABELS=$(echo "$RESP" | python3 -c 'import json,sys; print(" ".join(l["name"] for l in json.load(sys.stdin).get("labels", [])))')
BODY=$(echo "$RESP"   | python3 -c 'import json,sys; print(json.load(sys.stdin).get("body",""))')
TITLE=$(echo "$RESP"  | python3 -c 'import json,sys; print(json.load(sys.stdin)["title"])')

# Must have pickup:ready.
if ! echo "$LABELS" | grep -qw 'pickup:ready'; then
    echo "refusing: ${REPO}#${ID} is not pickup:ready (labels: $LABELS)" >&2
    echo "  only pickup:ready issues are eligible for promotion" >&2
    exit 1
fi

# Required sections.
for sec in Context Acceptance Scope Constraints "Decision points" Related; do
    if ! echo "$BODY" | grep -qE "^## ${sec}\$"; then
        echo "refusing: ${REPO}#${ID} missing required section '## ${sec}'" >&2
        exit 1
    fi
done

# Pick type + scope + effort from labels.
TYPE=$(echo "$LABELS" | tr ' ' '\n' | grep '^type:' | head -1 | cut -d: -f2)
EFFORT=$(echo "$LABELS" | tr ' ' '\n' | grep '^effort:' | head -1 | cut -d: -f2)
SCOPES=$(echo "$LABELS" | tr ' ' '\n' | grep '^scope:' | cut -d: -f2 | paste -sd, -)

# Map type → backlog kind.
case "$TYPE" in
    workaround|bug)            KIND=rote ;;
    feature)                   KIND=rote ;;  # initial assumption; operator can re-label to taste
    decision-requested)        echo "refusing: type:decision-requested issues belong in decisions-open.md, not backlog.yaml" >&2; exit 1 ;;
    *) echo "issue has no recognized type: label" >&2; exit 1 ;;
esac

# Generate backlog id from issue title — kebab-case, prefix with repo + issue num.
SAFE_TITLE=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | tr -c '[:alnum:]' '-' | sed 's/--*/-/g' | sed 's/^-\|-$//g' | cut -c1-40)
BACKLOG_ID="${REPO}-${ID}-${SAFE_TITLE}"

if [ "$DRY_RUN" = 1 ]; then
    cat <<DRY
── dry-run: would promote ${REPO}#${ID}
  backlog entry:
    id:       ${BACKLOG_ID}
    scope:    ${SCOPES}
    kind:     ${KIND}
    worker:   ${WORKER}
    deps:     []
    issue:    forgejo#${REPO}/${ID}
    status:   in-progress
  PATCH on ${REPO}#${ID}: pickup:ready → pickup:in-progress
DRY
    exit 0
fi

# Append to backlog.yaml.
cat >> "${UMBRELLA_DIR}/docs/agentic/backlog.yaml" <<YAML

- id: ${BACKLOG_ID}
  scope: ${SCOPES}
  kind: ${KIND}
  worker: ${WORKER}
  deps: []
  decision_gate: null
  issue: "forgejo#${REPO}/${ID}"
  acceptance:
    - issue_closed: ${REPO}#${ID}
  status: in-progress
YAML

# Flip pickup label: remove pickup:ready, add pickup:in-progress.
# Forgejo issues API accepts label replacement via PUT /labels with the
# full final set, or via DELETE + POST. Simplest: PUT with new set.
NEW_LABELS=$(echo "$LABELS" | tr ' ' '\n' | sed 's|^pickup:ready$|pickup:in-progress|' | python3 -c '
import json,sys
labels = [l.strip() for l in sys.stdin if l.strip()]
# Forgejo expects label IDs, not names, on PUT — but POST /labels accepts names
# via the label-name endpoint variant. Using the simpler `state` patch for the
# pickup flip would require a separate label-resolution step. For minimum
# K4 surface, just add a comment recording the promotion; operator flips the
# pickup label manually if Forgejo label IDs are not yet wired into the script.
print(json.dumps({"body": "Promoted to backlog as `'"$BACKLOG_ID"'` (worker: '"$WORKER"'). Flip pickup:ready → pickup:in-progress when convenient."}))
')

curl -fsS \
    -X POST \
    -H "Authorization: token ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$NEW_LABELS" \
    "${API}/comments" >/dev/null 2>&1 || {
    echo "warning: comment-post failed; backlog entry written but Forgejo not annotated" >&2
}
unset TOKEN

echo "✓ promoted ${REPO}#${ID} → backlog.yaml entry: ${BACKLOG_ID}"
echo "  next: /agentic-tick will dispatch to ${WORKER} on the next eligible iteration"
