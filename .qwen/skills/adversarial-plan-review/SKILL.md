---
name: adversarial-plan-review
description: Structured adversarial review of implementation plans, specs, and decision documents — cite section refs, prioritize P1/P2/P3, verify against parent docs before judging
source: auto-skill
extracted_at: '2026-06-02T16:15:00Z'
---

# Adversarial Plan Review

A read-only, adversarial review of an implementation plan or spec document. The goal is to surface gaps, contradictions, and underspecified acceptance gates *before* implementation starts — when fixes are cheapest.

## When to use

- A plan or spec has been drafted for a multi-slice implementation.
- Another agent or human has asked for adversarial review before committing.
- You want to verify that acceptance gates actually prove what the slice claims.
- Security, crypto, or supply-chain decisions need a second pair of eyes.

**Read-only.** Do not edit the review target or any related docs. Produce a verdict + prioritized findings.

## Procedure

### 1. Ground yourself (read-only)

Read these in order:
1. **The review target** — the plan or spec under review.
2. **Parent/authoritative specs** — the plan's stated parent doc (usually "Parent spec: …" at the top). Cross-check locked decisions, contracts, and scope boundaries.
3. **Scaffold docs** — the component repo's README, ARCHITECTURE.md, CLAUDE.md, VERSION. Verify the plan's claims match reality (e.g., "CI exists" → check `.forgejo/workflows/`).
4. **Relevant memory** — check for prior incidents the plan should account for (e.g., SSH key leaks, credential incidents).

### 2. Critique dimensions

Evaluate against these 5 dimensions. For each finding, **cite the plan section** (e.g., "plan §D1", "§1a.2 Acceptance") so the recipient can fold it precisely.

#### a. SLICING
- Is the slice order correct (foundation → risky bit → orchestration → manage)?
- Can each slice be **independently verified** without depending on the next slice's output?
- Are acceptance gates **sufficient to prove** that slice? (An image can build and pass /healthz while having an empty COPY'd repo layer — the gate must probe the actual dependency.)
- Is anything in the wrong slice, or is a slice missing?

#### b. ARCHITECTURAL DECISIONS
- Are the stated decisions (D1, D2, …) justified by the constraints the plan cites?
- If the plan acknowledges a risk (e.g., "transient coupling to unmerged branch"), is there a **mitigation** or just a note? Notes are fine for experiment phase, but flag when a mitigation is needed.
- Does the decision create a reproducibility, supply-chain, or provenance hazard? How is it bounded?

#### c. SECURITY / NON-NEGOTIABLES
- Does the plan uphold the component's stated invariants (stateless, loopback-only, public-safe, secrets-never-logged)?
- Token schemes: will the token leak via access logs, query params, or request bodies?
- Secret transport: how do secrets cross from frontend to backend? Are POST bodies logged?
- tmpfs/runtime state: is it size-bounded, or will it OOM?

#### d. CRYPTO / BACKUP RISK
- If backup/crypto is involved: is the hash contract unambiguous? (e.g., MANIFEST sha256 of what — inner payload or outer tarball?)
- Write-validate: does `touch` prove overwrite, or only create? Append-only remotes pass touch but fail actual backup.
- Key ordering: does restore extract the age key *before* running doctor?
- Are defaults adequate? (e.g., age --passphrase scrypt work factor for high-value secrets.)

#### e. CONCURRENCY / THREADING (for designs with workers, streams, or pause/resume)
- **Lifecycle ordering:** define an atomic `emit(event)` method that does `events.append() → queue.put() → if terminal: set flag`. All worker code must go through this. Test that no client can see `terminal=True` with a missing terminal event.
- **Queue semantics on disconnect:** when a stream consumer disconnects, what happens to events the worker keeps `put()`-ing? Is the replay-log canonical (reconnect serves from `events[from:]` only), or does the queue retain orphaned events that cause duplicates?
- **Terminal event delivery gap:** after yielding a terminal event, the next `queue.get(timeout=N)` blocks for N seconds before the stream closes. Fix: break immediately after terminal (it's final).
- **Lost-wakeup on pause/resume:** if the resume endpoint sets a `threading.Event` *before* the worker creates it (lazy creation at the pause point), the worker waits forever. Fix: pre-create all pause events at `start` time (the step graph is known upfront).
- **Redaction-set mutation across threads:** if secrets are added to the redaction set mid-run (e.g., captured unseal key at a checkpoint), the set is mutated by the worker but read by the stream consumer for on-the-fly redaction. Fix: add a `threading.Lock` around the set, or enforce that redaction is always done in the worker before emit.
- **Secret lifecycle in run objects:** if passphrases/keys are held in `app.state` run objects for re-use (e.g., re-backup), ensure (a) they're wiped after last use, (b) error handlers don't log `repr(run)` or serialize them, (c) finished runs are garbage-collected with a TTL or explicit delete endpoint.
- **Back-pressure:** if the worker produces events faster than the consumer yields them, is there a bound? An unbounded `queue.Queue` won't deadlock but can grow indefinitely for long-running commands with massive output.

#### f. MISSING RISKS / ACCEPTANCE GAPS
- CI alignment: are the plan's acceptance gates the **same tests** as the CI workflow, or do they drift?
- Tool version pinning: floating vs pinned? If floating, is the known-good set documented?
- Multi-arch: what's the target? Is it stated explicitly?
- Build reproducibility: `npm ci` vs `npm install`? `pip install .` vs lockfile?
- Image size budget: noted or ignored?

### 3. Prioritize findings

| Priority | Meaning | Example |
|---|---|---|
| **P1** | Correctness or security gap that would cause a broken build, secret leak, or acceptance gate that doesn't prove the slice | Token in access log; gate doesn't verify repo layer; MANIFEST sha256 chicken/egg |
| **P2** | Gap that won't break the slice but creates operational friction, ambiguity, or future rework | No reproducibility manifest; passphrase logging unspecified; tool versions floating without documentation |
| **P3** | Nice-to-have or deferred concern that should be tracked | Image size budget; build helper acceptance criteria |

### 4. Produce the review

Structure the reply as:

```
VERDICT: LGTM / CHANGES-NEEDED

## 1. SLICING (plan § "…")
P1/P2/P3 — finding text, citing the section

## 2. DECISIONS (plan § "D…")
...

## 3. SECURITY / non-negotiables
...

## 4. BACKUP/CRYPTO risk (plan § "…")
...

## 5. CONCURRENCY / threading (plan § "…")
...

## 6. MISSING RISKS / acceptance gaps
...

## Summary
| Priority | Count | Theme |
...
```

**End with a summary table** so the recipient can track how many findings landed at each priority and what themes emerged.

## Principles

- **Cite section refs** for every finding. The recipient needs to know exactly where in the plan the gap lives.
- **Propose mitigations**, not just problems. "Add X to acceptance gate" is better than "gate is missing X."
- **Acknowledge correct decisions**. If a slicing choice is sound, say so — the recipient should keep confidence in the parts that work.
- **Read-only.** You are critiquing, not editing. The plan owner folds the findings.
- **Distinguish experiment-phase tolerances from hard requirements.** Floating tool versions are fine for experiment phase; secrets in tracked files are never fine.
