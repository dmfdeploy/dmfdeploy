# Website repository handoff

The `site/` tree is the source for the two-page Astro website. The dedicated website repository and Git identity are supplied by the project owner outside this public handoff.

## Transfer

1. Start from the latest reviewed `codex/dmfdeploy-io-site` commit with a clean working tree. Check that the dedicated repository is empty and that GitHub authentication is active for the requested account.
2. Clone the dedicated repository. Set its Git author name and email in that clone's local config. Keep account details out of committed website files.
3. Export only the tracked `site/` tree into the clone. `git archive --format=tar codex/dmfdeploy-io-site:site | tar -xf - -C "$SITE_WORKTREE"` produces a clean snapshot without the umbrella repository history. Set `SITE_WORKTREE` to the clone directory first.
4. From the clone, run `npm ci`, `npm run check`, `npm run build`, and `npm run test:visual`. Review desktop and mobile screenshots and verify `/` and `/sponsor`.
5. Commit the imported tree with DCO sign-off and push it to the dedicated repository. Configure Cloudflare Pages with the repository root as the project root, `npm run build` as the build command, and `dist` as the output directory.
6. After the dedicated site is validated, update public source links and site ownership documentation in the umbrella repository through a separate review. Remove the old `site/` copy only after that review.

## Current boundaries

- The film poster is an actual frame from 006, cropped around 00:23 to show the media test-pattern preview. The film itself remains user-initiated.
- The architecture diagram is the intended operations loop. The demonstrated prototype path and proposed capabilities remain labeled separately.
- Sponsorship levels are proposed. The fiscal host, payment route, Open Collective reporting, and corporate invoicing remain unconfirmed or conditional. Do not enable a payment link during the transfer.
