#!/usr/bin/env bash
# hygiene-check.sh: static checks for the title, issue forms, CODEOWNERS and
# the PR template. The title-check workflow runs it on the real files and on
# the fixtures in .github/title-check-fixtures/. Run it locally from anywhere.
#
# Usage:
#   hygiene-check.sh title            # reads $GITHUB_EVENT_PATH; STRICT=1 fails
#   hygiene-check.sh form FILE        # issue form has required component and workstream
#   hygiene-check.sh owners FILE      # CODEOWNERS paths exist, owners are @login or @org/team
#   hygiene-check.sh pr FILE          # PR template has the checklist items
#   hygiene-check.sh real             # run form, owners and pr on the real files
#   hygiene-check.sh fixtures         # assert every bad fixture fails, every good one passes
#
# FILE is relative to the repository root. Exit 0 means ok, 1 means findings.
#
# Why ruby and jq: both ship on ubuntu-24.04 runners and on macOS. Python has
# no YAML parser in its standard library, and the two common "yq" tools differ
# in syntax, so neither is used.
set -euo pipefail
cd "$(dirname "$0")/../.."

kind="${1:-}"
file="${2:-}"
bad=()

case "$kind" in
  title)
    title=$(jq -r '(.pull_request // .issue).title // ""' "${GITHUB_EVENT_PATH:?GITHUB_EVENT_PATH is not set}")
    if printf '%s' "$title" | grep -Eqi '^[[:space:]]*(\[[^]]*\][[:space:]]*)*\[auto\]'; then
      msg="Title starts with an [auto] prefix. Use a plain title."
      if [ "${STRICT:-0}" = "1" ]; then
        echo "::error title=title-check::$msg"
        exit 1
      fi
      echo "::warning title=title-check::$msg"
    fi
    echo "title ok or warned: $title"
    exit 0
    ;;
  form)
    json=$(ruby -ryaml -rjson -e 'puts JSON.generate(YAML.safe_load(File.read(ARGV[0])))' "$file" 2>/dev/null) ||
      { echo "form: $file does not parse as YAML"; exit 1; }
    for need in component workstream; do
      jq -e --arg id "$need" '[.body[]? | select(.id == $id and .type == "dropdown" and .validations.required == true)] | length == 1' \
        <<<"$json" >/dev/null || bad+=("missing required dropdown: $need")
    done
    ;;
  owners)
    n=0
    while IFS= read -r line || [ -n "$line" ]; do
      n=$((n + 1))
      line="${line%%#*}"
      read -r -a parts <<<"$line"
      [ "${#parts[@]}" -gt 0 ] || continue
      pat="${parts[0]}"
      if ! compgen -G "${pat#/}" >/dev/null && [ ! -e "${pat#/}" ]; then
        bad+=("line $n: path not found: $pat")
      fi
      if [ "${#parts[@]}" -lt 2 ]; then
        bad+=("line $n: no owner")
      fi
      for o in "${parts[@]:1}"; do
        [[ "$o" =~ ^@[A-Za-z0-9_-]+(/[A-Za-z0-9_-]+)?$ ]] || bad+=("line $n: owner not in @login or @org/team form: $o")
      done
    done <"$file"
    ;;
  pr)
    for word in 'component:*' 'workstream:*' 'dmfdeploy/dmfdeploy#N' 'signed off' 'check-docs'; do
      grep -qF -- "$word" "$file" || bad+=("checklist item missing: $word")
    done
    ;;
  real)
    rc=0
    for f in .github/ISSUE_TEMPLATE/*.yml; do
      [ "$(basename "$f")" = config.yml ] && continue
      "$0" form "$f" || rc=1
    done
    "$0" owners .github/CODEOWNERS || rc=1
    "$0" pr .github/PULL_REQUEST_TEMPLATE.md || rc=1
    exit "$rc"
    ;;
  fixtures)
    d=.github/title-check-fixtures
    rc=0
    # expect WANT LABEL CMD...: run CMD quietly and compare its exit code.
    expect() {
      local want="$1" label="$2" got=0
      shift 2
      "$@" >/dev/null 2>&1 || got=$?
      if { [ "$want" = 0 ] && [ "$got" -ne 0 ]; } || { [ "$want" = fail ] && [ "$got" -eq 0 ]; }; then
        echo "FIXTURE WRONG: $label exited $got, wanted $want" >&2
        rc=1
      else
        echo "fixture ok: $label exit $got"
      fi
    }
    for f in "$d"/bad-form*.yml; do expect fail "$f" "$0" form "$f"; done
    for f in "$d"/good-form*.yml; do expect 0 "$f" "$0" form "$f"; done
    for f in "$d"/bad-codeowners*; do expect fail "$f" "$0" owners "$f"; done
    for f in "$d"/good-codeowners*; do expect 0 "$f" "$0" owners "$f"; done
    for f in "$d"/bad-pr-template*.md; do expect fail "$f" "$0" pr "$f"; done
    for f in "$d"/good-pr-template*.md; do expect 0 "$f" "$0" pr "$f"; done
    for f in "$d"/bad-pr.json "$d"/bad-issue.json; do
      expect fail "$f STRICT=1" env GITHUB_EVENT_PATH="$f" STRICT=1 "$0" title
      expect 0 "$f warn mode" env GITHUB_EVENT_PATH="$f" STRICT=0 "$0" title
    done
    for f in "$d"/good-pr.json "$d"/good-issue.json; do
      expect 0 "$f STRICT=1" env GITHUB_EVENT_PATH="$f" STRICT=1 "$0" title
    done
    exit "$rc"
    ;;
  *)
    echo "usage: hygiene-check.sh title | form FILE | owners FILE | pr FILE | real | fixtures" >&2
    exit 2
    ;;
esac

if [ "${#bad[@]}" -gt 0 ]; then
  for b in "${bad[@]}"; do echo "$kind: $b" >&2; done
  exit 1
fi
echo "$kind ok: $file"
