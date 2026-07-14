#!/usr/bin/env bash
# acceptance-matrix.sh — the R1 §8 trust-context/caller acceptance matrix,
# exercised through the REAL callers' argument wiring (not the library alone;
# bin/dmf-scan self-test covers the library level).
#
# Rows covered here (public-CI-safe: seeded canaries are the DMF-CANARY
# sentinel + a SYNTHETIC private fixture pattern — never operator data):
#   1  pre-commit hook   staged sentinel → refused; staged synthetic-private
#                        value → refused AND redacted through the caller
#   2  pre-push hook     sentinel in a pushed commit → refused
#   3  scrub             sentinel in tree → LEAK; clean tree → OK;
#                        synthetic-private in tree → LEAK + redacted
#   4  export-scan       sentinel in an export fixture umbrella → gates FAIL
#   5  dmf-env gate      sentinel in kept file → FAIL
#   10 scrub with a MISSING private manifest → CONFIG_ERROR (exit 3)
#   11 DMF_SCAN_PUBLIC_ONLY=1 spoof against scrub → CONFIG_ERROR (exit 3)
# Rows 6 (guard.yml BASE config) is live CI itself; 7–9 are
# tests/worktree-regression.sh; 12 (drift) is gen --check + dmf-scan check in ci.yml.
#
# The operator-local run of the PRIVATE rows with REAL canaries:
#   tests/acceptance-matrix.sh --private
# reads the operator manifest's own positive_canaries (values never printed).
#
# Canaries are ASSEMBLED AT RUNTIME so this committed file carries no literal
# that matches any rule. Exit 0 = all assertions pass.
set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PRIVATE_MODE=0
[ "${1:-}" = "--private" ] && PRIVATE_MODE=1

pass=0; fail=0
ok()  { echo "  ✓ $1"; pass=$((pass + 1)); }
bad() { echo "  ✗ $1" >&2; fail=$((fail + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dmf-acceptance.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# Sentinel assembled from parts (matches manifest rule dmf-canary-sentinel).
SENTINEL="DMF-CANARY-""ABCDEF012345"
PRIV_MARK="FIXTURE-PRIVATE-""654321"

if [ "$PRIVATE_MODE" = "1" ]; then
    # Operator-local: use the REAL private manifest and one of ITS canaries
    # (read into a variable, never printed; probes live only in tmp).
    PRIV_MANIFEST="${DMF_PATTERN_MANIFEST_PRIVATE:-$HOME/.dmfdeploy/pattern-manifest.private.toml}"
    PRIV_MARK="$(python3 - "$PRIV_MANIFEST" <<'EOF'
import sys, tomllib
m = tomllib.load(open(sys.argv[1], "rb"))
for e in m.get("pattern", []):
    for c in e.get("positive_canaries", []):
        print(c.replace("~", ""))
        raise SystemExit
EOF
)"
    [ -n "$PRIV_MARK" ] || { echo "no canary in the private manifest" >&2; exit 3; }
else
    PRIV_MANIFEST="$WORK/private-fixture.toml"
    cat > "$PRIV_MANIFEST" <<'EOF'
[[pattern]]
id = "fixture-private-marker"
category = "topology"
description = "fixture private topology marker (synthetic)"
regex = 'FIXTURE-PRIVATE-[0-9]{6}'
engines = ["pcre", "re2"]
case_sensitive = true
positive_canaries = ["FIXTURE-PRIVATE-314159"]
[pattern.gitleaks]
emit = true
kind = "custom"
tags = ["fixture"]
EOF
fi
export DMF_PATTERN_MANIFEST_PRIVATE="$PRIV_MANIFEST"

mkrepo() {  # mkrepo <dir> [content-file-body]
    mkdir -p "$1"
    git -C "$1" init -q -b main
    git -C "$1" config user.email "test@example.com"
    git -C "$1" config user.name "test"
    printf '%s\n' "${2:-benign}" > "$1/note.txt"
    git -C "$1" add -A
    git -C "$1" commit -qm fixture
}

# A fixture repo that CARRIES the scan tooling (for the hook rows: the hooks
# resolve bin/dmf-scan from the repo being committed).
mk_toolrepo() {
    local d="$1"
    mkdir -p "$d/bin/lib" "$d/patterns" "$d/.githooks"
    cp "$UMBRELLA_DIR/bin/dmf-scan" "$d/bin/"
    cp "$UMBRELLA_DIR/bin/gen-gitleaks-rules.py" "$d/bin/"
    cp "$UMBRELLA_DIR/bin/lib/dmf_scan.py" "$UMBRELLA_DIR/bin/lib/dmf_scan_selftest.py" "$d/bin/lib/"
    cp "$UMBRELLA_DIR/patterns/public-manifest.toml" "$d/patterns/"
    cp "$UMBRELLA_DIR/.gitleaks.toml" "$d/"
    cp "$UMBRELLA_DIR/.githooks/pre-commit" "$UMBRELLA_DIR/.githooks/pre-push" "$d/.githooks/"
    mkrepo "$d"
}

echo "── row 1: pre-commit caller (staged surface)"
tool="$WORK/toolrepo"
mk_toolrepo "$tool"
printf 'token = %s\n' "$SENTINEL" > "$tool/leak.txt"
git -C "$tool" add leak.txt
if (cd "$tool" && bash .githooks/pre-commit >/dev/null 2>&1); then
    bad "row 1: pre-commit accepted a staged public sentinel"
else
    ok "row 1: pre-commit refuses a staged public sentinel"
fi
git -C "$tool" rm -q --cached leak.txt && rm -f "$tool/leak.txt"
printf 'marker = %s\n' "$PRIV_MARK" > "$tool/priv.txt"
git -C "$tool" add priv.txt
out="$(cd "$tool" && bash .githooks/pre-commit 2>&1)" && rc=0 || rc=$?
if [ "$rc" -ne 0 ]; then
    ok "row 1: pre-commit refuses a staged private-tier value"
else
    bad "row 1: pre-commit accepted a staged private-tier value"
fi
if printf '%s' "$out" | grep -qF "$PRIV_MARK"; then
    bad "row 1: private value leaked through the pre-commit caller output"
else
    ok "row 1: private value redacted through the pre-commit caller"
fi
git -C "$tool" rm -q --cached priv.txt && rm -f "$tool/priv.txt"

echo "── row 2: pre-push caller (range surface)"
printf 'token = %s\n' "$SENTINEL" > "$tool/pushleak.txt"
git -C "$tool" add pushleak.txt
git -C "$tool" -c user.email=test@example.com -c user.name=test commit -qm "leaky"
sha="$(git -C "$tool" rev-parse HEAD)"
ZERO="0000000000000000000000000000000000000000"
if (cd "$tool" && printf 'refs/heads/main %s refs/heads/main %s\n' "$sha" "$ZERO" \
        | bash .githooks/pre-push origin ssh://example.invalid/r.git >/dev/null 2>&1); then
    bad "row 2: pre-push accepted a pushed commit carrying the sentinel"
else
    ok "row 2: pre-push refuses a pushed commit carrying the sentinel"
fi

echo "── row 3: scrub caller (tree surface)"
leaky="$WORK/leaky"; mkrepo "$leaky" "token = $SENTINEL"
clean="$WORK/clean"; mkrepo "$clean"
privleak="$WORK/privleak"; mkrepo "$privleak" "marker $PRIV_MARK here"
bash "$UMBRELLA_DIR/bin/scrub-public-repos.sh" --tree "$leaky" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 1 ] && ok "row 3: scrub catches the sentinel (exit 1)" \
                || bad "row 3: scrub rc=$rc for a seeded sentinel (want 1)"
bash "$UMBRELLA_DIR/bin/scrub-public-repos.sh" --tree "$clean" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 0 ] && ok "row 3: scrub passes a clean tree" \
                || bad "row 3: scrub rc=$rc on a clean tree (want 0)"
out="$(bash "$UMBRELLA_DIR/bin/scrub-public-repos.sh" --tree "$privleak" 2>&1)" && rc=0 || rc=$?
[ "$rc" -eq 1 ] && ok "row 3: scrub catches the private-tier value (exit 1)" \
                || bad "row 3: scrub rc=$rc for a private-tier value (want 1)"
if printf '%s' "$out" | grep -qF "$PRIV_MARK"; then
    bad "row 3: private value leaked through the scrub caller output"
else
    ok "row 3: private value redacted through the scrub caller"
fi

echo "── row 4: export-scan caller (orphan export surface)"
fx="$WORK/fx"
mk_toolrepo "$fx"
# governance + hygiene artifacts export-scan and its gates require
mkdir -p "$fx/.github"
for f in CONTRIBUTING.md SECURITY.md LICENSE NOTICE .gitignore .github/CODEOWNERS; do
    printf 'fixture\n' > "$fx/$f"
done
echo "0.0.0-test" > "$fx/VERSION"
cp "$UMBRELLA_DIR/bin/export-scan.sh" "$UMBRELLA_DIR/bin/scrub-public-repos.sh" \
   "$UMBRELLA_DIR/bin/check-public-repo-hygiene.sh" \
   "$UMBRELLA_DIR/bin/check-public-commit-authors.sh" "$fx/bin/"
cp "$UMBRELLA_DIR/bin/lib/dmf-repo-detect.sh" "$fx/bin/lib/"
printf 'token = %s\n' "$SENTINEL" > "$fx/leak.txt"
git -C "$fx" add -A
git -C "$fx" -c user.email=test@example.com -c user.name=test commit -qm "fixture umbrella"
es_out="$(UMBRELLA_DIR="$fx" EXPORT_ROOT="$WORK/es-out" bash "$fx/bin/export-scan.sh" . 2>&1)" && rc=0 || rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$es_out" | grep -q "GATES FAILED"; then
    ok "row 4: export-scan gates FAIL on a seeded sentinel in the export"
else
    bad "row 4: export-scan rc=$rc without gate failure (sentinel missed?)"
fi

echo "── row 5: dmf-env surface gate caller"
envfx="$WORK/envfx"
mkdir -p "$envfx"
git -C "$envfx" init -q -b main
git -C "$envfx" config user.email "test@example.com"
git -C "$envfx" config user.name "test"
printf 'fixture readme with token = %s\n' "$SENTINEL" > "$envfx/README.md"
git -C "$envfx" add -A && git -C "$envfx" commit -qm fixture
if bash "$UMBRELLA_DIR/bin/dmf-env-public-surface-gate.sh" "$envfx" >/dev/null 2>&1; then
    bad "row 5: env-gate passed a tree carrying the sentinel"
else
    ok "row 5: env-gate fails a tree carrying the sentinel"
fi

echo "── rows 10/11: fail-closed + opt-out authorization through the scrub caller"
DMF_PATTERN_MANIFEST_PRIVATE="/nonexistent/private.toml" \
    bash "$UMBRELLA_DIR/bin/scrub-public-repos.sh" --tree "$clean" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] && ok "row 10: missing private manifest → CONFIG_ERROR (exit 3)" \
                || bad "row 10: rc=$rc for a missing private manifest (want 3)"
DMF_SCAN_PUBLIC_ONLY=1 \
    bash "$UMBRELLA_DIR/bin/scrub-public-repos.sh" --tree "$clean" >/dev/null 2>&1; rc=$?
[ "$rc" -eq 3 ] && ok "row 11: DMF_SCAN_PUBLIC_ONLY spoof → CONFIG_ERROR (exit 3)" \
                || bad "row 11: rc=$rc for the public-only spoof (want 3)"

echo "acceptance-matrix: ${pass} passed, ${fail} failed$([ "$PRIVATE_MODE" = 1 ] && echo ' (private mode)')"
[ "$fail" -eq 0 ]
