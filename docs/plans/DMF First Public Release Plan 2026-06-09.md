---
status: executed
date: 2026-06-09
executed: 2026-06-11
---
# DMF First Public Release Plan
> **✅ EXECUTED (adjudicated 2026-06-11, refs issue #32 WP5):** all workstreams
> delivered — A clean-history imports (8 component repos public + CI-green,
> 2026-06-10), B dmf-env scrub, C ADR digests, D GitHub-first governance +
> DCO (ADR-0041), E1 PR-gate CI; umbrella published 2026-06-11 (entrance plan,
> issue #3). Remainder spun out: **E2 release automation = issue #6**.

**Date:** 2026-06-09 · **Status:** Approved (planning only — no release work executed)
**Author:** umbrella session (claude)
**Cross-checked:** codex via agent-bridge — 5 rounds to convergence, closed
**AGREE — no remaining issues** (2026-06-09). Findings marked **[codex]**.
**Supersedes/extends:** `docs/architecture/DMF Release and Contribution Model.md`
(→ ADR-0041 (0018 was already taken by self-managed-k3s-not-ack; next free slot 0041)) and `docs/plans/DMF Release and Contribution Model Implementation
Plan 2026-05-11.md`; resolves that doc's §5 external-contributor TBD.

## Context

We are approaching the first public GitHub release of the DMF Platform. Four
intertwined operator concerns drive this plan:

1. **ADRs are hard to maintain** — current truth is spread across multiple
   partially-superseding documents; but ADR numbers are referenced ~385 times
   across code (dmf-infra 211, dmf-env 74, dmf-runbooks 56, dmf-media 21,
   dmf-cms 20), so renumbering/merging would break those references.
2. **Clean, minimalistic GitHub repos** — mirror from LAN Forgejo like
   `dmf-runbooks`, but publish a single clean line, not the sprawling history
   (umbrella 301 commits, dmf-infra 193, dmf-env 231, dmf-cms 38, etc.).
3. **GitHub-first collaboration** — issues / discussions / PRs become the
   primary surface, to be ready for outside contributors.
4. **A clear CI/CD pipeline** — dev → testing → release mechanics.

Intended outcome: a small set of clean, public, well-governed repos on GitHub
with real PR-based collaboration and automated gates, consolidated docs, and no
leak of pre-publish history or secrets.

## Decisions locked (operator-confirmed)

| # | Decision | Choice |
|---|---|---|
| A | Canonical-source model | **GitHub-canonical-forward** — one clean import; afterward GitHub `main` is the single source of truth. |
| B | dmf-env reproducibility | **Publish a sanitized public `dmf-env`** (keep the name; see §B). |
| C | ADR consolidation | **Digest header in-place** — no renumber, no merge, no deletion. |
| D | CI/CD scope | **Gates first, release automation next.** |

**Core resolution of the clean-history ⇄ GitHub-PRs tension:** the clean cut is
a **one-time import**, after which **Forgejo `main` must STOP being the
full-history branch**. There is exactly **one public DAG**. Forgejo is demoted
to a **downstream mirror / archive only** — it is *not* the upstream of GitHub.
Full pre-publish history lives only in a LAN-only `<repo>-archive` repo. After
import, force-push to `main` is banned; all forward work is GitHub PRs.
**No "Forgejo push-mirror → GitHub" path** — that would re-introduce the old
model and is explicitly rejected **[codex]**.

---

## Pre-flight blockers (must close BEFORE any public flip)

### B. dmf-env → sanitized public `dmf-env` — **the biggest blocker [codex]**
**RESOLVED (operator, 2026-06-09): public is the goal, CONDITIONAL on `dmf-env`
being completely scrubbed of all non-generic / env-specific code.** The
path-allowlist gate below is the gating enforcement — if anything outside the
approved generic surface remains, the publish does not proceed.

`dmf-init` clones `dmf-env` at bootstrap; if it stays private a public user
cannot reproduce/install.
- **Keep the repo + checkout name `dmf-env`.** dmf-init hardcodes the `dmf-env`
  checkout dir in runtime code — `dmf-init/src/dmf_init/bootstrap_steps.py:224`
  (`repos_root/"dmf-env"/"bin/run-playbook.sh"`) and `.../main.py:399`
  (`repos/dmf-env/bin/init-wizard.sh`). A rename would be a runtime migration,
  not a config edit **[codex]**. Do not rename to `dmf-env-tools`.
- Public `dmf-env` = the **sanitized generic surface only** (`bin/`,
  `terraform/modules/`, generic per-provider roots, neutral `tasks/`/`templates/`).
  Per ADR-0035 this surface is designed generic; per-env state lives operator-local
  under `~/.dmfdeploy/envs/<env>/` and is never committed.
- Goes public via the **same clean-history cut as every repo (§A)** — one orphan
  commit drops the secret-bearing history (inventory / TF manifest / OpenBao
  role_id are all in old commits).
- **Reverses old handoff Gate 2** ("dmf-env never public") — that gate predates
  ADR-0035. Needs **explicit operator sign-off** + verification the *current
  tree* scrubs clean.
- **Positive path-allowlist export gate (not just scrub/gitleaks) [codex].**
  Because dmf-env was private by policy, a pattern scrub can miss
  private-but-low-entropy files. Add a dmf-env-specific gate that **fails on any
  path outside the approved generic surface** and **explicitly bans** inventories,
  `envs/`/per-env dirs, `*.tfstate*`, SOPS bundles, SSH key material,
  OpenBao/Shamir material, per-env manifests, and local operator config.
  Allowlist, not denylist — anything unrecognised fails closed.
- dmf-init clone list + CI bundle builder keep cloning `dmf-env`; only the remote
  changes (private Forgejo → public GitHub). No dmf-init code change.
- Update ADR-0035 + ADR-0036 with the decision.

### dmf-promsd — **RESOLVED: publish for v0.1 (operator, 2026-06-09)**
dmf-promsd is already in the dmf-init **runtime repo set**
(`dmf-init/bin/build-bundle.sh:37`, `dmf-init/src/dmf_init/repos.py:22`). Decision:
**publish it.** Add to `sync-to-github.sh` whitelist + `github_repo_name()` + the
import set; give it the same governance + CI + clean-history treatment as every
other public repo.

### Final public set (RESOLVED)
9 GitHub repos: `dmfdeploy` (umbrella), `dmf-cms`, `dmf-runbooks`,
`dmf-central`, `dmf-infra`, `dmf-media`, `dmf-init`, **`dmf-env` (sanitized)**,
**`dmf-promsd`**. The `dmf-env` private full-history repo is retired to
`dmf-env-archive` (LAN-only); each repo's pre-publish history is likewise
preserved in `<repo>-archive` (see §A.9).

### dmf-runbooks is already public at v0.1.2 — do not rewrite **[codex]**
It is already on the clean public DAG. Release **forward** from v0.1.2; never
republish v0.1.0 or rewrite history (breaks public trust + any forks). It is the
reference for the forward model.

---

## Workstream A — Clean history + canonical flip (per repo, except dmf-runbooks)

Publish from a **clean export worktree**, never by mutating the live repo in
place (avoids archive-by-tag fragility — a stray full-history `refs/heads/main`
mirror would leak old commits **[codex]**):

1. **Freeze writes** on the repo; pause agent dispatch.
2. Create LAN-only `<owner>/<repo>-archive` on the LAN Forgejo holding the full pre-publish
   history (replaces the fragile single-repo `archive/*` tag).
3. **Export-scan harness (new tooling).** Current gates assume repos under
   `UMBRELLA_DIR/$repo/.git` and silently skip missing repos
   (`bin/scrub-public-repos.sh:146`, `bin/check-public-commit-authors.sh:66`).
   Add a harness that stages each clean export under a predictable path and runs
   **scrub + commit-author + gitleaks `--no-git` + check-public-repo-hygiene.sh**
   against *that exact tree* **[codex]**.
4. Stage the clean export from current `main` tip, and **bake governance + CI
   files INTO that tree before the orphan commit** — `CONTRIBUTING.md`,
   `SECURITY.md`, `.github/CODEOWNERS`, `.github/ISSUE_TEMPLATE/`,
   `.github/PULL_REQUEST_TEMPLATE.md`, `.github/workflows/` (Workstreams D + E1).
   Then orphan/squash → one `Initial public release vX.Y.0` commit, so the public
   repo starts from **exactly one scanned commit** — no post-import governance
   commit series **[codex]**.
5. Run the export-scan harness on that exact tree (+ the dmf-env path-allowlist
   gate, §B, for `dmf-env`).
6. Create the GitHub repo **private first**; push clean line + release tag;
   verify: **1 commit**, correct tag, **no `archive/*` refs, no old commits**.
7. Configure **GitHub-side settings**: branch ruleset on `main` (linear history,
   required checks, **no direct push, no force-push**); **tag ruleset [codex]**
   (protect `v*` from update/delete except release automation, **restrict tag
   creation**, **block `archive/*` / any non-release tag** — closes the
   `refs/tags/archive/*` leak a stale clone could hit via `git push --tags`);
   Actions permissions (`read-all`, no PR-job secrets, E1).
   - **RESOLVED: `dmfdeploy` is on GitHub Free (operator, 2026-06-09).** Rulesets
     on Free apply only to **public** repos, so the **locked-window flip** is the
     path [codex]: import private → verify (step 6) → **flip public into a locked
     window (owner-only, no collaborators, no further pushes)** → **immediately**
     configure branch + tag rulesets + native secret scanning + push protection →
     **verify a test `git push --tags` is rejected** → only then add collaborators
     / accept PRs. The one-scanned-commit model is unchanged.
8. **Flip public** (per the tier branch); enable native GitHub **secret scanning +
   push protection** (Workstream D.3) at/immediately-after flip.
9. **RESOLVED: retire-to-archive (operator, 2026-06-09).** Retire the live
   Forgejo repo; its complete pre-publish history is preserved **permanently** in
   LAN-only `<owner>/<repo>-archive`. The operator wants **agents to retain access to
   the full commit history to inform future decisions** — so:
   - Keep every `<repo>-archive` indefinitely (do not delete).
   - Working clones repoint `origin` → GitHub (canonical forward), and add a
     read-only **`archive`** remote → the LAN Forgejo `<owner>/<repo>-archive` so
     `git log archive/main` / `git fetch archive` exposes the pre-publish history
     locally.
   - Document the `archive` remote convention in `CLAUDE.md` + `STATUS.md` so
     future agents know where history lives.
   Forgejo is **archive-only**, never the GitHub upstream. Stop all squash-mirror
   force-pushes.

> **`sync-to-github.sh` is an import tool, not the steady-state path [codex].**
> It hardcodes `v0.1.0`, excludes dmf-promsd, skips gitleaks if the binary is
> absent, and its commit-author allowlist rejects external contributors. Use it
> (or a one-shot variant) for the initial import only, then **retire/replace it**.
> Steady state = normal PR-merge to GitHub `main`.

---

## Workstream C — ADR consolidation (digest-in-place)

Readers get consolidated current-truth; the ~385 in-code refs keep resolving.
**Numbers are immutable IDs. No renumber, no merge, no deletion.**

1. Keep all 41 ADR files + numbers in place.
2. Add per-theme **canonical digest** docs under `docs/decisions/digests/`, one
   per over-fragmented cluster (mapping already in INDEX "Theme clusters"):
   identity (canon 0028), catalog/execution (canon 0013+0025+0038),
   secrets/unseal (canon 0029+0009), deployment/release (canon 0031).
3. Add a prominent **status / canonical-pointer header block** atop each
   superseded / partially-superseded ADR (full body preserved below — **not**
   stubbed; refs may rely on the detail, not just the anchor **[codex]**).
4. **Audit a sample of the 385 code refs** — confirm they cite a stable
   decision/anchor, not obsolete semantics; fix any now-wrong ones. ("No code
   touched" is too strong **[codex]**.)
5. Close portfolio-review nits (2026-05-27): ADR-0011 forward-pointer to 0031;
   fix ADR-0030 dangling "ADR-0028 coupling"; correct ADR-0020 stale 0028/0029
   numbering; reconcile INDEX "no gaps" wording with the 0029 reserved slot.

Doc-only; decoupled from publish work; **land first as a low-risk warm-up.**

---

## Workstream D — GitHub-first collaboration governance

GitHub-canonical removes the Forgejo scrub airgap — issues, PR bodies, diffs,
Actions logs, review comments all become leak surfaces **[codex]**. Per public repo:

1. **Rewrite `CONTRIBUTING.md`** (exists but written for the OLD Forgejo-canonical
   / "no direct push to GitHub" / mothballed-Constitution model, still says "5
   sibling repos"). New: GitHub-first PR flow, topic-branch naming, Conventional
   Commits, MUST/MUST-NOT distillation, no-secrets posture. **Carry forward the
   existing rules** from `CONTRIBUTING.md` + `DMF Release and Contribution
   Model.md` §5–§7 (operator-flagged — they are folded in, sourced from those two
   docs).
2. **`SECURITY.md`** + GitHub **private vulnerability reporting** + coordinated
   disclosure procedure.
3. **Secret scanning + push protection:** native GitHub features may require
   GitHub Secret Protection and may not be configurable while private **[codex]**.
   Keep **local + Actions** gitleaks/scrub as the **private pre-flip gate**;
   enable native scanning + push protection **on the public flip** (A.7–A.8).
4. **Issue + PR templates** (`.github/`) with a "never paste secrets / IPs /
   operator identity" banner; PR checklist (VERSION bump, Conventional Commit,
   gates green).
5. **CODEOWNERS** — present in all 7; confirm coverage; sanitized `dmf-env`
   inherits the high-risk-path rules.
6. **Discussions** for design Q&A; issues for actionable work.
7. **Maintainer leak-runbook** — rotate / purge / the one sanctioned
   history-rewrite procedure for an accidental public leak.
8. **RESOLVED: DCO (operator, 2026-06-09).** Use the Developer Certificate of
   Origin — require `Signed-off-by:` on every commit, enforced by a DCO check on
   PRs (DCO GitHub App or an Actions check). No CLA. Wire it **before** accepting
   any external PR; document `git commit -s` in `CONTRIBUTING.md`.
9. Promote `DMF Release and Contribution Model.md` → **ADR-0041 (Accepted)** once
   §5 (this plan) + §8 enforcement rows are satisfied.

---

## Workstream E — CI/CD (dev → test → release)

**E1 — PR gates + protection (before flip).** GitHub Actions, **hosted runners
only** (`ubuntu-24.04` / `ubuntu-24.04-arm`) — never self-hosted on public repos
(fork-PR RCE). The dmf-init Forgejo workflow is host-agnostic and ports with a
`runs-on:` change.
- PR checks: `gitleaks`, `scrub-public-repos.sh`, lint (per stack), `commitlint`
  (Conventional Commits), `trivy` fs scan.
- **Fork-PR hardening [codex]:** `pull_request` (never `pull_request_target`);
  default `permissions: read-all`; **no secrets on PR jobs**; require approval for
  first-time contributors; **pin third-party actions by SHA**; run scanners from a
  base-branch / locked **reusable workflow** so a PR can't weaken its own checker.
- **Runner ceiling [codex]:** public hosted arm runner ≈ 4 CPU / 16 GB /
  **14 GB disk** (private: 2 CPU / 8 GB). Validate the dmf-init bundle image build
  against the 14 GB disk ceiling before relying on hosted CI for it.
- Branch protection: linear history, required checks, no direct push, no
  force-push. Trunk-based by default (no `develop` unless cadence demands it).

**E2 — release automation (after flip).**
- `release.sh` per repo: VERSION bump → `vX.Y.Z` tag → CHANGELOG (Conventional
  Commits) → GHCR image / release asset. Reuse the dmf-init artifact-publish step.
- **Umbrella release manifest [codex]:** per-repo `release.sh` alone is too
  decentralized for 9 repos — one could ship valid-SemVer but set-incompatible.
  Add an umbrella compatibility manifest (pinned per-repo SHAs/versions) as the
  release-set gate; tag/publish each repo from its pin.

---

## Master sequencing (codex-corrected)

Public set = 9 repos incl. `dmf-promsd` + sanitized `dmf-env`; org on **GitHub
Free** → locked-window flip; **DCO**; **retire-to-archive**.

1. **Freeze writes**; pause agent dispatch.
2. **Workstream C** (ADR digests) — doc-only, land first.
3. **Workstream B** — sanitize `dmf-env` to the generic surface (allowlist gate);
   confirm dmf-init clones it unchanged.
4. **Build the export-scan harness** (+ dmf-env allowlist gate); **bake
   governance + CI files into each export tree** (+ **DCO** check wiring);
   orphan-commit; **scan exact trees**.
5. **Import to PRIVATE GitHub repos**; verify 1 commit / no archive refs / no old commits.
6. **Flip public into the locked window** (Free tier: owner-only, no pushes), then
   **immediately** configure branch + **tag ruleset** (protect `v*`, block
   `archive/*`) + Actions permissions + native secret scanning + push protection;
   **verify `git push --tags` is rejected**.
7. **Retire Forgejo → `<repo>-archive`** (kept permanently; add the `archive`
   remote for agent history access). Stop force-pushes.
8. **Accept PRs** (DCO check live); build E2 release automation + umbrella manifest.

## Critical files

- Tooling: `bin/sync-to-github.sh` (retire post-import), `bin/scrub-public-repos.sh`,
  `bin/check-public-commit-authors.sh`, `bin/check-public-repo-hygiene.sh`,
  `bin/generate-status.sh`; **new** export-scan harness + dmf-env allowlist gate.
- dmf-init coupling: `dmf-init/bin/build-bundle.sh:37`,
  `dmf-init/src/dmf_init/repos.py:16-30`,
  `dmf-init/src/dmf_init/bootstrap_steps.py:224`, `dmf-init/src/dmf_init/main.py:399`.
- ADRs: `docs/decisions/INDEX.md`, `docs/decisions/00{04,11,16,20,24,30}-*.md`,
  new `docs/decisions/digests/*.md`.
- Governance: per-repo `CONTRIBUTING.md`, `.github/CODEOWNERS`, **new**
  `SECURITY.md`, `.github/ISSUE_TEMPLATE/`, `.github/workflows/`.
- Source-of-truth: `docs/architecture/DMF Release and Contribution Model.md` → ADR-0041.

## Verification

- **Per-repo pre-flip:** export-scan harness exits clean on a tree that **already
  contains the governance + CI files**; GitHub private repo shows exactly **1
  commit** + the release tag, **no `archive/*`, no old commits**. Tag-protection
  ruleset rejects a test `git push --tags`.
- **dmf-env allowlist gate** fails closed on a planted out-of-surface path (e.g.
  a stray `inventories/` or `*.tfstate`).
- **dmf-init repro:** with `dmf-env` (+ dmf-promsd per choice) public, a clean
  `build-bundle.sh` from public remotes builds the bundle image and boots
  (`/healthz` ok) — proving a public user can reproduce.
- **Governance:** a test fork PR triggers PR gates with **no secret access** +
  read-only token; secret-scanning push-protection blocks a planted secret;
  DCO/CLA check fires on the PR.
- **ADR digests:** sampled code refs still resolve; INDEX clusters point to live
  digest docs.

## Out of scope / not done now

No history rewrites, repo splits, ADR edits, GitHub org/repo creation, or CI
files until execution is greenlit per workstream. ("Do not make changes for now.")

## Operator calls — ALL RESOLVED 2026-06-09

- **dmf-promsd:** ✅ publish for v0.1.
- **dmf-env public:** ✅ yes — conditional on a complete scrub to the generic
  surface (allowlist gate enforces).
- **DCO vs CLA:** ✅ DCO (`Signed-off-by:` + PR check).
- **Forgejo after flip:** ✅ retire-to-archive; `<repo>-archive` kept permanently;
  agents reach history via an `archive` remote.
- **GitHub org tier:** ✅ Free → locked-window flip path (A.7).

No operator decisions remain open. Execution is gated only on the operator's
go-ahead to start (Workstream C is the low-risk first slice).
