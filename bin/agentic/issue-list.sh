#!/usr/bin/env bash
# bin/agentic/issue-list.sh — list agent-opened Forgejo issues.
#
# Iterates the 6 public repos for `label:agent-opened` and aggregates.
# Read-only — does not modify any state.
#
# Usage:
#   bin/agentic/issue-list.sh                    # table output, all open
#   bin/agentic/issue-list.sh --json             # machine-readable
#   bin/agentic/issue-list.sh --pickup ready     # filter by pickup state
#   bin/agentic/issue-list.sh --repo dmf-cms     # one repo only
#   bin/agentic/issue-list.sh --state closed     # closed issues
#
# Exit codes:
#   0 — listing succeeded (may be empty)
#   2 — usage error
#   3 — Forgejo API unreachable
#
# Refs:
#   docs/plans/DMF Agentic Harness Plan 2026-05-11.md §Layer 4

set -euo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=/dev/null
. "${UMBRELLA_DIR}/bin/agentic/forgejo.env"

JSON_OUTPUT=0
PICKUP_FILTER=""
REPO_FILTER=""
STATE="open"

while [ "$#" -gt 0 ]; do
    case "$1" in
        --json)    JSON_OUTPUT=1; shift ;;
        --pickup)  PICKUP_FILTER="$2"; shift 2 ;;
        --repo)    REPO_FILTER="$2"; shift 2 ;;
        --state)   STATE="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

forgejo_validate_config || exit 2

TOKEN="$(cat "$FORGEJO_TOKEN_PATH")"

REPOS=("${FORGEJO_PUBLIC_REPOS[@]}")
if [ -n "$REPO_FILTER" ]; then
    REPOS=("$REPO_FILTER")
fi

LABEL_QUERY="agent-opened"
if [ -n "$PICKUP_FILTER" ]; then
    LABEL_QUERY="${LABEL_QUERY},pickup:${PICKUP_FILTER}"
fi

AGG_JSON='[]'
for repo in "${REPOS[@]}"; do
    api="https://${FORGEJO_HOST}/api/v1/repos/${FORGEJO_OWNER}/${repo}/issues?labels=${LABEL_QUERY}&state=${STATE}&type=issues"
    resp="$(curl -fsS -H "Authorization: token ${TOKEN}" "$api" 2>/dev/null)" || {
        echo "Forgejo API unreachable for ${repo}" >&2
        exit 3
    }
    AGG_JSON=$(python3 -c '
import json, sys
agg = json.loads("""'"$AGG_JSON"'""")
new = json.loads(sys.stdin.read())
for i in new:
    agg.append({
        "repo":  "'"$repo"'",
        "id":    i["number"],
        "title": i["title"],
        "labels": [l["name"] for l in i.get("labels", [])],
        "state": i["state"],
        "created_at": i["created_at"]
    })
print(json.dumps(agg))
' <<< "$resp")
done
unset TOKEN

if [ "$JSON_OUTPUT" = 1 ]; then
    echo "$AGG_JSON" | python3 -m json.tool
else
    printf '%-15s %5s  %-8s  %s\n' REPO '#' STATE TITLE
    printf '%-15s %5s  %-8s  %s\n' "$(printf '─%.0s' {1..15})" "─────" "────────" "$(printf '─%.0s' {1..40})"
    echo "$AGG_JSON" | python3 -c '
import json, sys
for i in json.load(sys.stdin):
    print(f"{i[\"repo\"]:<15} {i[\"id\"]:>5}  {i[\"state\"]:<8}  {i[\"title\"]}")
'
fi
