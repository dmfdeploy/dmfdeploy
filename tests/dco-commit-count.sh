#!/usr/bin/env bash
# Runs the dco.yml sign-off step's own script against stubbed PR commits and
# checks that it fails when a sign-off is missing, and also when it cannot
# check as many commits as the PR holds (the commits API lists at most 250).
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Pull the step's script out of the workflow, so the test runs what CI runs.
awk '
  /name: Verify Signed-off-by on every commit/ { found = 1 }
  found && /run: \|/ { grab = 1; next }
  grab && /^  [a-z]/ { exit }
  grab { sub(/^          /, ""); print }
' "$root/.github/workflows/dco.yml" >"$work/step.sh"
[ -s "$work/step.sh" ] || { echo "FAIL: could not extract the DCO script" >&2; exit 1; }

mkdir -p "$work/bin"
cat >"$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
args="$*"
page="${args##*page=}"
page="${page%% *}"
[ -f "$STUB_DIR/page$page" ] && cat "$STUB_DIR/page$page" || true
STUB
chmod +x "$work/bin/gh"

# run_step PR_COMMITS LISTED UNSIGNED ACTOR: the stub lists LISTED commits
# (capped at 250, 100 per page, like the real endpoint). Every commit carries a
# sign-off except number UNSIGNED (0 means none). The count is passed to the
# step as given, so it can be empty or not a number.
run_step() {
  python3 - "$work" "$2" "$3" <<'PY'
import sys, json, base64
work, listed, unsigned = sys.argv[1], min(int(sys.argv[2]), 250), int(sys.argv[3])
signed = "feat(ci): add a thing\n\nSigned-off-by: A <a@example.com>"
unsigned_msg = "feat(ci): add a thing"
for page in range(1, 4):
    rows = [base64.b64encode(json.dumps({"sha": "%040x" % n,
                                         "commit": {"message": unsigned_msg if n == unsigned else signed}}).encode()).decode()
            for n in range((page - 1) * 100 + 1, min(page * 100, listed) + 1)]
    open(f"{work}/page{page}", "w").write("\n".join(rows))
PY
  PATH="$work/bin:$PATH" STUB_DIR="$work" COMMITS_URL=x PR_COMMITS="$1" ACTOR="$4" \
    bash "$work/step.sh" >"$work/out" 2>&1
}

fail=0
# expect NAME WANT_EXIT PR_COMMITS LISTED UNSIGNED ACTOR
expect() {
  local rc=0
  run_step "$3" "$4" "$5" "$6" || rc=$?
  if [ "$rc" -ne "$2" ]; then
    echo "FAIL: $1 (exit $rc, want $2)" >&2; cat "$work/out" >&2; fail=1
  else
    echo "ok: $1"
  fi
}
# expect_message NAME TEXT: the output of the last run must hold TEXT.
expect_message() {
  grep -qF "$2" "$work/out" || { echo "FAIL: $1 (no '$2' in output)" >&2; cat "$work/out" >&2; fail=1; }
}

expect "all commits signed and the count matches passes" 0 3 3 0 octocat
expect "a commit without a sign-off fails" 1 3 3 2 octocat
expect_message "missing sign-off names the commit" "missing Signed-off-by trailer"
expect "250 commits signed, PR holds 250, passes" 0 250 250 0 octocat
expect "PR holds 300, API lists 250, fails closed" 1 300 300 0 octocat
expect_message "cap failure reports both counts" "checked 250 of 300 PR commits"
expect "PR holds more commits than were listed fails" 1 5 3 0 octocat
expect "PR holds fewer commits than were listed fails" 1 2 3 0 octocat
expect "missing commit count fails" 1 "" 3 0 octocat
expect_message "missing count is reported" "missing or not a number"
expect "commit count not a number fails" 1 abc 3 0 octocat
expect_message "non-numeric count is reported" "missing or not a number"
expect "dependabot passes with an unsigned commit" 0 3 3 2 "dependabot[bot]"
expect "dependabot passes without a commit count" 0 "" 3 2 "dependabot[bot]"
exit "$fail"
