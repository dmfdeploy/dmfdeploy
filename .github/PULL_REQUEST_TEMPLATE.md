<!--
⚠️ NEVER paste secrets, credentials, real IPs/DNS, kubeconfigs, Terraform state,
or operator identity into this PR. Use placeholder syntax (<control-node-public-ip>,
dmf.example.com, <handle>). CI gitleaks/scrub will block a leak — but it is your
responsibility first.
-->

## What & why

<!-- One paragraph: what this changes and the motivation. -->

Refs dmfdeploy/dmfdeploy#NNN

<!-- Replace NNN with the issue number. Keep the full dmfdeploy/dmfdeploy prefix, and use "Closes" in place of "Refs" if this is the last PR for the issue. For a change with no issue, ask a maintainer for the `no-issue` label. -->

## How it's tested

<!-- The commands you ran and what they showed, so a reviewer can rerun them. Match the evidence to the change: see "Match the evidence to the change" in CONTRIBUTING.md. If no test applies, say why. -->

## Checklist

- [ ] The PR has one `component:*` label and one `workstream:*` label (see [`docs/WORKING-MODEL.md`](docs/WORKING-MODEL.md) section 2).
- [ ] The description has a fully qualified issue reference: `Refs dmfdeploy/dmfdeploy#N`, or `Closes dmfdeploy/dmfdeploy#N` if this is the last PR for the issue. A bare `#N` points at the wrong repo.
- [ ] Commits are **signed off** (`git commit -s`; DCO). The DCO check verifies them.
- [ ] Commit messages follow **Conventional Commits** (`feat:`/`fix:`/`docs:`/…).
- [ ] `VERSION` bumped if this is a release-tagged change (ADR-0005); otherwise N/A.
- [ ] No secrets / real IPs / DNS / operator identity anywhere in the diff or this PR.
- [ ] The checks in [Develop and test](https://github.com/dmfdeploy/dmfdeploy/blob/main/CONTRIBUTING.md#develop-and-test) that match this change pass, or the description says why they were not run.
- [ ] CI is green (gitleaks, scrub, lint, commitlint where applicable).
- [ ] Docs/ADRs updated if behavior or decisions changed.
- [ ] Docs gate: `bin/check-docs.sh` passes, and a plan doc's frontmatter is updated in this PR if the PR completes it.
- [ ] Checked the governing ADRs for the area I changed (see [`docs/decisions/INDEX.md`](docs/decisions/INDEX.md) → ★ Start here).
