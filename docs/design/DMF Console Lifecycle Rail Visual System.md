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
| **Luminance / fill** | selection ("am I looking at this one") |
| **Icon** | stage identity — see §3 for the set. |
| **Badge** | count of actionable items. **Absence of badge = nothing actionable.** |

Everything except hue survives greyscale, and hue only carries identity —
already redundant with the visible label. **Art. 11 clean by construction.**

**Rejected:** folding stage-state into fill/edge alongside selection (an
earlier #481 proposal) — that is six treatments that must all survive
greyscale, and Art. 11 was only ever verified for the dot the previous round
shipped.

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
  nothing claiming a number the console cannot yet verify.

---

## 6. Open gaps (explicit, so none of these is silently assumed done)

| Gap | Status | Where it's tracked |
|---|---|---|
| Padlock for authorization-denial only | **Not built — future work, not this round's gap.** This round ships full identity-icon coverage without it (§2a). Returns only once an authorization-denied state distinct from "locked" exists in the code. | §2a; downstream of a future #493-adjacent behaviour change |
| Notch depth | **Unmeasured.** Do not build from the reported 141.4px figure. | §5 |
| CVD simulation on the five stage hues | **Not yet run.** | §4 |
| Badge counts | **Deferred by design** — slot built, no number rendered until ADR-0046 lands. | §5 |

---

## 7. Sequencing

Per the Shell Round Plan: **spec the model now (this doc + the #493 IA
amendment), build visuals against it, behaviour lands after.** The icon set
(§3) and the shape (§5) ship together this round, with **no padlock** — see
§2a. The padlock itself is not scheduled; it returns only once the
authorization-denial state named in §2a exists, which is future work outside
this round's plan.
