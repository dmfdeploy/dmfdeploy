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

**Operator ruling, 2026-08-30 — Phase C is deferred to a decision point, not scheduled.**
The question is answered *after Phase B lands and is looked at in a browser*, judging whether
an empty history reads acceptably on camera. Until then Phase C is not started, and #496's
producer plus the D7 routing stay unscheduled. This is a deliberate deferral with a named
trigger, not an open question left drifting — see §5.1.

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

## 5. Operator rulings on this round's three questions

All three were put to the operator on **2026-08-30** and answered. They are recorded here
rather than left open, because each one silently changes what a later phase is allowed to
build.

### 5.1 Phase C — deferred to a named trigger, not scheduled

**Question:** does the demo need the bus's history path?

**Ruling: decide after Phase B lands.** Build the live path first, look at it in a browser,
and judge from the real render whether an unavailable history reads acceptably on camera.
Until that look happens, **Phase C is not started** and
[#496](https://github.com/dmfdeploy/dmfdeploy/issues/496)'s terminal-event producer plus the
ADR-0028 D7 routing stay unscheduled.

The trigger is what makes this a deferral rather than a drift: the decision point is *Phase B
rendered and inspected*, not "sometime later". D7 remains unmet either way — deferring the
decision does not close that gap, and #496 stays open as the place it is tracked.

### 5.2 The bell keeps reading workspace health this round

**Question:** the bell becomes an inbox with nothing to put in it — ship a defined empty
state, or leave it?

**Ruling: leave the bell reading workspace health.** Do **not** convert it to an inbox this
round. It keeps its current meaning until the alarm LED exists to take that job over.

The reasoning is the same one that governs the bus's own empty state (§4): the platform has
no approval-gated automation and no human-to-human messaging, so an inbox would ship empty
while *implying* a capability that does not exist. An empty state that has to explain why it
is empty is a worse answer than not making the claim yet. This also keeps the bell and the
LED from having to agree before the LED is even built.

### 5.3 Release timing — unchanged

Deferred until this round lands, **dmf-runbooks first** (tag → Forgejo mirror → AWX project
re-pin → 693), or the console ships with the throbber's step text permanently dark and only
the designed fallback ever visible. Already recorded in `STATUS.md`; restated here only
because §1 depends on it.
