#!/usr/bin/env bash
# check-docs.sh — offline documentation gate for the DMF umbrella.
# Hard-fails on missing/broken frontmatter, dangling superseded_by targets,
# stale plans index, or inconsistent ADR file↔INDEX cross-references.
# Prints warnings for issues that don't block (missing tracking_issue,
# unresolved links, closed tracking issues).
#
# Scope (pass 1): docs/plans/ frontmatter + links, docs/decisions/ index↔files.
#
# Usage:
#   bin/check-docs.sh          # run all checks; exit 1 on any hard failure
#   bin/check-docs.sh --check  # synonym for bare invocation (for CI)

set -euo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

for arg in "$@"; do
    case "$arg" in
        --check|-h|--help)
            sed -n '/^# check-docs.sh/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown arg: $arg" >&2; exit 1 ;;
    esac
done

cd "$UMBRELLA_DIR"

FAILED=0

# ── Use Python for reliable frontmatter parsing ──

# Produces a report on stdout: one line per file, tab-separated:
# filepath \t status \t date \t executed \t superseded_by
# Lines starting with "ERROR:" are hard failures (no frontmatter, etc.)
parse_all_plans() {
    python3 << 'PYEOF'
import os, re, subprocess

result = subprocess.run(
    ["git", "-c", "core.quotepath=false", "ls-files", "-z", "docs/plans/*.md"],
    capture_output=True, text=True
)
files = [f for f in result.stdout.split("\0") if f]

for filepath in files:
    base = os.path.basename(filepath)
    if base in ("INDEX.md", "README.md"):
        continue
    try:
        with open(filepath) as fh:
            head = fh.read(1024)
    except Exception as e:
        print(f"ERROR\t{filepath}\tcannot read: {e}")
        continue
    if not head.startswith("---"):
        print(f"ERROR\t{filepath}\tdoes not start with '---'")
        continue
    m = re.match(r"^---\n(.*?)\n---", head, re.DOTALL)
    if not m:
        print(f"ERROR\t{filepath}\tempty or malformed frontmatter block")
        continue
    block = m.group(1)
    status_m = re.search(r"^status:\s*(\S+)", block, re.MULTILINE)
    date_m = re.search(r"^date:\s*(\S+)", block, re.MULTILINE)
    exec_m = re.search(r"^executed:\s*(\S+)", block, re.MULTILINE)
    sb_m = re.search(r'''^superseded_by:\s*["']?([^"'\n]+)["']?''', block, re.MULTILINE)
    status = status_m.group(1) if status_m else ""
    date_v = date_m.group(1) if date_m else ""
    executed = exec_m.group(1) if exec_m else ""
    sb = sb_m.group(1) if sb_m else ""
    if not status:
        print(f"ERROR\t{filepath}\tmissing status")
    elif status not in ("active", "draft", "executed", "superseded", "historical"):
        print(f"ERROR\t{filepath}\tinvalid status '{status}'")
    elif not date_v:
        print(f"ERROR\t{filepath}\tmissing date")
    else:
        # OK line
        print(f"OK\t{filepath}\t{status}\t{date_v}\t{executed}\t{sb}")
PYEOF
}

# ── HARD CHECK 1: Frontmatter on every plan file ─

echo "── check: frontmatter on every plan file"

BAD_FM=()
SUPERSEDED_FILES=()
SUPERSEDED_BY=()

while IFS=$'\t' read -r level filepath status _date _exec sb; do
    if [ "$level" = "ERROR" ]; then
        BAD_FM+=("${filepath}: ${status}")
    elif [ "$level" = "OK" ]; then
        if [ "$status" = "superseded" ] && [ -n "$sb" ]; then
            SUPERSEDED_FILES+=("$filepath")
            SUPERSEDED_BY+=("$sb")
        fi
    fi
done < <(parse_all_plans)

if [ "${#BAD_FM[@]}" -gt 0 ]; then
    echo "  ✗ frontmatter issues:" >&2
    for item in "${BAD_FM[@]}"; do
        echo "    ${item}" >&2
    done
    FAILED=1
else
    echo "  ✓ all plan files have valid frontmatter"
fi

# ── HARD CHECK 2: superseded_by targets exist ─

echo "── check: superseded_by targets exist"

BAD_SB=()
for i in "${!SUPERSEDED_FILES[@]}"; do
    filepath="${SUPERSEDED_FILES[$i]}"
    sb="${SUPERSEDED_BY[$i]}"
    target="docs/plans/${sb}"
    if [ ! -f "$target" ]; then
        BAD_SB+=("${filepath}: superseded_by target '${sb}' does not exist")
    fi
done

if [ "${#BAD_SB[@]}" -gt 0 ]; then
    echo "  ✗ dangling superseded_by:" >&2
    for item in "${BAD_SB[@]}"; do
        echo "    ${item}" >&2
    done
    FAILED=1
else
    echo "  ✓ all superseded_by targets exist"
fi

# ── HARD CHECK 3: generate-plans-index.sh --check is clean ─

echo "── check: plans index consistency"

if [ -x "bin/generate-plans-index.sh" ]; then
    if ! bin/generate-plans-index.sh --check >/dev/null 2>&1; then
        echo "  ✗ docs/plans/INDEX.md is stale — run bin/generate-plans-index.sh" >&2
        FAILED=1
    else
        echo "  ✓ plans index is current"
    fi
else
    echo "  ✗ bin/generate-plans-index.sh not found or not executable" >&2
    FAILED=1
fi

# ── HARD CHECK 4: docs/decisions/INDEX.md ↔ 00*.md consistency ─

echo "── check: ADR file↔INDEX cross-references"

ADR_BAD=()
INDEX_PATH="docs/decisions/INDEX.md"
if [ -f "$INDEX_PATH" ]; then
    # 4a: Every 00*.md must be mentioned in INDEX.md
    index_content="$(cat "$INDEX_PATH")"
    for adr_file in docs/decisions/00*.md; do
        [ -f "$adr_file" ] || continue
        adr_base="$(basename "$adr_file")"
        if ! echo "$index_content" | grep -qF "$adr_base"; then
            ADR_BAD+=("${adr_file}: not mentioned in ${INDEX_PATH}")
        fi
    done

    # 4b: Every ADR filename reference in INDEX.md must exist as a file
    # Use Python to extract bare filenames matching 00*.md pattern
    while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        if [ ! -f "docs/decisions/${ref}" ]; then
            ADR_BAD+=("${INDEX_PATH}: references '${ref}' which does not exist")
        fi
    done < <(python3 -c "
import re
with open('${INDEX_PATH}') as f:
    content = f.read()
# Find all markdown links or bare refs to 00*.md files
for m in re.finditer(r'(\b00\d{2}[-a-zA-Z0-9_]+\.md)\b', content):
    print(m.group(1))
" | sort -u)
else
    ADR_BAD+=("${INDEX_PATH}: file not found")
fi

if [ "${#ADR_BAD[@]}" -gt 0 ]; then
    echo "  ✗ ADR inconsistency:" >&2
    for item in "${ADR_BAD[@]}"; do
        echo "    ${item}" >&2
    done
    FAILED=1
else
    echo "  ✓ ADR file↔INDEX consistent"
fi

# ── WARNINGS (never affect exit code) ────────────────────────────────────────

echo ""
echo "── warnings"

warn_count=0

# W1: Unresolved relative .md links in docs/plans/
echo "  · checking unresolved relative links ..."
while IFS= read -r -d '' filepath; do
    # Extract markdown link targets: [text](target)
    while IFS= read -r link_target; do
        [ -z "$link_target" ] && continue
        [[ "$link_target" == http* ]] && continue
        [[ "$link_target" == mailto:* ]] && continue
        [[ "$link_target" == "#"* ]] && continue
        # URL-decode, then drop any #fragment
        decoded="$(python3 -c "import urllib.parse,sys; print(urllib.parse.unquote(sys.argv[1]))" "$link_target" 2>/dev/null)" || continue
        decoded="${decoded%%#*}"
        [ -z "$decoded" ] && continue
        # Only .md targets; skip regex-shaped/code false positives and
        # paren-containing filenames (the ERE stops at the first ')')
        [[ "$decoded" != *.md ]] && continue
        [[ "$decoded" == *"("* ]] && continue
        [[ "$decoded" == *"<"* ]] && continue
        # Resolve relative to the file's directory
        file_dir="$(dirname "$filepath")"
        resolved="${file_dir}/${decoded}"
        if [ ! -e "$resolved" ]; then
            echo "    ⚠ ${filepath}: unresolved link '${link_target}' (looked for '${resolved}')"
            warn_count=$((warn_count + 1))
        fi
    # BSD grep has no -P; -E plus explicit ](...) stripping is portable
    done < <(grep -oE '\]\([^)]+\)' "$filepath" 2>/dev/null | sed -E 's/^\]\(//; s/\)$//' || true)
done < <(git -c core.quotepath=false ls-files -z 'docs/plans/*.md' 2>/dev/null)

# W2: Active plans without tracking_issue
echo "  · checking active plans without tracking_issue ..."
while IFS=$'\t' read -r level filepath status _date _exec _sb; do
    if [ "$level" = "OK" ] && [ "$status" = "active" ]; then
        # Re-read frontmatter to check for tracking_issue
        head_content="$(head -20 "$filepath" 2>/dev/null)" || continue
        fm_block="$(echo "$head_content" | sed -n '2,/^---$/p' | sed '$d')" || true
        if ! echo "$fm_block" | grep -q '^tracking_issue:'; then
            echo "    ⚠ ${filepath}: active but no tracking_issue"
            warn_count=$((warn_count + 1))
        fi
    fi
done < <(parse_all_plans)

# W3: Active plan whose tracking_issue is closed (only if gh available)
if command -v gh >/dev/null 2>&1; then
    if gh auth status >/dev/null 2>&1; then
        echo "  · checking closed tracking issues ..."
        while IFS= read -r -d '' filepath; do
            head_content="$(head -20 "$filepath" 2>/dev/null)" || continue
            [[ "$head_content" != "---"* ]] && continue
            fm_block="$(echo "$head_content" | sed -n '2,/^---$/p' | sed '$d')" || true
            status="$(echo "$fm_block" | grep '^status:' | head -1 | sed 's/^status: *//' | tr -d '[:space:]')" || true
            if [ "$status" = "active" ]; then
                ti="$(echo "$fm_block" | grep '^tracking_issue:' | head -1 | sed 's/^tracking_issue: *//')" || true
                if [ -n "$ti" ]; then
                    issue_num="$(echo "$ti" | grep -oE 'issues/[0-9]+' | head -1 | sed 's/issues\///')" || true
                    if [ -n "$issue_num" ]; then
                        issue_state="$(gh api "repos/dmfdeploy/dmfdeploy/issues/${issue_num}" --jq '.state' 2>/dev/null)" || true
                        if [ "$issue_state" = "closed" ]; then
                            echo "    ⚠ ${filepath}: tracking_issue #${issue_num} is closed"
                            warn_count=$((warn_count + 1))
                        fi
                    fi
                fi
            fi
        done < <(git -c core.quotepath=false ls-files -z 'docs/plans/*.md' 2>/dev/null)
    fi
fi

echo ""
if [ "$FAILED" -eq 0 ]; then
    echo "check-docs: ok (${warn_count} warning(s))"
    exit 0
else
    echo "check-docs: FAILED (${warn_count} warning(s))" >&2
    exit 1
fi
