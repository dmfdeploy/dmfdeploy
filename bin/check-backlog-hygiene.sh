#!/usr/bin/env bash
# check-backlog-hygiene.sh — detect GitHub backlog drift across the DMF org.
#
# Read-only detector: every OPEN issue in the umbrella repo must carry a
# milestone, at least one component:* label, and at least one workstream:*
# label. The script also verifies that umbrella issues appear on the org
# Project board with Component and Workstream fields populated, flags active
# plan docs whose tracking issue is CLOSED, and surfaces untriaged component-
# repo issues older than the staleness threshold. (umbrella issue #32)
#
# Usage:
#   bin/check-backlog-hygiene.sh          # full run (umbrella + component repos + board)
#   bin/check-backlog-hygiene.sh --help   # print this header
#
# Exit: 0 = no findings, 1 = one or more findings detected.
# Env overrides:
#   DMF_TRIAGE_DAYS  — staleness threshold for untriaged component issues (default 7)

set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

# ── Constants ──────────────────────────────────────────────────────────────
ORG="dmfdeploy"
UMBRELLA_REPO="dmfdeploy/dmfdeploy"
PROJECT_ID="PVT_kwDOENb9uM4BaPY-"
COMPONENT_REPOS=(dmf-cms dmf-runbooks dmf-central dmf-infra dmf-env dmf-media dmf-init dmf-promsd)
STALE_DAYS="${DMF_TRIAGE_DAYS:-7}"

TOTAL_FINDINGS=0

# ── Helpers ────────────────────────────────────────────────────────────────
finding() {
    echo "  ✗ $*"
    TOTAL_FINDINGS=$((TOTAL_FINDINGS + 1))
}

skipped() {
    echo "  · SKIPPED ($*)"
}

gh_json() {
    # Wrapper: run gh api graphql, return stdout; caller checks exit code.
    gh api graphql --input - <<<"$1" 2>/dev/null
}

# ── Check 1: Umbrella issue labeling / milestone ──────────────────────────
check_umbrella_labels() {
    echo "── check 1: umbrella issue labeling / milestone"

    local payload
    payload='{"query":"query($owner:String!,$repo:String!){repository(owner:$owner,name:$repo){issues(states:[OPEN],first:100){nodes{number,title,milestone{title},labels(first:20){nodes{name}}}}}}","variables":{"owner":"'"$ORG"'","repo":"'"${UMBRELLA_REPO#*/}"'"}}'

    local resp
    resp="$(gh_json "$payload")" || { skipped "gh api failed — token may lack repo scope"; return; }

    local count
    count="$(echo "$resp" | jq -r '.data.repository.issues.nodes | length' 2>/dev/null)" || { skipped "jq parse failed"; return; }

    for i in $(seq 0 $((count - 1))); do
        local num title milestone
        num="$(echo "$resp" | jq -r ".data.repository.issues.nodes[$i].number")"
        title="$(echo "$resp" | jq -r ".data.repository.issues.nodes[$i].title")"
        milestone="$(echo "$resp" | jq -r ".data.repository.issues.nodes[$i].milestone.title // empty")"

        # hygiene-exempt escape hatch
        local exempt
        exempt="$(echo "$resp" | jq -r "[.data.repository.issues.nodes[$i].labels.nodes[].name] | map(select(.==\"hygiene-exempt\")) | length")"
        [ "$exempt" -gt 0 ] && continue

        local labels
        labels="$(echo "$resp" | jq -r "[.data.repository.issues.nodes[$i].labels.nodes[].name] | .[]")"

        if [ -z "$milestone" ]; then
            finding "#$num \"$title\": missing milestone"
        fi

        local has_component=0 has_workstream=0
        while IFS= read -r lbl; do
            [[ "$lbl" == component:* ]] && has_component=1
            [[ "$lbl" == workstream:* ]] && has_workstream=1
        done <<<"$labels"

        [ "$has_component" -eq 0 ] && finding "#$num \"$title\": missing component:* label"
        [ "$has_workstream" -eq 0 ] && finding "#$num \"$title\": missing workstream:* label"
    done
}

# ── Check 2: Board membership + fields ────────────────────────────────────
check_board_membership() {
    echo "── check 2: board membership + fields"

    # Fetch board items with their content issue number, state, and the
    # Component / Workstream field values. Use aliased fields to avoid
    # GraphQL key collisions (fieldValueByName returns only the last match
    # when called twice without aliases).
    local payload
    payload='{"query":"query($pid:ID!){node(id:$pid){...on ProjectV2{items(first:100){nodes{comp:fieldValueByName(name:\"Component\"){...on ProjectV2ItemFieldSingleSelectValue{name}}ws:fieldValueByName(name:\"Workstream\"){...on ProjectV2ItemFieldSingleSelectValue{name}}content{...on Issue{number,state}}}}}}}","variables":{"pid":"'"$PROJECT_ID"'"}}'

    local resp
    resp="$(gh_json "$payload")" || { skipped "gh api failed — token may lack org-project scope"; return; }

    local count
    count="$(echo "$resp" | jq -r '.data.node.items.nodes | length' 2>/dev/null)" || { skipped "jq parse failed"; return; }

    # Build the set of issue numbers present on the board. Space-separated
    # string, not an associative array — operator machines may run bash 3.2
    # (macOS), where `local -A` is a runtime error.
    local board_issue_numbers=" "
    for i in $(seq 0 $((count - 1))); do
        local issue_num issue_state comp ws
        issue_num="$(echo "$resp" | jq -r ".data.node.items.nodes[$i].content.number // empty")"
        issue_state="$(echo "$resp" | jq -r ".data.node.items.nodes[$i].content.state // empty")"
        comp="$(echo "$resp" | jq -r ".data.node.items.nodes[$i].comp.name // empty")"
        ws="$(echo "$resp" | jq -r ".data.node.items.nodes[$i].ws.name // empty")"

        [ -n "$issue_num" ] && board_issue_numbers="${board_issue_numbers}${issue_num} "

        # Check empty fields on OPEN content issues
        if [ -n "$issue_num" ] && [ "$issue_state" = "OPEN" ]; then
            [ -z "$comp" ] && finding "board item issue #$issue_num: empty Component field"
            [ -z "$ws" ] && finding "board item issue #$issue_num: empty Workstream field"
        fi
    done

    # Compare against check 1's open umbrella issue list — any OPEN umbrella
    # issue NOT on the board is a finding. Reuse the same GraphQL query from
    # check 1 but only collect numbers.
    local umb_payload
    umb_payload='{"query":"query($owner:String!,$repo:String!){repository(owner:$owner,name:$repo){issues(states:[OPEN],first:100){nodes{number,labels(first:20){nodes{name}}}}}}","variables":{"owner":"'"$ORG"'","repo":"'"${UMBRELLA_REPO#*/}"'"}}'

    local umb_resp
    umb_resp="$(gh_json "$umb_payload")" || { skipped "gh api failed for umbrella issue list"; return; }

    local umb_count
    umb_count="$(echo "$umb_resp" | jq -r '.data.repository.issues.nodes | length' 2>/dev/null)" || return

    for i in $(seq 0 $((umb_count - 1))); do
        local num exempt
        num="$(echo "$umb_resp" | jq -r ".data.repository.issues.nodes[$i].number")"
        exempt="$(echo "$umb_resp" | jq -r "[.data.repository.issues.nodes[$i].labels.nodes[].name] | map(select(.==\"hygiene-exempt\")) | length")"
        [ "$exempt" -gt 0 ] && continue
        case "$board_issue_numbers" in
            *" $num "*) ;;
            *) finding "umbrella issue #$num: not on org Project board" ;;
        esac
    done
}

# ── Check 3: Active plans with closed tracking issues ─────────────────────
check_active_plans() {
    echo "── check 3: active plans with closed tracking issues"

    local plan_dir="$UMBRELLA_DIR/docs/plans"
    [ -d "$plan_dir" ] || { skipped "docs/plans directory not found"; return; }

    local found_any=0
    for plan_file in "$plan_dir"/*.md; do
        [ -f "$plan_file" ] || continue
        # Extract frontmatter block
        # Same regex parsing as check-docs.sh — stdlib only (PyYAML is not a
        # given on operator machines).
        local fm status tracking
        fm="$(sed -n '/^---$/,/^---$/p' "$plan_file" 2>/dev/null)" || continue
        status="$(echo "$fm" | sed -n 's/^status:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)"
        [ "$status" != "active" ] && continue

        tracking="$(echo "$fm" | sed -n 's/^tracking_issue:[[:space:]]*//p' | head -1 | tr -d '"')"
        [ -z "$tracking" ] && continue
        found_any=1

        # Parse issue number from URL like https://github.com/dmfdeploy/dmfdeploy/issues/32
        local issue_repo issue_num
        issue_repo="$(echo "$tracking" | sed -n 's|https://github\.com/\([^/]*\)/\([^/]*\)/issues/.*|\1/\2|p')"
        issue_num="$(echo "$tracking" | sed -n 's|.*/issues/\([0-9]*\).*|\1|p')"
        { [ -z "$issue_repo" ] || [ -z "$issue_num" ]; } && continue

        local state_resp state
        state_resp="$(gh api repos/"$issue_repo"/issues/"$issue_num" 2>/dev/null)" || { skipped "gh api failed for $tracking"; continue; }
        state="$(echo "$state_resp" | jq -r '.state // empty')"
        [ "$state" = "closed" ] && finding "$(basename "$plan_file"): status=active but tracking issue #$issue_num is CLOSED"
    done
    [ "$found_any" -eq 0 ] && echo "  · no active plans with tracking_issue found"
}

# ── Check 4: Untriaged component-repo issues ──────────────────────────────
check_untriaged_component_issues() {
    echo "── check 4: untriaged component-repo issues"

    # Compute cutoff date
    local cutoff
    cutoff="$(date -u -v-"${STALE_DAYS}"d +%Y-%m-%dT00:00:00Z 2>/dev/null)" || \
    cutoff="$(date -u -d "${STALE_DAYS} days ago" +%Y-%m-%dT00:00:00Z 2>/dev/null)" || \
    { skipped "cannot compute cutoff date"; return; }

    local found_any=0
    for repo in "${COMPONENT_REPOS[@]}"; do
        local payload
        # Cutoff is compared client-side (the issues connection has no
        # created-before filter) — do NOT declare it as a GraphQL variable,
        # an unused variable is a GraphQL validation error.
        payload='{"query":"query($owner:String!,$repo:String!){repository(owner:$owner,name:$repo){issues(states:[OPEN],first:100,orderBy:{field:CREATED_AT,direction:DESC}){nodes{number,title,createdAt,labels(first:20){nodes{name}}}}}}","variables":{"owner":"'"$ORG"'","repo":"'"$repo"'"}}'

        local resp
        resp="$(gh_json "$payload")" || { skipped "gh api failed for $repo"; continue; }

        local count
        count="$(echo "$resp" | jq -r '.data.repository.issues.nodes | length' 2>/dev/null)" || continue
        [ "$count" -eq 0 ] && continue

        for i in $(seq 0 $((count - 1))); do
            local num title created_at
            num="$(echo "$resp" | jq -r ".data.repository.issues.nodes[$i].number")"
            title="$(echo "$resp" | jq -r ".data.repository.issues.nodes[$i].title")"
            created_at="$(echo "$resp" | jq -r ".data.repository.issues.nodes[$i].createdAt")"

            # hygiene-exempt escape
            local exempt
            exempt="$(echo "$resp" | jq -r "[.data.repository.issues.nodes[$i].labels.nodes[].name] | map(select(.==\"hygiene-exempt\")) | length")"
            [ "$exempt" -gt 0 ] && continue

            # Issues older than cutoff are untriaged
            if [[ "$created_at" < "$cutoff" ]]; then
                finding "$repo #$num \"$title\": created $created_at (>${STALE_DAYS}d ago, untriaged)"
                found_any=1
            fi
        done
    done
    [ "$found_any" -eq 0 ] && echo "  · no untriaged component-repo issues"
}

# ── Main ──────────────────────────────────────────────────────────────────
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    sed -n '/^# check-backlog-hygiene/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

check_umbrella_labels
check_board_membership
check_active_plans
check_untriaged_component_issues

echo ""
if [ "$TOTAL_FINDINGS" -eq 0 ]; then
    echo "backlog-hygiene: OK (0 findings)"
    exit 0
else
    echo "backlog-hygiene: $TOTAL_FINDINGS finding(s)"
    exit 1
fi
