# Site design iteration

This directory records the redesign before it is applied to the Astro pages. The live local site remains a functional two-page prototype. The rejected floating orbit artwork has been removed from that prototype.

## Review package

- [Creative direction](creative-direction.md) compares three approaches and recommends the operational loop.
- [Interaction specification](interaction-spec.md) defines purposeful motion, reduced-motion behavior and the optional film dock.
- [Independent review](design-review.md) identifies changes needed before the mockups become an implementation reference.
- [Homepage mockup](mockups/homepage.html) and [sponsorship mockup](mockups/sponsor-operational-loop.html) are standalone design studies. Their desktop and mobile captures sit beside the HTML files.

The design team covered creative direction, interaction design, visual mockups for each page and independent design review. The second mockup pass addresses the review findings. The mockups are **awaiting design approval**; they do not change the production pages or enable sponsorship payments.

## Second-pass review response

| Review finding | Current mockup response |
|---|---|
| Two separate visual systems | Both pages use the same warm gradient, type stack and [visual tokens](mockups/visual-tokens.md). |
| Sponsor-only decorative edges | The clipped edge and second purple gradient are removed. |
| Unclear architecture return | The homepage labels Prometheus as the source and Console as the destination, with visible direction markers and a text legend. |
| Mobile wayfinding | Both pages use a Sponsor action and a menu that opens the same four primary destinations. |
| Small status text | Essential status labels and values are at least 14px in the revised mockups. |
| Film interaction | The 006 film plays inline after user activation. A floating dock remains an optional behavior specified in the interaction document. |

The final visual decision still belongs to the project owner. The Astro pages have not been changed to match these mockups.

## Local preview

From the `site/` directory, serve a copy containing only the mockups and public media:

```sh
mkdir -p /tmp/dmfdeploy-design-preview/design
cp -R design/mockups /tmp/dmfdeploy-design-preview/design/
ln -sfn "$PWD/public" /tmp/dmfdeploy-design-preview/public
python3 -m http.server 4323 --bind 0.0.0.0 --directory /tmp/dmfdeploy-design-preview
```

Open `/design/mockups/homepage.html` or `/design/mockups/sponsor-operational-loop.html` on port 4323. The preview is a static design artifact; the functional Astro site remains on port 4321. Repeat the copy command after changing a mockup.

## Decision record

1. Retain the project logo, warm brand gradient and headline “A shared foundation for dynamic media.”
2. Remove the free-floating orbit SVG, card ellipses and unrelated decorative motion from the live prototype.
3. Use connected geometry only when it explains the prototype control path or groups related content.
4. Keep the 006 film user-initiated. Any video pop-out needs an explicit opt-in control and a clear return action.
5. Mark sponsorship levels and fiscal arrangements as proposals until verified. Keep inquiry available; leave payment inactive.

The next implementation step is to translate the approved visual system into shared Astro components, then repeat desktop and mobile Playwright review.
