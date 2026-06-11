# DMF dmf-runbooks Path A Public Publish — Completion Handoff

**Date:** 2026-05-22
**Author:** session that executed Phases 1-7 of the 2026-05-21 Path A handoff and validated the bootstrap unblock end-to-end on `g2r6-foa9`
**For:** the next session/agent that picks up either (a) expansion to the remaining 5 public DMF repos, or (b) any work touching the `forgejo-bootstrap` role / cluster Forgejo mirror lifecycle.

> **2026-05-23 supersession note:** Public history was remediated again after
> a stricter presentation/security audit found public-history topology
> breadcrumbs and public guard files that named operator-specific identity
> patterns. See
> [`DMF dmf-runbooks Public History Remediation Handoff 2026-05-23.md`](DMF%20dmf-runbooks%20Public%20History%20Remediation%20Handoff%202026-05-23.md).
> GitHub now exposes only `main` and `v0.1.2`, both at `0eb94d1`; `v0.1.0`,
> `v0.1.1`, and stale `master` are no longer public.

> 🛑 **READ FIRST:**
> [`docs/handoffs/DMF dmf-runbooks Public Publish Path A Handoff 2026-05-21.md`](DMF%20dmf-runbooks%20Public%20Publish%20Path%20A%20Handoff%202026-05-21.md)
> — the executed plan. This handoff records what landed, where reality differed
> from the plan, and what's still in flight.

---

## TL;DR

Path A for `dmf-runbooks` is **live end-to-end**:

```
Operator → LAN Forgejo (<lan-ip>/<lan-user>/dmf-runbooks)
            ↓ push-mirror, branch_filter=main, sync_on_commit
        github.com/dmfdeploy/dmf-runbooks  (PUBLIC, v0.1.1, branch-protected)
            ↓ pull-mirror via forgejo_mirror_repos, 1h interval
        per-cluster in-cluster Forgejo
            ↓
        AWX project sync → catalog JT create succeeds
```

The original blocker — `bootstrap-configure.yml`'s AWX catalog JT create step
at `awx-integration/tasks/main.yml:1085` returning HTTP 400 because the
cluster Forgejo's `dmf-runbooks` was empty — is **closed**. The bootstrap
on `g2r6-foa9` now gets all the way through that step. A separate downstream
failure at `697-cms-awx-token.yml:121` (AWX admin-user 401) currently blocks
`bootstrap-configure` completion — see the **DMF Two-Identity Admin Model
Implementation Handoff 2026-05-22** for that thread (PR1 = same-session 1-line
fix; PR2 + ADR-0024 follow-on).

---

## What landed (summary by phase)

### Phase 1: re-orphan `dmf-runbooks` to v0.1.1

- Strategy 2 (re-orphan, not fixup) per operator decision. Old 7-commit chain
  carrying `ada0c75`'s leak collapsed into a single orphan commit `d19b6af`.
- Tag `pre-republish-2026-05-21` on the old `d928bfe` tip (operator workstation
  only; intentionally NOT pushed to LAN Forgejo or GitHub — see Phase 5 cleanup).
- Tag `v0.1.1` at the new orphan.

### Phase 2: gates + polish

- `gitleaks detect --log-opts=main` clean ✓
- `gitleaks detect --no-git` clean ✓
- `bin/scrub-public-repos.sh` reported **zero** matches for dmf-runbooks
  itself. (Found 200+ matches in umbrella docs/ and 8 in dmf-infra
  k3s-lab-bootstrap/ — out of scope for this session, in scope for the
  remaining-5-repos expansion.)
- Polish landed by amending the orphan commit (not a fixup):
  - `VERSION` 0.1.0 → 0.1.1
  - Empty `.gitmodules` deleted
  - Three relative `../docs/` umbrella-tree markdown links (broken for any
    standalone-repo viewer on GitHub) converted to plain ADR-name references
- Final orphan SHA: `d19b6af`.

### Phase 3: GitHub repo create

- `gh repo create dmfdeploy/dmf-runbooks --private` — created.
- `gh` installed via Homebrew this session; operator did `gh auth login`
  themselves so PAT didn't pass through the agent's tool calls
  (ADR-0007 — secrets never in argv).

### Phase 4: first push + visibility flip

- `git remote add github` initially used SSH URL per handoff template;
  failed because operator's GitHub SSH key isn't registered. Switched
  to HTTPS + `gh auth setup-git` for credential helper (operator action).
- Pushed `main` + `v0.1.1` (not `--tags`, per handoff Gate 1). Verified
  GitHub side via `gh api`: 1 commit, 1 tag, LICENSE rendered.
- Visibility flipped to public via `gh repo edit --visibility public
  --accept-visibility-change-consequences`.

### Phase 5: LAN Forgejo push-mirror — three deviations from the 2026-05-21 plan

**Deviation A — topology correction.** The handoff said `origin =
forgejo.<stale-decommissioned-host>/forgejo-svc/dmf-runbooks.git = "lab Forgejo on
Hetzner" = canonical operator workflow target`. Reality:
- `forgejo.<stale-decommissioned-host>` = NXDOMAIN (stale; the env was renamed/decommissioned)
- `forgejo.<cluster-base-domain>` resolves to Tailscale IPs `<tailscale-cluster-ips>` =
  the **in-cluster** Forgejo on g2r6-foa9 (downstream pull-mirror consumer,
  not the operator push target)
- Operator's canonical push target is the **LAN Forgejo at
  `<lan-ip>/<lan-user>/dmf-runbooks`** (`local` remote in git terms, owner `<lan-user>`,
  not `forgejo-svc` as the 2026-05-21 handoff template assumed)

→ Future handoffs/docs that reference "lab Forgejo on Hetzner" as the
canonical push target are **inaccurate** for this operator's setup.

**Deviation B — Forgejo's "push-mirror" UI doesn't support custom refspecs.**
The handoff said "set explicit refspec `+refs/heads/main:refs/heads/main` and
`+refs/tags/v*:refs/tags/v*`". In Forgejo 14.0.3+gitea-1.22.0, that UI field
is `branch_filter` (single token, applies to branch names only — tags are
always pushed regardless). Pasting refspec syntax in produced a mangled
`refs/heads/+refs/tags/v0.1.1:refs/tags/v0.1.1` string and the mirror push
failed. Resolution:
- Set `branch_filter=main` (just the word `main`)
- Delete the forensic tags (`archive/pre-publish-2026-05-07`,
  `pre-republish-2026-05-21`) from LAN Forgejo, since Forgejo will push all
  tags in `refs/tags/*` regardless of branch_filter. They survive on the
  operator workstation as personal archives.
- LAN Forgejo's stale `master` branch (legacy from pre-2026-05-07 rename)
  stays on LAN Forgejo but `branch_filter=main` excludes it from GitHub.

**Deviation C — direct-push to GitHub first, then reconcile LAN Forgejo.**
The handoff's Phase 4 has operator push directly to GitHub before setting up
the mirror. Side-effect: LAN Forgejo and GitHub disagreed about `main`
(old `d928bfe` 7-commit chain on LAN vs new `d19b6af` orphan on GitHub).
Reconciliation required three operator-run pushes against LAN Forgejo:
1. Push `pre-republish-2026-05-21` tag to LAN Forgejo (then later deleted —
   see Deviation B)
2. `git push --force local main` (LAN Forgejo's main → `d19b6af`)
3. Push `v0.1.1` tag

After reconciliation, LAN Forgejo's push-mirror first sync was a no-op
(LAN ≡ GitHub).

### Phase 6: GitHub branch protection on `main`

Set via `gh api -X PUT`:
- `required_linear_history: true`
- `allow_force_pushes: false`
- `allow_deletions: false`
- `enforce_admins: true` (protection applies to operator too — must
  explicitly disable to recover from a stuck push)
- `required_status_checks: null` (deferred until CI exists)
- Tag protection on `v*` tags **skipped** — endpoint deprecated; the rulesets
  API replacement was deemed out of scope. Worth landing later via web UI.

### Phase 7: cluster Forgejo pull-mirror + role hardening

Two-track:

**Track A (immediate g2r6-foa9 unblock):** `claude-bottom` (pane 4 agent)
empirically verified Forgejo's invariant that **mirror state can only be set
at repo creation via `/repos/migrate`**. The role's prior PATCH-based mirror
task returned HTTP 200 but silently no-op'd the mirror flag — POST to
`/mirror-sync` then 400'd with "Repository is not a mirror". DELETE +
POST `/repos/migrate` worked. Mirror live; ls-remote on cluster Forgejo
matches GitHub exactly.

**Track B (role fix for all future envs):** `dmf-infra` commit `a604812`:
- New `tasks/ensure-mirror-repo.yml` include with GET-check +
  DELETE-if-not-mirror + POST-migrate idempotency. UID lookup via
  `/users/{forgejo_svc_user}` only fires on create/recreate path.
- `forgejo_repos` GET/create loop now filters out mirror-listed repos via
  `| difference((forgejo_mirror_repos | default({})).keys() | list)` so
  they aren't pre-created as non-mirror repos before the migrate step.
- `forgejo_mirror_repos` default populated:
  `dmf-runbooks: https://github.com/dmfdeploy/dmf-runbooks.git`
- `Push initial README` task `when:` extended to skip if dmf-runbooks
  is in `forgejo_mirror_repos` (mirror repos 422 on contents POST).
- 692-forgejo-bootstrap re-run on g2r6-foa9 verified idempotent: all four
  ensure-mirror-repo gates `skip`/`ok`, `mirror_updated` timestamp unchanged.

**Bootstrap-configure unblock:** confirmed by operator's run on g2r6-foa9.
AWX catalog JT create step succeeded (570 ok / 16 changed / 138 skipped).
Subsequent failure at `697-cms-awx-token.yml:121` is unrelated — see the
two-identity handoff.

---

## What lives where now

| Artifact | Location |
|---|---|
| Public canonical source | `github.com/dmfdeploy/dmf-runbooks` (main `d19b6af`, v0.1.0 + v0.1.1 tags) |
| Operator push target | `http://<lan-ip>/<lan-user>/dmf-runbooks.git` (`local` remote in git) |
| Cluster Forgejo mirror (g2r6-foa9) | `https://forgejo.<cluster-base-domain>/forgejo-svc/dmf-runbooks` (pull-mirror, 1h interval) |
| LAN Forgejo push-mirror config | LAN Forgejo Settings → Mirror Settings, branch_filter=main, sync_on_commit |
| Forensic tags (pre-orphan history) | Operator workstation only: `pre-republish-2026-05-21` @ `d928bfe`, `archive/pre-publish-2026-05-07` @ `08058d9a`. NOT on any Forgejo or GitHub. |
| Role idempotency mechanism | `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/ensure-mirror-repo.yml` |
| Stale `master` branch | LAN Forgejo only (`1fab1631`). Excluded from GitHub via `branch_filter=main`. Cleanup deferred. |

---

## Out of scope / explicit deferrals (queued for the next session)

### 1. Expansion to the other 5 public repos

Per the 2026-05-21 handoff §Expansion plan, the remaining DMF public repos
use the same procedure but each needs its own pre-publish leak audit.

| Repo | GitHub target | Pre-publish work |
|---|---|---|
| `dmf-platform` (umbrella, lab Forgejo path: `<lan-user>/dmf-platform`) | `github.com/dmfdeploy/dmf-platform` | **104 stem + 102 TLD matches** in docs/ tree. Substantial scrub. Most are in operator handoffs/plans/sessions referencing the actual hostnames. |
| `dmf-cms` | `github.com/dmfdeploy/dmf-cms` | Operator console; matching image already on GHCR. Status: 2 unpushed commits on `main`. Pre-publish audit not run. |
| `dmf-central` | `github.com/dmfdeploy/dmf-central` | Phase 0 scaffold. 1 unpushed commit on `main`. |
| `dmf-infra` | `github.com/dmfdeploy/dmf-infra` | 8 stem matches in k3s-lab-bootstrap/. Cleanup before publish. |
| `dmf-media` | `github.com/dmfdeploy/dmf-media` | Media catalog metadata + (future) Layer 5 roles. 1 unpushed commit on `main`. |

`dmf-env` **never goes public** (Gate 2).

For each: re-run `gitleaks detect --log-opts=main` + `bin/scrub-public-repos.sh`,
fix leaks (Strategy 1 fixup or Strategy 2 orphan per scope), then repeat
Phases 3-6 of the 2026-05-21 handoff. The push-mirror setup for each is
identical to dmf-runbooks (LAN Forgejo Settings → Mirror Settings,
`branch_filter=main`, same long-lived classic PAT for auth). Add an entry
to `forgejo_mirror_repos` in `dmf-infra` defaults for each cluster-consumed
repo (currently just dmf-runbooks; future expansion may pull more).

### 2. Tag protection on GitHub `v*` tags

Per handoff Phase 6 "optional but recommended". GitHub's classic
`/repos/.../tags/protection` is deprecated (404 today). Use the rulesets
API (`POST /repos/.../rulesets` with appropriate include patterns) or
the web UI: Settings → Rules → Rulesets → New ruleset → tags pattern `v*`,
restrict deletions + creations.

### 3. Stale `master` branch cleanup across LAN Forgejo

Per umbrella CLAUDE.md "All 7 repos use main as the default branch" but
LAN Forgejo still carries stale `master` branches (verified for
dmf-runbooks; likely also dmf-infra and others). Excluded from GitHub
mirrors via `branch_filter=main`, but worth removing in a cleanup pass
for hygiene.

### 4. Documentation correction — "lab Forgejo on Hetzner" framing

The 2026-05-21 handoff (and possibly others) frames the canonical
operator push target as "lab Forgejo on Hetzner" with placeholder
`<lab-forgejo-host>`. Operator's actual canonical push target is
the **LAN Forgejo at <lan-ip>** (the `local` git remote per
operator naming). Existing handoffs/docs that conflate "lab" and
"cluster" Forgejos with "LAN" Forgejo need a correction sweep. Not
urgent, but worth noting because following the 2026-05-21 handoff
literally got us a wrong-target push attempt this session.

### 5. CI on PR for gitleaks/scrub

Per the 2026-05-07 readiness handoff §"What was deliberately deferred".
Local pre-commit hook is sufficient for the dmf-runbooks publish; CI is
belt-and-braces. Worth landing when expansion runs catch a leak the
pre-commit missed.

### 6. Conventional Commits / commitlint / automated CHANGELOG

Same deferral as above. Strategy 2's orphan-rebase loses individual commit
history anyway; granular changelog only becomes useful from v0.1.2 onward.

### 7. Forgejo pre-receive server-side gitleaks

Defense in depth; not blocking. Would catch the case where a developer
without local hooks pushes a leak.

---

## Gates status (echoed from 2026-05-21 handoff)

| Gate | What | Status |
|---|---|---|
| Gate 1 | Forgejo push-mirror refspec excludes `archive/*` tags | ✓ via `branch_filter=main` + forensic-tag deletion on LAN Forgejo |
| Gate 2 | `dmf-env` never goes public | ✓ (not touched this session) |
| Gate 3 | `gitleaks detect --log-opts=main` returns "no leaks found" | ✓ for dmf-runbooks at `d19b6af` |
| Gate 4 | `bin/scrub-public-repos.sh` returns "OK — clean for public publish" | ⚠️ NOT cleanly green for the umbrella overall (umbrella + dmf-infra still have matches), but dmf-runbooks itself is clean. Gate 4 for the expansion needs the umbrella sweep first. |
| Gate 5 | After first sync, no `archive/*` tag on GitHub | ✓ verified post-sync |

---

## References

- Predecessor handoff (the plan I executed):
  [`docs/handoffs/DMF dmf-runbooks Public Publish Path A Handoff 2026-05-21.md`](DMF%20dmf-runbooks%20Public%20Publish%20Path%20A%20Handoff%202026-05-21.md)
- Readiness baseline:
  [`docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07.md`](DMF%20Public%20Publish%20Readiness%20Handoff%202026-05-07.md)
- Adjacent in-flight thread (697 unblock + two-identity admin model):
  [`docs/handoffs/DMF Two-Identity Admin Model Implementation Handoff 2026-05-22.md`](DMF%20Two-Identity%20Admin%20Model%20Implementation%20Handoff%202026-05-22.md)
- ADR-0025 (canonical-on-public pattern that Path A extends to source code):
  `docs/decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md`
- Role fix:
  `dmf-infra` commit `a604812` — `forgejo-bootstrap/tasks/ensure-mirror-repo.yml`
- Role default + README-skip:
  `dmf-infra` commit `afff1c7` — superseded by `a604812` for the mirror-task logic;
  the default + README-skip parts remain in force.

---

**End of completion handoff.** Pick up the expansion to the remaining
5 public repos when ready, or the two-identity work for the bootstrap-
configure completion path, depending on priorities.
