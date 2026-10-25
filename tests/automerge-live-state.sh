#!/usr/bin/env bash
# automerge-live-state.sh — regressions for automerge.yml deciding from the
# PR's live labels and draft state, not the event payload (umbrella #439).
#
# Extracts the step's `run:` script and runs it with a fake `gh` on PATH.
#
#   A  payload has no hold, live labels have hold  -> disarms, never arms
#   B  live no hold, not draft, no changes requested -> arms
#   B2 live changes requested                      -> does not arm, exits non-zero
#   C  live draft                                  -> skips
#   D  API read fails                              -> does not arm, exits non-zero
#   E  isDraft null or missing, labels not an array -> neither arms nor disarms,
#      exits non-zero (a malformed reply fails closed)
#
# The step makes two gh pr view calls (labels/isDraft, then reviews). The stub
# returns FAKE_VIEW_JSON for both, so the JSON must satisfy both queries. Cases
# A and C exit before the reviews call; only B and B2 reach it.
#
# AUTOMERGE_YML overrides the workflow file (to run against an older copy).
set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
YML="${AUTOMERGE_YML:-$UMBRELLA_DIR/.github/workflows/automerge.yml}"
pass=0; fail=0
ok()  { echo "  ✓ $1"; pass=$((pass + 1)); }
bad() { echo "  ✗ $1" >&2; fail=$((fail + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dmf-automerge.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"

# The step script is the block after the only `run: |` line, indented 10.
awk '/^        run: \|$/ {on=1; next} on { if (/^          /) {sub(/^          /,""); print} else if (!/^$/) exit }' \
  "$YML" > "$WORK/step.sh"
[ -s "$WORK/step.sh" ] || { echo "could not extract run script from $YML" >&2; exit 2; }

cat > "$WORK/bin/gh" <<'F'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") [ -n "${FAKE_VIEW_FAIL:-}" ] && exit 1; printf '%s\n' "$FAKE_VIEW_JSON" ;;
  "pr merge") echo "$*" >> "$FAKE_LOG" ;;
  *) exit 1 ;;
esac
F
chmod +x "$WORK/bin/gh"

# run_case <live-json> <fail:0|1>; sets RC and LOG. The payload env says
# "no hold, not draft" every time: only the live read may change the outcome.
run_case() {
  : > "$WORK/log"
  FAKE_LOG="$WORK/log" FAKE_VIEW_JSON="$1" FAKE_VIEW_FAIL="${2:+x}" \
  PATH="$WORK/bin:$PATH" PR_URL="https://example.test/pr/1" \
  PR_LABELS="" PR_DRAFT="false" bash "$WORK/step.sh" > "$WORK/out" 2>&1
  RC=$?; LOG="$(cat "$WORK/log")"
}

echo "automerge live-state cases ($YML)"

run_case '{"isDraft":false,"labels":[{"name":"hold"},{"name":"component:ci"}]}'
if [ "$RC" = 0 ] && [[ "$LOG" == *"--disable-auto"* ]] && [[ "$LOG" != *"--auto --rebase"* ]]; then
  ok "A: live hold disarms and does not arm"; else bad "A: live hold (rc=$RC log=[$LOG])"; fi

run_case '{"isDraft":false,"labels":[{"name":"component:ci"}],"reviews":[]}'
if [ "$RC" = 0 ] && [[ "$LOG" == *"--auto --rebase"* ]]; then
  ok "B: no hold, not draft, no changes requested arms"; else bad "B: arm (rc=$RC log=[$LOG])"; fi

run_case '{"isDraft":false,"labels":[],"reviews":[{"state":"CHANGES_REQUESTED","author":{"login":"reviewer1"},"submittedAt":"2026-01-01T00:00:00Z"}]}'
if [ "$RC" != 0 ] && [[ "$LOG" != *"--auto --rebase"* ]]; then
  ok "B2: changes requested does not arm"; else bad "B2: changes requested (rc=$RC log=[$LOG])"; fi

run_case '{"isDraft":true,"labels":[]}'
if [ "$RC" = 0 ] && [ -z "$LOG" ]; then
  ok "C: live draft skips"; else bad "C: draft (rc=$RC log=[$LOG])"; fi

run_case '' 1
if [ "$RC" != 0 ] && [[ "$LOG" != *"--auto --rebase"* ]]; then
  ok "D: failed API read does not arm"; else bad "D: read failure (rc=$RC log=[$LOG])"; fi

for bad_json in '{"isDraft":null,"labels":[]}' '{"labels":[]}' \
                '{"isDraft":false,"labels":"hold"}' '{"isDraft":false,"labels":[{"name":1}]}'; do
  run_case "$bad_json"
  if [ "$RC" != 0 ] && [ -z "$LOG" ]; then
    ok "E: malformed reply $bad_json fails closed"; else bad "E: $bad_json (rc=$RC log=[$LOG])"; fi
done

echo "passed=$pass failed=$fail"
[ "$fail" = 0 ]
