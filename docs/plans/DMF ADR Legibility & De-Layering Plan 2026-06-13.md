---
status: executed
date: 2026-06-13
executed: 2026-06-13
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/61
---
# DMF ADR Legibility & De-Layering Plan 2026-06-13

> **Goal:** make the 41-ADR decision record legible to a newcomer (human *or*
> cold-start agent) **without adding another layer** — by (A) putting a one-line
> binding **Rule** at the top of each ADR, (B) collapsing the newcomer entry
> points into a **single canonical door** with one bounded "core" set, and (C)
> giving humans a **trip-wire** that surfaces the governing ADR at the moment
> they touch its domain. Net file count goes **down**, not up.
>
> **Provenance:** falls out of the §4 finding of
> [`docs/reviews/DMF ADR Portfolio Review 2026-05-27.md`](../reviews/DMF%20ADR%20Portfolio%20Review%202026-05-27.md)
> (CLOSED 2026-06-12) and the design discussion that followed it. Tracking issue:
> [#61](https://github.com/dmfdeploy/dmfdeploy/issues/61) (see §7).
>
> **Cross-checked** by a sibling qwen agent on 2026-06-13 (adversarial review);
> findings folded in (core set named, citable convention anchor, `STATUS.md` kept
> as provenance, `★` inline). Its lone "blocker" — a supposedly-missing
> `docs/INDEX.md` repoint — was a misread; that ref is already in §5.

## Problem

The decision record is healthy but **not legible on first contact**. A newcomer
faces 41 ADRs and, today, *five* meta-layers pointing at them:
`decisions/INDEX.md`, `decisions/READING-GUIDE.md`, four `digests/`,
`architectural-commitments-v1.md`, and the theme-cluster table inside INDEX.
That is arguably one layer too many already, so the instinct to "add a guide"
is exactly wrong. Two concrete defects:

1. **The binding rule of each ADR is buried in discussion.** To learn what an
   ADR *obliges* you to do you must read the whole Context/Decision prose. The
   template has a bottom `## Enforcement` section but no top-of-doc one-liner.
2. **The "must-read core" set is implicit and duplicated.** `READING-GUIDE.md`
   names 8 load-bearing ADRs in sequence; `architectural-commitments-v1.md`
   names the frozen core; INDEX has a status column and theme clusters. The
   "what must a contributor actually internalize?" boundary is real but lives in
   prose across several docs and can drift.

This matters more here than in a human-only repo: agents start **cold every
session** and re-derive the rules from whatever they happen to read. A
discipline-only decision that isn't reliably *surfaced* effectively does not
exist for the next agent. So "surfacing = enforcement" — and the cheapest
surfacing is co-located (in the ADR) and singular (one door), not another
layer.

## Scope

**In scope (this plan = legibility & de-layering only):**

- **A** — top-of-ADR `**Rule:**` line + template change.
- **B** — single canonical newcomer door + one bounded "core" marker; fold/retire
  the redundant entry point.
- **C** — human trip-wire surfacing (PR template + contributor-path pointer).

**Explicitly OUT of scope (do not let this PR grow into it):**

- **Mechanical enforcement / per-ADR "enforcement tier" taxonomy** and writing
  missing CI gates. That is the *hard* strand of Portfolio-Review §4 and is a
  separate decision with its own cost/benefit. → **deferred to a follow-up
  issue** (see §8). Conflating "make ADRs legible" with "mechanically enforce
  ADRs" would bloat this change and muddy review.
- Re-litigating any ADR's *content*. This is presentation only; **no decision is
  reopened.**
- The digests are **kept as-is** (they consolidate per-cluster current truth and
  solve the "assemble truth from 8 partially-superseding docs" problem — that is
  real work, not redundancy). Considered and deliberately not folded. **Digests
  are *content* (per-cluster consolidated narrative); INDEX is a *pointer*
  (catalog + sequence) — different jobs, not stacked layers.**

## A — Top-of-ADR Rule line

**What:** directly under the `**Status:**/**Date:**/**Deciders:**` block, a
single bolded line:

```
**Rule:** <the binding constraint, one imperative sentence>
```

Example (ADR-0006): `**Rule:** The live cluster is the source of truth; never
trust or act on local kubectl state.`

It is the *obligation*, not the rationale — the newcomer reads one line; the
executive reads the whole doc. It is co-located (cannot drift out of sync with
the decision) and adds zero files.

**Template change:** add the `**Rule:**` line to
[`docs/decisions/0000-template.md`](../decisions/0000-template.md) (mandatory
going forward). Leave the existing bottom `## Enforcement` section untouched —
Rule (what binds you) and Enforcement (how it's kept honest) are different jobs.

**Citable anchor (no ADR needed):** also add a one-line convention comment at the
top of the template — `<!-- ADR convention: every ADR carries a top-of-doc
**Rule:** line; see CONTRIBUTING.md → ADR conventions -->` — and a 2–3 line **"ADR
conventions"** subsection to `CONTRIBUTING.md` (Rule line mandatory · Enforcement
section mandatory · filename `NNNN-kebab-title.md`). A subsection in an existing
file, not a new layer; it gives the convention something to cite when an ADR
lacks a Rule line.

**Backfill scope — DECISION B1-adjacent, see §6:** backfill the Rule line on the
**core set only** (the 8 named in §B) in this PR (bounded, high-quality, reviewable), make it
mandatory in the template for all new ADRs, and backfill the remaining ~33
opportunistically (when an ADR is next touched) or in a follow-up. Rationale: a
41-file diff where each line needs *judgment* is not cross-checkable in one
sitting; a careless backfill produces 41 mediocre one-liners, which is worse
than none.

## B — One canonical door, one core set

**Core set (this PR's bounded scope — 8 entries):** ADR-0003,
`architectural-commitments-v1`, ADR-0013, ADR-0025, ADR-0028, ADR-0008, ADR-0035,
ADR-0036 (the READING-GUIDE pedagogical sequence). The `★` marker (below) and the
Rule-line backfill (§A) apply to **exactly these** — a reviewer counts 8 rows, no
reverse-engineering from a cited doc.

**Decision to confirm (B1) — see §6.** Recommended approach:

- **Promote `decisions/INDEX.md` to the single newcomer door.** Add a short
  **"Start here"** section at the top: the core ADRs **in pedagogical order**
  (the existing READING-GUIDE sequence: taxonomy → commitments → catalog model →
  execution → identity → secrets → operator-local envs → dmf-init), each line
  carrying its new one-sentence Rule inline so the door *is* the summary.
- **Mark the same set in the catalog table** with a `★` (core) flag so "what
  binds a contributor" is visible without opening anything — the **same** bit
  that bounds the must-read set *and* (if the enforcement strand ever lands) the
  set whose bar is raised. One distinction, drawn once.
- **Retire `decisions/READING-GUIDE.md`** (its curriculum now lives in INDEX
  "Start here"). Repoint all inbound references (§5). This is the actual
  de-layer: one fewer file, the core list lives in exactly one place.

**Alternative (B1-alt):** *keep* READING-GUIDE as the curriculum door and do
**not** add a core marker to INDEX (avoid duplicating the list). Lower blast
radius (no inbound repoints, discussion #27 stays valid) but leaves two doors.
Captured for the cross-check; the recommendation is to fold.

## C — Human trip-wire surfacing

Newcomers should never have to read the record front-to-back; the relevant ADR
should **find them** when they touch its domain.

- **Agents:** already covered — the boot ritual ("skim INDEX, apply relevant
  ADRs") and skill `§0`s. No change.
- **Humans (minimal, recommended — C1):**
  - Add one line to `.github/pull_request_template.md`: a checkbox —
    *"I checked the governing ADR(s) for the area I changed (see
    `docs/decisions/INDEX.md`)."*
  - Ensure `CONTRIBUTING.md`'s contributor path points at the **single door**
    (INDEX "Start here") rather than READING-GUIDE.
- **Deliberately NOT doing (C1-alt, rejected as ceremony):** a per-directory
  README→ADR map or a CODEOWNERS-style area→ADR mapping. High maintenance, drifts,
  and re-creates a layer. Trip-wire = one pointer at the single door, not a matrix.

## 5 — Inbound-reference repoint set (if B1 = fold)

Retiring `READING-GUIDE.md` requires repointing these **live** refs to
`decisions/INDEX.md` (anchor `#start-here`). Verified by `grep` on 2026-06-13:

| File | Line | Note |
|---|---|---|
| `README.md` | 26 | contributor audience path |
| `CONTRIBUTING.md` | 15 | **text reword, not just a URL swap** — "the ~8 ADRs" → "the core ADRs marked ★ in INDEX" |
| `CLAUDE.md` | 75 | "New here" table row |
| `docs/INDEX.md` | 16 | top-level docs index row |
| `docs/JOURNEY.md` | 117, 230 | two prose links — repoint **both** |
| `docs/THESIS.md` | 72 | prose link |

- **`STATUS.md:117` is provenance, not navigation** — it records that WP13
  *created* `READING-GUIDE.md`; that historical fact stays true regardless of the
  fold. → **do not repoint** (struck from the table above).
- **Plan-doc refs are historical** (`DMF Umbrella Public Entrance ... 2026-06-10.md`
  lines 137/151/157) → **do not repoint** (frozen provenance).
- **GitHub Discussion #27** links to `READING-GUIDE.md` (we fixed it 2026-06-12).
  If folded, re-point it to `INDEX.md#start-here` via `gh api graphql
  updateDiscussion` as a post-merge step (external; not in the PR diff).
- `bin/check-docs.sh`'s unresolved-relative-link warning is the backstop that
  catches a missed repoint.

## 6 — Decisions to confirm (for the cross-checking agent)

1. **B1 — fold vs keep READING-GUIDE.** Recommend **fold into INDEX + retire**
   (true de-layer) vs keep it as the door (lower blast radius). *Lead author
   leans fold.*
2. **A backfill breadth.** Recommend **core set only this PR** + template
   mandatory + opportunistic rest, vs backfill all 41 now.
3. **RFC/ADR-worthiness.** This edits the ADR *template* and retires a
   governance doc. Recommend **issue + this plan, no new ADR** — spinning up an
   RFC-then-ADR to authorize de-layering is self-defeating ceremony; record the
   convention in the template comment + CONTRIBUTING. (Alternative: a small
   ADR-0042 "ADR document conventions" if we want the convention itself
   citable.) *Lead author leans no ADR.*
4. **`★` glyph vs a `core` column** in the INDEX table — **recommend `★` inline in
   the Title column** (keeps the existing 4-column `# | Title | Status | Domain`
   layout; marks existing structure instead of adding a column). Implementer may
   override, but the default is set to avoid thrash.

## 7 — Working-model / PR procedure compliance

Per `docs/WORKING-MODEL.md` and the `guard` CI gates (we hit `issue-link` on
PR #49 — this is **tracked work**, so it must reference an issue; `no-issue`
does **not** apply):

1. **Tracking issue opened:** [#61](https://github.com/dmfdeploy/dmfdeploy/issues/61)
   (`component:umbrella` + `workstream:entrance`, milestone `v0.1-polish` — serves
   the "legible to an outsider" work-selection rule). This plan's `tracking_issue:`
   frontmatter is set to it.
2. **Flip frontmatter:** `status: draft → active` when work starts; the
   completing PR sets `status: executed` + `executed: <date>` **in the same
   change** that closes the issue.
3. **The implementing PR** must: apply A/B/C; close the issue (`Closes #N`);
   flip this plan's frontmatter; regenerate `docs/plans/INDEX.md`
   (`bin/generate-plans-index.sh`); repoint §5 refs; pass `check-docs` + `guard`.
4. **Commit discipline:** DCO sign-off, **no `Co-Authored-By` trailer** (operator
   policy).
5. **Concurrency:** the implementing agent should work in an **isolated git
   worktree** (another agent is active in the shared umbrella tree — this plan
   itself was authored in one) and stage files surgically (never `git add -A`).

## 8 — Deferred follow-up (separate issue)

The §4 "enforcement is discipline-only" strand — giving Accepted ADRs an honest
enforcement *tier* and writing the cheap missing gates, with the bar raised on
the **committed core** now that the experiment phase closed (2026-06-06). Open
as its own issue; **do not** fold into this PR. The `★`-core marker from B is the
natural input to that work (the set whose bar rises = the set already flagged).

## 9 — Verification

Fresh-eyes dry-run by an **uninvolved agent pane** (same method as the Public
Entrance plan's WP13 check): starting from `decisions/INDEX.md` alone, can a
newcomer answer *"what binds me when I touch X?"* by reading only the "Start
here" section + the relevant Rule line — **without opening all 41 ADRs**? If yes,
the de-layer worked. Plus: `bin/check-docs.sh` green (no unresolved links from a
missed repoint), `guard` green.

## Risks

- **Missed inbound repoint** → dangling link. *Mitigation:* §5 list + check-docs
  unresolved-link warning + the fresh-eyes dry-run.
- **Discussion #27 re-breaks** (we fixed it twice already). *Mitigation:* explicit
  post-merge step in §5; or choose B1-alt (keep READING-GUIDE) and the link stays
  valid.
- **Rule-line quality drift** if backfilled carelessly. *Mitigation:* core-only
  scope in this PR; each Rule line reviewed.
- **Scope creep into enforcement-tiering.** *Mitigation:* §8 fence.
- **Concurrent-agent collision** on the shared tree. *Mitigation:* worktree
  isolation + surgical staging.
