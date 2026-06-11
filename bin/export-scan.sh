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
GITHUB_ORG="${DMF_GITHUB_ORG:-dmfdeploy}"
EXPORT_ROOT="${EXPORT_ROOT:-/tmp/dmf-export}"

# Clean public identity for the orphan commit (NOT the operator's local git identity).
PUB_NAME="znerol2"
PUB_EMAIL="6800371+znerol2@users.noreply.github.com"

die() { echo "FATAL: $*" >&2; exit 1; }

[ "$#" -eq 1 ] || die "usage: bin/export-scan.sh <repo>"
REPO="$1"

# ── Pinned gitleaks — MUST match guard.yml's version so the pre-publish gate is
# authoritative for what CI sees. NO system-gitleaks fallback (default rulesets drift
# between versions; that skew let private-key placeholders through on 8.30.1 once).
GL_VERSION="8.21.2"
case "$(uname -s)/$(uname -m)" in
    Darwin/arm64) GL_ASSET="gitleaks_${GL_VERSION}_darwin_arm64.tar.gz"; GL_SHA256="cad3de5dc9a4d5447d967a70a4d49499c557f04db028274cc324f9ff983f6502" ;;
    Linux/x86_64) GL_ASSET="gitleaks_${GL_VERSION}_linux_x64.tar.gz";    GL_SHA256="5bc41815076e6ed6ef8fbecc9d9b75bcae31f39029ceb55da08086315316e3ba" ;;
    *) die "no pinned gitleaks ${GL_VERSION} for $(uname -s)/$(uname -m) — add its checksum" ;;
esac
GL_DIR="${TMPDIR:-/tmp}/dmf-gitleaks-${GL_VERSION}"
GL="${GL_DIR}/gitleaks"
if [ ! -x "$GL" ]; then
    mkdir -p "$GL_DIR"
    curl -fsSLo "$GL_DIR/gl.tgz" "https://github.com/gitleaks/gitleaks/releases/download/v${GL_VERSION}/${GL_ASSET}" \
        || die "gitleaks ${GL_VERSION} download failed"
    echo "${GL_SHA256}  $GL_DIR/gl.tgz" | shasum -a 256 -c - >/dev/null 2>&1 || die "gitleaks ${GL_VERSION} sha256 mismatch"
    tar -xzf "$GL_DIR/gl.tgz" -C "$GL_DIR" gitleaks || die "gitleaks extract failed"
fi
# Assert the resolved binary is exactly the pinned version (no silent drift).
"$GL" version 2>/dev/null | grep -qx "$GL_VERSION" || die "pinned gitleaks is not ${GL_VERSION} (got: $("$GL" version 2>/dev/null))"

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

SRC="$UMBRELLA_DIR/$REPO"
[ "$REPO" = "." ] && SRC="$UMBRELLA_DIR"
[ -d "$SRC/.git" ] || die "no git repo at $SRC"
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

run "scrub-public-repos --tree"        bash "$UMBRELLA_DIR/bin/scrub-public-repos.sh" --tree "$SCRATCH"
run "check-public-commit-authors --tree" bash "$UMBRELLA_DIR/bin/check-public-commit-authors.sh" --tree "$SCRATCH"
# gitleaks MUST run from inside the scratch with --source . so it emits REPO-RELATIVE
# paths — otherwise absolute /tmp/... paths defeat the repos' path allowlists (codex).
# Authoritative public gate = the no-git full-tree scan; also keep a git/log scan.
run "gitleaks ${GL_VERSION} (no-git tree, relative)" bash -c "cd '$SCRATCH' && '$GL' detect --source . --no-git --config .gitleaks.toml --no-banner --redact"
run "gitleaks ${GL_VERSION} (main scope, 1 commit)"  bash -c "cd '$SCRATCH' && '$GL' detect --log-opts=main --config .gitleaks.toml --no-banner --redact"
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
