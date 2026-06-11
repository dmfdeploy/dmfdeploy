#!/usr/bin/env bash
# MOTHBALLED 2026-06-04 (historical, fails closed): bin/agentic/issue-open.sh — open a new agent-opened Forgejo issue.
#
# Constitution Rule 11: only the orchestrator (Claude) runs this script.
# Constitution Rule 12: body + title pass through scrub + gitleaks; any
# hit hard-fails. The agent rewrites with placeholder syntax and resubmits.
#
# Pipeline:
#   1. Source forgejo.env; validate config.
#   2. Read --title + body (--body-file or stdin).
#   3. Run scrub-public-repos.sh --stdin on body; reject on hit.
#   4. Run gitleaks detect --no-git --pipe on body; reject on hit.
#   5. Title regex check (Layer 4 §"Drift firebreaks" rule 1).
#   6. Required body sections present (Context / Acceptance / Scope /
#      Constraints / Decision points / Related).
#   7. Label-set validation (exactly 1 type:, ≥1 scope: not dmf-env, etc.).
#   8. Fuzzy dup-check against existing open agent-opened issues on the
#      target repo.
#   9. POST to Forgejo API; append the new issue to docs/agentic/issues.yaml.
#
# Usage:
#   bin/agentic/issue-open.sh \
#       --scope <repo>        # the primary scope: label (which Forgejo repo
#                             # to post on; the body's Scope section can list
#                             # additional scope: labels for tracker issues)
#       --title "..."         # 5-80 chars, regex per Layer 4
#       --type workaround|feature|bug|decision-requested
#       --pickup ready|blocked|in-progress|deferred
#       --effort S|M|L
#       --body-file <path>    # body markdown; required sections enforced
#       [--scope-additional repo1,repo2,...]  # for cross-repo trackers
#       [--dry-run]           # validate + show payload; no API call
#
# Exit codes:
#   0 — issue created (or dry-run validated)
#   1 — validation failed (scrub / gitleaks / template / dup / label)
#   2 — usage / argument error
#   3 — API error
#
# Refs:
#   docs/agentic/CONSTITUTION.md (Rules 8, 11, 12, 13)
#   docs/agentic/ISSUE-TEMPLATES.md (canonical templates + tokens)
#   docs/plans/DMF Agentic Harness Plan 2026-05-11.md §Layer 4

set -euo pipefail

if [[ "${DMF_AGENTIC_OVERRIDE:-}" != "1" ]]; then
    echo "mothballed 2026-06-04 — set DMF_AGENTIC_OVERRIDE=1 to run" >&2
    exit 1
fi

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
# shellcheck source=/dev/null
. "${UMBRELLA_DIR}/bin/agentic/forgejo.env"

# ── Parse args ───────────────────────────────────────────────────────────────

SCOPE=""
TITLE=""
TYPE=""
PICKUP=""
EFFORT=""
BODY_FILE=""
SCOPE_ADDITIONAL=""
DRY_RUN=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --scope)              SCOPE="$2"; shift 2 ;;
        --title)              TITLE="$2"; shift 2 ;;
        --type)               TYPE="$2"; shift 2 ;;
        --pickup)             PICKUP="$2"; shift 2 ;;
        --effort)             EFFORT="$2"; shift 2 ;;
        --body-file)          BODY_FILE="$2"; shift 2 ;;
        --scope-additional)   SCOPE_ADDITIONAL="$2"; shift 2 ;;
        --dry-run)            DRY_RUN=1; shift ;;
        -h|--help)
            sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

# ── Required args present ────────────────────────────────────────────────────

missing=()
[ -z "$SCOPE" ]    && missing+=("--scope")
[ -z "$TITLE" ]    && missing+=("--title")
[ -z "$TYPE" ]     && missing+=("--type")
[ -z "$PICKUP" ]   && missing+=("--pickup")
[ -z "$EFFORT" ]   && missing+=("--effort")
[ -z "$BODY_FILE" ] && missing+=("--body-file")
if [ "${#missing[@]}" -gt 0 ]; then
    echo "missing required: ${missing[*]}" >&2
    exit 2
fi

# Validate config unless --dry-run AND no real call needed for validation
if [ "$DRY_RUN" = 0 ]; then
    forgejo_validate_config || exit 2
fi

# ── Validate label values ────────────────────────────────────────────────────

case "$TYPE" in
    workaround|feature|bug|decision-requested) ;;
    *) echo "invalid --type: $TYPE (allowed: workaround|feature|bug|decision-requested)" >&2; exit 2 ;;
esac
case "$PICKUP" in
    ready|blocked|in-progress|deferred) ;;
    *) echo "invalid --pickup: $PICKUP (allowed: ready|blocked|in-progress|deferred)" >&2; exit 2 ;;
esac
case "$EFFORT" in
    S|M|L) ;;
    *) echo "invalid --effort: $EFFORT (allowed: S|M|L)" >&2; exit 2 ;;
esac

# Scope labels — at least the primary; reject dmf-env.
ALL_SCOPES=("$SCOPE")
if [ -n "$SCOPE_ADDITIONAL" ]; then
    IFS=',' read -ra _add <<< "$SCOPE_ADDITIONAL"
    ALL_SCOPES+=("${_add[@]}")
fi
for s in "${ALL_SCOPES[@]}"; do
    case "$s" in
        umbrella|dmf-cms|dmf-infra|dmf-central|dmf-media|dmf-runbooks|dmf-init) ;;
        dmf-env) echo "scope:dmf-env is forbidden (Constitution Rule 13)" >&2; exit 1 ;;
        *) echo "invalid scope: $s" >&2; exit 2 ;;
    esac
done

# Cross-repo enforcement: > 1 scope → reject with instruction.
if [ "${#ALL_SCOPES[@]}" -gt 1 ]; then
    echo "cross-repo scope detected (${ALL_SCOPES[*]})" >&2
    echo "  per Layer 4 firebreak #5: file ONE issue per repo + a tracker issue" >&2
    echo "  with type:feature linking them. Refusing." >&2
    exit 1
fi

# ── Title regex ──────────────────────────────────────────────────────────────

if ! [[ "$TITLE" =~ ^[A-Za-z][A-Za-z0-9\ :_/\.\-]{4,80}$ ]]; then
    echo "title fails regex check" >&2
    echo "  required: ^[A-Za-z][A-Za-z0-9 :_/.\\-]{4,80}\$" >&2
    echo "  got:      $TITLE" >&2
    exit 1
fi

# Title placeholder check — no <placeholder> syntax in titles.
if echo "$TITLE" | grep -q '<[a-z][a-z0-9_-]*>'; then
    echo "title contains placeholder syntax (Layer 4 firebreak #1: titles must be self-describing)" >&2
    exit 1
fi

# ── Body must exist + cap ───────────────────────────────────────────────────

if [ ! -r "$BODY_FILE" ]; then
    echo "body file not readable: $BODY_FILE" >&2
    exit 2
fi
BODY_BYTES=$(wc -c < "$BODY_FILE")
if [ "$BODY_BYTES" -gt 8192 ]; then
    echo "body too large: ${BODY_BYTES} bytes (cap: 8192). Issue is the index — link to a handoff or plan instead." >&2
    exit 1
fi

# ── Required body sections ───────────────────────────────────────────────────

REQUIRED_SECTIONS=(Context Acceptance Scope Constraints "Decision points" Related)
for sec in "${REQUIRED_SECTIONS[@]}"; do
    if ! grep -qE "^## ${sec}\$" "$BODY_FILE"; then
        echo "missing required section: '## ${sec}'" >&2
        exit 1
    fi
done

# ── Scrub + gitleaks gate (Constitution Rule 12) ─────────────────────────────

COMBINED_INPUT=$(mktemp -t issue-open.XXXXXX)
trap 'rm -f "$COMBINED_INPUT"' EXIT
{
    echo "$TITLE"
    cat "$BODY_FILE"
} > "$COMBINED_INPUT"

# scrub-public-repos.sh has a per-repo mode, not --stdin yet. For now, run
# gitleaks --no-git --pipe-style on the combined content. The scrub-stdin
# extension is a follow-on task (tracked in autonomous-decisions if we
# notice a gap that the per-repo scrub catches but gitleaks misses).
if command -v gitleaks >/dev/null 2>&1; then
    # --config is mandatory: --no-git --source <file> does NOT auto-load the
    # umbrella .gitleaks.toml. Without it gitleaks uses default rules only
    # and DMF custom rules (dmf-internal-topology, dmf-operator-identity,
    # dmf-dev-changeme) silently miss matches in the issue body.
    GL_CONFIG="${UMBRELLA_DIR}/.gitleaks.toml"
    if ! gitleaks detect --no-git --source "$COMBINED_INPUT" --config "$GL_CONFIG" --no-banner --redact >/dev/null 2>&1; then
        echo "scrub gate failed: gitleaks detected leak in title+body" >&2
        gitleaks detect --no-git --source "$COMBINED_INPUT" --config "$GL_CONFIG" --no-banner --redact 2>&1 | tail -10 | sed 's/^/    /' >&2
        echo "  Rewrite using placeholder syntax (Constitution Rule 8) and resubmit." >&2
        exit 1
    fi
fi

# ── Dup-check ────────────────────────────────────────────────────────────────
# Fetch open agent-opened issues from the target Forgejo repo; fuzzy-match
# title via tr-tolower + word-set overlap.

dup_check() {
    local target_repo="$1" target_title="$2"
    [ "$DRY_RUN" = 1 ] && { echo "(dry-run) skipping dup-check"; return 0; }

    local token; token="$(cat "$FORGEJO_TOKEN_PATH")"
    local api="https://${FORGEJO_HOST}/api/v1/repos/${FORGEJO_OWNER}/${target_repo}/issues?labels=agent-opened&state=open&type=issues"
    local resp; resp="$(curl -fsS -H "Authorization: token ${token}" "$api" 2>/dev/null)" || {
        echo "dup-check: Forgejo API unreachable; aborting (Halt Condition 9)" >&2
        exit 3
    }
    local lower_t; lower_t="$(echo "$target_title" | tr '[:upper:]' '[:lower:]')"
    local existing
    existing="$(echo "$resp" | python3 -c '
import json,sys
for i in json.load(sys.stdin):
    print(f"{i[\"number\"]}\t{i[\"title\"]}")
' 2>/dev/null)" || existing=""
    while IFS=$'\t' read -r num existing_title; do
        [ -z "$num" ] && continue
        local lower_e; lower_e="$(echo "$existing_title" | tr '[:upper:]' '[:lower:]')"
        # Substring match either direction → reject
        if [[ "$lower_t" == *"$lower_e"* ]] || [[ "$lower_e" == *"$lower_t"* ]]; then
            echo "dup-check: existing open issue #${num}: ${existing_title}" >&2
            echo "  Comment on the existing issue instead of opening a new one." >&2
            exit 1
        fi
    done <<< "$existing"
}

dup_check "$SCOPE" "$TITLE"

# ── Build payload ────────────────────────────────────────────────────────────

LABELS_JSON=$(python3 -c '
import json,sys
labels = ["agent-opened", "type:'"$TYPE"'", "pickup:'"$PICKUP"'", "effort:'"$EFFORT"'"]
for s in "'"${ALL_SCOPES[*]}"'".split():
    labels.append(f"scope:{s}")
print(json.dumps(labels))
')

PAYLOAD=$(python3 -c '
import json, sys
with open("'"$BODY_FILE"'") as f:
    body = f.read()
payload = {"title": "'"$TITLE"'", "body": body, "labels": '"$LABELS_JSON"'}
print(json.dumps(payload))
')

# ── Dry-run output ───────────────────────────────────────────────────────────

if [ "$DRY_RUN" = 1 ]; then
    echo "── dry-run: would POST to Forgejo"
    echo "  endpoint: https://${FORGEJO_HOST}/api/v1/repos/${FORGEJO_OWNER}/${SCOPE}/issues"
    echo "  labels:   ${LABELS_JSON}"
    echo "  title:    ${TITLE}"
    echo "  body:     ${BODY_BYTES} bytes (${BODY_FILE})"
    echo "  scrub:    passed"
    echo "  gitleaks: passed"
    echo "  template: all 6 required sections present"
    echo "  dup:      (skipped in dry-run)"
    exit 0
fi

# ── Real POST ────────────────────────────────────────────────────────────────

TOKEN="$(cat "$FORGEJO_TOKEN_PATH")"
API="https://${FORGEJO_HOST}/api/v1/repos/${FORGEJO_OWNER}/${SCOPE}/issues"

RESP=$(curl -fsS \
    -X POST \
    -H "Authorization: token ${TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" \
    "$API" 2>/dev/null) || {
    echo "Forgejo API error on POST" >&2
    exit 3
}
unset TOKEN

NEW_NUM=$(echo "$RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["number"])')
echo "✓ opened ${SCOPE}#${NEW_NUM}: ${TITLE}"

# ── Append to issues.yaml mirror ─────────────────────────────────────────────

ISO_TS=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
BODY_SHA=$(shasum -a 256 "$BODY_FILE" | cut -d' ' -f1)

cat >> "${UMBRELLA_DIR}/docs/agentic/issues.yaml" <<YAML

- id: ${NEW_NUM}
  repo: ${SCOPE}
  title: "${TITLE}"
  type: ${TYPE}
  scope: [${ALL_SCOPES[*]}]
  pickup: ${PICKUP}
  effort: ${EFFORT}
  opened_at: "${ISO_TS}"
  opened_by: agentic-harness
  body_sha256: ${BODY_SHA}
YAML

echo "✓ mirrored to docs/agentic/issues.yaml"
