# Interaction and motion specification

Status: proposal for iterative implementation. Scope: homepage film, architecture flow, and section entrances. This document describes behavior; it does not authorize motion for its own sake.

## Creative direction

The page should feel like a clear technical explanation with a human pace. Let hierarchy, typography, real diagrams, and meaningful grouping carry the design. A shape is justified when it communicates grouping, continuity, or an actual system boundary. Remove the floating ellipse ornaments that sit over standard, value, programme, tier, and governance cards, and the small ellipse attached to the hero rule: they do not explain content or interaction. Keep the project mark and only use an orbital diagram when it is directly tied to a named concept. Do not add generic parallax, cursor-following effects, animated borders, or scroll hijacking.

Huly is useful as a reference for pacing and continuity: its landing page alternates strong product statements with grouped feature panels and visual demonstrations, giving the narrative a clear flow. For dmfdeploy, use connected information and clear visual hierarchy. Keep the visual language evidence-led and restrained, grounded in the project's own content. Reference: [Huly homepage](https://huly.io/).

## Current implementation notes

- Astro renders static pages; there is no client framework. `FilmCard.astro` has one small inline script for the pitch video and CSS animates the orbital SVG.
- `FilmCard.astro` uses a real `<video>` with `preload="none"`, a poster, a play button, and native controls after play. It currently only hides the play button on `play` and restores it on pause/end.
- The architecture section is an ordered four-step flow: Console → AWX + k3s → NetBox → Prometheus. It has hover lift on cards and decorative arrows; its feedback line is meaningful, but visually separate from the steps.
- `global.css` animates the decorative orbital field, plus hover-lift on cards. Reduced motion currently disables CSS animation and transitions globally.
- Playwright covers basic home/sponsor layout, film play, mobile navigation, narrow viewport overflow, in-page anchors, and reduced motion for the orbital field. It does not yet cover scroll entrances or a floating player.

## Motion decisions

### 1. Architecture flow: connected steps, no scroll animation required

The architecture sequence is the strongest place to use continuity. Prefer a static, continuous connector behind/between the four ordered steps, with the existing arrows retained as a simple fallback and with the feedback return line clearly attached to the sequence. On desktop, the connector may draw in as the section enters view; on mobile, use a simple vertical connector. The line communicates “control path” and “observed state returns.”

- **Trigger:** IntersectionObserver marks the architecture plate visible once at least 20% is in view; only if `prefers-reduced-motion` is `no-preference`.
- **Start/state:** The line reveals from first step toward last over 450–650 ms; step text and card geometry are already fully visible before animation. No content is hidden pending JavaScript.
- **Exit:** Finish and hold. Do not reverse when scrolling upward or replay on repeated entry.
- **Implementation sketch:** Static SVG connector with `pathLength="1"`, CSS `stroke-dasharray` / `stroke-dashoffset` transition toggled by a class. Observer disconnects after first intersection. The diagram stays semantic HTML (`ol`); SVG is decorative (`aria-hidden="true"`). Sequence arrows use CSS/SVG and stay outside the focus order.
- **Mobile:** Vertical connector follows the one-column sequence. Avoid drawing across the two-column tablet layout if it would cross text; use separate short connectors or static arrows.
- **Reduced motion / no JS:** Fully drawn connector and all content visible by default. With reduced motion, omit the draw transition. This is progressive enhancement.

### 2. Section entrance: a single restrained reveal for key content groups

Use a modest reveal on section headers and the architecture plate / status ledger as a whole. Keep all cards in that group on the same timing. The aim is to signal a new chapter while scrolling. Keep normal document flow; do not pin sections or delay reading.

- **Trigger:** A group becomes visible at 15–20% intersection, with `rootMargin: 0px 0px -8% 0px`.
- **Start/state:** At most 12 px vertical offset and opacity 0.82 to 1 over 240–320 ms with an ease-out curve. Content must be visible in its default CSS state, then JS may add an enhancement class; never ship an initially hidden state.
- **Exit:** Animate once and hold. No reverse fade, no repeated replay, and no per-item cascading delays.
- **Implementation sketch:** Small vanilla module or inline script using one IntersectionObserver and a shared data attribute. Observe a short allowlist of meaningful groups. `unobserve` after reveal. No scroll event handler, animation library, or state framework.
- **Accessibility:** `prefers-reduced-motion: reduce` disables offset/fade. Screen-reader tree and keyboard order are unchanged. Maintain visible focus outlines and avoid transforms on focused elements.
- **Mobile/performance:** Same or smaller 8 px offset; skip observing below low-power constraints only if performance data shows a need. Do not animate the decorative background field as a substitute for content hierarchy.

### 3. Pitch film: keep inline playback as the default; do not auto-pop out

A floating mini-player could preserve the pitch while readers continue down the long homepage, but it risks competing with the page and obscuring content. The film is only 30 seconds and the user must start it; a pop-out is therefore optional and should be implemented only if a tested scroll journey shows a real need. Never auto-play, auto-mute, or move a playing video without user intent.

If pursued, make it an explicit, reversible “Keep playing while I browse” action shown only after playback begins. This is preferable to silently converting playback on scroll.

- **Trigger:** User activates a visible “Keep playing while I browse” control while the inline video is playing. Scroll position alone never triggers pop-out. The control is hidden until play has started and shown only when there is enough viewport space.
- **Start/state:** Move the same video element into a fixed compact dock (do not clone the media element or restart playback). Dock dimensions approximately 320×180 desktop, bottom-right with safe margins, below sticky header; on narrow mobile use a full-width bottom dock with capped height and enough bottom padding added to page content. Keep native video controls available. Show a visible “Return video to page” button and a clear close/minimize button.
- **Exit:** Return action scrolls the original card into view, restores the element in place, then removes dock state. Close/minimize returns it inline without stopping playback. On `ended`, return inline and restore the play affordance. On route change/page hide, browser-native behavior applies; do not persist video state.
- **Keyboard/accessibility:** Both dock actions are real buttons with accessible names. Do not steal focus when entering the dock; if user activates a dock action, preserve logical focus and ensure it remains visible. Escape must not unexpectedly stop playback. Announce the state change with a concise `aria-live="polite"` message only when user explicitly changes state. Native controls remain keyboard accessible.
- **Reduced motion:** Relocation is immediate (no scale/slide transition); no change to playback policy. Reduced motion must not pause or start the film.
- **Mobile:** Test Safari/iOS and Android Chrome. If the browser takes playback fullscreen or lacks reliable inline relocation, omit the dock there and keep the inline player. The feature must never block page controls or cover a CTA.
- **Implementation sketch:** A tiny client-side controller attaches the existing `<video>` to a dedicated dock via DOM placement and a placeholder marker. One `IntersectionObserver` may update whether the opt-in control is relevant, but must not change playback. State is `inline-playing` / `docked-playing` / `inline-paused-or-ended`; every transition requires an explicit control or native video event. Keep Astro output static and SSR friendly.

## Decorative form and card continuity

Use cards when they distinguish a meaningful unit: architecture steps, observed vs planned status, sponsor levels, or a decision with its own explanation. Avoid wrapping every paragraph or tool name in a tile. Use consistent radii, borders, spacing, and connected edges to establish grouping. An edge may flow into the next card only where sequence or shared grouping is real; use a shared rail, connector, overlapping border, or aligned baseline. Do not use free-floating ellipse outlines as a proxy for flow. Pills are appropriate for short status or tool labels only if they aid scanning.

## Acceptance criteria for implementation

1. No ornamental ellipses remain on hero rules or content cards. Any retained orbit graphic has a clear relationship to nearby explanatory copy or the logo system.
2. Main content remains readable and visible with CSS/JS disabled. No motion is necessary to understand order, meaning, or status.
3. Architecture sequence reads in DOM order at desktop, tablet, mobile, and with a screen reader; connectors never obscure labels or text.
4. If section reveals ship, they trigger once, stay subtle, and are disabled for reduced motion. No scroll handlers or third-party animation packages are added.
5. Video never autoplays. If mini-player ships, only an explicit user action docks it; return and close actions work by keyboard and touch; native playback controls continue working; the video does not duplicate or restart.
6. Mini-player is omitted if it cannot be made reliable on mobile Safari. It must not cover nav, page CTAs, or focused controls.
7. Update Playwright coverage to assert reduced-motion behavior and keyboard operation for any added control. Visual review at 320 px, 390 px, tablet, and desktop confirms no horizontal overflow, occlusion, or content hidden behind the dock.

## Recommended scope for first iteration

Remove decorative ellipses and simplify the orbital background first. Keep the architecture flow static but visually connected. Add only the one-time section reveal if manual review shows it improves orientation. Defer the mini-player until a usability pass confirms that readers want the video to remain visible after starting it; the current inline, user-initiated player is a sound default.
