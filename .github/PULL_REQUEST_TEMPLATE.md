<!--
⚠️ NEVER paste secrets, credentials, real IPs/DNS, kubeconfigs, Terraform state,
or operator identity into this PR. Use placeholder syntax (<control-node-public-ip>,
dmf.example.com, <handle>). CI gitleaks/scrub will block a leak — but it is your
responsibility first.
-->

## What & why

<!-- One paragraph: what this changes and the motivation. Link issues with "Closes dmfdeploy/dmfdeploy#NNN". -->

## How it's tested

<!-- The commands you ran and what they showed, so a reviewer can rerun them. If no test applies, say why. -->

## Checklist

- [ ] The PR has one `component:*` label and one `workstream:*` label (see [`docs/WORKING-MODEL.md`](docs/WORKING-MODEL.md) section 2).
- [ ] The description has a fully qualified issue reference: `Refs dmfdeploy/dmfdeploy#N`, or `Closes dmfdeploy/dmfdeploy#N` if this is the last PR for the issue. A bare `#N` points at the wrong repo.
- [ ] Commits are **signed off** (`git commit -s`; DCO). The DCO check verifies them.
- [ ] Commit messages follow **Conventional Commits** (`feat:`/`fix:`/`docs:`/…).
- [ ] `VERSION` bumped if this is a release-tagged change (ADR-0005); otherwise N/A.
- [ ] No secrets / real IPs / DNS / operator identity anywhere in the diff or this PR.
- [ ] CI is green (gitleaks, scrub, lint, commitlint where applicable).
- [ ] Docs/ADRs updated if behavior or decisions changed.
- [ ] Docs gate: `bin/check-docs.sh` passes, and a plan doc's frontmatter is updated in this PR if the PR completes it.
- [ ] Checked the governing ADR(s) for the area I changed (see [`docs/decisions/INDEX.md`](docs/decisions/INDEX.md) → ★ Start here).
