#!/usr/bin/env bash
# Render a .bpmn file to .svg with the shared docs/processes/diagrams/_styles.css
# stylesheet injected. Wraps `npx bpmn-to-image`.
#
# Usage:
#   bin/render-bpmn.sh <path/to/file.bpmn> [path/to/output.svg]
#
# Defaults:
#   output    → same dir + same basename + .svg
#   styles    → docs/processes/diagrams/_styles.css (override with $BPMN_STYLES)

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <input.bpmn> [output.svg]" >&2
  exit 64
fi

input="$1"
[[ -f "$input" ]] || { echo "error: $input does not exist" >&2; exit 66; }

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
styles="${BPMN_STYLES:-$repo_root/docs/processes/diagrams/_styles.css}"
[[ -f "$styles" ]] || { echo "error: stylesheet $styles not found" >&2; exit 66; }

if [[ $# -eq 2 ]]; then
  output="$2"
else
  output="${input%.bpmn}.svg"
fi

# bpmn-to-image emits a footer with title + bpmn.io logo; --no-footer drops it.
echo "→ rendering $input → $output"
npx --yes bpmn-to-image --no-footer "$input:$output"

# Inject the stylesheet immediately after the opening <svg …> tag using a
# Python helper for safe handling of multi-line CSS and special characters.
echo "→ injecting $styles"
python3 - "$output" "$styles" <<'PY'
import sys, re, pathlib
svg_path = pathlib.Path(sys.argv[1])
css_path = pathlib.Path(sys.argv[2])
svg = svg_path.read_text(encoding="utf-8")
css = css_path.read_text(encoding="utf-8")
style_block = f"<style><![CDATA[\n{css}\n]]></style>"
new_svg, n = re.subn(r"(<svg\b[^>]*>)", r"\1" + style_block, svg, count=1)
if n != 1:
    sys.exit("error: could not locate <svg> opening tag for injection")
svg_path.write_text(new_svg, encoding="utf-8")
PY

echo "✓ done: $output"
