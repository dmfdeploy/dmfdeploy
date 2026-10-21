#!/usr/bin/env bash
# Mutation test for the Voice rules.
#
# For each row below, copy the tree to a scratch directory, replace one exact
# string in one rule file, run the fixture check, and require that it FAILS and
# names that rule. Never touches the repo.
#
# Usage: bin/mutate-voice.sh        Exit 0 if every mutation was caught.
set -euo pipefail
root="${VOICE_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# rule file @@ exact text in that file @@ replacement. Each "exact text" starts
# at the list marker or opening quote of one token line, so it cannot match the
# message or description. Each one breaks one regex.
mutations=(
  "Contrast@@  - ',\\s+not@@  - ',\\s+nxt"
  "Contrast@@  - '\\bnot\\s+only@@  - '\\bnxt\\s+only"
  "Contrast@@  - '\\bnot\\s+(?:a|an|the@@  - '\\bnxt\\s+(?:a|an|the"
  "Contrast@@  - '\\b(?:it|this|that)(?:@@  - '\\b(?:it|this|that)x(?:"
  "Contrast@@  - '\\bless\\s+[^.!?,;]{1,40},@@  - '\\bless\\s+[^.!?,;]{1,40};"
  "Contrast@@  - '(?:^|(?<=[.!?]\\s))not@@  - '(?:^|(?<=[.!?]\\s))nxt"
  "SoftContrast@@  - rather than@@  - rather thxn"
  "SoftContrast@@  - instead of@@  - instead xf"
  "Vocabulary@@  - 'robust@@  - 'robxst"
  "Vocabulary@@  - 'facilitat@@  - 'facilitxt"
  "StockPhrases@@  - 'plays? an?@@  - 'plxys? an?"
  "StockPhrases@@  - 'worth (?:noting@@  - 'wxrth (?:noting"
  "StockPhrases@@  - 'i hope this helps@@  - 'i hope this hxlps"
  "Openers@@  - '^(?:Additionally@@  - '^(?:Addxtionally"
  "Openers@@  - '^Overall,@@  - '^Ovxrall,"
  "EmDash@@  - '—@@  - 'xx"
  "EmDash@@  - '\\s--\\s@@  - '\\s-x\\s"
  "BoldLeadBullets@@  - '(?m)^@@  - 'xx(?m)^"
  "ColonHeading@@  - ':\\s@@  - ';\\s"
  "Triads@@  - '\\b[A-Za-z-]+, [A-Za-z-]+,? (?:and|or)@@  - '\\b[A-Za-z-]+, [A-Za-z-]+,? (?:xnd|xr)"
)
fail=0
for row in "${mutations[@]}"; do
  rule="${row%%@@*}"; rest="${row#*@@}"; from="${rest%%@@*}"; to="${rest#*@@}"
  rm -rf "$scratch/t"; cp -R "$root" "$scratch/t"
  VOICE_FROM="$from" VOICE_TO="$to" python3 -I - "$scratch/t/.vale/styles/Voice/$rule.yml" <<'PY'
import os, sys
p = sys.argv[1]
t = open(p, encoding="utf-8").read()
a, b = os.environ["VOICE_FROM"], os.environ["VOICE_TO"]
if t.count(a) < 1:
    sys.exit(f"mutation text not found in {p}: {a}")
open(p, "w", encoding="utf-8").write(t.replace(a, b, 1))
PY
  out="$(VOICE_ROOT="$scratch/t" "$scratch/t/bin/check-voice-fixtures.sh" 2>&1 || true)"
  if grep -q "FAIL: bad.md.*Voice.$rule" <<<"$out"; then
    echo "caught   Voice.$rule  [$from]"
  else
    echo "MISSED   Voice.$rule  [$from]"; fail=1
  fi
done
exit "$fail"
