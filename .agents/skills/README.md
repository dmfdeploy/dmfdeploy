# DMF canonical skills store — conventions + decay rubric

This directory is the **one agent-neutral skill store** (ADR-0042). The
`.claude/skills/` and `.qwen/skills/` trees are generated, gitignored views
rebuilt by `bin/sync-skills.sh --apply`; never hand-edit a view. New
auto-minted skills enter through `_inbox/` → `--promote` → PR.

Skills are **public-trajectory content**: no tokens, no private IPs, no
operator identity, no operator-home paths (enforced by `bin/sync-skills.sh
--check` in pre-commit + CI). Environment slugs rotate — reference
`STATUS.local.md`, never a concrete env id.

## Metadata rubric (R3, issue #225)

Every `SKILL.md` carries these frontmatter keys, validated by
`bin/sync-skills.sh --check`:

| Key | Values | Meaning |
|---|---|---|
| `type` | `durable-pattern` \| `incident-residue` \| `operational-procedure` | What kind of knowledge this is (drives review cadence) |
| `scope` | free text (e.g. `agent-workflow`, `github`, `live-env`, `dmf-cms`) | Where it applies |
| `owner` | `operator` | Accountable role (never a personal identity — public trajectory) |
| `review_by` | `YYYY-MM-DD` | Next mandatory re-validation date |
| `source_ref` | URL (optional) | Issue/PR/transcript the skill came from; required for NEW skills, legacy auto-extractions may lack it |
| `merged_from` | list (optional) | Names of retired skills folded into this one |

`source:`/`extracted_at:` are creation provenance (auto-skill machinery) and
stay as-is. `last-used` tracking was considered and rejected: self-reporting
does not happen in practice, so `review_by` is the enforceable decay field.

**Review cadence by type:**

- `durable-pattern` — 6 months. Encodes a reusable technique or protocol.
- `incident-residue` — 3 months. Born from one incident; the shortest leash,
  because it is either promoted to durable (the hazard recurred), folded into
  a durable skill, or retired.
- `operational-procedure` — 6 months, and IMMEDIATELY when the system it
  drives changes shape (release path, cluster access, unseal quorum).

An overdue `review_by` is a **warning**, not a commit blocker (a date
rollover must not brick unrelated commits); the reviewer either re-validates
(bump the date, fix drift) or retires.

## Retirement (rubric-driven, never count-driven)

There is **no target skill count**. A one-off-looking skill that encodes an
expensive recurring hazard stays. Retire when at least one of:

1. The knowledge landed in tooling/CI (the skill's job is now automated).
2. The system it describes was retired or restructured beyond recognition.
3. It was merged into another skill (record `merged_from` there).
4. Two consecutive reviews found no plausible future use.

Procedure: delete the skill directory in a reviewed PR; record the
retirement in the log below (name, date, reason, where the knowledge went).
If the skill encoded a live hazard, make sure the hazard note survives
somewhere reachable (merged skill, memory, or doc) before deleting.

## Retirement log

| Skill | Date | Reason | Knowledge went to |
|---|---|---|---|
| `cold-agent-wp-execution` | 2026-07-14 | merged (R3) | `cold-agent-execution` |
| `cold-agent-multi-file-implementation` | 2026-07-14 | merged (R3) | `cold-agent-execution` |
| `orchestrated-lifter-workflow` | 2026-07-14 | merged (R3) | `cold-agent-execution` |
