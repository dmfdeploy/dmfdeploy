#!/usr/bin/env bash
# Runs the guard.yml commitlint step's own script against stubbed PR commits
# and checks that a session link in any commit message fails it (#838).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Pull the step's script out of the workflow, so the test runs what CI runs.
awk '
  /name: Conventional Commits check/ { found = 1 }
  found && /run: \|/ { grab = 1; next }
  grab && /^  [a-z]/ { exit }
  grab { sub(/^          /, ""); print }
' "$root/.github/workflows/guard.yml" >"$work/step.sh"
[ -s "$work/step.sh" ] || { echo "FAIL: could not extract the commitlint script" >&2; exit 1; }

# Built from parts so this file never holds a real session URL.
link="https://claude.ai/""code/session_""01Example"
ulink="https://""CLAUDE"".AI/""code/session_""01Example"

# run_step PR_COMMITS COUNT MESSAGE: the stub lists COUNT commits (capped at 250,
# 100 per page, like the real endpoint), each with MESSAGE and a distinct SHA.
run_step() {
  python3 - "$work" "$2" "$3" <<'PY'
import sys, json, base64
work, count, msg = sys.argv[1], min(int(sys.argv[2]), 250), sys.argv[3]
for page in range(1, 4):
    rows = [base64.b64encode(json.dumps({"sha": "%040x" % n, "commit": {"message": msg}}).encode()).decode()
            for n in range((page - 1) * 100 + 1, min(page * 100, count) + 1)]
    open(f"{work}/page{page}", "w").write("\n".join(rows))
PY
  mkdir -p "$work/bin"
  cat >"$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
args="$*"
page="${args##*page=}"
page="${page%% *}"
[ -f "$STUB_DIR/page$page" ] && cat "$STUB_DIR/page$page" || true
STUB
  chmod +x "$work/bin/gh"
  PATH="$work/bin:$PATH" STUB_DIR="$work" COMMITS_URL=x PR_COMMITS="$1" bash "$work/step.sh" >"$work/out" 2>&1
}

fail=0
# expect NAME WANT_EXIT PR_COMMITS COUNT MESSAGE
expect() {
  local rc=0
  run_step "$3" "$4" "$5" || rc=$?
  if [ "$rc" -ne "$2" ]; then
    echo "FAIL: $1 (exit $rc, want $2)" >&2; sed "s|$link|<link>|g" "$work/out" >&2; fail=1
  else
    echo "ok: $1"
  fi
}
# The public log must never hold the link or the offending subject text.
expect_quiet() {
  if grep -qF "$link" "$work/out" || grep -qF "SUBJECTTEXT" "$work/out"; then
    echo "FAIL: $1 (output echoes the link or subject)" >&2; fail=1
  else
    echo "ok: $1"
  fi
}

expect "clean commit passes" 0 1 1 "feat(ci): add a thing

Signed-off-by: A <a@example.com>"
expect "trailer link fails" 1 1 1 "feat(ci): add a thing

Claude-Session: $link"
expect "subject link fails" 1 1 1 "feat(ci): SUBJECTTEXT $link"
expect_quiet "subject link output is quiet"
grep -qE 'commit 0000000 links to an agent session' "$work/out" || { echo "FAIL: no SHA in link error" >&2; fail=1; }
expect "malformed subject with link fails" 1 1 1 "SUBJECTTEXT $link"
expect_quiet "malformed subject with link output is quiet"
expect "malformed subject without link fails" 1 1 1 "SUBJECTTEXT without a type"
expect_quiet "malformed subject without link output is quiet"
grep -qE 'commit 0000000 has a non-conventional subject' "$work/out" || { echo "FAIL: no SHA in subject error" >&2; fail=1; }
expect "merge commit with link fails" 1 1 1 "Merge branch x

$link"
expect "uppercase hostname in subject fails" 1 1 1 "feat(ci): SUBJECTTEXT $ulink"
if grep -qF "$ulink" "$work/out" || grep -qF "SUBJECTTEXT" "$work/out"; then
  echo "FAIL: uppercase subject output echoes the link or subject" >&2; fail=1
fi
expect "uppercase hostname in body fails" 1 1 1 "feat(ci): add a thing

Claude-Session: $ulink"
expect "uppercase hostname in merge commit fails" 1 1 1 "Merge branch x

$ulink"
expect "PR_COMMITS empty fails" 1 "" 1 "feat(ci): add a thing"
grep -qF 'not a number' "$work/out" || { echo "FAIL: no count diagnostic (empty)" >&2; fail=1; }
expect "PR_COMMITS non-numeric fails" 1 abc 1 "feat(ci): add a thing"
grep -qF 'not a number' "$work/out" || { echo "FAIL: no count diagnostic (non-numeric)" >&2; fail=1; }
expect "PR_COMMITS valid unequal fails" 1 2 1 "feat(ci): add a thing"
expect "250 commits, PR holds 250, passes" 0 250 250 "feat(ci): add a thing"
expect "PR holds 300, API lists 250, fails closed" 1 300 300 "feat(ci): add a thing"
grep -qF 'checked 250 of 300 PR commits' "$work/out" || { echo "FAIL: no cap message" >&2; fail=1; }
exit "$fail"
