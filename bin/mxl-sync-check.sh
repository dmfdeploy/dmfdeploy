#!/usr/bin/env bash
# mxl-sync-check.sh — report how far each mxl-spike repo is behind origin/main.
#
# Read-only drift checker for the five mxl-spike repos (umbrella + dmf-cms,
# dmf-env, dmf-infra, dmf-media). For each repo it fetches origin, then prints
# how many commits the current branch is behind/ahead of origin/main, plus a
# conflict preview (files changed on both sides) and the exact merge command to
# run. It NEVER mutates anything — no merge, no checkout, no push.
#
# Why session-start, not pre-push: you want to know you're stale BEFORE building
# on a stale base, so you sync and avoid the conflict — not discover it at push.
# See `docs/plans/DMF MXL On-Demand Media Function Cycle Plan 2026-06-01.md`.
#
# Usage:
#   bin/mxl-sync-check.sh            # fetch + report drift for all spike repos
#   bin/mxl-sync-check.sh --no-fetch # use already-fetched refs (offline-safe)
#
# Exit status: 0 if every repo is up to date with origin/main, 1 if any is behind.

set -euo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PARENT_DIR="$(cd "$UMBRELLA_DIR/.." && pwd)"

# The umbrella, then the four component repos. Component repos may sit either
# nested inside the umbrella (canonical clone) or as siblings (spike worktree).
COMPONENT_REPOS=(dmf-cms dmf-env dmf-infra dmf-media)

DO_FETCH=1
[ "${1:-}" = "--no-fetch" ] && DO_FETCH=0

# Resolve a repo name to its working dir in either layout, or empty if absent.
resolve_repo() {
    local name="$1"
    if   [ -e "$UMBRELLA_DIR/$name/.git" ]; then echo "$UMBRELLA_DIR/$name"
    elif [ -e "$PARENT_DIR/$name/.git" ];   then echo "$PARENT_DIR/$name"
    fi
}

behind_total=0

report_repo() {
    local label="$1" dir="$2"
    if [ -z "$dir" ]; then
        printf '  %-13s \033[2m(not found locally — skipped)\033[0m\n' "$label"
        return
    fi
    [ "$DO_FETCH" = 1 ] && git -C "$dir" fetch -q origin 2>/dev/null || true

    local branch base behind ahead
    branch="$(git -C "$dir" branch --show-current)"
    if ! git -C "$dir" rev-parse --verify -q origin/main >/dev/null; then
        printf '  %-13s \033[2mno origin/main\033[0m\n' "$label"
        return
    fi
    base="$(git -C "$dir" merge-base HEAD origin/main)"
    behind="$(git -C "$dir" rev-list --count "$base"..origin/main)"
    ahead="$(git -C "$dir" rev-list --count "$base"..HEAD)"

    if [ "$behind" -eq 0 ]; then
        printf '  %-13s \033[32m✓ up to date\033[0m  (branch %s, ahead %s)\n' "$label" "$branch" "$ahead"
        return
    fi

    behind_total=$((behind_total + 1))
    printf '  %-13s \033[33m⚠ behind origin/main by %s\033[0m  (branch %s, ahead %s)\n' \
        "$label" "$behind" "$branch" "$ahead"

    # Conflict preview: files changed on BOTH sides since the merge base.
    local overlap
    overlap="$(comm -12 \
        <(git -C "$dir" diff --name-only "$base"..origin/main | sort) \
        <(git -C "$dir" diff --name-only "$base"..HEAD        | sort) || true)"
    if [ -n "$overlap" ]; then
        echo "      conflict-risk files (changed on both sides):"
        echo "$overlap" | sed 's/^/        ! /'
    else
        echo "      no file overlap — clean merge expected"
    fi
    echo "      sync:  git -C $dir merge origin/main"
}

echo "mxl-spike drift vs origin/main:"
report_repo "dmf-platform" "$UMBRELLA_DIR"
for name in "${COMPONENT_REPOS[@]}"; do
    report_repo "$name" "$(resolve_repo "$name")"
done

echo
if [ "$behind_total" -eq 0 ]; then
    echo "All spike repos are current with origin/main."
    exit 0
fi
echo "$behind_total repo(s) behind — merge origin/main before building on them."
exit 1
