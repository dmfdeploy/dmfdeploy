#!/usr/bin/env bash
# check-backlog-hygiene.sh — detect GitHub backlog drift across the DMF org.
#
# Read-only detector: every OPEN issue in the umbrella repo must carry a
# milestone or the platform-debt label (unscheduled work, see
# docs/WORKING-MODEL.md §2), at least one component:* label, and at least one
# workstream:* label. An issue that entered its milestone on or after
# ACCEPTANCE_START must have a "## Acceptance" heading with a list item.
# Issues labelled hygiene-exempt are skipped. The script
# also flags active AND draft plan docs whose tracking issue is CLOSED, and
# surfaces untriaged component-repo issues older than the staleness
# threshold. (umbrella issue #32)
#
# Board membership is deliberately NOT checked: org Project #1 is a human-
# curated surface for issues of significance, not an automation target — see
# docs/WORKING-MODEL.md §3 (umbrella issue #52).
#
# Usage:
#   bin/check-backlog-hygiene.sh          # full run (umbrella + component repos)
#   bin/check-backlog-hygiene.sh --help   # print this header
#   bin/check-backlog-hygiene.sh --self-test  # offline check of the freshness rules
#   bin/check-backlog-hygiene.sh --warn   # print findings but always exit 0
#
# Exit: 0 = no findings, 1 = one or more findings detected, or a check could
# not read a required input (a failed gh call, no docs/plans). Each such
# skip prints "SKIPPED", and the last line is then
# "backlog-hygiene: INCOMPLETE (N check(s) could not run)", never the OK line.
# With --warn the same lines print ("(warn mode, exit 0)" is appended to the
# findings line), but the exit is 0.
# Env overrides:
#   DMF_TRIAGE_DAYS  — staleness threshold for untriaged component issues (default 7)
#   DMF_WIP_LIMIT    — max concurrent active plans before a WIP finding (default 3)
#   DMF_ISSUE_LIMIT  — most open umbrella issues read (default 2000); reaching
#                      it is a finding, because issues past it go unchecked

set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

# ── Constants ──────────────────────────────────────────────────────────────
ORG="dmfdeploy"
UMBRELLA_REPO="dmfdeploy/dmfdeploy"
COMPONENT_REPOS=(dmf-cms dmf-runbooks dmf-central dmf-infra dmf-env dmf-media dmf-init dmf-promsd)
STALE_DAYS="${DMF_TRIAGE_DAYS:-7}"
ISSUE_LIMIT="${DMF_ISSUE_LIMIT:-2000}"

TOTAL_FINDINGS=0
# Every skip is a required input that could not be read, so the run is
# incomplete. No check has an optional input that may be skipped.
SKIPPED_COUNT=0
WARN=0
# Newline-separated keys that checks 1 and 2 already reported, so check 5's
# overlapping rules (3 and 1) skip them and each finding prints once.
REPORTED_ISSUES=""
REPORTED_PLANS=""
# Issues check 1 reported as unscheduled, so rule 4 skips them.
REPORTED_UNSCHEDULED=""
# Open umbrella issues as {"issues":[...]}, read once by check 1 and reused
# by check 5. Empty when the read failed.
UMBRELLA_ISSUES=""

# ── Helpers ────────────────────────────────────────────────────────────────
finding() {
    echo "  ✗ $*"
    TOTAL_FINDINGS=$((TOTAL_FINDINGS + 1))
}

skipped() {
    echo "  · SKIPPED ($*)"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
}

gh_json() {
    # Wrapper: run gh api graphql, return stdout; caller checks exit code.
    gh api graphql --input - <<<"$1" 2>/dev/null
}

# ── Check 1: Umbrella issue labeling / milestone ──────────────────────────
# Read every open umbrella issue as
# {"issues":[{number,title,milestone,labels,body,milestoned_at}]}.
# gh issue list pages through the API up to --limit. Exit 1 if gh fails, 2 if
# the result reaches the limit (issues past it would go unchecked), 3 if the
# milestone dates could not be read (the issues still print, with
# milestoned_at null, so check 1 can run).
fetch_umbrella_issues() {
    local raw count issues dates
    raw="$(gh issue list --repo "$UMBRELLA_REPO" --state open --limit "$ISSUE_LIMIT" \
        --json number,title,milestone,labels,body 2>/dev/null)" || return 1
    count="$(jq -r 'length' <<<"$raw" 2>/dev/null)" || return 1
    [ "$count" -ge "$ISSUE_LIMIT" ] && return 2
    issues="$(jq -c '{issues: [.[] | {number, title, milestone: (.milestone.title // null),
        labels: [.labels[].name], body: (.body // "")}]}' <<<"$raw")"
    if dates="$(fetch_milestoned_at "$issues")"; then
        jq -c --argjson d "$dates" \
            '.issues |= map(. + {milestoned_at: ($d[.number | tostring] // null)})' <<<"$issues"
    else
        jq -c '.issues |= map(. + {milestoned_at: null})' <<<"$issues"
        return 3
    fi
}

# Print {"<number>":"<createdAt>"}, the latest MilestonedEvent of each
# milestoned issue in a {"issues":[...]} payload. One GraphQL query per batch
# of 50 issues, one alias per issue, instead of one REST call per issue.
# Exit 1 if any query fails.
fetch_milestoned_at() {
    local batch n fields query resp dates="{}"
    while IFS= read -r batch; do
        [ -n "$batch" ] || continue
        fields=""
        for n in $(printf '%s' "$batch"); do
            fields+="i$n:issue(number:$n){timelineItems(itemTypes:[MILESTONED_EVENT],last:1){nodes{... on MilestonedEvent{createdAt}}}} "
        done
        query="query{repository(owner:\"$ORG\",name:\"${UMBRELLA_REPO#*/}\"){$fields}}"
        resp="$(gh_json "$(jq -nc --arg q "$query" '{query:$q}')")" || return 1
        dates="$(jq -c --argjson acc "$dates" '.data.repository
            | if type == "object" then . else error("no repository") end
            | $acc + (to_entries | map({key: (.key | ltrimstr("i")),
                value: .value.timelineItems.nodes[0].createdAt}) | from_entries)' \
            <<<"$resp" 2>/dev/null)" || return 1
    done < <(jq -r '.issues[] | select(.milestone != null) | .number' <<<"$1" | xargs -n 50)
    printf '%s\n' "$dates"
}

# Check 1's findings for a {"issues":[...]} payload, one line per finding.
# An issue without a milestone is a finding only if it lacks platform-debt.
check1_lines() {
    jq -r '.issues[] | select((.labels | index("hygiene-exempt")) == null)
        | (if .milestone == null and (.labels | index("platform-debt")) == null
             then "#\(.number) \"\(.title)\": missing milestone" else empty end),
          (if (.labels | map(select(startswith("component:"))) | length) == 0
             then "#\(.number) \"\(.title)\": missing component:* label" else empty end),
          (if (.labels | map(select(startswith("workstream:"))) | length) == 0
             then "#\(.number) \"\(.title)\": missing workstream:* label" else empty end)'
}

check_umbrella_labels() {
    echo "── check 1: umbrella issue labeling / milestone"

    local rc=0
    UMBRELLA_ISSUES="$(fetch_umbrella_issues)" || rc=$?
    if [ "$rc" -eq 3 ]; then
        skipped "milestone events not read — Acceptance rule not run"
    elif [ "$rc" -eq 2 ]; then
        UMBRELLA_ISSUES=""
        finding "open umbrella issues reach DMF_ISSUE_LIMIT=$ISSUE_LIMIT; raise it, issues past the limit are not checked"
        return
    elif [ "$rc" -ne 0 ]; then
        UMBRELLA_ISSUES=""
        skipped "gh issue list failed — token may lack repo scope"
        return
    fi

    local line
    while IFS= read -r line; do
        [ -n "$line" ] && finding "$line"
    done < <(check1_lines <<<"$UMBRELLA_ISSUES")

    REPORTED_ISSUES="$(jq -r '.issues[] | select((.labels | index("hygiene-exempt")) == null)
        | select(((.labels | map(select(startswith("component:"))) | length) == 0)
              or ((.labels | map(select(startswith("workstream:"))) | length) == 0))
        | .number' <<<"$UMBRELLA_ISSUES")"$'\n'
    REPORTED_UNSCHEDULED="$(jq -r '.issues[] | select((.labels | index("hygiene-exempt")) == null)
        | select(.milestone == null and (.labels | index("platform-debt")) == null)
        | .number' <<<"$UMBRELLA_ISSUES")"$'\n'
}

# ── Check 2: Active plans with closed tracking issues ─────────────────────
check_active_plans() {
    echo "── check 2: active/draft plans with closed tracking issues"

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
        # `draft` is checked alongside `active`, and the draft case is the more
        # insidious one: a parked plan reads as deliberate, so a closed tracker
        # under it looks like intent rather than rot. Found by hand 2026-08-28 —
        # a draft plan tracked a CLOSED defect sweep it never described, and this
        # check skipped it. Terminal statuses (executed/superseded/historical) are
        # SUPPOSED to have closed trackers, so they stay excluded.
        case "$status" in
            active|draft) ;;
            *) continue ;;
        esac

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
        if [ "$state" = "closed" ]; then
            finding "$(basename "$plan_file"): status=$status but tracking issue #$issue_num is CLOSED"
            REPORTED_PLANS+="$(basename "$plan_file")"$'\n'
        fi
    done
    [ "$found_any" -eq 0 ] && echo "  · no active/draft plans with tracking_issue found"
}

# ── Check 3: Untriaged component-repo issues ──────────────────────────────
check_untriaged_component_issues() {
    echo "── check 3: untriaged component-repo issues"

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
        # A repository that resolves to null (no access) is a failed read, not
        # an empty one.
        count="$(echo "$resp" | jq -r '.data.repository.issues.nodes
            | if type == "array" then length else error("no issues") end' 2>/dev/null)" \
            || { skipped "no issue list for $repo"; continue; }
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

# ── Check 4: WIP cap (concurrent active plans) ────────────────────────────
# Focus/scope discipline: too many `status: active` plan docs in flight signals
# work spawning faster than it lands. Offline (frontmatter only, no gh calls).
check_wip_cap() {
    echo "── check 4: WIP cap (concurrent active plans)"

    local limit="${DMF_WIP_LIMIT:-3}"
    local plan_dir="$UMBRELLA_DIR/docs/plans"
    [ -d "$plan_dir" ] || { skipped "docs/plans directory not found"; return; }

    local active=0 plan_file fm status
    for plan_file in "$plan_dir"/*.md; do
        [ -f "$plan_file" ] || continue
        fm="$(sed -n '/^---$/,/^---$/p' "$plan_file" 2>/dev/null)" || continue
        status="$(echo "$fm" | sed -n 's/^status:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)"
        [ "$status" = "active" ] && active=$((active + 1))
    done

    if [ "$active" -gt "$limit" ]; then
        finding "WIP over limit: ${active} active plans (limit ${limit}) — finish or close in-flight work before opening new. Override: DMF_WIP_LIMIT."
    else
        echo "  · WIP OK (${active} active plan(s), limit ${limit})"
    fi
}

# ── Check 5: Freshness rules (rules are pure: JSON in, finding lines out) ─
# Each rule_* function reads one JSON payload on stdin and prints one line per
# finding. --self-test feeds each rule an inline payload with no network calls.
# Rules 1 and 3 overlap with checks 2 and 1: check 5 states the freshness
# contract in one place, and --self-test proves it. Checks 1 and 2 keep their
# output unchanged and record what they reported (REPORTED_*); check 5 drops
# those items before the overlapping rules run, so each finding prints once.
DRAFT_MAX_DAYS="${DMF_DRAFT_MAX_DAYS:-90}"

# Rule 1: active plan whose tracking issue is closed.
# Payload: {"plans":[{"file","status","tracker_state","tracker"}]}
# shellcheck disable=SC2329  # called indirectly through apply_rule
rule_active_plan_closed_tracker() {
    jq -r '.plans[]? | select(.status == "active" and .tracker_state == "closed")
        | "\(.file): status=active but tracking issue #\(.tracker) is CLOSED"'
}

# Rule 2: draft plan whose frontmatter date is older than the limit.
# Payload: {"today":"YYYY-MM-DD","max_days":N,"plans":[{"file","status","date"}]}
# shellcheck disable=SC2329  # called indirectly through apply_rule
rule_stale_draft_plan() {
    jq -r '(.today + "T00:00:00Z" | fromdate) as $now | .max_days as $max
        | .plans[]? | select(.status == "draft")
        | (try (.date + "T00:00:00Z" | fromdate) catch null) as $d
        | select($d != null and (($now - $d) / 86400) > $max)
        | "\(.file): draft plan dated \(.date) is older than \($max) days"'
}

# Rule 3: open issue lacking the label pair (component:* and workstream:*).
# Payload: {"issues":[{"number","title","labels":[names]}]}
# shellcheck disable=SC2329  # called indirectly through apply_rule
rule_issue_label_pair() {
    jq -r '.issues[]? | select((.labels | index("hygiene-exempt")) == null)
        | select(((.labels | map(select(startswith("component:"))) | length) == 0)
              or ((.labels | map(select(startswith("workstream:"))) | length) == 0))
        | "#\(.number) \"\(.title)\": lacks the component:* and workstream:* label pair"'
}

# Rule 4: open issue with no milestone and no platform-debt label.
# Payload: {"issues":[{"number","title","milestone":null|"name","labels":[names]}]}
# shellcheck disable=SC2329  # called indirectly through apply_rule
rule_issue_unscheduled() {
    jq -r '.issues[]? | select((.labels | index("hygiene-exempt")) == null)
        | select(.milestone == null and (.labels | index("platform-debt")) == null)
        | "#\(.number) \"\(.title)\": no milestone and no platform-debt label"'
}

# Rule 5: open issue that entered its milestone on or after ACCEPTANCE_START
# without a "## Acceptance" heading followed by a list item before the next
# heading. The start date is the day the rule was written: 54 of the 78
# milestoned issues then lacked the section, and the rule checks an issue at
# milestone entry, so issues milestoned before it are not checked (#661).
# Payload: {"start":"YYYY-MM-DD","issues":[{"number","title","milestone",
#   "milestoned_at":null|"ISO time","body","labels":[names]}]}
ACCEPTANCE_START="2026-10-23"
# shellcheck disable=SC2329  # called indirectly through apply_rule
rule_issue_acceptance() {
    jq -r '
        def has_acceptance:
            reduce ((. // "") | gsub("\r"; "") | split("\n"))[] as $line
                ({in: false, ok: false};
                 if $line | test("^#{1,6}[ \t]") then
                     .in = ($line | test("^##[ \t]+Acceptance[ \t]*$"))
                 elif .in and ($line | test("^[ \t]*([-*+]|[0-9]+[.)])[ \t]+[^ \t]")) then
                     .ok = true
                 else . end)
            | .ok;
        (.start + "T00:00:00Z") as $start
        | .issues[]? | select((.labels | index("hygiene-exempt")) == null)
        | select(.milestone != null and .milestoned_at != null and .milestoned_at >= $start)
        | select(.body | has_acceptance | not)
        | "#\(.number) \"\(.title)\": milestoned \(.milestoned_at[:10]) without a ## Acceptance list"'
}

# Drop items a check already reported. Pure: JSON in, JSON out.
# drop_reported_issues <payload> <newline-separated issue numbers>
drop_reported_issues() {
    printf '%s' "$1" | jq -c --arg r "$2" \
        '($r | split("\n") | map(select(. != "") | tonumber)) as $s
         | .issues |= map(select(.number as $n | ($s | index($n)) == null))'
}
# drop_reported_plans <payload> <newline-separated plan file names>
drop_reported_plans() {
    printf '%s' "$1" | jq -c --arg r "$2" \
        '($r | split("\n") | map(select(. != ""))) as $s
         | .plans |= map(select(.file as $f | ($s | index($f)) == null))'
}

# Run a rule on a payload and report each output line as a finding.
apply_rule() {
    local rule="$1" payload="$2" line
    while IFS= read -r line; do
        [ -n "$line" ] && finding "$line"
    done < <(printf '%s' "$payload" | "$rule")
}

check_freshness() {
    echo "── check 5: freshness (closed tracker, stale draft, label pair, scheduling, acceptance)"

    local plan_dir="$UMBRELLA_DIR/docs/plans"
    if [ -d "$plan_dir" ]; then
        local plans="[]" plan_file fm status tracking pdate issue_repo issue_num state
        for plan_file in "$plan_dir"/*.md; do
            [ -f "$plan_file" ] || continue
            fm="$(sed -n '/^---$/,/^---$/p' "$plan_file" 2>/dev/null)" || continue
            status="$(echo "$fm" | sed -n 's/^status:[[:space:]]*\([^[:space:]]*\).*/\1/p' | head -1)"
            case "$status" in active|draft) ;; *) continue ;; esac
            pdate="$(echo "$fm" | sed -n 's/^date:[[:space:]]*\([0-9-]*\).*/\1/p' | head -1)"
            tracking="$(echo "$fm" | sed -n 's/^tracking_issue:[[:space:]]*//p' | head -1 | tr -d '"')"
            state=""
            if [ "$status" = "active" ] && [ -n "$tracking" ]; then
                issue_repo="$(echo "$tracking" | sed -n 's|https://github\.com/\([^/]*\)/\([^/]*\)/issues/.*|\1/\2|p')"
                issue_num="$(echo "$tracking" | sed -n 's|.*/issues/\([0-9]*\).*|\1|p')"
                if [ -n "$issue_repo" ] && [ -n "$issue_num" ]; then
                    state="$(gh api repos/"$issue_repo"/issues/"$issue_num" 2>/dev/null | jq -r '.state // empty')"
                    [ -n "$state" ] || skipped "gh api failed for $tracking"
                fi
            fi
            plans="$(jq -c --arg f "$(basename "$plan_file")" --arg s "$status" --arg d "$pdate" \
                --arg st "$state" --arg t "${issue_num:-}" \
                '. + [{file:$f,status:$s,date:$d,tracker_state:$st,tracker:$t}]' <<<"$plans")"
            issue_num=""
        done
        local today
        today="$(date -u +%Y-%m-%d)"
        apply_rule rule_active_plan_closed_tracker \
            "$(drop_reported_plans "$(jq -c '{plans:.}' <<<"$plans")" "$REPORTED_PLANS")"
        apply_rule rule_stale_draft_plan \
            "$(jq -c --arg t "$today" --argjson m "$DRAFT_MAX_DAYS" '{today:$t,max_days:$m,plans:.}' <<<"$plans")"
    else
        skipped "docs/plans directory not found"
    fi

    # Check 1 read the open issues; without them the issue rules cannot run.
    [ -n "$UMBRELLA_ISSUES" ] || { skipped "umbrella issues not read — issue rules not run"; return; }
    # Rules 3 and 4 overlap check 1 (label pair and milestone), so issues
    # check 1 already reported are dropped and each finding prints once.
    apply_rule rule_issue_label_pair "$(drop_reported_issues "$UMBRELLA_ISSUES" "$REPORTED_ISSUES")"
    apply_rule rule_issue_unscheduled "$(drop_reported_issues "$UMBRELLA_ISSUES" "$REPORTED_UNSCHEDULED")"
    apply_rule rule_issue_acceptance \
        "$(jq -c --arg s "$ACCEPTANCE_START" '{start: $s} + .' <<<"$UMBRELLA_ISSUES")"
}

# ── Self-test: four bad payloads (one finding each), four repaired twins (0) ─
self_test() {
    local fails=0 n
    expect() {
        # expect <name> <expected-count> <rule> <payload>
        n="$(printf '%s' "$4" | "$3" | grep -c . || true)"
        if [ "$n" -eq "$2" ]; then
            echo "  ok   $1: $n finding(s)"
        else
            echo "  FAIL $1: expected $2 finding(s), got $n"
            fails=$((fails + 1))
        fi
    }

    local r1_bad r1_good r2_bad r2_good r3_bad r3_bad2 r3_good r4_bad r4_good
    r1_bad='{"plans":[{"file":"p.md","status":"active","tracker_state":"closed","tracker":"1"}]}'
    r1_good='{"plans":[{"file":"p.md","status":"active","tracker_state":"open","tracker":"1"}]}'
    r2_bad='{"today":"2026-10-20","max_days":90,"plans":[{"file":"p.md","status":"draft","date":"2026-01-01"}]}'
    r2_good='{"today":"2026-10-20","max_days":90,"plans":[{"file":"p.md","status":"draft","date":"2026-09-01"}]}'
    r3_bad='{"issues":[{"number":1,"title":"t","labels":["component:cms"]}]}'
    r3_bad2='{"issues":[{"number":1,"title":"t","labels":["workstream:ops"]}]}'
    r3_good='{"issues":[{"number":1,"title":"t","labels":["component:cms","workstream:ops"]}]}'
    r4_bad='{"issues":[{"number":2,"title":"t","milestone":null,"labels":["component:cms"]}]}'
    r4_good='{"issues":[{"number":2,"title":"t","milestone":null,"labels":["component:cms","platform-debt"]}]}'

    expect "rule1 closed tracker (bad)"   1 rule_active_plan_closed_tracker "$r1_bad"
    expect "rule1 closed tracker (good)"  0 rule_active_plan_closed_tracker "$r1_good"
    expect "rule2 stale draft (bad)"      1 rule_stale_draft_plan "$r2_bad"
    expect "rule2 stale draft (good)"     0 rule_stale_draft_plan "$r2_good"
    expect "rule3 label pair (bad)"       1 rule_issue_label_pair "$r3_bad"
    expect "rule3 label pair (no component)" 1 rule_issue_label_pair "$r3_bad2"
    expect "rule3 label pair (good)"      0 rule_issue_label_pair "$r3_good"
    expect "rule4 unscheduled (bad)"      1 rule_issue_unscheduled "$r4_bad"
    expect "rule4 unscheduled (good)"     0 rule_issue_unscheduled "$r4_good"

    # Rule 5: the bad payload entered its milestone after the start with no
    # Acceptance section, and with an Acceptance heading that has no item
    # before the next heading. The good twin has an item; an issue
    # milestoned before the start is not checked.
    local r5_bad r5_good
    r5_bad='{"start":"2026-10-23","issues":[
        {"number":6,"title":"t","milestone":"v0.2","milestoned_at":"2026-10-24T09:00:00Z","labels":[],"body":"## Outcome\n- done"},
        {"number":7,"title":"t","milestone":"v0.2","milestoned_at":"2026-10-23T00:00:00Z","labels":[],"body":"## Acceptance\nprose only\n## Notes\n- not an item of Acceptance"}]}'
    r5_good='{"start":"2026-10-23","issues":[
        {"number":6,"title":"t","milestone":"v0.2","milestoned_at":"2026-10-24T09:00:00Z","labels":[],"body":"## Outcome\r\n\r\n## Acceptance\r\n\r\n- [ ] the check passes\r\n"},
        {"number":7,"title":"t","milestone":"v0.2","milestoned_at":"2026-10-22T23:59:59Z","labels":[],"body":""}]}'
    expect "rule5 acceptance (bad)"       2 rule_issue_acceptance "$r5_bad"
    expect "rule5 acceptance (good)"      0 rule_issue_acceptance "$r5_good"

    # No duplicates: an item that matches both an existing check and a new rule
    # prints once. The existing check reports it (REPORTED_*), so the new rule
    # sees nothing; an unreported twin still reaches the rule.
    local dup_issues dup_plans
    dup_issues='{"issues":[{"number":1,"title":"t","labels":["component:cms"]},{"number":2,"title":"u","labels":[]}]}'
    dup_plans='{"plans":[{"file":"a b.md","status":"active","tracker_state":"closed","tracker":"1"},{"file":"c.md","status":"active","tracker_state":"closed","tracker":"2"}]}'
    expect "rule3 no duplicate of check 1" 0 rule_issue_label_pair \
        "$(drop_reported_issues "$dup_issues" $'1\n2\n')"
    expect "rule3 still fires if unreported" 1 rule_issue_label_pair \
        "$(drop_reported_issues "$dup_issues" $'1\n')"
    expect "rule1 no duplicate of check 2" 0 rule_active_plan_closed_tracker \
        "$(drop_reported_plans "$dup_plans" $'a b.md\nc.md\n')"
    expect "rule1 still fires if unreported" 1 rule_active_plan_closed_tracker \
        "$(drop_reported_plans "$dup_plans" $'a b.md\n')"
    expect "rule4 no duplicate of check 1" 0 rule_issue_unscheduled \
        "$(drop_reported_issues "$r4_bad" $'2\n')"

    # Check 1: platform-debt and hygiene-exempt issues need no milestone; an
    # issue with neither is still a finding.
    local c1_debt c1_exempt c1_neither
    c1_debt='{"issues":[{"number":3,"title":"t","milestone":null,"labels":["component:cms","workstream:ops","platform-debt"]}]}'
    c1_exempt='{"issues":[{"number":4,"title":"t","milestone":null,"labels":["hygiene-exempt"]}]}'
    c1_neither='{"issues":[{"number":5,"title":"t","milestone":null,"labels":["component:cms","workstream:ops"]}]}'
    expect "check1 platform-debt, no milestone" 0 check1_lines "$c1_debt"
    expect "check1 hygiene-exempt"              0 check1_lines "$c1_exempt"
    expect "check1 neither, no milestone"       1 check1_lines "$c1_neither"

    # Pagination: a fake gh serves 150 open issues and honours --limit (gh's
    # own default is 30). Only the 101st lacks a milestone, so a read capped
    # at 100 misses it. When the result reaches the limit, the read fails.
    local ptmp fetched rc
    ptmp="$(mktemp -d)"
    mkdir -p "$ptmp/bin"
    cat >"$ptmp/bin/gh" <<'GH'
#!/usr/bin/env bash
[ "$1" = api ] && { echo '{"data":{"repository":{}}}'; exit 0; }
limit=30
while [ $# -gt 0 ]; do [ "$1" = --limit ] && limit="$2"; shift; done
jq -c --argjson n "$limit" '.[:$n]' "$FAKE_ISSUES"
GH
    chmod +x "$ptmp/bin/gh"
    jq -nc '[range(1; 151) | {number: ., title: "t",
        milestone: (if . == 101 then null else {title: "v0.2"} end),
        labels: [{name: "component:cms"}, {name: "workstream:ops"}]}]' >"$ptmp/issues.json"
    fetched="$(PATH="$ptmp/bin:$PATH" FAKE_ISSUES="$ptmp/issues.json" fetch_umbrella_issues)"
    expect "check1 finds the 101st of 150 issues" 1 check1_lines "$fetched"
    if PATH="$ptmp/bin:$PATH" FAKE_ISSUES="$ptmp/issues.json" ISSUE_LIMIT=150 \
        fetch_umbrella_issues >/dev/null; then
        echo "  FAIL read reaching the limit: expected a failure"
        fails=$((fails + 1))
    else
        echo "  ok   read reaching the limit fails"
    fi

    # End to end: an issue with neither a milestone nor platform-debt is
    # reported once, by check 1, not again by rule 4.
    local e2e_n
    cat >"$ptmp/bin/gh" <<'GH'
#!/usr/bin/env bash
[ "$1" = issue ] || exit 1
echo '[{"number":7,"title":"t","milestone":null,"labels":[{"name":"component:cms"},{"name":"workstream:ops"}]}]'
GH
    e2e_n="$(PATH="$ptmp/bin:$PATH" UMBRELLA_DIR="$ptmp" "$BASH" "$0" --warn 2>/dev/null | grep -c '✗' || true)"
    if [ "$e2e_n" -eq 1 ]; then
        echo "  ok   unscheduled issue reported once end to end"
    else
        echo "  FAIL unscheduled issue end to end: expected 1 finding, got $e2e_n"
        fails=$((fails + 1))
    fi

    # Milestone dates: the read joins each issue's latest MilestonedEvent
    # from the GraphQL query, so the rule sees an issue milestoned after the
    # start. When that query fails, the read exits 3 and keeps the issues.
    cat >"$ptmp/bin/gh" <<'GH'
#!/usr/bin/env bash
case "$1" in
    issue) echo '[{"number":8,"title":"t","milestone":{"title":"v0.2"},"labels":[],"body":"no section"},
                 {"number":9,"title":"t","milestone":null,"labels":[],"body":""}]' ;;
    api) [ -n "${FAKE_GH_FAIL:-}" ] && exit 1
         echo '{"data":{"repository":{"i8":{"timelineItems":{"nodes":[{"createdAt":"2099-01-01T00:00:00Z"}]}}}}}' ;;
esac
GH
    fetched="$(PATH="$ptmp/bin:$PATH" fetch_umbrella_issues)"
    expect "rule5 reads the milestone date" 1 rule_issue_acceptance \
        "$(jq -c --arg s "$ACCEPTANCE_START" '{start: $s} + .' <<<"$fetched")"
    rc=0
    fetched="$(PATH="$ptmp/bin:$PATH" FAKE_GH_FAIL=1 fetch_umbrella_issues)" || rc=$?
    if [ "$rc" -eq 3 ] && [ "$(jq '.issues | length' <<<"$fetched")" -eq 2 ]; then
        echo "  ok   milestone date query fails: exit 3, issues kept"
    else
        echo "  FAIL milestone date query fails: expected exit 3 and 2 issues, got exit $rc"
        fails=$((fails + 1))
    fi
    rm -rf "$ptmp"

    # A check that cannot read its input makes the run INCOMPLETE, never OK.
    # The fake gh fails only the calls named in FAKE_GH_FAIL ("issue", "api");
    # the others return empty, valid results.
    local itmp out
    itmp="$(mktemp -d)"
    mkdir -p "$itmp/bin" "$itmp/repo/docs/plans" "$itmp/noplans"
    cat >"$itmp/bin/gh" <<'GH'
#!/usr/bin/env bash
case " ${FAKE_GH_FAIL:-} " in *" $1 "*) exit 1 ;; esac
case "$1" in
    issue) echo '[]' ;;
    api) if [ -n "${FAKE_GH_NULL:-}" ]; then echo '{"data":{"repository":null}}'
         else echo '{"data":{"repository":{"issues":{"nodes":[]}}}}'; fi ;;
esac
GH
    chmod +x "$itmp/bin/gh"
    printf -- '---\nstatus: executed\ndate: 2026-10-01\n---\n' >"$itmp/repo/docs/plans/done.md"
    incomplete() {
        # incomplete <name> <expected rc> <expected summary> <env...> [-- args]
        local name="$1" want_rc="$2" want="$3"; shift 3
        out="$(env PATH="$itmp/bin:$PATH" "$@" 2>&1)"; rc=$?
        if [ "$rc" -eq "$want_rc" ] && [ "$(printf '%s\n' "$out" | tail -1)" = "$want" ] \
            && { [ "$want" = "backlog-hygiene: OK (0 findings)" ] \
                 || ! printf '%s\n' "$out" | grep -q '^backlog-hygiene: OK'; }; then
            echo "  ok   $name: exit $rc, $want"
        else
            echo "  FAIL $name: expected exit $want_rc and '$want', got exit $rc and '$(printf '%s\n' "$out" | tail -1)'"
            fails=$((fails + 1))
        fi
    }
    incomplete "issue query fails (strict)" 1 "backlog-hygiene: INCOMPLETE (2 check(s) could not run)" \
        FAKE_GH_FAIL=issue UMBRELLA_DIR="$itmp/repo" "$BASH" "$0"
    incomplete "issue query fails (--warn)" 0 "backlog-hygiene: INCOMPLETE (2 check(s) could not run)" \
        FAKE_GH_FAIL=issue UMBRELLA_DIR="$itmp/repo" "$BASH" "$0" --warn
    incomplete "no docs/plans directory" 1 "backlog-hygiene: INCOMPLETE (3 check(s) could not run)" \
        UMBRELLA_DIR="$itmp/noplans" "$BASH" "$0"
    incomplete "component repo resolves to null" 1 "backlog-hygiene: INCOMPLETE (8 check(s) could not run)" \
        FAKE_GH_NULL=1 UMBRELLA_DIR="$itmp/repo" "$BASH" "$0"
    incomplete "every input read" 0 "backlog-hygiene: OK (0 findings)" \
        UMBRELLA_DIR="$itmp/repo" "$BASH" "$0"
    rm -rf "$itmp"

    # Both modes, end to end and offline: a fake gh that always fails skips
    # every network check, and a stale draft plan gives exactly one finding.
    local tmp rc_strict rc_warn
    tmp="$(mktemp -d)"
    mkdir -p "$tmp/bin" "$tmp/docs/plans"
    printf '#!/bin/sh\nexit 1\n' >"$tmp/bin/gh"
    chmod +x "$tmp/bin/gh"
    printf -- '---\nstatus: draft\ndate: 2000-01-01\n---\n' >"$tmp/docs/plans/old.md"
    PATH="$tmp/bin:$PATH" UMBRELLA_DIR="$tmp" "$BASH" "$0" >/dev/null 2>&1
    rc_strict=$?
    PATH="$tmp/bin:$PATH" UMBRELLA_DIR="$tmp" "$BASH" "$0" --warn >/dev/null 2>&1
    rc_warn=$?
    rm -rf "$tmp"
    if [ "$rc_strict" -eq 1 ]; then
        echo "  ok   findings without --warn: exit 1"
    else
        echo "  FAIL findings without --warn: expected exit 1, got $rc_strict"
        fails=$((fails + 1))
    fi
    if [ "$rc_warn" -eq 0 ]; then
        echo "  ok   findings with --warn: exit 0"
    else
        echo "  FAIL findings with --warn: expected exit 0, got $rc_warn"
        fails=$((fails + 1))
    fi

    if [ "$fails" -eq 0 ]; then
        echo "backlog-hygiene self-test: OK (31/31 expectations)"
        return 0
    fi
    echo "backlog-hygiene self-test: $fails expectation(s) failed"
    return 1
}

# ── Main ──────────────────────────────────────────────────────────────────
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    sed -n '/^# check-backlog-hygiene/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

for arg in "$@"; do
    [ "$arg" = "--warn" ] && WARN=1
done

for arg in "$@"; do
    if [ "$arg" = "--self-test" ]; then
        self_test
        exit $?
    fi
done

check_umbrella_labels
check_active_plans
check_untriaged_component_issues
check_wip_cap
check_freshness

echo ""
if [ "$TOTAL_FINDINGS" -eq 0 ] && [ "$SKIPPED_COUNT" -eq 0 ]; then
    echo "backlog-hygiene: OK (0 findings)"
    exit 0
fi
suffix=""
[ "$WARN" -eq 1 ] && suffix=" (warn mode, exit 0)"
[ "$TOTAL_FINDINGS" -gt 0 ] && echo "backlog-hygiene: $TOTAL_FINDINGS finding(s)$suffix"
# The INCOMPLETE line comes last, so a caller reading the last line sees it.
[ "$SKIPPED_COUNT" -gt 0 ] && echo "backlog-hygiene: INCOMPLETE ($SKIPPED_COUNT check(s) could not run)"
[ "$WARN" -eq 1 ] && exit 0
exit 1
