---
status: active
date: 2026-10-28
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/803
---
# dmfdeploy.io local site plan

Build a reviewable, static two-page site in `site/` in the umbrella checkout.
The local prototype uses the Control plane design studies from the content
repository. The repository location is provisional; publishing and payment
activation are separate decisions.

## Sources and claim boundaries

- `README.md` and `docs/THESIS.md` define the project purpose, current proof,
  and open independent-reproduction test.
- `ROADMAP.md` defines the three outcome milestones. It gives no dates.
- `CONTRIBUTING.md` and ADR-0041 define the public RFC, ADR, PR, and DCO
  process. A founder-protected sponsorship charter is a proposal.
- The user supplied the four proposed annual levels: €1,000, €5,000,
  €15,000, and €25,000+. No tier buys technical control.
- Fiscal hosting, Open Collective reporting, invoicing, and payment links
  remain unconfirmed or inactive. The verified inquiry address in film 006
  is `inquiries@dmfdeploy.io`.

## Build

Use Astro's static output, Tailwind CSS, and TypeScript. Keep navigation and
video playback native where possible. Add only the small client scripts needed
for the mobile menu and film play control. A web-sized derivative of the
publish-cleared film 006 and its dedicated poster support local playback.
All page content builds into static files for a future Cloudflare Pages review.

The homepage covers the problem, broad project vision, simplified current
architecture, standards and tools, status, governance, and participation.
The sponsor page covers the industry case, roadmap-aligned funding priorities,
proposed levels, independence, financial readiness, and corporate inquiry.
The homepage sponsorship CTA routes to `/sponsor`.

## Verification

Run Astro's check and static build. Use Playwright at desktop and mobile widths
to inspect full-page screenshots and verify navigation, film playback, the
inquiry link, tier labels, and the absence of payment actions. Check focus,
reduced motion, contrast, overflow, and readable mobile text. Compare the
rendered pages with the design studies and refine visible differences.

The two routes, mobile menu, 30-second film, inquiry links, and proposed tier
labels were checked locally. Playwright captured full-page desktop and mobile
screenshots and checked 320-pixel overflow. No payment path is implemented.
The site stays unpublished while the fiscal host and sponsorship terms are
reviewed.
