#!/usr/bin/env bash
# automerge-live-state.sh — regressions for automerge.yml deciding from the
# PR's live labels, draft state and base branch, not the event payload
# (umbrella #439), arming only PRs into the default branch, and applying hold
# when a PR is retargeted off it (umbrella #544).
#
# Extracts the step's `run:` script and runs it with a fake `gh` on PATH.
#
#   A  payload has no hold, live labels have hold  -> disarms, never arms
#   A2 hold on a PR into a topic branch            -> disarms, never arms
#   B  live no hold, not draft, base is default    -> arms
#   B2 base is a topic branch                      -> adds hold, disarms
#   B3 base is a topic branch, already armed       -> adds hold, disarms
#      (migration of an armed PR)
#   B4 default branch unknown (empty payload field) -> does not arm
#   R1 armed, retargeted to a topic branch (edited) -> adds hold, disarms
#   R2 edited, title or body only                 -> no gh call at all
#   R3 held, retargeted back to the default branch -> hold kept, disarms, no arm
#   R4 retargeted to a topic branch, label write fails -> still disarms, exits
#      non-zero
#   R4a retargeted to a topic branch, disarming fails -> remains armed, exits
#       non-zero
#   R5 no hold, retargeted back to the default branch -> arms (the normal rule)
#   R6 base reads the default branch before arming and a topic branch after
#      (retargeted mid-run)                        -> arms, then adds hold, disarms
#   R7 the read after arming fails                 -> adds hold, disarms
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
  "pr view") [ -n "${FAKE_VIEW_FAIL:-}" ] && exit 1
    # Reads after the first fail when $FAKE_VIEW_FAIL_AFTER is set, and get
    # $FAKE_VIEW_AFTER when that is set.
    [ -n "${FAKE_VIEW_FAIL_AFTER:-}" ] && [ -e "$FAKE_VIEWED" ] && exit 1
    if [ -n "${FAKE_VIEW_AFTER:-}" ] && [ -e "$FAKE_VIEWED" ]; then
      printf '%s\n' "$FAKE_VIEW_AFTER"
    else
      printf '%s\n' "$FAKE_VIEW_JSON"
    fi
    : > "$FAKE_VIEWED" ;;
  "pr merge") echo "$*" >> "$FAKE_LOG"
    case " $* " in
      *" --disable-auto "*) [ -n "${FAKE_DISABLE_FAIL:-}" ] && exit 1; echo 0 > "$FAKE_ARMED" ;;
      *" --auto "*) echo 1 > "$FAKE_ARMED" ;;
    esac ;;
  "api -X") echo "$*" >> "$FAKE_LOG"; [ -z "${FAKE_LABEL_FAIL:-}" ] ;;
  *) echo "unexpected: $*" >> "$FAKE_LOG"; exit 1 ;;
esac
F
chmod +x "$WORK/bin/gh"

# run_case <live-json> [fail]; sets RC, LOG and ARMED. The payload env says
# "no hold, not draft" every time: only the live read may change the outcome.
# START_ARMED=1 starts the case armed. DEFAULT is the payload's default branch.
# ACTION and BASE_MOVED stand in for the event action and whether the payload
# records a base change; LABEL_FAIL=1 makes the label write fail and
# DISABLE_FAIL=1 makes disarming fail. VIEW_AFTER is the reply to every read
# after the first; VIEW_FAIL_AFTER=1 fails them.
# The step runs under the runner's default bash flags (-eo pipefail), so a
# failing pipeline behaves here as it does in Actions.
run_case() {
  : > "$WORK/log"; echo "${START_ARMED:-0}" > "$WORK/armed"; rm -f "$WORK/viewed"
  FAKE_LOG="$WORK/log" FAKE_ARMED="$WORK/armed" FAKE_VIEW_JSON="$1" \
  FAKE_VIEWED="$WORK/viewed" FAKE_VIEW_AFTER="${VIEW_AFTER:-}" \
  FAKE_VIEW_FAIL_AFTER="${VIEW_FAIL_AFTER:-}" \
  FAKE_VIEW_FAIL="${2:+x}" FAKE_LABEL_FAIL="${LABEL_FAIL:-}" \
  FAKE_DISABLE_FAIL="${DISABLE_FAIL:-}" PATH="$WORK/bin:$PATH" \
  PR_URL="https://example.test/pr/1" DEFAULT_BRANCH="${DEFAULT-main}" \
  REPO="example/repo" PR_NUMBER="1" EVENT_ACTION="${ACTION:-labeled}" \
  BASE_CHANGED="${BASE_MOVED:-false}" \
  PR_LABELS="" PR_DRAFT="false" bash --noprofile --norc -eo pipefail "$WORK/step.sh" > "$WORK/out" 2>&1
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
if [ "$RC" = 0 ] && [ "$ARMED" = 0 ] && [[ "$LOG" == *"repos/example/repo/issues/1/labels"* ]] && [[ "$LOG" == *"--disable-auto"* ]] && [[ "$LOG" != *"--auto --rebase"* ]]; then
  ok "B2: topic base adds hold and disarms"; else bad "B2: topic base (rc=$RC armed=$ARMED log=[$LOG])"; fi

START_ARMED=1 run_case '{"isDraft":false,"labels":[],"baseRefName":"topic/x"}'
if [ "$RC" = 0 ] && [ "$ARMED" = 0 ] && [[ "$LOG" == *"repos/example/repo/issues/1/labels"* ]] && [[ "$LOG" == *"--disable-auto"* ]] && [[ "$LOG" != *"--auto --rebase"* ]]; then
  ok "B3: armed topic-base PR is disarmed via the hold path"; else bad "B3: armed topic base (rc=$RC armed=$ARMED log=[$LOG])"; fi

DEFAULT="" run_case '{"isDraft":false,"labels":[],"baseRefName":"main"}'
if [ "$RC" = 0 ] && [ "$ARMED" = 0 ] && [ -z "$LOG" ]; then
  ok "B4: unknown default branch does not arm"; else bad "B4: no default (rc=$RC log=[$LOG])"; fi

LABEL_ADD="api -X POST repos/example/repo/issues/1/labels -f labels[]=hold"

START_ARMED=1 ACTION=edited BASE_MOVED=true run_case '{"isDraft":false,"labels":[],"baseRefName":"topic/x"}'
if [ "$RC" = 0 ] && [ "$ARMED" = 0 ] && [[ "$LOG" == *"$LABEL_ADD"* ]] && [[ "$LOG" == *"--disable-auto"* ]] \
   && [[ "$LOG" != *"--auto --rebase"* ]]; then
  ok "R1: armed PR retargeted to a topic branch gets hold and is disarmed"
else bad "R1: retarget to topic (rc=$RC armed=$ARMED log=[$LOG])"; fi

for json in '{"isDraft":false,"labels":[],"baseRefName":"topic/x"}' '{"isDraft":false,"labels":[],"baseRefName":"main"}'; do
  START_ARMED=1 ACTION=edited BASE_MOVED=false run_case "$json"
  if [ "$RC" = 0 ] && [ "$ARMED" = 1 ] && [ -z "$LOG" ]; then
    ok "R2: title-only edit changes nothing ($json)"; else bad "R2: title edit $json (rc=$RC armed=$ARMED log=[$LOG])"; fi
done

START_ARMED=1 ACTION=edited BASE_MOVED=true run_case '{"isDraft":false,"labels":[{"name":"hold"}],"baseRefName":"main"}'
if [ "$RC" = 0 ] && [ "$ARMED" = 0 ] && [[ "$LOG" == *"--disable-auto"* ]] && [[ "$LOG" != *"api"* ]] \
   && [[ "$LOG" != *"--auto --rebase"* ]]; then
  ok "R3: retarget back to the default branch keeps hold and does not arm"
else bad "R3: retarget back with hold (rc=$RC armed=$ARMED log=[$LOG])"; fi

START_ARMED=1 LABEL_FAIL=1 ACTION=edited BASE_MOVED=true run_case '{"isDraft":false,"labels":[],"baseRefName":"topic/x"}'
if [ "$RC" != 0 ] && [ "$ARMED" = 0 ] && [[ "$LOG" != *"--auto --rebase"* ]]; then
  ok "R4: failed label write on retarget still disarms and exits non-zero"
else bad "R4: label write fails (rc=$RC armed=$ARMED log=[$LOG])"; fi

START_ARMED=1 DISABLE_FAIL=1 ACTION=edited BASE_MOVED=true run_case '{"isDraft":false,"labels":[],"baseRefName":"topic/x"}'
if [ "$RC" != 0 ] && [ "$ARMED" = 1 ] && [[ "$LOG" == *"--disable-auto"* ]] && [[ "$LOG" != *"--auto --rebase"* ]]; then
  ok "R4a: failed disarm leaves the PR armed and exits non-zero"
else bad "R4a: disarm fails (rc=$RC armed=$ARMED log=[$LOG])"; fi

ACTION=edited BASE_MOVED=true run_case '{"isDraft":false,"labels":[],"baseRefName":"main"}'
if [ "$RC" = 0 ] && [ "$ARMED" = 1 ] && [[ "$LOG" != *"api"* ]]; then
  ok "R5: unheld PR retargeted back to the default branch arms"
else bad "R5: retarget back without hold (rc=$RC armed=$ARMED log=[$LOG])"; fi

VIEW_AFTER='{"isDraft":false,"labels":[],"baseRefName":"topic/x"}' \
  run_case '{"isDraft":false,"labels":[],"baseRefName":"main"}'
if [ "$RC" = 0 ] && [ "$ARMED" = 0 ] && [[ "$LOG" == *"--auto --rebase"*"$LABEL_ADD"*"--disable-auto"* ]]; then
  ok "R6: retargeted while arming gets hold and is disarmed"
else bad "R6: retarget mid-run (rc=$RC armed=$ARMED log=[$LOG])"; fi

VIEW_FAIL_AFTER=1 run_case '{"isDraft":false,"labels":[],"baseRefName":"main"}'
if [ "$RC" = 0 ] && [ "$ARMED" = 0 ] && [[ "$LOG" == *"--auto --rebase"*"$LABEL_ADD"*"--disable-auto"* ]]; then
  ok "R7: a failed read after arming gets hold and is disarmed"
else bad "R7: re-read fails (rc=$RC armed=$ARMED log=[$LOG])"; fi

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
