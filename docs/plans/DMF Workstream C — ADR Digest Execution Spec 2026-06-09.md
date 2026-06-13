---
status: executed
date: 2026-06-09
executed: 2026-06-09
---
# DMF Workstream C — ADR Digest Execution Spec

**Date:** 2026-06-09 · **Status:** Ready to execute (doc-only, no code)
**Parent plan:** `docs/plans/DMF First Public Release Plan 2026-06-09.md` (Workstream C)
**Executor:** qwen-left (lifting) · **Orchestrator/verifier:** claude · **Cross-check:** codex

> **Goal:** make the ADR corpus readable at a glance WITHOUT renumbering, merging,
> or deleting any ADR. ADR numbers are immutable IDs referenced ~385× in code.
> You add *digest* docs and *header pointers* only. **Touch no code. Edit no ADR
> body text** — only prepend a header block to the ADRs named in §3.

## Hard rules (read first)

1. **Do NOT rename, renumber, merge, move, or delete any file in `docs/decisions/`.**
2. **Do NOT edit the body** of any ADR. The only ADR change allowed is
   **prepending** the header block in §3 (everything below the existing
   `# NNNN — Title` line stays byte-for-byte unchanged).
3. **Every factual claim in a digest must be traceable to a canonical ADR** —
   prefer quoting the ADR's own decision sentence over paraphrase. No invented
   facts, no new decisions.
4. Work only inside `docs/decisions/`. Create the new dir `docs/decisions/digests/`.
5. When done, reply via agent-bridge (see §6) with the grep-proof checklist filled in.

## 1. Read these first (source of truth)

- `docs/decisions/INDEX.md` — esp. the "Theme clusters & canonical pointer" table
  and "Open decision debt".
- `docs/reviews/DMF ADR Portfolio Review 2026-05-27.md` — the nits in §5 are fixed here.
- The ADRs named in §2 and §3 below (read each before writing about it).

## 2. Create 4 digest docs under `docs/decisions/digests/`

One file per cluster. Filenames exactly:
- `identity-and-authority.md`
- `catalog-and-execution.md`
- `secrets-and-unseal.md`
- `deployment-scope-and-release.md`

**Cluster → ADR mapping (from INDEX; do not change it):**

| Digest file | Canonical ADR(s) — quote these | History/context ADRs — one row each |
|---|---|---|
| `identity-and-authority.md` | **0028** | 0015, 0021, 0024, 0032 |
| `catalog-and-execution.md` | **0013 + 0025 + 0038** | 0014, 0016, 0027, 0037 |
| `secrets-and-unseal.md` | **0029 + 0009** | 0008, 0011, 0031 |
| `deployment-scope-and-release.md` | **0031** | 0004, 0018, 0020, 0022, 0026 |

**Every digest uses exactly this template** (fill, don't restyle):

```markdown
# <Cluster name> — Canonical Digest

**Scope:** <one sentence: what topic this cluster decides>
**Canonical ADR(s):** `ADR-XXXX (TBD)`[, `ADR-YYYY` ...]
**Last refreshed:** 2026-06-09

> This digest states the **current consolidated truth** for this topic so a reader
> does not have to reverse-engineer it from multiple partially-superseding ADRs.
> The numbered ADRs remain authoritative source; this digest points at them.

## Current truth

- <3–6 bullets. Each bullet states what is true NOW and cites the canonical ADR
  it comes from, e.g. "Machine identities are least-privilege per-service
  (ADR-0028 C3; ADR-0032 for the catalog NetBox writer)." Prefer quoting the
  ADR's decision sentence.>

## History / context behind it

| ADR | Role today | Superseded / amended by |
|---|---|---|
| 00NN | <one line: what it decided + its residual status> | <ADR-XXXX or "—"> |
| ... | ... | ... |

## Open items in this cluster

- <Any Proposed/deferred ADR here (e.g. 0026, 0022, 0027) + its forcing function,
  or "none">.
```

## 3. Prepend a canonical-pointer header to these ADRs ONLY

These are the superseded / partially-superseded / amended ADRs. Prepend the block
**immediately after** the `# NNNN — Title` line (insert a blank line, then the
block, then a blank line; leave the rest of the file untouched):

| ADR file | Cluster digest to point at | Status line to use |
|---|---|---|
| `0004-experiment-phase-stance.md` | deployment-scope-and-release | stance superseded for the committed core by `architectural-commitments-v1` (2026-06-04) |
| `0011-auto-unseal-tradeoff.md` | secrets-and-unseal | reframed as "Tier 3, explicitly chosen" by **ADR-0029**; AWS-KMS variant adopted in **ADR-0031** |
| `0016-awx-control-node-ssh-via-cloud-init-and-openbao.md` | catalog-and-execution | **partially superseded by ADR-0025** (canonical for `media-*` JTs; still authoritative for AWX→infra plays) |
| `0024-two-identity-admin-model.md` | identity-and-authority | **largely superseded by ADR-0028** |
| `0027-catalog-instance-vs-definition-separation.md` | catalog-and-execution | **amended by ADR-0037** (instance layer in NetBox + AWX, not a CRD) |

Header block template (substitute `<digest-file>` and `<status line>`):

```markdown
> **⚠️ Canonical truth for this topic is consolidated in the
> [<Cluster> digest](digests/<digest-file>).** This ADR's status: <status line>.
> Full text preserved below for decision history — do not act on it without
> reading the digest + the named successor.
```

## 4. Portfolio-review nits — **VERIFY-ONLY (already fixed; do NOT edit) [codex]**

The 2026-05-27 portfolio review is stale: its nits were already applied. **Do not
re-edit these — only confirm they are present** (a duplicate edit would churn
settled text). Run the greps and report PRESENT/ABSENT for each; **only** if one is
genuinely ABSENT at the cited location, stop and flag it in your reply (do not fix
it yourself):

1. `0011-auto-unseal-tradeoff.md` — forward-pointer + AWS-KMS reconciliation already
   present (~lines 6-10 and the amendment ~119-146). Verify, no edit.
2. `0030-console-i18n-and-airgap-posture.md` — the dangling "ADR-0028 coupling" is
   already corrected in the decision bullet (~line 16, downstream note ~42). Verify,
   no edit. NOTE: line ~5 still mentions "review on the ADR-0028 coupling" as
   **historical decider context** — that is correct; do NOT touch it.
3. `0020-deployment-scope-and-regulatory-posture.md` — stale-numbering correction
   already present (~lines 253-258). Verify, no edit.
4. `INDEX.md` — the no-gaps wording is already reconciled (~lines 21-22) and ADR-0029
   now EXISTS (~line 62). **No rule-text edit.** The only INDEX change in this
   workstream is the digest-link wiring in §5.

This keeps §4 fully consistent with Hard Rule 2 (the only ADR-file edits are the §3
header prepends; everything else is verify-only).

## 5. Wire the digests into INDEX.md

In `INDEX.md`, in the existing "Theme clusters & canonical pointer" section, add a
link from each cluster row to its new digest file (e.g. append
"· [digest](../decisions/digests/identity-and-authority.md)" to the cluster's "Canonical" cell).
Do not restructure the table.

## 6. Acceptance — reply with this grep-proof checklist filled

Reply via:
`~/.claude/skills/agent-bridge/bin/agent-bridge send claude -- "<reply>"`
(absolute path; bare `agent-bridge` is not on your PATH.)

Fill in actual command output (not "done"). Run from the umbrella root.

- [ ] `ls docs/decisions/digests/` → lists exactly the 4 files.
- [ ] `grep -c '^# ' docs/decisions/digests/*.md` → each has its title.
- [ ] For each of the 5 ADRs in §3: `head -6 <file>` shows the header block AND the
      original `# NNNN — Title` line is still line 1.
- [ ] **New digest files (avoid the pre-existing-untracked false-fail [codex]):**
      `git ls-files --others --exclude-standard docs/decisions/` → exactly the 4
      `digests/*.md` files (and nothing else under docs/decisions/).
- [ ] **Tracked edits are scoped correctly [codex]:**
      `git diff --name-only -- docs/decisions/` → exactly the 5 §3 ADR files
      (`0004,0011,0016,0024,0027`) + `INDEX.md`. **0020 and 0030 MUST NOT appear**
      (they were verify-only). Nothing outside `docs/decisions/` in
      `git diff --name-only` either.
- [ ] **Bodies untouched — prove it per file [codex]:** for each of the 5 §3 ADRs,
      `git diff --unified=0 -- <file>` shows **exactly one hunk, at the very top
      (right after line 1), additions only** (lines start `+`), **zero deeper
      hunks and zero `-` body-deletions**. Paste the hunk header(s) per file.
- [ ] §4 verify-only: report PRESENT/ABSENT for each of the 4 nits at its cited
      location (all should be PRESENT; flag any ABSENT, do not fix).
- [ ] List any digest "Current truth" bullet you could NOT trace to a canonical
      ADR (should be none) — flag any you had to infer. Accuracy over completeness.

**Do not claim DONE without the actual command output above.** If any digest bullet
required inference beyond the ADRs, say so explicitly — accuracy over completeness.
