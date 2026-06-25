---
status: executed
date: 2026-05-11
---
# DMF Public Repo Identity Leak Sweep (2026-05-11)

**Status:** Draft — actively executing
**Date:** 2026-05-11
**Author:** umbrella session investigating identifying-artifact residue
**Supersedes:** none
**Related:**
- `docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07.md` (parent — defines the publish gates this plan extends)
- `docs/architecture/DMF Release and Contribution Model.md` (defensive layer this plan hardens)

---

## TL;DR

The 2026-05-07 publish-prep landed a strong defensive layer (orphan rebase to `v0.1.0`,
gitleaks pre-commit, scrub script, CODEOWNERS, `.gitignore` baseline, IP/domain
variabilization). But the scrub script and gitleaks config have a blind spot: **operator
identity**. A quick survey of the six public repos found `<operator>`, `/Users/<operator>`,
`/Volumes/<operator>`, `/home/<operator>`, `<operator-workstation>`, and per-commit author `<operator-name> <<operator>@<operator-workstation>>`
across tree content and git metadata. This plan closes that gap before the first push
to GitHub.

## Goals

1. Catalog every category of identifying artifact that could leak via a public push.
2. Extend the three defensive layers (scrub, gitleaks, CI) to BLOCK on those patterns.
3. Sweep tracked content of every public repo and parameterize, rewrite, or allowlist
   each hit.
4. Rewrite the orphan v0.1.0 commit author identity to a neutral public form *before*
   any push.
5. Wire continuous protection so the same regressions cannot reappear.

## Non-goals

- Republishing or rotating any LAN-only credential (`dev:changeme`, etc.) — handoff
  Gate 2 already covers; archive history stays LAN-only.
- License/NOTICE work (handoff Phase D deferred — separate plan).
- External-contributor model decision (Release Model §5 TBD — separate plan).
- Repository renames (`k3s-lab-bootstrap` rename, etc.).

---

## Threat surfaces found (survey, 2026-05-11)

| # | Surface | Concrete examples |
|---|---|---|
| 1 | Operator filesystem paths | `<repos>/dmfdeploy` (every sub-repo agent doc); `<secure-store>/openbao-breakglass/...` (skill files); `<repos>/...` (`dmf-media/playbooks/lifecycle-operate.yml`); `$HOME/.colima/...` (READMEs) |
| 2 | GitHub namespace error | `dmf-cms/Dockerfile` → `github.com/<operator>/dmf-cms` (also a correctness bug; should be `dmfdeploy`) |
| 3 | Registry namespace | `dmf-runbooks/roles/nmos-cpp/defaults/main.yml`, `dmf-media/catalog/nmos-cpp.yaml`, related READMEs use `registry.dmf.example.com/<operator>/...` |
| 4 | GitHub handle | `@<handle>` in every public repo's `.github/CODEOWNERS` (kept by decision; documented) |
| 5 | Commit metadata | Every public commit authored `<operator-name> <<operator>@<operator-workstation>>`; one `Claude <claude@anthropic.com>` slip in `dmf-runbooks` archive |
| 6 | macOS metadata | `.DS_Store` reportedly shipped once (handoff confirms); existing `.gitignore` baseline does not list it explicitly |

The current `bin/scrub-public-repos.sh` does **not** match any of (1)–(6).
The current `.gitleaks.toml` does not match any of (1)–(6).
The current `bin/sync-to-github.sh` does not exist yet (Release Model §1 — deferred).

## Decisions (locked 2026-05-11)

1. **Commit identity rewrite target:** `znerol2 <ID+znerol2@users.noreply.github.com>`
   where `ID` is the numeric GitHub user ID for `znerol2`. Operator action: fetch via
   `curl -s https://api.github.com/users/znerol2 | jq .id`.
2. **Skill files with operator paths:** parameterize with `<secure-store>/...`
   placeholders. Document the convention in umbrella `CLAUDE.md §Conventions`.
3. **CODEOWNERS handle:** keep `@<handle>`. It is already public on the GitHub org.

## Phases

### Phase 1 — Extend the defensive layer (tooling)

1.1 Add a fourth BLOCKING category `Operator identity` to `bin/scrub-public-repos.sh`:

```
\b<operator>\b             | operator username
/Users/<operator>                 | operator macOS home
/Volumes/<operator>               | operator secure-store mount
/home/<operator>                  | operator Linux home (catalog playbook leak)
Mac-mini\.local            | operator device hostname
\bznerol[0-9]*\b           | operator GitHub handle
\.DS_Store                 | macOS metadata in tracked tree
```

Allowlist (self-references): `bin/scrub-public-repos.sh`, `.gitleaks.toml`,
`.github/CODEOWNERS`, this plan doc, the publish-readiness handoff.

1.2 Mirror the patterns into `.gitleaks.toml` as `dmf-operator-path` and
`dmf-operator-handle` custom rules with the same allowlist paths. Pre-commit
will refuse any unintentional reintroduction.

1.3 Write `bin/check-public-commit-authors.sh`:
- Walks `git log main --pretty='%an <%ae>'` in each public repo.
- Refuses any author/email not on a one-line allowlist (initially:
  `znerol2 <ID+znerol2@users.noreply.github.com>`).
- Wire into the planned `bin/sync-to-github.sh` push pipeline.

1.4 Add a `git ls-files --others --ignored --exclude-standard` arm to the scrub
script as a soft warning — surfaces ignored-but-staged accidents.

### Phase 2 — Sweep tracked content

Mechanical rewrites, one PR per repo (or one commit on the orphan `main` since
each repo currently sits at exactly one commit):

| Target | Action |
|---|---|
| Sub-repo `CLAUDE.md`/`AGENTS.md`/`QWEN.md` (5 component repos) | `<umbrella-path>/` → `<umbrella-path>/`; rewrite boot-ritual snippet to use a documented env-var convention (`$DMFDEPLOY_UMBRELLA`) |
| `.claude/skills/dmf-cluster-access/SKILL.md`, `dmf-openbao-unseal/SKILL.md` | `<secure-store>/...` → `<secure-store>/...`; add convention banner |
| `dmf-cms/Dockerfile`, `dmf-cms/docs/DEVELOPMENT-AND-BUILD-RULES.md` | `github.com/<operator>/dmf-cms` → `github.com/dmfdeploy/dmf-cms` |
| `dmf-runbooks/roles/nmos-cpp/{defaults/main.yml,README.md}` | registry namespace `<operator>/nmos-cpp-*` → `dmf/nmos-cpp-*` |
| `dmf-media/catalog/nmos-cpp.yaml` | same registry-namespace rewrite |
| `dmf-media/playbooks/lifecycle-operate.yml` | `<umbrella-path>/dmf-media/catalog` → `{{ dmf_media_catalog_path }}` variable |
| `dmf-infra/AGENTS.md`, `dmf-infra/docs/SECURITY-REMEDIATION-GUIDE.md` | `<home>/...`, `<volumes>/...` → placeholders |
| Umbrella `README.md` | `<note-store>/...` history reference → generic phrasing |
| Every public repo `.gitignore` | add `.DS_Store` line explicitly |

### Phase 3 — Rewrite git identity on the orphan commits

Once Phase 2 lands cleanly and the new gates pass:

```bash
GH_ID=$(curl -s https://api.github.com/users/znerol2 | jq -r .id)
for repo in . dmf-cms dmf-runbooks dmf-central dmf-infra dmf-media; do
  git -C "$repo" checkout main
  git -C "$repo" \
    -c user.name='znerol2' \
    -c user.email="${GH_ID}+znerol2@users.noreply.github.com" \
    commit --amend --reset-author --no-edit
  git -C "$repo" tag -f v0.1.0
done
```

Verify with `bin/check-public-commit-authors.sh`. Do **not** force-move
`archive/pre-publish-2026-05-07` — its parent commit predates the orphan rebase
and stays LAN-only by Gate 1.

### Phase 4 — Install sub-repo pre-commit hooks

Handoff Phase D §4 deferred this. Extend `bin/install-hooks.sh` (or add a
sibling `bin/install-sub-repo-hooks.sh`) so each public sub-repo gets the same
`gitleaks protect --staged` pre-commit hook. Per-clone, like umbrella.

### Phase 5 — Re-run all gates

Per `docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07.md` §Gates,
extended with new checks:

```
bin/scrub-public-repos.sh                  # OK — clean for public publish
bin/check-public-commit-authors.sh         # clean
for r in . dmf-cms dmf-runbooks dmf-central dmf-infra dmf-media; do
  git -C "$r" log --oneline                # exactly 1 commit
  ( cd "$r" && gitleaks detect --log-opts=main --no-banner )
  ( cd "$r" && gitleaks detect --no-git --no-banner )
done
```

Confirm Gate 1 (Forgejo push-mirror refspec excludes `archive/*`) still holds.

### Phase 6 — Continuous protection (deferred items now reachable)

- GitHub Actions workflow per public repo: `gitleaks` + `scrub` +
  `check-public-commit-authors` on PR and on `main` after push.
- Forgejo pre-receive hook: same three checks, server-side, can't be
  `--no-verify`'d.

## Verification

A successful sweep means:
1. `bin/scrub-public-repos.sh` exits 0 with the new BLOCKING category active.
2. `git log main --pretty='%an <%ae>'` per public repo returns only the
   approved public identity.
3. `gitleaks detect --log-opts=main` and `gitleaks detect --no-git` both
   return `no leaks found` per repo.
4. A planted reintroduction of `<operator>` or `<volumes>/` in any file is refused
   by the pre-commit hook.

## Risks & non-obvious traps

- `\b<operator>\b` is a broad regex and will false-positive on unrelated technical
  terms (none seen in the current survey, but possible in future content).
  Mitigation: word-boundary anchoring + allowlist of legitimate self-references.
- Re-amending the v0.1.0 orphan commit changes its hash. Any external reference
  to that hash (none expected pre-public-push) is invalidated. The `v0.1.0` tag
  is force-moved; that is fine because no one has fetched it yet.
- Phase 4 sub-repo pre-commit hooks are per-clone, not enforced by repo policy.
  Forgejo pre-receive (Phase 6) is the only server-side hard gate.

---

## Execution log

- 2026-05-11 — plan drafted, decisions locked, Phase 1 started.
