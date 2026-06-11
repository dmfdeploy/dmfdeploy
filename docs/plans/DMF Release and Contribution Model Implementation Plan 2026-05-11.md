---
status: superseded
date: 2026-05-11
superseded_by: "DMF Workstream D — GitHub-First Governance Execution Spec 2026-06-09.md"
---
# DMF Release and Contribution Model — Implementation Plan
> **Superseded by** [DMF Workstream D — GitHub-First Governance Execution Spec 2026-06-09.md](DMF%20Workstream%20D%20%E2%80%94%20GitHub-First%20Governance%20Execution%20Spec%202026-06-09.md) — see frontmatter.

**Status:** Draft
**Date:** 2026-05-11
**Pairs with:** `docs/architecture/DMF Release and Contribution Model.md` (the
spec; will become ADR-0018 once this plan is fully landed)
**Driver:** the spec's §170 follow-ups + §8 enforcement table. This plan
turns each row from *discipline-only* into *script-enforced*.

---

## 1. Current state vs. spec (audited 2026-05-11)

Snapshot of all 7 repos against the Release and Contribution Model. `✓` =
present; `❌` = missing; `⚠` = partial.

### §2 License + §3 Structural

| Item | dmfdeploy | dmf-cms | dmf-infra | dmf-central | dmf-media | dmf-runbooks | dmf-env (private) |
|---|---|---|---|---|---|---|---|
| `LICENSE` at root | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | n/a |
| `NOTICE` at root | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | n/a |
| `## License` in `README.md` | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | n/a |

### §4 Versioning

| Item | dmfdeploy | dmf-cms | dmf-infra | dmf-central | dmf-media | dmf-runbooks | dmf-env |
|---|---|---|---|---|---|---|---|
| `VERSION` file | ❌ | ✓ (0.7.3) | ❌ | ❌ | ✓ (0.1.0) | ❌ | ❌ |
| `CHANGELOG.md` | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `bin/release.sh` | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `bin/generate-changelog.sh` | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

ADR-0005 already mandates `VERSION`; only 2 of 7 repos have one today.

### §5 Branch & review

| Item | Status |
|---|---|
| `main` is default in all 7 repos | ✓ (verified 2026-05-11) |
| Conventional Commits prefix discipline | ⚠ recent commits in `dmf-infra`, `dmf-env`, `dmfdeploy` look conventional; component repos' "Initial public release v0.1.0" commit is non-conformant but acceptable as a baseline marker |
| `commitlint` configured | ❌ |
| GitHub branch protection | ❌ no `github.com/dmfdeploy/*` org exists yet; no `github` remote on any repo |
| Sub-repo dirty-state respected | ✓ documented in boot ritual (discipline only) |

### §6 Defensive (3-layer)

| Layer | Status |
|---|---|
| Pre-commit gitleaks — umbrella | ✓ via `.githooks/pre-commit` (installed by `bin/install-hooks.sh`) |
| Pre-commit gitleaks — 6 component repos | ❌ none of `dmf-cms`, `dmf-infra`, `dmf-env`, `dmf-central`, `dmf-media`, `dmf-runbooks` have a `.githooks/` dir |
| Pre-receive gitleaks (LAN Forgejo) | ❌ not implemented |
| CI gitleaks on GitHub mirror | ❌ no GitHub Actions wired anywhere (dmf-cms has an empty `.github/workflows/` shell from earlier work) |
| `.gitignore` baseline (`*.kubeconfig`, `*.tfstate*`, `.terraform/`, `hosts.ini`, `openbao-*`, `*.pem`, `*.key`, `secret_id*`, `.env*`) | ⚠ partial — `dmf-env` covers tfstate; `dmf-infra` covers vault pass + `inventories/local/`; **no repo carries the full baseline list** |
| `CODEOWNERS` at every public repo | ✓ all 6 public repos have `.github/CODEOWNERS` (dormant until GitHub is live) |
| `bin/scrub-public-repos.sh` | ✓ exists, blocking SECRET + TOPOLOGY patterns; soft on CONTEXT |
| `bin/sync-to-github.sh` | ❌ does not exist |
| `bin/check-public-repo-hygiene.sh` | ❌ does not exist |

### §7 LLM agent contract

| Item | Status |
|---|---|
| Boot ritual in `CLAUDE.md` | ✓ |
| Skill §0 for cluster / OpenBao / dmf-cms release | ✓ (`dmf-cluster-access`, `dmf-openbao-unseal`, `dmf-cms-build-and-release`) |
| `bin/run-playbook.sh` mandated for cluster mutation | ✓ ADR-0010 |
| Hook enforcement in `.claude/settings.json` | ⚠ exists but not audited against §7 must/must-never list |
| Push only via `bin/sync-to-github.sh` | ❌ script doesn't exist yet |

### §8 enforcement summary — actual state

| Rule | Spec-mandated enforcer | Today |
|---|---|---|
| Apache 2.0 + LICENSE present | `bin/check-public-repo-hygiene.sh` (CI) | ❌ neither LICENSE nor script |
| Conventional Commits | `commitlint` in CI | ❌ |
| VERSION drift = no release | `bin/release.sh` reads VERSION | ❌ |
| No secrets in commits | `gitleaks` ×3 | ⚠ 1 of 3 (umbrella pre-commit only) |
| No forbidden patterns in public mirror | `bin/sync-to-github.sh` scrub | ⚠ scrub exists, sync wrapper does not |
| Branch protection | GitHub branch protection | ❌ |
| Linear history | GitHub branch protection | ❌ |
| Sub-repo dirty state respected | Boot ritual + agent settings hook | ⚠ discipline only |
| Cluster ops only via playbook | ADR-0010 + agent denylist | ✓ ADR; ⚠ denylist not re-audited |

### Incidental findings flagged during audit

1. **Plaintext credentials in `git remote -v` URLs.** Not in tracked content
   (so not a leak per the spec), but operationally smelly:
   - `local` remote on all 7 repos: `http://<user>:<REDACTED-numeric-pw>@<lan-ip>/<operator>/<repo>.git`
   - `forgejo-lab` remote on `dmf-infra` and `dmf-media`:
     `https://<user>:<REDACTED-dev-pw>@forgejo.<lan-host>/...`
   - `dmf-runbooks` `origin` = `https://forgejo.<lan-host>/...` (no creds)
   These shapes are already in the `bin/scrub-public-repos.sh` SECRET
   pattern list and in the pre-commit gitleaks ruleset, so they cannot
   accidentally land in a commit (gitleaks caught the first draft of
   this very plan doc — working as intended). Recommend rotating during
   Phase 1 and switching to credential helper or SSH-only.
2. **`dmf-cms` has `.github/workflows/`** with no workflow file inside it
   (empty shell created during earlier work). Phase 4 fills it.
3. **No `github` remote exists anywhere yet** — the dmfdeploy GitHub org
   itself is unbuilt. Phase 2 stands it up.

---

## 2. Implementation strategy

Six phases, ordered by dependency. **Phases 0–2 are the publish-safety
gate** — per the 2026-05-07 readiness handoff and the operator's 2026-05-11
decision, no GitHub push lands until those three phases complete and
`bin/check-public-repo-hygiene.sh` returns clean across all 6 public repos.
Phases 3–5 harden the model after the org is live.

### Phase 0 — Per-repo baseline hygiene

**Goal:** every public repo carries the artifacts the spec requires to exist
on disk. No tooling yet — just files.

**Steps (apply to each of the 6 public repos):**

0.1. Add `LICENSE` (Apache 2.0 verbatim) at root.
0.2. Add `NOTICE` listing upstream-derived components. Known entries to
     seed: `dmf-runbooks` → `sony/nmos-cpp` (Apache 2.0). Other repos start
     with an empty stub plus comment header.
0.3. Add `## License` section to `README.md`: short paragraph + link to
     `LICENSE` + attribution note.
0.4. Add `VERSION` (`0.1.0`) to the 4 repos missing one: `dmfdeploy`,
     `dmf-infra`, `dmf-central`, `dmf-runbooks`.
0.5. Extend each repo's `.gitignore` to include the §6 baseline block:
     ```
     *.kubeconfig
     *.tfstate
     *.tfstate.*
     .terraform/
     hosts.ini
     openbao-*
     *.pem
     *.key
     secret_id*
     .env
     .env.*
     ```
     Apply to all 7 repos including `dmf-env` (which already covers some
     of these; merge with the baseline, don't overwrite).
0.6. Bulk-commit per repo with `chore: add LICENSE/NOTICE/VERSION + baseline .gitignore`.
0.7. Add `CONTRIBUTING.md` to each public repo. Short (1 page). Distils the
     binding rules from the spec doc (§4 versioning, §5 branch/PR model,
     §6 secrets posture, §7 agent rules) into a scannable
     **MUST / MUST NOT** bullet list at the bottom. Inspired by
     `fvwmorg/fvwm/docs/DEVELOPERS.md` — contributors landing on a public
     repo need one short doc that links back to the umbrella spec, not a
     hunt across `docs/architecture/`. Include:
     - Topic-branch naming convention: `<initials>/<short-slug>` (e.g.
       `<operator>/release-model-impl`). Add the same line to the spec doc §5.
     - Pointer to `bin/sync-to-github.sh` as the only sanctioned publish
       path (Phase 2 will create the script).
     - Pointer to ADR INDEX for "decisions that bind contributor work."

**Acceptance:** `find . dmf-cms dmf-infra dmf-central dmf-media dmf-runbooks
-maxdepth 1 -name LICENSE -o -name NOTICE -o -name VERSION
-o -name CONTRIBUTING.md | wc -l` → 24 (4 × 6). All 7 `.gitignore`s
contain the baseline block.

**Estimated effort:** 1 session, mostly mechanical.

### Phase 1 — Defensive Layer 1 (per-repo gitleaks pre-commit)

**Goal:** the §6 layer-1 (pre-commit) gate covers every repo, not just the
umbrella.

**Steps:**

1.1. Extract the gitleaks block from the umbrella's `.githooks/pre-commit`
     into a **slim, repo-agnostic** `.githooks/pre-commit` template. Place
     a copy in each component repo's `.githooks/pre-commit`.
1.2. Generalize `bin/install-hooks.sh` to work from any of the 7 repos
     (it currently assumes the umbrella). Document one-time activation
     in each repo's `CLAUDE.md` and `README.md`.
1.3. Add a minimal `.gitleaks.toml` allowlist at each repo root for known
     non-secret false-positives (e.g. example placeholders, fixture
     credentials in test data). Seed empty; populate as hits surface.
1.4. Rotate the LAN-Forgejo `<user>` password and the `forgejo-lab`
     `<user>` password (the two credentials flagged in §1 incidental
     findings); switch `local` and
     `forgejo-lab` remotes to SSH or credential-helper-backed URLs. Update
     any scripts that reference them.

**Acceptance:** `git config core.hooksPath` returns `.githooks` in every
clone. Deliberate-leak smoke test (`echo "ghp_$(openssl rand -hex 18)" >
secret; git add secret; git commit`) is refused in each repo.

**Estimated effort:** 1 session.

### Phase 2 — Publish-flow tooling

**Goal:** a single sanctioned path from LAN Forgejo `origin` → public
GitHub mirror, with the hygiene gate baked in.

**Steps:**

2.1. Build `bin/check-public-repo-hygiene.sh`. For each public repo:
     - Assert `LICENSE` exists and matches Apache 2.0 SHA
     - Assert `NOTICE` exists
     - Assert `VERSION` exists and is a valid semver
     - Assert `README.md` contains a `## License` section
     - Assert `.github/CODEOWNERS` exists
     - Assert `.gitignore` contains the §6 baseline block
     - Exit non-zero on any miss
2.2. Build `bin/sync-to-github.sh` per the 2026-05-11 decision:
     wrapper that **calls `scrub-public-repos.sh` then pushes** (scrub
     stays a separate, reusable tool — needed independently for the
     Forgejo pre-receive hook in Phase 5). Flow per repo:
     1. `--dry-run` flag mandatory by default; require explicit `--push`
     2. `cd <repo>` and `git fetch origin`
     3. Verify clean working tree
     4. Run `check-public-repo-hygiene.sh <repo>` — abort on fail
     5. Run `scrub-public-repos.sh <repo>` — abort on fail
     6. Run the orphan-rebase to `v0.1.0` per the 2026-05-07 Public Publish
        Readiness handoff (`docs/handoffs/DMF Public Publish Readiness
        Handoff 2026-05-07.md`)
     7. Push to `github` remote with `--refspec` gate (only the prepared
        branch + tag, never `--all`)
2.3. Stand up the `github.com/dmfdeploy` org. For each of the 6 public
     repos: create empty GitHub repo, add `github` remote locally, commit
     no content yet.
2.4. First **dry-run** of `sync-to-github.sh` against each of the 6 repos.
     Resolve all findings before any real push.

**Acceptance:**
- `bin/check-public-repo-hygiene.sh` exits 0 across all 6 public repos.
- `bin/sync-to-github.sh --dry-run dmf-cms` runs clean end-to-end.
- GitHub org `dmfdeploy` exists with 6 empty repos.

**Estimated effort:** 2 sessions.

### Phase 2.5 — Publish gate ✋

**Authorization checkpoint.** Phases 0–2 complete + dry-run clean = green
light for the **first real push**. Push one repo at a time, smallest blast
radius first (`dmf-central` → `dmf-media` → `dmf-runbooks` → `dmf-infra`
→ `dmf-cms` → `dmfdeploy`). After each push, do a manual `gh repo view`
sanity check. **Do not push the next repo until the previous one is
verified visually.**

### Phase 3 — Procedural enforcement (versioning + commits)

**Goal:** turn "VERSION drift → no release" and "Conventional Commits"
from convention into machinery.

**Steps:**

3.1. Build `bin/release.sh` per public repo (or a single umbrella-level
     orchestrator that takes a repo arg — operator preference). Flow:
     - Read `VERSION`
     - Verify CHANGELOG entry exists for that version
     - Run repo-local tests + lint
     - Tag `v<VERSION>` matching the file exactly; refuse on mismatch
     - Push tag to `origin` (LAN Forgejo); GitHub mirroring is Phase 4 CI's job
3.2. Build `bin/generate-changelog.sh` per repo. Idempotent. Parses commits
     since the last tag using Conventional Commits prefixes. Writes
     `CHANGELOG.md` with sections per version.
3.3. Add a `commit-msg` hook in `.githooks/commit-msg` that rejects commits
     not matching the Conventional Commits pattern. Install via
     `install-hooks.sh`. Same allowlist mechanism as gitleaks
     (`COMMITLINT_SKIP=1` escape hatch for emergencies).
3.4. Backfill `CHANGELOG.md` in each repo from existing tags (or from
     repo creation if no tags exist). One-time bulk operation.

**Acceptance:** `bin/release.sh --dry-run` works in each public repo;
intentional bad commit message (`updated stuff`) is refused by the
commit-msg hook; CHANGELOG.md present and populated in all 6 public repos.

**Estimated effort:** 2 sessions.

### Phase 4 — CI on GitHub Actions

**Goal:** §8 rows "Conventional Commits", "No secrets in commits" (layer
3), and "Apache 2.0 + LICENSE present" all enforced server-side, not
discipline-side.

**Steps (one workflow per concern, deployed to each public repo):**

4.1. `.github/workflows/secrets-scan.yml` — `gitleaks` on every PR and on
     `main` after push. Use a shared composite action in `dmfdeploy/.github`
     repo (or per-repo copy; decide during implementation).
4.2. `.github/workflows/hygiene.yml` — calls `bin/check-public-repo-hygiene.sh`.
4.3. `.github/workflows/commitlint.yml` — Conventional Commits check on PRs.
4.4. `.github/workflows/trivy.yml` — `trivy fs` scan; fail on `HIGH` and
     above (configurable).
4.5. Per-repo language CI:
     - `dmf-cms`: existing build (already has `.github/workflows/` shell)
     - `dmf-infra`, `dmf-runbooks`: `ansible-lint` + `yamllint`
     - `dmf-central`, `dmf-media`, `dmfdeploy`: minimal (lint markdown,
       check links)

**Acceptance:** each public repo has all 4 workflows green on the `main`
branch tip after first run. A deliberate bad PR (missing prefix, planted
secret, missing LICENSE) is rejected.

**Estimated effort:** 2 sessions.

### Phase 5 — Pre-receive + branch protection

**Goal:** Layer 2 of the defensive stack (the only one that can't be
bypassed locally) and structural lock-down on GitHub.

**Steps:**

5.1. LAN Forgejo: install gitleaks pre-receive hook that calls
     `bin/scrub-public-repos.sh --strict` on the receiving repo. Test by
     attempting to push a planted secret with `--no-verify` locally —
     server must reject.
5.2. GitHub branch protection per public repo:
     - Direct push to `main` blocked
     - PRs require at least one approval (CODEOWNERS auto-requests)
     - Required checks: `secrets-scan`, `hygiene`, `commitlint`, per-repo
       language CI
     - Linear history required (no merge commits)
     - Force-push blocked
5.3. Configure `dmfdeploy` org-wide rules to mirror per-repo settings
     so new repos inherit the posture.

**Acceptance:** `git push --no-verify` to LAN Forgejo with a planted secret
is rejected server-side. `gh api repos/dmfdeploy/<repo>/branches/main/protection`
returns the expected rule set for all 6 repos.

**Estimated effort:** 1 session.

### Phase 6 — Agent contract + ADR-0018 ratification

**Goal:** close the §7 LLM agent contract loop and convert the spec into
an accepted ADR.

**Steps:**

6.0. **Resolve open question: external contributor flow on the GitHub
     mirror.** fvwm's `docs/DEVELOPERS.md` spells out fork → add upstream
     → rebase → PR. Our spec is silent. Once GitHub repos go live, an
     external contributor's PR would land on the mirror, not on the
     Forgejo canonical. Decide and document one of:
     - **Closed model:** disable PRs on the GitHub mirror; instructions
       in `CONTRIBUTING.md` say "file an issue, we'll act on Forgejo."
     - **Open model:** accept GitHub PRs; document the round-trip back to
       Forgejo (operator pulls PR branch, replays on Forgejo, pushes,
       mirror gets it back via `sync-to-github.sh`, closes original PR
       with a pointer).
     - **Hybrid:** accept doc PRs (low-risk) on the mirror, redirect code
       PRs to Forgejo invitations.
     The decision lands as a paragraph in the spec doc §5 and in every
     repo's `CONTRIBUTING.md`. ADR-0018 cannot be marked Accepted with
     this open.
6.1. Audit `.claude/settings.json` against the §7 must / must-never list.
     Add hooks to deny:
     - `kubectl apply|patch|delete` outside of `bin/run-playbook.sh`
     - `helm upgrade` direct
     - `git commit --no-verify` / `--no-gpg-sign`
     - `git push --force` to `main` of any repo
     - Direct push to a `github` remote (require `bin/sync-to-github.sh`)
     - Writes under `<secure-store>/` or `/etc/rancher/`
6.2. Update `CLAUDE.md` boot ritual §6 cross-references with paths to the
     skills it gates (already documented; verify still accurate after the
     above changes).
6.3. Verify CODEOWNERS protects `.github/` and `bin/` in every public repo
     (already done — re-confirm).
6.4. Mark `docs/architecture/DMF Release and Contribution Model.md` as
     **Accepted**.
6.5. Write `docs/decisions/0018-release-and-contribution-model.md` citing
     the architecture doc as the detail.
6.6. Update `docs/decisions/INDEX.md`.
6.7. Update §8 of the spec doc to mark every row "✓ enforced" with the
     enforcing artifact path.

**Acceptance:** `docs/decisions/INDEX.md` lists ADR-0018 as Accepted; spec
doc §8 has no unenforced rows; deliberate agent-policy violations are
refused by Claude Code hooks.

**Estimated effort:** 1 session.

---

## 3. Dependency graph

```
Phase 0 (baseline files)
  └─→ Phase 1 (pre-commit gitleaks per repo)
        └─→ Phase 2 (hygiene + sync-to-github)
              └─→ Phase 2.5 ✋ FIRST PUSH GATE
                    └─→ Phase 3 (release.sh + changelog + commitlint)
                          ├─→ Phase 4 (GitHub Actions CI)
                          │     └─→ Phase 5 (branch protection)
                          └─→ Phase 6 (agent contract + ADR-0018)
```

Phases 4 and 6 can run in parallel after Phase 3.

## 4. Risks and decisions deferred

- **Where does `release.sh` live?** Per-repo copies vs. one umbrella
  orchestrator. Decide during Phase 3. Per-repo is more independent;
  umbrella is DRY but couples component release cadence to umbrella version.
- **GitHub Actions reusable workflows vs. per-repo copies.** Reusable
  workflows in a `dmfdeploy/.github` repo are DRY but add an indirection.
  Decide during Phase 4.
- **`dmf-env` posture.** The Release and Contribution Model classifies
  `dmf-env` as **Private**. This plan extends the gitleaks pre-commit and
  `.gitignore` baseline into `dmf-env`, but does NOT add a public mirror.
  Re-confirm during Phase 1 that `dmf-env` stays off the GitHub org.
- **Conventional Commits backfill.** Existing commits in the 4 newly-public
  repos use the "Initial public release v0.1.0" style. Phase 3.3's
  `commit-msg` hook only enforces going forward; we accept the existing
  baseline as-is.
- **Rotating the LAN-Forgejo and `forgejo-lab` URL passwords**
  (Phase 1.4, see §1 incidental findings) touches scripts and
  saved credentials across multiple machines. Coordinate with operator
  before flipping — currently scoped to a single session, but may spill.
- **External contributor flow on the GitHub mirror** is undefined today.
  Phase 6.0 must resolve it before ADR-0018 ratifies. See §6.0 above for
  the three candidate models.

## 5. Done definition

ADR-0018 is **Accepted** when:
- Every row in the spec doc §8 table has a working, non-discipline
  enforcement mechanism named.
- `bin/check-public-repo-hygiene.sh` passes on all 6 public repos.
- A deliberate-violation smoke test fails as expected in each of the 3
  defensive layers (pre-commit, pre-receive, CI).
- All 6 public repos are visible at `github.com/dmfdeploy/<repo>` with
  branch protection live.
- Each `STATUS.md` operator-notes section flags this stream as **done**
  before the ADR is marked accepted.
