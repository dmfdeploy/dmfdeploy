---
title: DMF Console Shell Round 2 — Rail Band and Message Bus
date: 2026-08-31
status: draft
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/480
---

# Console Shell Round 2 — the rail band and the message bus

Round 1 (`DMF Console Shell Round Plan 2026-08-30.md`, merged) **decided** the shell's
shape and **built none of it** except the throbber. This round builds it.

**Read round 1's plan first.** This document deliberately does not restate its rulings —
the three-surface model, the LED's four states, the rail visual system, the audit contract.
A second copy is a second thing to drift.

---

## 1. Where round 1 actually left things

**Built and merged:** the live throbber (dmf-cms#125), the ghost grid (#126), status
legibility (#127), milestone markers (dmf-runbooks#46), and the design record (#500).

**Decided but not built — this round's work:**

| Issue | What |
|---|---|
| [#481](https://github.com/dmfdeploy/dmfdeploy/issues/481) | Rail moves to its own band, horizontally centred, **no indicators in the band** |
| [#482](https://github.com/dmfdeploy/dmfdeploy/issues/482) | Per-key icons — pencil / puzzle / cloud-upload / sliders / circled-check |
| [#483](https://github.com/dmfdeploy/dmfdeploy/issues/483) | Directional chevron form, nested with a thin gap, flat terminals |
| [#480](https://github.com/dmfdeploy/dmfdeploy/issues/480) | The message bus |
| [#496](https://github.com/dmfdeploy/dmfdeploy/issues/496) | The audit producer the bus projects — **prerequisite for the bus's history path** |

**Unreleased:** dmf-cms `main` is 10 commits past `v0.30.0`; dmf-runbooks 2 past `v0.4.7`.
Release is deliberately deferred until this round lands (see `STATUS.md`). **dmf-runbooks
must be released before dmf-cms** or the throbber's step text stays dark.

---

## 2. The dependency that decides sequencing

**The rail band trio is buildable today. The bus is not.**

`#480` says the bus projects a durable record. `#496` establishes that record **does not
exist**: the console's audit stream records *dispatch* (`launched` / `dispatched`), never
the terminal outcome, and nothing routes `dmf_cms.audit` into a retained stream, so
ADR-0028 D7 is unmet.

But round 1 recorded a split worth exploiting: **the bus's LIVE path may not need any of
that.** An in-memory ring buffer over `OperationStore` — which *does* hold terminal state —
can serve the current stream. It is the **history** path that needs the durable record.

So:

- **Phase A — rail band (#481, #482, #483).** No backend. No dependencies. Start here.
- **Phase B — bus live path (#480, partial).** Ring buffer over `OperationStore`, the bar
  itself, the LED reading `classifyWorkspaceHealth`. History renders "unavailable", not
  "nothing happened".
- **Phase C — the record (#496), then the bus's history path.** Terminal audit-event
  producer, `clear-for-deployment` onto the helper, structured CloudEvents JSON, Promtail
  routing plus its acceptance check.

**Do not start Phase C without deciding whether the demo needs it.** It is compliance work
with a real cost, and Phase B may be enough for the recording.

---

## 3. The subtraction that must not be forgotten

[#499](https://github.com/dmfdeploy/dmfdeploy/issues/499) is **open and only one-third
done**. One running job is still announced four times on one screen. #127 replaced one of
them with the throbber. The other two leave with **this round**:

- `#481` must end with **zero status text in the lifecycle band** — that removes the
  rail-adjacent "A … job is in progress." *and* relocates the "N OF N RUNNING" readout.
- `#480` must end with **exactly two on-screen statements** per running job — the bus and
  the acting stage's throbber — with wording from **one derivation**, not parallel strings.

Both are already recorded as acceptance criteria on those issues. **Adding the bus without
removing the old announcements lands at six, not two.** This is the single most likely
thing to be skipped, because every individual line looks defensible on its own.

---

## 4. Hard constraints carried forward

From round 1's design docs and the UX Constitution. Each has already cost a review round
somewhere:

- **The rail band carries no indicators.** That is what structurally fixes the centring —
  the group cannot centre while fighting a right-pinned sibling.
- **No padlock.** Reserved for authorization denial, a state that does not exist yet.
  Five identity icons only.
- **Muted per-stage identity hues, avoiding red and amber** — those are reserved for the
  alarm LED. Hue carries identity, luminance carries selection, the icon carries the
  stage, the badge carries count. Everything except hue survives greyscale.
- **Badge-ready, no counts.** Counts need the ADR-0046 divergence derivation
  ([#495](https://github.com/dmfdeploy/dmfdeploy/issues/495)) which does not exist.
- **The chevron notch must be MEASURED**, not derived from the 141.4px figure — that number
  is *reported in #481*, unverified in the tree, with no zoom recorded. Take a fresh
  measurement on a real render and record viewport **and** zoom.
- **`clip-path` clips the focus ring.** Use a wrapper element carrying the ring;
  `drop-shadow` follows the silhouette but dies under Windows forced-colors.
- **The LED reads Prometheus** (`classifyWorkspaceHealth` / `watchdog_firing`), never the
  ops store's `DIRTY_STATES`. Reuse the existing classifier — the bell and the LED must not
  be able to disagree.
- **The bus is not the Watchdog.** Watchdog proves *monitoring* is alive. A dead producer
  leaves the LED nominal and the bus silently empty, so the bus must never render emptiness
  as "nothing happened" unqualified ([#497](https://github.com/dmfdeploy/dmfdeploy/issues/497)).

---

> **How this round is run** — agent roles, dispatch discipline, verification
> practice, review and merge mechanics — is session-continuity material and is
> deliberately **not** in this repo. It lives in the operator-local handoff.

## 5. Open questions for the operator

Do **not** guess these:

1. **Does the demo need the bus's history path (Phase C)?** If the live stream is enough,
   #496's producer and the D7 routing can be scheduled separately from the demo.
2. **When the bell becomes the inbox, it ships empty** — the platform has no approval-gated
   automation and no human-to-human messaging. Confirm that a defined empty state is
   acceptable, or defer the bell entirely and leave it reading workspace health until the
   LED exists.
3. **Release timing.** Currently deferred until this round lands. dmf-runbooks first.
