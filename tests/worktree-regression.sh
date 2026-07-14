#!/usr/bin/env bash
# worktree-regression.sh — proves the public-safety gates scan a git WORKTREE
# instead of silently skipping it (R1 spec §7, acceptance matrix rows 7–9).
#
# The bug: `[ -d "$path/.git" ]` is false for a worktree (there `.git` is a file),
# so the old scrub `continue`d past worktrees and reported clean without scanning.
# This test builds a throwaway repo with a seeded PUBLIC canary, adds a worktree,
# and asserts:
#   row 7  scrub-public-repos.sh --tree <worktree>   → CATCHES the canary (exit != 0)
#   row 8  check-public-repo-hygiene.sh --tree <wt>   → resolves the repo (not no-repo)
#   row 9  export-scan.sh from a worktree source       → resolves the repo (not "no git repo")
#
# Canaries are ASSEMBLED AT RUNTIME from harmless parts so THIS committed file
# carries no value that matches a scrub/gitleaks rule (verified: the repo's own
# pre-commit gitleaks passes on this file).
#
# Self-contained: no network, no operator-private include needed (public rule
# only). Exit 0 = all assertions pass; 1 = a regression.
set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRUB="$UMBRELLA_DIR/bin/scrub-public-repos.sh"
HYGIENE="$UMBRELLA_DIR/bin/check-public-repo-hygiene.sh"

pass=0
fail=0
ok()   { echo "  ✓ $1"; pass=$((pass + 1)); }
bad()  { echo "  ✗ $1" >&2; fail=$((fail + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dmf-wt-regression.XXXXXX")"
cleanup() {
    # Remove the worktree registration before the dir, then the source repo.
    git -C "$WORK/repo" worktree remove --force "$WORK/wt" >/dev/null 2>&1 || true
    rm -rf "$WORK"
}
trap cleanup EXIT

# Since the §9 step 4 switchover scrub is a thin fail-closed caller of
# bin/dmf-scan: the scrub context REQUIRES a private manifest. Provide a
# SYNTHETIC one (fixture pattern only — never operator data) so this test
# stays hermetic in CI and never reads the operator's real manifest.
cat > "$WORK/private-fixture.toml" <<'EOF'
[[pattern]]
id = "fixture-private-marker"
category = "topology"
description = "fixture private topology marker (synthetic)"
regex = 'FIXTURE-PRIVATE-[0-9]{6}'
engines = ["pcre", "re2"]
case_sensitive = true
positive_canaries = ["FIXTURE-PRIVATE-314159"]
[pattern.gitleaks]
emit = false
covered_by = "git-grep"
EOF
export DMF_PATTERN_MANIFEST_PRIVATE="$WORK/private-fixture.toml"

# ── Fixture: a repo whose tracked content holds a PUBLIC-matching canary ──
# Assemble an AWS-access-key-shaped canary (scrub SECRET_PATTERNS: \bAKIA[0-9A-Z]{16}\b)
# from parts, so the literal never appears in this committed test file.
key_prefix="AKIA"
key_body="ABCDEFGHIJKLMNOP"          # 16 upper-alnum; harmless on its own
CANARY="${key_prefix}${key_body}"

mkdir -p "$WORK/repo"
git -C "$WORK/repo" init -q -b main
git -C "$WORK/repo" config user.email "test@example.com"
git -C "$WORK/repo" config user.name "test"
printf 'aws_key = "%s"\n' "$CANARY" > "$WORK/repo/leak.txt"
git -C "$WORK/repo" add -A
git -C "$WORK/repo" commit -qm "seed canary"

# Sanity: the seeded value must match under a NORMAL clone first (baseline).
if bash "$SCRUB" --tree "$WORK/repo" >/dev/null 2>&1; then
    bad "baseline: scrub did NOT catch the canary in a normal clone (fixture broken?)"
else
    ok  "baseline: scrub catches the canary in a normal checkout"
fi

# ── Add a worktree; .git there is a FILE, not a directory ──
git -C "$WORK/repo" worktree add -q --detach "$WORK/wt" main
if [ -f "$WORK/wt/.git" ]; then
    ok  "worktree .git is a file (the condition the old test mis-handled)"
else
    bad "worktree .git is not a file — environment unexpected"
fi

# ── row 7: scrub must scan the worktree and CATCH the canary ──
if bash "$SCRUB" --tree "$WORK/wt" >/dev/null 2>&1; then
    bad "row 7: scrub SKIPPED the worktree (regression — canary not caught)"
else
    ok  "row 7: scrub scans the worktree and catches the canary"
fi

# ── row 8: hygiene must resolve the worktree repo, not report no-repo ──
hy="$(bash "$HYGIENE" --tree "$WORK/wt" 2>&1 || true)"
if printf '%s' "$hy" | grep -q 'no-repo'; then
    bad "row 8: hygiene reported no-repo for a worktree (regression)"
else
    ok  "row 8: hygiene resolves the worktree as a repo"
fi

# ── row 9: invoke bin/export-scan.sh ITSELF from a worktree source ──
# Build a minimal umbrella-shaped fixture (export-scan sources bin/lib/
# dmf-repo-detect.sh and, for REPO='.', checks VERSION), make a worktree of it,
# and run export-scan with UMBRELLA_DIR pointed at that worktree. A stubbed pinned
# gitleaks (isolated via TMPDIR so the shared cache is never clobbered) lets it get
# past the download to the repo check. We assert it reaches the export banner —
# i.e. it proceeded PAST the `no git repo at` refusal — not that a full export
# succeeds (the fixture deliberately lacks governance files, so it stops later).
fx="$WORK/fx"
mkdir -p "$fx/bin/lib"
cp "$UMBRELLA_DIR/bin/lib/dmf-repo-detect.sh" "$fx/bin/lib/dmf-repo-detect.sh"
cp "$UMBRELLA_DIR/bin/export-scan.sh" "$fx/bin/export-scan.sh"
echo "0.0.0-test" > "$fx/VERSION"
git -C "$fx" init -q -b main
git -C "$fx" config user.email "test@example.com"
git -C "$fx" config user.name "test"
git -C "$fx" add -A
git -C "$fx" commit -qm "export-scan fixture"
git -C "$fx" worktree add -q --detach "$WORK/fxwt" main

es_tmp="$WORK/es-tmp"
mkdir -p "$es_tmp/dmf-gitleaks-8.21.2"
printf '#!/bin/sh\n[ "$1" = version ] && echo 8.21.2\nexit 0\n' > "$es_tmp/dmf-gitleaks-8.21.2/gitleaks"
chmod +x "$es_tmp/dmf-gitleaks-8.21.2/gitleaks"

es_out="$(UMBRELLA_DIR="$WORK/fxwt" TMPDIR="$es_tmp" EXPORT_ROOT="$WORK/es-out" \
    bash "$WORK/fxwt/bin/export-scan.sh" . 2>&1 || true)"
if printf '%s' "$es_out" | grep -q 'no git repo at'; then
    bad "row 9: export-scan refused the worktree source ('no git repo at' — regression)"
elif printf '%s' "$es_out" | grep -q 'export-scan:'; then
    ok  "row 9: export-scan proceeds past the repo check on a worktree source"
else
    bad "row 9: export-scan neither refused nor reached the banner (unexpected: $es_out)"
fi
git -C "$fx" worktree remove --force "$WORK/fxwt" >/dev/null 2>&1 || true

# ── resolver unit checks: worktree accepted, non-repo rejected (no false positive) ──
# shellcheck source=bin/lib/dmf-repo-detect.sh
. "$UMBRELLA_DIR/bin/lib/dmf-repo-detect.sh"
mkdir -p "$WORK/plain"
if dmf_is_repo_root "$WORK/plain"; then
    bad "resolver false-positive: a non-repo dir was accepted as a repo"
else
    ok  "resolver rejects a non-repo directory (no false positive)"
fi

echo "worktree-regression: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
