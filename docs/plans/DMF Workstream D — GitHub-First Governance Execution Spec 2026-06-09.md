---
status: executed
date: 2026-06-09
executed: 2026-06-09
---
# DMF Workstream D — GitHub-First Governance Execution Spec
> Supersedes: [DMF Release and Contribution Model Implementation Plan 2026-05-11.md](DMF%20Release%20and%20Contribution%20Model%20Implementation%20Plan%202026-05-11.md)

**Date:** 2026-06-09 · **Status:** Draft for codex cross-check → qwen lift
**Author:** umbrella session (claude, orchestrator)
**Parent plan:** [`DMF First Public Release Plan 2026-06-09.md`](DMF%20First%20Public%20Release%20Plan%202026-06-09.md) §Workstream D
**Resume handoff:** `docs/handoffs/DMF First Public Release — C+B Done, A-D-E Next — Handoff 2026-06-09.md`

> **This spec is self-contained.** A lifting agent (qwen-left) should be able to
> execute it end-to-end without reading other docs, using only the templates and
> the per-repo substitution table below. Where a file must be copied verbatim
> from an existing repo, the source path is given explicitly.

---

## 0. Scope & non-goals

**In scope (this workstream produces governance + CI-governance files, on `main`
of each repo, as normal forward commits — NO history rewrite):**

1. Rewrite `CONTRIBUTING.md` in all **9** public repos to the **GitHub-canonical-forward**
   model (the existing ones describe the retired Forgejo-canonical / "no direct push
   to GitHub" / `sync-to-github.sh`-only / mothballed-Constitution / "five sibling
   repos" model — all stale).
2. Add `SECURITY.md` + GitHub **private vulnerability reporting** language to all 9.
3. Add `.github/ISSUE_TEMPLATE/` (bug + feature + `config.yml`) and
   `.github/PULL_REQUEST_TEMPLATE.md` to all 9, each carrying the **"never paste
   secrets / IPs / operator identity"** banner.
4. Add a **DCO check** workflow (`.github/workflows/dco.yml`) to all 9 and document
   `git commit -s` in every `CONTRIBUTING.md`.
5. **CODEOWNERS:** **normalize all to `@dmfdeploy/maintainers`** (6 repos currently
   use `@<handle>`); **add** the file to `dmf-env` + `dmf-promsd` (operator decision).
6. **Bring `dmf-env` + `dmf-promsd` to hygiene parity** with the 7 existing public
   repos — they are bare. Add `LICENSE` (Apache 2.0), `NOTICE`, a `## License` README
   section (dmf-promsd only), **`dmf-env/VERSION`=`0.1.0`**, `.gitleaks.toml` +
   `.githooks/pre-commit` (copied verbatim from dmf-infra), dmf-promsd `.gitignore`
   baseline block, and fix the stale `forgejo-<handle>` `image.source` label in
   `dmf-promsd/Dockerfile`. (`.githooks/pre-push` is out of scope — missing in all
   repos; flagged to E1/A.)
7. Promote `docs/architecture/DMF Release and Contribution Model.md` to a new ADR
   (**ADR-0041** — see §7 for the number rationale) and mark the source doc
   **Accepted**. Wire the INDEX row.

> **Co-export invariant (master plan §A.4):** for the **8 clean-import repos**, D's
> `.github/` content and E1's CI workflows are **baked into the same orphan export
> commit** before the public flip, so a public repo **never exists without the CI
> gates**. The CONTRIBUTING/PR-template wording describes those gates as live
> (desired-state at flip time). If D is committed to the Forgejo working repos ahead
> of E1, that interim window is LAN-only and pre-public — acceptable.
>
> **⚠️ `dmf-runbooks` exception (codex) — it is ALREADY PUBLIC at v0.1.2, with no
> private orphan-export window and currently no CI workflows.** Its D templates would
> claim live gitleaks/scrub/commitlint gates that do not yet exist on the public repo.
> Therefore: qwen **prepares** dmf-runbooks' D files like every other repo, but they
> are **committed locally only and MUST NOT be pushed to the `github` remote until
> the same batch as dmf-runbooks' E1 CI workflows** (one public PR carrying D + E1
> together). The orchestrator commits D to local `main`; **no `git push github` for
> dmf-runbooks happens in Workstream D.** (All other repos are still private — no push
> risk.)

**Non-goals (owned elsewhere — do NOT do here):**
- The PR-gate CI workflows — gitleaks/scrub/lint/commitlint/trivy — are **Workstream E1**.
  This spec adds **only** the DCO workflow (it is governance, not a build gate).
- Any GitHub repo creation, branch/tag rulesets, secret-scanning toggles, or public
  flip — those are **Workstream A** (and require explicit per-step operator approval).
- Any history rewrite. dmf-runbooks is already public at v0.1.2 — a `CONTRIBUTING.md`
  update is a normal forward commit, which is allowed; do **not** touch its history.
- No edits to the **bodies** of existing ADRs (locked decision C).

---

## 1. The model these files must encode (read once, then apply)

The single source of the new rules is the parent plan + `DMF Release and
Contribution Model.md` §5–§7, **as amended** by the 2026-06-09 locked decisions.
Net rules the governance files must state:

- **GitHub `main` is the single source of truth** (GitHub-canonical-forward). All
  forward work is **GitHub Pull Requests**. Direct push to `main` is blocked;
  force-push is banned.
- **Forgejo is archive-only**, never the upstream of GitHub. There is **no**
  "Forgejo push-mirror → GitHub" path. (Working clones keep a read-only `archive`
  remote → LAN Forgejo `<owner>/<repo>-archive` for pre-publish history — mention
  this only in CONTRIBUTING's "history" note, not as a contribution path.)
- **`bin/sync-to-github.sh` is a retired one-time import tool**, NOT the publish
  path. Remove all "only sanctioned publish path is sync-to-github.sh" language.
- **DCO, not CLA.** Every commit needs `Signed-off-by:` (`git commit -s`); a DCO
  check enforces it on PRs.
- **Conventional Commits** required on `main`; **SemVer**; **VERSION file** is the
  single source of truth (ADR-0005); no VERSION bump → no release.
- **Topic branches** `<handle>/<short-slug>`; linear history; squash/rebase onto `main`.
- **Secrets posture:** secrets stay in OpenBao; never commit credentials, kubeconfigs,
  tfstate, keys. **Placeholder syntax only** for IPs/DNS/operator identity in any
  public artifact (`<control-node-public-ip>`, `dmf.example.com`, `<handle>`).
- **Agent contract** (concise): agents contribute via PRs like everyone else; no
  `--no-verify`/`--force`/`--no-gpg-sign`; cluster mutation only via
  `bin/run-playbook.sh` (ADR-0010); stop & ask on dirty sub-repo state. (Drop the
  stale "sync-to-github.sh is the only push path" and "obey the Constitution" lines.)

---

## 2. CONTRIBUTING.md — canonical template

Write this to each repo, substituting `{{...}}` from the table in §8. Keep the
structure identical across repos so it is grep-verifiable; the only per-repo
variance is the title line, the role blurb, and the **Repo-specific rules** block.

````markdown
# Contributing to {{REPO_NAME}}

{{REPO_ROLE_BLURB}}

This repo is part of the **DMF Platform**. GitHub is the canonical home and the
single source of truth: all changes land via **Pull Request** against `main`.
(The full pre-publish history lives in a LAN-only `{{REPO_NAME}}-archive` Forgejo
repo, reachable as a read-only `archive` git remote — it is **not** an upstream
and is never a contribution path.)

## Quick start

1. Read the platform overview in the **dmf-platform** umbrella repo
   (`docs/architecture/DMF Platform Plan.md`) and apply any relevant ADRs from
   `docs/decisions/INDEX.md`.
2. Fork or branch, make your change on a topic branch, open a PR against `main`.
3. Ensure CI is green and your commits are **signed off** (see DCO below).

## Branch & PR model

- **GitHub Pull Requests only.** Direct push to `main` is blocked; force-push is
  banned; linear history is required.
- Topic branches: **`<handle>/<short-slug>`** (e.g. `jdoe/fix-probe-path`). One
  logical change per branch; rebase onto `main` rather than long-lived branches.
- **Conventional Commits** (`feat:`, `fix:`, `docs:`, `chore:`, `refactor:`,
  `test:`, `build:`, `ci:`) are **required** on `main` and checked in CI. Other
  prefixes are rejected.
- A reviewer (per `CODEOWNERS`) and green required checks are needed to merge.

## Developer Certificate of Origin (DCO)

We use the [Developer Certificate of Origin](https://developercertificate.org/),
not a CLA. **Every commit must be signed off:**

```bash
git commit -s -m "fix: correct the probe path"
```

This appends a `Signed-off-by: Your Name <you@example.com>` trailer certifying you
have the right to submit the work under the project license. A **DCO check** runs
on every PR and fails if any commit is missing the trailer. Amend with
`git commit --amend -s` or rebase with `git rebase --signoff main` to fix. PRs are
**rebase-merged** by default so your signed-off commits land on `main` unchanged.

## Versioning & releases

This repo carries a `VERSION` file (single semver line). Per **ADR-0005**,
`VERSION` is the single source of truth — any release-tagged change must update it
in the same commit. **No VERSION bump → no release.** Release tags are `v<VERSION>`,
created by release automation, never by hand.

## Secrets & public-safety posture

**Secrets stay in OpenBao.** Never commit, track, or reference credentials, tokens,
keys, kubeconfigs, or Terraform state — not even with a "remove later" TODO. Use
**placeholder syntax** for any IPs, DNS names, or operator identity in code, docs,
PR descriptions, or issues (`<control-node-public-ip>`, `dmf.example.com`,
`<handle>`). A local pre-commit gitleaks hook runs on commit, and CI runs
secret-scanning + scrub gates on every PR — but redaction is your responsibility
first. If you need a secret, ask a maintainer — do not improvise a transport.

## Must / Must not

### MUST
- Open changes as **GitHub PRs against `main`** with **signed-off** commits.
- Use Conventional Commit messages and `<handle>/<short-slug>` topic branches.
- Update `VERSION` in the same commit as any release-tagged change.
- Use **placeholder syntax** for all IPs / DNS / operator identity in every artifact.
{{REPO_MUST_EXTRA}}

### MUST NOT
- Commit secrets, tokens, keys, kubeconfigs, or Terraform state.
- Push directly to `main`, force-push, or use `--no-verify` / `--no-gpg-sign`.
- Paste secrets, real IPs/DNS, or operator identity into issues, PRs, or CI logs.
{{REPO_MUST_NOT_EXTRA}}

## AI agent contract

Much of this platform is built by AI agents. Agents contribute the same way:
**PRs against `main`, signed off, CI green.** Additionally, agents must run cluster
mutation only via `bin/run-playbook.sh` (ADR-0010), must not use
`--no-verify`/`--force`/`--no-gpg-sign`, and must stop and ask before modifying a
sub-repo with uncommitted state.

## Reporting security issues

See [`SECURITY.md`](SECURITY.md). **Do not** open a public issue for a vulnerability.

## License & spec

Contributions are licensed under [Apache 2.0](LICENSE). The canonical governance
model is **ADR-0041 — DMF Release and Contribution Model** in the dmf-platform
umbrella repo (`docs/decisions/`).
````

**Per-repo notes:**
- For the **umbrella** (`dmf-platform`), replace the "Quick start" step 1 with the
  boot-ritual pointer (read `STATUS.md`, latest handoff, `INDEX.md`) and the
  "Versioning" section's "this repo carries a VERSION file" with "component repos
  carry VERSION files; the umbrella holds docs/ADRs/plans." Keep everything else.
- `{{REPO_MUST_EXTRA}}` / `{{REPO_MUST_NOT_EXTRA}}` are blank for most repos; see §8
  for the runbooks/env/infra additions. If blank, omit the placeholder line entirely
  (no empty bullet).

---

## 3. SECURITY.md — canonical template

Identical in every repo except `{{REPO_NAME}}`:

````markdown
# Security Policy

## Reporting a vulnerability

**Do not open a public issue, PR, or discussion for a security vulnerability.**

Report privately via GitHub's **[Report a vulnerability](https://github.com/dmfdeploy/{{REPO_NAME}}/security/advisories/new)**
(Security → Advisories → Report a vulnerability) on the `{{REPO_NAME}}` repository.
This opens a private advisory visible only to maintainers.

If you cannot use the GitHub flow, contact the maintainer listed in `CODEOWNERS`
through their GitHub profile and request a private channel — never include the
vulnerability details in a public message.

## What to include

- Affected repo, version (`VERSION` file), and commit/branch.
- A description of the issue and its impact.
- Steps to reproduce (a minimal PoC if possible).
- **Never include real secrets, credentials, cluster IPs/DNS, or operator
  identity** — use placeholders, exactly as in the rest of the project.

## Our commitment

- We acknowledge reports within **5 business days**.
- We work with you on a coordinated-disclosure timeline and credit you (if you wish)
  in the advisory and release notes.
- Fixes ship as a normal `vX.Y.Z` release; the advisory is published once a fix is
  available.

## Supported versions

This project is pre-1.0 (experiment phase). Only the latest `vX.Y.Z` release on
`main` is supported; please reproduce against the current tip before reporting.
````

---

## 4. `.github/` issue + PR templates

### 4.1 `.github/PULL_REQUEST_TEMPLATE.md` (identical in every repo)

````markdown
<!--
⚠️ NEVER paste secrets, credentials, real IPs/DNS, kubeconfigs, Terraform state,
or operator identity into this PR. Use placeholder syntax (<control-node-public-ip>,
dmf.example.com, <handle>). CI gitleaks/scrub will block a leak — but it is your
responsibility first.
-->

## What & why

<!-- One paragraph: what this changes and the motivation. Link issues with #NNN. -->

## Checklist

- [ ] Commits are **signed off** (`git commit -s`) — DCO check will verify.
- [ ] Commit messages follow **Conventional Commits** (`feat:`/`fix:`/`docs:`/…).
- [ ] `VERSION` bumped if this is a release-tagged change (ADR-0005); otherwise N/A.
- [ ] No secrets / real IPs / DNS / operator identity anywhere in the diff or this PR.
- [ ] CI is green (gitleaks, scrub, lint, commitlint where applicable).
- [ ] Docs/ADRs updated if behavior or decisions changed.
````

### 4.2 `.github/ISSUE_TEMPLATE/config.yml` (identical)

````yaml
blank_issues_enabled: false
contact_links:
  - name: Security vulnerability (private)
    url: https://github.com/dmfdeploy/{{REPO_NAME}}/security/advisories/new
    about: Report security issues privately — never in a public issue. See SECURITY.md.
````

> Org confirmed **`dmfdeploy`** (the public `dmf-runbooks` remote is
> `github.com/dmfdeploy/dmf-runbooks`). Only `{{REPO_NAME}}` is substituted per repo.

### 4.3 `.github/ISSUE_TEMPLATE/bug_report.yml` (identical)

````yaml
name: Bug report
description: Something is broken or behaving unexpectedly.
labels: [bug]
body:
  - type: markdown
    attributes:
      value: |
        ⚠️ **Never paste secrets, real IPs/DNS, kubeconfigs, or operator identity.**
        Use placeholders (`<control-node-public-ip>`, `dmf.example.com`, `<handle>`).
        For security vulnerabilities, **stop** — use SECURITY.md (private reporting).
  - type: input
    id: version
    attributes:
      label: Version
      description: Contents of the repo's VERSION file (or commit SHA).
    validations: { required: true }
  - type: textarea
    id: what-happened
    attributes:
      label: What happened?
      description: What you expected vs. what occurred. Redact any sensitive values.
    validations: { required: true }
  - type: textarea
    id: repro
    attributes:
      label: Steps to reproduce
    validations: { required: true }
````

### 4.4 `.github/ISSUE_TEMPLATE/feature_request.yml` (identical)

````yaml
name: Feature request
description: Propose an enhancement or new capability.
labels: [enhancement]
body:
  - type: markdown
    attributes:
      value: |
        For larger design questions, prefer **Discussions**. ⚠️ No secrets, real
        IPs/DNS, or operator identity in this issue — use placeholders.
  - type: textarea
    id: problem
    attributes:
      label: Problem / motivation
      description: What problem does this solve? Who needs it?
    validations: { required: true }
  - type: textarea
    id: proposal
    attributes:
      label: Proposed solution
    validations: { required: false }
````

---

## 5. DCO check workflow — `.github/workflows/dco.yml` (identical in every repo)

**Form chosen (codex-confirmed): inline POSIX `sh` over the PR commits API — no
third-party action** (avoids supply-chain surface for a trivial trailer grep).
Fork-PR-safe: `pull_request` trigger (never `pull_request_target`), least-privilege
permissions, no secrets, no checkout. `pull-requests: read` is included alongside
`contents: read` because the job calls the PR commits API.

````yaml
name: DCO
on:
  pull_request:
    branches: [main]
permissions:
  contents: read
  pull-requests: read
jobs:
  dco:
    runs-on: ubuntu-24.04
    steps:
      - name: Verify Signed-off-by on every commit
        env:
          GH_TOKEN: ${{ github.token }}
          COMMITS_URL: ${{ github.event.pull_request.commits_url }}
        run: |
          set -eu
          missing=0
          # Page through the PR commits and check each message for the trailer.
          page=1
          while :; do
            batch="$(gh api "${COMMITS_URL}?per_page=100&page=${page}" \
              --jq '.[] | @base64')"
            [ -z "$batch" ] && break
            for row in $batch; do
              msg="$(printf '%s' "$row" | base64 -d | \
                python3 -c 'import sys,json;d=json.load(sys.stdin);print(d["commit"]["message"]);print(d["sha"])')"
              sha="$(printf '%s\n' "$msg" | tail -n1)"
              body="$(printf '%s\n' "$msg" | sed '$d')"
              if ! printf '%s\n' "$body" | grep -qiE '^Signed-off-by: .+ <.+@.+>'; then
                echo "::error::commit ${sha} missing Signed-off-by trailer (run: git commit -s)"
                missing=1
              fi
            done
            page=$((page+1))
          done
          [ "$missing" -eq 0 ] || exit 1
````

> **Lifter note:** `gh` is preinstalled on `ubuntu-24.04` hosted runners; `python3`
> is too. Keep the workflow byte-identical across all 9 repos. Do **not** add
> `secrets.` or a `checkout` step. **codex confirmed this form** (over
> `tim-actions/dco`) on 2026-06-09.

### 5.1 DCO merge-method gap (cross-workstream note → Workstream A)

A PR DCO check proves the **PR commits** carry the trailer, but a **squash-merge**
re-authors a new commit on `main` whose generated message may drop it — so "DCO
green" can still land an **unsigned `main` commit** (codex). Mitigation, enforced in
**Workstream A's GitHub repo settings** (not by qwen here):

- Set each repo's allowed merge method to **"Rebase and merge" only** (preserves the
  signed-off PR commits verbatim), **or** if squash is kept, require maintainers to
  retain the `Signed-off-by` trailer in the squash commit message.
- CONTRIBUTING already documents `git commit -s`; add one sentence noting that
  **rebase-merge is the default** so trailers survive. (Template §2 updated.)

This is flagged here so Workstream A configures the merge method at flip time; qwen
only ships the `dco.yml` + the CONTRIBUTING sentence.

---

## 6. CODEOWNERS — normalize all + add the two missing

**Operator decision (2026-06-09): the CODEOWNER handle is `@dmfdeploy/maintainers`
across ALL repos.** Today the handle is split — `dmf-runbooks` uses
`@dmfdeploy/maintainers`; the other 6 (umbrella, dmf-cms, dmf-central, dmf-infra,
dmf-media, dmf-init) use `@<handle>`. **Normalize the 6 to `@dmfdeploy/maintainers`**
and add CODEOWNERS to the 2 bare repos.

> **⚠️ Operator prerequisite (NOT qwen's job), for ALL 9 repos:** the
> `dmfdeploy/maintainers` **team must exist in the org**, with `znerol2` as a member,
> be **org-visible**, and have **write (or maintain) access to each repo**. GitHub
> only honors a CODEOWNERS team that can actually be requested for review — a
> nonexistent, secret, or read-only team makes the rule **silently ineffective** (no
> error). Confirm/create + grant per-repo access before the Workstream A public flip
> (so branch-protection "require CODEOWNER review" actually binds). Tracked in §10.

- **Normalize (7 repos that have CODEOWNERS):** in umbrella, dmf-cms, dmf-central,
  dmf-infra, dmf-media, dmf-init — replace every `@<handle>` with
  `@dmfdeploy/maintainers`. **Keep each file's existing path rules and comments
  otherwise** (do not restructure dmf-infra's secret-path rules etc.). dmf-runbooks
  already uses the team handle — leave it. Verify each retains a `*` default and a
  `/.github/` rule.
- **Add `.github/CODEOWNERS` to `dmf-env` and `dmf-promsd`:**

**dmf-env** (`dmf-env/.github/CODEOWNERS`) — protect the high-risk generic surface:
````
# dmf-env — CODEOWNERS. Activates on GitHub once branch protection requires reviews.
*                    @dmfdeploy/maintainers
/terraform/          @dmfdeploy/maintainers
/bin/                @dmfdeploy/maintainers
/.github/            @dmfdeploy/maintainers
````

**dmf-promsd** (`dmf-promsd/.github/CODEOWNERS`):
````
# dmf-promsd — CODEOWNERS. Activates on GitHub once branch protection requires reviews.
*                    @dmfdeploy/maintainers
/.github/            @dmfdeploy/maintainers
````

---

## 7. dmf-env + dmf-promsd hygiene parity (LICENSE / NOTICE / README / VERSION / source label)

Both repos are bare of license hygiene; `bin/check-public-repo-hygiene.sh` (the CI
gate) requires both `LICENSE` **and** `VERSION` present. Bring them to parity with
the other 7:

1. **`LICENSE`** — copy **verbatim** from `dmf-infra/LICENSE` (Apache 2.0) into
   `dmf-env/LICENSE` and `dmf-promsd/LICENSE`. Do not retype; `cp` it (verify with
   `cmp`).
2. **`NOTICE`** — copy `dmf-infra/NOTICE` as the template, then edit the project/
   component line to name the repo. codex confirmed (2026-06-09) no vendored/
   upstream-derived code in either tree beyond declared deps/providers — keep the
   NOTICE **minimal** (project name + copyright + Apache reference). The §11
   verification grep guards against a future missed bundled component.
3. **README `## License` section:**
   - `dmf-env/README.md` **already has** a `## License` section — leave it.
   - `dmf-promsd/README.md` has **none** — append a `## License` section matching
     the wording used in `dmf-infra/README.md` (name, link to `LICENSE`,
     attribution note).
4. **`VERSION`:**
   - `dmf-env` has **no** `VERSION` — add `dmf-env/VERSION` containing `0.1.0`
     (single line, no trailing prose). This aligns it with the first-public-release
     tag discipline (`v0.1.0`) used by every other repo.
   - `dmf-promsd` already has `VERSION` = `0.1.3` — **leave it** (do not reset).
5. **Stale canonical-source label (dmf-promsd):** `dmf-promsd/Dockerfile:8` carries
   `org.opencontainers.image.source="https://forgejo-<handle>/<handle>/dmf-promsd"` — an
   internal-topology leak + wrong canonical source for the GitHub-forward model.
   Change it to `https://github.com/dmfdeploy/dmf-promsd`. Grep the rest of the
   dmf-promsd tree for any other `forgejo-<handle>`/`forgejo`/`<operator>/` source labels and
   fix them too (see §11). This is the only known dmf-promsd public-surface scrub
   item (it never had a Workstream-B-style pass).
6. **Secret-scanning hygiene files (file-parity with the 7 existing public repos):**
   `bin/check-public-repo-hygiene.sh:67` (the export-scan gate) checks for
   `LICENSE NOTICE VERSION .gitignore .github/CODEOWNERS .gitleaks.toml
   .githooks/pre-commit .githooks/pre-push`. dmf-env/dmf-promsd are missing
   `.gitleaks.toml` and `.githooks/pre-commit`. Copy both **verbatim from dmf-infra**
   (confirmed generic + public-safe — no operator identity; `dmf-infra/.gitleaks.toml`
   is byte-identical to dmf-runbooks', and the **sub-repo** pre-commit hook is
   identical across the **component** public repos — the umbrella's own hook differs
   intentionally, so do NOT use it as the source):
   - `cp dmf-infra/.gitleaks.toml {dmf-env,dmf-promsd}/.gitleaks.toml`
   - `cp dmf-infra/.githooks/pre-commit {dmf-env,dmf-promsd}/.githooks/pre-commit`
     (preserve the executable bit).
   - **`.gitignore`:** dmf-env's (88 lines) already carries the baseline secret block;
     **dmf-promsd's is only 9 lines** — add the Release-model §6 baseline block
     (`*.kubeconfig`, `*.tfstate`, `*.tfstate.*`, `.terraform/`, `hosts.ini`,
     `openbao-*`, `*.pem`, `*.key`, `secret_id*`, `.env`, `.env.*`) if absent.
   - **`.githooks/pre-push` is intentionally OUT of scope:** **none** of the 7
     existing public repos carry it, so the gate's pre-push requirement is a
     **pre-existing cross-repo gap**, not introduced or closed by D. Flag it for
     **E1/A** (decide: add pre-push everywhere or relax the gate). Do NOT block D on it.

---

## 8. ADR-0041 promotion (number rationale + steps)

**Number rationale (do not use 0018):** the parent plan and the source doc both say
"promote to **ADR-0018**", but `0018` is **already an Accepted decision**
(`0018-self-managed-k3s-not-ack.md`). Locked decision C forbids renumber/merge/delete.
The next free monotonic slot is **0041** (highest existing is `0040`). Use **0041**.

Steps:

1. **Create `docs/decisions/0041-release-and-contribution-model.md`** — a normal ADR
   that **references** `docs/architecture/DMF Release and Contribution Model.md` as
   the detail (do not duplicate the whole doc). Status **Accepted**, date 2026-06-09.
   Context: the four 2026-06-09 locked decisions (GitHub-canonical-forward, DCO,
   retire-to-archive, Free-tier locked-window flip) close the doc's §5 external-
   contributor TBD. Decision: adopt the model in that doc as amended by the
   First Public Release Plan. Consequences: governance files (this workstream),
   PR gates (E1), release automation (E2).
2. **Edit `docs/architecture/DMF Release and Contribution Model.md`:**
   - Line 3 status: `Draft for ratification (will become ADR-0018 once accepted)` →
     `Accepted — ratified as ADR-0041 (2026-06-09)`.
   - §1 topology table: flip `dmf-env` row `Private` → `Public (sanitized generic
     surface — ADR-0035)`; add `dmf-promsd` (Public) and `dmf-init` (Public) rows.
   - §1 prose: replace the "GitHub is a one-way push mirror; LAN Forgejo is primary;
     single sanctioned publish path is `bin/sync-to-github.sh`" paragraph with the
     **GitHub-canonical-forward** statement (Forgejo archive-only; PRs to GitHub
     `main`; sync-to-github.sh retired post-import).
   - §5: replace the **"External contributor flow — TBD"** bullet with the resolved
     **DCO + GitHub-first PR** model.
   - §8 enforcement table: update the "No forbidden patterns in public mirror /
     sync-to-github.sh scrub" and "Branch protection" rows to GitHub rulesets +
     CI gitleaks/scrub (no Forgejo pre-receive as the canonical gate).
   - "Open follow-ups before this doc becomes ADR-0018" section: retitle to a brief
     "Ratified as ADR-0041 (2026-06-09)" note; check off the resolved follow-ups
     (CONTRIBUTING per repo = this workstream; §5 TBD = resolved). Leave genuinely
     open CI items pointing at E1/E2.
3. **`docs/decisions/INDEX.md`:** add the `0041` row to the chronological table
   (Status Accepted, theme `release / governance`) and reference it from the
   deployment/release theme-cluster row if appropriate. Match the existing row format.
4. **Fix the parent plan's stale ADR-0018 references** (codex) — the approved
   `docs/plans/DMF First Public Release Plan 2026-06-09.md` still points future
   agents at 0018:
   - `:7-9` (header "Supersedes/extends … → ADR-0018") → `→ ADR-0041`.
   - `:225` ("Promote `DMF Release and Contribution Model.md` → **ADR-0018
     (Accepted)**") → `**ADR-0041 (Accepted)**`.
   - `:291` ("Source-of-truth: … → ADR-0018") → `→ ADR-0041`.
   Add a one-line parenthetical at the first occurrence: `(0018 was already taken by
   self-managed-k3s-not-ack; next free slot 0041)`.

> **Do not** edit any other ADR body. Do **not** touch `0018`.

---

## 9. Per-repo substitution table

GitHub repo name, role blurb, and any MUST/MUST-NOT extras. **Resolved constants:**
GitHub org/URL namespace = **`dmfdeploy`**; CODEOWNER handle = **`@dmfdeploy/maintainers`**
(all repos, §6).

| Local dir | `{{REPO_NAME}}` (GitHub) | `{{REPO_ROLE_BLURB}}` | MUST/MUST-NOT extras |
|---|---|---|---|
| `.` (umbrella) | `dmf-platform` | The umbrella workspace for the DMF Platform: consolidated knowledge base (`docs/`), ADRs, plans, handoffs, skills, and cross-repo status. Code lives in the component repos. | — (use the umbrella Quick-start/Versioning variants from §2) |
| `dmf-cms` | `dmf-cms` | The DMF operator console (React + FastAPI). | — |
| `dmf-runbooks` | `dmf-runbooks` | Thin AWX launcher playbooks + NetBox-side catalog roles for the DMF Platform. | MUST: keep launchers thin (logic in roles/charts, ADR-0014/0025); update `NOTICE` if a new upstream-derived role is added. MUST NOT: hardcode AWX inventory IDs / cluster names. |
| `dmf-central` | `dmf-central` | Central-services scaffolding for the DMF Platform. | — |
| `dmf-infra` | `dmf-infra` | Generic Ansible playbooks and roles for the DMF Platform. | MUST: keep roles generic — no env-specific values; placeholder syntax for all cluster identifiers. |
| `dmf-media` | `dmf-media` | Media-domain catalog metadata and (future) Layer 5 roles + Helm charts. | — |
| `dmf-init` | `dmf-init` | The Day-0 stateless init/bootstrap container (React + FastAPI) that wraps the dmf-env wizard + toolchain behind a localhost web UI. | — |
| `dmf-env` | `dmf-env` | Generic environment tooling for the DMF Platform: `bin/` scripts, `terraform/modules/` + generic per-provider roots, neutral `tasks/`/`templates/`. Per-env state is operator-local and never committed (ADR-0035). | MUST: keep the surface generic — per-env state stays under `~/.dmfdeploy/envs/<env>/`; placeholder syntax everywhere. MUST NOT: commit inventories, tfstate, SOPS bundles, SSH keys, or OpenBao/Shamir material. |
| `dmf-promsd` | `dmf-promsd` | NetBox-driven Prometheus service-discovery for the DMF Platform (dynamic monitoring targets from the NetBox SoT). | — |

---

## 10. Open items — RESOLVED (2026-06-09)

1. **Org / CODEOWNER** — ✅ org `dmfdeploy` (confirmed from the public dmf-runbooks
   remote); CODEOWNER handle `@dmfdeploy/maintainers` across all repos, normalizing
   the 6 that use `@<handle>` (operator decision). **Operator prerequisite (NOT
   qwen), for all 9 repos:** the **`dmfdeploy/maintainers` team must exist** in the
   org with `znerol2` as a member, be **org-visible**, and have **write/maintain
   access to each repo** — otherwise GitHub silently ignores the CODEOWNERS rule (no
   error) and "require CODEOWNER review" won't bind. Do this before the Workstream A
   public flip.
2. **DCO enforcement form** — ✅ inline POSIX `sh` over the PR commits API, no
   third-party action (codex-confirmed, §5).
3. **DCO in D vs E1** — ✅ stays in D (D.8 "wire the DCO check"; bakes with the rest
   of `.github/`). Not a required status check until Workstream A configures rulesets.
4. **DCO merge-method gap** — ✅ flagged to Workstream A (§5.1): rebase-merge-only (or
   signed-off squash) so `main` commits keep the trailer.
5. **NOTICE minimal vs full** — ✅ minimal NOTICE for dmf-env/dmf-promsd (codex
   confirmed no vendored upstream code); §11 grep guards against regressions.
6. **`.githooks/pre-push` hygiene-gate gap (→ E1/A, NOT D):** `check-public-repo-hygiene.sh`
   requires `.githooks/pre-push`, but **none of the 9 repos carry it** — the gate has
   never passed clean. D does not introduce or fix this. E1/A must decide: deploy a
   pre-push hook everywhere, or relax the gate. D's hygiene assertion (§11) expects
   exactly this one item to remain failing.

---

## 11. Verification (orchestrator runs after qwen lift — grep-proof, do not trust DONE)

Per-repo, from the umbrella root:

```bash
for r in . dmf-cms dmf-runbooks dmf-central dmf-infra dmf-media dmf-init dmf-env dmf-promsd; do
  echo "== $r =="
  ls "$r"/CONTRIBUTING.md "$r"/SECURITY.md "$r"/LICENSE "$r"/NOTICE 2>&1
  [ "$r" = "." ] || ls "$r"/VERSION 2>&1
  ls "$r"/.github/CODEOWNERS "$r"/.github/PULL_REQUEST_TEMPLATE.md \
     "$r"/.github/workflows/dco.yml 2>&1
  ls "$r"/.github/ISSUE_TEMPLATE/{config.yml,bug_report.yml,feature_request.yml} 2>&1
done
# bare repos only — hygiene files added by §7.6:
for r in dmf-env dmf-promsd; do ls "$r"/.gitleaks.toml "$r"/.githooks/pre-commit 2>&1; done
```

> **⚠️ Component repos are independent, gitignored sibling repos** — the umbrella's
> `git grep` does NOT see their files. **Every content check MUST iterate with
> `git -C "$r" grep`** (codex), or qwen can claim DONE while a component file is
> dirty. Use this loop form for all greps below:

```bash
REPOS=(. dmf-cms dmf-runbooks dmf-central dmf-infra dmf-media dmf-init dmf-env dmf-promsd)
```

Content gates (each must be empty / pass for **every** repo via `git -C "$r" grep`):

- **No stale model language** in any CONTRIBUTING/SECURITY:
  ```bash
  for r in "${REPOS[@]}"; do git -C "$r" grep -nEi \
    'sync-to-github\.sh.*(only|sanctioned|publish path)|one-way (push )?mirror|Forgejo.canonical|five sibling repos|obey the Constitution' \
    -- CONTRIBUTING.md SECURITY.md; done
  ```
  → no hits.
- **DCO documented** in every CONTRIBUTING: per-repo
  `git -C "$r" grep -n 'git commit -s' -- CONTRIBUTING.md` and `Signed-off-by` present (all 9).
- **Banner present** in every PR template + every issue template
  (`git -C "$r" grep -ni 'never paste\|No secrets' -- .github/`) — all 9.
- **DCO workflow hardening:** every `.github/workflows/dco.yml` is byte-identical
  (`md5`/`cmp` across repos), `on: pull_request` (NOT `pull_request_target`),
  `permissions:` = exactly `contents: read` + `pull-requests: read`, **no `secrets.`
  references**, **no `checkout` step**, **no `uses:` third-party action** (inline `sh`).
  Any future external action MUST be 40-char-SHA-pinned.
- **CODEOWNERS normalized:** `@dmfdeploy/maintainers` everywhere; **no `@<handle>`
  remains** —
  `for r in "${REPOS[@]}"; do git -C "$r" grep -n '@<handle>' -- .github/CODEOWNERS; done`
  → no hits. dmf-env + dmf-promsd CODEOWNERS now exist.
- **dmf-env/dmf-promsd file-parity** (NOT the full gate — see note): each of
  `LICENSE NOTICE VERSION .gitignore .github/CODEOWNERS .gitleaks.toml
  .githooks/pre-commit` present. `cmp dmf-env/LICENSE dmf-infra/LICENSE` exits 0 (same
  for dmf-promsd); `.gitleaks.toml` + `.githooks/pre-commit` byte-identical to
  dmf-infra's; **`dmf-env/VERSION`=`0.1.0`**, `dmf-promsd/VERSION`=`0.1.3`;
  `dmf-promsd/README.md` has a `## License` section; dmf-promsd `.gitignore` carries
  the baseline secret block.
  - **`bin/check-public-repo-hygiene.sh` will still report `.githooks/pre-push`
    missing for ALL repos** (pre-existing — none have it). That is the only expected
    failure; assert the diff is **exactly** that one item, flagged to E1/A. Do not
    claim the gate passes clean.
- **No bundled-upstream attribution missed (codex):**
  `for r in dmf-env dmf-promsd; do git -C "$r" grep -nEi 'SPDX|Copyright|derived from|vendored|copied from|based on|upstream'; done`
  → review every hit; if it names third-party code, the NOTICE must cite it.
- **No stale internal source labels (codex):**
  `git -C dmf-promsd grep -nE 'forgejo-<handle>|forgejo[^.]|/<handle>/'`
  → no hits (the `Dockerfile:8` `image.source` is now `github.com/dmfdeploy/dmf-promsd`).
- **ADR-0041 (umbrella):** `docs/decisions/0041-*.md` exists, INDEX has the row,
  source doc status flipped, parent plan's 3 stale `0018` refs (≈ lines 8/225/291)
  now say `0041`, and **`0018` is untouched** (`git -C . diff --stat` shows no
  `0018-*.md` change).
- **`.gitleaks.toml` allowlist:** if any new file legitimately contains a pattern the
  umbrella pre-commit hook flags (unlikely — generic templates), add it to the
  matching per-rule allowlist (handoff gotcha).

Then: codex final cross-check → commit per-repo (`docs(governance): GitHub-first
CONTRIBUTING/SECURITY/templates + DCO (Workstream D)`) and umbrella
(`docs(adr): ratify Release & Contribution Model as ADR-0041 + governance spec`).
Each commit signed off (`-s`) to dogfood DCO.
````
