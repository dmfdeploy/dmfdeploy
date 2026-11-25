---
status: active
date: 2026-11-25
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/1010
---

# Staying current plan

This plan keeps the platform's tool versions current without a manual hunt for
what is behind. It closes
[#1010](https://github.com/dmfdeploy/dmfdeploy/issues/1010), and it sets the
properties that each step must meet. The decisions come from the operator
(2026-11-25). The version policy that they follow is in the RFC and the ADR
that this plan's step 1 produces.

## Decisions

- **Stay current by default.** A pin holds the current version, or it carries a
  one-line hard reason next to it. Version coupling and "not yet tested" are not
  reasons to stay behind.
- **In-place upgrade starts at v1.0.** Until then `main` may break, and an
  environment is rebuilt. v1.0 has no milestone yet, and the dmf-init default
  refs stay `main` until v1.0.
- **A batch install every two weeks.** The automatic lane runs weekly.
- **Every major version in the survey moves,** in two batches. The next section
  names them.
- **A changelog break is a named blocker.** Before a major version moves, search
  its changelog for a break in something the platform uses. A break sends the
  item to a named-blocker issue. The item is recorded and not dropped.
- **Two items are decisions and not moves.** Promtail (upstream retired it) and
  the AWX control-plane image each get a decision issue.
- **Fedora follows the newest release.** The execution environment base is the
  newest released Fedora, and the base refreshes when the next Fedora ships.

## Batches

- **Batch 1:** the ignore rules go, and everything behind moves inside its
  current major line. One install proves it, and its passing closes #1010.
- **Batch 2:** the major groups, under a new tracking issue, with its own
  install. The groups are:
  - k3s 1.33 to 1.37, with kubectl and the Python `kubernetes` library
  - NetBox 4.5 to 4.7 (chart 8), with `pynetbox`
  - PostgreSQL 16 to 19
  - Forgejo 14 to 17
  - Debian 12 to 13
  - Authentik 2026.2 to 2026.8
  - Traefik chart 39 to 43, with the values migration
  - Grafana chart to current, from its new upstream repository
  - the observability charts (Prometheus, Loki, LibreNMS, Blackbox, MetalLB,
    Hetzner CCM)
  - Helm 3 to 4
  - the dmf-cms frontend majors (TypeScript 7, zustand 5, react-router 8)
  - the Cloudflare Terraform provider 4 to 5

## Lanes

- **Automatic:** CI proves the update, and it merges on green checks. This
  covers GitHub Actions, linters, CI scanners, and development dependencies.
- **Batched:** only a cluster proves the update. It merges on green checks, and
  one fresh install proves the whole batch.
- **Decision:** the update raises a question about the component itself.

## Review and proof

- One tool per commit. The three scanners in one repository's guard workflow
  count as one tool.
- Minor and patch updates: one PR per repository per batch, with one commit per
  tool, so parking a tool is one revert. Each major group is its own PR.
- Past 35 PRs in total, the work stops for a simplify-or-park choice.
- A batch gets one fresh install for proof. Batch 1 gets at most two attempts,
  and batch 2 at most three. After that, the operator decides.
- A major that fails and needs more than one small fix returns to its old pin
  and gets a named-blocker issue.

## Steps

### Step 0, scanners and the execution environment base

Lands first and waits for nothing else.

- The three scanners (gitleaks, trivy and actionlint) are current in all nine `guard.yml` files, each
  checksum taken from the release's official checksum file.
- The execution environment builds on the newest released Fedora. It is
  verified locally, published by the operator, and then consumers switch to it.
  The switch is a separate PR that stays held until the image is published.
- A CI leg that mirrors the execution environment's Python moves with it, in the
  same step.

### Step 1, policy

An RFC in Discussions, then an ADR. The ADR also moves the in-place-upgrade
trigger in `docs/OPEN-QUESTIONS.md` and the v0.1 commitment plan to v1.0.

### Step 2, closing the gaps

- The blanket major-version ignore rules leave all nine Dependabot
  configurations, and so does the stale `ansible >= 15` ignore in dmf-media and
  dmf-central.
- A trial runs Renovate in report-only mode on dmf-infra. If its report covers
  the survey rows for the pins that nothing proposes, it replaces a list
  workflow. If it doesn't, one scheduled workflow in the umbrella, built with
  GitHub's own tools, opens or updates one issue that lists those pins.
- Turning the bot on to open PRs needs a token from the operator. Whether it
  replaces Dependabot's version updates is a later decision.

### Step 3, batch 1

Everything behind moves inside its current major line, then one fresh install
proves it, with the controller and execution environment versions recorded side
by side.

### Step 4, batch 2

The major groups, each as its own PR, then one fresh install.

## Pull requests

Titles are conventional commits. Every body says `Refs dmfdeploy/dmfdeploy#1010`
until the completing PR, which says `Closes dmfdeploy/dmfdeploy#1010`.

| Step | Repository | Tool | PR title |
|---|---|---|---|
| 0 | dmf-infra, dmf-runbooks, dmf-init, dmf-env, dmf-cms, dmf-media, dmf-promsd, dmf-central, dmfdeploy | the guard workflow (gitleaks, trivy, actionlint) | `ci(guard): move gitleaks, trivy and actionlint to current releases` |
| 0 | dmf-infra | execution environment base | `build(ee): move the execution environment base to Fedora 45` |
| 0 | dmf-infra | execution environment tag, held until publish | `chore(ee): switch the awx execution environment to 0.5.0` |
| 0 | dmf-runbooks | CI leg that mirrors the execution environment's Python, held until publish | `ci: move the ee leg to the execution environment's Python` |
| 2 | nine repositories | Dependabot configuration | `ci(dependabot): remove the blanket major-version ignore` |
| 2 | dmf-infra | Renovate report-only trial | `ci(renovate): add a report-only trial` |
| 2 | dmfdeploy | scheduled list workflow, only if the trial falls short | `ci: list the pins that nothing proposes` |
| 3 | one per repository that has a minor or patch move | one commit per tool | `chore(deps): bring <repository> current inside its major lines` |
| 4 | one per major group | the group's tools | `chore(deps): move <group> to <version>` |

Batch 1 and batch 2 rows are counted when the batch starts, from the survey.

## Done when

- #1010's own done-when holds: steps 1 to 4 of its order have merged, and one
  fresh install has run on the new ansible-core with the controller and
  execution environment versions recorded side by side.
- No ignore rule holds a version back without a named reason.
- The scheduled check, or the Renovate report that replaces it, is running.
- The batch 1 install passed, with the controller and execution environment
  versions side by side.
- Each parked major has a named-blocker issue.
