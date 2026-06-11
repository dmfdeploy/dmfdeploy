# DMF Move 2 Closure + Path A Handoff — 2026-05-04

**Session:** /plan-ceo-review on the umbrella, Path B selected (Move 2 write-up
first, then public-push prep).

## What was done this session

1. Surveyed `docs/` (architecture, plans, reviews, handoffs, decisions). Read
   the strategic review, chain review, Move 2 task spec, and most-recent
   handoff. Verified Move 2 implementation state in `dmf-cms/` and
   `dmf-infra/k3s-lab-bootstrap/`.

2. Confirmed Move 2 substantially landed:
   - 10 apps registered as NetBox `ipam.Service` (defaults in
     `roles/common/dmf-born-inventory/defaults/main.yml`)
   - AWX svc-account token wired via `playbooks/697-cms-awx-token.yml`
   - dmf-cms ↔ AWX client at `dmf-cms/src/dmf_cms/awx.py`, endpoints in
     `main.py:282-345`
   - Smoke test at `playbooks/699-cms-smoke-test.yml`
   - The plan-mandated "write-up of what was learned" was missing.

3. Wrote that write-up:
   `docs/reviews/dmf-platform-move-2-learnings-2026-05-04.md`. Anchored to
   evidence in the codebase. Key surprises captured:
   - NetBox v4 changed `ipam.Service.device` from FK to generic relation
     (`parent_object_type` / `parent_object_id`). The Move 2 plan was wrong
     on this; the role pivoted.
   - `app-contract` narrowed (no `oidc_client_id` / `exposure`); those moved
     to NetBox `comments`.
   - `/me/` verification idea didn't survive; smoke test uses
     `/api/v2/inventories/` reachability instead.
   - Per-user identity is **not** preserved end-to-end — dmf-cms acts as
     `dmf-cms-svc` for all AWX calls. Deferred deliberately.
   - Bonus: NetBox v4 v2-token format, heredoc + Ansible footgun, OpenBao
     mode-toggle was failing open (already fixed in `9bdf758`).

4. Updated `docs/INDEX.md` — added learnings doc under `reviews/`.

5. Updated `TODOS.md` — Move 2 marked ✓ closed with cross-reference.

## Commit gate status

Per the strategic review's gate:

| Condition | Status |
|---|---|
| First vertical slice end-to-end | ✅ DONE (Move 2) |
| NMOS registry deployed in `dmf-media` | ❌ NOT STARTED (Move 1) |
| `docs/architectural-commitments-v1.md` written | ❌ Pending both |

**Half-met.** Move 1 (NMOS spike) is now the sole remaining gate item.

## Open questions — for Path A (public push)

User selected Path B (Move 2 write-up + Path A in same week). The write-up is
done. **Path A has not started.** Four decisions are pending before any
license / README / scrub / push work:

### Q1 — Which repos go public initially?

- **A1** — `dmfdeploy` (umbrella) only. Smallest blast radius.
- **A2** — `dmfdeploy` + `dmf-infra`. Adds the generic-public-intended
  infra code; per-repo CLAUDE.md already says it's public-intended.
- **A3** — Above + `dmf-cms` (v0.6.0 application code).
- **A4** — Above + scaffolds (`dmf-central`, `dmf-media`) as
  reservations.
- `dmf-env` stays private regardless (site-specific; break-glass paths;
  `<lan-host>` inventory).

### Q2 — GitHub destination

Personal account? Existing org? New org? Need the namespace to draft
remotes.

### Q3 — License

- **MIT** — most permissive
- **Apache-2.0** — patent grant + contribution clause; common for infra
- **AGPL-3.0** — copyleft for SaaS

Earlier lean was **Apache-2.0** for a portfolio infra/architecture piece.
Not yet confirmed.

### Q4 — Forgejo posture after GitHub push

- Forgejo primary, GitHub mirror (push to both)
- GitHub primary, Forgejo retired or read-only
- Both active, manual choice per push

### Pre-push blockers (independent of Q1-Q4)

These need attention regardless of which repos are pushed:

- [ ] `LICENSE` file in each in-scope repo
- [ ] Top-level `README.md` in each in-scope repo (currently none of the 6
  have one — checked)
- [ ] In-tree secret scrub for each in-scope repo:
  - `Admin123` in CLAUDE.md (flagged P0 by Pre-Rebuild Review, status
    unconfirmed)
  - NetBox API token plaintext in Forgejo SCM (Pre-Rebuild Review P0)
  - `<lan-host>` references — decide which are "example domain" (keep)
    vs site-specific (scrub)
  - General `git log --all -p | grep -iE 'password|token|secret'` sweep
- [ ] History scrub decision — separate, harder pass; needed if the in-tree
  scrub turns up history-only leaks
- [ ] Per-repo CLAUDE.md `<note-store>/Projects/...` path cleanup (umbrella
  CLAUDE.md flagged this as pending). Some repos already have the rewrite
  commit (`ba2ac04` in dmf-infra, `19257d9` in dmf-cms); umbrella
  CLAUDE.md note may be stale — needs verification per-repo.

## Files touched

- **Created:** `docs/reviews/dmf-platform-move-2-learnings-2026-05-04.md`
- **Edited:** `docs/INDEX.md` (added learnings entry under `reviews/`)
- **Edited:** `TODOS.md` (Move 2 marked closed)
- **Created:** this handoff

No code in component repos was modified. Nothing was committed. Nothing was
pushed.

## Pickup steps for next session

1. Read `docs/reviews/dmf-platform-move-2-learnings-2026-05-04.md` for
   context on what Move 2 actually taught us.
2. Resolve Q1-Q4 with the user.
3. Address pre-push blockers in dependency order: secret scrub first
   (could surface history-scrub work), then LICENSE, then README, then
   remote add + push.
4. Decide whether to also kick off Move 1 (NMOS spike) — that's the
   remaining commit-gate item and was deferred to "after the public push"
   under Path B.

## Cross-reference

- Move 2 learnings: [`docs/reviews/dmf-platform-move-2-learnings-2026-05-04.md`](../reviews/dmf-platform-move-2-learnings-2026-05-04.md)
- Strategic review (the framing for everything above): [`docs/reviews/dmf-platform-strategic-review-2026-04-30.md`](../reviews/dmf-platform-strategic-review-2026-04-30.md)
- Move 2 task spec: [`docs/plans/dmf-platform-move-2-task-2026-04-30.md`](../plans/dmf-platform-move-2-task-2026-04-30.md)
- Prior session's handoff (privilege audit, still partly open): [`DMF Bootstrap User Privileges Handoff 2026-05-03.md`](DMF%20Bootstrap%20User%20Privileges%20Handoff%202026-05-03.md)
