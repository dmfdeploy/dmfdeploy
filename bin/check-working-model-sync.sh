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
#   bin/check-working-model-sync.sh --apply          # rewrite drifted blocks in place from the template
#   bin/check-working-model-sync.sh --report-pins    # how far behind each sibling's CI template pin is
#
# --apply is the generator the markers promise: it replaces the marker-fenced
# region of each agent file with the canonical block (idempotent — only differing
# blocks are touched, per-repo content is left alone). Keep it an EXPLICIT action,
# never a SessionStart auto-run, so it can't silently dirty a sibling repo another
# agent is working in. The default (--check) stays the pre-commit/CI gate.
#
# --report-pins exists because of how sibling CI consumes this template. Each
# component repo's `working-model` job checks out dmfdeploy/dmfdeploy and diffs
# its own copies against docs/templates/working-model-block.md. Historically that
# checkout carried no `ref:`, i.e. the umbrella's DEFAULT BRANCH resolved at CI
# time — so the instant a template correction landed on umbrella main, the
# working-model job failed on the next PR in all 8 component repos plus .github.
# A two-line clarification cost a 9-repo flag day, which is why the block was
# left contradicting the canonical filing rule for weeks rather than fixed.
#
# Siblings therefore pin `ref: working-model-vN` (an umbrella tag). Umbrella main
# can then correct the template without reddening anyone, and each sibling bumps
# its pin in its own PR alongside its regenerated copies. The cost of that trade
# is that a lagging sibling is now SILENT rather than loud — so this report makes
# the lag visible, and an unpinned repo is called out as the flag-day hazard it is.
#
# Exit: 0 clean (or all drift re-synced under --apply, or any --report-pins run),
#       1 drift (default) or missing block (--strict).

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
APPLY=0
REPORT_PINS=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --strict)        STRICT=1; shift ;;
        --umbrella-only) UMBRELLA_ONLY=1; shift ;;
        --apply)         APPLY=1; shift ;;
        --report-pins)   REPORT_PINS=1; shift ;;
        --repo)     SINGLE_REPO="$2"; shift 2 ;;
        --template) TEMPLATE="$2"; shift 2 ;;
        -h|--help)
            sed -n '/^# check-working-model-sync/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

resolve_repo_dir() {
    local repo="$1"
    if   [ -d "$UMBRELLA_DIR/$repo/.git" ]; then printf '%s\n' "$UMBRELLA_DIR/$repo"
    elif [ -d "$PARENT_DIR/$repo/.git" ];   then printf '%s\n' "$PARENT_DIR/$repo"
    fi
}

# Sorted oldest→newest. Numeric sort on the suffix rather than `sort -V`, which
# BSD/macOS sort does not reliably provide.
wm_tags() {
    git -C "$UMBRELLA_DIR" tag -l 'working-model-v*' 2>/dev/null \
        | sed 's/^working-model-v//' | sort -n | sed 's/^/working-model-v/'
}

# The pin a repo's working-model job uses, or empty when the checkout carries no
# `ref:` and therefore tracks the umbrella's default branch.
extract_pin() {
    grep -rhoE 'ref:[[:space:]]*working-model-v[0-9]+' "$1/.github/workflows/" 2>/dev/null \
        | head -1 | sed -E 's/.*(working-model-v[0-9]+)/\1/'
}

report_pins() {
    local tags latest pinned dir behind repo unpinned=0 lagging=0 found=0
    tags="$(wm_tags)"
    latest="$(printf '%s\n' "$tags" | tail -1)"
    [ -n "$latest" ] || latest="(none yet)"
    echo "working-model template pin report — umbrella latest: $latest"
    echo
    for repo in "${COMPONENT_REPOS[@]}"; do
        dir="$(resolve_repo_dir "$repo")"
        if [ -z "$dir" ]; then
            printf '  %-14s %-18s %s\n' "$repo" "-" "no local checkout — skipped"
            continue
        fi
        found=$((found + 1))
        pinned="$(extract_pin "$dir")"
        if [ -z "$pinned" ]; then
            printf '  %-14s %-18s %s\n' "$repo" "(unpinned)" \
                "tracks umbrella default branch — a template change breaks its CI at once"
            unpinned=$((unpinned + 1))
        elif [ "$pinned" = "$latest" ]; then
            printf '  %-14s %-18s %s\n' "$repo" "$pinned" "current"
        else
            behind="$(printf '%s\n' "$tags" | awk -v p="$pinned" 'f{c++} $0==p{f=1} END{print c+0}')"
            printf '  %-14s %-18s %s\n' "$repo" "$pinned" \
                "$behind behind — bump the pin, then --repo <path> --apply"
            lagging=$((lagging + 1))
        fi
    done
    echo
    if [ "$found" -eq 0 ]; then
        # Every repo skipped is NOT a clean report — it is a report that checked
        # nothing. Most often this is a run from a git worktree, where PARENT_DIR
        # is the worktree root rather than the repo estate's parent.
        echo "WARN: no sibling checkouts resolved — this report checked NOTHING." >&2
        echo "      Run it from the umbrella clone, or set DMFDEPLOY_UMBRELLA/UMBRELLA_DIR" >&2
        echo "      to the umbrella whose parent directory holds the component repos." >&2
        return 0
    fi
    echo "summary: $found checked — $unpinned unpinned, $lagging behind, latest $latest"
    echo "report only — never fails a build; each repo's --strict check is the gate"
}

if [ "$REPORT_PINS" -eq 1 ]; then
    report_pins
    exit 0
fi

[ -f "$TEMPLATE" ] || { echo "FAIL: template not found: $TEMPLATE" >&2; exit 1; }

extract_block() {
    awk '/<!-- WORKING-MODEL-BLOCK-START/{keep=1} keep{print} /<!-- WORKING-MODEL-BLOCK-END -->/{exit}' "$1"
}

# Replace the marker-fenced region of $1 with $canonical (which itself spans the
# START..END markers): splice prefix-before-START + canonical + suffix-after-END.
# (Done with single-line awk passes rather than `awk -v repl=...` because BSD awk
# rejects newlines inside a -v string.)
apply_block() {
    local file="$1" tmp
    tmp="$(mktemp)" || return 1
    awk '/<!-- WORKING-MODEL-BLOCK-START/{exit} {print}' "$file"            >  "$tmp"
    printf '%s\n' "$canonical"                                              >> "$tmp"
    awk 'p{print} /<!-- WORKING-MODEL-BLOCK-END -->/{p=1}' "$file"          >> "$tmp"
    mv "$tmp" "$file"
}

canonical="$(extract_block "$TEMPLATE")"
[ -n "$canonical" ] || { echo "FAIL: no block markers in template $TEMPLATE" >&2; exit 1; }

failures=0
checked=0
fixed=0

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
        if [ "$APPLY" -eq 1 ]; then
            if apply_block "$file"; then
                echo "  ✎ $file: block re-synced from template"
                fixed=$((fixed + 1))
            else
                echo "  ✗ $file: failed to rewrite block" >&2
                failures=$((failures + 1))
            fi
        else
            echo "  ✗ $file: working-model block DRIFTED from template" >&2
            diff <(printf '%s\n' "$canonical") <(printf '%s\n' "$block") | head -10 >&2
            failures=$((failures + 1))
        fi
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
if [ "$APPLY" -eq 1 ]; then
    echo "OK: re-synced $fixed block(s); $checked copy(ies) checked"
    exit 0
fi
echo "OK: $checked working-model block copy(ies) match the template"
