#!/usr/bin/env bash
# Strict Voice check on the Markdown files a change touches.
#
# Lints each Markdown file that HEAD adds or modifies relative to BASE, with
# the Voice rules at error level only (Contrast and EmDash). Only files that
# .vale.ini lints are checked, and its BlockIgnores apply: the config is
# derived from .vale.ini, so the scope cannot drift from the warn-mode run.
# Deleted files and pure renames (no content change) are skipped; a renamed
# file with edits is checked at its new path.
#
# This blocks new occurrences in the files a PR touches without asking for a
# cleanup of the whole corpus first. The whole-tree run stays in warn mode.
#
# Usage: bin/check-voice-changed.sh BASE [HEAD]
#   HEAD defaults to HEAD and must be the checked-out tree.
#   Exit 0: no error-level Voice alert.  Exit 1: at least one.
#   Exit 2: bad usage, or git or Vale failed.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 BASE [HEAD]" >&2
  exit 2
fi
base="$1" head="${2:-HEAD}"
command -v vale >/dev/null || { echo "check-voice-changed: vale is not installed" >&2; exit 2; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
git -C "$root" diff --name-status -z -M --diff-filter=AMR "$base" "$head" >"$tmp/diff" \
  || { echo "check-voice-changed: git diff $base $head failed" >&2; exit 2; }

files=()
while IFS= read -r -d '' status; do
  IFS= read -r -d '' path
  case "$status" in
    R100) IFS= read -r -d '' path; continue ;;   # pure rename: skip
    R*) IFS= read -r -d '' path ;;               # rename with edits: new path
  esac
  [[ "$path" == *.md && -f "$root/$path" ]] && files+=("$path")
done <"$tmp/diff"

if [[ ${#files[@]} -eq 0 ]]; then
  echo "check-voice-changed: no changed Markdown files"
  exit 0
fi

sed -e "s|^StylesPath = .*|StylesPath = $root/.vale/styles|" \
  -e 's/^MinAlertLevel = .*/MinAlertLevel = error/' -e '/^Packages =/d' \
  -e 's/^BasedOnStyles = ..*/BasedOnStyles = Voice/' \
  "$root/.vale.ini" >"$tmp/voice-strict.ini"

# Vale matches .vale.ini globs against the path relative to the working
# directory, so run from the root with repo-relative paths.
out="$(cd "$root" && vale --no-exit --output=line --config "$tmp/voice-strict.ini" "${files[@]}")" \
  || { echo "check-voice-changed: vale failed" >&2; exit 2; }

echo "check-voice-changed: ${#files[@]} changed Markdown file(s) checked"
[[ -z "$out" ]] && exit 0
while IFS=: read -r file line col check msg; do
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::error file=$file,line=$line,col=$col::$check: $msg"
  else
    echo "$file:$line:$col: $check: $msg"
  fi
done <<<"$out"
echo "check-voice-changed: $(wc -l <<<"$out" | tr -d ' ') error-level Voice alert(s). See docs/STYLE.md."
exit 1
