---
status: draft
date: 2026-08-21
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/432
---
# DMF Console UI Round Plan (2026-08-21)

> **STATUS: DRAFT, parked on a branch.** Freeze-era design work does not open new
> issues (standing operator policy: no new design scope until a named outsider
> completes the demo). This plan exists so the design decisions taken on
> 2026-08-21 are recorded and reviewable; the **defect sweep** it sits beside
> (dmfdeploy#432) is not blocked by it and proceeds independently.
>
> Where this plan and the
> [Console UX Constitution](../design/DMF%20Console%20UX%20Constitution%202026-05-25.md)
> disagree, the Constitution wins.

## 1. Why

An operator-led live walk of the console on 2026-08-21 (dmf-cms v0.25.0, sandbox
env) produced twelve confirmed defects and one summary judgement from a lay
audience the operator had shown the console to:

> *"looks like a geek site, not a 'product'"*

The defects are filed as **dmfdeploy#432**. This plan covers the part that is
**design, not defect**: the surfaces and grammar the defects sit inside.

The structural diagnosis is worth stating plainly, because it explains why the
console reads as unfinished rather than as broken:

**Most of the "geekiness" is honesty gates discharged as prose.** The
Constitution requires the console never overclaim. The current implementation
satisfies that requirement by *printing paragraphs*. The loudest element on the
create screen is an amber warning that the draft may be lost. The brightest
element on the setup screen is Teardown. Two of three live tiles read
`NO PREVIEW`. Every wizard step carries the caption "The workload is here now"
next to a badge already reading "Now".

None of that is dishonest. All of it is heavy. The fix is not less honesty — it
is moving honesty out of paragraphs and into **state, colour, placement, and
progressive disclosure**. That mechanism is already specified and parked as
**#244** (disclosure Level axis, default ↔ expert). #244 is the structural answer
to the operator's judgement, and this plan is the tactical one.

## 2. Scope

**In:** lifecycle-rail visual grammar (with #405 folded in), entry surfaces
(empty state, header-slot consistency), the copy doctrine, and the shape of a
persistent operation-status affordance (#390).

**Out:** the #432 defect sweep (proceeds independently); console actions in
Recent changes (#419/#421); the full #244 disclosure axis; mobile Finalise
reachability (parked by operator decision 2026-08-21, not reproduced in the
walk); anything requiring a new ADR.

**Method constraint — iterate, not rewrite.** Verified by inspection, not
assumed: the rail's state model already lives *outside* the component
(`lib/workloadLifecycle.ts`, `lib/workloadFlow.ts`, `lib/stagePalette.ts`),
`LifecycleStrip.tsx` contains exactly one inline style and one state literal, and
six test suites pin its behaviour — including `railRouteContract.test.tsx`. We
therefore **keep all state derivation and the route contract, and change only how
each key is painted.** The single genuine replacement is the layout primitive
(label-driven widths → equal columns), contained to the render.

## 3. The rail

### 3.1 What is wrong now

Measured live at v0.25.0:

| property | measured |
|---|---|
| icons | **zero** on every key |
| key widths | 47px (Plan) → 123px (Finalise & Review) — a **2.63x spread** |
| selected key | `rgb(232,232,234)` near-white on near-black |
| on the workload home | **no key is selected** — five identical grey chips |

Two consequences. Because widths are label-driven, keys *move* as state changes
the labels. And on the workload home — which #414 made the workload's home — the
rail communicates **nothing at all**: five equally dead chips, no position, no
progress.

The brightest element on the setup page is the Teardown step, because Finalise &
Review is both the widest key and the selected one.

### 3.2 State grammar

The operator's proposal (2026-08-21) and the reasoning behind it are adopted,
with one refinement.

**The catch that changed the design:** the candidate icon set uses a **circled
check for Finalise**. A tick as the "complete" mark would put *two ticks* on the
Finalise key whenever it is complete. The tick is therefore unavailable as a
state mark, and the operator identified this before the icon set was built.

**Refinement — the dot is a completeness meter, not a selection marker.**
The operator proposed filled-dot for complete and unfilled-dot for current. But
selection is already carried by the key's own fill, so marking it again with a
dot is the redundancy the operator asked to avoid. Splitting the two jobs also
makes the future case work without new glyphs:

| carrier | meaning |
|---|---|
| key fill / emphasis | **you are viewing this key** (unchanged from today) |
| filled dot | stage **complete** |
| outline dot | stage **partially satisfied** — started, or invalidated by an upstream change |
| no dot | stage **not started** |
| padlock | stage **locked** — cannot be entered |

Four states, two glyphs, one fill variation, one absence. No animation, no busy
stripe, no position-vs-selection tally.

**This handles the operator's future scenario with no new marks.** If a user
revises the Design, Plan is no longer fully satisfied → Plan's dot goes filled →
outline. Provision, holding pending planned items, likewise goes filled →
outline. Completeness becomes a per-stage quantity that can *regress*, and the
grammar already expresses it.

**Why keep the padlock at all.** "Locked" and "not started" are different facts
and must not collapse into the same absence. Dimming alone would conflate them.

**Colour-independence (Constitution Art. 11).** Every distinction above is
shape, fill, or absence — never hue. The grammar survives greyscale and colour
blindness. This is the reason a mark exists at all rather than colour alone, and
it is the constraint that must not be traded away for a cleaner look.

### 3.3 Build constraints

- **Equal columns.** Five `1fr` columns so keys never move. The shared column
  width is set by "Finalise & Review", which is never abbreviated.
- **Verify mark legibility at rendered size.** Filled-vs-outline at ~7px is a
  fine distinction. The mark size must be chosen against a real render, not a
  mockup — and confirmed in greyscale.
- **Forward-compatible prop shape.** The component must accept a *per-stage
  completeness* value rather than deriving completeness from `index < current`.
  The regression semantics in §3.2 is a **backend lifecycle-derivation change**
  (`_derive_workload_lifecycle`, governed by ADR-0046) and is **not** in this
  round. Taking the prop shape now means enabling it later costs no repaint.
- **#405 folds in cleanly.** "Locked-but-reachable steps" is state-model work;
  the repaint is presentation work. Different layers, guarded at the seam by
  `railRouteContract.test.tsx`.
- **The rail must say something on the workload home.** Today it says nothing
  there. At minimum it must show completeness, even when no key is selected.

## 4. Entry surfaces

### 4.1 Media Workloads empty state

The create button is already the most prominent control in the product (195x40,
sky fill on near-black). Lay users still missed it. The measurement says the
label is not the cause: the button sits top-right while the eye lands centre,
where the copy reads *"No Media Function instances in your scope."* — a dead
sentence, in the wrong vocabulary (Workload and Function are distinct under
ADR-0046), offering nothing to do.

**Both, not either** (operator decision 2026-08-21): a centred call to action in
the empty state **and** the existing header-slot button retained, so the control
does not move as the list fills.

The empty state carries: what a media workload *is*, in one plain line; a large
primary action; page-matching vocabulary.

### 4.2 Facilities header slot

Facilities has no header control, so the page reads as a different product from
Media Workloads. **Operator decision (2026-08-21): add a visually consistent
placeholder in the same slot.**

This was argued against and the operator reaffirmed it, so it proceeds. The
recorded concern, and the constraint that resolves it:

This codebase **never renders a locked control as `disabled`** — it substitutes
inert text naming the reason (`FlowStep.tsx:153-165`,
`ViewLiveExit.tsx:63-68`). A permanently-dead button would be the only one in the
product. And facilities are not "not yet" — they are created by environment
bootstrap, deliberately not by the console.

**Therefore the placeholder must explain rather than do nothing.** It occupies
the same slot with the same visual footprint, and on interaction it says where
facilities come from. Consistency of layout without a dead control or a false
promise.

## 5. Copy doctrine

Two registers, split by whether anything is at stake. The split is the whole
doctrine — without it, "playful" collides with the Alarm Philosophy and the
honesty gates.

### 5.1 Sober register — wherever state is asserted

Alarms, degraded reads, destructive confirmations, provenance and freshness.
Precise, plain, never softened, never cute.

**The application states what it is doing. It does not instruct the operator.**

Current copy fails this at three sites — `WorkloadMaterializing.tsx:252`,
`LifecycleStrip.tsx:353`, `WorkloadSetup.tsx:638` — all rendering
*"… — wait for its outcome."* The string is additionally pinned by four test
assertions, so it was a considered choice and changing it is a real decision that
must update the tests in the same change.

The replacement must still carry *why a control is unavailable* (the
no-dead-controls rule depends on it), but as a fact rather than an order:
"Provision job running" rather than "wait for its outcome".

**Candidate wording (operator, 2026-08-21):**

> "The outcome is observable in the Recent changes log."

This is the doctrine working correctly: it states where the answer will appear
instead of instructing the operator to wait. It also does something the current
sentence does not — it tells someone who *does* navigate away where to look,
which is the actual question behind §6.

**Dependency, and it is a real one:** Recent changes cannot currently answer that
question. Its rows are labelled by AWX job template rather than by workload, they
report a past-tense verb beside a "Running" badge, and they are not interactive
(#432 §F). Pointing operators at that surface before those are fixed would direct
them somewhere that cannot tell them which workload they are looking at. **This
copy change must land with or after the #432 §F labelling fix, not before it.**

### 5.2 Inviting register — wherever nothing is at stake

Empty states, first run, and invitations to explore. Warm, and allowed to be
playful. The console should **invite the operator in**, not present a wall to be
decoded.

This register never touches an alarm, a degraded read, or a destructive
confirmation.

### 5.3 Standing rules

- No boilerplate that restates an adjacent control ("The workload is here now"
  beside a "Now" badge).
- Never render the same sentence twice on one screen.
- Use the page's own vocabulary — Workload where the page says Workload.
- Preserve what the operator typed; do not title-case a display name back out of
  its slug.
- No raw internal identifiers at default disclosure level (`op cdd887cb…`,
  `node —`). This is the seam with #244.

## 6. Persistent operation status (#390)

The walk confirmed that in-flight operations lose their surface entirely on
navigation, for both Provision and Teardown. The operator's proposed shape:

> `[Specific Media Workload]: Finalise & Review · running`

Adopted as the target shape. It also fixes the Recent-changes labelling defect in
#432 §F, because it forces the *workload* to be the subject rather than the AWX
job template.

Constraints:

- **It complements the in-place outcome; it never replaces it.** Hard gate #2
  requires every operator action to close its loop *at the point of action*. A
  global chip that became the only place an outcome appeared would violate it.
- **It must be addressable** — clicking it returns to the operation. Returning to
  `/setup` is not the answer: that route is derived from lifecycle state per
  ADR-0046 and legitimately lands on Finalise once provisioning completes.
- **Not the notification bell.** The bell is alert-scoped ("Monitoring alerts /
  All systems nominal") and is a different concern. Its dismissal behaviour is
  the pattern to copy, not its content.

## 7. Sequencing

**Ahead of everything, on its own PR** — the `settleQuery` conversion in
`WorkloadHome.tsx` (#432 §A). It fixes the amber flicker, the preview restart,
and the withheld live view together; it removes a **hard-gate-#5 violation**; and
it closes an unconverted site of the #343 sweep. It depends on nothing in this
plan.

Then, in order: the #432 defect sweep (independent of this plan) → rail repaint
with #405 → entry surfaces → copy doctrine applied → #390.

## 8. Open questions

1. **Mark size.** Filled-vs-outline dot legibility at rail scale is unverified;
   it must be settled against a real render in greyscale, not a mockup.
2. **Completeness regression** (§3.2) needs a backend derivation change under
   ADR-0046. Out of scope here; the prop shape must not foreclose it.
3. **#244 sequencing.** This plan treats disclosure as the structural answer to
   the operator's judgement, but #244 sits behind the freeze. Whether the demo
   can be reached without it is unresolved.
4. **Recorded, unfiled from the transcript review:** MXL-specific naming leaks
   across the dmf-cms driver/policy contract boundary (accepted as valid, no fix
   landed), and the design-record supersession sweep left one active plan doc
   unswept.
