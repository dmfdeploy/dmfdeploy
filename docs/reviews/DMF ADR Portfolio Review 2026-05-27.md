# DMF ADR Portfolio Review — 2026-05-27

**Reviewer:** Claude (Opus), at operator request
**Scope:** All 31 ADRs in [`docs/decisions/`](../decisions/) (0001–0028, 0030, 0031, 0032).
**Mode:** Read-only review. No ADR content was changed. This document records
findings; the §6 actions were *recommendations* at the time of writing.

> **Resolution — 2026-06-12: CLOSED.** All §2 contradictions and §6 organizing
> actions were applied 2026-05-30 and re-verified 2026-06-12: **0029** written;
> **0011** amended with forward-pointers to 0029/0031; **0020** numbering
> corrected; **0030** dangling reference fixed; **INDEX** gained a status column
> for partially/largely-superseded ADRs (0016, 0024) plus a "Theme clusters &
> canonical pointer" map. The two §5 cosmetic nits (**0015** format, **0017**
> operator-local paths) were resolved 2026-06-12. **One finding is standing —
> not a checklist item:** §4's "enforcement is discipline-only" gap, sharpened
> now that ADR-0004's experiment-phase stance is superseded by
> [`architectural-commitments-v1`](../decisions/architectural-commitments-v1.md)
> (2026-06-06).

---

## 1. Snapshot

**31 ADRs**, dated 2026-04-17 → 2026-05-27, covering structure, security,
operations, lifecycle, architecture, networking, strategic posture, and release.
ADR **0029 does not exist as a file** (reserved, never written — see §2.3).

| Status | ADRs |
|---|---|
| **Accepted** | 0001–0010, 0012–0019, 0021, 0023, 0024, 0025, 0028, 0031, 0032 |
| **Accepted w/ explicit caveat** | 0011 (known tradeoff), 0020 (Mode A only; B/C Proposed) |
| **Proposed** | 0022, 0026, 0030 |
| **Proposed-deferred** | 0027 |
| **Partially superseded** | 0016 (superseded by 0025 for `media-*` JTs only; still canonical for infra plays) |
| **Missing / reserved** | 0029 |

**Overall verdict: healthy and unusually disciplined.** Cross-referencing is
dense, supersession chains are tracked (0016→0025, 0024→0028), amendment logs
carry dates + commit SHAs, and [ADR-0011](../decisions/0011-auto-unseal-tradeoff.md)
is a model of honest tradeoff documentation. The problems below are maintenance
drift and over-fragmentation, not rot.

The corpus clusters into four themes, two of which are over-fragmented:

- **Foundations** (0001–0006): stable, clean, no issues.
- **Secrets / identity** — 0007, 0008, 0009, 0011, 0015, 0021, **0024, 0028**,
  0032 (~9 ADRs). Over-fragmented; see §4.
- **Catalog / execution** — 0012, 0013, 0014, **0016, 0025**, 0017, 0027, 0032
  (~8 ADRs). Densest cluster; current truth is spread across partially-superseding docs.
- **Deployment scope / release** — 0004, 0018, 0019, 0020, 0022, 0026, 0030, 0031.

---

## 2. Contradictions (concrete)

### 2.1 Cloud-KMS unseal: 0011 rejects it, 0031 adopts it
[ADR-0011](../decisions/0011-auto-unseal-tradeoff.md) §Alternatives C rejects
cloud-KMS auto-unseal as a "philosophical mismatch with a local-first lab."
[ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md)'s
AWS profile makes **AWS KMS auto-unseal the release-default boot posture**. 0031
reconciles this *in spirit* ("topology shifts to cloud-first"), but **0011 has no
amendment pointing forward to 0031** — a reader of 0011 alone gets the wrong
current answer.

### 2.2 Numbering forward-references are now wrong
[ADR-0020](../decisions/0020-deployment-scope-and-regulatory-posture.md)'s
2026-05-23 amendment proposes future "ADR-0028 managed-service, ADR-0029
flypack-offline." In reality **0028 became Identity & Authority Chain** and
**0029 is reserved for tiered-unseal**. The suggested numbering in 0020 is stale
and misleading.

### 2.3 INDEX self-contradiction
[INDEX.md](../decisions/INDEX.md) states "Numbering is monotonic, **no gaps**,"
yet the index itself skips 0028→0030 and the 0030 row admits "0029 reserved for
tiered-unseal posture." The governance doc violates its own rule.

### 2.4 Dangling reference in 0030
[ADR-0030](../decisions/0030-console-i18n-and-airgap-posture.md) says "re-open
the Radix/shadcn choice in favour of React Aria — **see ADR-0028 coupling
below**." There is no such section, and **ADR-0028 is the Identity/Authority
Chain** (nothing to do with UI primitives). Either a missing section or a wrong
ADR number — needs verification.

---

## 3. Staleness

- **ADR-0011 triggers are overtaken.** Its revisit triggers reference "Move 2
  lands" (old roadmap vocabulary) and "repo goes public" — the latter is now
  *actively firing* via ADR-0031 (OSS v0.1). Its stated "next-state target = HA
  bao" has been overtaken by a per-profile resolution (sandbox local-unseal /
  AWS KMS / the reserved tiered-unseal ADR). Needs an amendment acknowledging 0031.
- **ADR-0004 thesis-killers partially resolved but unamended.** Thesis-killer #1
  ("NMOS on commodity k3s — `dmf-media/` is empty") has materially advanced —
  nmos-cpp catalog ran end-to-end per ADR-0025. ADR-0004 still reads as if Layer
  5 is untouched.
- **ADR-0026 (Provider Descriptors) is stalling in Proposed.** Its own status
  note admits "the descriptor exists; the loader does not," and ADR-0031 O5
  explicitly routes v0.1 *around* it with an inline manifest, deferring
  descriptors to v0.2. Worth a status check — it may be drifting toward irrelevance.
- **ADR-0023 has a promised-but-unwritten amendment.** Its 2026-05-19 update says
  the scope table "will be simplified… Tracked as a follow-up amendment" once
  Lane C lands. Open loop.
- **Env-slug churn.** ADRs anchor evidence to ephemeral env ids: `hetzner-arm`,
  `aliyun-123` (both retired), `g2r6-foa9` (0031's "live lab"), `z4ud-sy22`, and
  `wobe-9n0c` (0032, 2026-05-27). These age fast by design — 0024/0026 already
  carry "retired" notes, but it's a recurring maintenance tax.

---

## 4. Over-complexity / sprawl

- **Identity model is spread across 5 ADRs + 3 plans + a separate architecture
  doc.** 0015→0021→0024→0028→0032. Notably, **0024 was heavily superseded by 0028
  only two days after acceptance** (05-22 → 05-24). The INDEX lists 0024 as plain
  "Accepted" with no status-column forward-pointer to 0028 — a reader could treat
  0024 as current. Two backend-split helper roles (`admin-identity-resolve` vs
  `app-admin-facts`) add real indirection that 0028 itself flagged as borderline
  scope creep.
- **Catalog / execution requires assembling current truth from ~8
  partially-superseding ADRs.** 0016 is the trap: half-superseded, two separate
  amendment dates, canonical for some job templates and dead for others. 0027 is
  a Proposed-deferred Kubernetes operator that may never be built.
- **ADR-0031 is ~28 KB, roughly half a non-binding "Historical draft."**
  Preservation is deliberate and well-marked, but it's a footgun — a careless
  reader could act on the superseded AWS-only content.
- **Enforcement is "discipline-only" almost everywhere.** ~10 ADRs (0002, 0007,
  0010, 0011, 0018, 0023, 0026, 0028, 0032…) defer their enforcement mechanism to
  a future hook/CI gate/verifier. Acceptable for experiment phase, but
  portfolio-wide the gap between "decided" and "mechanically enforced" is wide.

---

## 5. Governance / formatting nits

- **ADR-0015 breaks format convention** — YAML frontmatter + em-dash heading
  instead of the `**Status:**` bold-line style; no Enforcement or Deciders
  section; and it oddly refers to an "ADR-0015 precursor" inside itself.
- **ADR-0017 embeds operator-local paths** (`~/Downloads/…pdf`,
  `<home>/mxl-smoke-tmp/…`) — minor hygiene against the repo's own "no local
  paths" discipline.
- **Status taxonomy lacks "partially superseded"** — 0016's real state is forced
  into parenthetical prose in both the file and the INDEX.

---

## 6. Suggested organizing actions (not applied)

Tidy-ups that do not reopen any decision:

1. **Resolve the 0029 question** — either write the reserved tiered-unseal ADR,
   or change the INDEX "no gaps" rule to "gaps allowed for reserved numbers" and
   annotate 0029 as reserved. Pick one. (Fixes §2.3.)
2. **Amend ADR-0011** with a forward-pointer to ADR-0031 (KMS reconciliation) and
   refresh its triggers to current roadmap vocabulary. (Fixes §2.1, §3.)
3. **Strengthen the INDEX status column** for superseded / largely-superseded
   cases (0016, 0024) so the canonical successor is visible without opening the
   file. (Addresses §4.)
4. **Fix the ADR-0030 "ADR-0028 coupling" reference** — verify intended target.
   (Fixes §2.4.)
5. **Correct ADR-0020's stale numbering suggestion** (0028/0029 no longer mean
   what it predicted). (Fixes §2.2.)
6. **Add a one-page "ADR map"** grouping the identity cluster (canonical = 0028)
   and the catalog cluster (canonical = 0013 + 0025) so newcomers don't
   reverse-engineer current truth from 8 documents.

---

## 7. Strengths worth preserving

- Honest tradeoff documentation (ADR-0011 is exemplary — it explicitly states
  where Shamir *does not* defend, rather than over-claiming).
- Live-verification records with commit SHAs and env names (0021, 0025, 0028).
- Disciplined supersession with forward links and dated amendment logs.
- Clear "Enforcement" and "Alternatives considered" sections on nearly every ADR.
