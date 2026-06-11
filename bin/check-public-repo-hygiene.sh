#!/usr/bin/env bash
# bin/check-public-repo-hygiene.sh — per-repo Tier A.2 hygiene gate.
#
# Verifies each public repo carries the artifacts required before first
# GitHub push:
#   - LICENSE                          (Apache-2.0 per ADR-0020 Mode A)
#   - NOTICE                           (third-party attributions)
#   - VERSION                          (single-line semver; ADR-0005 SSOT)
#   - .gitignore baseline              (covers operator-local + macOS metadata + secrets/)
#   - .github/CODEOWNERS               (review routing; dormant until GitHub live)
#   - .gitleaks.toml                   (per-repo secret-scanning config)
#   - .githooks/pre-commit (gitleaks)  (deployed by install-agentic-hooks.sh)
#   (.githooks/pre-push was the retired sync-to-github gate — dropped 2026-06-09)
#
# Output: per-repo / per-check status grid. Exit 0 only if ALL repos pass
# ALL checks.
#
# Usage:
#   bin/check-public-repo-hygiene.sh                   # check all publish targets (umbrella + 8 public components)
#   bin/check-public-repo-hygiene.sh --repo dmf-cms    # one repo
#   bin/check-public-repo-hygiene.sh --tree <path>     # scan one export tree directly
#   bin/check-public-repo-hygiene.sh --json            # machine-readable output
#   bin/check-public-repo-hygiene.sh --quiet           # only summary line
#
# Exit codes:
#   0 — every checked repo passed every check
#   1 — one or more checks failed (count printed on summary)
#   2 — usage error
#
# Refs:
#   docs/processes/pre-release-compliance-checklist.md  (Tier A.2 specifically)
#   docs/plans/DMF Release and Contribution Model Implementation Plan 2026-05-11.md (Phase 0)
#   docs/agentic/CONSTITUTION.md (Rule 10 VERSION SSOT, Rule 8 placeholder syntax)

set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"

# Publish targets: umbrella (`.`) + the 8 public components (dmf-env + dmf-promsd
# joined the public set per the 2026-06-09 first-public-release plan).
PUBLIC_REPOS=(. dmf-cms dmf-runbooks dmf-central dmf-infra dmf-media dmf-init dmf-env dmf-promsd)

TARGET_REPO=""
TREE_PATH=""
JSON_OUTPUT=0
QUIET=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo)  TARGET_REPO="$2"; shift 2 ;;
        --tree)  TREE_PATH="$2"; shift 2 ;;
        --json)  JSON_OUTPUT=1; shift ;;
        --quiet) QUIET=1; shift ;;
        -h|--help)
            sed -n '2,28p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

if [ -n "$TREE_PATH" ]; then
    REPOS=("$TREE_PATH")
elif [ -n "$TARGET_REPO" ]; then
    REPOS=("$TARGET_REPO")
else
    REPOS=("${PUBLIC_REPOS[@]}")
fi

# .githooks/pre-push intentionally dropped 2026-06-09: it was the retired
# sync-to-github push gate (GitHub-canonical-forward uses PRs + CI, not a sync hook).
CHECKS=(LICENSE NOTICE VERSION .gitignore .github/CODEOWNERS .gitleaks.toml .githooks/pre-commit)

check_repo() {
    local repo="$1"
    # --tree passes an absolute/relative path directly; default mode resolves a
    # bare name to the sibling checkout beside the umbrella (legacy nested works).
    local repo_path="$UMBRELLA_DIR/$repo"
    case "$repo" in
        .) repo_path="$UMBRELLA_DIR" ;;
        /*|*/*) repo_path="$repo" ;;
        *) [ -e "$UMBRELLA_DIR/$repo/.git" ] || repo_path="$(dirname "$UMBRELLA_DIR")/$repo" ;;
    esac

    if [ ! -d "$repo_path/.git" ]; then
        echo "MISSING:no-repo"
        return 1
    fi

    local fails=0
    for c in "${CHECKS[@]}"; do
        local file="$repo_path/$c"
        if [ -f "$file" ] && [ -s "$file" ]; then
            echo "OK:$c"
        else
            echo "MISSING:$c"
            fails=$((fails + 1))
        fi
    done
    return $fails
}

TOTAL_FAILS=0

if [ "$JSON_OUTPUT" = 1 ]; then
    echo "{"
    echo "  \"repos\": ["
    first=1
    for r in "${REPOS[@]}"; do
        [ "$first" = 1 ] && first=0 || echo "    ,"
        results=$(check_repo "$r" || true)
        repo_fails=0
        echo "    {"
        local_repo_name="$r"
        [ "$r" = "." ] && local_repo_name="umbrella"
        echo "      \"repo\": \"$local_repo_name\","
        echo "      \"checks\": {"
        check_first=1
        while IFS= read -r line; do
            status="${line%%:*}"
            name="${line#*:}"
            [ "$check_first" = 1 ] && check_first=0 || echo "        ,"
            echo -n "        \"$name\": \"$status\""
            [ "$status" = "MISSING" ] && repo_fails=$((repo_fails + 1))
        done <<< "$results"
        echo ""
        echo "      },"
        echo "      \"fails\": $repo_fails"
        echo "    }"
        TOTAL_FAILS=$((TOTAL_FAILS + repo_fails))
    done
    echo "  ],"
    echo "  \"total_fails\": $TOTAL_FAILS"
    echo "}"
else
    for r in "${REPOS[@]}"; do
        label="$r"
        [ "$r" = "." ] && label="umbrella"
        [ "$QUIET" = 0 ] && echo "── $label"
        results=$(check_repo "$r" || true)
        repo_fails=0
        while IFS= read -r line; do
            status="${line%%:*}"
            name="${line#*:}"
            if [ "$status" = "OK" ]; then
                [ "$QUIET" = 0 ] && echo "  ✓ $name"
            else
                [ "$QUIET" = 0 ] && echo "  ✗ MISSING: $name"
                repo_fails=$((repo_fails + 1))
            fi
        done <<< "$results"
        TOTAL_FAILS=$((TOTAL_FAILS + repo_fails))
        [ "$QUIET" = 0 ] && echo
    done
    echo "── summary"
    if [ "$TOTAL_FAILS" = 0 ]; then
        echo "  OK — every checked repo passed every check"
    else
        echo "  FAIL — $TOTAL_FAILS missing item(s) across ${#REPOS[@]} repo(s)"
    fi
fi

[ "$TOTAL_FAILS" = 0 ]
