#!/usr/bin/env bash
# merge-brake.sh: decide whether a pull request may merge. The merge-brake
# workflow runs it on every label and review change, and its exit status
# becomes the "merge-brake" check.
#
# Usage:
#   merge-brake.sh < input.json
#
# The input is one JSON object:
#   {
#     "labels":  ["hold", ...],          # label names on the PR
#     "reviews": [ <review>, ... ]       # GET /repos/{o}/{r}/pulls/{n}/reviews
#   }
# Each review needs .user.login, .state, .author_association and
# .submitted_at, which is what the REST API returns.
#
# The brake is on, and the script exits 1, when either:
#   - the PR carries the "hold" label, or
#   - a reviewer's latest decisive review is CHANGES_REQUESTED.
# Otherwise it exits 0. Exit 2 means the input could not be read.
#
# A decisive review is APPROVED, CHANGES_REQUESTED or DISMISSED. A COMMENTED
# review does not clear an earlier request for changes, which matches how
# GitHub itself reads review state. A dismissed request shows up as DISMISSED,
# so dismissing it releases the brake.
#
# Only reviewers whose author_association is OWNER, MEMBER or COLLABORATOR
# count. That keeps a drive-by review on a public repository from blocking a
# merge. It approximates write access without an extra API call per reviewer.
set -euo pipefail

input=$(cat)

if ! printf '%s' "$input" | jq -e 'type == "object"
    and (.labels | type == "array")
    and (.reviews | type == "array")' >/dev/null 2>&1; then
  echo "::error title=merge-brake::input must be an object with labels and reviews arrays"
  exit 2
fi

brake=0

if printf '%s' "$input" | jq -e '.labels | index("hold")' >/dev/null; then
  echo "::error title=merge-brake::the hold label is on this PR. Remove it to let the PR merge."
  brake=1
fi

blocking=$(printf '%s' "$input" | jq -r '
  [ .reviews[]
    | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED")
    | select(.author_association == "OWNER" or .author_association == "MEMBER" or .author_association == "COLLABORATOR") ]
  | sort_by(.submitted_at)
  | group_by(.user.login)
  | map(last)
  | map(select(.state == "CHANGES_REQUESTED") | .user.login)
  | .[]')

if [ -n "$blocking" ]; then
  while IFS= read -r login; do
    echo "::error title=merge-brake::${login} requested changes. A new approval from ${login}, or a dismissal of that review, releases the brake."
  done <<<"$blocking"
  brake=1
fi

if [ "$brake" -eq 0 ]; then
  echo "merge-brake: no hold label and no outstanding request for changes"
fi
exit "$brake"
