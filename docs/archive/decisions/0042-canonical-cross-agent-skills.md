# ADR-0042 archive: Canonical cross-agent skills store with generated per-agent views

This file holds material moved out of [ADR-0042](../../decisions/0042-canonical-cross-agent-skills.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **`docs/skills/` or top-level `skills/`** (the two locations #46 originally listed) — agent-neutral but **not any agent's native path**, so *every* agent (including Codex/Gemini) needs generated glue. `.agents/skills/` gives the three native-readers for free.
- **Committed per-skill symlinks, no script** — no review gate on auto-minted skills, and whole-dir symlinking `.claude/skills/` collides with Claude's `.system/` internals. Loses the capture→promote gate that is the point of #46.
- **Auto-absorb without an `_inbox`** — moving agent-authored skills straight into canonical bypasses PR review, the exact failure #46 exists to fix.
