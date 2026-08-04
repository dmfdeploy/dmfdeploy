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

# G: --staged must read the INDEX, not the worktree. Stage a leaking file, then
# delete it from the worktree: the commit would still carry the leak from the
# index, so a gate that consults the worktree reports clean while the leak
# lands. This is the exact skip an earlier `[ -f <worktree path> ]` guard
# created.
G="$WORK/staged"; rm -rf "$G"; mkdir -p "$G"
git -C "$G" init --quiet 2>/dev/null
git -C "$G" config user.email t@e; git -C "$G" config user.name t
printf 'doc naming env %s\n' "$FIXTURE_ID" > "$G/leak.md"
git -C "$G" add leak.md 2>/dev/null
rm -f "$G/leak.md"                     # staged, but absent from the worktree
rc_staged="$(DMF_DATA_ROOT="$WORK/store" UMBRELLA_DIR="$G" "$GATE" --staged >/dev/null 2>&1; echo $?)"
if [ "$rc_staged" = "1" ]; then
    ok "G: --staged reads the index, catching a worktree-deleted staged leak"
else
    bad "G: FAIL-OPEN — staged leak missed when absent from the worktree (exit $rc_staged)"
fi

# H: an UNREADABLE env store must exit 2, never read as an empty list. The
# fail-open here was concrete: find's stderr was discarded inside a process
# substitution, so a store the gate could not read derived zero identifiers and
# a leaking tree passed clean. Skipped as root, where mode 000 still reads.
if [ "$(id -u)" = "0" ]; then
    echo "  · H skipped: running as root, mode 000 is still readable"
else
    # a leaking tree, so a regression would surface as exit 0 or 1 — never 2
    printf 'doc naming env %s\n' "$FIXTURE_ID" > "$WORK/tree/dirty.md"
    git -C "$WORK/tree" add -A 2>/dev/null
    chmod 000 "$WORK/store/envs"
    rc_h="$(rc "$WORK/store")"
    chmod 755 "$WORK/store/envs"
    if [ "$rc_h" = "2" ]; then
        ok "H: unreadable env store fails closed (exit 2)"
    else
        bad "H: FAIL-OPEN — unreadable store read as empty (exit $rc_h)"
    fi
    rm -f "$WORK/tree/dirty.md"; git -C "$WORK/tree" add -A 2>/dev/null
fi

# I: --tree on a directory that is not a git repository must exit 2. git grep
# fails there (exit >=2); swallowing that reported an unscannable tree as clean.
mkdir -p "$WORK/plain"; printf 'doc naming env %s\n' "$FIXTURE_ID" > "$WORK/plain/x.md"
rc_i="$(DMF_DATA_ROOT="$WORK/store" "$GATE" --tree "$WORK/plain" >/dev/null 2>&1; echo $?)"
[ "$rc_i" = "2" ] && ok "I: unscannable tree fails closed (exit 2)" \
                  || bad "I: non-repo tree reported clean (exit $rc_i)"

# J: --staged outside a repository must exit 2 — enumeration failure is not
# an empty stage.
rc_j="$(DMF_DATA_ROOT="$WORK/store" UMBRELLA_DIR="$WORK/plain" "$GATE" --staged >/dev/null 2>&1; echo $?)"
[ "$rc_j" = "2" ] && ok "J: staged enumeration failure fails closed (exit 2)" \
                  || bad "J: staged outside a repo reported clean/empty (exit $rc_j)"

# ctrl: a missing store must ANNOUNCE the skip, not pass silently.
out="$(run "$WORK/nonexistent")"
if printf '%s' "$out" | grep -qi 'no env store'; then
    ok "ctrl: missing env store is announced, not silent"
else
    bad "ctrl: missing env store skipped silently"
fi

echo "live-env-leak: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
