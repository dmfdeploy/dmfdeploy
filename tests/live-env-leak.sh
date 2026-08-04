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

# K: a staged filename containing the old sed delimiter must not hide a leak.
# The prefix was once built as a sed program from the path, so 'a|b.md' broke
# the pipeline and the failed substitution reported a MATCHING blob as clean.
K="$WORK/pipe"; rm -rf "$K"; mkdir -p "$K"
git -C "$K" init --quiet 2>/dev/null
printf 'doc naming env %s\n' "$FIXTURE_ID" > "$K/a|b.md"
git -C "$K" add -A 2>/dev/null
rc_k="$(DMF_DATA_ROOT="$WORK/store" UMBRELLA_DIR="$K" "$GATE" --staged >/dev/null 2>&1; echo $?)"
[ "$rc_k" = "1" ] && ok "K: leak caught in a pipe-delimiter filename" \
                  || bad "K: FAIL-OPEN — pipe-named staged leak missed (exit $rc_k)"

# L: a staged TYPE CHANGE must be scanned. A symlink replaced by a regular
# file is a T entry; --diff-filter=ACMR omitted T, so that staged blob was
# committed without the gate enumerating its path.
L="$WORK/typechange"; rm -rf "$L"; mkdir -p "$L"
git -C "$L" init --quiet 2>/dev/null
git -C "$L" config user.email t@e 2>/dev/null; git -C "$L" config user.name t 2>/dev/null
ln -s /dev/null "$L/thing"
git -C "$L" add -A 2>/dev/null; git -C "$L" commit -qm init 2>/dev/null
rm "$L/thing"; printf 'doc naming env %s\n' "$FIXTURE_ID" > "$L/thing"
git -C "$L" add -A 2>/dev/null
rc_l="$(DMF_DATA_ROOT="$WORK/store" UMBRELLA_DIR="$L" "$GATE" --staged >/dev/null 2>&1; echo $?)"
[ "$rc_l" = "1" ] && ok "L: leak caught across a symlink-to-file type change" \
                  || bad "L: FAIL-OPEN — staged type change not scanned (exit $rc_l)"

# M: BINARY content must be scanned. grep -I treated a binary blob as clean,
# so an identifier embedded in an archive, image, or compiled artifact rode
# through. Output must still leak neither the identifier nor binary noise.
M="$WORK/binary"; rm -rf "$M"; mkdir -p "$M"
git -C "$M" init --quiet 2>/dev/null
printf 'BIN\x00HEAD env %s tail\x00\x01\n' "$FIXTURE_ID" > "$M/blob.bin"
git -C "$M" add -A 2>/dev/null
rc_m="$(DMF_DATA_ROOT="$WORK/store" "$GATE" --tree "$M" >/dev/null 2>&1; echo $?)"
out_m="$(DMF_DATA_ROOT="$WORK/store" "$GATE" --tree "$M" 2>&1)"
if [ "$rc_m" = "1" ] && ! printf '%s' "$out_m" | grep -qE "$FIXTURE_ID|HEAD"; then
    ok "M: leak caught in binary content, output still clean"
elif [ "$rc_m" != "1" ]; then
    bad "M: FAIL-OPEN — binary leak treated as clean (exit $rc_m)"
else
    bad "M: binary leak caught but the output echoed forbidden content"
fi

# N: an env-store path that exists as a FILE is malformed, not absent — the
# skip must not fire. [ -d ] alone read it as "no store" and exited 0.
mkdir -p "$WORK/rootN"; : > "$WORK/rootN/envs"
rc_n="$(DMF_DATA_ROOT="$WORK/rootN" "$GATE" --tree "$WORK/tree" >/dev/null 2>&1; echo $?)"
[ "$rc_n" = "2" ] && ok "N: malformed store (a file) fails closed, not skipped" \
                  || bad "N: FAIL-OPEN — file-shaped store skipped as absent (exit $rc_n)"

# O: a data root that exists but cannot be searched must fail closed — a real
# store with real identifiers can sit exactly behind it. Skipped as root.
if [ "$(id -u)" = "0" ]; then
    echo "  · O skipped: running as root, mode 000 is still searchable"
else
    mkdir -p "$WORK/rootO/envs/$FIXTURE_ID"
    chmod 000 "$WORK/rootO"
    rc_o="$(DMF_DATA_ROOT="$WORK/rootO" "$GATE" --tree "$WORK/tree" >/dev/null 2>&1; echo $?)"
    chmod 755 "$WORK/rootO"
    [ "$rc_o" = "2" ] && ok "O: unsearchable data root fails closed, not skipped" \
                      || bad "O: FAIL-OPEN — store behind a 000 root skipped as absent (exit $rc_o)"
fi

# P: the HOOK must surface the gate's skip announcements — both variants. The
# wiring once matched only "no env store", so an existing-but-empty store
# ("holds no envs") was a silent bypass. Hook-level: runs the real pre-commit
# from a fixture repo carrying the gate, since the hook skips repos without it.
HOOK="$UMBRELLA_DIR/.githooks/pre-commit"
PFIX="$WORK/hookfix"; rm -rf "$PFIX"; mkdir -p "$PFIX/bin"
git -C "$PFIX" init --quiet 2>/dev/null
cp "$GATE" "$PFIX/bin/check-live-env-leak.sh"; chmod +x "$PFIX/bin/check-live-env-leak.sh"
mkdir -p "$WORK/emptystore/envs"
p_out="$(cd "$PFIX" && DMF_DATA_ROOT="$WORK/emptystore" GITLEAKS_HOOK_QUIET=1 bash "$HOOK" 2>&1)"; p_rc=$?
if [ "$p_rc" = "0" ] && printf '%s' "$p_out" | grep -q 'holds no envs'; then
    ok "P: hook surfaces the empty-store skip announcement"
else
    bad "P: silent bypass — hook exit $p_rc, announcement absent"
fi

# Q: a file NAMED with a live identifier is a leak even with clean content —
# the name reaches the tree. And the refusal must REDACT the identifier from
# the reported path, or the report itself violates the no-print guarantee.
Q="$WORK/idname"; rm -rf "$Q"; mkdir -p "$Q"
git -C "$Q" init --quiet 2>/dev/null
printf 'perfectly clean content\n' > "$Q/${FIXTURE_ID}-notes.md"
git -C "$Q" add -A 2>/dev/null
rc_q="$(DMF_DATA_ROOT="$WORK/store" UMBRELLA_DIR="$Q" "$GATE" --staged >/dev/null 2>&1; echo $?)"
out_q="$(DMF_DATA_ROOT="$WORK/store" UMBRELLA_DIR="$Q" "$GATE" --staged 2>&1)"
if [ "$rc_q" = "1" ] && ! printf '%s' "$out_q" | grep -q "$FIXTURE_ID" \
   && printf '%s' "$out_q" | grep -q '<env>'; then
    ok "Q: id-named staged file caught, path redacted in the report"
elif [ "$rc_q" != "1" ]; then
    bad "Q: FAIL-OPEN — identifier-carrying filename passed (exit $rc_q)"
else
    bad "Q: caught, but the report echoed the identifier"
fi

# R: same rule in --tree mode.
R="$WORK/idname-tree"; rm -rf "$R"; mkdir -p "$R"
git -C "$R" init --quiet 2>/dev/null
printf 'clean\n' > "$R/${FIXTURE_ID}.cfg"
git -C "$R" add -A 2>/dev/null
rc_r="$(DMF_DATA_ROOT="$WORK/store" "$GATE" --tree "$R" >/dev/null 2>&1; echo $?)"
out_r="$(DMF_DATA_ROOT="$WORK/store" "$GATE" --tree "$R" 2>&1)"
if [ "$rc_r" = "1" ] && ! printf '%s' "$out_r" | grep -q "$FIXTURE_ID"; then
    ok "R: id-named file caught in tree mode, report redacted"
else
    bad "R: tree-mode filename leak (exit $rc_r) or identifier echoed"
fi

# ctrl: a missing store must ANNOUNCE the skip, not pass silently.
out="$(run "$WORK/nonexistent")"
if printf '%s' "$out" | grep -qi 'no env store'; then
    ok "ctrl: missing env store is announced, not silent"
else
    bad "ctrl: missing env store skipped silently"
fi

echo "live-env-leak: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
