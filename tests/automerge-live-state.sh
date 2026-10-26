#!/usr/bin/env bash
# automerge-live-state.sh — regressions for automerge.yml deciding from the
# PR's live labels, draft state and base branch, not the event payload
# (umbrella #439), and arming only PRs into the default branch (umbrella #544).
#
# Extracts the step's `run:` script and runs it with a fake `gh` on PATH.
#
#   A  payload has no hold, live labels have hold  -> disarms, never arms
#   A2 hold on a PR into a topic branch            -> disarms, never arms
#   B  live no hold, not draft, base is default    -> arms
#   B2 base is a topic branch                      -> does not arm, exits 0
#   B3 base is a topic branch, already armed       -> stays armed (only hold
#      disarms)
#   B4 default branch unknown (empty payload field) -> does not arm
#   C  live draft                                  -> skips
#   D  API read fails                              -> does not arm, exits non-zero
#   E  isDraft null or missing, labels not an array, base branch missing, empty
#      or not a string -> neither arms nor disarms, exits non-zero (a malformed
#      reply fails closed)
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

# The stub keeps auto-merge state in $FAKE_ARMED: "--auto" arms it and
# "--disable-auto" clears it, so a case can start armed and check the end state.
cat > "$WORK/bin/gh" <<'F'
#!/usr/bin/env bash
case "$1 $2" in
  "pr view") [ -n "${FAKE_VIEW_FAIL:-}" ] && exit 1; printf '%s\n' "$FAKE_VIEW_JSON" ;;
  "pr merge") echo "$*" >> "$FAKE_LOG"
    case " $* " in
      *" --disable-auto "*) echo 0 > "$FAKE_ARMED" ;;
      *" --auto "*) echo 1 > "$FAKE_ARMED" ;;
    esac ;;
  *) echo "unexpected: $*" >> "$FAKE_LOG"; exit 1 ;;
esac
F
chmod +x "$WORK/bin/gh"

# run_case <live-json> [fail]; sets RC, LOG and ARMED. The payload env says
# "no hold, not draft" every time: only the live read may change the outcome.
# START_ARMED=1 starts the case armed. DEFAULT is the payload's default branch.
run_case() {
  : > "$WORK/log"; echo "${START_ARMED:-0}" > "$WORK/armed"
  FAKE_LOG="$WORK/log" FAKE_ARMED="$WORK/armed" FAKE_VIEW_JSON="$1" \
  FAKE_VIEW_FAIL="${2:+x}" PATH="$WORK/bin:$PATH" \
  PR_URL="https://example.test/pr/1" DEFAULT_BRANCH="${DEFAULT-main}" \
  PR_LABELS="" PR_DRAFT="false" bash "$WORK/step.sh" > "$WORK/out" 2>&1
  RC=$?; LOG="$(cat "$WORK/log")"; ARMED="$(cat "$WORK/armed")"
}

echo "automerge live-state cases ($YML)"

START_ARMED=1 run_case '{"isDraft":false,"labels":[{"name":"hold"},{"name":"component:ci"}],"baseRefName":"main"}'
if [ "$RC" = 0 ] && [ "$ARMED" = 0 ] && [[ "$LOG" == *"--disable-auto"* ]] && [[ "$LOG" != *"--auto --rebase"* ]]; then
  ok "A: live hold disarms and does not arm"; else bad "A: live hold (rc=$RC armed=$ARMED log=[$LOG])"; fi

START_ARMED=1 run_case '{"isDraft":false,"labels":[{"name":"hold"}],"baseRefName":"topic/x"}'
if [ "$RC" = 0 ] && [ "$ARMED" = 0 ] && [[ "$LOG" == *"--disable-auto"* ]] && [[ "$LOG" != *"--auto --rebase"* ]]; then
  ok "A2: hold disarms a PR into a topic branch"; else bad "A2: topic hold (rc=$RC armed=$ARMED log=[$LOG])"; fi

run_case '{"isDraft":false,"labels":[{"name":"component:ci"}],"baseRefName":"main"}'
if [ "$RC" = 0 ] && [ "$ARMED" = 1 ] && [[ "$LOG" == *"--auto --rebase"* ]]; then
  ok "B: no hold, not draft, default base arms"; else bad "B: arm (rc=$RC log=[$LOG])"; fi

run_case '{"isDraft":false,"labels":[],"baseRefName":"topic/x"}'
if [ "$RC" = 0 ] && [ "$ARMED" = 0 ] && [ -z "$LOG" ]; then
  ok "B2: topic base does not arm"; else bad "B2: topic base (rc=$RC armed=$ARMED log=[$LOG])"; fi

START_ARMED=1 run_case '{"isDraft":false,"labels":[],"baseRefName":"topic/x"}'
if [ "$RC" = 0 ] && [ "$ARMED" = 1 ] && [ -z "$LOG" ]; then
  ok "B3: armed topic-base PR is left as it is"; else bad "B3: armed topic base (rc=$RC armed=$ARMED log=[$LOG])"; fi

DEFAULT="" run_case '{"isDraft":false,"labels":[],"baseRefName":"main"}'
if [ "$RC" = 0 ] && [ "$ARMED" = 0 ] && [ -z "$LOG" ]; then
  ok "B4: unknown default branch does not arm"; else bad "B4: no default (rc=$RC log=[$LOG])"; fi

run_case '{"isDraft":true,"labels":[],"baseRefName":"main"}'
if [ "$RC" = 0 ] && [ -z "$LOG" ]; then
  ok "C: live draft skips"; else bad "C: draft (rc=$RC log=[$LOG])"; fi

run_case '' 1
if [ "$RC" != 0 ] && [[ "$LOG" != *"--auto --rebase"* ]]; then
  ok "D: failed API read does not arm"; else bad "D: read failure (rc=$RC log=[$LOG])"; fi

for bad_json in '{"isDraft":null,"labels":[],"baseRefName":"main"}' '{"labels":[],"baseRefName":"main"}' \
                '{"isDraft":false,"labels":"hold","baseRefName":"main"}' \
                '{"isDraft":false,"labels":[{"name":1}],"baseRefName":"main"}' \
                '{"isDraft":false,"labels":[]}' '{"isDraft":false,"labels":[],"baseRefName":""}' \
                '{"isDraft":false,"labels":[],"baseRefName":null}' '{"isDraft":false,"labels":[],"baseRefName":1}'; do
  run_case "$bad_json"
  if [ "$RC" != 0 ] && [ -z "$LOG" ]; then
    ok "E: malformed reply $bad_json fails closed"; else bad "E: $bad_json (rc=$RC log=[$LOG])"; fi
done

echo "passed=$pass failed=$fail"
[ "$fail" = 0 ]
