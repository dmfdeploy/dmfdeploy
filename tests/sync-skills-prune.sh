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
#   D  a MISSING canonical SKILL.md must not read as "targets all agents"
#      (skill_meta prints an empty agents= on OSError, indistinguishable from a
#      legitimately absent agents: key). NOTE: this case also fails on the
#      pre-fix script, because check step (2) independently flags a missing
#      SKILL.md — it does not isolate the fail-closed change. Case E does.
#   E  an UNREADABLE-but-present SKILL.md must not materialize the skill into a
#      view it does not target. A `-f` test passes for such a file, so the
#      empty agents= from the OSError handler still read as "all agents" and
#      --apply projected a qwen-only skill into the claude view. Asserts on
#      --apply's actual output, not on --check, because that is the surface
#      that puts a malformed skill in front of an agent.
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
expect "D: missing SKILL.md fails closed" 1 "$(check_rc)"

# E: present but unreadable. Must not project a qwen-only skill into .claude/.
# Skipped as root, where a mode-000 file is still readable and the fixture
# cannot express the condition.
build "agents: [qwen]"
rm -rf "$ROOT/.claude/skills/alpha"          # not targeted; start from truth
chmod 000 "$ROOT/.agents/skills/alpha/SKILL.md"
if cat "$ROOT/.agents/skills/alpha/SKILL.md" >/dev/null 2>&1; then
    echo "  · E skipped: SKILL.md still readable after chmod 000 (running as root?)"
else
    "$SCRIPT" --repo "$ROOT" --apply >/dev/null 2>&1
    if [ -e "$ROOT/.claude/skills/alpha" ] || [ -L "$ROOT/.claude/skills/alpha" ]; then
        bad "E: unreadable SKILL.md projected into a view it does not target"
    else
        ok "E: unreadable SKILL.md fails closed (not projected)"
    fi
fi
chmod 644 "$ROOT/.agents/skills/alpha/SKILL.md" 2>/dev/null || true

echo "sync-skills-prune: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
