#!/usr/bin/env bash
# merge-brake.sh: decide whether a pull request may merge, from its labels.
# The merge-brake workflow runs it on every label change and push, and its
# exit status becomes the "merge-brake" check.
#
# Usage:
#   merge-brake.sh < input.json
#
# The input is one JSON object:
#   { "labels": ["hold", ...] }    # label names on the PR
#
# The brake is on, and the script exits 1, when the PR carries the "hold"
# label. The match is exact, so a label such as "on-hold" doesn't count.
# Otherwise it exits 0. Exit 2 means the input could not be read, which the
# workflow treats as a failure too, so a broken input never passes.
#
# Review state is not checked here. On main, the ruleset already refuses a
# merge while a reviewer has an outstanding request for changes.
set -euo pipefail

input=$(cat)

# Slurp, so empty input or more than one JSON document is rejected too.
if ! printf '%s' "$input" | jq -se 'length == 1 and (.[0]
    | type == "object"
    and (.labels | type == "array")
    and all(.labels[]; type == "string"))' >/dev/null 2>&1; then
  echo "::error title=merge-brake::input must be an object with a labels array of strings"
  exit 2
fi

if printf '%s' "$input" | jq -e '.labels | index("hold")' >/dev/null; then
  echo "::error title=merge-brake::the hold label is on this PR. Remove it to let the PR merge."
  exit 1
fi

echo "merge-brake: no hold label"
exit 0
