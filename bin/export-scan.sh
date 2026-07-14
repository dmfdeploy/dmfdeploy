#!/usr/bin/env bash
# export-scan.sh — stage a CLEAN-HISTORY orphan export of one component repo and run
# every public-safety gate against that exact tree. Workstream A (first public release).
#
# It produces a single-commit orphan in a scratch dir (no pre-publish history), re-authored
# to the clean public identity, tagged v<VERSION>, and scanned. It NEVER pushes and NEVER
# creates a GitHub repo — on success it prints the exact operator command for review.
#
# Usage:
#   bin/export-scan.sh <repo>          # e.g. dmf-central
#   EXPORT_ROOT=/path bin/export-scan.sh <repo>   # override scratch parent (default /tmp/dmf-export)
#
# Accepts `.` for the umbrella (WP17, 2026-06-10 — the former B2 deferral is closed by the
# entrance plan's scrub sweep): exports to /tmp/dmf-export/dmfdeploy with two extra umbrella
# gates (STATUS.md no-allowlist identity check; informational full-tree no-allowlist report).
#
# Exit: 0 = scratch staged + ALL gates green (ready for operator push); non-zero otherwise.

set -euo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=bin/lib/dmf-repo-detect.sh
. "$UMBRELLA_DIR/bin/lib/dmf-repo-detect.sh"
GITHUB_ORG="${DMF_GITHUB_ORG:-dmfdeploy}"
EXPORT_ROOT="${EXPORT_ROOT:-/tmp/dmf-export}"

# Clean public identity for the orphan commit (NOT the operator's local git identity).
PUB_NAME="znerol2"
PUB_EMAIL="6800371+znerol2@users.noreply.github.com"

die() { echo "FATAL: $*" >&2; exit 1; }

[ "$#" -eq 1 ] || die "usage: bin/export-scan.sh <repo>"
REPO="$1"

# ── gitleaks pinning now lives in the shared scan library (R1 §6): ONE
# pinned version + sha for every context, still matching guard.yml. The
# library resolves/downloads it on demand; no in-script fallback exists.

# GitHub repo name mapping (the 8 importable component repos; dmf-runbooks joined the
# clean-import set after its public repo was deleted in the 2026-06-09 CI recovery).
gh_name() {
    case "$1" in
        .) printf 'dmfdeploy' ;;
        dmf-cms|dmf-central|dmf-infra|dmf-media|dmf-init|dmf-env|dmf-promsd|dmf-runbooks) printf '%s' "$1" ;;
        *) return 1 ;;
    esac
}

GH_NAME="$(gh_name "$REPO")" || die "'$REPO' is not in the importable set"

# Component repos are siblings of the umbrella since 2026-06-11 (ADR-0001
# amendment); legacy nested checkouts still resolve.
SRC="$UMBRELLA_DIR/$REPO"
[ -e "$SRC/.git" ] || SRC="$(dirname "$UMBRELLA_DIR")/$REPO"
[ "$REPO" = "." ] && SRC="$UMBRELLA_DIR"
dmf_is_repo_root "$SRC" || die "no git repo at $SRC"
[ -f "$SRC/VERSION" ] || die "$REPO has no VERSION file"
VERSION="$(tr -d '[:space:]' < "$SRC/VERSION")"
[ -n "$VERSION" ] || die "$REPO VERSION is empty"
TAG="v$VERSION"

SCRATCH="$EXPORT_ROOT/$GH_NAME"
echo "━━━ export-scan: $REPO → $GH_NAME  (tag $TAG)"
echo "    scratch: $SCRATCH"
rm -rf "$SCRATCH"
mkdir -p "$SCRATCH"

# 1. Export the tracked tip only — git archive drops .git, so NO history rides along.
git -C "$SRC" archive main | tar -x -C "$SCRATCH"

# 2. Confirm governance + CI rode along (they are committed on main per Workstreams D/E1).
for f in CONTRIBUTING.md SECURITY.md LICENSE .github; do
    [ -e "$SCRATCH/$f" ] || die "governance/CI artifact missing from export: $f (is D/E1 committed on $REPO main?)"
done

# 3. Orphan commit with the CLEAN public identity; sign off (DCO); tag.
git -C "$SCRATCH" init -q -b main
git -C "$SCRATCH" -c user.name="$PUB_NAME" -c user.email="$PUB_EMAIL" add -A
git -C "$SCRATCH" -c user.name="$PUB_NAME" -c user.email="$PUB_EMAIL" \
    commit -sq -m "Initial public release $TAG"
git -C "$SCRATCH" tag "$TAG"

# 4. Scan the EXACT scratch tree. Any failure aborts.
echo "━━━ gates"
fail=0
run() { echo "── $1"; shift; if "$@"; then echo "  ✓"; else echo "  ✗ FAILED"; fail=1; fi; }

# R1 §6 switchover: one library call replaces the separate scrub + gitleaks
# steps — manifest-driven grep pass + pinned gitleaks (no-git, run WITH
# cwd=scratch so paths stay repo-relative for the allowlists) under the
# ephemeral merged public+private config, HARDCODED export-scan context,
# fail-closed on a missing private manifest (§5.3).
run "dmf-scan tree (grep + pinned gitleaks)" "$UMBRELLA_DIR/bin/dmf-scan" tree "$SCRATCH" --context export-scan
run "dmf-scan range (main scope, 1 commit)"  "$UMBRELLA_DIR/bin/dmf-scan" range main --repo "$SCRATCH" --context export-scan
run "check-public-commit-authors --tree" bash "$UMBRELLA_DIR/bin/check-public-commit-authors.sh" --tree "$SCRATCH"
run "check-public-repo-hygiene --tree" bash "$UMBRELLA_DIR/bin/check-public-repo-hygiene.sh" --tree "$SCRATCH"
if [ "$REPO" = "dmf-env" ]; then
    run "dmf-env-public-surface-gate"  bash "$UMBRELLA_DIR/bin/dmf-env-public-surface-gate.sh" "$SCRATCH"
fi
if [ "$REPO" = "." ]; then
    # WP17 gate: the exported STATUS.md (HUMAN section included) must be
    # placeholder-clean — the normal scrub allowlists STATUS.md, so check it
    # in isolation with the allowlist disabled.
    status_gate() {
        local d; d="$(mktemp -d "${TMPDIR:-/tmp}/dmf-status-gate.XXXXXX")"
        cp "$SCRATCH/STATUS.md" "$d/STATUS.md"
        git -C "$d" init -q && git -C "$d" add STATUS.md
        SCRUB_NO_ALLOWLIST=1 bash "$UMBRELLA_DIR/bin/scrub-public-repos.sh" --tree "$d"
        local rc=$?
        rm -rf "$d"
        return $rc
    }
    run "STATUS.md no-allowlist identity/topology" status_gate
    # Informational (never gates): full-tree no-allowlist sweep for the
    # operator's manual adjudication pass (WP17 raw grep).
    echo "── umbrella no-allowlist sweep (INFORMATIONAL — adjudicate by hand)"
    SCRUB_NO_ALLOWLIST=1 bash "$UMBRELLA_DIR/bin/scrub-public-repos.sh" --tree "$SCRATCH" || true
fi

# 5. Defensive: confirm exactly one commit and no stray refs.
commits="$(git -C "$SCRATCH" rev-list --count HEAD)"
[ "$commits" = "1" ] || { echo "  ✗ expected 1 commit, found $commits" >&2; fail=1; }

if [ "$fail" -ne 0 ]; then
    echo "━━━ RESULT: $REPO — GATES FAILED. Do not push." >&2
    exit 1
fi

echo
echo "━━━ READY: $REPO — scratch clean, $(git -C "$SCRATCH" rev-list --count HEAD) commit, gates GREEN."
git -C "$SCRATCH" log --oneline --decorate
echo
echo "To import (operator, AFTER creating the PRIVATE GitHub repo dmfdeploy/$GH_NAME):"
echo "    git -C \"$SCRATCH\" remote add github git@github.com:$GITHUB_ORG/$GH_NAME.git"
echo "    git -C \"$SCRATCH\" push github main $TAG    # main + the one tag ONLY — never --tags/--all"
echo
echo "(this script pushed nothing and created no GitHub repo.)"
