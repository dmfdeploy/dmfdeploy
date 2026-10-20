---
status: executed
date: 2026-06-10
executed: 2026-06-10
---
# DMF LAN Forgejo — Archive + GitHub-Mirror Plan — 2026-06-10

**Status:** ✅ EXECUTED 2026-06-10 (interval 8h per operator) — see Execution box below

> ## Execution (2026-06-10)
> All 8 components done via the Forgejo API (admin `<handle>`): each renamed
> `dmf-<x>` → `dmf-<x>-archive` + **Archived** (history preserved — verified
> root/HEAD unchanged on every repo), and a new `dmf-<x>` **pull-mirror** of
> `github.com/dmfdeploy/dmf-<x>` created at **8h** interval (all verified
> tracking GitHub `main`). Umbrella untouched.
> - **Actions:** left **off** on the 7 CI-only mirrors (no redundant LAN CI);
>   **enabled on `dmf-init`** for its `workflow_dispatch` appliance build.
> - **Residuals for operator (UI — runner API not exposed in this Forgejo):**
>   (1) confirm the `dmf-builder` runner serves the new `<handle>/dmf-init` mirror
>   (it may have been repo-scoped to the now-archived original → re-register at
>   org/instance scope or move it); (2) optionally test the `workflow_dispatch`
>   build once, when convenient.
> - **§8.3 clone-retirement wrinkle — NOT done, needs a call:** the
>   `~/repos/dmfdeploy/<x>` clones are the **umbrella's sibling component
>   checkouts** that local tooling (boot ritual, generate-status) expects — not
>   purely legacy. Their `origin` now resolves to the read-only mirror (divergent
>   history). Deleting them would break the umbrella workspace. Options: leave
>   as-is; repoint origin to `-archive`; or relocate the whole umbrella working
>   setup to the `dmfgithub` clones (bigger change). Deferred to operator.

**Status (original):** Draft for operator review — not yet executed
**Goal:** On the LAN Forgejo (`<lan-forgejo-ip>`, user `<handle>`), preserve the full
pre-publish commit history of every component repo **and** keep a LAN copy that is
always current with the public GitHub canonical — without losing either.

## 1. The hard constraint (why two repos per component)

The first public release was a **clean orphan import**: GitHub's `main` shares **no
common root** with the LAN `main` (verified — e.g. dmf-runbooks LAN root `0eb94d1`
≠ GitHub root `02b39a4`). The histories diverge at the root, so a single repo/branch
**cannot** both retain the old history and track GitHub. Hence: **two LAN repos per
component.**

| LAN repo | Role | Source of truth | Writable? |
|---|---|---|---|
| `<handle>/dmf-<x>-archive` | Frozen **full pre-publish history** (today's LAN repo, **Archived** flag) | itself (frozen) | read-only |
| `<handle>/dmf-<x>` | **Pull mirror** of `github.com/dmfdeploy/dmf-<x>` | GitHub | read-only (mirror) |

This matches the `dmf-*-archive` read-only remote already promised in every
`CONTRIBUTING.md`. **Umbrella is excluded** — it is not on GitHub and stays the one
live read-write LAN repo.

Forgejo is `14.0.3` (Gitea 1.22 compat) — supports the Archived flag and pull
mirrors. Public GitHub repos mirror **anonymously** (no token needed).

## 2. Verified caveat — LAN Actions on mirror sync (2026-06-10)

Forgejo pull-mirror sync does **not** fire Actions on the synced refs (it isn't a
"push" event). Impact assessed against the live LAN runner:
- **`ci.yml`** (all repos, `on: [push, pull_request]`) — won't run on mirror sync.
  **Acceptable:** GitHub Actions is the canonical CI now; LAN CI on a read-only
  mirror is redundant.
- **`dmf-init/build-bundle.yml`** (`on: workflow_dispatch` + `push: tags: v*`) —
  the **primary trigger is manual `workflow_dispatch`**, which still works on a
  mirror. The auto-on-`v*`-tag path wouldn't fire on sync, but it was a follow-up
  ("once the build path is proven") and the operator builds manually today. The
  workflow is instance-agnostic by design (`${{ github.server_url }}`).
- **Residual to confirm in the pilot:** that `workflow_dispatch` is actually
  available/usable on a pull-mirror repo on this instance (enable Actions on the
  mirror repo if needed). This is the only open empirical question; it does not
  block the archive step.

## 3. Procedure (per component repo)

> Run the pilot (§4) first. All steps are reversible; the **rename preserves
> history** (Gitea keeps a redirect), and the Archived flag + mirror are toggleable.

For each of the 8 components (NOT umbrella):
1. **Archive the history:** rename `<handle>/dmf-<x>` → `<handle>/dmf-<x>-archive`
   (Settings → rename), then Settings → **Archive** (read-only). History preserved.
2. **Create the mirror:** New Migration → URL `https://github.com/dmfdeploy/dmf-<x>`
   → check **"This repository will be a mirror"** → owner `<handle>`, name
   `dmf-<x>` → anonymous (public). Set sync interval (e.g. `1h`).
3. **Verify:** mirror's `main` HEAD == GitHub `main` HEAD after first sync;
   `-archive` is read-only and still has the full (orphan-divergent) history.

Order: pilot → remaining 7. `dmf-init` last (it carries the build workflow).

## 4. Pilot (do this first)

Pick **`dmf-promsd`** (smallest, no Actions dependency):
1. Rename → `dmf-promsd-archive`, Archive it.
2. Create `dmf-promsd` pull-mirror from GitHub; force a sync; confirm HEAD matches.
3. Confirm the mirror is read-only in the UI and the archive is frozen.
4. **Then a dmf-init-shaped check:** on the mirror repo, confirm the Actions tab is
   present and a `workflow_dispatch` workflow can be manually run (enable Actions on
   the mirror if the toggle is off). This validates the §2 residual before we touch
   `dmf-init`.

## 5. `dmf-init` specifics
Mirror it like the rest. The appliance build runs via **manual `workflow_dispatch`**
on the mirror repo (unchanged operator action). If auto-build-on-tag is later wanted
on LAN, options: a scheduled LAN workflow that pulls+builds, or drive the build from
**GitHub Actions** (canonical) instead. Decide post-pilot.

## 6. Operator-local clone implications
The legacy `~/repos/dmfdeploy/<x>` clones point `origin` at LAN `dmf-<x>`. After the
rename+mirror, that name resolves to the **mirror** (GitHub content, divergent root)
— a `git pull` there would hit "unrelated histories". Since real work now happens in
`~/repos/dmfgithub/dmfdeploy/<x>` (see memory `project_github_pr_clones`), the
recommended cleanup is: **retire the `~/repos/dmfdeploy/<x>` component clones** (keep
only the umbrella clone there). If the old history is needed locally, clone
`<handle>/dmf-<x>-archive` on demand.

## 7. Safety / rollback
- **No history is destroyed:** the rename preserves the repo; only the *name* and a
  read-only flag change. The mirror is additive.
- **Reversible:** un-archive to make writable again; delete a mirror to remove it.
- **Do NOT** ever configure a pull-mirror on the history-bearing repo (it would
  force-overwrite refs from GitHub and clobber the orphan history). The mirror is
  always a *new* repo; the history repo is only ever renamed + archived.

## 8. Open decisions for the operator
1. **Sync interval** — `1h` proposed (Forgejo min is configurable; balances freshness
   vs load).
2. **Mirror all 8, or skip any?** Default: all 8 (dmf-init included, build via manual
   dispatch).
3. **Retire the LAN-origin working clones** (`~/repos/dmfdeploy/<x>`) — recommended
   yes; confirm.
4. **Umbrella** — stays live LAN-only for now. Its eventual GitHub publish is a
   separate, later decision.

## 9. Acceptance
- All 8 `dmf-<x>-archive` repos: Archived (read-only), full history intact
  (root commit unchanged).
- All 8 `dmf-<x>` repos: pull-mirror, `main` HEAD tracks GitHub within the sync
  interval.
- `dmf-init` appliance build runnable via `workflow_dispatch` on the mirror.
- Umbrella untouched.
