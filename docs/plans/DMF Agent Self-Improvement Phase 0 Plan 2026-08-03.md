---
status: active
date: 2026-08-03
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/355
---
# DMF Agent Self-Improvement — Phase 0 Plan (2026-08-03)

> **STATUS: ACTIVE.** Deliverable of umbrella
> [#355](https://github.com/dmfdeploy/dmfdeploy/issues/355). This plan
> implements **only** Phase 0 of a larger design. That larger design — an
> automated loop analysing our own agent-to-agent exchanges and proposing
> changes to agent behaviour — was written, adversarially reviewed, and
> **recommended against building at current scale.** The analysis is not
> public. This document records what Phase 0 is, why the rest is deferred, and
> what would have to change to revisit it.

## 1. Why only Phase 0

The full design was reviewed adversarially and returned **FAIL with four P1
findings**. The deferral is **forced by those findings**, not a considered
preference arrived at independently:

1. **Cross-vendor is not verifier independence.** The adversary produced much of
   the evidence the loop would analyse, and would then be asked to refute
   conclusions distilled from its own past verdicts. Vendor diversity reduces
   correlated failure only probabilistically; the documented self-preference
   effect is driven by output familiarity, which changing vendors does not
   remove.
2. **The "forbidden targets" boundary was a policy promise, not a mechanism.** A
   change to dispatch templates can alter the adversary's effective prompt,
   required reads, or probe scope without touching anything named "gate prompt"
   or "CI config". Enforcing it would need an immutable path allowlist outside
   the loop's own credentials, a protected validator, and a hash-pinned
   validation set — none of which was specified.
3. **The proposed auto-apply tier changes behaviour.** It was justified as
   "hygiene that cannot alter what an agent does". It can: repairing a dangling
   skill link **activates a previously dormant skill**; repairing a truncated
   description invents semantics that drive retrieval; deduplication changes
   retrieval order. There is no safe auto-apply tier, and the concept was
   removed.
4. **A record identifier does not establish that evidence is authentic.** A
   recorded turn can assert that a live probe ran and passed with no
   corresponding tool event behind it. Following a pointer to that turn confirms
   the pointer, not the probe.

At current scale the review's cost/benefit conclusion — implement the dispatch
rules and a recording convention; do not build the loop — is accepted.

## 2. What Phase 0 delivers

### 2.1 A conversation-recording format skill

`.agents/skills/agent-conversation-recording/` — **format only, deliberately
silent on storage, transport, retrieval, and tooling.**

Without a fixed grammar, records drift within weeks: turn headers acquire
several incompatible shapes, verdict wording varies by author, classification is
skipped, and the boundary of "one conversation" moves. The cost is not
aesthetic — it makes any count derived from the records wrong in a direction
nobody notices, because verdict-shaped text gets counted from turns that merely
*quote* an earlier verdict.

The skill fixes: a schema version; a closed metadata schema with enum-valued
`Mechanism`, `Type`, and `Outcome`; ISO-8601 timestamps; a single turn-header
grammar; and objective conversation boundaries (a new record begins when the
work item changes, or when the receiving agent's context is reset — both
observable facts rather than judgement calls).

Its most important decision is structural: **the binding verdict lives in record
metadata, never in a turn body.** Turn bodies are verbatim and carry no
authority. That removes the quoted-verdict ambiguity outright instead of asking
each reader to disambiguate — fencing a quotation does not help, since a fenced
quotation still contains a verdict-shaped line.

**Why the skill is format-only.** Public-trajectory content must not characterise
where or how exchanges are retained; a pointer to a non-public location is itself
the disclosure, and "not named, only described" is not a defence. That constraint
is very likely why no such skill existed before. The resolution is that the
*format* is publishable even when nothing else about the arrangement is.

### 2.2 The five anti-churn rules, in the dispatch path

`.agents/skills/issues-cruncher/references/anti-churn-rules.md`, wired into the
cruncher's hard gates (new gate 8) and phases 3–4, as an **explicitly delimited
paste payload** so "paste verbatim" has one determinate meaning.

Four are the operator's own rules from the 2026-08-01 retrospective — comment
fidelity, ownership-move lifecycle test, counts-as-pasted-output, sibling sweep.
A blind automated pass over that session recovered all four independently.

The fifth is new: **premise citation**, scoped to *decision-bearing* premises
(those determining scope, expected behaviour, or an acceptance criterion) and
discharged by a premise table in the WO report — `premise | source | check |
result`. Motivated by four wrong architectural premises entering one session
through the orchestrator's own work-order text in a single day, every one caught
only because the implementer read canonical docs before building. Dispatch text
is a reliable *delivery channel* and an untrusted *content source*.

Rule 1 says the working tree **after the edits**, not the committed file: the
commit is gated until cross-check and verify pass, commit ownership is the
orchestrator's alone, and the implementer is forbidden from committing — so at
WO-report time there is nothing committed to re-read.

### 2.3 Why the dispatch path rather than memory

- **Empirical** — the retrospective's own finding: a rule adopted at the day's
  first FAIL was violated four rounds later. Rules held in memory decay within a
  single session.
- **Structural, correctly stated** — the adversary has **no memory store**. It
  reads the canonical `.agents/skills/` tree natively (ADR-0042 §Decision chose
  that path because Codex, Gemini, and Cursor read it directly, needing no
  generated view), so skills *do* reach it; memory does not. Dispatch text and
  skills reach every agent, memory reaches one.
- **Reproduced under observation** — while producing this work, an agent that had
  just authored a warning about pattern-matching verdict markers committed that
  exact error three tool calls later, with the lesson still in context. **Recall
  is not enforcement.**

> An earlier draft of this plan asserted the adversary had "no skills store at
> all" and that dispatch text was therefore "the only channel by construction".
> That was false, and contradicted an accepted ADR — caught in review. It is
> recorded here rather than silently corrected, because it is precisely the
> failure rule 5 exists to prevent: a decision-bearing premise asserted without
> citing the source that would have falsified it.

## 3. Explicitly out of scope

| Deferred | Why |
|---|---|
| The analysis loop and its refutation stage | Four unrepaired P1s; not justified at current scale |
| A rejects ledger | Only meaningful once a loop exists |
| A vendor-neutral memory store | Genuinely new transformation, merge, and rollback machinery — not a reuse of the skills pipeline, as the design had claimed |
| Memory hygiene | No repo change; and there is no safe auto-apply tier |

## 4. What would justify revisiting

Capacity-based triggers, not efficacy-based. The original trigger — "build it if
the dispatch rules work" — was backwards: if the rules work that argues for more
rules, and if they fail that calls for diagnosis, not automation. Revisit when:

- **volume outgrows reading** — an operator can no longer read a session's gate
  rounds in the time available, sustained over weeks;
- **recurrence goes cross-session** — a defect class recurs across sessions far
  enough apart that no human would connect them, observed more than once;
- **the rule set stops converging** — new rules keep being needed at a rate
  suggesting classes are missed rather than fixed.

None holds today.

## 5. Acceptance

- [x] Recording skill in the canonical store, passing the metadata rubric, and
      disclosing nothing about storage, transport, retrieval, tooling, **or the
      existence and nature of any non-public location**.
- [x] Five rules reachable from the dispatch path as a delimited payload;
      cruncher hard gate 8 added; phases 3–4 point at them.
- [x] This plan carries `tracking_issue` frontmatter; `docs/plans/INDEX.md`
      regenerated.
- [ ] `bin/sync-skills.sh --check` and `bin/check-docs.sh` pass in CI.
- [ ] Adversarial re-gate after the review fixes — **pending**, adversary seat
      unavailable.

## 6. Incidental fix

`issues-cruncher`'s Reuse section cited a **generated view** rather than the
canonical store, and named `orchestrated-lifter-workflow`, retired 2026-07-14
(merged into `cold-agent-execution`). Both corrected.

Still outstanding, deliberately not fixed: the cruncher names **qwen** as the
implementer, which no longer matches the live roster. Larger edit; own pass.
