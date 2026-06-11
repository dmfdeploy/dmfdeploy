#!/usr/bin/env bash
# MOTHBALLED 2026-06-04 (historical, fails closed): bin/agentic/postflight.sh — agentic-harness tick-end guard.
#
# Runs at the end of every `/agentic-tick` after the worker has reported
# DONE or BLOCKED. Verifies the tick didn't break the secret-discipline or
# state-tracking invariants. Returns clean exit only when every guard passes.
#
# Guards run in this order (short-circuits on first failure):
#   1. gitleaks on staged changes (umbrella + named touched component repos)
#   2. gitleaks on tree (--no-git scan, catches unstaged leaks)
#   3. bin/scrub-public-repos.sh <repo> for each touched component repo
#   4. bin/generate-status.sh --no-fetch to refresh STATUS.md
#   5. Append a tick-result block to docs/agentic/loop-log.md
#
# Output: per-guard status (✓/✗) on stdout. Exit codes:
#   0 — every guard passed
#   1 — one or more guards failed; halt the loop
#
# Usage:
#   bin/agentic/postflight.sh                              # umbrella only
#   bin/agentic/postflight.sh --touched dmf-infra,dmf-cms  # scrub these repos
#   bin/agentic/postflight.sh --tick-id <n> --task <id>    # write loop-log entry
#   bin/agentic/postflight.sh --result done|blocked|halt   # log outcome
#
# Refs:
#   docs/plans/DMF Agentic Harness Plan 2026-05-11.md §Layer 2 "Enforcement"
#   docs/agentic/CONSTITUTION.md (Rule 2 secret gate; Rule 6 handoff hygiene)

set -euo pipefail

if [[ "${DMF_AGENTIC_OVERRIDE:-}" != "1" ]]; then
    echo "mothballed 2026-06-04 — set DMF_AGENTIC_OVERRIDE=1 to run" >&2
    exit 1
fi

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
TOUCHED_REPOS=""
TICK_ID=""
TASK_ID=""
RESULT=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --touched) TOUCHED_REPOS="$2"; shift 2 ;;
        --tick-id) TICK_ID="$2"; shift 2 ;;
        --task)    TASK_ID="$2"; shift 2 ;;
        --result)  RESULT="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

cd "$UMBRELLA_DIR"

FAILED=0

# ── Guard 1: gitleaks on staged changes ──────────────────────────────────────

if command -v gitleaks >/dev/null 2>&1; then
    if gitleaks protect --staged --no-banner --redact >/dev/null 2>&1; then
        echo "  ✓ gitleaks staged (umbrella)"
    else
        echo "  ✗ gitleaks staged (umbrella) — leak in staged changes" >&2
        FAILED=1
    fi

    IFS=',' read -ra _touched_arr <<< "${TOUCHED_REPOS:-}"
    for r in "${_touched_arr[@]+${_touched_arr[@]}}"; do
        [ -z "$r" ] && continue
        if [ ! -d "$r/.git" ]; then
            echo "  ! gitleaks staged ($r) — repo not present locally; skipping" >&2
            continue
        fi
        if ( cd "$r" && gitleaks protect --staged --no-banner --redact ) >/dev/null 2>&1; then
            echo "  ✓ gitleaks staged ($r)"
        else
            echo "  ✗ gitleaks staged ($r) — leak in staged changes" >&2
            FAILED=1
        fi
    done
else
    echo "  ! gitleaks not installed — skipping staged scan (install: brew install gitleaks)" >&2
fi

# ── Guard 2: gitleaks --no-git tree scan (catches unstaged leaks) ────────────

if command -v gitleaks >/dev/null 2>&1; then
    if gitleaks detect --no-git --no-banner --redact >/dev/null 2>&1; then
        echo "  ✓ gitleaks tree (umbrella)"
    else
        echo "  ✗ gitleaks tree (umbrella) — leak in working tree" >&2
        FAILED=1
    fi
fi

# ── Guard 3: scrub-public-repos.sh per touched repo ──────────────────────────

if [ -n "${TOUCHED_REPOS:-}" ]; then
    IFS=',' read -ra _touched_arr <<< "$TOUCHED_REPOS"
    for r in "${_touched_arr[@]}"; do
        [ -z "$r" ] && continue
        if [ ! -d "$r" ]; then
            echo "  ! scrub ($r) — repo not present locally; skipping" >&2
            continue
        fi
        if "$UMBRELLA_DIR/bin/scrub-public-repos.sh" "$r" >/dev/null 2>&1; then
            echo "  ✓ scrub ($r)"
        else
            echo "  ✗ scrub ($r) — public-publish hygiene failed" >&2
            FAILED=1
        fi
    done
fi

# ── Guard 4: STATUS.md refresh ───────────────────────────────────────────────

if [ -x "$UMBRELLA_DIR/bin/generate-status.sh" ]; then
    if "$UMBRELLA_DIR/bin/generate-status.sh" --no-fetch >/dev/null 2>&1; then
        echo "  ✓ STATUS.md refreshed"
    else
        echo "  ✗ STATUS.md refresh failed" >&2
        FAILED=1
    fi
fi

# ── Guard 5: Append loop-log entry ───────────────────────────────────────────
# Only emit a block if --tick-id was supplied (lets the orchestrator call
# postflight in dry-run / standalone mode without polluting the log).

if [ -n "$TICK_ID" ] && [ -f "docs/agentic/loop-log.md" ]; then
    ISO_TS=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    {
        echo ""
        echo "─── tick $TICK_ID @ $ISO_TS ───────────────────────────────────────────────"
        echo "task:       ${TASK_ID:-<unspecified>}"
        echo "touched:    ${TOUCHED_REPOS:-<umbrella-only>}"
        echo "result:     ${RESULT:-<unspecified>}"
        echo "guards:     $([ "$FAILED" = 0 ] && echo "all ok" || echo "FAILED — see stderr")"
    } >> docs/agentic/loop-log.md
    echo "  ✓ loop-log entry written"
fi

# ── Exit ─────────────────────────────────────────────────────────────────────

if [ "$FAILED" = 0 ]; then
    echo "postflight: ok"
    exit 0
else
    echo "postflight: FAILED" >&2
    exit 1
fi
