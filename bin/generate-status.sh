#!/usr/bin/env bash
# generate-status.sh — regenerate STATUS.local.md at the umbrella root.
#
# Auto-derives the parts that come from `git log` / `git status` / `git fetch`
# across all 9 repos (umbrella + 8 components). Preserves a hand-edited
# section from committed STATUS.md between <!-- HUMAN-START --> and
# <!-- HUMAN-END --> markers so operators can record in-flight work,
# pending decisions, etc. without committing volatile repo-state tables.
#
# Usage:
#   bin/generate-status.sh                # regenerate STATUS.local.md (default)
#   bin/generate-status.sh --no-fetch     # skip remote fetch (offline-safe)
#
# This script is read-only against the cluster — it does not SSH anywhere.

set -euo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PARENT_DIR="$(dirname "$UMBRELLA_DIR")"
STATUS_NOTES_FILE="$UMBRELLA_DIR/STATUS.md"
STATUS_FILE="$UMBRELLA_DIR/STATUS.local.md"
COMPONENT_REPOS=(dmf-cms dmf-runbooks dmf-central dmf-infra dmf-env dmf-media dmf-init dmf-promsd)

# Component repos are siblings of the umbrella under a common parent since the
# public release (2026-06-11, ADR-0001 amendment); legacy nested checkouts
# still resolve.
is_repo_root() {
    local path="$1" top
    [ -e "$path/.git" ] && return 0
    top="$(git -C "$path" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$top" ] && [ "$top" = "$path" ]
}

component_path() {
    if is_repo_root "$UMBRELLA_DIR/$1"; then
        printf '%s' "$UMBRELLA_DIR/$1"
    else
        printf '%s' "$PARENT_DIR/$1"
    fi
}

DO_FETCH=1
for arg in "$@"; do
    case "$arg" in
        --no-fetch) DO_FETCH=0 ;;
        -h|--help)
            sed -n '/^# generate-status/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "unknown arg: $arg" >&2
            exit 1
            ;;
    esac
done

cd "$UMBRELLA_DIR"

# ── Collect repo state ───────────────────────────────────────────────────
collect_repo() {
    local name="$1" path="$2"
    local branch dirty unpushed last_commit_short last_commit_msg last_commit_age
    local count_dirty count_unpushed status_summary

    if ! is_repo_root "$path"; then
        printf '| %s | — | — | — | (not a git repo) |\n' "$name"
        return
    fi

    branch="$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

    # Dirty count (modified + untracked, excluding ignored)
    count_dirty="$(git -C "$path" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$count_dirty" -gt 0 ]; then
        # Path-safe summary: porcelain paths start at column 4 — awk '$NF'
        # split filenames containing spaces. quotepath off so such names
        # aren't C-quoted either.
        status_summary="$(git -C "$path" -c core.quotepath=false status --porcelain | head -3 | cut -c4- | tr '\n' '·' | sed 's/·$//')"
        dirty="${count_dirty}: \`${status_summary}\`"
    else
        dirty="clean"
    fi

    # Last commit — short hash + age, subject truncated to keep the row readable
    last_commit_short="$(git -C "$path" log -1 --format='%h' 2>/dev/null || echo '—')"
    last_commit_msg="$(git -C "$path" log -1 --format='%s' 2>/dev/null | cut -c1-50 || echo '—')"
    last_commit_age="$(git -C "$path" log -1 --format='%ar' 2>/dev/null || echo '—')"

    # Unpushed — only meaningful when an upstream exists. The old
    # `git log @{u}.. | wc -l || echo 0` double-printed ("0\n0") under
    # pipefail on branches without an upstream (e.g. pre-push topic
    # branches), corrupting the table cell across two lines.
    if [ "$DO_FETCH" -eq 1 ]; then
        git -C "$path" fetch --quiet 2>/dev/null || true
    fi
    if git -C "$path" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
        count_unpushed="$(git -C "$path" log '@{u}'..HEAD --oneline 2>/dev/null | wc -l | tr -d ' ')"
        if [ "$count_unpushed" = "0" ] || [ -z "$count_unpushed" ]; then
            unpushed="—"
        else
            unpushed="**$count_unpushed**"
        fi
    else
        unpushed="_(no upstream)_"
    fi

    # shellcheck disable=SC2016
    printf '| %s | %s | `%s` (%s) | %s | %s | %s |\n' \
        "$name" "$branch" "$last_commit_short" "$last_commit_age" "$last_commit_msg" "$dirty" "$unpushed"
}

# ── Collect operator-local envs (ADR-0035 store) ─────────────────────────
# Lists ~/.dmfdeploy/envs/<slug>/manifest.yaml metadata only (id, label,
# provider, arch, created) — never key material or bundle contents. Disk
# state is not liveness: a listed env's node may be gone (spot reclaim);
# the cluster is the truth.
collect_envs() {
    local envs_dir="${DMFDEPLOY_ENVS_DIR:-$HOME/.dmfdeploy/envs}"

    if [ ! -d "$envs_dir" ]; then
        echo "_No operator-local env store (\`~/.dmfdeploy/envs/\`) on this machine._"
        return
    fi

    local rows=""
    local dir manifest
    for dir in "$envs_dir"/*/; do
        [ -d "$dir" ] || continue
        manifest="$dir/manifest.yaml"
        [ -f "$manifest" ] || continue
        # First occurrence wins: the metadata: block precedes spec:, and both
        # repeat provider/architecture keys.
        rows+="$(awk '
            /^[[:space:]]*name:/         && !n { sub(/.*name:[[:space:]]*/,"");         gsub(/"/,""); name=$0; n=1 }
            /^[[:space:]]*label:/        && !l { sub(/.*label:[[:space:]]*/,"");        gsub(/"/,""); label=$0; l=1 }
            /^[[:space:]]*provider:/     && !p { sub(/.*provider:[[:space:]]*/,"");     gsub(/"/,""); prov=$0; p=1 }
            /^[[:space:]]*architecture:/ && !a { sub(/.*architecture:[[:space:]]*/,""); gsub(/"/,""); arch=$0; a=1 }
            /^[[:space:]]*created:/      && !c { sub(/.*created:[[:space:]]*/,"");      gsub(/"/,""); created=$0; c=1 }
            END {
                if (name != "")
                    printf("%s\t| `%s` | %s | %s | %s | %s |\n",
                           created, name, label, prov, arch, created)
            }' "$manifest")"$'\n'
    done

    if [ -z "${rows//[[:space:]]/}" ]; then
        echo "_Env store present but no env manifests found._"
        return
    fi

    echo "| Env | Label | Provider | Arch | Created |"
    echo "|---|---|---|---|---|"
    # Newest first by created date (the tab-prefixed sort key is stripped).
    printf '%s' "$rows" | sort -r | cut -f2-

    echo
    echo "_Disk state, not liveness — newest first. Verify the node exists before_"
    echo "_operating on an env (spot instances vanish without warning)._"
}

# ── Collect active plans from frontmatter ────────────────────────────────
collect_active_plans() {
    local plans
    plans="$(python3 -c '
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
    except Exception:
        continue
    if not head.startswith("---"):
        continue
    m = re.match(r"^---\n(.*?)\n---", head, re.DOTALL)
    if not m:
        continue
    block = m.group(1)
    status_m = re.search(r"^status:\s*(\S+)", block, re.MULTILINE)
    if not status_m or status_m.group(1) != "active":
        continue
    date_m = re.search(r"^date:\s*(\S+)", block, re.MULTILINE)
    ti_m = re.search(r"^tracking_issue:\s*(\S+)", block, re.MULTILINE)
    bare = base[:-3]
    date_v = date_m.group(1) if date_m else "?"
    ti = ti_m.group(1) if ti_m else ""
    print("\t".join([bare, date_v, ti]))
' 2>/dev/null)" || true

    if [ -z "$plans" ]; then
        echo "_No active plans._"
        return
    fi

    echo "| Plan | Date | Tracking issue |"
    echo "|---|---|---|"

    while IFS=$'\t' read -r bare date_v ti; do
        local ti_display="—"
        if [ -n "$ti" ]; then
            # Check staleness via gh if available
            local stale=""
            if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
                local issue_num
                issue_num="$(echo "$ti" | grep -oE 'issues/[0-9]+' | head -1 | sed 's/issues\///')" || true
                if [ -n "$issue_num" ]; then
                    local issue_state
                    issue_state="$(gh api "repos/dmfdeploy/dmfdeploy/issues/${issue_num}" --jq '.state' 2>/dev/null)" || true
                    if [ "$issue_state" = "closed" ]; then
                        stale=" ⚠ stale?"
                    fi
                fi
            fi
            # Link to the issue for readability
            local issue_num
            issue_num="$(echo "$ti" | grep -oE 'issues/[0-9]+' | head -1 | sed 's/issues\///')" || true
            if [ -n "$issue_num" ]; then
                ti_display="[#${issue_num}](${ti})${stale}"
            else
                ti_display="[link](${ti})${stale}"
            fi
        fi
        printf '| %s | %s | %s |\n' "$bare" "$date_v" "$ti_display"
    done <<< "$plans"
}

# ── Collect recent activity (last 7 days, all repos) ─────────────────────
collect_activity() {
    local since="${ACTIVITY_SINCE:-7 days ago}"
    local max_per_repo="${ACTIVITY_MAX_PER_REPO:-10}"

    # Collect all lines into a temp file so we can sort + count per repo
    local tmp
    tmp="$(mktemp)"

    # Umbrella
    git -C "$UMBRELLA_DIR" log --since="$since" --format='%cI%x09dmfdeploy%x09%h%x09%s' >> "$tmp" 2>/dev/null || true

    # Components
    local repo_dir
    for repo in "${COMPONENT_REPOS[@]}"; do
        repo_dir="$(component_path "$repo")"
        is_repo_root "$repo_dir" || continue
        git -C "$repo_dir" log --since="$since" --format='%cI%x09'"$repo"'%x09%h%x09%s' >> "$tmp" 2>/dev/null || true
    done

    if [ ! -s "$tmp" ]; then
        rm -f "$tmp"
        echo "_No commits in the last 7 days._"
        return
    fi

    printf '| When | Repo | Commit | Subject |\n'
    printf '|---|---|---|---|\n'

    # Sort newest first, cap per repo, format
    sort -r "$tmp" \
        | awk -F'\t' -v max="$max_per_repo" '
        {
            repo = $2
            count[repo]++
            if (count[repo] > max) next
            # ISO timestamp → human-friendly
            ts = $1
            gsub("T", " ", ts)
            sub("\\+.*$", "", ts)
            sub(":[0-9][0-9]$", "", ts)
            # Truncate subject
            subject = $4
            if (length(subject) > 70) subject = substr(subject, 1, 67) "..."
            printf("| %s | %s | %s | %s |\n", ts, repo, $3, subject)
        }
        END {
            for (r in count) {
                if (count[r] > max) {
                    extra = count[r] - max
                    printf("\n_%s: %d more commit(s) not shown._\n", r, extra)
                }
            }
        }'

    rm -f "$tmp"
}

# ── Extract human-edited section ─────────────────────────────────────────
extract_human_section() {
    if [ ! -f "$STATUS_NOTES_FILE" ]; then
        cat <<'EOF'
<!-- HUMAN-START -->
### In-flight work

_What's actively being worked on right now? Add bullets like:
- `<branch>` in `<repo>` — short description (started YYYY-MM-DD by <agent/operator>)_

### Pending decisions blocking >1 repo

_Decisions you can't push down to a single repo. Add bullets like:
- ADR-NNNN draft on <topic> — blocks <repo-A>, <repo-B>_

### Known divergences

_Things that look inconsistent across repos and need a sweep._

<!-- HUMAN-END -->
EOF
        return
    fi

    awk '
        /<!-- HUMAN-START -->/ { keep = 1; print; next }
        /<!-- HUMAN-END -->/ { print; keep = 0; next }
        keep { print }
    ' "$STATUS_NOTES_FILE"
}

# ── Compose ──────────────────────────────────────────────────────────────
compose_status() {
    local timestamp
    timestamp="$(date -u '+%Y-%m-%d %H:%M UTC')"

    cat <<EOF
# DMF Status

_Auto-generated $timestamp by \`bin/generate-status.sh\`. This local snapshot is gitignored._
_The committed [STATUS.md](STATUS.md) contains only hand-edited operator notes;
run this generator when you need the live repo-state snapshot._

For decisions, see [docs/decisions/](docs/decisions/INDEX.md).
For active task spec, see the most recent file in [docs/plans/](docs/plans/).
For live handoff state, read the claimed tracking issue's comments
(two-tier model, R4); [docs/handoffs/](docs/handoffs/INDEX.md) is a frozen archive.
For canonical architecture, see [docs/architecture/DMF Platform Plan.md](docs/architecture/DMF%20Platform%20Plan.md).

## Repo state

| Repo | Branch | Last commit | Subject | Dirty | Unpushed |
|---|---|---|---|---|---|
EOF

    collect_repo "dmfdeploy (umbrella)" "$UMBRELLA_DIR"
    for repo in "${COMPONENT_REPOS[@]}"; do
        collect_repo "$repo" "$(component_path "$repo")"
    done

    cat <<EOF

## Operator-local envs (~/.dmfdeploy/envs — ADR-0035)

EOF
    collect_envs

    cat <<EOF

## Active plans

EOF
    collect_active_plans

    cat <<EOF

## Recent activity (last 7 days, all repos)

EOF
    collect_activity

    cat <<EOF

## Operator notes (hand-edited — preserved across regenerations)

EOF
    extract_human_section

    cat <<EOF

---

**Boot ritual reminder:** when starting a session in any DMF repo,
\`git fetch && git pull\` the umbrella, run \`bin/generate-status.sh\`, read
this local snapshot, read the tracking issue you are claiming (comments
included — the live handoff surface; \`docs/handoffs/\` is a frozen archive), run
\`git status\` in any component repo (\`../dmf-*\`) you're about to touch, and
ask the user before modifying any component repo with dirty state. Edit
committed \`STATUS.md\` only for hand-maintained operator notes.
EOF
}

# ── Write ────────────────────────────────────────────────────────────────
new_content="$(compose_status)"
printf '%s\n' "$new_content" > "$STATUS_FILE"
echo "wrote $STATUS_FILE"
