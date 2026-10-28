# Site design iteration

The current homepage and sponsor mockups are linked below. The local Astro site is a functional two-page prototype; sponsorship payment remains inactive.

## Review files

- [Creative directions](creative-direction.md), [interaction specification](interaction-spec.md), and [design review](design-review.md)
- [Homepage mockup](mockups/homepage.html): [desktop](mockups/homepage-desktop.png) and [mobile](mockups/homepage-mobile.png)
- [Sponsor mockup](mockups/sponsor-operational-loop.html): [desktop](mockups/sponsor-operational-loop-desktop.png) and [mobile](mockups/sponsor-operational-loop-mobile.png)
- [Website repository handoff](website-repository-handoff.md) records the transfer and deployment checks.

## Current decisions

1. Keep the project logo, warm gradient and “A shared foundation for dynamic media” headline.
2. Use the five-node operations loop in the final 006 film as the architecture reference. Oval nodes and arrows explain the path; the dotted return marks a capability still to prove. Mobile has its own layout. Remove the earlier square architecture cards and unrelated orbit decoration.
3. Keep copy short and label demonstrated work separately from proposed capabilities. The sponsor page shows indicative annual levels, unconfirmed fiscal hosting, conditional reporting and invoicing, and one email inquiry. No payment link is active.
4. Use the 006 film with an explicit play action. A floating player is an optional interaction for a later iteration.
5. Use an actual dark frame from the 006 film as its thumbnail. Let sections share the dark canvas; keep rules inside lists where they explain relationships.

The overall visual direction remains open for project-owner review. The loop and copy corrections have been applied to the local Astro prototype for comparison.

## Local network preview

The functional site runs on port `4321`; the standalone mockups run on port `4323`. To refresh the mockup server from `site/`:

```sh
mkdir -p /tmp/dmfdeploy-design-preview/design
cp -R design/mockups /tmp/dmfdeploy-design-preview/design/
ln -sfn "$PWD/public" /tmp/dmfdeploy-design-preview/public
python3 -m http.server 4323 --bind 0.0.0.0 --directory /tmp/dmfdeploy-design-preview
```
