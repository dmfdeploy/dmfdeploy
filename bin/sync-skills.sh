#!/usr/bin/env bash
# sync-skills.sh — one canonical agent-neutral skills source, many per-agent views.
#
# Canonical skills live at <repo>/.agents/skills/<name>/ (tracked, PR-reviewed —
# the only tracked copy). Per-agent views at <repo>/.claude/skills/ and
# <repo>/.qwen/skills/ are GENERATED from canonical and gitignored, so a lesson
# one agent records reaches the others and auto-minted skills get a review gate
# instead of polluting the tree (ADR-0042, umbrella issue #46). Codex/Gemini/Cursor
# read .agents/skills/ natively and need no view.
#
# A skill's frontmatter may carry sync-control keys:
#   agents: [claude, qwen]   # which views to materialize into (absent ⇒ all)
#   visibility: operator-local | experimental   # synced to local views, never tracked
#
# Usage:
#   bin/sync-skills.sh                 # --apply: (re)generate per-agent views
#   bin/sync-skills.sh --apply         # same (explicit)
#   bin/sync-skills.sh --copy          # views as copies, not symlinks (no core.symlinks)
#   bin/sync-skills.sh --check         # verify the canonical-only invariant; exit 1 on violation
#   bin/sync-skills.sh --promote <name> # move .agents/skills/_inbox/<name> → canonical
#   bin/sync-skills.sh --repo <path>   # operate on a sibling repo's own .agents/skills/
#   bin/sync-skills.sh --umbrella-only # no-op flag for symmetry with the other checkers
#
# Exit: 0 clean, 1 drift/violation, 2 bad args.

set -uo pipefail

UMBRELLA_DIR="${UMBRELLA_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
BASE="$UMBRELLA_DIR"
AGENTS=(claude qwen)

MODE="apply"
COPY=0
PROMOTE_NAME=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --apply)         MODE="apply"; shift ;;
        --check)         MODE="check"; shift ;;
        --copy)          COPY=1; shift ;;
        --promote)       MODE="promote"; PROMOTE_NAME="${2:-}"; shift 2 ;;
        --repo)          BASE="$2"; shift 2 ;;
        --umbrella-only) shift ;;   # accepted for symmetry; this script is repo-local anyway
        -h|--help)
            sed -n '/^# sync-skills.sh/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

CANON="$BASE/.agents/skills"
INBOX="$CANON/_inbox"

# Read a skill's sync-control frontmatter. Prints two lines: "agents=<csv>" and
# "visibility=<val>" (empty when unset). Machine-written frontmatter only, so a
# tight regex parser is enough — no YAML dependency.
skill_meta() {
    python3 - "$1" <<'PY'
import re, sys
p = sys.argv[1]
agents = ""
visibility = ""
try:
    text = open(p, encoding="utf-8").read()
except OSError:
    print("agents="); print("visibility="); sys.exit(0)
m = re.match(r"^---\n(.*?)\n---", text, re.DOTALL)
block = m.group(1) if m else ""
a = re.search(r"^agents:\s*(.+)$", block, re.MULTILINE)
if a:
    raw = a.group(1).strip().strip("[]")
    agents = ",".join(x.strip().strip("'\"") for x in raw.split(",") if x.strip())
v = re.search(r"^visibility:\s*(\S+)", block, re.MULTILINE)
if v:
    visibility = v.group(1).strip().strip("'\"")
print("agents=" + agents)
print("visibility=" + visibility)
PY
}

# Does skill <dir> target agent <name>? (absent agents: ⇒ all agents.)
targets_agent() {
    local skill_md="$1" agent="$2" line agents=""
    while IFS= read -r line; do
        case "$line" in agents=*) agents="${line#agents=}" ;; esac
    done < <(skill_meta "$skill_md")
    [ -z "$agents" ] && return 0
    case ",$agents," in *",$agent,"*) return 0 ;; *) return 1 ;; esac
}

canonical_names() {
    [ -d "$CANON" ] || return 0
    for d in "$CANON"/*/; do
        [ -d "$d" ] || continue
        local n; n="$(basename "$d")"
        [ "$n" = "_inbox" ] && continue
        printf '%s\n' "$n"
    done
}

apply() {
    [ -d "$CANON" ] || { echo "FAIL: no canonical store at $CANON" >&2; exit 1; }
    local agent viewdir name skill_md target entry made=0 pruned=0
    for agent in "${AGENTS[@]}"; do
        viewdir="$BASE/.$agent/skills"
        mkdir -p "$viewdir"
        # Prune stale entries (skill gone, or no longer targets this agent).
        # Leave Claude's internal .system/ dir alone.
        for entry in "$viewdir"/*; do
            [ -e "$entry" ] || continue
            name="$(basename "$entry")"
            [ "$name" = ".system" ] && continue
            if [ ! -d "$CANON/$name" ] || ! targets_agent "$CANON/$name/SKILL.md" "$agent"; then
                rm -rf "$entry"; pruned=$((pruned + 1))
            fi
        done
        # Materialize each targeted canonical skill.
        while IFS= read -r name; do
            skill_md="$CANON/$name/SKILL.md"
            targets_agent "$skill_md" "$agent" || continue
            target="$viewdir/$name"
            if [ "$COPY" -eq 1 ]; then
                rm -rf "$target"
                cp -R "$CANON/$name" "$target"
            else
                # Relative symlink: <base>/.<agent>/skills/<name> → ../../.agents/skills/<name>
                local link="../../.agents/skills/$name"
                if [ -L "$target" ] && [ "$(readlink "$target")" = "$link" ]; then
                    continue
                fi
                rm -rf "$target"
                ln -s "$link" "$target"
            fi
            made=$((made + 1))
        done < <(canonical_names)
    done
    echo "OK: synced $(canonical_names | wc -l | tr -d ' ') canonical skill(s) → ${AGENTS[*]} views (made/refreshed=$made, pruned=$pruned)"
}

check() {
    local fail=0 tracked name skill_md agents visibility line

    # (1) Core invariant: nothing generated or un-promoted may be tracked.
    tracked="$(git -C "$BASE" ls-files -- .claude/skills .qwen/skills .agents/skills/_inbox 2>/dev/null)"
    if [ -n "$tracked" ]; then
        echo "  ✗ generated/inbox paths are git-tracked (must be gitignored):" >&2
        printf '%s\n' "$tracked" | sed 's/^/      /' >&2
        fail=$((fail + 1))
    fi

    # (2) Canonical frontmatter must parse (name + description); control keys valid.
    if [ -d "$CANON" ]; then
        while IFS= read -r name; do
            skill_md="$CANON/$name/SKILL.md"
            if [ ! -f "$skill_md" ]; then
                echo "  ✗ $name: missing SKILL.md" >&2; fail=$((fail + 1)); continue
            fi
            if ! grep -q '^name:' "$skill_md" || ! grep -q '^description:' "$skill_md"; then
                echo "  ✗ $name: SKILL.md frontmatter missing name/description" >&2; fail=$((fail + 1))
            fi
            agents=""; visibility=""
            while IFS= read -r line; do
                case "$line" in
                    agents=*)     agents="${line#agents=}" ;;
                    visibility=*) visibility="${line#visibility=}" ;;
                esac
            done < <(skill_meta "$skill_md")
            if [ -n "$agents" ]; then
                local a
                for a in ${agents//,/ }; do
                    case " ${AGENTS[*]} " in *" $a "*) ;; *) echo "  ✗ $name: agents: lists unknown agent '$a'" >&2; fail=$((fail + 1)) ;; esac
                done
            fi
            if [ -n "$visibility" ]; then
                case "$visibility" in operator-local|experimental) ;; *) echo "  ✗ $name: invalid visibility '$visibility'" >&2; fail=$((fail + 1)) ;; esac
            fi
        done < <(canonical_names)
    else
        echo "  ✗ no canonical store at $CANON" >&2; fail=$((fail + 1))
    fi

    # (3) Public-safety: skills are reviewed, public-trajectory content — no
    # private IPs and no operator home paths may hide in them. Placeholders
    # (<node-priv-ip>, ~/...) pass; literals fail. Enforced in CI regardless of
    # any operator-local gitleaks rules.
    if [ -d "$CANON" ]; then
        local leaks
        leaks="$(python3 - "$CANON" <<'PY'
import os, re, sys
base = sys.argv[1]
ip = re.compile(r'\b(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b')
home = re.compile(r'/(?:Users|home)/(?!<)[A-Za-z0-9._-]+')
for root, _dirs, files in os.walk(base):  # followlinks=False: skips symlinked views
    if os.sep + "_inbox" in root:
        continue
    for fn in files:
        p = os.path.join(root, fn)
        try:
            lines = open(p, encoding="utf-8").read().splitlines()
        except (OSError, UnicodeDecodeError):
            continue
        for i, line in enumerate(lines, 1):
            for m in ip.finditer(line):
                print(f"{os.path.relpath(p, base)}:{i}: private IP literal {m.group()}")
            for m in home.finditer(line):
                print(f"{os.path.relpath(p, base)}:{i}: operator home path {m.group()}")
PY
)"
        if [ -n "$leaks" ]; then
            echo "  ✗ identifying elements in skills (use placeholders — see CLAUDE.md conventions):" >&2
            printf '%s\n' "$leaks" | sed 's/^/      /' >&2
            fail=$((fail + 1))
        fi
    fi

    # (4) Local view drift (skipped where views are absent, e.g. CI checkout).
    local agent viewdir name
    for agent in "${AGENTS[@]}"; do
        viewdir="$BASE/.$agent/skills"
        [ -d "$viewdir" ] || { echo "  · .$agent/skills absent (regenerate with --apply)"; continue; }
        while IFS= read -r name; do
            targets_agent "$CANON/$name/SKILL.md" "$agent" || continue
            [ -e "$viewdir/$name" ] || { echo "  ✗ .$agent/skills/$name missing (run --apply)" >&2; fail=$((fail + 1)); }
        done < <(canonical_names)
    done

    if [ "$fail" -gt 0 ]; then
        echo "FAIL: $fail skills-sync violation(s); canonical: .agents/skills/ — run bin/sync-skills.sh to refresh" >&2
        exit 1
    fi
    echo "OK: skills-sync invariant holds ($(canonical_names | wc -l | tr -d ' ') canonical skill(s))"
}

promote() {
    [ -n "$PROMOTE_NAME" ] || { echo "FAIL: --promote needs a skill name" >&2; exit 2; }
    local src="$INBOX/$PROMOTE_NAME" dst="$CANON/$PROMOTE_NAME"
    [ -d "$src" ] || { echo "FAIL: no inbox skill at $src" >&2; exit 1; }
    [ -e "$dst" ] && { echo "FAIL: canonical skill already exists: $dst" >&2; exit 1; }
    git -C "$BASE" mv "$src" "$dst" 2>/dev/null || mv "$src" "$dst"
    echo "OK: promoted $PROMOTE_NAME → canonical (stage + commit, then run --apply)"
}

case "$MODE" in
    apply)   apply ;;
    check)   check ;;
    promote) promote ;;
esac
