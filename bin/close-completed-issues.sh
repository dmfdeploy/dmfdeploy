#!/usr/bin/env bash
# close-completed-issues.sh — auto-close umbrella tracking issues whose
# completing PR has merged.
#
# GitHub records, on every issue, which PRs reference it with closing
# keywords: Issue.closedByPullRequestsReferences — the same parsed result
# its native auto-close consumes, including cross-repo references. Native
# auto-close still does not fire for us (cross-repo closes never fire, and
# bot-actor rebase auto-merge suppresses even same-repo keyword closes), so
# this reconciler closes exactly what GitHub itself parsed as a closing
# reference — i.e. what native auto-close *would* have closed had it fired.
# No PR-body text is parsed here; GitHub is the parser.
#
# Usage:
#   bin/close-completed-issues.sh             # dry-run (default — safe)
#   bin/close-completed-issues.sh --dry-run   # dry-run (explicit)
#   bin/close-completed-issues.sh --apply     # actually close issues
#   bin/close-completed-issues.sh --self-test # run candidate-filter unit tests
#   bin/close-completed-issues.sh --help      # print this header
#
# Exit: 0 = success (nothing to do, dry-run, or self-test pass), 1 = error.
#
# Documented semantics (deliberate, reviewed):
#   - A closing reference added by EDITING an already-merged PR's body is
#     honored: org members recording completion after the fact is intent,
#     not noise. Guards still bound it — the PR must be merged into its
#     repo's default branch and the issue must predate the merge.
#   - Any org-owned repo can complete umbrella work (no per-repo allowlist;
#     future repos are covered automatically). Foreign owners never qualify.
#   - The candidate set is computed once per run; a reopen landing in the
#     seconds between computation and close is caught by the next run's
#     guard, and closes are idempotent.
#
# Closing-reference cap (documented justification): only the first 100 closing-PR
# references per issue are examined (closedByPullRequestsReferences first:100 —
# the GraphQL connection maximum). A single umbrella issue accruing more than 100
# closing-PR references is implausible; full per-issue nested pagination (an
# inner cursor loop) would add real complexity for no practical gain, and this
# reconciler is a backstop to GitHub's native close mechanisms, not the sole
# closer. If an issue ever approaches the cap, revisit with true pagination.

set -euo pipefail

# ── Constants ──────────────────────────────────────────────────────────────
ORG="dmfdeploy"
UMBRELLA_NAME="dmfdeploy"
UMBRELLA_REPO="${ORG}/${UMBRELLA_NAME}"

MODE="dry-run"

# One query answers everything: every OPEN umbrella issue, the PRs GitHub
# linked to it as closing references (includeClosedPrs:true is required —
# merged PRs are closed PRs and are excluded by default), and the newest
# reopened event for the reopen guard. $endCursor enables gh --paginate.
ISSUES_QUERY='query($owner: String!, $name: String!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    issues(states: [OPEN], first: 100, after: $endCursor) {
      nodes {
        number
        createdAt
        closedByPullRequestsReferences(first: 100, includeClosedPrs: true) {
          nodes {
            url state mergedAt baseRefName
            repository { nameWithOwner }
            baseRepository { nameWithOwner defaultBranchRef { name } }
          }
        }
        timelineItems(itemTypes: [REOPENED_EVENT], last: 1) {
          nodes { ... on ReopenedEvent { createdAt } }
        }
      }
      pageInfo { hasNextPage endCursor }
    }
  }
}'

# Candidate rule, as a pure jq filter over an array of issue nodes (stdin),
# unit-tested by --self-test. Emits one TSV row per issue that has at least
# one qualifying closing PR:  number<TAB>decision<TAB>pr_url<TAB>merged_at<TAB>reopened_at
#   decision = "close"          newest qualifying PR merged after any reopen
#   decision = "skip-reopened"  a human reopened the issue after that merge
# A closing PR qualifies iff it mirrors what native auto-close requires:
#   - MERGED with a mergedAt timestamp,
#   - in an org-owned repo (defense in depth — GitHub only links cross-repo
#     closing refs from writers, but a foreign-repo link must never close),
#   - merged into its own repository'\''s DEFAULT branch (native keyword close
#     is default-branch gated; null/missing branch metadata fails closed),
#   - and the issue existed before the merge (a reference to a not-yet-born
#     issue can only come from a post-merge edit; missing createdAt fails
#     closed via the "9999" sentinel).
# ISO-8601 UTC strings compare correctly as strings; an empty reopened_at
# sorts before any merge.
CANDIDATE_FILTER='
  .[]
  | .number as $n
  | (.createdAt // "9999") as $created
  | ([.timelineItems.nodes[]?.createdAt] | max // "") as $reopened
  | ([ .closedByPullRequestsReferences.nodes[]?
       | select(.state == "MERGED" and .mergedAt != null)
       | select((.repository.nameWithOwner | split("/")[0]) == $org)
       | select(.baseRepository != null and .baseRepository.defaultBranchRef != null)
       | select(.baseRepository.nameWithOwner == .repository.nameWithOwner)
       | select(.baseRefName == .baseRepository.defaultBranchRef.name)
       | select($created <= .mergedAt) ]
     | sort_by(.mergedAt) | last) as $pr
  | select($pr != null)
  | (if $pr.mergedAt > $reopened then "close" else "skip-reopened" end) as $decision
  | [($n | tostring), $decision, $pr.url, $pr.mergedAt, $reopened]
  | @tsv'

# ── Candidate computation ──────────────────────────────────────────────────
select_candidates() {
    jq -r --arg org "$ORG" "$CANDIDATE_FILTER"
}

# find_candidates
#   Prints the TSV rows described above for all open umbrella issues.
#   Called once; --dry-run and --apply act on the same set, so the modes
#   cannot drift. Under set -euo pipefail any API failure aborts the whole
#   run before a single mutation — never close on unknown state.
find_candidates() {
    local pages
    pages="$(gh api graphql --paginate \
        -f owner="$ORG" -f name="$UMBRELLA_NAME" \
        -f query="$ISSUES_QUERY")"
    # Guard the one gap set -e cannot see: a zero-exit but EMPTY response
    # would flatten to "no candidates" instead of aborting. Unknown ≠ empty.
    if [ -z "$pages" ]; then
        echo "error: empty response from gh api graphql — aborting (unknown state)" >&2
        return 1
    fi
    printf '%s' "$pages" \
        | jq -s '[.[].data.repository.issues.nodes[]]' \
        | select_candidates
}

# ── Self-test ─────────────────────────────────────────────────────────────
run_self_test() {
    local pass=0 fail=0

    # assert LABEL FIXTURE_JSON EXPECTED_TSV
    #   FIXTURE_JSON: an array of issue nodes as returned by ISSUES_QUERY.
    #   EXPECTED_TSV: full expected output (use $'\t'; empty for no rows).
    assert() {
        local label="$1" fixture="$2" expected="$3"
        local actual
        actual="$(printf '%s' "$fixture" | select_candidates)"
        if [ "$actual" = "$expected" ]; then
            echo "  PASS  $label"
            pass=$((pass + 1))
        else
            echo "  FAIL  $label: expected '${expected}', got '${actual}'"
            fail=$((fail + 1))
        fi
    }

    # Fixture builders keep the cases readable.
    # pr URL STATE MERGED_AT REPO [BASE_REF] [BASE_REPO] [DEFAULT_BRANCH]
    #   One closing-PR reference node; defaults model the normal case (merged
    #   into the same repo's default branch "main"). Pass "null" where the
    #   API would return null.
    pr() {
        local url="$1" state="$2" merged="$3" repo="$4"
        local base_ref="${5:-main}" base_repo="${6:-$repo}" default="${7:-main}"
        local merged_json="\"$merged\"" default_json="{\"name\":\"$default\"}"
        [ "$merged" = "null" ] && merged_json="null"
        [ "$default" = "null" ] && default_json="null"
        printf '{"url":"%s","state":"%s","mergedAt":%s,"baseRefName":"%s","repository":{"nameWithOwner":"%s"},"baseRepository":{"nameWithOwner":"%s","defaultBranchRef":%s}}' \
            "$url" "$state" "$merged_json" "$base_ref" "$repo" "$base_repo" "$default_json"
    }

    # issue NUMBER CREATED_AT REOPENED_AT [PR_JSON ...]
    issue() {
        local num="$1" created="$2" reopened="$3"
        shift 3
        local prs="" sep="" p
        for p in "$@"; do prs="${prs}${sep}${p}"; sep=","; done
        local tl='{"nodes":[]}'
        [ -n "$reopened" ] && tl="{\"nodes\":[{\"createdAt\":\"$reopened\"}]}"
        printf '{"number":%s,"createdAt":"%s","closedByPullRequestsReferences":{"nodes":[%s]},"timelineItems":%s}' \
            "$num" "$created" "$prs" "$tl"
    }

    echo "── candidate-filter self-test"

    local born="2026-05-01T00:00:00Z"   # issue creation predating all merges

    # 1. merged closing PR, never reopened → close
    assert "merged ref, no reopen → close" \
        "[$(issue 20 "$born" "" "$(pr u://env/4 MERGED 2026-06-12T09:09:40Z dmfdeploy/dmf-env)")]" \
        $'20\tclose\tu://env/4\t2026-06-12T09:09:40Z\t'

    # 2. closing PR still OPEN (the live #47/#51 case) → no row
    assert "open PR ref → not a candidate" \
        "[$(issue 47 "$born" "" "$(pr u://um/51 OPEN null dmfdeploy/dmfdeploy)")]" \
        ""

    # 3. closing PR CLOSED without merging → no row
    assert "closed-unmerged PR ref → not a candidate" \
        "[$(issue 7 "$born" "" "$(pr u://cms/9 CLOSED null dmfdeploy/dmf-cms)")]" \
        ""

    # 4. reopened AFTER the merge → skip-reopened (human intent wins)
    assert "reopened after merge → skip" \
        "[$(issue 8 "$born" 2026-06-02T10:00:00Z "$(pr u://infra/2 MERGED 2026-06-01T10:00:00Z dmfdeploy/dmf-infra)")]" \
        $'8\tskip-reopened\tu://infra/2\t2026-06-01T10:00:00Z\t2026-06-02T10:00:00Z'

    # 5. reopened BEFORE the merge → close (merge supersedes the reopen)
    assert "reopened before merge → close" \
        "[$(issue 9 "$born" 2026-06-02T10:00:00Z "$(pr u://infra/3 MERGED 2026-06-03T10:00:00Z dmfdeploy/dmf-infra)")]" \
        $'9\tclose\tu://infra/3\t2026-06-03T10:00:00Z\t2026-06-02T10:00:00Z'

    # 6. merged closing PR in a FOREIGN-owner repo → no row (org guard)
    assert "foreign-owner repo ref → not a candidate" \
        "[$(issue 10 "$born" "" "$(pr u://evil/1 MERGED 2026-06-01T10:00:00Z evil/dmfdeploy)")]" \
        ""

    # 7. two merged refs straddling a reopen → close, citing the NEWEST PR
    #    (per-PR comparison: the newer merge post-dates the reopen)
    assert "reopen between two merges → close via newest PR" \
        "[$(issue 11 "$born" 2026-06-03T10:00:00Z \
            "$(pr u://env/5 MERGED 2026-06-01T10:00:00Z dmfdeploy/dmf-env)" \
            "$(pr u://env/6 MERGED 2026-06-05T10:00:00Z dmfdeploy/dmf-env)")]" \
        $'11\tclose\tu://env/6\t2026-06-05T10:00:00Z\t2026-06-03T10:00:00Z'

    # 8. issue with no closing refs at all → no row
    assert "no refs → ignored" \
        "[$(issue 12 "$born" "")]" \
        ""

    # 9. mixed: merged + open refs, no reopen → close citing the merged one
    assert "merged + open refs → close via merged" \
        "[$(issue 13 "$born" "" \
            "$(pr u://um/60 OPEN null dmfdeploy/dmfdeploy)" \
            "$(pr u://cms/7 MERGED 2026-06-04T10:00:00Z dmfdeploy/dmf-cms)")]" \
        $'13\tclose\tu://cms/7\t2026-06-04T10:00:00Z\t'

    # 10. multiple issues in one page → independent rows
    assert "multiple issues → independent decisions" \
        "[$(issue 14 "$born" "" "$(pr u://env/8 MERGED 2026-06-01T10:00:00Z dmfdeploy/dmf-env)"),$(issue 15 "$born" "")]" \
        $'14\tclose\tu://env/8\t2026-06-01T10:00:00Z\t'

    # 11. merged into a NON-default branch → no row (native close is
    #     default-branch gated)
    assert "merged into non-default branch → not a candidate" \
        "[$(issue 16 "$born" "" "$(pr u://env/9 MERGED 2026-06-01T10:00:00Z dmfdeploy/dmf-env release-v0.1)")]" \
        ""

    # 12. defaultBranchRef null → no row (unknown branch metadata fails closed)
    assert "null default-branch metadata → fail closed" \
        "[$(issue 17 "$born" "" "$(pr u://env/10 MERGED 2026-06-01T10:00:00Z dmfdeploy/dmf-env main dmfdeploy/dmf-env null)")]" \
        ""

    # 13. base repository differs from the PR's repository → no row
    assert "cross-repo base repository → not a candidate" \
        "[$(issue 18 "$born" "" "$(pr u://env/11 MERGED 2026-06-01T10:00:00Z dmfdeploy/dmf-env main dmfdeploy/dmf-cms)")]" \
        ""

    # 14. issue created AFTER the PR merged → no row (the reference can only
    #     come from a post-merge edit naming a not-yet-born issue)
    assert "issue born after merge → not a candidate" \
        "[$(issue 19 2026-06-10T00:00:00Z "" "$(pr u://env/12 MERGED 2026-06-01T10:00:00Z dmfdeploy/dmf-env)")]" \
        ""

    # 15. issue createdAt missing → no row (fail closed via "9999" sentinel)
    assert "missing issue createdAt → fail closed" \
        '[{"number":21,"closedByPullRequestsReferences":{"nodes":['"$(pr u://env/13 MERGED 2026-06-01T10:00:00Z dmfdeploy/dmf-env)"']},"timelineItems":{"nodes":[]}}]' \
        ""

    echo ""
    echo "self-test: ${pass} passed, ${fail} failed"
    return "$fail"
}

# ── Argument parsing ──────────────────────────────────────────────────────
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    sed -n '/^# close-completed-issues/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
fi

if [ "${1:-}" = "--self-test" ]; then
    run_self_test
    exit $?
fi

if [ "${1:-}" = "--apply" ]; then
    MODE="apply"
elif [ "${1:-}" = "--dry-run" ]; then
    MODE="dry-run"
elif [ -n "${1:-}" ]; then
    echo "Unknown argument: $1" >&2
    echo "Usage: $0 [--apply|--dry-run|--self-test|--help]" >&2
    exit 1
fi

# ── Core logic ────────────────────────────────────────────────────────────
echo "close-completed-issues: mode=$MODE"

# Single candidate computation — dry-run and apply use the same set.
candidates="$(find_candidates)"

total=0
skipped_reopen=0
if [ -n "$candidates" ]; then
    while IFS=$'\t' read -r issue_num decision pr_url pr_merged_at reopened_at; do
        [ -z "$issue_num" ] && continue

        if [ "$decision" = "skip-reopened" ]; then
            echo "  · SKIP umbrella #$issue_num (reopened at ${reopened_at}, after PR merged at ${pr_merged_at})"
            skipped_reopen=$((skipped_reopen + 1))
            continue
        fi

        if [ "$MODE" = "apply" ]; then
            # The close targets the umbrella repo explicitly (-R).
            gh issue close "$issue_num" \
                -R "$UMBRELLA_REPO" \
                --reason completed \
                --comment "Closed by merged ${pr_url} (auto-reconciled — cross-repo/rebase auto-close gap)."
            echo "  ✓ Closed umbrella #$issue_num (PR ${pr_url})"
        else
            echo "  · Would close umbrella #$issue_num (PR ${pr_url})"
        fi
        total=$((total + 1))
    done <<<"$candidates"
fi

echo ""
if [ "$MODE" = "dry-run" ]; then
    echo "close-completed-issues: dry-run — ${total} issue(s) would be closed"
else
    echo "close-completed-issues: ${total} issue(s) closed"
fi
if [ "$skipped_reopen" -gt 0 ]; then
    echo "close-completed-issues: ${skipped_reopen} issue(s) skipped (reopened after PR merged)"
fi
