#!/usr/bin/env bash
# check-public-commit-authors.sh — verify every commit author/committer on
# every public DMF Platform repo matches the public-identity allowlist.
#
# Commit metadata (author name, author email, committer name, committer
# email) is visible on the public GitHub mirror once a push lands. Even
# with a clean tree, `git log --pretty='%an <%ae>'` can leak operator
# username + device hostname (e.g. `<operator-name> <<operator>@<operator-workstation>>`). This
# script is the last-mile gate before `bin/sync-to-github.sh` pushes.
#
# Usage:
#   bin/check-public-commit-authors.sh                # all public repos
#   bin/check-public-commit-authors.sh dmf-infra      # one repo
#
# Exits 0 if every author/committer on the scanned ref matches an entry
# in APPROVED_IDENTITIES (PCRE-flavored). Exits 1 otherwise.
#
# The scanned ref is `main` if it exists, else `HEAD`. The script does NOT
# walk into `archive/*` tags by design — pre-publish history stays LAN-only
# per the 2026-05-07 publish-readiness handoff Gate 1.

set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
PUBLIC_REPOS_DEFAULT=(. dmf-cms dmf-runbooks dmf-central dmf-infra dmf-media dmf-init dmf-env dmf-promsd)

# Resolve a repo entry to a path: absolute / slash-containing (e.g. --tree scratch)
# used directly; bare name relative to UMBRELLA_DIR.
repo_path() {
    case "$1" in
        .)      printf '%s' "$UMBRELLA_DIR" ;;
        /*|*/*) printf '%s' "$1" ;;
        *)      printf '%s' "$UMBRELLA_DIR/$1" ;;
    esac
}

# Approved identities. Regex-matched against `git log --pretty='%an <%ae>'`
# and `--pretty='%cn <%ce>'` (committer). Add a new entry only after
# explicit operator approval — these are the identities that will appear
# on the public GitHub mirror.
#
# Allowlist locked 2026-05-11 after the Phase 3 filter-branch rewrite
# (docs/plans/DMF Public Repo Identity Leak Sweep 2026-05-11.md):
# GitHub numeric user ID 6800371 is pinned. Loosening this regex to
# accept other IDs reopens the operator-identity leak surface; only
# extend if a second approved public identity becomes load-bearing.
APPROVED_IDENTITIES=(
    '^znerol2 <6800371\+znerol2@users\.noreply\.github\.com>$'
)

TREE_PATH=""
POSITIONAL=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --tree) TREE_PATH="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done

if [ -n "$TREE_PATH" ]; then
    PUBLIC_REPOS=("$TREE_PATH")
elif [ "${#POSITIONAL[@]}" -gt 0 ]; then
    PUBLIC_REPOS=("${POSITIONAL[@]}")
else
    PUBLIC_REPOS=("${PUBLIC_REPOS_DEFAULT[@]}")
fi

is_approved() {
    local entry="$1" rx
    for rx in "${APPROVED_IDENTITIES[@]}"; do
        if printf '%s' "$entry" | grep -qE "$rx"; then
            return 0
        fi
    done
    return 1
}

failures=0

for repo in "${PUBLIC_REPOS[@]}"; do
    rpath="$(repo_path "$repo")"
    if [ ! -d "$rpath/.git" ]; then
        continue
    fi
    rname="$repo"
    [ "$repo" = "." ] && rname="dmfdeploy (umbrella)"

    ref="main"
    if ! git -C "$rpath" rev-parse --verify "$ref" >/dev/null 2>&1; then
        ref="HEAD"
    fi

    # Collect unique (role:name <email>) tuples for both author and committer.
    identities=()
    while IFS= read -r line; do
        [ -n "$line" ] && identities+=("$line")
    done < <(
        {
            git -C "$rpath" log "$ref" --pretty='author:%an <%ae>'
            git -C "$rpath" log "$ref" --pretty='committer:%cn <%ce>'
        } | sort -u
    )

    repo_bad=0
    for ident in "${identities[@]}"; do
        ident_value="${ident#*:}"
        if ! is_approved "$ident_value"; then
            if [ "$repo_bad" -eq 0 ]; then
                echo "── $rname (ref: $ref)"
                repo_bad=1
            fi
            echo "  unapproved ${ident%%:*}: $ident_value"
        fi
    done
    [ "$repo_bad" -eq 1 ] && failures=$((failures + 1))
done

echo
if [ "$failures" -eq 0 ]; then
    echo "OK — every commit author/committer matches the public-identity allowlist"
    exit 0
fi
echo "FAIL — $failures repo(s) carry unapproved commit identities" >&2
echo "Approved identities (regex):" >&2
printf '  %s\n' "${APPROVED_IDENTITIES[@]}" >&2
exit 1
