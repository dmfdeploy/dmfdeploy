#!/usr/bin/env bash
# MOTHBALLED 2026-06-04 (historical, fails closed): bin/agentic/preflight.sh — agentic-harness tick-start fact dump.
#
# Runs at the start of every `/agentic-tick`. Prints a structured facts
# block on stdout the orchestrator reads to decide whether to proceed,
# halt, or expect specific dirty state.
#
# The script provides FACTS, not POLICY. Policy lives in the orchestrator
# (Claude's tick logic): is the constitution hash drift expected? are the
# listed dirty repos the ones the current task said it would touch? etc.
#
# Output: a key=value block on stdout (one fact per line) plus a summary
# line on the last line. Exit codes:
#   0 — facts gathered cleanly
#   1 — could not gather facts (missing CONSTITUTION, missing repo, etc.)
#
# Usage:
#   bin/agentic/preflight.sh                # run from umbrella
#   bin/agentic/preflight.sh --status-max-age 1800   # override 30-min default
#   bin/agentic/preflight.sh --json         # JSON output (one object)
#
# Refs:
#   docs/plans/DMF Agentic Harness Plan 2026-05-11.md §Layer 2 "Enforcement"
#   docs/agentic/CONSTITUTION.md (Rule 5 self-hash; orchestrator compares)

set -euo pipefail

if [[ "${DMF_AGENTIC_OVERRIDE:-}" != "1" ]]; then
    echo "mothballed 2026-06-04 — set DMF_AGENTIC_OVERRIDE=1 to run" >&2
    exit 1
fi

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
STATUS_MAX_AGE_SECONDS=1800   # 30 min
JSON_OUTPUT=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --status-max-age) STATUS_MAX_AGE_SECONDS="$2"; shift 2 ;;
        --json)           JSON_OUTPUT=1; shift ;;
        -h|--help)
            sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

cd "$UMBRELLA_DIR"

# ── 1. CONSTITUTION.md presence + hash ───────────────────────────────────────

CONSTITUTION_PATH="docs/agentic/CONSTITUTION.md"
if [ ! -f "$CONSTITUTION_PATH" ]; then
    echo "preflight: missing $CONSTITUTION_PATH — harness not initialized" >&2
    exit 1
fi
CONSTITUTION_SHA="$(shasum -a 256 "$CONSTITUTION_PATH" | cut -d' ' -f1)"

# ── 2. STATUS.md freshness ───────────────────────────────────────────────────

STATUS_PATH="STATUS.md"
STATUS_FRESH=1
STATUS_AGE_SECONDS=0
if [ -f "$STATUS_PATH" ]; then
    if [ "$(uname)" = "Darwin" ]; then
        STATUS_MTIME=$(stat -f %m "$STATUS_PATH")
    else
        STATUS_MTIME=$(stat -c %Y "$STATUS_PATH")
    fi
    NOW=$(date +%s)
    STATUS_AGE_SECONDS=$((NOW - STATUS_MTIME))
    if [ "$STATUS_AGE_SECONDS" -gt "$STATUS_MAX_AGE_SECONDS" ]; then
        STATUS_FRESH=0
    fi
else
    STATUS_FRESH=0
    STATUS_AGE_SECONDS=-1
fi

# ── 3. Dirty umbrella state ──────────────────────────────────────────────────

UMBRELLA_DIRTY_COUNT=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

# ── 4. Dirty component-repo state ────────────────────────────────────────────

DIRTY_SUBREPOS=()
for r in dmf-cms dmf-infra dmf-env dmf-central dmf-media dmf-runbooks dmf-init; do
    if [ -d "$r/.git" ]; then
        if [ -n "$(git -C "$r" status --porcelain 2>/dev/null)" ]; then
            DIRTY_SUBREPOS+=("$r")
        fi
    fi
done

# ── 5. Decisions-open count ──────────────────────────────────────────────────

DECISIONS_OPEN_COUNT=0
if [ -f "docs/agentic/decisions-open.md" ]; then
    DECISIONS_OPEN_COUNT=$(grep -c '^Status: open' "docs/agentic/decisions-open.md" || true)
fi

# ── 6. Backlog state ─────────────────────────────────────────────────────────

BACKLOG_PENDING=0
BACKLOG_BLOCKED=0
BACKLOG_IN_PROGRESS=0
if [ -f "docs/agentic/backlog.yaml" ]; then
    BACKLOG_PENDING=$(grep -cE '^  status: pending' docs/agentic/backlog.yaml || true)
    BACKLOG_BLOCKED=$(grep -cE '^  status: blocked' docs/agentic/backlog.yaml || true)
    BACKLOG_IN_PROGRESS=$(grep -cE '^  status: in-progress' docs/agentic/backlog.yaml || true)
fi

# ── 7. Emit facts ────────────────────────────────────────────────────────────

if [ "$JSON_OUTPUT" = 1 ]; then
    cat <<JSON
{
  "constitution_sha256": "$CONSTITUTION_SHA",
  "constitution_path": "$CONSTITUTION_PATH",
  "status_fresh": $([ "$STATUS_FRESH" = 1 ] && echo true || echo false),
  "status_age_seconds": $STATUS_AGE_SECONDS,
  "status_max_age_seconds": $STATUS_MAX_AGE_SECONDS,
  "umbrella_dirty_count": $UMBRELLA_DIRTY_COUNT,
  "dirty_subrepos": [$(printf '"%s",' "${DIRTY_SUBREPOS[@]+${DIRTY_SUBREPOS[@]}}" | sed 's/,$//')],
  "decisions_open_count": $DECISIONS_OPEN_COUNT,
  "backlog": {
    "pending": $BACKLOG_PENDING,
    "blocked": $BACKLOG_BLOCKED,
    "in_progress": $BACKLOG_IN_PROGRESS
  }
}
JSON
else
    echo "constitution_sha256=$CONSTITUTION_SHA"
    echo "constitution_path=$CONSTITUTION_PATH"
    echo "status_fresh=$STATUS_FRESH"
    echo "status_age_seconds=$STATUS_AGE_SECONDS"
    echo "status_max_age_seconds=$STATUS_MAX_AGE_SECONDS"
    echo "umbrella_dirty_count=$UMBRELLA_DIRTY_COUNT"
    echo "dirty_subrepos=${DIRTY_SUBREPOS[*]+${DIRTY_SUBREPOS[*]}}"
    echo "decisions_open_count=$DECISIONS_OPEN_COUNT"
    echo "backlog_pending=$BACKLOG_PENDING"
    echo "backlog_blocked=$BACKLOG_BLOCKED"
    echo "backlog_in_progress=$BACKLOG_IN_PROGRESS"
    echo "preflight: ok"
fi

exit 0
