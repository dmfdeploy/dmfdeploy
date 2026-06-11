---
status: executed
date: 2026-06-11
executed: 2026-06-11
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/42
---
# DMF Org .github Slim WP7 Plan 2026-06-11

> **Goal:** stand up the `dmfdeploy/.github` org-default community-health +
> profile repo so GitHub serves fallback files for every repo in the org, and
> new repos inherit a minimum of working-model context from day one.
>
> Tracking: [umbrella issue #42](https://github.com/dmfdeploy/dmfdeploy/issues/42).
> The `.github` repo is live and the operator-applied **org settings**
> (description, branch ruleset, auto-merge) are in place, so this is the
> completing PR: it `Closes #42` and flips `status` to `executed`.

## Scope

### 1. Org profile README + description

- `profile/README.md`: short org-level landing — what the DMF Platform is,
  link to umbrella `docs/WORKING-MODEL.md`, link to Project #1 board.
- Org description (GitHub org settings): one-liner pointing at the platform
  thesis.

### 2. Org-default community-health files (fallbacks)

GitHub serves these when a per-repo copy is absent; **per-repo files always win**.

- **`CODE_OF_CONDUCT.md`** — Contributor Covenant v2.1 (standard text);
  enforcement channel = GitHub's private reporting (Security → Report a
  vulnerability / Report abuse flow), no plaintext email.
- **`SUPPORT.md`** — how to get help: issues (drive-by intake in component
  repos, canonical in umbrella), Discussions (Q&A / RFCs), and the CODEOWNERS
  team.
- **`GOVERNANCE.md`** — decision model: umbrella ADRs, Discussions RFCs,
  CODEOWNERS review, operator as final arbiter on cross-repo scope.
- **`LICENSE`** — Apache-2.0 (canonical; component repos inherit or override).

### 3. New-repo bootstrap checklist

WORKING-MODEL.md gets a new §8 — an ordered checklist that must be run for
every new component repo, because the enforcement net (hooks, rulesets,
required checks, gitleaks/scrub, CI gates) is **per-repo** and not inherited
from the org `.github` defaults. The `.github` defaults only soften the gap
(fallback community-health + profile); they do not enforce.

### 4. Repo hygiene for `.github` itself

- **`CODEOWNERS`** — single rule: `* @dmfdeploy/maintainers`.
- **`LICENSE`** — Apache-2.0.
- **Agent files** (`CLAUDE.md`, `AGENTS.md`, `QWEN.md`) — 2-3 line
  org-default intro + verbatim working-model block from the umbrella template.
- **Branch ruleset** — require PR + 1 approval + linear history.
  **No required status checks** — this repo has no CI; requiring checks would
  block auto-merge indefinitely.
- **Auto-merge** — `automerge.yml` (rebase on approval) + branch auto-delete,
  consistent with WP8 across all repos.
- **`SECURITY.md`** — private vulnerability reporting via GitHub Advisories.

### Out of scope

- Workflow templates (`workflow-templates/`) — deferred.

## Acceptance

- The org profile renders on <https://github.com/dmfdeploy>.
- A new repo created without any of these files still gets the fallback CoC,
  SUPPORT, GOVERNANCE, and LICENSE from `.github`.
- `dmfdeploy/.github` itself has agent files with the working-model block, a
  CODEOWNERS rule, a branch ruleset (PR + approval, no required checks), and
  auto-merge armed.
- WORKING-MODEL.md §8 exists and cites the correct script names from `bin/`.
- The `.github` repo + docs are landed and the org settings applied, so this
  completing PR `Closes #42` and flips this frontmatter to `executed`.
