---
status: draft
date: 2026-06-14
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/46
---
# Canonical Cross-Agent Skills — Implementation Spec (2026-06-14)

**Status:** Draft design spec for the implementation half of [#46](https://github.com/dmfdeploy/dmfdeploy/issues/46).
**Decision basis:** [ADR-0042](../decisions/0042-canonical-cross-agent-skills.md) (Accepted) — one canonical
`.agents/skills/` source, generated per-agent views, CI drift gate, capture→review→promote.
**Relates to:** [#26](https://github.com/dmfdeploy/dmfdeploy/issues/26) (stray component-repo `.qwen/` hygiene).

> The ADR ratifies *what* and *why*; this plan is *how*. The PR that implements it flips this
> doc's `status:` to `executed` and closes #46 in the same change.

## Survey (current state, 2026-06-14)

35 skills, single-file `SKILL.md`, no bundled files, **zero name collisions**, across:

| Location | Tracked | Count | Disposition |
|---|---|---|---|
| `dmfdeploy/.qwen/skills/` | 23 of 27 | 27 | → move to canonical; gitignore the dir |
| `dmfdeploy/.claude/skills/` | 4 | 4 | → move to canonical; gitignore the dir |
| `dmfdeploy/skills/` (legacy) | — | 1 | `issues-cruncher` → canonical; remove legacy dir |
| `../.qwen/skills/` (parent workspace, not a repo) | no | 1 | `dmf-deploy-commit-workflow` → canonical; emit untracked parent view |
| `dmf-init/.qwen/skills/` | 2 | 2 | stay component-local in `dmf-init/.agents/skills/` |

Mirror target: `bin/check-working-model-sync.sh` + `working-model-digest.sh` + CI `working-model`
job (one canonical template → many generated views → drift check).

## Target layout

```
dmfdeploy/
  .agents/skills/                 # canonical, tracked, agent-neutral (the ONLY tracked copy)
    <name>/SKILL.md
    _inbox/                       # gitignored capture scratch (auto-minted skills land here)
  .claude/skills/                 # GENERATED, gitignored
  .qwen/skills/                   # GENERATED, gitignored
  bin/sync-skills.sh              # materialize views / --check drift / promote from _inbox
```
Codex CLI, Gemini CLI, Cursor read `.agents/skills/` natively — **no view generated for them.**

## `bin/sync-skills.sh` (mirror `check-working-model-sync.sh` ergonomics)

Bash, dependency-free (`find`/`git`/`python3` for frontmatter as check-docs.sh does), shellcheck-clean.

Modes:
- `--apply` (default): regenerate `.claude/skills/` + `.qwen/skills/` from `.agents/skills/`, honoring per-skill `agents:` and `visibility:` frontmatter. Symlink per-skill subdir (copy fallback via `--copy` when `core.symlinks` is off). Prune views whose canonical source is gone.
- `--check`: exit 1 on any drift between canonical and views (for pre-commit + CI). No mutation.
- `--promote <name>`: move `_inbox/<name>/` into canonical (the reviewed promotion step; the PR carries it).
- `--repo <path>`: operate on a sibling repo's own `.agents/skills/` (so `dmf-init` uses the same script).
- `--umbrella-only`: skip siblings (pre-commit/CI never blocked by another repo's drift).

Frontmatter schema (additive to existing `name`/`description`/`source`/`extracted_at`):
- `agents:` *(optional list)* — absent ⇒ sync to **all** agents; `[claude]` ⇒ scope to listed agents only.
- `visibility:` *(optional)* — `operator-local` | `experimental` ⇒ kept in canonical but **gitignored** (never tracked, never synced to committed views). Preserves the `identity-scrub-sweep` carve-out.

## Wiring

1. **`.gitignore`** — add `.claude/skills/` and `.qwen/skills/` (generated) and `.agents/skills/_inbox/`; keep an operator-local carve-out for `visibility: operator-local` skills (e.g. `identity-scrub-sweep`).
2. **`.githooks/pre-commit`** — add `bin/sync-skills.sh --check --umbrella-only` alongside the existing doc checks.
3. **CI** — add a `skills-sync` job mirroring the `working-model` job: run `bin/sync-skills.sh --check`.
4. **Prose** — repoint `CLAUDE.md` + `QWEN.md` skill references from `.claude/skills/<name>/SKILL.md` to `.agents/skills/<name>/SKILL.md`; QWEN.md's 3-row table becomes a full/generated listing.

## Migration steps

1. `git mv` the 27 + 4 + legacy `issues-cruncher` + parent `dmf-deploy-commit-workflow` into `dmfdeploy/.agents/skills/`.
2. Add `bin/sync-skills.sh`; run `--apply`; verify the generated views match the pre-move set.
3. Apply the gitignore + hook + CI wiring; repoint prose.
4. `dmf-init`: rename `.qwen/skills/` → `.agents/skills/`, gitignore its generated views, run `--repo dmf-init`.
5. Emit the untracked parent-workspace view (`../.agents/skills`, `../.qwen/skills`) for root-launched agents.

## Verification

1. `bin/sync-skills.sh --apply` then `git status` → only `.agents/skills/` tracked; `.claude/skills/` + `.qwen/skills/` rebuilt and gitignored; canonical count = 35 minus dmf-init's 2.
2. **Idempotent** — second `--apply` is a no-op.
3. **Capture→promote** — drop a skill into `_inbox/foo/`, `--promote foo`, reconcile → appears in canonical + all views; absent before promotion.
4. **Tiering** — `agents: [claude]` skill present in `.claude/skills/`, absent from `.qwen/skills/`; `visibility: operator-local` stays untracked.
5. **Gate** — hand-introduced drift makes `--check` (pre-commit + CI `skills-sync`) red.
6. `shellcheck bin/sync-skills.sh` clean; `bin/check-docs.sh` clean.

## Out of scope (this slice)

- Codex/Gemini `AGENTS.md` include generation (they read `.agents/skills/` natively; revisit only if a non-native agent is added).
- Promoting `dmf-init`'s 2 component-local skills into the shared set (stays component-local unless explicitly promoted later).
- Hermes (runtime-memory skill model, not directory-based) — can read `.agents/skills/` as context; no view.
