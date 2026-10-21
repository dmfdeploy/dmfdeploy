# ADR-0005 archive: dmf-cms VERSION file is the single source of truth

This file holds material moved out of [ADR-0005](../../decisions/0005-version-as-single-source-of-truth.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Keep version in `pyproject.toml`, derive others.** Same pattern, different
  primary file. `VERSION` was chosen because it's a one-line plain-text file
  that's trivial to read from any language/tool (Python, JSON, YAML, shell).
- **`latest` tag for "current".** Pods cache by tag and won't repull
  `latest` reliably; a known anti-pattern.
