#!/usr/bin/env bash
# MOTHBALLED 2026-06-04 (historical, fails closed): bin/agentic/agent-status.sh — in-flight task status file helper.
#
# Replaces "agent-bridge read <pane> --lines N" polling with cheap reads
# of a JSON status file under docs/agentic/in-flight/<task-id>.json.
#
# The writing agent (typically Claude, doing the work) calls `write` at
# each phase boundary. The observing agent (typically Codex, supervising)
# calls `read` to see structured state instead of parsing pane scrollback.
#
# File schema (all fields optional except task_id, started_at, updated_at):
#   {
#     "task_id":    "pr5-bootstrap-verify",
#     "agent":      "claude",
#     "pane":       "2",
#     "phase":      "bootstrap-verify.yml running",
#     "started_at": "2026-05-24T15:34:44Z",
#     "updated_at": "2026-05-24T15:42:11Z",
#     "pid":        36979,
#     "log_path":   "/tmp/dmf-playbook-logs/pr5-...log",
#     "ok":         36,
#     "failed":     0,
#     "status":     "running",       // running | done | failed | halted
#     "note":       "free-text breadcrumb"
#   }
#
# Commands:
#   write <task-id> [--agent X] [--pane N] [--phase X] [--pid N]
#                   [--log PATH] [--ok N] [--failed N] [--status S]
#                   [--note X]
#       Upserts the file (merges over any existing fields). Always refreshes
#       updated_at. Creates the file (and started_at) on first write.
#       Prints the file path to stdout.
#
#   read  <task-id>                 Prints the JSON document, pretty-printed.
#   list                            Tabular listing of all in-flight tasks.
#   clear <task-id>                 Removes the file. Idempotent.
#
# Exit codes:
#   0  success
#   1  task not found (read/clear when nothing to clear)
#   2  bad usage / unknown flag / invalid task_id
#
# Refs:
#   docs/agentic/STATUS-FILE-CONVENTION.md (full schema + adoption notes)
#   docs/plans/DMF Agentic Harness Plan 2026-05-11.md §Layer 2

set -euo pipefail

if [[ "${DMF_AGENTIC_OVERRIDE:-}" != "1" ]]; then
    echo "mothballed 2026-06-04 — set DMF_AGENTIC_OVERRIDE=1 to run" >&2
    exit 1
fi

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
IN_FLIGHT_DIR="${IN_FLIGHT_DIR:-$UMBRELLA_DIR/docs/agentic/in-flight}"

usage() {
    sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'
}

valid_task_id() {
    [[ "$1" =~ ^[A-Za-z0-9_.-]+$ ]]
}

now_utc() {
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

require_jq() {
    command -v jq >/dev/null 2>&1 || {
        echo "agent-status: jq is required (brew install jq)" >&2
        exit 2
    }
}

cmd_write() {
    [ "$#" -ge 1 ] || { echo "write: task_id required" >&2; exit 2; }
    local task_id="$1"; shift
    valid_task_id "$task_id" || {
        echo "write: invalid task_id (allowed: [A-Za-z0-9_.-]+)" >&2; exit 2
    }

    local now; now="$(now_utc)"
    local -a jq_args=( --arg _task_id "$task_id" --arg _updated_at "$now" )
    local jq_filter='{task_id: $_task_id, updated_at: $_updated_at}'

    while [ "$#" -gt 0 ]; do
        case "$1" in
            --agent|--pane|--phase|--log|--status|--note)
                local key="${1#--}"
                [ "$key" = "log" ] && key="log_path"
                jq_args+=( --arg "_${key}" "$2" )
                jq_filter+=" + {${key}: \$_${key}}"
                shift 2 ;;
            --pid|--ok|--failed)
                local nkey="${1#--}"
                [[ "$2" =~ ^-?[0-9]+$ ]] || {
                    echo "write: ${1} expects integer, got '$2'" >&2; exit 2
                }
                jq_args+=( --argjson "_${nkey}" "$2" )
                jq_filter+=" + {${nkey}: \$_${nkey}}"
                shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) echo "write: unknown flag '$1'" >&2; exit 2 ;;
        esac
    done

    mkdir -p "$IN_FLIGHT_DIR"
    local file="$IN_FLIGHT_DIR/${task_id}.json"
    local patch
    patch="$(jq -nc "${jq_args[@]}" "$jq_filter")"

    local tmp="${file}.tmp.$$"
    if [ -f "$file" ]; then
        jq -s '.[0] * .[1]' "$file" <(echo "$patch") > "$tmp"
    else
        jq -n --arg _started_at "$now" --argjson _patch "$patch" \
            '{started_at: $_started_at} * $_patch' > "$tmp"
    fi
    mv "$tmp" "$file"
    echo "$file"
}

cmd_read() {
    [ "$#" -ge 1 ] || { echo "read: task_id required" >&2; exit 2; }
    local task_id="$1"
    local file="$IN_FLIGHT_DIR/${task_id}.json"
    [ -f "$file" ] || { echo "read: no such task: $task_id" >&2; exit 1; }
    jq . "$file"
}

cmd_list() {
    if [ ! -d "$IN_FLIGHT_DIR" ]; then
        echo "(no in-flight tasks)"
        return 0
    fi
    shopt -s nullglob
    local files=( "$IN_FLIGHT_DIR"/*.json )
    if [ "${#files[@]}" -eq 0 ]; then
        echo "(no in-flight tasks)"
        return 0
    fi
    printf "%-30s %-10s %-40s %s\n" "TASK_ID" "STATUS" "PHASE" "UPDATED_AT"
    printf "%-30s %-10s %-40s %s\n" "-------" "------" "-----" "----------"
    local f
    for f in "${files[@]}"; do
        jq -r '[
            (.task_id // "?"),
            (.status // "?"),
            ((.phase // "-") | .[0:39]),
            (.updated_at // "-")
        ] | @tsv' "$f" \
        | awk -F'\t' '{ printf "%-30s %-10s %-40s %s\n", $1, $2, $3, $4 }'
    done
}

cmd_clear() {
    [ "$#" -ge 1 ] || { echo "clear: task_id required" >&2; exit 2; }
    local task_id="$1"
    local file="$IN_FLIGHT_DIR/${task_id}.json"
    if [ -f "$file" ]; then
        rm -f "$file"
        echo "cleared: $task_id"
    else
        echo "clear: no such task: $task_id" >&2
        exit 1
    fi
}

require_jq

cmd="${1:-}"
[ "$#" -gt 0 ] && shift
case "$cmd" in
    write) cmd_write "$@" ;;
    read)  cmd_read  "$@" ;;
    list)  cmd_list ;;
    clear) cmd_clear "$@" ;;
    ""|-h|--help) usage ;;
    *) echo "unknown command: $cmd" >&2; usage >&2; exit 2 ;;
esac
