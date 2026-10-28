# dmfdeploy.io | creative direction

**Status:** Iteration 1 direction for the site redesign
**Audience:** design and implementation team
**Reference reviewed:** [Huly homepage](https://huly.io/) (accessed 2026-10-28)

## Direction in one sentence

Make dmfdeploy feel like an open engineering system becoming legible: a restrained industrial interface with one warm, atmospheric entry point, precise operational diagrams, and visible evidence for every claim.

## Current design critique

- The dark technical canvas, warm magenta-to-orange gradient, clear sections, and prototype-status distinctions are useful foundations. The prototype caveats give the site unusual credibility; retain them.
- The homepage hero has too many simultaneous signals: oversized all-caps headline, long summary, rule, action pair, status line, grid, orbit SVG, video card, and lower navigation strip. The ellipse overlay reads as decoration and competes with the video and message. Remove the orbit-field layer and ellipse-ended hero rule.
- Ellipses are repeated in arbitrary places: orbit traces behind content, ornamental ovals in standards/value cards, and rounded lower corners on several unrelated panels. Give the mark's geometry a coherent visual language. Keep the logo mark itself; use curvature when it explains grouping, continuity, or a transition.
- The interface currently toggles between precise technical panels and generic rounded cards. Card shapes, border radii, and outlines should have a shared logic. Avoid decorative outlines that do not map to a workflow or content group.
- The sponsor page gives the proposed tiers a large, colorful stage while the payment route and fiscal host remain unconfirmed. Keep the proposal status prominent and present the page as a transparent funding brief.
- Typography is broadly legible, but repeated uppercase headings, dense micro-labels, and the very large sponsor headline make the site feel more like a launch campaign than an engineering initiative. Use sentence case for most headings and reserve uppercase for compact metadata.

## What to learn from Huly

Huly's homepage uses a short positioning statement, a product preview near the top, then feature chapters that pair a clear claim with interface evidence. Its preview and feature imagery give visitors something concrete to inspect; navigation and repeated calls to action make a long page feel like a guided product tour. For dmfdeploy, the strongest lesson is **narrative sequencing with evidence**.

Borrow:

- A strong first screen with one clear proposition and a tangible proof object beside it.
- Section-by-section storytelling: problem, working system, how it works, state of the project, ways to participate.
- Product media presented as the subject, with quiet framing and an explicit interaction affordance. The project video can be a restrained hero preview that opens into a larger player on activation.
- Repeated wayfinding and calls to action when they answer a real next step.

Avoid:

- Huly's high-density feature inventory and broad “everything app” claims; dmfdeploy is early and narrower.
- Copying its software-dashboard imagery, gradients, floating product screens, or general SaaS polish. dmfdeploy needs industrial and broadcast credibility.
- Treating every section as another promotional benefit block. Show the control path and status evidence instead.

## Visual concepts

### A. Operational loop (recommended)

One warm gradient hero transitions into a dark, calm engineering canvas. The hero pairs the project proposition with an actual project-video still. Below, the operational loop becomes the signature graphic: four connected stages with a visible return path. Rounded ends appear only at the beginning/end of the loop or where a grouped card needs a deliberate soft boundary.

```text
┌──────────────────── warm, quiet gradient ─────────────────────┐
│ one proposition + 2 actions          [video still / play]     │
└──────────────────── curved transition ────────────────────────┘
  problem → operational loop → evidence/status → open participation
```

### B. Facility signal path

Treat the page as an engineering drawing: fine rules, numbered sections, a single continuous line that connects the catalog, automation, inventory, and observability. The line enters and exits grouped cards, and may bend between sections. No free-floating orbital lines or unattached dots.

```text
[Intent]──[Execute]──[Record]──[Observe]
                    ╰───────────────↶
```

### C. Field notes

Use editorial typography and a left-hand index rail to make the project feel like a public technical brief. A few large media panels interrupt the text; sponsorship becomes a compact, clearly qualified invitation. This is more document-like and less product-like, with less room for a strong system diagram.

```text
01  WHY         headline + compact explanation
02  HOW         large control-path illustration
03  STATUS      demonstrated | planned | unverified
04  PARTICIPATE  governance + support
```

## Recommended system rules

### Type

- Use one contemporary grotesk sans with a neutral, technical voice throughout. Prefer the existing system stack unless a licensed/webfont choice is explicitly made.
- Hero heading: sentence case, 3–4 lines maximum at desktop; target 9–14 words. Body: comfortable 55–70 character measure, 1.5–1.65 line height.
- Metadata may use uppercase, wide tracking, and compact size. Keep it legible; do not use micro-labels for important caveats.
- Use tabular numerals for tiers, versions, and step numbers. Avoid setting every card title in uppercase.

### Color

- Keep the established warm pink-to-orange gradient as a single signature field for the homepage hero. Let it fade into the deep blue-black technical canvas; do not repeat it behind every CTA or section.
- Main canvas: deep blue-black; raised surfaces: subtly lighter blue/teal; primary text: warm white; secondary text: muted blue-gray.
- Aqua is for active paths, links, and implemented/observed system states. Amber is for proposals, pending validation, and caution. Color must not be the only status cue.
- Keep borders low contrast unless they encode a connection, focus state, or semantic status.

### Shape and motion

- No standalone ellipses, orbital decorations, random nodes, or ornamental ellipse pseudo-elements. Do not remove or distort the actual brand mark.
- Default cards are square or modestly rounded (4–8 px). Reserve a larger radius for a deliberate grouped container, a media window, or the cap of a continuous flow. Do not give unrelated cards different corner treatments.
- Curves can connect sections or make successive cards flow into one another when the path has a meaning. Draw the relationship first; do not add curves as background texture.
- Use small, purposeful scroll reveals only for content already in the reading flow: a path may draw in, or a grouped card may settle into place. Keep motion brief, once-only, and optional. Respect `prefers-reduced-motion`; content must remain visible without animation.
- The hero video may expand to a larger overlay on click/tap, with a clear close control, keyboard support, captions if available, and no autoplay with sound. On mobile, use a poster and native inline playback or the same accessible player overlay.

## Page treatment

### Home hero

**Desktop:** Keep one warm gradient field. Use a balanced two-column composition: proposition, short supporting copy, one primary action and one text link on the left; a large, quiet video preview on the right. Remove the orbit SVG, grid texture behind the message, decorative endpoint oval, and extra lower hero strip. Put “open source / prototype in development” beneath the actions as a compact but readable status line. A curved lower edge or broad arc may ease into the next dark section if it creates a clear transition.

**Mobile:** Stack proposition, short copy, actions, then video. Use a natural sentence-case headline, avoid forced word-per-line breaks, and keep the video poster broad enough to recognize. Keep one action filled; let the second be a plain link. No background motion or overlay lines behind small text.

### Architecture

Make the architecture the main visual proof. On desktop, show the four stages in one connected track with a return line that clearly returns observed state to the console. Use concise labels and one-line descriptions; visually distinguish implemented stages from intended feedback. On mobile, convert to a vertical sequence with a single continuous connector, step numbers, and status text; do not shrink the desktop diagram into illegibility. Preserve the explicit note that this is a v0.1 prototype and not a production plant.

### Sponsorship

Treat the page as a transparent funding brief. Keep the “proposed” state beside tier amounts and show fiscal host, payment, and invoice status before asking for contact. The hero should summarize the work funding could enable and pair it with a compact programme-status panel. Present levels as a plain schedule or connected bands, with each level and qualifier easy to compare. On mobile, stack the levels and retain their annual/proposed qualifier next to each amount. Keep governance boundaries and the non-commitment language easy to find.

## Content and credibility guardrails

- Label every capability as **demonstrated**, **in development**, **planned**, or **unverified**; never let visual polish imply production readiness.
- Keep the boundary statements: single-node prototype scope; no claim of production ST 2110/PTP, high availability, benchmark validation, or multi-node operations.
- Distinguish project independence from EBU affiliation or endorsement. Name standards and components only for the role they actually play.
- Sponsorship amounts, levels, governance safeguards, fiscal hosting, invoicing, and payment must remain clearly marked proposed/unconfirmed until verified.
- Use interface or diagram imagery only when it represents the actual project. Do not use generic racks, waveforms, fake monitoring screens, or partner logos as credibility shortcuts.
- Every visual element should clarify a relationship, status, action, or real object. Remove it if it only fills space.

## Reference sources

- Huly homepage, reviewed directly: https://huly.io/
- Current site screenshots: `screenshots/home-desktop.png`, `screenshots/home-mobile.png`, `screenshots/sponsor-desktop.png`, `screenshots/sponsor-mobile.png`
- Current brand mark: `public/brand/mark.svg`
