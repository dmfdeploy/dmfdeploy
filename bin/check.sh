#!/usr/bin/env bash
# check.sh — run the umbrella's CI checks from one command.
#
# Each step is one CI job, and the job runs `bin/check.sh <step>`, so a local
# run and CI run the same commands. Tool versions and the platform can still
# differ. Without a step name the script runs every step in the order below.
#
# Usage:
#   bin/check.sh                        # every step
#   bin/check.sh STEP [STEP...]         # only the named steps
#
# Steps:
#   - shellcheck       ShellCheck over the scripts, then the self-tests and the
#                      regression tests of the other gates (ci.yml)
#   - review-comments  no review history in code comments (ci.yml)
#   - check-docs       plans index, doc gate, working-model block (ci.yml)
#   - skills-sync      the canonical skills store is the only tracked copy (ci.yml)
#   - surface          size budgets, filenames, archive placement (surface.yml)
#   - static           issue forms, CODEOWNERS and the PR template (title-check.yml)
#   - vale             the voice checks (vale.yml)
#
# Environment:
#   VOICE_RATCHET_BASE  vale step only. A committed ref, such as origin/main.
#                       The step then also fails when a Markdown file that
#                       HEAD changes gains an error-level voice alert.
#
# Before it runs anything, the script checks that every tool the chosen steps
# need is installed, and prints what is missing. The `vale` step also needs the
# Google style package: run `vale sync` once.
#
# Exit: 0 every chosen step passed; 1 a step failed; 2 bad usage or a missing tool.

set -euo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$UMBRELLA_DIR"

ALL_STEPS="shellcheck review-comments check-docs skills-sync surface static vale"
VALE_MIN="3.25.1"
PYTHON_MIN="3.11"

usage() {
    sed -n '/^# check.sh/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

# ── Preflight ────────────────────────────────────────────────────────────────

problems=""

add_problem() {  # add_problem <message>, once
    case "$problems" in
        *"  $1"$'\n'*) ;;
        *) problems="${problems}  $1"$'\n' ;;
    esac
}

want_tool() {  # want_tool <command> <how to get it>
    command -v "$1" >/dev/null 2>&1 || add_problem "$1 is not installed. $2"
}

want_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        add_problem "python3 is not installed. Install Python ${PYTHON_MIN} or later."
    elif ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'; then
        add_problem "python3 is older than ${PYTHON_MIN}. Use a newer interpreter."
    fi
}

want_vale() {
    local have
    if ! command -v vale >/dev/null 2>&1; then
        add_problem "vale is not installed. Install Vale ${VALE_MIN} or later (https://vale.sh)."
        return 0
    fi
    have="$(vale --version | sed -n 's/^vale version //p')"
    if ! command -v python3 >/dev/null 2>&1 \
        || ! python3 -c 'import sys
want = tuple(int(n) for n in sys.argv[2].split("."))
have = tuple(int(n) for n in sys.argv[1].split(".")[:3])
sys.exit(0 if have >= want else 1)' "$have" "$VALE_MIN"; then
        add_problem "vale ${have:-unknown} is older than ${VALE_MIN}. Upgrade Vale."
    fi
    if [ ! -d .vale/styles/Google ]; then
        add_problem "the Google style package is missing. Run: vale sync"
    fi
}

preflight() {  # preflight <step>
    case "$1" in
        shellcheck)
            want_python
            want_tool shellcheck "Install ShellCheck (https://www.shellcheck.net/)."
            want_tool jq "Install jq."
            want_tool ruby "Install Ruby."
            ;;
        review-comments | check-docs | skills-sync | surface)
            want_python
            ;;
        static)
            want_tool jq "Install jq."
            want_tool ruby "Install Ruby."
            ;;
        vale)
            want_python
            want_vale
            ;;
    esac
}

# ── Steps ────────────────────────────────────────────────────────────────────

step_shellcheck() {
    local scripts
    shopt -s nullglob
    scripts=(bin/*.sh bin/lib/*.sh tests/*.sh)
    shopt -u nullglob
    # Warnings and errors fail the step. Style and info findings stay advisory.
    shellcheck --severity=warning "${scripts[@]}"
    bash bin/close-completed-issues.sh --self-test
    python3 bin/lib/closing_refs.py --self-test
    python3 -m unittest discover -s tests -p 'test_issue_link_rerun.py' -v
    python3 -m unittest discover -s tests -p 'test_session_link_gate.py' -v
    bash tests/session-link-commitlint.sh
    bash tests/dco-commit-count.sh
    bash tests/worktree-regression.sh
    bash tests/hook-scoping.sh
    # Shape check only. The live comparison runs on a schedule in
    # governance-drift.yml with no credential, because a token there would be
    # reachable by code from a pull request.
    python3 - .github/expected-ruleset.json <<'PY'
import json
import sys

d = json.load(open(sys.argv[1]))
need = ['name', 'target', 'enforcement', 'conditions', 'rule_types',
        'required_status_checks', 'pull_request']
missing = [k for k in need if k not in d]
if missing:
    sys.exit('expectation missing keys: ' + ', '.join(missing))
if not isinstance(d['required_status_checks'], list) or not d['required_status_checks']:
    sys.exit('required_status_checks must be a non-empty list')
if 'bypass_actor_count' in d:
    sys.exit('expectation carries bypass_actor_count, which the drift check does NOT read; remove it')
print('expectation well-formed:', len(d['required_status_checks']), 'required checks')
PY
    bash tests/ruleset-drift.sh
    bash tests/automerge-live-state.sh
    bash tests/sync-skills-prune.sh
    bash tests/live-env-leak.sh
    bash tests/ghcr-publish-user.sh
    bash tests/hygiene-modes.sh
    python3 bin/gen-gitleaks-rules.py --check
    python3 bin/gen-gitleaks-rules.py --self-test
    bin/dmf-scan self-test
    bash tests/acceptance-matrix.sh
}

step_review_comments() {
    bin/check-review-comments.sh
    bin/check-review-comments.sh --self-test
}

step_check_docs() {
    bin/generate-plans-index.sh --check
    bin/check-docs.sh
    bin/check-working-model-sync.sh --umbrella-only
}

step_skills_sync() {
    bin/sync-skills.sh --check --umbrella-only
}

step_surface() {
    tests/surface/run.sh
    bin/check-surface.sh --strict size
    bin/check-surface.sh --strict filenames
    bin/check-surface.sh --strict placement
    bin/check-surface.sh --strict statuslog
    bin/check-surface.sh --strict enforcement
}

step_static() {
    .github/scripts/hygiene-check.sh real
    .github/scripts/hygiene-check.sh fixtures
}

step_vale() {
    local bad good
    vale .
    grep -v -e '^#' -e '^[[:space:]]*$' .vale/clean-set.txt \
        | xargs vale --minAlertLevel=error
    .vale/scope-test.sh
    for bad in .vale/fixtures/bad-*.md; do
        good="${bad/bad-/good-}"
        if vale --config .vale/strict.ini "$bad" >/dev/null; then
            echo "$bad passed but must fail" >&2
            return 1
        fi
        vale --config .vale/strict.ini "$good" >/dev/null \
            || { echo "$good must pass" >&2; return 1; }
    done
    bin/check-voice-fixtures.sh
    bin/mutate-voice.sh
    if [ -n "${VOICE_RATCHET_BASE:-}" ]; then
        bin/check-voice-changed.sh "$VOICE_RATCHET_BASE" HEAD
    fi
    tests/voice-changed-head.sh
    tests/voice-changed-links.sh
}

# ── Main ─────────────────────────────────────────────────────────────────────

steps=""
for arg in "$@"; do
    case "$arg" in
        -h | --help)
            usage
            exit 0
            ;;
        *)
            case " $ALL_STEPS " in
                *" $arg "*) steps="$steps $arg" ;;
                *)
                    echo "check: unknown step '$arg'" >&2
                    usage >&2
                    exit 2
                    ;;
            esac
            ;;
    esac
done
[ -n "$steps" ] || steps="$ALL_STEPS"

for s in $steps; do
    preflight "$s"
done
if [ -n "$problems" ]; then
    echo "check: cannot run, a tool is missing or too old:" >&2
    printf '%s' "$problems" >&2
    exit 2
fi

current=""
trap '[ $? -eq 0 ] || echo "check: step ${current:-?} failed" >&2' EXIT

for s in $steps; do
    current="$s"
    echo "==> check: $s"
    "step_${s//-/_}"
    echo "check: $s ok"
done
current=""
