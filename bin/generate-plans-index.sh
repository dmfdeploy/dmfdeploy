#!/usr/bin/env bash
# generate-plans-index.sh — scan docs/plans/*.md for YAML frontmatter and
# produce docs/plans/INDEX.md, grouped by status (Active / Draft / Executed /
# Superseded / Historical), newest-first. Superseded rows include
# superseded_by links; executed rows include executed dates when present.
#
# Usage:
#   bin/generate-plans-index.sh           # write docs/plans/INDEX.md
#   bin/generate-plans-index.sh --check   # diff vs current; exit 1 on drift

set -euo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
INDEX="$UMBRELLA_DIR/docs/plans/INDEX.md"

MODE="write"
for arg in "$@"; do
    case "$arg" in
        --check) MODE="check" ;;
        -h|--help)
            sed -n '/^# generate-plans-index.sh/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown arg: $arg" >&2; exit 1 ;;
    esac
done

cd "$UMBRELLA_DIR"

# ── Delegate to Python for reliable frontmatter parsing + markdown emit ──

generate_content() {
    python3 << 'PYEOF'
import os, re, subprocess, urllib.parse
from datetime import datetime, timezone

result = subprocess.run(
    ["git", "-c", "core.quotepath=false", "ls-files", "-z", "docs/plans/*.md"],
    capture_output=True, text=True
)
files = [f for f in result.stdout.split("\0") if f]

entries = []
for filepath in files:
    base = os.path.basename(filepath)
    if base in ("INDEX.md", "README.md"):
        continue
    with open(filepath) as fh:
        head = fh.read(1024)
    if not head.startswith("---"):
        continue
    m = re.match(r"^---\n(.*?)\n---", head, re.DOTALL)
    if not m:
        continue
    block = m.group(1)
    status_m = re.search(r"^status:\s*(\S+)", block, re.MULTILINE)
    date_m = re.search(r"^date:\s*(\S+)", block, re.MULTILINE)
    exec_m = re.search(r"^executed:\s*(\S+)", block, re.MULTILINE)
    sb_m = re.search(r'''^superseded_by:\s*["']?([^"'\n]+)["']?''', block, re.MULTILINE)

    bare = base[:-3]  # strip .md
    enc = urllib.parse.quote(base, safe="")
    sb_val = sb_m.group(1) if sb_m else ""
    sb_enc = urllib.parse.quote(sb_val, safe="") if sb_val else ""
    entries.append({
        "bare": bare,
        "status": status_m.group(1) if status_m else "",
        "date": date_m.group(1) if date_m else "",
        "executed": exec_m.group(1) if exec_m else "",
        "superseded_by": sb_val,
        "enc": enc,
        "sb_enc": sb_enc,
    })

today = datetime.now(timezone.utc).strftime("%Y-%m-%d")

lines = [
    "# DMF Plans Index",
    "",
    f"_Auto-generated {today} by `bin/generate-plans-index.sh`._",
    "",
    "Status taxonomy: **active** = guiding work now; **draft** = proposed/approved",
    "but not started; **executed** = work landed (terminal); **superseded** =",
    "replaced by a named successor; **historical** = point-in-time / frozen /",
    "shelved, kept for provenance.",
    "",
]

sections = [
    ("active", "Active"),
    ("draft", "Draft"),
    ("executed", "Executed"),
    ("superseded", "Superseded"),
    ("historical", "Historical"),
]

for status_val, title in sections:
    section_entries = [e for e in entries if e["status"] == status_val]
    # Sort newest-first by date
    section_entries.sort(key=lambda e: e["date"], reverse=True)
    lines.append("")
    lines.append(f"## {title} ({len(section_entries)})")
    lines.append("")
    for e in section_entries:
        item = f"- [{e['bare']}]({e['enc']}) — {e['date']}"
        if e["executed"]:
            item += f" (executed {e['executed']})"
        if e["superseded_by"]:
            item += f" → superseded by [{e['superseded_by']}]({e['sb_enc']})"
        lines.append(item)

print("\n".join(lines))
PYEOF
}

new_content="$(generate_content)"

if [ "$MODE" = "check" ]; then
    if [ ! -f "$INDEX" ]; then
        echo "$INDEX does not exist — run without --check to create" >&2
        exit 1
    fi
    if diff -q <(printf '%s\n' "$new_content") "$INDEX" >/dev/null; then
        echo "$INDEX is current."
        exit 0
    fi
    echo "$INDEX drift:" >&2
    diff <(printf '%s\n' "$new_content") "$INDEX" | head -40 >&2
    exit 1
fi

printf '%s\n' "$new_content" > "$INDEX"
echo "wrote $INDEX"
