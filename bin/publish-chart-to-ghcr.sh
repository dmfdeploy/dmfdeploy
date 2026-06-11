#!/usr/bin/env bash
# publish-chart-to-ghcr.sh - package a Helm chart and publish it to GHCR.
#
# Secrets posture (ADR-0007):
#   - GHCR token read from stdin only - never argv, never echoed.
#   - Isolated HELM_REGISTRY_CONFIG so login state does not touch ~/.config/helm.
#   - Cleanup trap removes package and auth temp files on any exit.
#
# Usage:
#   publish-chart-to-ghcr.sh <chart-dir> <ghcr-chart-ref>
#
# Example:
#   publish-chart-to-ghcr.sh dmf-media/charts/nmos-cpp ghcr.io/dmfdeploy/charts/nmos-cpp
#
# The second argument is the final chart ref without the version. Helm's OCI
# push API expects the parent repository, so this script normalizes the example
# above to `helm push <pkg> oci://ghcr.io/dmfdeploy/charts` and reports the
# published ref as `oci://ghcr.io/dmfdeploy/charts/nmos-cpp:<version>`.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  cat >&2 <<USAGE
Usage: $(basename "$0") <chart-dir> <ghcr-chart-ref>

Example:
  $(basename "$0") dmf-media/charts/nmos-cpp ghcr.io/dmfdeploy/charts/nmos-cpp
USAGE
  exit 2
fi

CHART_DIR="$1"
GHCR_CHART_REF="${2#oci://}"

if [[ ! -f "${CHART_DIR}/Chart.yaml" ]]; then
  echo "ERROR: ${CHART_DIR}/Chart.yaml not found." >&2
  exit 1
fi

if [[ "${GHCR_CHART_REF}" != ghcr.io/* ]]; then
  echo "ERROR: target must be under ghcr.io (got ${GHCR_CHART_REF})." >&2
  exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "ERROR: helm not found in PATH." >&2
  exit 1
fi

CHART_META="$(helm show chart "${CHART_DIR}")"
CHART_NAME="$(awk -F': *' '$1 == "name" { print $2; exit }' <<<"${CHART_META}")"
CHART_VERSION="$(awk -F': *' '$1 == "version" { print $2; exit }' <<<"${CHART_META}")"

if [[ -z "${CHART_NAME}" || -z "${CHART_VERSION}" ]]; then
  echo "ERROR: unable to read chart name/version from ${CHART_DIR}/Chart.yaml." >&2
  exit 1
fi

if [[ "${GHCR_CHART_REF}" == */"${CHART_NAME}" ]]; then
  PUSH_REPO="${GHCR_CHART_REF%/${CHART_NAME}}"
  PUBLISHED_REF="oci://${GHCR_CHART_REF}:${CHART_VERSION}"
else
  PUSH_REPO="${GHCR_CHART_REF}"
  PUBLISHED_REF="oci://${GHCR_CHART_REF}/${CHART_NAME}:${CHART_VERSION}"
fi

if [[ -z "${GHCR_USER:-}" ]]; then
  read -r -p "GitHub username: " GHCR_USER
fi
if [[ -z "${GHCR_USER}" ]]; then
  echo "ERROR: GitHub username required (set GHCR_USER or answer the prompt)." >&2
  exit 1
fi

if [[ -t 0 ]]; then
  echo "Paste GHCR personal access token (write:packages scope; will not echo):"
  read -r -s GHCR_TOKEN
  echo
else
  IFS= read -r GHCR_TOKEN
fi
if [[ -z "${GHCR_TOKEN:-}" ]]; then
  echo "ERROR: GHCR token not provided (pipe via stdin or run interactively)." >&2
  exit 1
fi

TMPDIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMPDIR}"
  unset HELM_REGISTRY_CONFIG
}
trap cleanup EXIT INT TERM

export HELM_REGISTRY_CONFIG="${TMPDIR}/registry.json"

echo "=== Helm package: ${CHART_DIR} ==="
helm package "${CHART_DIR}" --destination "${TMPDIR}"
PACKAGE_PATH="${TMPDIR}/${CHART_NAME}-${CHART_VERSION}.tgz"
if [[ ! -f "${PACKAGE_PATH}" ]]; then
  echo "ERROR: expected package ${PACKAGE_PATH} was not created." >&2
  exit 1
fi

echo "=== Helm registry login to ghcr.io ==="
printf '%s' "${GHCR_TOKEN}" | helm registry login ghcr.io -u "${GHCR_USER}" --password-stdin
unset GHCR_TOKEN

echo "=== Helm push: ${PACKAGE_PATH} -> oci://${PUSH_REPO} ==="
helm push "${PACKAGE_PATH}" "oci://${PUSH_REPO}"

cat <<DONE

=== Done ===
  pushed: ${PUBLISHED_REF}

=== Operator follow-ups ===
  Pull check: HELM_REGISTRY_CONFIG="\$(mktemp)" helm pull ${PUBLISHED_REF%:*} --version ${CHART_VERSION}
  Packages UI: https://github.com/orgs/$(awk -F/ '{ print $2 }' <<<"${GHCR_CHART_REF}")/packages
DONE
