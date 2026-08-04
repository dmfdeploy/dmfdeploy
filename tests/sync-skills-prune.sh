#!/usr/bin/env bash
# sync-skills-prune.sh — regressions for the stale-generated-view defects
# (umbrella issue #364; all three reproduced against the pre-fix script):
#
#   A  a DANGLING view symlink must be detected. Views are symlinks by default,
#      so deleting a canonical skill leaves a dangling link — `-e` follows the
#      link and is false for one, so an `-e`-only guard skipped exactly the
#      entry that most needs pruning.
#   B  a stale --copy DIRECTORY (canonical gone) must be detected.
#   C  a view whose skill no longer TARGETS that agent must be detected.
#   D  an unreadable canonical SKILL.md must not read as "targets all agents"
#      (skill_meta prints an empty agents= on OSError, indistinguishable from a
#      legitimately absent agents: key). NOTE: this case also fails on the
#      pre-fix script, because check step (2) independently flags a missing
#      SKILL.md — it does not isolate the fail-closed change.
#   ctrl  a clean tree still passes (the fix must not fire false positives).
#
# Why this matters beyond hygiene: per ADR-0042 the generated views are what
# Claude and qwen actually read, so a surviving view is a live instruction
# surface. Before the fix, `--check` reported the invariant holding both before
# and after a canonical skill was removed — a check that cannot fail in the
# direction that matters tests nothing.
#
# Hermetic: builds a synthetic repo tree and drives the real script via --repo.
set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRIPT="$UMBRELLA_DIR/bin/sync-skills.sh"
pass=0; fail=0
ok()  { echo "  ✓ $1"; pass=$((pass + 1)); }
bad() { echo "  ✗ $1" >&2; fail=$((fail + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dmf-sync-skills.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/repo"

# Build a minimal valid canonical skill + both generated views.
# $1 = an optional extra frontmatter line (e.g. "agents: [qwen]").
build() {
    rm -rf "$ROOT"
    mkdir -p "$ROOT/.agents/skills/alpha" "$ROOT/.claude/skills" "$ROOT/.qwen/skills"
    {
        echo '---'
        echo 'name: alpha'
        echo 'description: fixture skill'
        [ -n "${1:-}" ] && echo "$1"
        echo 'type: durable-pattern'
        echo 'scope: fixture'
        echo 'owner: operator'
        echo "review_by: '2099-01-01'"
        echo '---'
        echo 'body'
    } > "$ROOT/.agents/skills/alpha/SKILL.md"
    ln -s ../../.agents/skills/alpha "$ROOT/.claude/skills/alpha"
    ln -s ../../.agents/skills/alpha "$ROOT/.qwen/skills/alpha"
}

# Run --check against the fixture; echo its exit code.
check_rc() { "$SCRIPT" --repo "$ROOT" --check >/dev/null 2>&1; echo $?; }

expect() { # $1 label  $2 expected-rc  $3 actual-rc
    if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (exit $3, expected $2)"; fi
}

echo "sync-skills stale-view regressions (issue #364)"

build ""
expect "ctrl: clean tree passes" 0 "$(check_rc)"

build ""; rm -rf "$ROOT/.agents/skills/alpha"
expect "A: dangling view symlinks detected" 1 "$(check_rc)"

build ""
rm -rf "$ROOT/.claude/skills/alpha"
cp -R "$ROOT/.agents/skills/alpha" "$ROOT/.claude/skills/alpha"
rm -rf "$ROOT/.agents/skills/alpha" "$ROOT/.qwen/skills/alpha"
expect "B: stale --copy directory detected" 1 "$(check_rc)"

build "agents: [qwen]"
expect "C: de-targeted view detected" 1 "$(check_rc)"

build ""; rm -f "$ROOT/.agents/skills/alpha/SKILL.md"
expect "D: unreadable SKILL.md fails closed" 1 "$(check_rc)"

echo "sync-skills-prune: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
