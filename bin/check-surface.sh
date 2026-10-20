#!/usr/bin/env bash
# check-surface.sh — check the working surface of the umbrella repo against its
# size budgets, filename convention and archive-placement rules (hygiene
# enforcement, dmfdeploy/dmfdeploy#617).
#
# Subcommands: size, filenames, placement, statuslog, all (default).
#   size       README.md, AGENTS.md and each ADR stay under a line budget.
#   statuslog  STATUS.md stays under its line budget (no long status log).
#   filenames  Live docs use kebab-case names with no spaces and no date.
#   placement  docs/plans/ holds only plans with status active or draft, and
#              no live doc links into docs/archive/.
#
# Usage:
#   bin/check-surface.sh [--warn|--strict] [SUBCOMMAND] [--root DIR] [--file PATH ...]
#
#   --warn     report findings and exit 0 (default; used by the hook and CI).
#   --strict   exit 1 when there is any finding. Enforcement is switched on
#              later, in the integration package.
#   --root DIR scan the tree under DIR instead of the repository root.
#   --file P   check only the named file(s), applying every check that fits
#              the file's name and location. Tests use this to check fixtures
#              without depending on the real tree.
#
# The README, AGENTS.md and STATUS.md budgets come from #617. The ADR number
# is a target, not a hard cap: it is set by #617 and plan answer 6, and the
# ADR rewrite must show that every normative sentence survives.
#
# The AGENTS.md budget counts only the lines outside the working-model block:
# the span from the line containing WORKING-MODEL-BLOCK-START to the line
# containing WORKING-MODEL-BLOCK-END, marker lines included, is excluded. That
# block is generated and required by bin/check-working-model-sync.sh. A block
# with a start marker but no end marker excludes nothing.

set -euo pipefail

# ── Budgets (maximum number of lines) ────────────────────────────────────────
BUDGET_README=100
BUDGET_AGENTS=60
BUDGET_ADR=80
BUDGET_STATUS=30

# Trees that are never "live": the archive and the frozen trees.
EXCLUDED_RE='(^|/)docs/(archive|handoffs|agentic)/'
# Conventional upper-case names that the filename rule allows.
ALLOWED_NAMES_RE='^(README|INDEX)\.md$'

MODE="warn"
SUB="all"
ROOT=""
FILES=()

while [ $# -gt 0 ]; do
    case "$1" in
        --warn) MODE="warn" ;;
        --strict) MODE="strict" ;;
        --root) ROOT="${2:?--root needs a directory}"; shift ;;
        --file) FILES+=("${2:?--file needs a path}"); shift ;;
        size|statuslog|filenames|placement|all) SUB="$1" ;;
        -h|--help)
            sed -n '/^# check-surface/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "check-surface: unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

if [ -z "$ROOT" ]; then
    ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fi

FINDINGS=0
finding() {
    FINDINGS=$((FINDINGS + 1))
    printf 'check-surface: %s\n' "$*"
}

wants() { [ "$SUB" = all ] || [ "$SUB" = "$1" ]; }

is_excluded() { printf '%s\n' "$1" | grep -qE "$EXCLUDED_RE"; }

line_count() { wc -l < "$1" | tr -d ' '; }

# Number of lines outside the working-model block (marker lines excluded from
# the count). Without a complete START..END span, this is the whole file.
lines_outside_block() {
    awk '
        { total++ }
        s == 0 && /WORKING-MODEL-BLOCK-START/ { s = NR }
        s > 0 && e == 0 && /WORKING-MODEL-BLOCK-END/ { e = NR }
        END { if (s > 0 && e >= s) total -= (e - s + 1); print total + 0 }
    ' "$1"
}

# check_size FILE LABEL BUDGET [outside-block]
check_size() {
    local n
    if [ "${4:-}" = outside-block ]; then
        n="$(lines_outside_block "$1")"
    else
        n="$(line_count "$1")"
    fi
    if [ "$n" -gt "$3" ]; then
        finding "$2: $n lines, budget is $3 ($1)"
    fi
}

# Classify a file by its base name and run the matching size or status check.
check_file_size() {
    local path="$1" base lower
    base="$(basename "$path")"
    lower="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
        status*)
            wants statuslog && check_size "$path" "status log" "$BUDGET_STATUS" ;;
        readme*)
            wants size && check_size "$path" "README" "$BUDGET_README" ;;
        agents*)
            wants size && check_size "$path" "AGENTS.md" "$BUDGET_AGENTS" outside-block ;;
        adr-*|[0-9][0-9][0-9][0-9]-*)
            case "$lower" in 0000-*) return 0 ;; esac
            wants size && check_size "$path" "ADR" "$BUDGET_ADR" ;;
    esac
    return 0
}

# The filename rule applies to files under a docs/ directory.
check_file_name() {
    local path="$1" base
    base="$(basename "$path")"
    wants filenames || return 0
    printf '%s\n' "$path" | grep -qE '(^|/)docs/' || return 0
    is_excluded "$path" && return 0
    printf '%s\n' "$base" | grep -qE "$ALLOWED_NAMES_RE" && return 0
    if printf '%s\n' "$base" | grep -q ' '; then
        finding "filename has a space: $path"
    elif printf '%s\n' "$base" | grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2}'; then
        finding "filename has a date: $path"
    elif ! printf '%s\n' "$base" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*(\.[a-z0-9]+)+$'; then
        finding "filename is not kebab-case: $path"
    fi
    return 0
}

frontmatter_status() {
    awk '
        NR == 1 { if ($0 != "---") exit; next }
        /^---[ \t]*$/ { exit }
        /^status:/ { sub(/^status:[ \t]*/, ""); gsub(/["\047]/, ""); sub(/[ \t].*$/, ""); print; exit }
    ' "$1"
}

check_file_placement() {
    local path="$1" base st
    base="$(basename "$path")"
    wants placement || return 0
    is_excluded "$path" && return 0
    case "$path" in *.md) ;; *) return 0 ;; esac
    # A plan sits in a directory named plans (docs/plans/ in the real tree).
    if printf '%s\n' "$path" | grep -qE '(^|/)plans/[^/]+$' && [ "$base" != INDEX.md ]; then
        st="$(frontmatter_status "$path")"
        case "$st" in
            active|draft) ;;
            "") finding "plan has no status in its frontmatter: $path" ;;
            *) finding "plan status is '$st', docs/plans/ holds only active or draft: $path" ;;
        esac
    fi
    # A live doc must not link into the archive.
    if grep -qE '\]\([^)]*archive/' "$path"; then
        finding "live doc links into docs/archive/: $path"
    fi
    return 0
}

check_one() {
    check_file_size "$1"
    check_file_name "$1"
    check_file_placement "$1"
}

if [ ${#FILES[@]} -gt 0 ]; then
    for f in "${FILES[@]}"; do
        [ -f "$f" ] || { echo "check-surface: no such file: $f" >&2; exit 2; }
        check_one "$f"
    done
else
    cd "$ROOT"
    # Top-level budgeted files.
    for f in README.md AGENTS.md STATUS.md; do
        [ -f "$f" ] && check_file_size "$f"
    done
    # ADRs.
    if [ -d docs/decisions ]; then
        for f in docs/decisions/[0-9][0-9][0-9][0-9]-*.md; do
            [ -f "$f" ] && check_file_size "$f"
        done
    fi
    # Every file under docs/ (names), plus plans and links (markdown).
    if [ -d docs ]; then
        while IFS= read -r f; do
            check_file_name "$f"
            check_file_placement "$f"
        done < <(find docs -type f | LC_ALL=C sort)
    fi
fi

if [ "$FINDINGS" -gt 0 ]; then
    echo "check-surface: $FINDINGS finding(s) ($MODE mode)"
    [ "$MODE" = strict ] && exit 1
else
    echo "check-surface: clean"
fi
exit 0
