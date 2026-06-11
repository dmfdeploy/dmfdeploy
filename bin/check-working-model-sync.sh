#!/usr/bin/env bash
# check-working-model-sync.sh — keep the working-model block from drifting.
#
# The canonical copy of the agent-context working-model block lives at
# docs/templates/working-model-block.md (between the WORKING-MODEL-BLOCK
# markers). Every CLAUDE.md / AGENTS.md / QWEN.md across the 9 repos carries a
# byte-identical copy. This script extracts each copy and diffs it against the
# template, so 27 hand-pasted copies cannot drift (umbrella issue #32).
#
# Usage:
#   bin/check-working-model-sync.sh                  # umbrella strict; siblings checked if present
#   bin/check-working-model-sync.sh --umbrella-only  # skip sibling repos (pre-commit/CI: never blocked by another repo's drift)
#   bin/check-working-model-sync.sh --strict         # missing block in an existing file = fail
#   bin/check-working-model-sync.sh --repo <path>    # check one repo dir (component CI)
#   bin/check-working-model-sync.sh --template <f>   # alternate template (e.g. curl'd from umbrella)
#
# Exit: 0 clean, 1 drift (always) or missing block (--strict).

set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PARENT_DIR="$(dirname "$UMBRELLA_DIR")"
TEMPLATE="$UMBRELLA_DIR/docs/templates/working-model-block.md"
# Component + org meta repos (sibling dirs under $PARENT_DIR).
COMPONENT_REPOS=(dmf-cms dmf-runbooks dmf-central dmf-infra dmf-env dmf-media dmf-init dmf-promsd .github)
AGENT_FILES=(CLAUDE.md AGENTS.md QWEN.md)

STRICT=0
SINGLE_REPO=""
UMBRELLA_ONLY=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --strict)        STRICT=1; shift ;;
        --umbrella-only) UMBRELLA_ONLY=1; shift ;;
        --repo)     SINGLE_REPO="$2"; shift 2 ;;
        --template) TEMPLATE="$2"; shift 2 ;;
        -h|--help)
            sed -n '/^# check-working-model-sync/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

[ -f "$TEMPLATE" ] || { echo "FAIL: template not found: $TEMPLATE" >&2; exit 1; }

extract_block() {
    awk '/<!-- WORKING-MODEL-BLOCK-START/{keep=1} keep{print} /<!-- WORKING-MODEL-BLOCK-END -->/{exit}' "$1"
}

canonical="$(extract_block "$TEMPLATE")"
[ -n "$canonical" ] || { echo "FAIL: no block markers in template $TEMPLATE" >&2; exit 1; }

failures=0
checked=0

check_file() {
    local file="$1"
    if [ ! -f "$file" ]; then
        # --strict: a missing agent file is a real hole — that agent's harness
        # auto-loads exactly this file, so the forcing mechanism silently
        # vanishes (claude-bottom finding, 2026-06-11). Every repo carries all
        # three of CLAUDE.md + AGENTS.md + QWEN.md.
        if [ "$STRICT" -eq 1 ]; then
            echo "  ✗ $file: agent context file MISSING (CLAUDE.md + AGENTS.md + QWEN.md are all required)" >&2
            failures=$((failures + 1))
        fi
        return 0
    fi
    local block
    block="$(extract_block "$file")"
    if [ -z "$block" ]; then
        if [ "$STRICT" -eq 1 ]; then
            echo "  ✗ $file: working-model block MISSING" >&2
            failures=$((failures + 1))
        else
            echo "  · $file: no working-model block yet (info; --strict makes this fail)"
        fi
        return 0
    fi
    checked=$((checked + 1))
    if [ "$block" != "$canonical" ]; then
        echo "  ✗ $file: working-model block DRIFTED from template" >&2
        diff <(printf '%s\n' "$canonical") <(printf '%s\n' "$block") | head -10 >&2
        failures=$((failures + 1))
    fi
}

check_repo_dir() {
    local dir="$1"
    for f in "${AGENT_FILES[@]}"; do
        check_file "$dir/$f"
    done
}

if [ -n "$SINGLE_REPO" ]; then
    check_repo_dir "$SINGLE_REPO"
else
    # Umbrella: the block is mandatory regardless of --strict.
    saved_strict=$STRICT; STRICT=1
    check_repo_dir "$UMBRELLA_DIR"
    STRICT=$saved_strict
    # Components (sibling canonical, nested legacy); absent checkouts are skipped —
    # each component repo gates its own copies in its CI.
    if [ "$UMBRELLA_ONLY" -eq 0 ]; then
        for repo in "${COMPONENT_REPOS[@]}"; do
            if   [ -d "$UMBRELLA_DIR/$repo/.git" ]; then check_repo_dir "$UMBRELLA_DIR/$repo"
            elif [ -d "$PARENT_DIR/$repo/.git" ];   then check_repo_dir "$PARENT_DIR/$repo"
            fi
        done
    fi
fi

if [ "$failures" -gt 0 ]; then
    echo "FAIL: $failures working-model block issue(s); canonical template: docs/templates/working-model-block.md" >&2
    exit 1
fi
echo "OK: $checked working-model block copy(ies) match the template"
