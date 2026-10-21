#!/usr/bin/env bash
# Ratchet the error-level Voice alerts in the Markdown files a change touches.
#
# For each Markdown file that HEAD adds or modifies relative to BASE and that
# .vale.ini lints, count the error-level Voice alerts (Contrast and EmDash) at
# BASE and at HEAD. The check fails when a file has more at HEAD. A new file
# counts 0 at BASE; a renamed file with edits counts at its old path. Deleted
# files and pure renames are skipped.
#
# This blocks new occurrences without asking for a cleanup of the whole
# corpus first: a file with older alerts passes as long as the PR adds none.
# Both sides are linted with HEAD's rules and a config derived from HEAD's
# .vale.ini, so the scope and the archive exemption match the warn-mode run.
# The whole-tree run stays in warn mode.
#
# Vale reports one alert where the same match (say, two em dashes) occurs
# twice in one Markdown block, so a raw count can miss a new one. Each side
# is linted as a copy with a blank line after every line, which makes every
# line its own block; alert lines are mapped back to the real file.
#
# Usage: bin/check-voice-changed.sh BASE [HEAD]
#   HEAD defaults to HEAD and must be the checked-out tree.
#   Exit 0: no file gained an alert.  Exit 1: at least one did.
#   Exit 2: bad usage, or git or Vale failed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 BASE [HEAD]" >&2
  exit 2
fi
base="$1" head="${2:-HEAD}"
command -v vale >/dev/null || { echo "check-voice-changed: vale is not installed" >&2; exit 2; }
command -v python3 >/dev/null || { echo "check-voice-changed: python3 is required" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git -C "$root" diff --name-status -z -M --diff-filter=AMR "$base" "$head" >"$tmp/diff" \
  || { echo "check-voice-changed: git diff $base $head failed" >&2; exit 2; }

# Changed Markdown files at HEAD, each with its BASE path (empty when new).
files=() olds=()
while IFS= read -r -d '' status; do
  IFS= read -r -d '' path
  old=""
  case "$status" in
    R100) IFS= read -r -d '' path; continue ;;          # pure rename: skip
    R*) old="$path"; IFS= read -r -d '' path ;;         # rename with edits
    M) old="$path" ;;
  esac
  if [[ "$path" == *.md && -f "$root/$path" ]]; then
    files+=("$path")
    olds+=("$old")
  fi
done <"$tmp/diff"

if [[ ${#files[@]} -eq 0 ]]; then
  echo "check-voice-changed: 0 linted Markdown files changed"
  exit 0
fi

derive() { # derive <styles> <out>: .vale.ini with every styled section set to <styles>
  sed -e "s|^StylesPath = .*|StylesPath = $root/.vale/styles|" \
    -e 's/^MinAlertLevel = .*/MinAlertLevel = error/' -e '/^Packages =/d' \
    -e "s/^BasedOnStyles = ..*/BasedOnStyles = $1/" "$root/.vale.ini" >"$2"
}
derive Voice "$tmp/voice.ini"
# The probe style fires once on any file, so its JSON keys are the files that
# .vale.ini lints. Vale's own glob matcher decides the scope.
mkdir -p "$tmp/probe/Probe"
printf '%s\n' 'extends: existence' 'message: "in scope"' 'level: error' \
  'scope: raw' 'nonword: true' 'tokens:' "  - '\\A'" >"$tmp/probe/Probe/Hit.yml"
derive Probe "$tmp/probe.ini"
sed -i.bak "s|^StylesPath = .*|StylesPath = $tmp/probe|" "$tmp/probe.ini"
sed -i.bak '/^Vocab =/d' "$tmp/probe.ini"

# Spread copies sit at their real paths in scratch trees, because Vale
# matches .vale.ini globs against the path relative to the working directory.
spread() { # spread <out>: stdin with a blank line after every line
  mkdir -p "$(dirname "$1")"
  python3 -I -c 'import sys; sys.stdout.write("\n\n".join(sys.stdin.read().split("\n")))' >"$1"
}
for f in "${files[@]}"; do
  spread "$tmp/head/$f" <"$root/$f"
done
base_files=()
for old in "${olds[@]}"; do
  [[ -n "$old" ]] || continue
  git -C "$root" show "$base:$old" >"$tmp/raw" \
    || { echo "check-voice-changed: git show $base:$old failed" >&2; exit 2; }
  spread "$tmp/base/$old" <"$tmp/raw"
  base_files+=("$old")
done
mkdir -p "$tmp/base"

lint() { # lint <dir> <config> <out> FILE...
  local dir="$1" ini="$2" out="$3"
  shift 3
  (cd "$dir" && vale --no-exit --output=JSON --config "$ini" "$@") >"$out" \
    || { echo "check-voice-changed: vale failed in $dir" >&2; exit 2; }
}
lint "$root" "$tmp/probe.ini" "$tmp/scope.json" "${files[@]}"
lint "$tmp/head" "$tmp/voice.ini" "$tmp/head.json" "${files[@]}"
echo '{}' >"$tmp/base.json"
if [[ ${#base_files[@]} -gt 0 ]]; then
  lint "$tmp/base" "$tmp/voice.ini" "$tmp/base.json" "${base_files[@]}"
fi

for i in "${!files[@]}"; do
  printf '%s\0%s\0' "${files[$i]}" "${olds[$i]}"
done >"$tmp/pairs"

python3 -I - "$tmp/pairs" "$tmp/scope.json" "$tmp/head.json" "$tmp/base.json" <<'PY'
import json, os, sys
pairs_path, scope_js, head_js, base_js = sys.argv[1:5]
raw = open(pairs_path, encoding="utf-8").read().split("\0")[:-1]
pairs = list(zip(raw[0::2], raw[1::2]))
scope = json.load(open(scope_js))
head = json.load(open(head_js))
base = json.load(open(base_js))
gha = bool(os.environ.get("GITHUB_ACTIONS"))
checked = failed = 0
for new, old in pairs:
    if new not in scope:
        continue
    checked += 1
    alerts = head.get(new, [])
    n_head, n_base = len(alerts), len(base.get(old, [])) if old else 0
    if n_head <= n_base:
        continue
    failed += 1
    since = f"{old} at BASE" if old else "a new file"
    print(f"{new}: {n_head} error-level Voice alert(s), up from {n_base} ({since})")
    for a in alerts:
        line = (a["Line"] + 1) // 2  # spread copy line -> real line
        msg = f'{a["Check"]}: {a["Message"]}'
        if gha:
            print(f'::error file={new},line={line},col={a["Span"][0]}::{msg}')
        else:
            print(f'  {new}:{line}:{a["Span"][0]}: {msg}')
print(f"check-voice-changed: {checked} linted Markdown file(s) checked, "
      f"{failed} gained error-level Voice alerts. See docs/STYLE.md.")
sys.exit(1 if failed else 0)
PY
