#!/usr/bin/env bash
# check-live-env-leak.sh — refuse content carrying a LIVE environment identifier
# (umbrella issue #361).
#
# WHY NOT A SHAPE RULE. Env ids are minted as 8 characters drawn uniformly from
# [a-z0-9], split 4-4 (dmf-env init-wizard gen_env_id). Measured against 20 known
# identifiers and 20 known non-identifiers already in the tree, no shape
# refinement separates them: the best variant still admits false positives AND
# misses a real identifier whose second half is all digits. A uniformly-random
# alphanumeric token is not distinguishable by shape from a meaningful one — that
# is a property of the generator, not of the regex. So this gate matches the
# identifiers that ACTUALLY EXIST rather than guessing at the class.
#
# THE PATTERN IS DERIVED AT GATE TIME, NEVER TYPED IN. A hand-maintained value
# goes blind the moment the env rotates, which is exactly how a scrub gate can
# report green while missing what it was built to catch. The identifier list is
# read from the operator-local env store on every run, so a new env is covered
# the moment it exists and a retired one drops out on teardown.
#
# It never PRINTS an identifier it finds — a gate that echoes the value into a
# log or a transcript defeats itself. Findings are reported as file:line.
#
# Usage:
#   bin/check-live-env-leak.sh --staged     # pre-commit: scan staged content
#   bin/check-live-env-leak.sh --tree [dir] # scan a working tree
#
# Exit: 0 clean, 1 leak found, 2 could not run (fail closed).
set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
DATA_ROOT="${DMF_DATA_ROOT:-$HOME/.dmfdeploy}"
ENVS_DIR="$DATA_ROOT/envs"
MODE="${1:---staged}"
TREE="${2:-$UMBRELLA_DIR}"

# ── derive the identifier list from live state ──────────────────────────────
# ABSENT and INACCESSIBLE are different verdicts, and [ -d ] alone conflates
# them: it is false for a store that truly does not exist, but equally for one
# sitting behind an unsearchable data root, or a path that exists as something
# other than a directory. Only genuine absence may skip; anything else means
# the gate cannot establish what the store holds and must refuse — a real
# store with a real identifier can sit exactly behind such a failure.
if [ -d "$ENVS_DIR" ]; then
    :  # store present — proceed to enumeration below
elif [ -e "$ENVS_DIR" ] || [ -L "$ENVS_DIR" ]; then
    echo "FAIL(2): $ENVS_DIR exists but is not a directory — a malformed env store" >&2
    echo "  is not an absent one. Refusing to skip." >&2
    exit 2
elif { [ -e "$DATA_ROOT" ] || [ -L "$DATA_ROOT" ]; } && { [ ! -d "$DATA_ROOT" ] || [ ! -x "$DATA_ROOT" ]; }; then
    # -L as well as -e: -e follows a symlink, so a DANGLING data-root link —
    # a store configured on a volume that is not mounted — reads as absent
    # and skipped. Configured-but-unavailable is inaccessible, not absent.
    echo "FAIL(2): $DATA_ROOT exists but cannot be searched — whether an env store" >&2
    echo "  is behind it cannot be established. Refusing to skip." >&2
    exit 2
else
    # No data root at all, or a searchable one with no envs/ inside: genuinely
    # no local env state. Announced rather than silent — a quiet skip is
    # indistinguishable from a clean run, which is the failure this whole gate
    # exists to avoid.
    echo "check-live-env-leak: no env store at $ENVS_DIR — nothing to derive, skipping."
    echo "  (this gate protects the machine that holds env state; CI cannot run it)"
    exit 0
fi

# The enumeration's own failure must be visible. An earlier revision piped find
# through a process substitution with stderr discarded, so an UNREADABLE env
# store produced an empty list and the gate exited 0 — a live identifier walked
# through because the gate could not look and said nothing about it. pipefail is
# set, so a find failure survives the sort.
store_list="$(find "$ENVS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)" || {
    echo "FAIL(2): cannot enumerate the env store at $ENVS_DIR — refusing to treat" >&2
    echo "  an unreadable store as an empty one. Fix permissions and retry." >&2
    exit 2
}

ids=()
while IFS= read -r d; do
    [ -n "$d" ] || continue
    ids+=("$(basename "$d")")
done <<< "$store_list"

if [ "${#ids[@]}" -eq 0 ]; then
    echo "check-live-env-leak: env store present but holds no envs — nothing to match."
    exit 0
fi

# Build one alternation. Identifiers are literal; no shape guessing.
pattern="$(printf '%s\n' "${ids[@]}" | paste -sd'|' -)"
[ -n "$pattern" ] || { echo "FAIL(2): derived an empty pattern from $ENVS_DIR" >&2; exit 2; }

# Scan errors must fail closed, and "no match" must not be conflated with
# "could not look". grep and git grep exit 1 for a clean no-match and >=2 for a
# real error, so the two are distinguished explicitly everywhere below — an
# earlier revision discarded these statuses, so a scan that could not run
# reported clean.
case "$MODE" in
    --staged)
        # ACMRT, not ACMR: T is a type change, e.g. a symlink replaced by a
        # regular file. That staged blob is committed like any other, and with
        # T omitted the gate enumerated no path for it — a leak rode through in
        # a shape the filter did not name.
        files="$(git -C "$UMBRELLA_DIR" diff --cached --name-only --diff-filter=ACMRT 2>/dev/null)" || {
            echo "FAIL(2): could not enumerate staged files in $UMBRELLA_DIR." >&2
            exit 2
        }
        [ -n "$files" ] || { echo "check-live-env-leak: nothing staged."; exit 0; }
        # Read the INDEX blob and nothing else. An earlier revision first
        # required the worktree path to be a regular file, which made the gate
        # skippable: stage a leaking file, delete it from the worktree, and the
        # commit still carries the leak from the index while the check reported
        # clean. The worktree is not what gets committed — the index is.
        # --diff-filter=ACMR already excludes deletions, so no guard is needed.
        # The loop runs in the MAIN shell, not a command-substitution subshell,
        # so a per-file read failure can abort the run instead of vanishing.
        hits=""
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            blob="$(git -C "$UMBRELLA_DIR" show ":$f" 2>/dev/null)" || {
                echo "FAIL(2): could not read the staged blob for '$f' — refusing to" >&2
                echo "  treat an unreadable file as a clean one." >&2
                exit 2
            }
            # -a, not -I: binary content is scanned too. A live identifier in
            # any committed byte is a leak — archives, images, compiled blobs
            # all carry embedded strings. Output stays file:line, so binary
            # noise (and the identifier itself) is never echoed.
            h="$(printf '%s\n' "$blob" | grep -naE "$pattern")" ; rc=$?
            if [ "$rc" -ge 2 ]; then
                echo "FAIL(2): scan error on the staged blob for '$f'." >&2
                exit 2
            fi
            # Prefix the filename in pure shell. An earlier revision built a sed
            # program from the path ("s|^|$f:|"), so a filename containing the
            # delimiter broke the pipeline — and the failed substitution yielded
            # an empty string, reporting a MATCHING blob as clean. Data must
            # never become program text.
            if [ "$rc" -eq 0 ]; then
                while IFS= read -r match_line; do
                    [ -n "$match_line" ] || continue
                    hits+="${f}:${match_line%%:*}"$'\n'
                done <<< "$h"
            fi
        done <<< "$files"
        # Filenames are content too: a file NAMED with a live identifier
        # carries it into the tree even when every byte inside is clean.
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            for _id in "${ids[@]}"; do
                case "$f" in *"$_id"*) hits+="${f} (the filename itself)"$'\n'; break ;; esac
            done
        done <<< "$files"
        hits="${hits%$'\n'}"
        ;;
    --tree)
        # -a, not -I: same binary policy as the staged mode above.
        h="$(git -C "$TREE" grep -naE "$pattern" -- . 2>/dev/null)" ; rc=$?
        if [ "$rc" -ge 2 ]; then
            echo "FAIL(2): git grep failed in $TREE (not a repository, or unreadable) —" >&2
            echo "  refusing to report a tree it could not scan as clean." >&2
            exit 2
        fi
        hits=""
        [ "$rc" -eq 0 ] && hits="$(printf '%s\n' "$h" | cut -d: -f1,2)"
        # Filenames are content too — same rule as the staged mode.
        names="$(git -C "$TREE" ls-files 2>/dev/null)" || {
            echo "FAIL(2): could not list tracked files in $TREE." >&2
            exit 2
        }
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            for _id in "${ids[@]}"; do
                case "$f" in *"$_id"*) hits+=$'\n'"${f} (the filename itself)"; break ;; esac
            done
        done <<< "$names"
        hits="${hits#$'\n'}"
        ;;
    *) echo "usage: $0 [--staged | --tree <dir>]" >&2; exit 2 ;;
esac

if [ -z "$hits" ]; then
    echo "check-live-env-leak: clean (${#ids[@]} live identifier(s) checked, derived from $ENVS_DIR)"
    exit 0
fi

echo "FAIL(1): a LIVE environment identifier appears in the content being committed." >&2
echo "  Public repos must not carry live-environment specifics. Redact to a" >&2
echo "  placeholder, keeping the surrounding rationale." >&2
echo "  Locations (the identifier itself is deliberately not printed):" >&2
# A reported PATH can itself contain an identifier — a file named after one —
# so every hit line is redacted before printing. Pure substitution: the
# identifier list never becomes program text.
for _id in "${ids[@]}"; do
    hits="${hits//"$_id"/<env>}"
done
printf '%s\n' "$hits" | sed 's/^/      /' >&2
exit 1
