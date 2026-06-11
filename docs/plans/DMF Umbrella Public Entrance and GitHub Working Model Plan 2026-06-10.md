---
status: active
date: 2026-06-10
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/3
---

# DMF Umbrella Public Entrance & GitHub Working Model Plan 2026-06-10

**Status:** 🚧 ACTIVE — approved 2026-06-10; broken into work packages (WP1–WP17, §"Work packages") for agent pickup. No WP has started unless marked.

> This plan doc carries the new machine-readable frontmatter (see WP2) as its first
> production use. Reviewed adversarially by qwen-left and codex on 2026-06-10; all
> 17 findings folded in (see §"Review provenance").

## Context

All 8 component repos are public (clean orphan imports, 2026-06-09/10). The umbrella is the last unpublished repo and is the **entrance** to the project for humans and agents. Today it fails that job: README still claims "Experiment phase" (closed 2026-06-06 by `../decisions/architectural-commitments-v1.md`), 96/113 plan docs carry no status marker, STATUS.md is ~2,400 lines, TODOS.md is a ~300-line hand-maintained backlog, and ~38 operator-note-store + ~131 LAN-hostname references block publication.

The canonical reviews directly endorse this work: the 2026-06-06 dual-voice evaluation (`../reviews/dmf-platform-technical-evaluation-2026-06-06.md`) scored **external legibility 1/10**, and the committed work-selection rule is *"choose work that makes the proven core runnable and legible to an outsider."* This plan is Phase 3 ("the front door") of `DMF v0.1 Commitment & 30-Day Focus-Cut Plan 2026-06-06.md` + the deferred Workstream B2 (umbrella scrub+prune), extended with a GitHub-native working model.

### Decisions locked with the operator (2026-06-10 session)

1. **Publish model: full tree, scrubbed** — clean orphan import; provenance is a feature. No moving/renaming existing docs (display-name cross-links must not break).
2. **Three-layer reading architecture** — front door (new) / synthesis (new) / record (existing, mechanical pass only).
3. **Synthesis scope** — journey narrative + ADR reading guide + open-questions page. NMOS credibility writeup = separate later plan.
4. **Repo = record, GitHub = live.** ADRs + plans stay in-repo. TODOS.md retires into GitHub Issues (triage + migrate live items). Milestones + org Project #1 (made public at publish) carry scheduling. Discussions on the umbrella repo: Q&A + RFC-before-ADR pipeline + ADR announcement mirror (per-ADR threads going forward; one pinned index thread for the existing 44).
5. **Gates: frontmatter + check gate + staleness warnings** — thin, per the FREEZE-list ban on meta-harness machinery. GitHub liveness replaces most staleness mechanics (open/closed is machine state by construction).
6. Publish push is an **operator-gated final step**; not rushed.

### The split-brain precedence rule (canonical statement)

**GitHub Issues are canonical for scheduling/liveness ("is anyone working on this"); in-repo frontmatter is canonical for design/decision state.** On disagreement the issue wins for liveness and the plan's frontmatter must be flipped — the PR completing a plan's work flips frontmatter in the same change that closes the issue. The `check-docs.sh` best-effort "active plan whose tracking_issue is closed" warning is the offline drift detector. No sync automation beyond that — deliberately thin.

### Frontmatter schema (machine truth; prose `**Status:**` banners stay for humans)

```yaml
---
status: active | draft | executed | superseded | historical
date: 2026-05-19            # plan date (from filename/header)
executed: 2026-06-04        # optional, when status: executed
superseded_by: "DMF <Title> Plan 2026-xx-xx.md"   # optional; exact filename, quoted (spaces)
tracking_issue: https://github.com/dmfdeploy/<umbrella-repo>/issues/NN  # optional, going forward
---
```

YAML must be the literal first bytes of the file. Pass 1 covers `docs/plans/` only; `docs/reviews/` are point-in-time and exempt (the journey narrative contextualizes them).

---

## Work packages

Conventions for every WP below:
- **Mechanical** WPs go to qwen-right or fanned-out subagents; results are **always grep-verified by the orchestrator — never trust a DONE report**.
- **Judgment** WPs are drafted by Claude and reviewed by the operator.
- **Operator-gate** WPs need an explicit operator decision/action.
- A WP is done only when its Verification block passes.
- Do not enable any new commit-blocking gate before its prerequisite sweep is verified (see WP6 ordering).

### WP1 — Plan-status triage allowlist (judgment) — no dependencies

Derive an explicit **active/draft allowlist** from TODOS.md + STATUS.md operator notes + the v0.1 plan. Output: a triage table (appended to this plan doc or as `docs/plans/wp1-triage-table-2026-06.md`) mapping **every** file in `docs/plans/` to `{status, date, executed?, superseded_by?}`. Everything not on the allowlist defaults to `executed` or `historical`. The 17 plans with existing prose status translate it verbatim. **Sweep agents must never infer status from old prose** — the table is the single input to WP2.

*Verification:* table rows == `git ls-files 'docs/plans/*.md' | wc -l` (minus INDEX/README/this-plan); operator skims the active/draft rows.

### WP2 — Frontmatter sweep over docs/plans/ (mechanical; blocked by WP1)

Apply WP1's table: insert YAML frontmatter (schema above) as the first bytes of each `docs/plans/*.md`. Superseded docs additionally get a one-line banner under the title pointing at the successor (reciprocal where the successor exists). Edge cases: files starting with HTML comments/banners — frontmatter goes *above* them; filenames have spaces/em-dashes (26 git-quoted) — use `git ls-files -z`. Single review-file action: pointer banner on `docs/reviews/dmf-platform-strategic-review-2026-04-30.md` → the 2026-06-06 evaluation.

*Verification (orchestrator):* `git ls-files 'docs/plans/*.md' | while ...` → every file starts with `---`; status values ∈ allowed set; spot-check ≥10 against WP1 table; `git diff --stat` touches only intended files.

### WP3 — Directory READMEs + mothball hardening (mechanical) — no dependencies

- `docs/handoffs/README.md` — "append-only lab notebook; newest wins; never required reading to contribute." Handoffs stay frontmatter-exempt.
- `docs/sessions/README.md` — same framing.
- `docs/agentic/README.md` + `bin/agentic/README.md` — "mothballed 2026-06-04; preserved for provenance; superseded by the GitHub issues workflow."
- **Mutating `bin/agentic/` scripts fail closed:** issue-open/promote/backlog-editing scripts get an early-exit guard (`echo "mothballed 2026-06-04 — set DMF_AGENTIC_OVERRIDE=1 to run" >&2; exit 1` immediately after the shebang/set lines, unless `DMF_AGENTIC_OVERRIDE=1`) and are marked historical in the generated `docs/SCRIPTS.md` catalog. Read-only scripts (preflight/agent-status read) may stay unguarded.
- `wizard-spike/README.md` — verify a "architectural spike, not production code" banner is the first thing a reader sees; strengthen if buried.

*Verification:* each README exists with the framing line; running a guarded script without the override exits 1 with the message; `shellcheck` (via `uvx --from shellcheck-py shellcheck`) clean on touched scripts.

### WP4 — generate-plans-index.sh + check-docs.sh (code; blocked by WP1 schema freeze, runs against WP2 output)

- `bin/generate-plans-index.sh` (model on `bin/generate-scripts-catalog.sh`): emits `docs/plans/INDEX.md` from frontmatter, grouped Active / Draft / Executed / Superseded / Historical, newest-first, with dates and superseded_by links. `--check` mode for drift. Simple sorted list — no dashboards.
- `bin/check-docs.sh`: enumeration via `git ls-files -z` throughout. Scope: `docs/plans/` only in pass 1. Hard fails: parseable frontmatter with allowed `status` on every plan (except INDEX/README); `superseded_by` target exists; `generate-plans-index.sh --check` clean; `docs/decisions/INDEX.md` ↔ `docs/decisions/00*.md` existence consistency (both directions, existence only). Warnings (non-blocking): unresolved relative md links; `status: active` plan with no `tracking_issue`; (best-effort, only when `gh` available) active plan whose tracking_issue is closed.

*Verification:* both scripts shellcheck-clean; `check-docs.sh` exits 0 on the post-WP2 tree; deliberately corrupting one frontmatter field makes it exit 1; INDEX regen is idempotent (second run = no diff).

### WP5 — STATUS.md staleness + slimming (code; blocked by WP4 for the staleness source, by WP11 for landing order)

Extend `bin/generate-status.sh`: (a) a short auto section listing `status: active` plans (+ "stale?" flag from the WP4 best-effort check); (b) cap the recent-activity section (keep 7-day window but max N lines per repo) — slim, but never below operator utility; STATUS.md remains the operator/agent dashboard, the front door just stops sending newcomers there. **Lands after the TODOS→Issues swap (WP11) and before WP15 is finalized.**

*Verification:* regenerated STATUS.md < ~600 lines with current repo set; HUMAN section untouched by the generator; `--check` mode still works.

### WP6 — Gate wiring: pre-commit + CI (code; blocked by WP2-verified + WP4)

`.githooks/pre-commit` additionally regenerates the plans INDEX and runs `check-docs.sh` (same pattern as STATUS regen; `STATUS_HOOK_SKIP=1` escape stays). CI `ci.yml` gets a `check-docs` job — hardened conventions: 40-hex pinned actions, read-only permissions, no `gh` dependency (offline checks only). **Hard checkpoint: wire nothing until WP2 is grep-verified by the orchestrator** — enabling the gate against an incomplete sweep blocks every in-flight agent commit.

*Verification:* scratch commit triggers regen + gate and succeeds; a commit with broken frontmatter is rejected; CI job green on a test branch.

### WP7 — Umbrella repo-name freeze (operator-gate) — no dependencies, blocks WP8

Existing artifacts disagree: `.github/ISSUE_TEMPLATE/config.yml`, STATUS notes and first-public-release docs say `dmf-platform`; this plan drafted `dmfdeploy/dmfdeploy`. **Operator decides once.** Then sweep existing references to match **before** any `tracking_issue` URLs, advisory links, or Project items are minted.

*Verification:* `grep -ri 'dmf-platform\|dmfdeploy/dmfdeploy' --include='*.yml' --include='*.md' .` shows only the chosen name (or deliberate historical mentions).

### WP8 — GitHub umbrella repo + scaffolding (mechanical via gh; blocked by WP7)

Create the umbrella repo **private**; enable Issues + Discussions. Labels mirroring board fields (component:`dmf-*`/cross-repo; workstream:release/compliance/monitoring/…); milestones `v0.1-polish`, `v0.2`. Discussions categories: Announcements, Q&A, RFC (pre-ADR), Show & tell. **Repo-permanence rule: once any issue/Discussion exists, the repo is never deleted/recreated** — pre-flip content corrections happen by force-pushing the replacement orphan commit (private phase only).

*Verification:* `gh repo view` shows private + features enabled; `gh label list` / milestone list match spec.

### WP9 — TODOS.md triage table (judgment) — no dependencies, blocks WP10

Claude produces the triage table: every TODOS.md item → keep-as-issue `{repo, title, labels, milestone}` | drop-as-done | fold-into-existing. **Issue titles/bodies written placeholder-clean from the start** (`<placeholder>` hosts/IPs, no operator identity) — they go public at the flip and the file scrub does not cover them. Each issue body links back to its source doc. Operator reviews the table before WP10.

*Verification:* operator approval; zero identity/topology patterns in the table (grep the table with the WP16 pattern set).

### WP10 — Issue creation + board graduation (mechanical via gh; blocked by WP8 + WP9)

Create issues per the approved table; convert Project #1's 5 draft items to real issues in the right repos; add all to the board; tidy views (group by workstream, status columns). Seed Discussions: one pinned "Decision record (ADR index + digests)" announcement; RFC threads from `docs/questions/` — **seed list operator-reviewed before posting**.

*Verification:* `gh issue list` count == approved table; board has 0 draft items; orchestrator spot-checks 5 issue bodies for placeholder-cleanliness.

### WP11 — TODOS.md retirement, atomic swap (code/doc; blocked by WP10)

One commit: TODOS.md → 5-line pointer (Issues + board URL) **and** boot-ritual doc updates (CLAUDE.md/AGENTS.md/QWEN.md backlog references) together — no window where agents have no backlog. History preserves the old content; no archive file.

*Verification:* no doc still tells agents "the live backlog is TODOS.md"; `grep -rn 'TODOS.md' *.md .claude .qwen` reviewed.

### WP12 — docs/JOURNEY.md (judgment) — no dependencies

"The journey so far" (~3–5 pages): experiment phase → three thesis-killers → Move 1 (NMOS proven) → Move 2 (vertical slice) → MXL spike → commitment gate → v0.1. Pivots/contradictions told as narrative with links into the record. Raw material: strategic review 2026-04-30, technical evaluation 2026-06-06, move-1/2 learnings, architectural-commitments-v1. States which review is current and why the earlier one was right for its time.

*Verification:* operator review; every linked path resolves.

### WP13 — docs/decisions/READING-GUIDE.md (judgment) — no dependencies

"New here? read these ~8 ADRs in this order", layered on the existing 4 digests; everything else stays reference via INDEX.md.

*Verification:* operator review; listed ADRs exist; ≤ 1 page.

### WP14 — docs/OPEN-QUESTIONS.md (judgment) — no dependencies (links added after WP10)

Honest curated list: frozen items (federation, HA, Argo hybrid, in-place upgrade), unproven bits (cloud-lane seed-bao, multi-node), open races (catalog cross-action lock). Links to Discussions/Issues once WP10 exists. `docs/questions/` files stay; this is the curated view.

*Verification:* operator review; consistent with the FREEZE list in architectural-commitments-v1.

### WP15 — Front door (judgment; blocked by WP8, WP12–14; finalized after WP5)

- **README.md rewrite:** what DMF is (1 para), proven-thesis statement, component table (kept), **three audience paths** (casual user → THESIS → dmf-init quickstart; contributor → JOURNEY → READING-GUIDE → CONTRIBUTING → Issues/board; agent operator → CLAUDE.md/AGENTS.md boot ritual); phase section fixed (v0.1 committed, experiment closed); board/Discussions links; stale "Known stale references"/"Origin" sections compressed to a provenance note.
- **docs/THESIS.md** — one-page product thesis: who it's for, the first pain it solves, what a stranger validates in <1 hour. *If it doesn't fit on one page, cut.*
- **docs/INDEX.md** — knowledge-base map (one line per directory; record vs synthesis vs canonical).
- **CLAUDE.md/AGENTS.md/QWEN.md:** boot ritual updated (Issues/board instead of TODOS.md; check-docs gate in the loop; mothballed-harness section shrunk to a 3-line pointer at `docs/agentic/README.md`); new-work convention (issue → on-disk spec with `tracking_issue` → PR closes issue + flips frontmatter); split-brain precedence rule.
- **CONTRIBUTING.md:** contributor path, RFC→ADR pipeline (+ per-ADR announcement-thread convention), where issues live, DCO (existing), board link.

*Verification:* fresh-eyes dry-run by an uninvolved agent pane: README→THESIS→JOURNEY→READING-GUIDE answers "what is this, is it real, how do I try it, how do I help" without opening the record.

### WP16 — Identity/topology scrub sweep (mechanical; blocked by WP15 — don't scrub twice)

~38 operator-note-store refs, ~131 LAN-Forgejo-hostname hits → placeholder conventions (`<lan-forgejo-host>`, `dmf.example.com`); operator handles in STATUS.md HUMAN section → `<handle>`. **Pattern set for verification: do NOT inline it here** (this doc goes public; the pre-commit identity gate rightly rejects literals) — assemble it at run time from the operator-identity + internal-topology rules in `bin/scrub-public-repos.sh` (categories 2+3) and the umbrella `.gitleaks.toml`, plus RFC1918 prefixes, LAN hostnames, and real env ids.

*Verification (orchestrator):* full-pattern grep over all tracked files clean except a reviewed, explicit exemption list of deliberate provenance mentions.

### WP17 — Export, gates, metadata scan, publish (operator-gate; blocked by all of the above)

> Read `docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07.md` first (boot-ritual banner).

- Extend `bin/export-scan.sh` to accept the umbrella (currently hard-refuses `.` as "deferred B2"): orphan single-commit export to `/tmp/dmf-export`, clean public identity, all gates green, never pushes. Confirm the exported STATUS.md HUMAN section is placeholder-clean.
- `bin/scrub-public-repos.sh --tree . --strict` → all blocking categories fixed; `bin/check-public-repo-hygiene.sh` artifacts present.
- **No-allowlist raw grep over the exported tree**: full WP16 pattern set over **every tracked file type** in `/tmp/dmf-export`, no allowlist, every hit manually adjudicated (existing gates allowlist STATUS.md / decisions / publish-spec docs — those allowlists don't apply to the public tree).
- **GitHub metadata scan**: labels, milestone titles/descriptions, Project item titles/notes/field values, repo description/homepage, Discussion category descriptions, security-advisory/ISSUE_TEMPLATE contact links — dump via `gh api`, grep with the same pattern set (the current ISSUE_TEMPLATE already embeds the old `dmf-platform` name; metadata drift is real).
- **Operator pushes** the orphan import; flips Project #1 + repo public; verifies Issues/Discussions visible; CI green.

*Verification:* `export-scan.sh` exit 0; raw grep adjudicated; metadata grep clean; operator sign-off.

---

## Sequencing summary

```
WP1 ──► WP2 ──► WP6 (gate wiring; needs WP4 too)
WP3 (independent)
WP4 (after WP1 schema freeze; validates WP2)
WP7 ──► WP8 ──► WP10 ──► WP11 ──► WP5 ──► WP15-final
WP9 ──────────► WP10
WP12, WP13, WP14 (parallel, judgment) ──► WP15
WP15 ──► WP16 ──► WP17 (operator-gated publish)
```

The v0.1 plan's Phase 1 (reproducibility slice) still gates *the publish claim* — WP17's push timing respects that; everything else proceeds in parallel.

## Risks / gotchas

- **qwen false-DONE** on sweeps — every mechanical WP verified by grep, not by report.
- **Frontmatter edge cases** — YAML must be the literal first bytes; banners/HTML comments move below it; `git ls-files -z` for the 26 special-char filenames.
- **Don't enable the WP6 gate before WP2 is verified** (blocks unrelated commits mid-stream).
- **CI additions** follow hardened-actions conventions (40-hex pinned, read-only permissions, no unpinned downloads).
- **GitHub renders frontmatter as a table** atop each plan — keep the schema minimal.
- **ADR Discussion mirroring** kept to one pinned index thread for the back-catalog; per-ADR threads only going forward.
- **Umbrella repo stays private** until the operator-gated publish; never deleted once issues exist; no force-push after the public flip.

## Review provenance

*Adversarially reviewed by qwen-left 2026-06-10 (8 findings: gate-enablement checkpoint, issue↔frontmatter drift convention, atomic TODOS swap, placeholder-clean issue bodies + pre-flip issue scan, `git ls-files -z` in gate, simple INDEX, STATUS slim limited to operator-tolerable, operator-reviewed RFC seeding) — all folded in.*

*Cross-checked by codex 2026-06-10 (9 findings: repo-name freeze before URL minting; repo-permanence rule + private-phase force-push replacement; no-allowlist raw grep over the exported tree; GitHub metadata scan beyond bodies; mutating agentic scripts fail closed; allowlist-first triage with historical default; explicit issues-win-liveness / frontmatter-wins-record precedence; reviews exempt from frontmatter pass 1; STATUS slim ordered after issue swap, before front door) — all folded in.*
