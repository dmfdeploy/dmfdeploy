---
status: executed
date: 2026-06-09
executed: 2026-06-09
---
# DMF Workstream A — Pre-A Tooling Implementation Spec

**Date:** 2026-06-09 · **Status:** Draft for qwen lift (local/reversible — NO commits/pushes
by the lifter; NO outward GitHub/Forgejo actions)
**Author:** umbrella session (claude, orchestrator)
**Implements:** [`DMF Workstream A … Execution Spec 2026-06-09.md`](DMF%20Workstream%20A%20—%20Clean-History%20Import%20and%20Canonical%20Flip%20Execution%20Spec%202026-06-09.md) §2a + §3 (codex-AGREED).

> All work is in the umbrella's `bin/` + the dmf-env surface gate. **No network, no
> commits, no pushes, no GitHub/Forgejo actions.** The orchestrator runs the self-tests and
> commits after verification. Match each script's existing bash style.

---

## 1. `bin/dmf-env-public-surface-gate.sh` — add D/E1 governance paths to the allowlist

The Check-1 positive allowlist (`ALLOWLIST_RE`, ~line 31) predates D/E1 and now FAILS on the
governance/CI files D/E1 added to dmf-env. **Add these alternatives** to `ALLOWLIST_RE`
(keep all existing ones):

- `LICENSE` · `NOTICE` · `VERSION` · `SECURITY\.md` · `CONTRIBUTING\.md` · `\.gitleaks\.toml`
- `\.githooks/[^/]+` (the pre-commit hook)
- `\.github/.+` (CODEOWNERS, PULL_REQUEST_TEMPLATE.md, ISSUE_TEMPLATE/*, workflows/* — `.github`
  legitimately nests, so `.+` here is intentional, unlike the flat-dir `[^/]+` rule elsewhere)

Resulting regex (illustrative — preserve existing order/anchoring, just extend the group):
```
'^(bin/[^/]+|bin/lib/[^/]+|terraform/hetzner/.+|terraform/modules/hetzner/.+|terraform/README\.md|tasks/hetzner/.+|templates/[^/]+|tests/[^/]+|docs/answers-file-schema\.md|README\.md|CLAUDE\.md|QWEN\.md|\.gitignore|\.sops\.yaml|LICENSE|NOTICE|VERSION|SECURITY\.md|CONTRIBUTING\.md|\.gitleaks\.toml|\.githooks/[^/]+|\.github/.+)$'
```
Do NOT touch Checks 2–4 (ban list, retired-name scan, identity/topology scan). After the
edit the orchestrator self-tests: positive (current dmf-env tree → `OK … public-safe`) and
planted-bad (drop a stray `inventories/x` or `foo.tfstate` into a temp tree → still FAILS).

---

## 2. `bin/check-public-repo-hygiene.sh` — drop the retired pre-push hook + add tree mode + repos

- **CHECKS array (~line 67):** remove `.githooks/pre-push` (the retired sync-gate hook; no
  repo has it and the sync model is gone). Also update the header comment (lines ~13) that
  documents it. Keep all other checks.
- **PUBLIC_REPOS (~line 42):** add `dmf-env dmf-promsd` → `(. dmf-cms dmf-runbooks dmf-central
  dmf-infra dmf-media dmf-init dmf-env dmf-promsd)`. Update the stale comment.
- **Add `--tree <path>` mode:** when given, scan exactly that one path as the repo (set
  `REPOS=("<path>")` and make `repo_path` use the path **directly** when it's absolute or
  contains a `/`, instead of `$UMBRELLA_DIR/$repo`). Existing `--repo`/default modes unchanged.

---

## 3. `bin/scrub-public-repos.sh` — add tree mode + repos

- **PUBLIC_REPOS_DEFAULT (~line 31):** add `dmf-env dmf-promsd`.
- **Add `--tree <path>` mode:** scan exactly that single git tree. The script uses
  `git -C "$UMBRELLA_DIR/$repo" grep` and `git -C … ls-files`; in tree mode resolve the repo
  path **directly** to `<path>` (absolute) rather than `$UMBRELLA_DIR/$repo`. Keep `--strict`
  and the positional-list forms working. (Cleanest: a single helper
  `repo_path() { case "$1" in /*) printf %s "$1";; *) printf %s "$UMBRELLA_DIR/$1";; esac }`
  used everywhere `$UMBRELLA_DIR/$repo` appears, plus a `--tree` flag that pushes the absolute
  path as the sole repo.)

---

## 4. `bin/check-public-commit-authors.sh` — add tree mode + repos

- **PUBLIC_REPOS_DEFAULT (~line 25):** add `dmf-env dmf-promsd`.
- **Add `--tree <path>` mode:** check the single tree's `git log <ref>` authors/committers
  against `APPROVED_IDENTITIES` (same absolute-path resolution as §3). Confirm the approved
  list already matches `znerol2 <<user-id>+<handle>@users.noreply.github.com>` (the orphan
  re-author identity §6); if not present, ADD it.

---

## 5. `bin/sync-to-github.sh` — RETIRE (neuter, don't delete)

Replace the executable body with an **immediate hard stop** (preserve the file + a header
explaining why), e.g. right after the shebang/header:
```bash
echo "sync-to-github.sh is RETIRED (2026-06-09)." >&2
echo "GitHub-canonical-forward: steady state = PR-merge to GitHub main." >&2
echo "First import = bin/export-scan.sh (per-repo, operator-gated)." >&2
exit 1
```
It must be **impossible to push live full-history repos** with it. Keep the old logic below
the `exit 1` only as commented/quoted reference if convenient, or remove it — either way it
never runs.

---

## 6. `bin/export-scan.sh` — NEW harness (stage orphan scratch + scan; **NEVER push**)

`bin/export-scan.sh <repo>` — `<repo>` is a dir name (e.g. `dmf-central`). Behavior:

1. `set -euo pipefail`. **Hard-fail if gitleaks is missing** (`command -v gitleaks || {
   echo "FATAL: gitleaks required"; exit 1; }`).
2. Resolve `repo` dir under `$UMBRELLA_DIR`; refuse if missing or if `<repo>` is `.`
   (umbrella is deferred to B2) or `dmf-runbooks` (release-forward, not imported) — print why.
3. `VERSION="$(cat "$UMBRELLA_DIR/<repo>/VERSION")"`; `TAG="v$VERSION"`.
4. Scratch: `SCRATCH="${EXPORT_ROOT:-/tmp/dmf-export}/<repo>"`; `rm -rf "$SCRATCH"; mkdir -p`.
5. Export the tracked tip (no history): `git -C "$UMBRELLA_DIR/<repo>" archive main | tar -x
   -C "$SCRATCH"`.
6. **Sanity:** confirm governance/CI rode along — `.github/`, `CONTRIBUTING.md`, `SECURITY.md`,
   `LICENSE` exist in `$SCRATCH`; else FATAL (means D/E1 not committed on that repo's main).
7. Orphan commit with a CLEAN identity (not <operator>/local):
   ```bash
   git -C "$SCRATCH" init -q -b main
   git -C "$SCRATCH" -c user.name="znerol2" -c user.email="<user-id>+<handle>@users.noreply.github.com" \
     add -A
   git -C "$SCRATCH" -c user.name="znerol2" -c user.email="<user-id>+<handle>@users.noreply.github.com" \
     commit -sq -m "Initial public release $TAG"
   git -C "$SCRATCH" tag "$TAG"
   ```
   (the `-s` sign-off + clean author satisfy DCO and the commit-author gate.)
8. **Scan the exact scratch** (any failure → overall non-zero exit):
   - `bin/scrub-public-repos.sh --tree "$SCRATCH"`
   - `bin/check-public-commit-authors.sh --tree "$SCRATCH"`
   - `gitleaks detect --source "$SCRATCH" --no-git --config "$UMBRELLA_DIR/<repo>/.gitleaks.toml" --no-banner`
   - `gitleaks detect --source "$SCRATCH" --log-opts=main --no-banner`  (1 commit)
   - `bin/check-public-repo-hygiene.sh --tree "$SCRATCH"`
   - **if `<repo>` = dmf-env:** `bin/dmf-env-public-surface-gate.sh "$SCRATCH"` (positional)
9. **STOP — never push.** On all-green, print the scratch path, the 1-commit `git -C
   "$SCRATCH" log --oneline`, and the **exact command the operator would run** (for review),
   e.g.:
   ```
   READY: <repo> → scratch $SCRATCH, tag $TAG, gates GREEN.
   To import (operator, after creating the PRIVATE GitHub repo):
     git -C "$SCRATCH" remote add github git@github.com:dmfdeploy/<gh_name>.git
     git -C "$SCRATCH" push github main $TAG     # main + the one tag ONLY, never --tags
   ```
   Exit 0. **The script itself performs no `git push` and no `gh repo create`.**

`<gh_name>` map: same as the repos (umbrella→`dmf-platform`, else same name). Provide a small
`gh_name()` case; only the importable set matters (cms/central/infra/media/init/env/promsd).

---

## 7. Verification (orchestrator runs — do not trust DONE)

- `shellcheck` (via `uvx --from shellcheck-py shellcheck`) clean on all 5 changed/new scripts.
- **surface-gate:** `bin/dmf-env-public-surface-gate.sh` on current dmf-env → now PASSES
  (`OK … public-safe`); planted-bad temp tree → FAILS closed.
- **hygiene:** `--repo dmf-central` and `--repo dmf-env` → PASS (no pre-push failure);
  `--tree <dir>` works.
- **scrub / commit-authors:** `--tree <dir>` scan a sample tree cleanly; default lists now
  include dmf-env/dmf-promsd.
- **sync-to-github.sh:** running it → immediate `exit 1` with the retired message; cannot push.
- **export-scan.sh on pilot `dmf-central`:** produces `$SCRATCH` with **exactly 1 commit**
  (clean znerol2 author), tag `v0.1.0`, all gates GREEN, prints READY + the push command, and
  **pushes nothing** (verify: no `github` remote added in the real repo; `$SCRATCH` only).
  Also run on **dmf-env** (exercises the surface-gate path) and confirm it refuses `.`
  (umbrella) and `dmf-runbooks`.
- **Fail-closed proof:** plant a `foo.tfstate` (or an operator-identity string) into a repo's
  tree copy → export-scan exits non-zero.

Then: codex reviews the actual scripts → commit local-only (`feat(public-prep): pre-A export
-scan harness + gate --tree modes + retire sync-to-github`), signed off. NO pushes.
