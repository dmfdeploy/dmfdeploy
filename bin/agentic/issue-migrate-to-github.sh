#!/usr/bin/env bash
# MOTHBALLED 2026-06-04 (historical, fails closed): bin/agentic/issue-migrate-to-github.sh — operator-invoked migration of
# public-safe agent-opened Forgejo issues to GitHub at v0.1.0 publish.
#
# Never called by the loop. Runs only when:
#   - ADR-0020 is Accepted (Tier A.1 unblocked)
#   - sync-to-github.sh has pushed the corresponding repos
#   - The operator wants to expose the public-safe subset of agent work
#     to external contributors
#
# Pipeline:
#   1. For each agent-opened Forgejo issue NOT tagged `public-safe`:
#      - Re-scrub the body via gitleaks detect --no-git --source
#      - If clean: queue for tagging public-safe (operator confirms)
#      - If hits: tag stay-private, record reasons
#   2. For each public-safe issue:
#      - Build GitHub equivalent via `gh issue create`
#      - Mirror body, add `Mirror: forgejo#<repo>/<n>` line
#      - Add Forgejo comment: `migrated: gh#<n>`
#      - Forgejo issue stays open as canonical work record
#
# This is K4 SCAFFOLDING. The real migration step (gh issue create) is
# left as a dry-run-only path until the GitHub org exists (decision in
# decisions-open.md: github-org-name).
#
# Usage:
#   bin/agentic/issue-migrate-to-github.sh --dry-run    # show what would migrate
#   bin/agentic/issue-migrate-to-github.sh              # real migration
#                                                       # (refuses unless --confirm)
#   bin/agentic/issue-migrate-to-github.sh --confirm    # real migration
#
# Exit codes:
#   0 — migration planning succeeded (dry-run or real)
#   1 — preconditions not met (ADR-0020 not Accepted, no GitHub org, etc.)
#   2 — usage error
#
# Refs:
#   docs/plans/DMF Agentic Harness Plan 2026-05-11.md §Layer 4
#       "Migration to GitHub at v0.1.0 publish"

set -euo pipefail

if [[ "${DMF_AGENTIC_OVERRIDE:-}" != "1" ]]; then
    echo "mothballed 2026-06-04 — set DMF_AGENTIC_OVERRIDE=1 to run" >&2
    exit 1
fi

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=/dev/null
. "${UMBRELLA_DIR}/bin/agentic/forgejo.env"

DRY_RUN=0
CONFIRM=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1; shift ;;
        --confirm) CONFIRM=1; shift ;;
        -h|--help)
            sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

if [ "$DRY_RUN" = 0 ] && [ "$CONFIRM" = 0 ]; then
    echo "refusing real migration without --confirm; try --dry-run first" >&2
    exit 2
fi

# ── Precondition checks ──────────────────────────────────────────────────────

# 1. ADR-0020 must be Accepted.
ADR0020="${UMBRELLA_DIR}/docs/decisions"
if grep -rqE 'ADR-0020.*Accepted' "$ADR0020" 2>/dev/null; then
    echo "  ✓ ADR-0020 Accepted"
else
    echo "  ✗ ADR-0020 not yet Accepted — Tier A.1 still open" >&2
    echo "    Answer in docs/agentic/decisions-open.md first." >&2
    exit 1
fi

# 2. github CLI present.
if ! command -v gh >/dev/null 2>&1; then
    echo "  ✗ gh CLI not installed — migration requires \`brew install gh\`" >&2
    exit 1
fi

# 3. GITHUB_ORG decided.
GH_ORG="${DMF_GITHUB_ORG:-dmfdeploy}"
if [ "$GH_ORG" = "<placeholder>" ]; then
    echo "  ✗ GitHub org not configured — set DMF_GITHUB_ORG" >&2
    exit 1
fi

forgejo_validate_config || exit 2

# ── Iterate ──────────────────────────────────────────────────────────────────

TOKEN="$(cat "$FORGEJO_TOKEN_PATH")"
MIGRATE_QUEUE=()
PRIVATE_QUEUE=()

for repo in "${FORGEJO_PUBLIC_REPOS[@]}"; do
    api="https://${FORGEJO_HOST}/api/v1/repos/${FORGEJO_OWNER}/${repo}/issues?labels=agent-opened&state=open&type=issues"
    resp="$(curl -fsS -H "Authorization: token ${TOKEN}" "$api" 2>/dev/null)" || {
        echo "  ! Forgejo API error for ${repo}; skipping" >&2
        continue
    }

    while IFS=$'\t' read -r num title labels; do
        [ -z "$num" ] && continue
        if echo "$labels" | grep -qw 'public-safe'; then
            MIGRATE_QUEUE+=("${repo}#${num}: ${title}")
            continue
        fi

        # Re-scrub body.
        body_tmp=$(mktemp -t migrate.XXXXXX)
        echo "$resp" | python3 -c '
import json, sys
target = '"$num"'
for i in json.load(sys.stdin):
    if i["number"] == target:
        print(i["body"])
        break
' > "$body_tmp"

        if gitleaks detect --no-git --source "$body_tmp" --no-banner --redact >/dev/null 2>&1; then
            MIGRATE_QUEUE+=("${repo}#${num}: ${title}  (would tag public-safe)")
        else
            PRIVATE_QUEUE+=("${repo}#${num}: ${title}  (stay-private: scrub hit)")
        fi
        rm -f "$body_tmp"
    done < <(echo "$resp" | python3 -c '
import json, sys
for i in json.load(sys.stdin):
    print(f"{i[\"number\"]}\t{i[\"title\"]}\t{\" \".join(l[\"name\"] for l in i.get(\"labels\",[]))}")
')
done
unset TOKEN

# ── Report ───────────────────────────────────────────────────────────────────

echo
echo "── migration plan"
echo
echo "  PUBLIC-SAFE → would migrate (${#MIGRATE_QUEUE[@]}):"
for x in "${MIGRATE_QUEUE[@]+${MIGRATE_QUEUE[@]}}"; do echo "    + $x"; done
echo
echo "  STAY-PRIVATE → keep Forgejo-only (${#PRIVATE_QUEUE[@]}):"
for x in "${PRIVATE_QUEUE[@]+${PRIVATE_QUEUE[@]}}"; do echo "    · $x"; done
echo

if [ "$DRY_RUN" = 1 ]; then
    echo "dry-run: no GitHub issues created, no Forgejo labels flipped."
    exit 0
fi

# ── Real migration ───────────────────────────────────────────────────────────
# Deliberately stubbed in K4: implementing gh issue create + Forgejo
# label-flip + comment-add is non-trivial and the GitHub org doesn't
# exist yet (decisions-open.md: github-org-name). When that decision is
# answered AND ADR-0020 is Accepted AND the repos are on GitHub, this
# block becomes the actual migration loop.

echo "real migration: not yet implemented in K4 — pending github-org-name decision" >&2
echo "  the dry-run report above shows what WOULD migrate when this is wired up" >&2
exit 1
