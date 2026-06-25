---
status: executed
date: 2026-06-09
executed: 2026-06-10
---
# DMF Workstream A — Clean-History Import & Canonical Flip Execution Spec

**Date:** 2026-06-09 · **Status:** Draft for codex cross-check (PLANNING ONLY — no
execution without explicit per-repo operator go-ahead)
**Author:** umbrella session (claude, orchestrator)
**Parent plan:** [`DMF First Public Release Plan 2026-06-09.md`](DMF%20First%20Public%20Release%20Plan%202026-06-09.md) §Workstream A
**Supersedes the push-mirror model in:** [`DMF Public Publish Readiness Handoff 2026-05-07.md`](../handoffs/DMF%20Public%20Publish%20Readiness%20Handoff%202026-05-07.md)
**Depends on (all DONE):** C (ADR digests), B (dmf-env scrub), D (governance), E1 (PR-gate CI).

> **⚠️ This is the irreversible, outward-facing workstream** — it creates public GitHub
> repos and flips them public. Every outward step requires explicit operator approval at
> the time. Nothing here runs as a batch. **Private-first + visual verification before
> every public flip** is the core safety property.

---

## 0. What changed since the 2026-05-07 handoff (read this first)

The 2026-05-07 publish-readiness handoff left the original 6 repos at a single orphan
commit `Initial public release v0.1.0` (tag `v0.1.0`) with history on a LAN
`archive/pre-publish-2026-05-07` **tag**, and planned to publish via a **Forgejo
push-mirror → GitHub** (its Gate 1 = configure the mirror refspec to exclude `archive/*`).
**Three things invalidate that path and this spec replaces it:**

1. **The 2026-05-07 orphan state is STALE.** Five weeks of work (D, E1, mxl spike, NetBox
   monitoring, catalog, …) put full history back on every `main`. A must do a **FRESH
   orphan-rebase from the current `main` tip**, not reuse the old v0.1.0 orphan.
2. **The model is now GitHub-canonical-forward** (locked 2026-06-09). There is **no
   Forgejo push-mirror → GitHub** — that whole pipeline is RETIRED. A **disables** mirrors
   (the dmf-runbooks one was already removed 2026-06-09); it does not configure them. The
   2026-05-07 "Gate 1 push-mirror refspec" step is **reversed**.
3. **Archive is now a separate REPO, not a tag.** Locked decision: full pre-publish
   history → LAN-only `<owner>/<repo>-archive` repo (kept permanently), not an
   `archive/*` tag on the same repo (the old fragile approach that risked leaking via
   `git push --tags`).

Also: the 2026-05-07 Phase-D deferrals are now **closed** — LICENSE+NOTICE (D), commitlint
+ CI gates (E1), sub-repo hooks (D added `.githooks/pre-commit` to the 2 bare repos).

---

## 1. Locked decisions (recap) + the one OPEN decision

**Locked (do not re-litigate):** GitHub-canonical-forward; org `dmfdeploy`; Free-tier
**locked-window flip**; **DCO**; **retire-to-archive** (`<repo>-archive` LAN repos kept
permanently); **rebase-merge only** (operator 2026-06-09); CODEOWNER `@dmfdeploy/maintainers`
with **all-repository Write** (operator 2026-06-09); final public set = **9 repos**
(`dmf-platform` umbrella, `dmf-cms`, `dmf-runbooks`, `dmf-central`, `dmf-infra`,
`dmf-media`, `dmf-init`, `dmf-env`, `dmf-promsd`).

**OPEN — first-public-tag version per repo (needs operator decision, §11.1).** Current
`VERSION` files differ and **GHCR images already exist at those versions**:

| Repo | VERSION | GHCR image already public? |
|---|---|---|
| dmf-platform (umbrella) | 0.1.0 | n/a |
| dmf-cms | **0.10.0** | yes (`dmf-cms:0.10.0`) |
| dmf-runbooks | 0.1.2 | already PUBLIC on GitHub at `v0.1.2` |
| dmf-central | 0.1.0 | n/a (scaffold) |
| dmf-infra | 0.1.0 | n/a |
| dmf-media | 0.1.0 | n/a |
| dmf-init | **0.1.2** | image public |
| dmf-env | 0.1.0 | n/a |
| dmf-promsd | **0.1.3** | yes (`dmf-promsd:0.1.3`) |

Recommendation: **tag each repo's first public commit at its current `VERSION`** (not a
blanket `v0.1.0`). Resetting to v0.1.0 would desync from already-published GHCR images
(dmf-cms 0.10.0, dmf-promsd 0.1.3) and from dmf-runbooks' live `v0.1.2`. Treat VERSION as
"artifact maturity," independent of public-git-history depth. **sync-to-github.sh's
hardcoded `v0.1.0` must therefore be replaced by reading each repo's `VERSION`** (§4).

---

## 2. Preconditions (verify before any import)

- ✅ C/B/D/E1 committed locally on every repo's `main` (verify with `git -C <repo> log`).
- ✅ `dmfdeploy/maintainers` team: exists, `closed`, all-repository **Write** (done).
- ✅ dmf-runbooks Forgejo→GitHub push-mirror **removed** (done). **A must confirm no other
  repo has a Forgejo→GitHub push-mirror** before/at its import (a stale one auto-leaks the
  instant its GitHub repo exists).
- ✅ Merge method = rebase-only (set per repo at §5 step 9).
- **Freeze writes / pause agent dispatch** on a repo for the duration of its import.
- gitleaks installed locally (the harness needs it; `brew install gitleaks`).

### 2a. Tooling fixes REQUIRED before any import (codex round 1 — all verified live)

These block A and must land + self-test first (small lifts; gated like the rest):

- **`bin/dmf-env-public-surface-gate.sh` allowlist is stale** — it now **FAILS** on every
  D/E1 file added to dmf-env (`.github/**`, `.githooks/pre-commit`, `.gitleaks.toml`,
  `CONTRIBUTING.md`, `LICENSE`, `NOTICE`, `SECURITY.md`, `VERSION` → all "not in allowlist").
  **Add these governance/CI paths to the positive allowlist intentionally**, then rerun the
  positive-path **and** planted-bad self-tests (verified: `bin/dmf-env-public-surface-gate.sh`
  currently reports `FAIL — dmf-env tree is NOT public-safe`).
- **`.githooks/pre-push` hygiene gap** — `check-public-repo-hygiene.sh --repo <r>` fails on
  EVERY repo solely on missing `.githooks/pre-push` (verified on dmf-central + dmf-env;
  all other items ✓). That hook was the **old "sync-to-github push gate"** — obsolete under
  GitHub-canonical-forward. **Resolve before execution (codex: don't leave open):**
  RECOMMENDED — **drop `.githooks/pre-push` from the hygiene required-files list**
  (`check-public-repo-hygiene.sh:67`) since the sync-gate model is retired; alternative —
  add a trivial gitleaks pre-push hook to all 9. Either way, hygiene must pass clean so it
  can be a **blocking** export gate.
- **Gate scratch-tree support** — `scrub-public-repos.sh`, `check-public-commit-authors.sh`,
  `check-public-repo-hygiene.sh` are UMBRELLA_DIR/`.git`/default-list oriented; their default
  lists **omit dmf-env + dmf-promsd**, and they **silently skip missing repos** / can't scan
  an arbitrary export dir. The harness (§3) must add explicit **`--tree`/`--repo-root`** (or a
  scratch-parent + basename contract) modes, **update the repo lists** to include dmf-env +
  dmf-promsd, and **hard-fail if gitleaks is absent** (no silent skip). Do not assume
  existing gates can be "pointed at scratch" until this is implemented + self-tested.

---

## 3. The export-scan harness (new tooling — build + self-test FIRST)

Current gates assume repos under `UMBRELLA_DIR/$repo/.git` and **silently skip missing
repos** (`bin/scrub-public-repos.sh:146`, `bin/check-public-commit-authors.sh:66`) — so they
can't be trusted against an arbitrary export dir. Build a harness that stages a clean
orphan export and scans **that exact tree**:

`bin/export-scan.sh <repo>` (new):
1. Resolve `gh_name` + the first-public **tag** = the repo's `VERSION` (per §1 decision).
2. Stage a clean tree from the current `main` tip into a predictable scratch path
   (e.g. `$EXPORT_ROOT/<repo>/`): `git -C <repo> archive main | tar -x -C <scratch>` (drops
   `.git`, gives only tracked content at the tip — **no history**).
3. **Governance + CI are already committed on `main`** (D + E1), so they ride along in the
   `git archive` automatically — no separate bake step needed (the master plan's "bake INTO
   the export tree before the orphan commit" is satisfied because D/E1 are already on the
   tip). Verify they're present (`.github/`, `CONTRIBUTING.md`, `SECURITY.md`, `LICENSE`).
4. `git init` the scratch, set the orphan author/committer to a clean identity
   (`znerol2 <<user-id>+<handle>@users.noreply.github.com>` — NOT `<operator>`/local; closes the
   D/E1 local-signoff identity leak), `git add -A`,
   `git commit -s -m "Initial public release v<VERSION>"` (signed-off → satisfies DCO),
   `git tag v<VERSION>`.
5. **Scan the exact scratch tree** via the **adapted `--tree`/`--repo-root` gate modes**
   (§2a — these must exist + be self-tested first; do not run the default UMBRELLA_DIR forms):
   - `bin/scrub-public-repos.sh --tree <scratch>` → clean.
   - `bin/check-public-commit-authors.sh --tree <scratch>` → only the clean author on the
     single commit.
   - `gitleaks detect --source <scratch> --no-git --config <repo>/.gitleaks.toml` → no leaks
     (**hard-fail if gitleaks is not installed** — never silent-skip).
   - `gitleaks detect --source <scratch> --log-opts=main` → no leaks (1 commit).
   - `bin/check-public-repo-hygiene.sh --tree <scratch>` → all required files present
     (pre-push requirement already resolved per §2a, so this passes clean).
   - **dmf-env only:** `bin/dmf-env-public-surface-gate.sh <scratch>` (it takes a
     **positional** tree — `TREE="${1:-./dmf-env}"` — and runs `git ls-files`/`git grep`
     inside it, so the scratch must be the git-init'd orphan from step 4; needs only the
     §2a allowlist fix, no flag change).
6. Exit non-zero on ANY gate failure; never push from a failing scan.

**Self-test the harness** on a planted bad tree (e.g. inject a fake `*.tfstate` or an
operator-identity string) → it must FAIL closed, before trusting it on a real repo.

---

## 4. `sync-to-github.sh` — RETIRE, do not adapt (codex round 1)

It is **full-history-worktree oriented** (pushes the live repo's `main`), has stale
whitelist/refspec semantics (hardcoded `v0.1.0`, omits dmf-promsd), and **silently skips
gitleaks if absent** — all unsafe for the clean import. Adapting it risks accidentally
pushing live full history. Instead:

- **`export-scan.sh` owns the push.** Only the **verified scratch** (1-commit orphan, all
  gates green) can `git push github main v<VERSION>` — **`main` + exactly the one
  `v<VERSION>` tag, never `--tags`, never `--all`** (those would leak `archive/*` refs).
- **Retire `sync-to-github.sh`:** make it **refuse to run** in steady state and **impossible
  to run against the live full-history repos** (e.g. hard-stop / `exit 1` with a pointer to
  the PR-merge model + `export-scan.sh`). Steady state = normal PR-merge to GitHub `main`.

---

> **Scope framing (codex):** A delivers **8 component public repos now** (the 7
> clean-imports below + dmf-runbooks release-forward §6). **`dmf-platform` (umbrella) is
> deferred to a B2 doc-scrub follow-up (§7)** — so A does NOT complete the locked 9-repo set;
> it completes the 8 component repos and leaves the umbrella pending.

## 5. Per-repo import procedure (7 clean-import repos; NOT dmf-runbooks §6, NOT umbrella §7)

Order: **pilot one low-risk repo first** (recommend `dmf-central` — scaffold, smallest leak
surface), validate the whole flow end-to-end, THEN the rest. Per repo, operator-gated:

1. **Freeze** writes on the repo; pause agent dispatch.
2. **Create the archive repo** on LAN Forgejo (`<handle>/<repo>-archive`) capturing the
   **COMPLETE** pre-publish history = **(a) all LAN remote refs** (remote-only branches —
   there are several) **+ (b) the frozen local working-clone refs**, especially
   `refs/heads/main` at the **exact SHA being exported**. ⚠️ **The D/E1 commits are
   currently local-only — not yet on LAN `origin`** (verified: the 7 clean-import repos are
   ahead of LAN `origin` — dmf-env by 3, the rest by 2). So a plain `git clone --mirror
   <LAN>` taken *now* would **omit the D/E1 commits behind the public orphan** (codex) — the
   procedure below pushes them to LAN **first** so the archive is complete. Procedure for the
   **7 clean-import repos** (not yet on GitHub):
   1. **Confirm no Forgejo→GitHub push-mirror** on this repo (safe to push to LAN since no
      GitHub repo exists yet + no mirror).
   2. Push the **frozen local refs** to the live LAN repo: `git -C <repo> push origin main
      --tags` (+ any local branches). Now LAN `<handle>/<repo>` == local.
   3. Mirror it to the archive: `git clone --mirror <LAN <handle>/<repo>> /tmp/<repo>.git &&
      git -C /tmp/<repo>.git push --mirror <LAN <handle>/<repo>-archive>`.
   4. **Verification gate:** `git -C /tmp/<repo>.git rev-parse refs/heads/main` **==** the
      frozen local `git -C <repo> rev-parse main`; and the remote-only LAN branches/tags are
      present in the archive. Fail the import if not.
   - **dmf-runbooks differs (§6):** do **NOT** push local D/E1 to LAN `origin` (its origin is
     Forgejo + it's already public). Build `dmf-runbooks-archive` from the working clone's
     local refs + fetched LAN refs (push local `refs/heads/*`+`refs/tags/*` and the fetched
     LAN remote branches into the archive directly), or archive after the public PR — in all
     cases **without triggering any Forgejo→GitHub automation**.
   - The "never `--all`/`--tags`" rule applies only to the **GitHub scratch push** (steps
     4/5), never to these LAN-internal archive operations.
3. **Run `bin/export-scan.sh <repo>`** (§3) → clean orphan scratch + all gates green.
4. **Create the GitHub repo PRIVATE** (`gh repo create dmfdeploy/<gh_name> --private`).
5. **Push the orphan** `main` + `v<VERSION>` tag to the private GitHub repo (from the
   scratch; `main` + the single version tag only — **never `--tags`/`--all`**).
6. **Verify on GitHub (still private):** exactly **1 commit** on `main`; the `v<VERSION>`
   tag; **no `archive/*` refs, no old commits**; governance + CI files present; Actions tab
   shows the workflows. Visual README pass.
7. **Pre-flip access audit (codex round 1):** before flipping, confirm **no write-capable
   actor besides the owner** exists on the repo — no outside collaborators; **no team with
   write/admin except the operator**; no deploy keys / GitHub Apps / fine-grained tokens with
   write. **Note:** `dmfdeploy/maintainers` has **all-repository Write**, but its only member
   is `znerol2` (the owner), so it introduces **no third-party writer** — the "owner-only"
   intent holds. (If the team ever gains other members, suspend its access for the flip
   window.) Then flip **public**, owner-only / no further pushes, and **immediately**:
   - Branch **ruleset** on `main`: linear history, **block force-push**, **block deletion**,
     require PR + required status checks (the E1 `guard`/`ci` jobs + DCO) + **require
     review from Code Owners**, dismiss stale approvals.
   - **Tag ruleset:** protect `v*` from update/delete (except release automation),
     **restrict tag creation**, **block any non-`v*` tag** (closes the `archive/*`-via-
     `git push --tags` leak a stale clone could attempt).
   - **Merge method: enable ONLY "Rebase and merge"** (disable squash + merge-commit).
   - Enable native **secret scanning + push protection**.
   - Configure both rulesets with **no admin/owner bypass** where the Free tier allows
     (so even the operator can't accidentally force-push/weaken without an explicit ruleset
     edit).
   - **Rejection tests (all must be REJECTED before proceeding):** direct push to `main`;
     force-push to `main`; deleting `main`; creating a non-`v*` tag; and **`git push --tags`
     from a stale clone that still has old `v*`/`archive/*` local tags** (the real leak
     vector). Only after all are confirmed rejected do you continue.
8. **Retire Forgejo → archive:** confirm `<handle>/<repo>-archive` holds the full history;
   **disable any Forgejo→GitHub push-mirror**; demote the live Forgejo repo (it is
   archive-only henceforth, never the GitHub upstream).
9. **Repoint working clones:** `origin` → GitHub (`git@github.com:dmfdeploy/<gh_name>.git`);
   add read-only **`archive`** remote → `forgejo-<handle>:<handle>/<repo>-archive` so
   `git fetch archive` / `git log archive/main` keeps pre-publish history reachable locally.
   Document the `archive`-remote convention in the repo `CLAUDE.md` + umbrella `STATUS.md`.
10. **Only then** add collaborators / accept PRs (DCO check live).

> **Rollback safety:** through step 6 everything is private + reversible (delete the private
> repo, fix, re-run). The first irreversible-ish act is the **public flip** (step 7) — a
> public commit can be force-removed only via the maintainer leak-runbook, so the
> private-verify gate is the real safety net. Do one repo fully, confirm, then continue.

---

## 6. `dmf-runbooks` — RELEASE-FORWARD, do NOT re-import (exception)

dmf-runbooks is **already public at `v0.1.2`** on a clean DAG (pushed 2026-06-05). It must
**never be orphan-rebased / re-imported** — that would rewrite published history and break
any clone/fork (and public trust). Instead:
- Its **D + E1 commits (`b0f4a0c`, `186745b`) land as ONE normal PR** to
  `github.com/dmfdeploy/dmf-runbooks`, **rebase-merged**, once green. **VERSION SSOT
  (codex):** if the PR is to be tagged `v0.1.3`, it MUST include a `VERSION` bump
  `0.1.2 → 0.1.3` in the same PR (local VERSION is still `0.1.2`); otherwise **defer the
  tag to E2** and merge the PR untagged. Never tag without VERSION alignment (ADR-0005).
- **Remote hygiene (codex — live state):** dmf-runbooks' local `origin` is **still LAN
  Forgejo** (`git@forgejo-<handle>:<handle>/dmf-runbooks`); `github` is the GitHub remote. The PR
  branch must be **pushed only to the `github` remote, NEVER to `origin`** (a push to
  `origin` could re-trigger any residual Forgejo automation). After the public PR + rulesets
  + archive steps, **repoint `origin` → GitHub** and add a read-only **`archive`** remote →
  `<handle>/dmf-runbooks-archive`, exactly like the other repos (§5 step 9).
- It still gets: branch+tag rulesets, rebase-only, secret scanning (§5 step 7) and a
  `dmf-runbooks-archive`.
- The Forgejo push-mirror is already removed (2026-06-09) — **keep verifying no mirror
  exists** before any push, since `origin` still points at Forgejo.

---

## 7. `dmf-platform` (umbrella) — likely DEFER to a follow-up (open, §11.2)

The umbrella's `docs/` (handoffs, STATUS, plans, ADRs) is **saturated with operator
identity + internal topology** (`forgejo-<handle>`, `znerol2`, `<operator>`, LAN IPs, env ids) — that's
exactly what the **private** umbrella `.gitleaks.toml` `dmf-operator-identity` rule exists to
keep off public repos. A naive orphan export of the umbrella tip would **fail the
export-scan** (scrub + operator-identity gitleaks) on hundreds of doc lines. Publishing the
umbrella therefore needs its **own dedicated scrub pass** (a Workstream-B-style effort for
docs), which is **not** in C/B/D/E1.

**Recommendation:** **publish the 8 component repos first; defer `dmf-platform` to a
follow-up workstream** (call it B2 / "umbrella doc scrub") that decides what docs are public
vs. retained-private and scrubs identity/topology. This matches the standing
`project_public_publish_topology` note ("umbrella publish deferred — needs scrub+prune
first"). Operator confirms (§11.2).

---

## 8. Verification (per repo, before declaring done)

- Private GitHub repo: `git log --oneline` = **exactly 1 commit**; `git tag` = `v<VERSION>`
  only; **no `archive/*`, no old commits**; governance + CI present; Actions registered.
- export-scan harness: exits clean on the real tree; **fails closed** on a planted
  out-of-surface path / planted secret (self-test).
- Post-flip: a test `git push --tags` (or pushing a non-`v*` tag) is **rejected** by the tag
  ruleset; a direct push to `main` is rejected; force-push rejected.
- DCO + E1 `guard`/`ci` checks **run on a test PR** with read-only token + no secret access;
  secret-scanning push-protection blocks a planted secret.
- `archive` remote on the working clone exposes pre-publish history
  (`git log archive/main` works); `origin` = GitHub.
- **dmf-init repro (the real proof):** with `dmf-env` + `dmf-promsd` public, a clean
  `dmf-init/bin/build-bundle.sh` from the **public** remotes builds the bundle image and
  boots (`/healthz` ok) — proving a public user can reproduce/install.

---

## 9. Out of scope / explicitly deferred

- **E2** (release automation: VERSION→tag→GHCR, CHANGELOG, umbrella release manifest, the
  dmf-init appliance-bundle build + 14 GB hosted-runner-disk spike).
- **Umbrella publish** (§7 — separate doc-scrub workstream, pending operator confirm).
- Any history rewrite of dmf-runbooks (§6).
- **Adding a `.githooks/pre-push` hook is OUT of scope** (the sync-gate model is retired).
  But **updating `check-public-repo-hygiene.sh` to stop requiring that retired hook is IN
  scope and blocks A** (§2a) — so the hygiene gate passes clean as a blocking export gate.

---

## 10. Critical files

- New: `bin/export-scan.sh` (the harness — owns the verified scratch push, main + exactly
  `v<VERSION>`). **`bin/sync-to-github.sh` → retired/disabled** (made to refuse steady-state
  and impossible to run against live full-history repos; no dmf-promsd/refspec adaptation —
  any version/whitelist logic lives only inside `export-scan.sh`).
- Gates: `bin/scrub-public-repos.sh`, `bin/check-public-commit-authors.sh`,
  `bin/check-public-repo-hygiene.sh`, `bin/dmf-env-public-surface-gate.sh`.
- Reference (superseded push-mirror parts): `docs/handoffs/DMF Public Publish Readiness
  Handoff 2026-05-07.md`.

## 11. Decisions — codex-resolved + the 2 remaining OPERATOR calls

**codex round 1 resolved (technical):**
- ✅ **sync-to-github.sh → RETIRE** (not adapt); export-scan.sh owns the verified push (§4).
- ✅ **`.githooks/pre-push` → resolve before execution** (§2a) — recommend dropping it from
   the hygiene required list (retired sync-gate). Not left open during execution.
- ✅ **Gate scratch-tree modes + repo-list + gitleaks hard-fail** must be built+self-tested
   first (§2a/§3).
- ✅ **dmf-env surface-gate allowlist** must add the D/E1 governance paths first (§2a).
- ✅ **Archive = mirror clone/push** (§5.2); **dmf-runbooks VERSION bump before any tag** (§6).
- ✅ **Versioning = current-VERSION tags** (codex: a 1-commit `v0.10.0` is not a SemVer
   problem and aligns with already-public GHCR artifacts).
- ✅ **Umbrella deferred to B2**; A = 8 component repos, not the full 9.

**OPERATOR decisions — RESOLVED (2026-06-09):**
1. ✅ **First-public tag = current `VERSION` per repo** (cms `v0.10.0`, promsd `v0.1.3`,
   init `v0.1.2`, runbooks `v0.1.2`→`v0.1.3` on the D/E1 PR, rest `v0.1.0`). GHCR-aligned.
2. ✅ **Umbrella DEFERRED to a B2 doc-scrub follow-up.** A ships the 8 component repos only.

**Sequencing confirms (low-stakes, recommend-as-stated):**
3. **Pilot repo** = `dmf-central` (scaffold, smallest leak surface) — validate the full flow
   before the other 6 clean-imports.
4. **Archive repos** — create `<repo>-archive` for all 8 (cheap; uniform agent history access).
