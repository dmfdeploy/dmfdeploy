#!/usr/bin/env bash
# run.sh — fixture tests for bin/check-surface.sh. Every file under bad/ must
# make `--strict` exit non-zero, and every file under good/ must exit 0. The
# run exits non-zero on any mismatch or when a bad fixture has no good twin.
# A fixture under an enforcement/ directory runs the enforcement subcommand,
# which "all" leaves out while that rule warns (dmfdeploy/dmfdeploy#661).
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK="${CHECK_SURFACE:-$HERE/../../bin/check-surface.sh}"
fail=0

# sub_for FILE: the subcommand a fixture runs.
sub_for() {
    case "$1" in */enforcement/*) echo enforcement ;; *) echo all ;; esac
}

while IFS= read -r f; do
    if "$CHECK" --strict "$(sub_for "$f")" --file "$f" >/dev/null 2>&1; then
        echo "FAIL bad fixture passed: ${f#"$HERE"/}" >&2; fail=1
    else
        echo "ok   bad fixture rejected: ${f#"$HERE"/}"
    fi
done < <(find "$HERE/bad" -type f | LC_ALL=C sort)

while IFS= read -r f; do
    if "$CHECK" --strict "$(sub_for "$f")" --file "$f" >/dev/null 2>&1; then
        echo "ok   good twin accepted: ${f#"$HERE"/}"
    else
        echo "FAIL good twin rejected: ${f#"$HERE"/}" >&2; fail=1
    fi
done < <(find "$HERE/good" -type f | LC_ALL=C sort)

nb="$(find "$HERE/bad" -type f | wc -l | tr -d ' ')"
ng="$(find "$HERE/good" -type f | wc -l | tr -d ' ')"
if [ "$nb" -ne "$ng" ]; then
    echo "FAIL $nb bad fixtures but $ng good twins" >&2; fail=1
fi
exit "$fail"
