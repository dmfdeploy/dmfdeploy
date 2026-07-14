#!/usr/bin/env bash
# dmf-env-public-surface-gate.sh — fail-closed gate: is a dmf-env tree
# safe to publish as a generic env-tooling repo?
#
# Usage:
#   bin/dmf-env-public-surface-gate.sh [dmf-env-tree]
#   (default: ./dmf-env from the umbrella root)
#
# Exits 0 only if all checks pass. Any failure prints file:line context
# and exits 1.
#
# This is the PERMANENT publish gate (part of the export-scan harness). It
# scans EVERY tracked file — including README/CLAUDE/QWEN/terraform-README.
# There is no per-file exemption: a published file that carries operator
# identity must fail the gate, full stop.

set -uo pipefail

TREE="${1:-./dmf-env}"
if [ ! -d "$TREE" ]; then
  echo "FAIL: tree directory not found: $TREE" >&2
  exit 1
fi

FAIL=0
fail() { echo "FAIL: $*"; FAIL=1; }

# ── 1. Positive allowlist via anchored path-depth regex ────────────
# Flat dirs use [^/]+$ so future nested fixtures fail closed.
echo "━━━ Check 1: positive allowlist ━━━"
ALLOWLIST_RE='^(bin/[^/]+|bin/lib/[^/]+|terraform/hetzner/.+|terraform/modules/hetzner/.+|terraform/README\.md|tasks/hetzner/.+|templates/[^/]+|tests/[^/]+|docs/answers-file-schema\.md|README\.md|CLAUDE\.md|QWEN\.md|\.gitignore|\.sops\.yaml|LICENSE|NOTICE|VERSION|SECURITY\.md|CONTRIBUTING\.md|\.gitleaks\.toml|\.githooks/[^/]+|\.github/.+)$'
ALLOW_VIOLATIONS=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  # Retired mxl-media scripts are never allowed even under bin/.
  if printf '%s' "$path" | grep -q '^bin/mxl-media-'; then
    ALLOW_VIOLATIONS="${ALLOW_VIOLATIONS}  ${path}: retired mxl-media script"$'\n'
    continue
  fi
  if ! printf '%s' "$path" | grep -qE "$ALLOWLIST_RE"; then
    ALLOW_VIOLATIONS="${ALLOW_VIOLATIONS}  ${path}: not in allowlist"$'\n'
  fi
done < <(cd "$TREE" && git ls-files)

if [ -n "$ALLOW_VIOLATIONS" ]; then
  printf '%s' "$ALLOW_VIOLATIONS"
  fail "paths outside allowlist (see above)"
else
  echo "  OK — all tracked paths match allowlist"
fi

# ── 2. Ban list ────────────────────────────────────────────────────
echo "━━━ Check 2: ban list ━━━"
BAN_VIOLATIONS=""
while IFS= read -r path; do
  [ -n "$path" ] || continue
  case "$path" in
    inventories/*|manifests/*|envs/*|agentic/*|.qwen/*)
      BAN_VIOLATIONS="${BAN_VIOLATIONS}  ${path}: in banned directory"$'\n'; continue ;;
  esac
  case "$path" in
    *.tfstate*|*.tfvars|*.pem|*.key|secret_id*|openbao-keys*|*.shamir*|.env|.env.*)
      BAN_VIOLATIONS="${BAN_VIOLATIONS}  ${path}: banned file pattern"$'\n'; continue ;;
  esac
done < <(cd "$TREE" && git ls-files)

# Non-empty SOPS bundles (the repo-level empty .sops.yaml config is allowed).
while IFS= read -r path; do
  [ -n "$path" ] || continue
  case "$path" in .sops.yaml) continue ;; esac
  full="${TREE}/${path}"
  if [ -f "$full" ] && [ -s "$full" ]; then
    BAN_VIOLATIONS="${BAN_VIOLATIONS}  ${path}: non-empty SOPS bundle"$'\n'
  fi
done < <(cd "$TREE" && git ls-files '*.sops.yaml' '*.sops.yml')

if [ -n "$BAN_VIOLATIONS" ]; then
  printf '%s' "$BAN_VIOLATIONS"
  fail "banned paths/files found (see above)"
else
  echo "  OK — no banned paths or files"
fi

# ── 3. Retired-name / old-layout content scan (ALL tracked files) ──
echo "━━━ Check 3: retired-name content scan ━━━"
RETIRE_NAMES='aliyun-media|hetzner-arm|g2r6-foa9|aliyun-123|aws-sample|mxl-media|inventories/|manifests/'
RETIRE_VIOLATIONS=""
while IFS= read -r line; do
  [ -n "$line" ] || continue
  RETIRE_VIOLATIONS="${RETIRE_VIOLATIONS}  ${line#./}"$'\n'
done < <(cd "$TREE" && git grep -nIE "$RETIRE_NAMES" 2>/dev/null || true)

if [ -n "$RETIRE_VIOLATIONS" ]; then
  printf '%s' "$RETIRE_VIOLATIONS"
  fail "retired names / old-layout refs found in content (see above)"
else
  echo "  OK — no retired names in kept files"
fi

# ── 4. Content scan: THIN CALLER of the shared scan library (R1 §6) ──
# One implementation replaces the include-sourced greps + the unpinned
# default-rules gitleaks pass (spec Inconsistency #4): manifest-driven grep
# (private identity runs case-insensitively per its manifest entries, #137)
# + PINNED gitleaks under the ephemeral merged public+private config.
# HARDCODED dmf-env context; FAIL-CLOSED on a missing private manifest
# (§5.3) — this gate's never-skip philosophy, now library-enforced.
echo "━━━ Check 4: identity / topology / dev-secrets scan ━━━"
UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
if "$UMBRELLA_DIR/bin/dmf-scan" tree "$TREE" --context dmf-env | sed 's/^/  /'; then
  echo "  OK — no identity/topology/dev-secrets leaks in kept files"
else
  fail "content scan hits or scan config error (see above)"
fi

# ── Result ─────────────────────────────────────────────────────────
echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "OK — dmf-env tree is public-safe"
  exit 0
else
  echo "FAIL — dmf-env tree is NOT public-safe (see failures above)"
  exit 1
fi
