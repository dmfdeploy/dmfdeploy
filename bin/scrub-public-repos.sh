#!/usr/bin/env bash
# scrub-public-repos.sh — pre-publish secret + topology + identity scan.
#
# THIN CALLER of the shared scan library (R1 spec §6; switchover §9 step 4):
# this wrapper owns only its scan surface — which repos/trees to scan — and
# HARDCODES its trust context. Patterns live in the manifests
# (patterns/public-manifest.toml + the operator-local private manifest);
# bin/dmf-scan owns loading, allowlists, redaction, and failure classes.
#
# Usage:
#   bin/scrub-public-repos.sh                 # scan all public repos
#   bin/scrub-public-repos.sh dmf-infra       # scan one repo
#   bin/scrub-public-repos.sh --tree <dir>    # scan one tree (e.g. export scratch)
#   bin/scrub-public-repos.sh --strict        # informational entries also block
#
# Env:
#   SCRUB_NO_ALLOWLIST=1   disable path allowlists (raw pre-publish sweep)
#   DMF_PATTERN_MANIFEST_PRIVATE  override the private manifest path
#
# FAIL-CLOSED (spec §5.3): a missing/unreadable private manifest is a hard
# CONFIG_ERROR, never a warn-and-continue. There is no public-only escape in
# this context (§5.4).
#
# Exit classes (§5.5): 0 clean; 1 LEAK_FOUND; 3 CONFIG_ERROR; 4 DRIFT_ERROR.

set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
# shellcheck source=bin/lib/dmf-repo-detect.sh
. "$UMBRELLA_DIR/bin/lib/dmf-repo-detect.sh"
PUBLIC_REPOS_DEFAULT=(. dmf-cms dmf-runbooks dmf-central dmf-infra dmf-media dmf-init dmf-env dmf-promsd)

# Resolve a repo entry to a filesystem path: an absolute path or one containing a
# slash (e.g. an export scratch via --tree) is used directly; a bare name resolves
# to the sibling checkout beside the umbrella (legacy nested checkouts still work).
repo_path() {
    case "$1" in
        .)      printf '%s' "$UMBRELLA_DIR" ;;
        /*|*/*) printf '%s' "$1" ;;
        *)      if [ -e "$UMBRELLA_DIR/$1/.git" ]; then printf '%s' "$UMBRELLA_DIR/$1"
                else printf '%s' "$(dirname "$UMBRELLA_DIR")/$1"; fi ;;
    esac
}

STRICT=0
TREE_PATH=""
POSITIONAL=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --strict) STRICT=1; shift ;;
        --tree)   TREE_PATH="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) POSITIONAL+=("$1"); shift ;;
    esac
done

DEFAULT_SWEEP=0
if [ -n "$TREE_PATH" ]; then
    PUBLIC_REPOS=("$TREE_PATH")
elif [ "${#POSITIONAL[@]}" -gt 0 ]; then
    PUBLIC_REPOS=("${POSITIONAL[@]}")
else
    PUBLIC_REPOS=("${PUBLIC_REPOS_DEFAULT[@]}")
    DEFAULT_SWEEP=1
fi

SCAN_ARGS=(--context scrub)
[ "$STRICT" -eq 1 ] && SCAN_ARGS+=(--strict)
# Honor the historical env name for the raw no-allowlist sweep (WP17).
[ "${SCRUB_NO_ALLOWLIST:-0}" = "1" ] && SCAN_ARGS+=(--no-allowlist)

worst=0
bump() { [ "$1" -gt "$worst" ] && worst="$1"; return 0; }

for repo in "${PUBLIC_REPOS[@]}"; do
    rpath="$(repo_path "$repo")"
    rname="$repo"
    [ "$repo" = "." ] && rname="dmfdeploy (umbrella)"
    if ! dmf_is_repo_root "$rpath"; then
        if [ "$DEFAULT_SWEEP" -eq 1 ]; then
            # Partial sibling checkouts are normal in the default sweep — but
            # say so loudly instead of the old silent skip.
            echo "── $rname: SKIPPED (no repo at $rpath)"
            continue
        fi
        echo "── $rname: not a git repo root: $rpath" >&2
        bump 3
        continue
    fi
    echo "── $rname"
    "$UMBRELLA_DIR/bin/dmf-scan" tree "$rpath" "${SCAN_ARGS[@]}" | sed 's/^/  /'
    rc="${PIPESTATUS[0]}"
    [ "$rc" -ne 0 ] && bump "$rc"
done

# Soft check: surface ignored-but-tracked artifacts (e.g. .DS_Store, *.tfstate
# that slipped past .gitignore). Informational only — the scan above is the
# real gate; this just makes accidents visible.
echo "── ignored-but-tracked artifacts (informational)"
ign_hits=0
for repo in "${PUBLIC_REPOS[@]}"; do
    rpath="$(repo_path "$repo")"
    dmf_is_repo_root "$rpath" || continue
    rname="$repo"
    [ "$repo" = "." ] && rname="dmfdeploy (umbrella)"
    leaked="$(git -C "$rpath" ls-files --cached --ignored --exclude-standard 2>/dev/null || true)"
    if [ -n "$leaked" ]; then
        count="$(printf '%s\n' "$leaked" | wc -l | tr -d ' ')"
        echo "  [$rname] $count ignored-but-tracked file(s)"
        printf '%s\n' "$leaked" | sed 's/^/      /' | head -5
        [ "$count" -gt 5 ] && echo "      ... ($((count - 5)) more)"
        ign_hits=$((ign_hits + 1))
    fi
done
[ "$ign_hits" -eq 0 ] && echo "  (clean)"
echo

echo "── summary"
case "$worst" in
    0) echo "  OK — clean for public publish"; exit 0 ;;
    1) echo "  FAIL — leaks found; address before publish" >&2; exit 1 ;;
    *) echo "  FAIL — scan could not run cleanly (class $worst); fix the environment, never the patterns" >&2
       exit "$worst" ;;
esac
