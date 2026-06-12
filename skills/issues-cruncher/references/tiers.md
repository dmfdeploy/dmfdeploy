# Risk-Signal Tiers

Match ceremony to risk, sized by **what the change touches**, not by diff size. A
one-line change to a lock is Tier 3; a 200-line docs sweep is Tier 1.

## Signals (any present ⇒ at least Tier 3)

Concurrency / locks / subprocess / async cancellation · auth **flow**, session, or
token handling · data migration / schema change · money or billing · destructive or
irreversible ops (delete, force-push, teardown) · **public contract** (API, CLI,
released artifact, wire format).

**Negative examples (do NOT bump):** editing auth *docs* ≠ auth risk; renaming a
variable in a payments file ≠ money risk; adding a test ≠ the tier of the code under
test. The trigger is touching the *behavior*, not the *vicinity*.

## Tiers

| Tier | Means | Crew | Deliverables |
|---|---|---|---|
| **1** | trivial, reversible, local | orchestrator solo | edit + verify on disk |
| **2** | normal feature/bugfix, no signals | + implementer + verify | brief + discriminating test + PR evidence bundle |
| **3** | a signal present: correctness-critical / high-blast-radius / public contract | full trio + **expect an external review round** | all of T2 + adversary cross-check + independent regression design + re-verify each round |

## Checkpoint gates (stop-the-line)

Re-evaluate the tier at **four fixed points**, and a bump is a *stop-the-line gate
with changed deliverables*, not just "add codex later":

1. **Issue scope** (Phase 1 start) — initial tier from the issue text.
2. **Touched-file discovery** (after reading the code) — the most important gate;
   a signal found here means the *test design* must be (re)done independently, or it
   may already be contaminated.
3. **Pre-commit** — last chance before the diff is frozen.
4. **Pre-PR** — confirm the deliverables for the final tier are all present.

## Rules

- **Escalate freely; do not de-escalate mid-run without human confirmation** —
  otherwise the flow games the tier down to skip ceremony.
- A late Tier-3 discovery after implementation is a **red flag**: assume the test
  may encode the same misunderstanding as the fix and have it independently
  re-designed (`guardrails.md` → independent regression design).
- When no panes are live, Tier 1–2 can run orchestrator-solo; a Tier-3 issue with no
  adversary/reviewer available should **wait or warn**, not proceed unguarded.
