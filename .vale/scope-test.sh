#!/usr/bin/env bash
# Check which README files .vale.ini lints.
#
# Builds a scratch tree with a README.md at the root, in sub/, in
# sub/deeper/ and in docs/archive/, each with one project-rule violation.
# It lints the tree with a copy of .vale.ini that keeps the section layout
# but uses only the project style, so no package download is needed.
# Expected: root, sub and sub/deeper are flagged; docs/archive is not.
#
# Usage: .vale/scope-test.sh [path/to/.vale.ini]
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
ini="${1:-$repo/.vale.ini}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/sub/deeper" "$tmp/docs/archive" "$tmp/.vale"
cp -R "$repo/.vale/styles" "$tmp/.vale/styles"
for d in . sub sub/deeper docs/archive; do
  printf '# Scope check\n\nThis page is simply a test.\n' >"$tmp/$d/README.md"
done
sed -e 's/Google, Dmfdeploy/Dmfdeploy/' -e '/^Packages = Google/d' \
  "$ini" >"$tmp/.vale.ini"

fail=0
check() { # check <dir> <yes|no>
  local out
  out="$(cd "$tmp" && vale --no-exit --output=line --config .vale.ini "$1/README.md")"
  if [[ "$2" == yes && -z "$out" ]]; then
    echo "FAIL: $1/README.md is not linted"; fail=1
  elif [[ "$2" == no && -n "$out" ]]; then
    echo "FAIL: $1/README.md is linted but must be exempt: $out"; fail=1
  else
    echo "ok: $1/README.md (linted: $2)"
  fi
}
check . yes
check sub yes
check sub/deeper yes
check docs/archive no
exit "$fail"
