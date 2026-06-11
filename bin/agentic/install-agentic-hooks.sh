#!/usr/bin/env bash
# MOTHBALLED 2026-06-04 (historical, fails closed): bin/agentic/install-agentic-hooks.sh — install agentic-harness git hooks
# into the umbrella and (optionally) every public component repo.
#
# Operator-driven. Idempotent. Companion to the umbrella's `bin/install-hooks.sh`
# which only configures the umbrella itself.
#
# What it installs:
#
#   Per repo:
#     <repo>/.githooks/pre-push  ← copied from bin/agentic/templates/pre-push
#                                  (refuses push to `github` remote unless
#                                   SYNC_TO_GITHUB=1 from sync-to-github.sh)
#
#   Component repos only (umbrella already has its richer pre-commit):
#     <repo>/.githooks/pre-commit ← copied from bin/agentic/templates/pre-commit
#                                   (gitleaks-only minimal hook)
#
#   Per repo:
#     `git config core.hooksPath .githooks`
#
# What it does NOT install:
#   - Anything outside .githooks/. The umbrella's existing pre-commit
#     (with STATUS.md auto-refresh) stays untouched.
#   - Anything in dmf-env (private — never participates in public publish
#     posture; Constitution Rule 13).
#
# Usage:
#   bin/agentic/install-agentic-hooks.sh                 # umbrella + all 6 public
#   bin/agentic/install-agentic-hooks.sh --umbrella-only # just umbrella pre-push
#   bin/agentic/install-agentic-hooks.sh --repo dmf-cms  # single component repo
#   bin/agentic/install-agentic-hooks.sh --dry-run       # print actions only
#
# Idempotency:
#   - If the target file exists with byte-identical content → "already-installed"
#   - If the target file exists with DIFFERENT content → halt + report drift
#     (operator decides whether to accept upstream changes via --force)
#   - --force overwrites without prompting
#
# Refs:
#   docs/agentic/CONSTITUTION.md Rule 1 (push gate) + Rule 2 (secret gate)
#   docs/plans/DMF Agentic Harness Plan 2026-05-11.md §Layer 2

set -euo pipefail

if [[ "${DMF_AGENTIC_OVERRIDE:-}" != "1" ]]; then
    echo "mothballed 2026-06-04 — set DMF_AGENTIC_OVERRIDE=1 to run" >&2
    exit 1
fi

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
TEMPLATE_DIR="$UMBRELLA_DIR/bin/agentic/templates"

PUBLIC_REPOS=(dmf-cms dmf-runbooks dmf-central dmf-infra dmf-media dmf-init)

DRY_RUN=0
FORCE=0
UMBRELLA_ONLY=0
TARGET_REPO=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dry-run)        DRY_RUN=1; shift ;;
        --force)          FORCE=1; shift ;;
        --umbrella-only)  UMBRELLA_ONLY=1; shift ;;
        --repo)           TARGET_REPO="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

# Sanity-check templates exist before doing anything.
for t in pre-push pre-commit; do
    if [ ! -f "$TEMPLATE_DIR/$t" ]; then
        echo "missing template: $TEMPLATE_DIR/$t" >&2
        exit 1
    fi
done

# install_hook <repo-path> <hook-name> <skip-if-umbrella-pre-commit>
# Returns 0 on success or already-installed; non-zero on drift refusal.
install_hook() {
    local repo_path="$1"
    local hook_name="$2"
    local skip_umbrella_precommit="${3:-0}"

    # The umbrella has its own richer pre-commit (auto-refreshes STATUS.md +
    # docs/SCRIPTS.md). Never overwrite it with the minimal template.
    if [ "$skip_umbrella_precommit" = "1" ] && [ "$hook_name" = "pre-commit" ]; then
        echo "    · pre-commit (umbrella) — keeping existing richer hook"
        return 0
    fi

    local src="$TEMPLATE_DIR/$hook_name"
    local dst="$repo_path/.githooks/$hook_name"

    if [ -f "$dst" ]; then
        if cmp -s "$src" "$dst"; then
            echo "    · $hook_name — already installed (byte-identical)"
            return 0
        fi
        if [ "$FORCE" = 1 ]; then
            if [ "$DRY_RUN" = 1 ]; then
                echo "    ↻ $hook_name — would overwrite (--force, --dry-run)"
            else
                cp "$src" "$dst"
                chmod 0755 "$dst"
                echo "    ↻ $hook_name — overwritten (--force)"
            fi
            return 0
        fi
        echo "    ⚠ $hook_name — DRIFT: existing file differs from template" >&2
        echo "        existing: $dst" >&2
        echo "        template: $src" >&2
        echo "        diff:" >&2
        diff -u "$dst" "$src" | head -20 | sed 's/^/          /' >&2
        echo "        resolve: --force to overwrite, or sync manually" >&2
        return 1
    fi

    if [ "$DRY_RUN" = 1 ]; then
        echo "    + $hook_name — would install"
    else
        mkdir -p "$repo_path/.githooks"
        cp "$src" "$dst"
        chmod 0755 "$dst"
        echo "    + $hook_name — installed"
    fi
    return 0
}

# configure_hookspath <repo-path>
configure_hookspath() {
    local repo_path="$1"
    local current
    current="$(git -C "$repo_path" config --get core.hooksPath 2>/dev/null || true)"
    if [ "$current" = ".githooks" ]; then
        echo "    · core.hooksPath — already set to .githooks"
        return 0
    fi
    if [ "$DRY_RUN" = 1 ]; then
        echo "    + core.hooksPath — would set to .githooks (was: '${current:-<unset>}')"
        return 0
    fi
    git -C "$repo_path" config core.hooksPath .githooks
    echo "    + core.hooksPath — set to .githooks (was: '${current:-<unset>}')"
}

failures=0

# ── Umbrella ─────────────────────────────────────────────────────────────────

if [ -z "$TARGET_REPO" ] || [ "$TARGET_REPO" = "." ] || [ "$TARGET_REPO" = "umbrella" ]; then
    echo "── umbrella (.)"
    install_hook "$UMBRELLA_DIR" pre-push 0 || failures=$((failures + 1))
    install_hook "$UMBRELLA_DIR" pre-commit 1 || failures=$((failures + 1))
    configure_hookspath "$UMBRELLA_DIR"
    echo
fi

# ── Component repos ──────────────────────────────────────────────────────────

if [ "$UMBRELLA_ONLY" = 0 ]; then
    for r in "${PUBLIC_REPOS[@]}"; do
        if [ -n "$TARGET_REPO" ] && [ "$r" != "$TARGET_REPO" ]; then
            continue
        fi
        if [ ! -d "$UMBRELLA_DIR/$r/.git" ]; then
            echo "── $r — repo not present locally; skipping"
            echo
            continue
        fi
        echo "── $r"
        install_hook "$UMBRELLA_DIR/$r" pre-push 0 || failures=$((failures + 1))
        install_hook "$UMBRELLA_DIR/$r" pre-commit 0 || failures=$((failures + 1))
        configure_hookspath "$UMBRELLA_DIR/$r"
        echo
    done
fi

echo "── summary"
if [ "$failures" -gt 0 ]; then
    echo "  FAIL — $failures hook(s) reported drift; resolve with --force or manual sync"
    exit 1
fi
if [ "$DRY_RUN" = 1 ]; then
    echo "  OK — dry-run; no files written"
else
    echo "  OK — agentic hooks installed"
fi
