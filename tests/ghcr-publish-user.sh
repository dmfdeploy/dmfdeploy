#!/usr/bin/env bash
# ghcr-publish-user.sh - regressions for issue #677.
#
# When the token is piped on stdin and GHCR_USER is unset, the publish scripts
# used to prompt for a username. The prompt read the token as the username, the
# next read hit end of input, and set -e ended the script with no message.
#
# Cases, run for bin/publish-chart-to-ghcr.sh and bin/publish-image-to-ghcr.sh:
#   a  piped token, GHCR_USER unset: exit non-zero, stderr names GHCR_USER,
#      and no tool shim was called.
#   b  piped token, GHCR_USER set: the login shim receives that user and the
#      token on stdin.
#
# Hermetic: helm and docker are PATH shims that log their calls. The token is a
# placeholder. Set PUBLISH_BIN_DIR to run against another copy of the scripts.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="${PUBLISH_BIN_DIR:-${ROOT}/bin}"
TOKEN="placeholder-token-0000"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

SHIMS="${WORK}/shims"
mkdir -p "${SHIMS}" "${WORK}/chart"
cat > "${WORK}/chart/Chart.yaml" <<'YAML'
apiVersion: v2
name: demo
version: 0.0.1
YAML

# Every shim appends "<tool> <args>" to CALLS. Login shims also log stdin.
cat > "${SHIMS}/helm" <<'SH'
#!/usr/bin/env bash
echo "helm $*" >> "${CALLS}"
case "$1 ${2:-}" in
  "show chart") printf 'name: demo\nversion: 0.0.1\n' ;;
  "registry login") echo "stdin: $(cat)" >> "${CALLS}" ;;
esac
if [[ "$1" == package ]]; then
  dest=""
  while [[ $# -gt 0 ]]; do [[ "$1" == --destination ]] && dest="$2"; shift; done
  : > "${dest}/demo-0.0.1.tgz"
fi
exit 0
SH
cat > "${SHIMS}/docker" <<'SH'
#!/usr/bin/env bash
echo "docker $*" >> "${CALLS}"
case "$1" in
  login) echo "stdin: $(cat)" >> "${CALLS}" ;;
  image) echo "linux/amd64" ;;
esac
exit 0
SH
chmod +x "${SHIMS}/helm" "${SHIMS}/docker"

FAILS=0
check() { # check <label> <condition-exit-status>
  if [[ "$2" -eq 0 ]]; then echo "  ok: $1"; else echo "  FAIL: $1"; FAILS=$((FAILS + 1)); fi
}

run_case() { # run_case <name> <with-user: 0|1> <script> <args...>
  local name="$1" with_user="$2"; shift 2
  export CALLS="${WORK}/calls-${name}-${with_user}"
  : > "${CALLS}"
  local user=""
  [[ "${with_user}" == 1 ]] && user="alice"
  printf '%s\n' "${TOKEN}" \
    | env -u GHCR_USER ${user:+GHCR_USER="${user}"} PATH="${SHIMS}:${PATH}" CALLS="${CALLS}" \
        HOME="${WORK}" bash "$@" > "${WORK}/out-${name}-${with_user}" 2> "${WORK}/err-${name}-${with_user}"
  RC=$?
}

for name in chart image; do
  echo "== publish-${name}-to-ghcr.sh =="
  if [[ "${name}" == chart ]]; then
    args=("${BIN}/publish-chart-to-ghcr.sh" "${WORK}/chart" ghcr.io/example/charts/demo)
  else
    args=("${BIN}/publish-image-to-ghcr.sh" src:1 ghcr.io/example/demo:1)
  fi

  echo " (a) piped token, GHCR_USER unset"
  run_case "${name}" 0 "${args[@]}"
  [[ "${RC}" -ne 0 ]]; check "exits non-zero (rc=${RC})" $?
  grep -q GHCR_USER "${WORK}/err-${name}-0"; check "stderr names GHCR_USER" $?
  [[ ! -s "${CALLS}" ]]; check "no shim was called" $?

  echo " (b) piped token, GHCR_USER set"
  run_case "${name}" 1 "${args[@]}"
  [[ "${RC}" -eq 0 ]]; check "exits zero (rc=${RC})" $?
  grep -q -- '^[a-z]* \(registry \)\?login ghcr.io -u alice --password-stdin' "${CALLS}"
  check "login shim got user alice" $?
  grep -qx "stdin: ${TOKEN}" "${CALLS}"; check "login shim got the token on stdin" $?
done

if [[ "${FAILS}" -ne 0 ]]; then
  echo "ghcr-publish-user: ${FAILS} check(s) failed" >&2
  exit 1
fi
echo "ghcr-publish-user: all checks passed"
