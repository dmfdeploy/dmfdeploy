#!/usr/bin/env bash
# sync-to-github.sh — RETIRED 2026-06-09 (do not use).
#
# This was the old Forgejo-canonical "push the live repo's main + v0.1.0" mirror
# tool. The DMF Platform moved to GitHub-canonical-forward (ADR-0041): GitHub `main`
# is the single source of truth and steady-state publishing is normal PR-merge to
# GitHub. The first public import is a CLEAN-HISTORY orphan via bin/export-scan.sh
# (per-repo, operator-gated) — never a full-history mirror push.
#
# Pushing the live full-history repo here would publish pre-publish history (the
# 2026-05-07 handoff documents a real Admin123 cred in dmf-infra's old awx.md). This
# script is therefore neutered to a hard stop. The original logic is preserved below
# the exit for reference only and never executes.

if [ "${ALLOW_RETIRED_SYNC_TO_GITHUB:-}" != "I_KNOW_THIS_IS_RETIRED" ]; then
    echo "sync-to-github.sh is RETIRED (2026-06-09)." >&2
    echo "  GitHub-canonical-forward: steady state = PR-merge to GitHub main." >&2
    echo "  First import = bin/export-scan.sh (per-repo, operator-gated, clean orphan)." >&2
    echo "  This tool would push LIVE FULL HISTORY and is intentionally disabled." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Original (retired) implementation below — kept for reference, never reached.
# ---------------------------------------------------------------------------
#
# Usage:
#   bin/sync-to-github.sh <repo> [<repo>...]    # push the named repo(s)
#   bin/sync-to-github.sh --all                  # push all publish targets (umbrella + 6 public components)
#   bin/sync-to-github.sh <repo> --dry-run       # show what would be pushed
#   bin/sync-to-github.sh --all --dry-run
#
# Repo names match the umbrella subdirectory layout. Use `.` for the
# umbrella (publishes as github.com/dmfdeploy/dmf-platform).
#
# Optional flags:
#   --dry-run            Print every gate result + `git push --dry-run`
#                        output. No actual push.
#   --force-with-lease   Allow non-fast-forward push (required after a
#                        history rewrite such as filter-branch). Refuses
#                        if the remote has moved unexpectedly.
#   -h, --help           Print this header and exit.
#
# Gates (all must pass per repo before push):
#   1. Repo is on the public-publish whitelist (dmf-env is forbidden).
#   2. bin/scrub-public-repos.sh <repo>            → OK clean
#   3. bin/check-public-commit-authors.sh <repo>   → OK clean
#   4. gitleaks detect --log-opts=main             → no leaks
#   5. gitleaks detect --no-git                    → no leaks
#   6. A 'github' remote is configured for <repo>.
#
# Refspec: pushes only `main` + tag `v0.1.0`. Never `--tags` and never
# `--all` — both would publish `archive/pre-publish-*` tags that handoff
# Gate 1 (Forgejo push-mirror refspec) deliberately fences off as
# LAN-only. The archive history contains pre-publish credentials and
# topology that must not land on GitHub.
#
# Exit codes:
#   0 — every requested repo pushed (or dry-run printed) cleanly
#   1 — one or more gates failed; no push was performed for the failing repo
#   2 — usage / argument error

set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
GITHUB_ORG="${DMF_GITHUB_ORG:-dmfdeploy}"

# Mapping: umbrella subdir → GitHub repo name. The umbrella itself
# publishes as `dmf-platform` per handoff Phase E. dmf-env is
# DELIBERATELY ABSENT — that repo never goes public (handoff Gate 2).
github_repo_name() {
    case "$1" in
        .)            echo "dmf-platform" ;;
        dmf-cms)      echo "dmf-cms" ;;
        dmf-runbooks) echo "dmf-runbooks" ;;
        dmf-central)  echo "dmf-central" ;;
        dmf-infra)    echo "dmf-infra" ;;
        dmf-media)    echo "dmf-media" ;;
        dmf-init)     echo "dmf-init" ;;
        *)            return 1 ;;
    esac
}

# Publish targets: umbrella (`.`) + 6 public components. dmf-env stays private;
# dmf-promsd is a component repo but NOT yet on the public-publish path (add it
# here + to github_repo_name() only when that path is decided — see TODOS.md).
PUBLIC_REPOS=(. dmf-cms dmf-runbooks dmf-central dmf-infra dmf-media dmf-init)

DRY_RUN=0
FORCE_LEASE=0
ALL=0
TARGET_REPOS=()

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)          DRY_RUN=1; shift ;;
        --force-with-lease) FORCE_LEASE=1; shift ;;
        --all)              ALL=1; shift ;;
        -h|--help)
            sed -n '2,42p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        --) shift; while [ "$#" -gt 0 ]; do TARGET_REPOS+=("$1"); shift; done ;;
        -*) echo "unknown flag: $1" >&2; exit 2 ;;
        *)  TARGET_REPOS+=("$1"); shift ;;
    esac
done

if [ "$ALL" = 1 ]; then
    TARGET_REPOS=("${PUBLIC_REPOS[@]}")
fi

if [ "${#TARGET_REPOS[@]}" -eq 0 ]; then
    echo "usage: bin/sync-to-github.sh <repo>... | --all  [--dry-run] [--force-with-lease]" >&2
    echo "       bin/sync-to-github.sh --help" >&2
    exit 2
fi

# Validate every requested repo is on the whitelist BEFORE running any
# expensive gate. Fast fail on dmf-env or typos.
for r in "${TARGET_REPOS[@]}"; do
    if ! github_repo_name "$r" >/dev/null 2>&1; then
        echo "refusing: '$r' is not in the public-publish whitelist" >&2
        echo "          allowed: . dmf-cms dmf-runbooks dmf-central dmf-infra dmf-media dmf-init" >&2
        echo "          (dmf-env is deliberately private — handoff Gate 2)" >&2
        exit 2
    fi
done

TMP="$(mktemp -d -t dmf-sync.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

run_gate() {
    local label="$1" outfile="$2"
    shift 2
    if "$@" >"$outfile" 2>&1; then
        echo "  ✓ $label"
        return 0
    fi
    echo "  ✗ $label" >&2
    sed 's/^/      /' "$outfile" >&2
    return 1
}

sync_one() {
    local repo="$1"
    local gh_name; gh_name="$(github_repo_name "$repo")"
    local label="$repo"
    [ "$repo" = "." ] && label="dmfdeploy (umbrella)"

    echo "── $label → github.com/${GITHUB_ORG}/${gh_name}"

    # Gate 2: scrub
    run_gate "scrub"                "$TMP/scrub.log"  "$UMBRELLA_DIR/bin/scrub-public-repos.sh" "$repo" || return 1
    # Gate 3: commit-author check
    run_gate "commit-author check"  "$TMP/auth.log"   "$UMBRELLA_DIR/bin/check-public-commit-authors.sh" "$repo" || return 1

    # Gate 4 + 5: gitleaks (main scope + no-git tree scan)
    if command -v gitleaks >/dev/null 2>&1; then
        if ! ( cd "$UMBRELLA_DIR/$repo" && gitleaks detect --log-opts=main --no-banner ) >"$TMP/glmain.log" 2>&1; then
            echo "  ✗ gitleaks --log-opts=main: leaks found" >&2
            sed 's/^/      /' "$TMP/glmain.log" >&2
            return 1
        fi
        echo "  ✓ gitleaks main"
        if ! ( cd "$UMBRELLA_DIR/$repo" && gitleaks detect --no-git --no-banner ) >"$TMP/glnogit.log" 2>&1; then
            echo "  ✗ gitleaks --no-git: leaks found" >&2
            sed 's/^/      /' "$TMP/glnogit.log" >&2
            return 1
        fi
        echo "  ✓ gitleaks no-git"
    else
        echo "  ! gitleaks not installed — skipping (install: brew install gitleaks)" >&2
    fi

    # Gate 6: github remote
    local gh_url
    gh_url="$(git -C "$UMBRELLA_DIR/$repo" remote get-url github 2>/dev/null || true)"
    if [ -z "$gh_url" ]; then
        echo "  ✗ no 'github' remote configured for $label" >&2
        echo "    add with:" >&2
        if [ "$repo" = "." ]; then
            echo "      git -C \"$UMBRELLA_DIR\" remote add github git@github.com:${GITHUB_ORG}/${gh_name}.git" >&2
        else
            echo "      git -C \"$UMBRELLA_DIR/$repo\" remote add github git@github.com:${GITHUB_ORG}/${gh_name}.git" >&2
        fi
        return 1
    fi
    echo "  ✓ github remote: $gh_url"

    # Push. Refspec is locked to main + v0.1.0; never --tags, never --all.
    local push_args=()
    [ "$FORCE_LEASE" = 1 ] && push_args+=("--force-with-lease")

    if [ "$DRY_RUN" = 1 ]; then
        echo "  [dry-run] git push ${push_args[*]} --dry-run github main v0.1.0"
        ( cd "$UMBRELLA_DIR/$repo" && git push "${push_args[@]}" --dry-run github main v0.1.0 2>&1 | sed 's/^/      /' ) || {
            echo "  ✗ dry-run push reported a problem" >&2
            return 1
        }
        return 0
    fi

    echo "  pushing main + v0.1.0..."
    if ! ( cd "$UMBRELLA_DIR/$repo" && git push "${push_args[@]}" github main v0.1.0 2>&1 | sed 's/^/      /' ); then
        echo "  ✗ push failed" >&2
        return 1
    fi
    echo "  ✓ pushed to github.com/${GITHUB_ORG}/${gh_name}"
}

failures=0
for r in "${TARGET_REPOS[@]}"; do
    if ! sync_one "$r"; then
        failures=$((failures + 1))
    fi
    echo
done

echo "── summary"
if [ "$failures" -gt 0 ]; then
    echo "  FAIL — $failures repo(s) did not sync" >&2
    exit 1
fi
if [ "$DRY_RUN" = 1 ]; then
    echo "  OK — dry-run complete; no commits pushed"
else
    echo "  OK — synced ${#TARGET_REPOS[@]} repo(s) to github.com/${GITHUB_ORG}/"
fi
