#!/usr/bin/env bash
# session-budget.sh — Claude Code Stop hook: passive session tool-use brake.
#
# Fires when the assistant finishes a turn. Counts tool-use events in the
# session transcript and, when over a soft budget, prints a one-line advisory
# so a runaway / expensive session becomes VISIBLE to the operator. It never
# blocks stopping (always exits 0) and stays silent under budget — no per-turn
# noise. This is the cost/focus companion to the safety deny-list: correctness
# is enforced by hooks; economy is nudged here.
#
# Budget override: DMF_SESSION_TOOL_BUDGET (default 200 tool-use events).
# Reads the hook JSON on stdin; needs `jq`. Degrades to exit 0 on any error.

set -uo pipefail

budget="${DMF_SESSION_TOOL_BUDGET:-200}"

input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0

transcript="$(printf '%s' "$input" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
[ -n "$transcript" ] && [ -f "$transcript" ] || exit 0

# Count tool_use content blocks across the session transcript (JSONL).
n="$(grep -o '"type":"tool_use"' "$transcript" 2>/dev/null | wc -l | tr -d ' ')"
[ -n "$n" ] || n=0

if [ "$n" -gt "$budget" ]; then
    echo "⚠ session-budget: ${n} tool calls this session (soft budget ${budget}) — consider wrapping up, compacting, or narrowing scope. Override: DMF_SESSION_TOOL_BUDGET."
fi
exit 0
