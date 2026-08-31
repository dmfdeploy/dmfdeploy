# DMF Console — Lifecycle Rail Visual System

**Status:** **Design spec** (2026-08-30).
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
#483 (directional shape). The three are one visual system: icons, colour, and
shape all compete for the same 141px-ish key, so specifying them separately
risks three uncoordinated repaints. This doc specifies all three together.

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

## 2. Four channels, four facts

| Channel | Carries |
|---|---|
| **Hue** (muted, permanent, per stage) | stage identity |
| **Selection ring** (**inset**, drawn in the key's **own ink**) | selection ("am I looking at this one") — **see §2c** |
| **Luminance / fill** | reinforces selection on every key; **never carries it alone — §2c** |
| **Icon** | stage identity — see §3 for the set. |
| **Badge** | count of actionable items. **Absence of badge = nothing actionable — but only once the channel is live; see §2b.** |

Everything except hue survives greyscale, and hue only carries identity —
already redundant with the visible label. **Art. 11 clean by construction.**

**Rejected:** folding stage-state into fill/edge alongside selection (an
earlier #481 proposal) — that is six treatments that must all survive
greyscale, and Art. 11 was only ever verified for the dot the previous round
shipped.

### 2c. Selection needs its own channel — fill luminance cannot carry it

**Amendment, 2026-08-31 (operator ruling).** The original table gave *selection* to
"luminance / fill" while giving *stage identity* to hue. Measured against a real
render, those two assignments are not simultaneously satisfiable.

Selection paints an achromatic near-white fill, `rgb(232,232,234)`. How much a key
actually changes when selected therefore depends entirely on where its identity hue
sits on the luminance ramp:

| stage | identity fill | contrast when selected | ink on selection |
|---|---|---|---|
| Design | `rgb(52,106,92)` | 5.10:1 | light → dark, flips |
| Plan | `rgb(74,97,150)` | 4.99:1 | light → dark, flips |
| Provision | `rgb(146,129,187)` | 2.82:1 | dark → dark, no change |
| Configure | `rgb(190,151,196)` | 2.04:1 | dark → dark, no change |
| **Finalise & Review** | `rgb(215,183,200)` | **1.49:1** | `rgb(15,23,32)` → `rgb(10,10,11)`, no change |

On the three lightest keys selection is at or below the WCAG 1.4.11 3:1 floor for a
UI-state change, and on Finalise & Review it is imperceptible — the ink does not flip
either, because light hues already carry dark ink. `aria-pressed` is correct
throughout, so assistive technology is unaffected and a full test suite passes; a
sighted operator simply cannot see which key is selected.

**Why no retune fixes it.** The constraints pull in opposite directions: §4's 3:1
fill-vs-background floor pushes hues *lighter*, while a 3:1 fill-vs-selected-fill
floor pushes them *darker*. Solving all of §4's requirements at once leaves two
disjoint usable bands — roughly L\* 39.4–42.9 for dark-ink swatches and L\* 53.2–55.7
for light-ink ones, about 6 L\* units in total. That is capacity for **two** distinct
swatches; the rail needs **five**. No single alternate selection tone escapes it
either: clearing 3:1 from both ends of the existing ramp would require a luminance
above 1.0 (impossible) or one indistinguishable from the page background.

So this is a structural conflict, not a tuning gap.

**The ruling.** **Selection is carried by a persistent ring, drawn *inset* — inside the
key, over the key's own fill — rather than by fill luminance.** The achromatic
fill-invert is **kept on every key alongside it**, because it costs nothing and is a
genuine reinforcement at the dark end (~5:1 on Design and Plan). What changes is that it
is **never the sole signal anywhere** — the ring is what carries selection, and the
fill-invert only ever adds to it.

**Inset is load-bearing, and a fixed neutral ring is provably impossible.** An earlier
draft of this section called for "a persistent ring in a fixed neutral tone" facing
both the key and the page background. That is unsatisfiable, and the proof is short —
for a ring of relative luminance `L` against page background 0.0031, selected fill
0.8081, and the Design fill 0.1181:

| must clear 3:1 against | admissible `L` |
|---|---|
| page background | `L ≥ 0.1092` |
| selected fill | `L ≤ 0.2360` (lighter would need `L ≥ 2.52`) |
| Design fill | `L ≥ 0.4543` **or** `L ≤ 0.0060` |

The first two give `[0.1092, 0.2360]`; the third excludes it entirely. **No fixed
neutral exists.** That draft would have reproduced, one level out, the very defect this
section fixes.

**What makes it solvable is that the two rings face different things.**

- **The selection ring is inset**, so *both* of its sides sit on the key's own fill. It
  never meets the page background or a neighbour, and the only requirement is contrast
  against the fill it sits on. Drawing it in the key's **own ink** satisfies that for
  free — §4 already requires every swatch to pair with an ink clearing **4.5:1**, which
  is above the 3:1 this needs.
- **The focus ring is outset**, so it genuinely does face the page background and the
  neighbouring key. It therefore needs a **two-tone stroke** — an inner stroke in the
  page-background tone and an outer stroke in the text tone — so that whatever it
  crosses, one of the two has contrast. This also holds **by construction**: §4 point 1
  already requires every identity hue to clear 3:1 against the page background, so a
  background-toned stroke clears 3:1 against every fill automatically, and the text tone
  clears 16.17:1 against the background.

That second point is the useful structural result: **the ring constraints are not new
constraints.** They are §4's existing ones re-used, which means a future retune of the
hues cannot silently break the rings so long as §4 point 1 and the ink rule still hold.

Consequences that bind implementation:

- **Focused, selected, and focused-and-selected must be three distinguishable states**,
  and that distinction must survive greyscale (Art. 11) — both signals are rings, so
  they cannot be separated by colour alone. Inset-versus-outset is itself the
  greyscale-safe separator.
- **Total outward reach must stay inside the inter-key gap.** The key boxes are
  **3.00px** apart, measured on a real render; an outward stroke reaching further will
  overlap the neighbour.
- **Forced-colors mode must be considered per layer.** `outline` is recoloured to a
  guaranteed-visible system colour and survives; `box-shadow` drops out. Any two-tone
  treatment must therefore leave a working indicator when only the outline remains.
- §4's CVD and contrast work is unaffected. Hue keeps carrying identity; it simply stops
  being asked to carry selection as well.

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

**This amendment changes the badge channel's semantics only — it does not change what
Phase A must build.** §5 still assigns Phase A the slot itself: the reserved geometry,
the fixed width budget, and the `aria-hidden` treatment that keeps an empty decorative
box out of the accessibility tree. That work is a Phase-A requirement and is *not*
recorded here as already done. What §2b settles is what the finished slot **means**
while it is empty: nothing. A future reader therefore cannot derive a false claim from
§2's table, and whoever implements #495 knows that switching the channel on is also
what switches its absence semantics on.

**Consequence worth stating plainly:** between this round and #495, the rail has
*no* progress or actionable-work signal at all — the completeness dot is retired
(§1: completeness is not a coherent property of an independent peer stage) and the
badge is not yet live. The workload home, where no key is selected, is the state
that loses the most. That is an accepted, temporary gap, not an oversight.

### 2a. The padlock — no padlock this round (operator ruling, 2026-08-30)

**This round ships the five identity icons only (§3).** Every key — including
one with nothing actionable — renders its own stage-identity icon
(pencil / puzzle / cloud-upload / sliders / circled-check). No key is ever
iconless, and nothing on the rail substitutes a padlock, or any other glyph,
for a key's identity icon.

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

**Recorded here for the first time.** An operator reference image has shown
this set since before #449, but it is not written down anywhere in the repos
— not the plan, the issues, the design docs, or the agent transcript archive
(per #482). This is that record:

| Stage | Icon |
|---|---|
| Design | pencil |
| Plan | puzzle |
| Provision | cloud-upload |
| Configure | sliders |
| Finalise & Review | circled-check |

Notes, carried from #482's constraints (this doc records the semantic set;
picking exact icon names/glyphs is implementation's job in #482 itself):

- **`lucide-react` is the existing icon dependency** — no new icon library is
  needed to build this.
- Icons are **decorative next to a visible text label** — mark them
  `aria-hidden`, not announced twice by assistive tech.
- The key's accessible **name** stays the bare EBU label (`Design`, `Plan`,
  …) — icons must not fold anything additional into the name; tests address
  keys by that name.
- **Label spelling stays exactly "Finalise & Review."** The reference image
  reads "Finalize / Review"; adopting that spelling is a separate, deliberate
  copy decision, not a side effect of adding icons.
- The circled-check reasoning matters beyond naming: it is *why* the rail's
  completeness/actionable-count mark (§2's Badge channel) cannot also be a
  tick — a tick on Finalise would duplicate the circled-check icon already
  sitting on that key.
- **Every key renders its identity icon regardless of stage state** —
  including a stage that currently has nothing actionable. No key is ever
  iconless this round, and no icon is ever swapped for a padlock or any other
  state glyph (see §2a for the no-padlock-this-round ruling and why).

---

## 4. Colour

Five **muted, permanent, per-stage identity hues.**

1. **Reserve red and amber entirely.** No lifecycle hue may approach them —
   those mean *abnormal* everywhere else in the console. This removes roughly
   a third of the wheel, so five distinct muted hues is genuinely tight.
   **Cross-reference, both directions:** red and amber are reserved
   specifically *because* the top-bar alarm LED's warning/critical states use
   them (red = critical, amber = warning — see the
   [Shell Round Plan](../plans/DMF%20Console%20Shell%20Round%20Plan%202026-08-30.md)
   §1b's LED visual spec). That doc's §1b carries the matching
   cross-reference back to here, so a future round cannot loosen either
   side's reservation without seeing the other.
2. **CVD check is mandatory, and harder because the hues are muted** —
   low-chroma hues converge under deuteranopia/protanopia far faster than
   saturated ones. **Run an actual CVD simulation on the chosen five; do not
   eyeball it.** Verify luminance separation too, not only hue — two hues that
   simulate to the same grey are not distinguished by luminance alone unless
   that was checked separately.
3. **Dark theme.** The console is dark; the same tokens must hold in both
   themes, and muted-on-dark needs different chroma than muted-on-light to
   read as equally muted.
4. **Carry it past the rail** — tint the stage's content area too, or the hue
   is decoration living in a 40px band. **Never** apply it to anything that
   reads as *status* elsewhere in the console, or operators learn the hue
   means something operational when it only ever means "which stage."
   **Status: not built, explicitly deferred (operator ruling, 2026-08-31) —
   see §6, tracked as
   [#505](https://github.com/dmfdeploy/dmfdeploy/issues/505).** This point is an affirmative requirement of this document, not an
   optional polish item, and #481/#482/#483 do not deliver it. Until it does
   land, the warning in this very bullet is the accurate description of what
   ships: the hue lives in the band alone.

**Rationale for muted over a saturated ribbon:** borrows ISA-101
(greyscale-normal, colour = abnormal, ~90% neutral so real problems pop). The
top bar is simultaneously gaining a message bus and an alarm LED — the two
elements that genuinely need to shout (see the
[Shell Round Plan](../plans/DMF%20Console%20Shell%20Round%20Plan%202026-08-30.md)).
Recognisability comes from **form** instead — the chevron silhouette (§5) is
already unique on the page.

---

## 5. Shape

- **Nested with a thin gap** — interlocking geometry, but a 2–3px
  band-coloured gap cut into the shape so keys nest without visually
  touching. Keeps the one-ribbon read *and* keeps a single contrast problem
  (key vs. band) instead of adding a second one (key vs. key).
- **Flat terminals** — Design's left edge and Finalise & Review's right edge
  are flat, not pointed. A lifecycle is a bounded process; pointed terminals
  read as "continues off-screen."
- **Notch depth — unmeasured, pending a real render. Do not build from
  141.4px.** A figure of 141.4px / spread 1.000 has circulated in #481, but
  it is a **live-render number reported in that issue with no viewport zoom
  recorded** — not a value the code or any prior gate established as a
  baseline. "Finalise & Review" is the longest label, and a notch takes width
  on one side and adds it on the other, so usable text width is `track −
  notch`, narrower than the shared column width. **Before implementation:**
  take a fresh measurement on a real render at the 1920×1080 capture
  viewport, **record both the viewport and the zoom level** alongside the
  number, and compute the notch budget from that measurement — not from the
  unverified 141.4px figure above. If the measured budget truncates the
  label, the fix is a shallower notch, a wider track, or shorter label text —
  decided from the measurement, not guessed ahead of it.
- **Focus ring: use a wrapper element carrying the ring.** `clip-path` clips
  the focus outline along with the shape, silently removing the keyboard
  focus indicator. `filter: drop-shadow()` follows the silhouette well but
  dies under Windows forced-colors mode. Take the boring, robust option: a
  wrapper element that carries the ring independently of the clipped shape.
- **Badge-ready, no counts this round.** Build the badge slot — geometry and
  width budget — but render no number until the ADR-0046 lifecycle-derivation
  work produces a real actionable-item count to show. Nothing painted twice,
  nothing claiming a number the console cannot yet verify. **While the slot is
  empty it carries no meaning at all — §2b, which is what stops §2's
  absence-semantics from asserting "nothing actionable" on every key this
  round.**

---

## 6. Open gaps (explicit, so none of these is silently assumed done)

| Gap | Status | Where it's tracked |
|---|---|---|
| Padlock for authorization-denial only | **Not built — future work, not this round's gap.** This round ships full identity-icon coverage without it (§2a). Returns only once an authorization-denied state distinct from "locked" exists in the code. | §2a; downstream of a future #493-adjacent behaviour change |
| Notch depth | **Unmeasured.** Do not build from the reported 141.4px figure. | §5 |
| CVD simulation on the five stage hues | **Not yet run.** | §4 |
| Badge counts | **Deferred by design** — slot built, no number rendered until ADR-0046 lands. Absence carries no meaning meanwhile. | §5; §2b |
| **Hue carry-through into stage content** (§4 point 4) | **Not built — explicitly deferred, operator ruling 2026-08-31.** The rail ships its five identity hues; tinting the stage content area is a materially larger surface (every stage page) and is *not* part of #481/#482/#483. Recorded here so it is not silently assumed done — until it lands, §4 point 4's own warning applies and the hue does live in the band alone. | §4 point 4; [#505](https://github.com/dmfdeploy/dmfdeploy/issues/505) |
| No progress/actionable signal on the rail between this round and #495 | **Accepted temporary gap** — completeness dot retired (§1), badge not yet live. Costs the workload home the most. | §2b |

---

## 7. Sequencing

Per the Shell Round Plan: **spec the model now (this doc + the #493 IA
amendment), build visuals against it, behaviour lands after.** The icon set
(§3) and the shape (§5) ship together this round, with **no padlock** — see
§2a. The padlock itself is not scheduled; it returns only once the
authorization-denial state named in §2a exists, which is future work outside
this round's plan.
