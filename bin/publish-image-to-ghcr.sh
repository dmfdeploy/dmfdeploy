#!/usr/bin/env bash
# publish-image-to-ghcr.sh — generic helper to publish one or more locally-built
# images to GHCR. Replaces the per-repo publish-to-ghcr.sh duplication
# (NMOS, AWX EE, dmf-cms) introduced in the 2026-05-19 Lane A work.
#
# Each component repo retains a *thin* wrapper at its conventional path
# (e.g. dmf-infra/k3s-lab-bootstrap/ee/scripts/publish-to-ghcr.sh) that
# resolves its repo-specific image list + tag policy and then `exec`s
# this script. The umbrella is the single source of truth for auth +
# push behaviour (token-via-stdin, isolated DOCKER_CONFIG with cleanup
# trap, isolated docker context).
#
# Secrets posture (ADR-0007, dmf-cluster-access skill §0):
#   - GHCR token read from stdin only — never argv, never echoed.
#   - Isolated DOCKER_CONFIG so the login doesn't leak into ~/.docker.
#   - Cleanup trap removes the temp config on any exit.
#
# Usage:
#
#   publish-image-to-ghcr.sh <src1> <dst1> [<src2> <dst2> ...]
#
#   Pair the source local image with the target GHCR ref. Args come in
#   pairs; image refs include the tag.
#
#   Interactive (token at prompt):
#     publish-image-to-ghcr.sh src1:tag dst1:tag src2:tag dst2:tag
#
#   Piped (token from stdin, e.g. macOS Keychain):
#     security find-generic-password -s "ghcr.io" -a "$USER" -w \
#       | GHCR_USER="$USER" publish-image-to-ghcr.sh src1:tag dst1:tag
#
# Env knobs:
#   GHCR_USER     GitHub username (prompts if unset and stdin is a tty)
#   DOCKER_HOST   defaults to Colima docker-build socket
#
# Output:
#   For each pushed pair: a `pushed: <dst>` line followed by `digest: <repo-digest>`.
#   At the end: a "next steps" hint with the GitHub Packages UI link.

set -euo pipefail

# Arg parsing ----------------------------------------------------------------

if [[ $# -lt 2 ]] || (( $# % 2 != 0 )); then
  cat >&2 <<USAGE
Usage: $(basename "$0") <src1> <dst1> [<src2> <dst2> ...]

Provide one or more (source-local-ref, target-ghcr-ref) pairs. Args come
in pairs; both refs include the tag.

Example:
  $(basename "$0") \\
    registry.dmf.example.com/dmf/awx-ee:0.1.0 ghcr.io/dmfdeploy/awx-ee:0.1.0
USAGE
  exit 2
fi

PAIRS=("$@")

# Preflight ---------------------------------------------------------------

export DOCKER_HOST="${DOCKER_HOST:-unix://$HOME/.colima/docker-build/docker.sock}"
if ! docker info >/dev/null 2>&1; then
  echo "ERROR: docker daemon at \$DOCKER_HOST=$DOCKER_HOST is not reachable." >&2
  echo "       Is the Colima docker-build profile running?" >&2
  exit 1
fi

echo "=== Verifying local source images ==="
i=0
while (( i < ${#PAIRS[@]} )); do
  src="${PAIRS[$i]}"
  if ! docker image inspect "$src" >/dev/null 2>&1; then
    echo "ERROR: local image $src not found." >&2
    echo "       Build it first (see the repo's build script)." >&2
    exit 1
  fi
  arch=$(docker image inspect "$src" --format '{{.Architecture}}/{{.Os}}')
  echo "  ok: $src ($arch)"
  i=$(( i + 2 ))
done

# Credentials --------------------------------------------------------------

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

# Isolated DOCKER_CONFIG so the GHCR token doesn't bleed into ~/.docker.
DOCKER_CONFIG="$(mktemp -d)"
export DOCKER_CONFIG
cleanup() {
  rm -rf "${DOCKER_CONFIG}"
  unset DOCKER_CONFIG
}
trap cleanup EXIT INT TERM

# Login --------------------------------------------------------------------

echo "=== Docker login to ghcr.io ==="
printf '%s' "${GHCR_TOKEN}" | docker login ghcr.io -u "${GHCR_USER}" --password-stdin
unset GHCR_TOKEN

# Tag + push --------------------------------------------------------------

PUSHED=()
DIGESTS=()
GHCR_NAMESPACES=()
i=0
while (( i < ${#PAIRS[@]} )); do
  src="${PAIRS[$i]}"
  dst="${PAIRS[$(( i + 1 ))]}"
  echo "=== Tag + push: $src → $dst ==="
  docker tag "$src" "$dst"
  docker push "$dst"
  digest=$(docker image inspect "$dst" --format '{{index .RepoDigests 0}}' 2>/dev/null || echo "(unavailable from local inspect)")
  PUSHED+=("$dst")
  DIGESTS+=("$digest")
  # Capture the namespace for the "next steps" link.
  ns=$(echo "$dst" | awk -F/ '{print $2}')
  GHCR_NAMESPACES+=("$ns")
  i=$(( i + 2 ))
done

# Report ------------------------------------------------------------------

echo ""
echo "=== Done ==="
for i in "${!PUSHED[@]}"; do
  echo "  pushed: ${PUSHED[$i]}"
  echo "  digest: ${DIGESTS[$i]}"
done

# Unique-ify namespaces for the link line.
unique_ns=$(printf '%s\n' "${GHCR_NAMESPACES[@]}" | sort -u | tr '\n' ' ')
echo ""
echo "=== Operator follow-ups ==="
for ns in $unique_ns; do
  echo "  Packages UI: https://github.com/orgs/${ns}/packages"
done
echo "  - Link new packages to source repos (Settings → Link a repository)."
echo "  - Set visibility (Settings → Danger Zone → Change visibility)."
echo "  - Record digests in release notes / STATUS.md."
