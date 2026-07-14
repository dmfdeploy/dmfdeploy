#!/usr/bin/env bash
# fix-docs.sh — regenerate every deterministic generated artifact in one shot.
#
# The pre-commit hook is CHECK-ONLY since R7 (issue #223): it refuses on
# generated-artifact drift and points here. This script is the ONE sanctioned
# regenerator — it writes, reports what changed, and stages NOTHING (review,
# then `git add` what you meant). CI never auto-commits; humans/agents run
# this locally instead.
#
# Regenerates:
#   docs/SCRIPTS.md            (bin/generate-scripts-catalog.sh — refuses
#                               section loss, e.g. from a worktree where
#                               sibling repos don't resolve)
#   docs/plans/INDEX.md        (bin/generate-plans-index.sh)
#   .gitleaks.toml rules region (bin/gen-gitleaks-rules.py --emit)
#   .claude/.qwen skill views  (bin/sync-skills.sh --apply; gitignored)
#
# Usage:
#   bin/fix-docs.sh          # regenerate everything, report changes
#
# Exit: 0 = regenerated (changes, if any, reported); non-zero = a generator
# refused (fix its complaint first — never force past the section-loss guard
# unless a repo was genuinely retired).

set -euo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
cd "$UMBRELLA_DIR"

TRACKED_OUTPUTS=(docs/SCRIPTS.md docs/plans/INDEX.md .gitleaks.toml)

if [ "$(git rev-parse --git-dir 2>/dev/null)" != "$(git rev-parse --git-common-dir 2>/dev/null)" ]; then
    echo "NOTE: this is a linked worktree — sibling component repos may not" >&2
    echo "      resolve here; the scripts-catalog generator will refuse a" >&2
    echo "      write that would drop their sections." >&2
fi

before="$(git status --porcelain -- "${TRACKED_OUTPUTS[@]}")"

echo "── docs/SCRIPTS.md"
bin/generate-scripts-catalog.sh
echo "── docs/plans/INDEX.md"
bin/generate-plans-index.sh
echo "── .gitleaks.toml rules region"
python3 bin/gen-gitleaks-rules.py --emit
echo "── skill views (gitignored)"
bin/sync-skills.sh --apply --umbrella-only >/dev/null 2>&1 || bin/sync-skills.sh --apply >/dev/null

after="$(git status --porcelain -- "${TRACKED_OUTPUTS[@]}")"

echo
if [ -z "$after" ]; then
    echo "── all generated tracked artifacts already current"
elif [ "$before" = "$after" ]; then
    echo "── generated artifacts differ from HEAD (unchanged by this run):"
    printf '%s\n' "$after" | sed 's/^/  /'
else
    echo "── regenerated; review and stage what you meant:"
    printf '%s\n' "$after" | sed 's/^/  /'
    echo "  git add <path>   # nothing was staged automatically"
fi
