# Independent design and accessibility review

**Review scope:** Iteration 1 homepage and sponsorship mockups, their desktop/mobile screenshots, and `creative-direction.md`
**Reviewer:** Independent art direction and accessibility review
**Date:** 2026-10-28

## Overall assessment

The two pages share a useful dark technical canvas, restrained rules, and a warm hero entry, but they do not yet read as one finished design system. The homepage is expressive and display-led; the sponsorship page is more conventional and uses a different type and color treatment. The mockups are strong enough to guide a next iteration, but their visual tokens and navigation need to converge before implementation.

The strongest visual proof is the homepage architecture track. Its connector has a stated control path and return-state label, so it communicates a real relationship better than the removed orbital decoration. The return curve still needs clearer direction and endpoints to avoid reading as a bracket around the stages.

## Prioritized fixes

### 1. Unify the two page systems

- **Color:** the homepage establishes a pink-to-orange field; the sponsor hero shifts to pink-to-purple, and the sponsor closing section introduces another purple gradient. Keep one shared warm gradient and use the same transition into the dark canvas on both pages.
- **Type:** the homepage declares an Inter/Avenir/system stack, while the sponsor page declares Arial/Helvetica. Adopt one stack and shared heading, body, metadata, and line-length tokens. The homepage's heavy display face and the sponsor page's more ordinary sans currently feel like separate products.
- **Navigation:** the homepage hides its entire navigation on mobile; the sponsor page retains only a “Get in touch” action. Give both pages the same compact, discoverable mobile navigation pattern and consistent active-page/focus treatment.
- **Shared components:** align button heights, border treatment, focus rings, spacing scale, and panel corners. The rounded video window, square architecture frame, status box, sponsor rows, and angled hero cut currently lack a single shape rule.

### 2. Remove the remaining decoration without a job

The sponsor hero's clipped zig-zag bottom edge has no relationship to the content and interrupts the otherwise calm layout. The purple close-section gradient is also a second atmospheric effect without a distinct meaning. Remove both or make the boundary transition a single, consistent section treatment. Keep the homepage's warm gradient as the brand field and its video as the hero proof object.

The current hierarchy does not need more ellipses. Keep the actual logo geometry and use curves only where they connect meaningful groups or paths.

### 3. Make the control-path drawing directional

The four numbered stages are aligned by a fine line and the label “Control path”; the lower return line is labeled “Observed state returns to the console.” That makes the intended relationship legible, but the desktop U-shaped line spans the full sequence without an arrowhead or a clear origin at Prometheus and destination at Console. It reads partly as an enclosing bracket. Draw the return path from the observation stage back to the console, mark direction at its endpoint, and distinguish command and observation paths with labels or line styles. On mobile, attach the return connector to the final stage and show its destination at the first stage; do not leave it as a detached vertical stroke below the list.

Preserve the caveat that this is the demonstrated v0.1 path and not a production broadcast plant. Make the line legend/status available in text so color is not the only distinction.

### 4. Improve mobile wayfinding and reading comfort

- Keep a visible, keyboard-accessible route to Project, Architecture, Status, and Sponsorship on both pages. The homepage currently has no navigation at all at the narrow breakpoint.
- The sponsor page's horizontal section-jump row is scrollable but hides its scrollbar and gives no cue that more links continue offscreen. Prefer a wrapping list or add a clear scroll affordance and ensure keyboard users can reach every item.
- Several metadata labels and sponsor-status values are set at 11–12px with wide tracking. Raise essential status text to at least 14px where layout permits; reserve smaller text for nonessential indices.
- Add a visible `:focus-visible` treatment to links and buttons in both standalone mockups. Preserve logical heading order and ensure the play control remains a real keyboard-operable button when the video behavior is specified.

### 5. Keep the video interaction explicit

The homepage poster is prominent and appropriately treated as evidence, but its play button is only a visual affordance in this standalone mockup. For the next prototype, define the activated state: user-initiated playback, captions when available, keyboard-operable close/restore controls if it becomes a floating player, and no autoplay with sound. If scroll-triggered pop-out is retained, trigger it only after the user starts playback and when the inline player leaves view; offer a clear close action and respect reduced motion.

## Typography and spacing notes

The homepage headline is memorable and the desktop two-column hero has good balance. Across the long pages, however, the repeated very large headings and uppercase section labels create a launch-campaign rhythm. Use the sentence-case hierarchy proposed in `creative-direction.md`, keep eyebrow labels for section indexing only, and give paragraphs enough width to avoid overly short line wraps. On mobile, the sponsor layout stacks cleanly, but the one-column length and repeated section labels make it feel dense; keep spacing consistent and group related funding details without shrinking body text.

## Decision summary

Advance the operational-loop direction with a shared typography/color/component system. Keep the real architecture stages and project-video poster as evidence. Remove the sponsor-only clipped hero edge and secondary purple atmosphere, unify mobile navigation, and redraw the observation return as a directional connection with visible endpoints. No extra decorative ellipse system is needed.

## Second-pass check

The main visual findings are resolved: both pages now use the same warm gradient and declared type stack, share the compact mobile Sponsor/Menu header, keep the sponsor section links visible as a wrapping list, and use more readable status text. The sponsor-only clipped hero edge and closing purple gradient are gone. The architecture return now has explicit Prometheus-to-Console labels, direction markers, and a text legend; it reads as a relationship rather than a bracket. The remaining circles belong to the numbered stages or the brand mark, and I see no free-floating decoration in the screenshots.

The desktop and mobile mockups now read as one two-page reference with consistent color, hierarchy, navigation, and spacing. There is no visual blocker to seeking design approval. One interaction remains an open design choice: the video plays inline after activation, but the optional floating/pop-out state is not shown or implemented. The mobile menu also hides a focused link after navigation; return focus to its toggle if the menu is later used for same-page navigation.

## Third-pass correction

The final 006 film replaces the earlier four-box control path as the architecture reference. The homepage now draws Operations, Automation, Facility, Observability and Source of truth as an open loop with directional arrows. The dotted return identifies the planned delta path. A separate mobile drawing keeps the labels readable. Copy on both pages has been shortened, and the sponsorship path has one email inquiry while fiscal hosting and payment remain unconfirmed. The functional local site now carries the same architecture model for review.
