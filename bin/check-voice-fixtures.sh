#!/usr/bin/env bash
# Prove the Voice rules against their fixtures.
#
#   bad.md   Each trigger has a line  <!-- expect: Voice.Rule -->  above it.
#            Every expected rule must fire inside the block (the lines up to
#            the next blank line), and every Voice rule must be expected at
#            least once.
#   good.md  Must produce no Voice alert at suggestion level, and no alert
#            from any style at warning level.
#
# Usage: bin/check-voice-fixtures.sh      Exit 0 on success, 1 on any failure.
#
# Mutation test (prove one rule): copy the tree, break one regex in the copy,
# and run with VOICE_ROOT pointing at the copy. See the end of this file.
set -euo pipefail

root="${VOICE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
styles="$root/.vale/styles"
dir="$root/.vale/fixtures/voice"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

others="Dmfdeploy"
[[ -d "$styles/Google" ]] && others="Google, Dmfdeploy"
ini() { printf 'StylesPath = %s\nMinAlertLevel = %s\nVocab = Dmfdeploy\n\n[*.md]\nBasedOnStyles = %s\n' "$styles" "$2" "$3" >"$1"; }
ini "$tmp/voice.ini" suggestion "Voice"
ini "$tmp/all.ini" warning "Voice, $others"

vale --no-exit --output=JSON --config "$tmp/voice.ini" "$dir/bad.md" >"$tmp/bad.json"
vale --no-exit --output=JSON --config "$tmp/voice.ini" "$dir/good.md" >"$tmp/good-voice.json"
vale --no-exit --output=JSON --config "$tmp/all.ini" "$dir/good.md" >"$tmp/good-all.json"

python3 -I - "$dir/bad.md" "$tmp/bad.json" "$tmp/good-voice.json" "$tmp/good-all.json" "$styles/Voice" <<'PY'
import json, os, re, sys
bad_md, bad_js, good_v, good_a, rules_dir = sys.argv[1:6]
rules = {"Voice." + f[:-4] for f in os.listdir(rules_dir) if f.endswith(".yml")}
lines = open(bad_md, encoding="utf-8").read().split("\n")
alerts = [a for al in json.load(open(bad_js)).values() for a in al]
fired = {}
for a in alerts:
    fired.setdefault(a["Check"], []).append(a["Line"])
fails, expected_rules = [], set()
for i, text in enumerate(lines, start=1):
    m = re.match(r"\s*<!--\s*expect:\s*(\S+)\s*-->", text)
    if not m:
        continue
    rule = m.group(1)
    expected_rules.add(rule)
    end = i + 1
    while end <= len(lines) and lines[end - 1].strip():
        end += 1
    if not any(i < n < end for n in fired.get(rule, [])):
        fails.append(f"bad.md:{i}: expected {rule} in lines {i+1}-{end-1}, not fired")
for rule in sorted(rules - expected_rules):
    fails.append(f"bad.md: no expect comment for {rule}")
for path, label in ((good_v, "Voice"), (good_a, "any style")):
    for name, al in json.load(open(path)).items():
        for a in al:
            fails.append(f'good.md:{a["Line"]}: unexpected {label} alert {a["Check"]}: {a["Message"]}')
for f in fails:
    print("FAIL:", f)
print(f"check-voice-fixtures: {len(rules)} rules, {len(expected_rules)} expected in bad.md, {len(fails)} failure(s)")
sys.exit(1 if fails else 0)
PY

# Mutation test: bin/mutate-voice.sh copies the tree, breaks one regex on one
# token line of one rule (the match starts at the list marker, so it cannot
# hit a message or description), and requires this script to fail naming that
# rule. To do one by hand, copy the tree to a scratch directory, edit one token
# line in the copy, and run it with VOICE_ROOT=<copy>. Never edit the repo.
