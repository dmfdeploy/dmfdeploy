#!/usr/bin/env bash
# scrub-public-repos.sh — pre-publish secret + topology + identity scan.
#
# Searches the tracked content of every public DMF Platform repo for
# strings that must not go public. Four categories:
#
#   1. Secrets / credentials  (BLOCKING — fail fast)
#   2. Internal topology      (BLOCKING — fail fast)
#   3. Operator identity      (BLOCKING — fail fast)
#   4. Operational context    (informational unless --strict)
#
# Plus a soft check that surfaces ignored-but-tracked files (e.g. .DS_Store
# slips that bypass .gitignore).
#
# Run before pushing any repo to a public mirror, and as part of the
# pre-receive hook on the LAN Forgejo (planned).
#
# Usage:
#   bin/scrub-public-repos.sh                 # scan all public repos
#   bin/scrub-public-repos.sh dmf-infra       # scan one repo
#   bin/scrub-public-repos.sh --strict        # also fail on context matches
#
# Exits 0 if clean (per chosen severity), 1 otherwise.
#
# Adding a pattern: append a "regex|short description" entry to the
# matching array. PCRE syntax (git grep -nP).

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
            sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
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

# === Pattern catalog ====================================================

# Real secret shapes — any match is an incident.
SECRET_PATTERNS=(
    '-----BEGIN.+PRIVATE KEY-----|PEM-armored private key'
    'https?://[^/\s:]+:[^@\s<][^@\s]{3,}@|credentials embedded in URL'
    '\bdev:changeme\b|known dev:changeme cred (LAN Forgejo dev creds)'
    '\bhvs\.[A-Za-z0-9_-]{20,}|Vault HMAC token'
    '\bhvb\.[A-Za-z0-9_-]{20,}|Vault batch/service token'
    '\bAKIA[0-9A-Z]{16}\b|AWS access key id'
    '\bghp_[A-Za-z0-9]{36}\b|GitHub personal access token'
    '\bglpat-[A-Za-z0-9_-]{20}|GitLab personal access token'
    '\bxoxb-[A-Za-z0-9-]{20,}|Slack bot token'
    '"client_token"\s*:\s*"[a-z0-9-]{20,}"|Vault/bao client_token literal'
    '"secret_id"\s*:\s*"[a-z0-9-]{20,}"|AppRole secret_id literal'
    '\bage1[0-9a-z]{58}\b|SOPS age recipient (public key, operator-setup fingerprint)'
    'AGE-SECRET-KEY-1[0-9A-Z]{58}|SOPS age secret key (identity)'
)

# Internal topology + operator identity — the concrete literals are
# OPERATOR-PRIVATE and live outside every repo, in an operator-local
# include (default ~/.dmfdeploy/scrub-private-patterns.sh, override with
# DMF_SCRUB_PRIVATE_PATTERNS). The public tree carries only the mechanism:
# publishing the patterns would publish what they protect. The include
# defines DMF_PRIVATE_IDENTITY_PATTERNS / DMF_PRIVATE_TOPOLOGY_PATTERNS
# ('PCRE|description' entries) and is mirrored by .gitleaks.local.toml —
# keep the two in lock-step.
TOPOLOGY_PATTERNS=()
IDENTITY_PATTERNS=(
    '\.DS_Store|macOS metadata leaked into tracked tree'
)
PRIVATE_PATTERNS_FILE="${DMF_SCRUB_PRIVATE_PATTERNS:-$HOME/.dmfdeploy/scrub-private-patterns.sh}"
if [ -f "$PRIVATE_PATTERNS_FILE" ]; then
    # shellcheck source=/dev/null
    . "$PRIVATE_PATTERNS_FILE"
    IDENTITY_PATTERNS+=("${DMF_PRIVATE_IDENTITY_PATTERNS[@]}")
    TOPOLOGY_PATTERNS+=("${DMF_PRIVATE_TOPOLOGY_PATTERNS[@]}")
else
    echo "WARN: operator-private patterns not found at $PRIVATE_PATTERNS_FILE —" >&2
    echo "      identity/topology categories run generic checks only." >&2
fi

# Operational context — DNS-discoverable, generally OK to mention in docs
# but worth flagging in case a stricter posture is wanted.
#
# 2026-05-19: the operator lab/headscale hostnames moved to IDENTITY
# (operator treats the custom domain stem + TLD as identity, not context);
# since 2026-06-11 they live in the operator-local include.
CONTEXT_PATTERNS=(
)

# === Scan logic =========================================================

# Allowlist: paths (basic regex) that intentionally reference a pattern
# as part of meta content (the script itself, the gitleaks config, docs
# that explicitly call out a smell). Hits in these paths are suppressed.
ALLOWLIST_PATHS=(
    'bin/scrub-public-repos\.sh'
    'bin/check-public-commit-authors\.sh'
    'bin/dmf-env-public-surface-gate\.sh'
    'bin/export-scan\.sh'
    '(^|/)\.gitignore$'
    '(^|/)\.helmignore$'
    # CODEOWNERS must name the repo owner's GitHub handle (@znerol2); that
    # handle is the public account that owns the published repos, so it is
    # intentionally public, not a leak. The same adjudication covers the
    # export/author tooling and the workstream specs below: they reference
    # the public handle functionally (commit identity, org setup).
    # NB: .gitleaks.toml is allowlisted since 2026-06-11 — it is public-safe
    # by construction now (identity/topology rules moved to the gitignored
    # .gitleaks.local.toml); regressions into it are caught at commit time
    # by the pre-commit second pass running the local rules.
    '(^|/)\.gitleaks\.toml$'
    '(^|/)\.github/CODEOWNERS$'
    # The pattern manifest is the source the gitleaks rules region + the
    # dmf-scan grep passes are generated from: its synthetic canaries match
    # the very rules it defines, by design. Public-safe by construction
    # (shapes only — never operator values); same adjudication as the
    # .gitleaks.toml allowlisting above. Keep in lock-step with the
    # manifest's [scan].allowlist_paths (checked by bin/check-pattern-parity.py).
    '(^|/)patterns/public-manifest\.toml$'
    'docs/plans/DMF Workstream A .*Spec 2026-06-09\.md'
    'docs/plans/DMF Workstream B .*Scrub Spec 2026-06-09\.md'
    'docs/plans/DMF Workstream D .*Governance Execution Spec 2026-06-09\.md'
    'docs/reviews/dmf-mxl-upstream-profile-and-contribution-review-2026-06-01\.md'
    '(^|/)docs/DEVELOPMENT-AND-BUILD-RULES\.md$'
    '(^|/)docs/decisions/[0-9]+'
    'docs/architecture/DMF Release and Contribution Model\.md'
    'docs/plans/DMF Release and Contribution Model Implementation Plan 2026-05-11\.md'
    'docs/reviews/dmf-move1-gate2-ssh-credential-incident-2026-05-05\.md'
    'docs/plans/DMF Public Repo Identity Leak Sweep 2026-05-11\.md'
    'docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07\.md'
    'k3s-lab-bootstrap/docs/repo-strategy\.md'
)

is_allowlisted() {
    # SCRUB_NO_ALLOWLIST=1 disables the allowlist entirely — used by the
    # pre-publish raw sweep (every hit adjudicated by hand, WP17).
    if [ "${SCRUB_NO_ALLOWLIST:-0}" = "1" ]; then
        return 1
    fi
    local file="$1"
    local pat
    for pat in "${ALLOWLIST_PATHS[@]}"; do
        if printf '%s' "$file" | grep -qE "$pat"; then
            return 0
        fi
    done
    return 1
}

scan_category() {
    local title="$1" fail_on_hit="$2"
    shift 2
    local cat_hits=0

    echo "── $title"
    for repo in "${PUBLIC_REPOS[@]}"; do
        local rpath; rpath="$(repo_path "$repo")"
        if ! dmf_is_repo_root "$rpath"; then
            continue
        fi
        local rname="$repo"
        [ "$repo" = "." ] && rname="dmfdeploy (umbrella)"

        for entry in "$@"; do
            local rx="${entry%%|*}"
            local desc="${entry#*|}"
            local results
            results="$(git -C "$rpath" grep -nP "$rx" 2>/dev/null || true)"
            [ -z "$results" ] && continue

            # Filter allowlisted paths out
            local filtered=""
            while IFS= read -r line; do
                local file_part="${line%%:*}"
                if is_allowlisted "$file_part"; then
                    continue
                fi
                filtered="${filtered:+$filtered$'\n'}$line"
            done <<< "$results"
            [ -z "$filtered" ] && continue

            cat_hits=$((cat_hits + 1))
            local count
            count="$(printf '%s\n' "$filtered" | wc -l | tr -d ' ')"
            echo "  [$rname] $desc — $count match(es)"
            printf '%s\n' "$filtered" | sed 's/^/      /' | head -5
            [ "$count" -gt 5 ] && echo "      ... ($((count - 5)) more)"
        done
    done
    [ "$cat_hits" -eq 0 ] && echo "  (clean)"
    echo

    if [ "$fail_on_hit" -eq 1 ] && [ "$cat_hits" -gt 0 ]; then
        return 1
    fi
    return 0
}

failures=0
scan_category "1. Secrets / credentials  (BLOCKING)" 1 "${SECRET_PATTERNS[@]}" \
    || failures=$((failures + 1))
if [ "${#TOPOLOGY_PATTERNS[@]}" -eq 0 ]; then
    echo "── 2. Internal topology      (BLOCKING)"
    echo "  (skipped — operator-private patterns not installed)"
    echo
else
    scan_category "2. Internal topology      (BLOCKING)" 1 "${TOPOLOGY_PATTERNS[@]}" \
        || failures=$((failures + 1))
fi
scan_category "3. Operator identity      (BLOCKING)" 1 "${IDENTITY_PATTERNS[@]}" \
    || failures=$((failures + 1))
if [ "${#CONTEXT_PATTERNS[@]}" -eq 0 ]; then
    echo "── 4. Operational context    ($([ $STRICT -eq 1 ] && echo BLOCKING || echo informational))"
    echo "  (clean)"
    echo
else
    scan_category "4. Operational context    ($([ $STRICT -eq 1 ] && echo BLOCKING || echo informational))" \
        "$STRICT" "${CONTEXT_PATTERNS[@]}" \
        || failures=$((failures + 1))
fi

# Soft check: surface ignored-but-tracked artifacts (e.g. .DS_Store, *.tfstate
# that slipped past .gitignore). Informational only — gitleaks + the BLOCKING
# categories above are the real gate; this just makes accidents visible.
echo "── ignored-but-tracked artifacts (informational)"
ign_hits=0
for repo in "${PUBLIC_REPOS[@]}"; do
    rpath="$(repo_path "$repo")"
    if ! dmf_is_repo_root "$rpath"; then
        continue
    fi
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
if [ "$failures" -eq 0 ]; then
    echo "  OK — clean for public publish"
    exit 0
fi
echo "  FAIL — $failures category(ies) need to be addressed before publish" >&2
exit 1
