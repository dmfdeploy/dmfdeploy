#!/usr/bin/env bash
# live-env-leak.sh — regressions for the live-environment-identifier gate
# (umbrella issue #361).
#
#   A  an identifier present in the scanned content is DETECTED
#   B  content without one passes (no false positive)
#   C  the identifier is NEVER printed in the failure output — a gate that
#      echoes the value into a log or transcript defeats itself
#   D  the pattern is DERIVED from the env store at run time, not baked in:
#      adding an env to the store makes a previously-clean file fail, with no
#      edit to the gate. This is the property that keeps it from going stale
#      when an env rotates.
#   E  an env store that exists but is empty matches nothing (no wildcard)
#   ctrl  a missing env store is ANNOUNCED, not silently treated as clean
#
# Hermetic: builds a fixture env store and points DMF_DATA_ROOT at it, so it
# never reads operator state and runs identically in CI.
set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
GATE="$UMBRELLA_DIR/bin/check-live-env-leak.sh"
pass=0; fail=0
ok()  { echo "  ✓ $1"; pass=$((pass + 1)); }
bad() { echo "  ✗ $1" >&2; fail=$((fail + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dmf-live-env-leak.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

FIXTURE_ID="zzzz-9999"     # synthetic; shaped like a real id, belongs to no env
OTHER_ID="yyyy-8888"
mkdir -p "$WORK/store/envs/$FIXTURE_ID"
mkdir -p "$WORK/tree"
git -C "$WORK/tree" init --quiet 2>/dev/null
printf 'a doc mentioning env %s in prose\n' "$FIXTURE_ID" > "$WORK/tree/dirty.md"
printf 'a doc mentioning env <env> in prose\n' > "$WORK/tree/clean.md"
git -C "$WORK/tree" add -A 2>/dev/null

run() { DMF_DATA_ROOT="$1" "$GATE" --tree "$WORK/tree" 2>&1; }
rc()  { DMF_DATA_ROOT="$1" "$GATE" --tree "$WORK/tree" >/dev/null 2>&1; echo $?; }

echo "live-env-leak gate regressions (issue #361)"

[ "$(rc "$WORK/store")" = "1" ] && ok "A: identifier in content is detected" \
                                || bad "A: identifier NOT detected"

out="$(run "$WORK/store")"
if printf '%s' "$out" | grep -q "$FIXTURE_ID"; then
    bad "C: failure output LEAKS the identifier"
else
    ok "C: identifier never printed in the failure output"
fi

# B: remove the offending file; the same store must now pass.
rm -f "$WORK/tree/dirty.md"; git -C "$WORK/tree" add -A 2>/dev/null
[ "$(rc "$WORK/store")" = "0" ] && ok "B: clean content passes (no false positive)" \
                                || bad "B: false positive on clean content"

# D: derivation. Re-add a file naming a DIFFERENT id — clean until that id
# exists in the store, failing once it does, with no change to the gate.
printf 'another doc naming env %s\n' "$OTHER_ID" > "$WORK/tree/other.md"
git -C "$WORK/tree" add -A 2>/dev/null
before="$(rc "$WORK/store")"
mkdir -p "$WORK/store/envs/$OTHER_ID"
after="$(rc "$WORK/store")"
if [ "$before" = "0" ] && [ "$after" = "1" ]; then
    ok "D: pattern derived from the store at run time (rotation-safe)"
else
    bad "D: derivation not live (before=$before after=$after, expected 0 then 1)"
fi

# E: an empty store must match nothing rather than everything.
mkdir -p "$WORK/empty/envs"
[ "$(rc "$WORK/empty")" = "0" ] && ok "E: empty env store matches nothing" \
                                || bad "E: empty store produced matches"

# ctrl: a missing store must ANNOUNCE the skip, not pass silently.
out="$(run "$WORK/nonexistent")"
if printf '%s' "$out" | grep -qi 'no env store'; then
    ok "ctrl: missing env store is announced, not silent"
else
    bad "ctrl: missing env store skipped silently"
fi

echo "live-env-leak: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
