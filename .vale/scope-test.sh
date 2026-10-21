#!/usr/bin/env bash
# Check which files .vale.ini lints.
#
# Builds a scratch tree with a README.md at the root, in sub/, in
# sub/deeper/ and in docs/archive/, plus a page in each glob section that
# the Voice package added (docs/THESIS.md, docs/templates/, .github/ at two
# depths). Each file has one project-rule violation. It lints the tree with
# a copy of .vale.ini that keeps the section layout but uses only the
# project styles, so no package download is needed.
# Expected: every file is flagged except docs/archive/README.md.
#
# Usage: .vale/scope-test.sh [path/to/.vale.ini]
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
ini="${1:-$repo/.vale.ini}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pages=(README.md sub/README.md sub/deeper/README.md docs/archive/README.md
  docs/THESIS.md docs/templates/page.md .github/PAGE.md .github/sub/page.md)
mkdir -p "$tmp/.vale"
cp -R "$repo/.vale/styles" "$tmp/.vale/styles"
for p in "${pages[@]}"; do
  mkdir -p "$tmp/$(dirname "$p")"
  printf '# Scope check\n\nThis page is simply a test.\n' >"$tmp/$p"
done
sed -e 's/Google, Dmfdeploy/Dmfdeploy/' -e '/^Packages = Google/d' \
  "$ini" >"$tmp/.vale.ini"

fail=0
check() { # check <file> <yes|no>
  local out
  out="$(cd "$tmp" && vale --no-exit --output=line --config .vale.ini "$1")"
  if [[ "$2" == yes && -z "$out" ]]; then
    echo "FAIL: $1 is not linted"; fail=1
  elif [[ "$2" == no && -n "$out" ]]; then
    echo "FAIL: $1 is linted but must be exempt: $out"; fail=1
  else
    echo "ok: $1 (linted: $2)"
  fi
}
for p in "${pages[@]}"; do
  if [[ "$p" == docs/archive/* ]]; then check "$p" no; else check "$p" yes; fi
done
exit "$fail"
