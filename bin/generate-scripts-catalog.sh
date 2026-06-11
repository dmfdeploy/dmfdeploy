#!/usr/bin/env bash
# generate-scripts-catalog.sh — scan all DMF repos for shell scripts and
# produce docs/SCRIPTS.md, a single discoverable index. Each script's first
# non-shebang comment paragraph (consecutive `#` lines until the first
# blank `#`, with pure-decoration lines skipped) becomes its catalog entry.
#
# Convention: scripts live in <repo>/bin/ or <repo>/scripts/. The first
# paragraph after the shebang should be a tight summary of what the
# script does — that's what the catalog shows. Deeper detail goes in
# subsequent paragraphs separated by a blank `#`.
#
# Usage:
#   bin/generate-scripts-catalog.sh           # write docs/SCRIPTS.md
#   bin/generate-scripts-catalog.sh --check   # diff vs current; exit 1 on drift

set -euo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PARENT_DIR="$(dirname "$UMBRELLA_DIR")"
OUT="$UMBRELLA_DIR/docs/SCRIPTS.md"
COMPONENT_REPOS=(dmf-cms dmf-central dmf-infra dmf-env dmf-media dmf-init)

# Component repos are siblings of the umbrella under a common parent since the
# public release (2026-06-11, ADR-0001 amendment); legacy nested checkouts
# still resolve.
component_path() {
    if [ -e "$UMBRELLA_DIR/$1/.git" ]; then printf '%s' "$UMBRELLA_DIR/$1"
    else printf '%s' "$PARENT_DIR/$1"; fi
}

MODE="write"
for arg in "$@"; do
    case "$arg" in
        --check) MODE="check" ;;
        -h|--help)
            sed -n '/^# generate-scripts-catalog/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown arg: $arg" >&2; exit 1 ;;
    esac
done

cd "$UMBRELLA_DIR"

# Extract the first descriptive paragraph from a shell script's header.
# Reads contiguous comment lines (skipping pure-decoration lines that contain
# no letters), joins them with spaces, and strips any "scriptname.sh — " prefix.
# Stops at the first blank-comment line after content, or at first non-comment line.
extract_desc() {
    local file="$1"
    local base desc
    base="$(basename "$file")"
    desc="$(awk '
        BEGIN { have_content = 0 }
        /^#!/ { next }                             # skip shebang
        /^# *$/ {                                  # blank comment line
            if (have_content) exit                 # paragraph ended
            next                                   # otherwise keep looking
        }
        /^# / {
            sub(/^# */, "")
            # Skip pure-decoration lines (no letters at all — box drawing, ===, etc.)
            if (match($0, /[A-Za-z]/) == 0) next
            have_content = 1
            print
            next
        }
        /^[^#]/ { exit }                           # non-comment ends header
    ' "$file" | tr '\n' ' ' | sed -E 's/[[:space:]]+/ /g; s/^ //; s/ $//')"

    # Strip "scriptname — desc" / "scriptname: desc" / "scriptname - desc"
    # prefixes using bash parameter expansion (UTF-8 safe).
    desc="${desc#$base — }"
    desc="${desc#$base —}"
    desc="${desc#$base - }"
    desc="${desc#$base -}"
    desc="${desc#$base: }"
    desc="${desc#$base:}"

    # Escape pipes for markdown table
    desc="${desc//|/\\|}"

    printf '%s' "$desc"
}

emit_section() {
    local title="$1" subdir="$2"
    local has_any=0

    # First pass: see if there are any scripts
    for f in "$subdir"/*.sh; do
        [ -f "$f" ] && has_any=1 && break
    done
    [ "$has_any" -eq 0 ] && return

    {
        printf '\n## %s\n\n' "$title"
        printf '| Script | Description |\n'
        printf '|---|---|\n'
        for f in "$subdir"/*.sh; do
            [ -f "$f" ] || continue
            local rel desc exec_marker
            # Repo-relative display path in either layout (nested or sibling) —
            # never an absolute operator-local path (scrub gate category 3).
            rel="${f#$UMBRELLA_DIR/}"
            rel="${rel#$PARENT_DIR/}"
            desc="$(extract_desc "$f")"
            [ -z "$desc" ] && desc="_(no description in script header)_"
            if [ -x "$f" ]; then
                exec_marker=""
            else
                exec_marker=" *(not executable)*"
            fi
            printf '| `%s` | %s%s |\n' "$rel" "$desc" "$exec_marker"
        done
    }
}

compose_catalog() {
    cat <<EOF
# DMF Scripts Catalog

_Auto-generated $(date -u +%Y-%m-%d) by \`bin/generate-scripts-catalog.sh\`._

A single discoverable index of every shell script across the DMF repos.
Each entry shows where the script lives and what it does in one line.
Run the generator to refresh; \`--check\` exits non-zero on drift.

**Convention:** scripts live in \`<repo>/bin/\` or \`<repo>/scripts/\`. The
first non-shebang comment **paragraph** (consecutive \`#\` lines until the
first blank \`#\`, with pure-decoration lines skipped) becomes the catalog
description. Keep the first paragraph a tight summary; put deeper detail
in subsequent paragraphs separated by a blank \`#\`.

For a deeper read of any script, open it directly. For repository-specific
context (working directory, env vars, secrets discipline), see the relevant
repo's \`CLAUDE.md\` and the matching skill in \`.claude/skills/\`.
EOF

    # Umbrella first
    emit_section "umbrella — \`dmfdeploy/bin/\`" "$UMBRELLA_DIR/bin"

    # Mothballed agentic harness scripts (provenance; mutating ones fail
    # closed unless DMF_AGENTIC_OVERRIDE=1 — see bin/agentic/README.md)
    emit_section "umbrella — \`dmfdeploy/bin/agentic/\` (mothballed 2026-06-04)" "$UMBRELLA_DIR/bin/agentic"

    # Component repos: check bin/ then scripts/
    for repo in "${COMPONENT_REPOS[@]}"; do
        for sub in bin scripts; do
            local subdir
            subdir="$(component_path "$repo")/$sub"
            [ -d "$subdir" ] || continue
            emit_section "$repo — \`$repo/$sub/\`" "$subdir"
        done
    done
}

new_content="$(compose_catalog)"

if [ "$MODE" = "check" ]; then
    if [ ! -f "$OUT" ]; then
        echo "$OUT does not exist — run without --check to create" >&2
        exit 1
    fi
    if diff -q <(printf '%s\n' "$new_content") "$OUT" >/dev/null; then
        echo "$OUT is current."
        exit 0
    fi
    echo "$OUT drift:" >&2
    diff <(printf '%s\n' "$new_content") "$OUT" | head -40 >&2
    exit 1
fi

printf '%s\n' "$new_content" > "$OUT"
echo "wrote $OUT"
