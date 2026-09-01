# DMF Console — Lifecycle Rail Visual System

**Status:** **Design spec** (2026-08-30; amended 2026-09-01).
**The rail and the vertical nav now share one token set — see §2d**, which supersedes the
achromatic-invert selection this doc originally specified and the two-tone focus stroke in
§5.4. They share *colours*, not treatments: the rail keeps a hover edge the nav tile does not
have, and §2d splits the two explicitly. Tracking issue
[dmfdeploy/dmfdeploy#512](https://github.com/dmfdeploy/dmfdeploy/issues/512).
Everything not marked as amended still stands.
**Governs three companion issues — land here from any of them:**
[dmfdeploy/dmfdeploy#481](https://github.com/dmfdeploy/dmfdeploy/issues/481)
(own band, horizontally centred, no indicators in the band),
[dmfdeploy/dmfdeploy#482](https://github.com/dmfdeploy/dmfdeploy/issues/482)
(per-key icons), and
[dmfdeploy/dmfdeploy#483](https://github.com/dmfdeploy/dmfdeploy/issues/483)
(directional chevron form). If you arrived here from any one of the three,
this whole doc applies — the three issues are one visual system, not three
independent ones.
**Applies to:** the **lifecycle rail** within a Media Workload's detail view
(`LifecycleStrip.tsx`) — Design / Plan / Provision / Configure / Finalise &
Review. This is **not** the primary console navigation rail described in the
[Information Architecture](DMF%20Console%20Information%20Architecture%202026-06-23.md)
doc (Workspace / Facilities / Media Workloads / Catalog) — the two documents
use "rail" for genuinely different things; don't cross-apply one's rulings to
the other's surface.
**Reads with:** [UX Constitution](DMF%20Console%20UX%20Constitution%202026-05-25.md)
(Art. 11 colour-independence; §5's ISA-101 discipline) · the IA doc's
2026-08-30 (#493) amendment (the stage model this system paints — see §1) ·
[DMF Console Shell Round Plan 2026-08-30](../plans/DMF%20Console%20Shell%20Round%20Plan%202026-08-30.md)
(the layout seam — the rail moves into its own band below the top bar).

---

## 0. Why this doc exists

dmf-cms 0.30.0 shipped the rail's state grammar (equal columns, per-stage
marks) but landed with **zero icons on any key** and **not centred** in its
row — both named defects, split into #481 (band/centring), #482 (icons), and
#483 (directional shape). The three are one visual system competing for the
same small key, so specifying them separately risks three uncoordinated
repaints. This doc specifies them together.

**Status, updated 2026-09-01 — two implementations, and they are not the same one.** Read the
provenance carefully before following any value in here:

- **[dmf-cms#128](https://github.com/dmfdeploy/dmf-cms/pull/128) — merged 2026-08-31, shipped
  in 0.31.0.** All three companion issues above. This is the baseline: shape, icon set, hue
  removal, band. Anything in §§2–5 *not* marked as amended describes it, and it is running in
  production.
- **[dmf-cms#131](https://github.com/dmfdeploy/dmf-cms/pull/131) — open at the time of
  writing.** The rail/nav parity amendment ([dmfdeploy/dmfdeploy#512](https://github.com/dmfdeploy/dmfdeploy/issues/512)):
  40px geometry, shared opaque selected face, shared resting ink, hover, focus-ring rebuild.
  Everything marked **amended 2026-09-01** is this, and it is **not yet shipped**.

Where the two disagree the amendment wins as *design*, and #128 wins as *what is live* until
#131 merges. §5.1 in particular now carries #131's 40px values under a section whose
measurements originally came from #128 — the retired column is kept alongside precisely so
that distinction stays visible rather than being flattened.

Sections 2–5 are written as a **record of what was built and why**, rather than as forward
specification, because the design changed materially while being built — three times during
#128, and again during #131, each on evidence:

1. **Colour was removed from the rail entirely** (§4). It was specified as a per-stage
   identity channel, tried as a fill and then as an edge line, and measured out at
   ΔE2000 **0.85** under protanopia — below the threshold at which a difference is
   visible at all.
2. **The position marker was removed** (§2). The backend derivation could only ever name
   two of the five keys, and it was announced as a step in a sequence the model does not
   have.
3. **Two of the five icons were wrong** (§3) — this document had recorded a
   reconstruction rather than the decision.

Each of those was found by **rendering the thing and looking at it**, not by the test
suite, which stayed green throughout. That is recorded here because it is the most
transferable thing this round produced.

---

## 1. The model this system paints (cross-reference, not redefinition)

A lifecycle stage is a **peer view of the workload, not a step in a gated
sequence** — full ruling in the Information Architecture doc's **2026-08-30
(#493) amendment**. This visual system paints that model; it does not
redefine it. Two consequences that shape the channels below:

- "Locked" is a **status**, not a refusal — every key stays reachable.
- The per-key mark is **actionable-item count**, not completeness (§2's Badge
  channel), because completeness is not a coherent property of an
  independent peer stage.

---

## 2. Four channels, three facts

**Amended 2026-08-31.** This table replaces an earlier version that gave *stage identity*
to hue. Hue has been **removed from the rail entirely** — see §4 for the measurements that
killed it and §2c for the reasoning.

**Four channels carrying three facts.** Icon and label both carry stage identity — that
redundancy is deliberate and is what makes the rail colour-independent by construction.
The three facts are **identity**, **selection**, and **actionable count**:

| Channel | Carries |
|---|---|
| **Icon** (filled, per stage) | stage identity — the primary carrier. See §3 for the set. |
| **Label** (bare EBU stage name) | stage identity — always visible, never abbreviated. |
| **Luminance / fill** (opaque selected face, shared with the nav) | selection ("am I looking at this one") — **see §2c**, amended 2026-09-01 |
| **Badge** | count of actionable items. **Absence of badge = nothing actionable — but only once the channel is live; see §2b.** |

**There is no colour channel on this rail.** No key's appearance depends on *which* stage it
is — all five take the same face, ink and edge in the same state (§2d, amended 2026-09-01;
before that there was one fill full stop, because there was effectively one state). Identity
is carried by icon and label, both of which survive greyscale unchanged, so
**Art. 11 holds by construction rather than by verification** — there is no per-stage hue left
to strip, and the one hue that does appear (the shared selected face) carries state, not
identity, and carries it in luminance too.

**The rail carries no position marker.** Selection is the only state it shows. Removed
2026-08-31 (operator ruling) — the backend derivation could only ever name two of the
five keys, and it was announced as `aria-current="step"` in a model where a stage is a
peer view and explicitly *not* a step in a gated sequence (§1). What "how far along is
this workload" should mean is the Badge's job, once #495 makes it real.

**Rejected, and kept as record:**

- Folding stage-state into fill/edge alongside selection (an earlier #481 proposal) —
  six treatments that must all survive greyscale.
- **Hue as stage identity, in any form** — as a key fill, then as a 3px bottom-edge line.
  §4 has the measurements.
- **A dedicated selection ring.** Once every key shares one resting fill, selection measures
  uniformly across all five keys — identical by construction — so a ring adds nothing. It was
  necessary only while hue made the fill-invert unreliable. *(The mechanism became an opaque
  shared face rather than an achromatic invert on 2026-09-01; the reason a ring is
  unnecessary is unchanged, since it rests on the resting fill being uniform, not on which
  fill it is. A hover-only ring did arrive in §2d — that is a different signal, for a
  different state, and selection still needs none.)*

### 2c. Why hue left the rail, and why selection needs no ring

**Amended 2026-08-31.** This section previously ruled that selection required its own
inset ring. That ruling is **superseded** — but the analysis behind it is kept, because it
is what eventually removed hue, and a future round proposing per-stage colour needs to be
able to read why it failed rather than rediscover it.

#### The finding: fill luminance cannot carry identity and selection at once

While hue was still the key fill, selection painted an achromatic near-white,
`rgb(232,232,234)`. How much a key visibly changed on selection therefore depended entirely
on where its identity hue sat in luminance:

| stage | identity fill | contrast when selected | ink on selection |
|---|---|---|---|
| Design | `rgb(52,106,92)` | 5.10:1 | light → dark, flips |
| Plan | `rgb(74,97,150)` | 4.99:1 | light → dark, flips |
| Provision | `rgb(146,129,187)` | 2.82:1 | dark → dark, no change |
| Configure | `rgb(190,151,196)` | 2.04:1 | dark → dark, no change |
| **Finalise & Review** | `rgb(215,183,200)` | **1.49:1** | `rgb(15,23,32)` → `rgb(10,10,11)`, no change |

On the three lightest keys selection sat at or under the WCAG 1.4.11 3:1 floor for a
UI-state change; on Finalise & Review it was imperceptible, and the ink did not flip either
because light hues already carry dark ink. `aria-pressed` was correct throughout, so
assistive technology was unaffected and the full suite passed. A sighted operator simply
could not tell which key was selected.

**It hid because the two checks that existed both passed for the worst key.** Finalise &
Review had the *best* numbers in the ramp on fill-vs-background (10.83:1) and ink-vs-fill
(9.88:1). The missing check was fill-vs-**selected**-fill — and those constraints pull in
opposite directions, because the further a hue sits from a dark page background the closer
it sits to a light selection fill.

**No retune could fix it.** Solving all the colour constraints at once left two disjoint
usable bands — roughly L\* 39.4–42.9 for dark-ink swatches and L\* 53.2–55.7 for light-ink
ones, about **6 L\* units** in total. That is capacity for **two** distinct swatches; the
rail needs **five**. Nor did a different selection tone escape it: clearing 3:1 from both
ends of the ramp would require a luminance above 1.0, or one indistinguishable from the
page background.

#### Why the ring is gone too

The ring existed to give selection a carrier independent of the hue ramp. **Once hue left
the rail (§4), the problem it solved ceased to exist.** No key's fill depends on which stage
it is — every key takes the same face in the same state (§2d) — so selection measures
**uniformly on every key**, identical by construction rather than by tuning. A ring on top of
that would be a second signal for a fact already unambiguously carried, which is the
redundancy this rail has spent two rounds removing.

> **Amended 2026-09-01 (dmfdeploy/dmfdeploy#512).** This paragraph said "all five keys share
> one neutral fill" and quoted 5.06:1, for an achromatic invert to `--color-text`. Both are
> retired: §2d specifies **three state-dependent faces**, and the current selected-vs-resting
> figure is **3.57:1**. The *argument* survives intact, because what it actually turns on is
> the face being uniform **across keys within a state** — which is still true, and is the
> only property the "no ring needed" conclusion ever needed.

**Recorded because it nearly shipped:** a draft of this section specified "a persistent ring
in a fixed neutral tone" facing both the key fill and the page background. No such tone
exists. For a ring of relative luminance `L`, the page background and selected fill admit
`[0.1092, 0.2360]`, while the Design fill demands `L ≥ 0.4543` or `L ≤ 0.0060` — no overlap.
That draft would have reproduced, one level out, the very defect it was written to fix. The
lesson generalises: **a single element asked to contrast against things that pull in
opposite directions is the same trap every time.**

#### What survives from that analysis

The **focus ring** is still outset, so it genuinely does face the page background and the
neighbouring key. With no per-stage hue the argument is simpler than it was: there are two
faces to clear, not five hues — and the current ring clears both (11.39:1 resting, 3.19:1
selected) plus the band at 15.53:1. §4.4's criteria are what make it hold. *(The two-tone stroke
this paragraph used to describe is retired and was never producing two visible tones — see
§5.4, amended 2026-09-01.)*

### 2d. The rail and the vertical nav share one token set (amendment, 2026-09-01)

**Tracking issue: [dmfdeploy/dmfdeploy#512](https://github.com/dmfdeploy/dmfdeploy/issues/512).
Implementation PR: [dmf-cms#131](https://github.com/dmfdeploy/dmf-cms/pull/131) — open at the
time of writing, not yet merged.**

Found by the operator reviewing the shipped rail against a real provision run: the rail
worked, and did not look like it belonged to the same application as the nav beside it. Key
height, icon size, selection treatment and ground all differed. This section records what
replaced the achromatic invert and why the obvious fix was not available.

**What is shared is the token set, not the whole treatment.** Both components take their
colours from the same literals, so selection can never drift apart again — but the two
surfaces are different shapes and do not paint identically. Stating this precisely matters:
an earlier draft of this section presented one table for both, which would have directed a
future nav round to give its tiles a hover ring they do not have.

**Shared tokens — identical values in both components, and the point of the round:**

| token | value | role |
|---|---|---|
| `--color-selected-face` | `#58879e` | the selected face, in both. ΔE2000 between them is **0.00** by construction. |
| `--color-resting-ink` | `#b4b4b8` | the resting ink, in both |
| `--color-bg` | `#0a0a0b` | the selected ink, in both |
| `--color-text` | `#e8e8ea` | the hover ink, in both |

**Per-component treatment — deliberately different, because the surfaces are:**

| | rail key | nav tile |
|---|---|---|
| resting face | `--color-rail-fill` `#2c2c2e` | **none** — the `--color-sidebar` ground shows through |
| hover face | `--color-rail-fill` (unchanged) | **none** — unchanged |
| selected face | `--color-selected-face` | `--color-selected-face` |
| hover edge | **2px `--color-selected-face`**, following the clipped chevron | **none** — the tile has no edge in any state |
| shape | `clip-path` chevron, so the fill is its own silhouette | `rounded-lg` tile |

The rail has an edge because a clipped chevron has a silhouette worth drawing and a resting
face distinct from the band behind it. The nav tile has neither — it is transparent at rest,
so there is nothing for a ring to enclose, and its hover is carried entirely by the ink
(`--color-resting-ink` → `--color-text`). **A future nav round should not add one to match.**

`--color-rail-edge` is **retired**. The band's ground moved from `--color-bg` to
`--color-sidebar`, which is what merges it with the nav.

**Hover on the rail is new** — it had none. The hover edge is deliberately the *selected*
colour: hovering previews what selecting would look like, which is a reason that stands on
its own rather than a way of avoiding some other colour.

> **A draft of this paragraph added "and the accent stays reserved for focus". That was
> wrong and is removed.** It came from my believing the rail's focus ring was accent-coloured;
> it never was — it was `outline-current`, and after §5.4 it is `outline-text`. Accent does
> still carry focus in the **nav** (`focus-visible:outline-accent` on the tile), so the claim
> is true there and false here, which is exactly the kind of half-true rule that survives
> review.
>
> **The actual hover/focus differentiation on the rail** is colour *and* position, neither
> involving accent:
>
> | | colour | where |
> |---|---|---|
> | hover | `--color-selected-face` | on the shape, following the chevron silhouette |
> | focus | `--color-text` | outside the box, in the inter-key gap |
>
> Both were checked together on a render with a real pointer and a real Tab, including the
> both-at-once case — a hovered-but-unfocused key never reads as focused.

#### Why not simply copy the nav's tint

Copying `bg-accent/20 text-accent` would have imported a defect. The nav's selected tile
measures **1.52:1** against its own resting state — under 1.4.11's 3:1 floor, and the same
shape of defect §2c documents: correct in the accessibility tree, invisible on screen.

> **The figure here was 1.49:1 in an earlier draft, and that was wrong.** It came from
> arithmetic against `--color-bg`; the nav tile composites over `--color-sidebar`, which is
> the lighter of the two. **1.52:1 is the render-measured value against the real backdrop**
> and is the one used throughout this section. Measuring against the page background instead
> of the actual parent is the same mistake that produced two other stale figures in this
> round — worth naming, because it is easy to make and each instance looks individually
> plausible.
>
> Note that **1.49:1 also appears in §2c's table, for something else entirely** — the
> Finalise & Review key's own selection contrast under the retired hue ramp. That collision
> is coincidence. Do not reconcile the two; they measure different things.

Raising the alpha fixed the state change and broke a check nobody had run. At 55% the rail's
label measured **2.34:1** against its own tint, against 1.4.3's 4.5:1 floor. That is
structural, not a tuning miss. With the darker resting face, a *lighter* selected face must
satisfy two clauses at once:

```
state change >= 3:1     =>  Y_selected >= 0.176
white-ish text >= 4.5:1 =>  Y_selected <= 0.141
```

Empty interval — the same shape of result as §2c's disjoint-bands finding, and the second
time this rail has produced one. Going darker is worse: the resting face is already so dark
that no darker selected face clears 3:1 against it at all. **Inverting the ink rather than
chasing the face is what resolves it.**

An alpha tint also composites differently over each surface's substrate — the rail's over the
key face, the nav's over the sidebar ground — leaving the two **ΔE2000 4.63** apart while
sitting adjacent. One opaque literal in both places makes it **0.00** by construction. That is
the actual reason the face is opaque; the contrast is a constraint, the shared literal is the
point.

#### Measured, on a real render

```
rail label vs selected face .......  5.06   (1.4.3,  floor 4.5)
sidebar icon vs selected face .....  5.06   (1.4.11, floor 3.0)
rail selected vs resting face .....  3.57   (1.4.11, floor 3.0)
sidebar selected vs its ground ....  4.86   (1.4.11, floor 3.0)
rail resting label ................  6.74   (1.4.3,  floor 4.5)
sidebar resting icon ..............  9.20   (1.4.11, floor 3.0)
hover edge vs band ................  4.86
focus ring, all four combinations . 15.53
CIEDE2000, rail face vs nav face ..  0.00
```

The rail is also substantially calmer than the version that prompted the report: selected face
L\* **92 → 54**, resting face L\* **41 → 18**.

#### The resting keys ship with no visible outline, deliberately

Resting silhouette is **1.36:1** against the band. That is conformant because 1.4.11 governs
the visual information *required to identify* the control, and these keys carry visible text
labels at 6.74:1 — **not** because 1.36 clears anything. Stated here and in the source so a
later reader does not read a missing outline as an oversight and restore one.

#### A trade taken, not discovered — and it is **not** repaid in the nav

Raising the nav's resting ink from `--color-muted` to `--color-resting-ink` cost its hover
delta, **2.28 → 1.69**. Hover there was carried entirely by the ink brightening, and a lighter
resting ink leaves less room above it to brighten into. That is the price of sharing the
resting ink with the rail, and it was accepted deliberately.

**A background cannot substitute for it.** Opaque `--color-panel` measures **1.03:1** against
`--color-sidebar`, so no alpha of it does anything at all — which is why `hover:bg-panel/50`
was removed rather than left as decoration that measures nothing, and why "just strengthen the
hover background" is not an available fix.

**The two surfaces end up in opposite places, and an earlier draft of this paragraph got that
wrong** by saying the new hover edge repays the loss. It does not — the nav has no edge (§2d):

| | before | after | carriers |
|---|---|---|---|
| **nav tile** | 2.28 | **1.69** | ink only — the loss stands, unrepaid |
| **rail key** | *no hover at all* | 1.69 ink **+** a 2px edge | two, where it previously had none |

So the rail gained a hover state it never had, and the nav's got softer. Hover is not a
WCAG-governed state, so a softer nav hover is a legitimate trade rather than a conformance
problem — but it is a real regression on that surface and is recorded as one, not as
something the edge quietly made up for elsewhere.

#### Corrections to earlier figures in this document

- The **2.76:1** figure quoted during this round for the shipped nav icon was wrong. It
  described a mid-build 55%-alpha variant that never shipped. The shipped icon measures
  **7.50:1** and was never a defect. The real shipped weakness is narrower: a 1.52:1 tile lift
  and a 1.68:1 icon luminance change — a state change carried mostly by hue.
- Alpha figures derived by naive sRGB interpolation run **~0.04 optimistic**, because
  Tailwind v4 composites in OKLab. Moot for what shipped, since the selected face is opaque.

### 2b. Badge-absence carries no meaning until the channel is live

**Amendment, 2026-08-30.** §2's "absence of badge = nothing actionable" and §5's
"badge-ready, no counts this round" contradict each other when composed, and the
contradiction is not visible from either one alone.

This round renders **no badge on any key, under any state**. If absence already
meant "nothing actionable", the rail would assert *"nothing actionable anywhere"*
on every key of every workload — including one mid-provision, where the claim is
false. That is precisely the failure Art. 1 forbids elsewhere on this same
component, which prints `Count unavailable` rather than a stale or guessed number:
**do not state a fact the console cannot verify.**

So, explicitly:

- **Until the badge channel renders real counts**, the slot is **reserved geometry
  and nothing else**. It carries no meaning, and absence of a badge says nothing —
  neither "nothing actionable" nor anything else.
- **Once counts land** (the ADR-0046 derivation,
  [#495](https://github.com/dmfdeploy/dmfdeploy/issues/495)), §2's reading takes
  effect and absence becomes meaningful.

**This section governs the badge channel's semantics only.** The slot itself — reserved
geometry, fixed width budget, and the `aria-hidden` treatment that keeps an empty
decorative box out of the accessibility tree — **is built by the implementing PR** (§5.5).
What §2b settles is
what that finished slot **means** while it is empty: nothing. A future reader therefore
cannot derive a false claim from §2's table, and whoever implements #495 knows that
switching the channel on is also what switches its absence semantics on.

**Consequence worth stating plainly:** between this round and #495, the rail has
*no* progress or actionable-work signal at all — the completeness dot is retired
(§1: completeness is not a coherent property of an independent peer stage) and the
badge is not yet live. The workload home, where no key is selected, is the state
that loses the most. That is an accepted, temporary gap, not an oversight.

### 2a. The padlock — no padlock this round (operator ruling, 2026-08-30)

**The rail ships the five identity icons only — §3 is the authoritative set.** Every
key, including one with nothing actionable, renders its own stage-identity icon. No key
is ever iconless, and nothing on the rail substitutes a padlock, or any other glyph, for
a key's identity icon.

*(This section previously listed the glyphs inline and went stale when §3 was corrected.
It deliberately no longer names them: one authoritative list, in §3.)*

**"Nothing actionable here, because X" is conveyed in words, on the stage
page itself** — per the IA doc's 2026-08-30 (#493) amendment's own ruling
that "locked" is a status, not a gate — **never as a lock glyph on the rail.**
The rail's icon channel carries stage identity only; it never carries stage
state, so it has nothing to say about whether a stage currently has anything
actionable.

This resolves cleanly what an earlier draft of this doc flagged as a
knock-on: the padlock used to be **the only `<svg>` in the rail**, with every
non-locked key rendering no icon at all. After this round every key carries
its identity icon regardless of state, so there is no iconless-key gap left
to close — §3 covers all five keys unconditionally.

**One clearly marked note, kept for the record.** An authorization-denied
state — distinct from plain "nothing actionable yet" — does not exist in the
code today. The padlock, reserved for authorization denials only and never
for "nothing to do here," returns to the rail **only if and when that state
is built.** That is genuine future work, contingent on a real
authorization-denial state landing (most likely alongside further #493
behaviour work) — it is **not** recorded as this round's gap in the icon
channel, because this round ships full icon coverage cleanly without it.

---

## 3. Icon set

**Corrected 2026-08-31.** The set below is the one that was actually decided. An earlier
version of this section was a **reconstruction** assembled from surviving second-hand
references rather than from the source, and it got **two of five wrong** — it recorded the
*mockup's* choices for exactly the two stages where the decision had overruled the mockup.

| Stage | Icon | |
|---|---|---|
| Design | **pencil** | |
| Plan | **map pin** | *was wrongly recorded as "puzzle"* |
| Provision | **stacked blocks / rack** | *was wrongly recorded as "cloud-upload"* |
| Configure | **sliders** | |
| Finalise & Review | **circled check** | |

The decision, recovered verbatim from the session where it was taken:

> **Plan — MAP PIN.** Not a puzzle piece (unguessable cold) and not a calendar (implies
> time; wrong). Plan in this product resolves WHICH FACILITY the workload runs on, so a
> location pin is both the most legible option and the most semantically accurate one.
>
> **Provision — STACKED BLOCKS / rack.** Not a cloud — that misstates the architecture
> (self-managed Kubernetes on owned hardware). Blocks read as allocating instances.

Note the second reason: a cloud glyph does not merely look generic here, it **states
something false about the platform**. That is why this is a correctness fix and not a
preference.

### Styling: filled, not stroked

The same decision carried a craft rule that the reconstruction also lost:

> **FILLED FORMS, NOT THIN STROKES.** Solid silhouettes survive 16px; 1.5px stroke sets die
> there. Rounded terminals and generous corner radius. One idea per icon, big silhouette, no
> internal detail.

The five are therefore **inline SVG symbols drawn in-repo**, filled, `fill="currentColor"`.
This supersedes the earlier "`lucide-react` is the existing icon dependency, no new icon
library is needed" note — lucide is a 1.5px *stroke* set and cannot satisfy the rule. Drawing
five symbols inline satisfies it **without** adding a dependency, so the constraint behind
that note is honoured even though its conclusion is not. lucide remains the dependency
everywhere else in the app.

**Known collision, designed out rather than discovered later:** stacked blocks and sliders are
both horizontal-line forms — the flaw that sank an earlier icon set. They are separated by
**weight and rhythm**: blocks are three chunky bars with graduated opacity; sliders are two
thin rules broken by large solid knobs at different x-positions. Any future change to either
must re-check the two **rendered side by side at rail size**, not judged individually.

### Constraints that hold regardless of the set

- Icons are **decorative beside a visible label** — `aria-hidden`, never announced twice.
- The key's accessible **name** stays the bare EBU label (`Design`, `Plan`, …). Tests address
  keys by that name, so it must not absorb anything else.
- **Label spelling stays exactly "Finalise & Review."** Reference images read
  "Finalize / Review"; adopting that is a separate, deliberate copy decision, never a side
  effect of an icon change. This has been attacked more than once.
- **Every key renders its identity icon regardless of state** — including a stage with nothing
  actionable. No key is ever iconless, and no icon is ever swapped for a padlock or any other
  state glyph (§2a).
- The circled check is *why* the Badge (§2) can never be a tick — a tick on Finalise would
  duplicate the icon already on that key.
- **Ship gates: a squint test at 16px and a greyscale check, both rendered rather than
  asserted.** With colour gone from the rail (§4), icon distinctness is load-bearing for
  identity rather than decorative.

---

## 4. Colour — retired from the rail (operator ruling, 2026-08-31)

**There is no colour on the lifecycle rail.** No key carries a colour of its own: nothing in
the rail's painting depends on *which* stage a key is. The five `--color-rail-*` tokens, the
per-stage map and the CVD verification apparatus are deleted from the code, not merely unused.

**Amended 2026-09-01 (dmfdeploy/dmfdeploy#512).** This paragraph read "all five keys share a
single neutral fill and a single ink", which was true when the rail's only state was
selected-or-not. §2d replaced that with a **per-state** model — face, ink and edge each take
one of three values by state, and all five keys take the *same* value in the *same* state. The
per-stage ruling is untouched and is what this section is about: identity never varies by
colour. What varies is state, uniformly across every key.

The selected face is a cyan (`--color-selected-face`) shared with the vertical nav. That is
not per-stage colour returning by the back door — it says "this one is selected", the same
sentence on whichever key it lands, and §2d's measurements show it survives greyscale.

This section previously specified five muted per-stage identity hues. It is kept — rewritten
— because the reasoning is the expensive part and a future round *will* propose per-stage
colour again.

### 4.1 What was tried, and what it measured

**Attempt 1 — hue as the key fill.** Defeated by §2c: fill luminance cannot carry stage
identity and selection simultaneously. Usable capacity was two swatches against five needed.

**Attempt 2 — hue reduced to a 3px bottom-edge line**, keeping fills neutral so selection
worked again. This is the version that looked most promising, and it is where the idea
actually died. Measured on a real render with Machado/Oliveira/Fernandes (2009) simulation
and CIEDE2000:

| condition | tightest pair | ΔE2000 |
|---|---|---|
| **protanopia** | plan / provision | **0.85** |
| **deuteranopia** | plan / provision | **1.17** |
| tritanopia | configure / finalise | 6.74 |

**~1.0 is approximately the floor of human colour discrimination.** So 0.85 is not a tight
pair — it is *below the threshold at which any difference can be seen*, under the two
**common** deficiencies, which together affect roughly 1 in 12 males. Confirmed visually with
a protanopia filter on the live render, not only numerically. Widening the hue spread was
attempted and broke a different constraint, so it was reverted rather than trading one defect
for another.

**Why the line failed where the fill had not:** shrinking hue from a whole key to a 3px line
removes most of the colour area, and small patches are exactly where muted low-chroma colours
stop being separable. The same pairs were adequate at fill size.

### 4.2 The ruling

Hue that is imperceptible for 1 in 12 viewers is **not an identity channel**. It was judged
not worth the token surface, the CVD verification surface or the documentation surface for a
cue that fails outright for that share of the audience. **Identity is carried by the icon and
the label**, both independent of colour vision and both surviving greyscale unchanged (§2).

### 4.3 If per-stage colour is ever reproposed

Read §2c and §4.1 first. The two failures were not tuning problems:

- Fill-borne hue fights selection for the same luminance channel.
- Line-borne hue is too small an area for muted colours to remain separable under common CVD.

A serious proposal has to defeat both, with **measurements on a real render** — a CVD
simulation *and* a separate luminance-separation check, since a palette can pass ΔE while two
of its members share a luminance. Red and amber remain reserved for the alarm LED regardless
(critical/warning), as does the rule that a stage hue must never be applied to anything that
reads as *status* elsewhere in the console.

### 4.4 The contrast criteria — one unconditional, one conditional

**Amended 2026-09-01.** This section previously stated **two** binding floors. That was
wrong about the first one, and after §2d the document would have been asserting a rule its
own design breaks. Restated as what actually binds:

- **Unconditional — each face pairs with an ink clearing 4.5:1** (SC 1.4.3). No escape
  hatch, no conditions. Shipped: resting **6.74:1**, hover **11.39:1**, selected **5.06:1**.

- **Conditional — a key's silhouette needs 3:1 against its background *only when the
  silhouette is what identifies the control*** (SC 1.4.11). The old absolute framing came
  from a true observation with a false conclusion attached: a clipped shape carries no
  border, so the fill is the key's only possible edge — therefore, it was assumed, the fill
  must carry 3:1. But 1.4.11 governs the information **required to identify** the component,
  and these keys carry always-visible text labels, so the boundary is not what identifies
  them. The shipped resting face measures **1.36:1** against the band and is conformant on
  the label.

  **The condition is load-bearing, not a loophole.** If a future round removes the labels,
  abbreviates them, or hides them at a breakpoint, the 3:1 floor becomes binding again on the
  same day. Note also that the background moved — the band paints `--color-sidebar`, not
  `--color-bg` — so any silhouette figure quoted against the page background is stale.

Note the WCAG "dead zone" around relative luminance ~0.131–0.207, where neither a light nor a
dark ink reaches 4.5:1. Any future fill must stay out of it.

---

## 5. Shape

**Measured, 2026-08-31; rescaled 2026-09-01.** This section previously specified the shape as
pending measurement. Every value here is taken from a real render at the stated conditions —
not estimates — but **two implementations contribute and they must not be conflated**: the
construction, the corner treatment and the two-joint-radii finding come from
[dmf-cms#128](https://github.com/dmfdeploy/dmf-cms/pull/128) (merged, live in 0.31.0), while
the 40px column in §5.1, the hover ring and the §5.4 focus ring come from
[dmf-cms#131](https://github.com/dmfdeploy/dmf-cms/pull/131) (open, not yet shipped).

### 5.1 Geometry, as built

**Amended 2026-09-01 (dmfdeploy/dmfdeploy#512).** The key height went 28 → 40px to match the
vertical nav's own `h-10 w-10` tile. The 28px column is kept alongside, because the *rules*
are the durable part, not the numbers.

> **This table is not a uniform ×1.4286 rescale, and must not be re-derived as one.** Three
> values follow the height scale; three are governed by their own rule and deviate from it.
> A future rescale that multiplies the table will silently break two deliberate decisions.
>
> | value | rule |
> |---|---|
> | notch depth, apex radius, icon | linear with height |
> | content offset | `notch / 2`, so linear by consequence |
> | **outer terminal radius** | **= the nav tile's own radius, taken exact** |
> | **the two joint radii** | **ratio-preserving against the original pair** |
>
> **Terminal radius is 8, where the scale gives 8.57.** It is not a rounding. At 28px the rail
> deliberately did *not* match the nav's 8px `rounded-lg`, because a 28px key and a 40px tile
> were different size buckets and radius scales by bucket. The rescale merged the buckets —
> both are 40px now — so the operative rule stopped being "scale the old rail value" and
> became "**use the nav's radius**". The value is `Sidebar.tsx`'s literal, not arithmetic on 6.
>
> **The joint radii are 9 and 12, where the scale gives 8.57 and 11.43.** Rounding each
> independently would give 9 and 11 — and shift their ratio from **0.75 to 0.818**. That ratio
> is the whole content of the unequal split: it encodes *an acute joint needs more radius than
> an obtuse one to read equally soft*, and it exists because the operator circled the
> notch-side joint as still-too-sharp on two separate equal-radius attempts. 9/12 holds 0.75
> exactly. The pair was then confirmed on a render at the new size — but the value came from
> holding the ratio, not from re-judging the angle from scratch.
>
> This is also why the two values that both started at **6** diverged to **8** and **9**: they
> are governed by two different rules, not one scale factor.

On a **40px-tall** key at the shared column width, with a **3.00px** inter-key gap (a layout
constant, never derived from height):

| feature | 28px (retired) | **40px (current)** |
|---|---|---|
| notch depth (tip protrusion and tail inset alike) | 12px | **17px** |
| apex radius — arrow tip *and* notch apex | 5px | **7px** |
| outer terminal radius (Design's left, Finalise's right) | 6px | **8px** |
| joint radius, tip side | 6px | **9px** |
| joint radius, notch side | 8px | **12px** |
| icon | 14px | **20px** |
| content offset on notched keys (`notch / 2`) | 6px | **8.5px** |
| hover ring inset | — | **2px** |

**The icon size is not an independent choice.** It is 50% of key height in both the rail and
the nav tile, so matching the height matched the icon automatically — 14px in a 28px key and
20px in a 40px tile are the same ratio.

**The two joint radii differ deliberately.** The tip-side joint (flat edge meeting the
outgoing diagonal) is obtuse, ~120°; the notch-side joint is acute, ~77°. **At equal radius
the acute corner reads sharper** — perceived softness depends on the included angle, not the
radius alone. Collapsing these to one value reintroduces visible sharp corners on the notch
side, which is how it was caught.

**Every vertex is rounded.** There are no raw corners anywhere: not the terminals, not the
apexes, and not the four diagonal-to-flat joints — those four were the last to be treated and
were the most visible once everything else was smooth.

**Terminals are rounded-square, not pill.** A radius of half the height reads as a tab or
chip; on a 28px control that lands on the toy side of "friendly, not toy". The 40px rescale
does not change this — the terminal radius is 8px against a 20px half-height, so it stays
clearly square-ish.

### 5.2 Construction

**A generic corner-rounding pass over a data-only vertex list**, not hand-written vertices.
Each corner becomes a quadratic curve whose control point is the original sharp vertex, with
the radius clamped to half the shorter adjoining edge so neighbouring corners can never
overrun each other. One function serves all three key positions.

This matters beyond tidiness: the previous implementation was **56 hand-computed polygon
vertices** including a hardcoded `calc(50% - 14px)` tied to the 28px height. It was correct,
but unreadable and impossible to eyeball — which is precisely why sharp corners survived
several rounds of review in it.

**Rendered with `clip-path: shape()`**, which accepts percentages and `calc()` so the shape
scales with a runtime, content-driven key width, and has real curve commands. `clip-path:
path()` cannot be used — absolute coordinates only. SVG `clipPathUnits="objectBoundingBox"`
cannot either — it turns a uniform pixel radius into an ellipse on a 166×28 box.

**Firefox does not support `shape()`** (verified empirically, 2026-08-31). Operator ruling:
Firefox gets **plain rounded rectangles**, feature-queried on a `curve` command specifically —
supporting the function is not the same as supporting every command. The old polygon is
**deleted**, not retained as the fallback.

### 5.3 Content centring — centre on the painted shape, not the box

A notched key's painted region starts `notch` px in from its left edge, so its optical centre
sits `notch/2` right of the box centre. Content centred on the **box** therefore sits visibly
left of centre on every notched key. **Content is centred on the painted region**, which means
a `notch/2` offset on keys with a notch and **no offset on the first key**, whose left edge is
flat.

Recorded because it is invisible to every automated check and regressed silently the moment
the notch existed.

### 5.4 Focus ring

**The ring lives on the unclipped element; only an inner layer carries the clip.** `clip-path`
clips a focus outline away silently, and `filter: drop-shadow()` follows the silhouette but
dies under Windows forced-colors. That part is unchanged and remains the load-bearing
constraint.

**Amended 2026-09-01 (dmfdeploy/dmfdeploy#512) — the two-tone stroke is retired, and it did
not work.** This section previously specified a two-tone stroke: an inner band in the
page-background tone, an outer band in the text tone, on the reasoning that whatever the ring
crossed, one of the two would have contrast. An adversarial review found the reasoning is
geometrically unsound, and the implementation it described was broken in one state:

- The ring was `outline-current` at `outline-offset: 0`, so the 2px outline occupied the
  **0–2px outward band**. Both `box-shadow` strokes are zero-offset zero-blur spreads
  occupying that **same** band, and an outline paints **above** outer box-shadows. The
  outline therefore *occluded* both tones rather than sitting between them — there was never
  a visible sandwich, only the outline.
- `currentColor` is the ink, and after this round the selected key's ink is dark
  (`--color-bg`). So on a **selected, keyboard-focused** key every exposed stroke was dark on
  a near-black band — roughly **1.04:1**. The operator state most likely to need a focus
  indicator was the one state that had none.

**Now: a single unconditional outline in the text tone** (`outline-text`, 2px, offset 0), with
no `box-shadow`. It cannot follow the ink, so no ink change can darken it. Measured
**15.53:1** in all four selected × focused combinations, and it clears 3:1 against every
adjacent surface — the band (15.53:1), the resting face (11.39:1) and the selected face
(3.19:1).

Total outward reach stays inside the 3.00px inter-key gap so a focused key never touches its
neighbour. `outline` survives forced-colors and is recoloured by the OS — which is now the
whole mechanism rather than half of it, so there is no longer a second stroke to lose.

> **The generalisable part:** the earlier ruling was reasoned from the CSS box model rather
> than measured on a render, and it was wrong about paint order. Two agents and this document
> all repeated it. A ring's *stated* composition is not evidence about the pixels it produces.

### 5.5 Badge

**Slot built, no number rendered** until the ADR-0046 derivation
([#495](https://github.com/dmfdeploy/dmfdeploy/issues/495)) produces a real actionable-item
count. While empty **the slot carries no meaning at all** (§2b) — nothing painted twice,
nothing claiming a number the console cannot verify.

---

## 6. Open gaps (explicit, so none of these is silently assumed done)

| Gap | Status | Where it's tracked |
|---|---|---|
| Padlock for authorization-denial only | **Not built — future work, not a gap in this round.** Full identity-icon coverage ships without it (§2a). Returns only once an authorization-denied state distinct from "locked" exists in the code. | §2a; downstream of a future #493-adjacent behaviour change |
| Badge counts | **Deferred by design** — slot built, no number rendered until ADR-0046 lands. Absence carries no meaning meanwhile. | §5.5; §2b |
| No progress or actionable signal on the rail until #495 | **Accepted temporary gap.** The completeness dot is retired (§1) and the position marker is removed (§2); the badge is not yet live. The workload home, where no key is selected, loses the most. | §2b; [#495](https://github.com/dmfdeploy/dmfdeploy/issues/495) |
| Filled icons elsewhere in the app | **Out of scope.** The rail's five are inline filled SVG (§3); the rest of the console still uses stroked lucide. | [#507](https://github.com/dmfdeploy/dmfdeploy/issues/507) |
| `shape()` unsupported in Firefox | **Accepted, with a defined fallback** — plain rounded rectangles, feature-queried on a `curve` command (§5.2). Operator ruling 2026-08-31. | §5.2 |
| Icon set provenance | The set in §3 is now corrected against the recovered decision, but the original **reference image still lives outside the repos**. Nothing in-tree can adjudicate a future disagreement. | [#506](https://github.com/dmfdeploy/dmfdeploy/issues/506) |

**Closed since the previous version of this table:**

- *Notch depth unmeasured* — measured and built; §5.1 carries the values and the conditions
  they were taken under.
- *CVD simulation on the five stage hues* — run, and it is what removed hue from the rail
  entirely (§4.1). There are no stage hues left to simulate.
- *Hue carry-through into stage content* — **moot.** It tracked carrying the rail's identity
  hue outward; there is no rail hue to carry. [#505](https://github.com/dmfdeploy/dmfdeploy/issues/505)
  closed as superseded. A stage-content tint for *wayfinding* would be a new question with its
  own contrast and CVD requirements, not a revival of that one.

---

## 7. Sequencing

Per the Shell Round Plan: **spec the model now (this doc + the #493 IA
amendment), build visuals against it, behaviour lands after.** The icon set
(§3) and the shape (§5) landed together in [dmf-cms#128](https://github.com/dmfdeploy/dmf-cms/pull/128) (merged 2026-08-31,
shipped in 0.31.0), with **no padlock** — see §2a. The
padlock is not scheduled; it returns only once the authorization-denial state
named in §2a exists, which is future work outside this round's plan.

**A second round followed, unplanned** — [dmf-cms#131](https://github.com/dmfdeploy/dmf-cms/pull/131) /
[dmfdeploy/dmfdeploy#512](https://github.com/dmfdeploy/dmfdeploy/issues/512), the rail/nav
parity amendment, open at the time of writing. It came from the operator looking at 0.31.0 on
a live environment, which is the point §8 makes: the defects that matter here are found by
looking, and shipping is what produces the look.

## 8. How this round was verified, and what that cost

Recorded because the pattern held without exception, and the next visual round should
start from it rather than rediscover it.

**Every visual defect was found by looking at a render. None was found by the test suite,
and none by adversarial diff review.** The suite ran green — 763, then 823, then 830
passing — through all of the following:

| defect | how it was found |
|---|---|
| Selection invisible on the three lightest keys (1.49:1) | rendering the harness and querying computed styles |
| Focus ring invisible against the page background (1.10:1) | the same, while fixing the above |
| Four untreated raw vertices on every key | operator looking at a magnified render |
| Tip and tail not interlocking | operator looking at a comparison board |
| Labels 6px off the painted centre on four of five keys | operator looking, then measured |

`aria-pressed` and the accessible names were correct throughout, so accessibility tests
passed while the interface was, for a sighted operator, ambiguous.

`aria-current` is a sharper case and worth separating out: it was **present, asserted and
passing — and semantically wrong**. It announced `step`, a position in a gated sequence, on a
model that had ruled stages are peer views and explicitly *not* steps (§1). A test pinned the
attribute's presence, so the suite defended the wrong semantics rather than catching them.
That is the same failure as a green check that checks nothing, one level up: the assertion was
about the attribute existing, never about whether it should.
**jsdom computes no pixels**, and a diff cannot see a colour relationship between two
rendered states.

Three practices earned their cost and should be defaults:

- **Build the harness before the component**, not as verification afterwards. It was the
  instrument, not the check.
- **Measure computed styles on a real render**, not source values. Alpha composites,
  `:focus-visible` does not match a programmatic `.focus()`, and `transform: scale()`
  rasterises `clip-path` into artifacts that look exactly like geometry bugs.
- **Put renders in front of the operator as options**, not descriptions. Four rounds were
  spent on prose adjectives — "softer", "less round" — before a comparison board settled
  the shape in one pass.

**Numbers need their derivation attached.** Three separate figures in this round did not
reproduce: a claimed luminance mitigation, then its correction, then a ΔE set from a
faulty pipeline. Each was precise, plausible and wrong. A figure that cannot be
recomputed from a stated method is not evidence, and the fix is to record the pipeline
next to the number — which §4.1 and §5.1 now do.
