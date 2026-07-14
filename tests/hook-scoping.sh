#!/usr/bin/env bash
# hook-scoping.sh — regressions for the R7 path-scoped pre-commit gates
# (codex R7 round-1 P1s, both reproduced before the fix):
#
#   P1-1  a RENAME's source path must fire its gate (--name-only with rename
#         detection reports only the destination, so `git mv bin/x.sh x.sh`
#         silently skipped the scripts-catalog gate and stale docs passed)
#   P1-2  a gate's own IMPLEMENTATION script is part of its trigger (staging
#         a broken bin/check-docs.sh must run — and fail — that gate)
#   ctrl  an unrelated root file fires NO doc gate (the fast path stays fast)
#
# Fixture repos carry the scan tooling + the doc-gate scripts so the real
# .githooks/pre-commit runs end-to-end. Hermetic: synthetic private manifest;
# canaries assembled at runtime.
set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
pass=0; fail=0
ok()  { echo "  ✓ $1"; pass=$((pass + 1)); }
bad() { echo "  ✗ $1" >&2; fail=$((fail + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dmf-hook-scoping.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

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

FX="$WORK/fx"
mkdir -p "$FX/bin/lib" "$FX/patterns" "$FX/.githooks" "$FX/docs"
cp "$UMBRELLA_DIR/bin/dmf-scan" "$UMBRELLA_DIR/bin/gen-gitleaks-rules.py" \
   "$UMBRELLA_DIR/bin/generate-scripts-catalog.sh" "$UMBRELLA_DIR/bin/check-docs.sh" \
   "$UMBRELLA_DIR/bin/generate-plans-index.sh" "$FX/bin/"
cp "$UMBRELLA_DIR/bin/lib/dmf_scan.py" "$UMBRELLA_DIR/bin/lib/dmf_scan_selftest.py" "$FX/bin/lib/"
cp "$UMBRELLA_DIR/patterns/public-manifest.toml" "$FX/patterns/"
cp "$UMBRELLA_DIR/.gitleaks.toml" "$FX/"
cp "$UMBRELLA_DIR/.githooks/pre-commit" "$FX/.githooks/"
printf '#!/bin/sh\n# probe.sh — fixture probe script for the catalog.\necho probe\n' > "$FX/bin/probe.sh"
chmod +x "$FX/bin/probe.sh"
git -C "$FX" init -q -b main
git -C "$FX" config user.email "test@example.com"
git -C "$FX" config user.name "test"
# A valid catalog baseline generated from THIS fixture (siblings absent by
# design — the fixture's catalog carries only its own sections).
(cd "$FX" && UMBRELLA_DIR="$FX" bin/generate-scripts-catalog.sh >/dev/null)
git -C "$FX" add -A
git -C "$FX" commit -qm "fixture baseline"

run_hook() { (cd "$FX" && UMBRELLA_DIR="$FX" bash .githooks/pre-commit >/dev/null 2>&1); }

echo "── control: unrelated root file fires no doc gate"
echo "note" > "$FX/unrelated.txt"
git -C "$FX" add unrelated.txt
if run_hook; then ok "control: benign root-file commit passes"; else bad "control: benign commit refused"; fi
git -C "$FX" reset -q unrelated.txt && rm -f "$FX/unrelated.txt"

echo "── P1-1: rename SOURCE must fire the scripts-catalog gate"
git -C "$FX" mv bin/probe.sh probe.sh
if run_hook; then
    bad "P1-1: hook passed a bin/→root rename with a now-stale catalog"
else
    ok "P1-1: hook refuses — rename source path fired the catalog gate"
fi
git -C "$FX" mv probe.sh bin/probe.sh

echo "── P1-2: a broken gate implementation must fire (and fail) its gate"
printf '\nexit 1\n' >> "$FX/bin/check-docs.sh"
git -C "$FX" add bin/check-docs.sh
if run_hook; then
    bad "P1-2: hook passed with a failing bin/check-docs.sh staged"
else
    ok "P1-2: hook refuses — the checker's own path fired its gate"
fi
# Unstage FIRST, then restore the worktree: a bare `checkout -- <file>`
# restores from the INDEX, which still holds the broken version — the
# leftover staged file then contaminates the next case (codex R7 delta).
git -C "$FX" reset -q -- bin/check-docs.sh
git -C "$FX" checkout -q -- bin/check-docs.sh

echo "── P1-2b: editing the hook itself re-arms every doc gate"
# Only the hook is staged; the catalog is made stale on disk (unstaged), so
# no data-path trigger fires — re-arming via the hook edit must catch it.
if ! git -C "$FX" diff --cached --quiet; then
    bad "P1-2b precondition: index not clean — previous case leaked staged state"
fi
printf '\n# hook edit probe\n' >> "$FX/.githooks/pre-commit"
git -C "$FX" add .githooks/pre-commit
printf '\nstale-tail\n' >> "$FX/docs/SCRIPTS.md"
if run_hook; then
    bad "P1-2b: hook-edit commit passed despite a drifted catalog"
else
    ok "P1-2b: hook-edit commit re-armed the catalog gate and refused"
fi
git -C "$FX" checkout -q -- docs/SCRIPTS.md
git -C "$FX" reset -q .githooks/pre-commit

echo "hook-scoping: ${pass} passed, ${fail} failed"
[ "$fail" -eq 0 ]
