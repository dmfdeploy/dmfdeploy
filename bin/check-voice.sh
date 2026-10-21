#!/usr/bin/env bash
# Lint prose against the project voice (Voice + Google + Dmfdeploy styles).
#
# Use it on any draft before you show it: an issue body, a PR body, a
# discussion post, or text for an external audience.
#
# Usage: bin/check-voice.sh [--conversational] FILE...
#   Exit 0: no error-level alert.
#   Exit 1: at least one error-level alert (a blocker).
#   Exit 2: bad usage, or Vale could not run.
#
# Voice rules run at suggestion level and up. Google and Dmfdeploy rules run
# at warning level and up. Both passes read every file you pass, whether or
# not .vale.ini has a section for it.
#
# Conversational mode is for issues, PR bodies and external text, which talk
# to a reader as "we" and quote literal strings. It turns off Google.We and
# Google.Will and lowers Google.Quotes to a warning. A file gets it when you
# pass --conversational, or when .vale.ini does not lint the file (any file
# outside the repo, such as a draft in a temporary directory). Files that
# .vale.ini lints get the documentation mode, which uses the rules as is.
#
# Environment:
#   VOICE_ROOT  Directory that holds .vale.ini and .vale/styles.
#               Default: the repo root.
set -euo pipefail

root="${VOICE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
styles="$root/.vale/styles"

force_conv=0
if [[ "${1:-}" == --conversational ]]; then
  force_conv=1
  shift
fi
if [[ $# -eq 0 ]]; then
  echo "usage: $0 [--conversational] FILE..." >&2
  exit 2
fi
command -v vale >/dev/null || { echo "check-voice: vale is not installed (brew install vale)" >&2; exit 2; }
command -v python3 >/dev/null || { echo "check-voice: python3 is required" >&2; exit 2; }
[[ -d "$styles/Voice" ]] || { echo "check-voice: $styles/Voice not found" >&2; exit 2; }
for f in "$@"; do
  [[ -f "$f" ]] || { echo "check-voice: no such file: $f" >&2; exit 2; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

others="Dmfdeploy"
if [[ -d "$styles/Google" ]]; then
  others="Google, Dmfdeploy"
else
  echo "check-voice: Google package not synced; run 'vale sync' for full coverage" >&2
fi

# in_surface <file>: true if .vale.ini lints the file. Vale's own glob matcher
# answers: a copy of .vale.ini whose styled sections use a probe rule that
# fires once on any file, run from the repo root on the repo-relative path.
mkdir -p "$tmp/probe/Probe"
printf '%s\n' 'extends: existence' 'message: "in scope"' 'level: error' \
  'scope: raw' 'nonword: true' 'tokens:' "  - '\\A'" >"$tmp/probe/Probe/Hit.yml"
if [[ -f "$root/.vale.ini" ]]; then
  sed -e "s|^StylesPath = .*|StylesPath = $tmp/probe|" -e '/^Packages =/d' \
    -e '/^Vocab =/d' -e 's/^BasedOnStyles = ..*/BasedOnStyles = Probe/' \
    "$root/.vale.ini" >"$tmp/probe.ini"
fi
in_surface() {
  [[ -f "$tmp/probe.ini" ]] || return 0
  local rel
  rel="$(python3 -I -c 'import os, sys
p, r = os.path.realpath(sys.argv[1]), os.path.realpath(sys.argv[2])
print(os.path.relpath(p, r) if p.startswith(r + os.sep) else "")' "$1" "$root")"
  [[ -n "$rel" ]] || return 1
  [[ -n "$(cd "$root" && vale --no-exit --output=line --config "$tmp/probe.ini" "$rel")" ]]
}

doc=() conv=()
for f in "$@"; do
  if [[ "$force_conv" == 1 ]] || ! in_surface "$f"; then conv+=("$f"); else doc+=("$f"); fi
done

write_ini() { # write_ini <file> <min level> <styles> [extra ini lines]
  printf 'StylesPath = %s\nMinAlertLevel = %s\nVocab = Dmfdeploy\n\n[*]\nBasedOnStyles = %s\n%s' \
    "$styles" "$2" "$3" "${4:-}" >"$1"
}
write_ini "$tmp/voice.ini" suggestion "Voice"
write_ini "$tmp/doc.ini" warning "$others"
write_ini "$tmp/conv.ini" warning "$others" \
  $'Google.We = NO\nGoogle.Will = NO\nGoogle.Quotes = warning\n'

run() { # run <pass> <ini> FILE...
  local pass="$1" ini="$2"
  shift 2
  vale --no-exit --output=JSON --config "$ini" "$@" >"$tmp/$pass.json" \
    || { echo "check-voice: vale failed on the $pass pass" >&2; exit 2; }
}
echo '{}' >"$tmp/doc.json"
echo '{}' >"$tmp/conv.json"
run voice "$tmp/voice.ini" "$@"
(( ${#doc[@]} )) && run doc "$tmp/doc.ini" "${doc[@]}"
(( ${#conv[@]} )) && run conv "$tmp/conv.ini" "${conv[@]}"
(( ${#conv[@]} )) && echo "check-voice: conversational mode for ${conv[*]}" >&2

python3 -I - "$tmp/voice.json" "$tmp/doc.json" "$tmp/conv.json" "$#" <<'PY'
import json, sys
counts = {"error": 0, "warning": 0, "suggestion": 0}
for path in sys.argv[1:4]:
    with open(path) as fh:
        data = json.load(fh)
    for name, alerts in data.items():
        for a in alerts:
            sev = a["Severity"]
            counts[sev] = counts.get(sev, 0) + 1
            print(f'{name}:{a["Line"]}:{a["Span"][0]}: {sev}: {a["Check"]}: {a["Message"]}')
print(f'check-voice: {counts["error"]} error, {counts["warning"]} warning, '
      f'{counts["suggestion"]} suggestion in {sys.argv[4]} file(s)')
sys.exit(1 if counts["error"] else 0)
PY
