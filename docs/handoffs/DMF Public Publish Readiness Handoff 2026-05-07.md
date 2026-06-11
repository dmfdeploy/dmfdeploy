# DMF Public Publish Readiness Handoff (2026-05-07)

> **🛑 READ THIS BEFORE ANY DMF PLATFORM REPO IS PUSHED TO A PUBLIC GITHUB MIRROR.**
>
> The platform was prepared for first public release on 2026-05-07. This handoff
> captures the work done, the open review items, and the operational gates that
> must hold before the first push. **Skipping this read risks leaking secrets
> or topology that the prep pass deliberately scrubbed.**

**Date:** 2026-05-07
**Author:** umbrella session that completed the orphan-rebase to `v0.1.0`
**For:** the next session that will conduct the in-depth pre-publish review

---

## TL;DR

All six public repos sit at a single orphan commit (`Initial public release v0.1.0`)
on `main`, tagged `v0.1.0`. Internal-development history is preserved on LAN Forgejo
under `archive/pre-publish-2026-05-07` and **must not be pushed to GitHub**.

The defensive layer (gitleaks, scrub script, `.gitignore` baseline, CODEOWNERS) is
fully in place. The variabilization sweep (`dmf.example.com` placeholders + IP
placeholders) is complete. Final scrub + gitleaks pass cleanly across all repos.

**Before pushing to GitHub the next session must:**

1. Re-run the gates from this doc to confirm nothing has drifted.
2. Walk through the review checklist below.
3. Stand up the GitHub `dmfdeploy` org.
4. Configure Forgejo push-mirrors with a refspec that **excludes archive tags**.
5. Push.

---

## State as of 2026-05-07

### Repo topology + tags

| Repo | LAN HEAD | Tags on LAN | Pushed to GitHub? |
|---|---|---|---|
| `dmfdeploy` (umbrella, Forgejo: `dmf-platform`) | `6ff979d` | `v0.1.0`, `archive/pre-publish-2026-05-07` | not yet |
| `dmf-cms` | `ad4be05` | `v0.1.0`, `archive/pre-publish-2026-05-07` | not yet |
| `dmf-runbooks` | `c530b52` | `v0.1.0`, `archive/pre-publish-2026-05-07` | not yet |
| `dmf-central` | `54fb17d` | `v0.1.0`, `archive/pre-publish-2026-05-07` | not yet |
| `dmf-infra` | `adc5e5d` | `v0.1.0`, `archive/pre-publish-2026-05-07` | not yet |
| `dmf-media` | `7c9d33d` | `v0.1.0`, `archive/pre-publish-2026-05-07` | not yet |

`dmf-env` is **private** — full history preserved, never to public. Tagged at its
own pace; the orphan-rebase did not touch it.

### Defensive layer (in place)

| Mechanism | Location | Status |
|---|---|---|
| `.gitleaks.toml` (umbrella) | `/.gitleaks.toml` | active — extends defaults, allowlists `docs/` for `generic-api-key`, adds custom `dmf-dev-changeme` rule |
| Pre-commit hook (umbrella) | `/.githooks/pre-commit` | runs `gitleaks protect --staged` and refuses on hit (tested with planted secret) |
| Scrub script (umbrella) | `/bin/scrub-public-repos.sh` | three-category scanner with allowlist for self-references and intentional smell-mentions |
| `.gitignore` baseline | every public repo's root | kubeconfigs, `*.tfstate*`, `.terraform/`, `*.pem`, `*.key`, `openbao-keys*`, `.vault_pass`, `.env*`, `.netrc`, `secret_id*` |
| `CODEOWNERS` | `<repo>/.github/CODEOWNERS` in each public repo | activates when GitHub branch protection requires reviews |

### Variabilization (done)

- All code/config files in public repos use `dmf.example.com` defaults and
  `<placeholder>` syntax for IPs (`<control-node-public-ip>`, `<node-public-ip>`,
  `<lb-public-ip>`, `<lan-ip>`, `<wg-mesh-ip>`, `<headscale-host>`).
- Real values live only in `dmf-env/inventories/<env>/group_vars/all/main.yml`
  (`cert_manager_cluster_domain`, `headscale_ssh_target`, etc.).
- Convention codified in the umbrella `CLAUDE.md` §Conventions.

### What was already cleaned up

- 2026-05-07 rename: `k3s-*` → `dmf-*` across every repo, code, doc, role default,
  AWX/Forgejo integration, hcloud labels, OpenBao Keychain service name.
- Master → main branch standardization across all 7 repos.
- Headscale node-table cleanup (43 stale `k3s-node-*` entries swept).
- `forgejo_mirror_repos: {}` (the `<handle>/k3s-*` upstream entries were removed
  per the publish-prep decision).

---

## ⚠️ Critical pre-push gates

### Gate 1 — Forgejo push-mirror refspec MUST exclude `archive/*`

Forgejo's push-mirror by default propagates all refs. Per repo, configure the
refspec at Settings → Mirror Settings → Push Mirror → Edit → Refspec:

```
+refs/heads/main:refs/heads/main
+refs/tags/v*:refs/tags/v*
```

If `archive/*` slips through, the entire pre-publish git history — including the
`Admin123` cred that lives in `dmf-infra`'s old `awx.md` (commit
`c0f03f8` and friends) — lands on GitHub. The orphan rebase **isolated** the
history; the push-mirror config is what **keeps it isolated on the wire**.

### Gate 2 — `dmf-env` never goes public under any circumstance

Inventory, Terraform manifest with concrete IPs, `openbao_secrets.yml` with real
role_id, hcloud token references — all here. Stays on LAN Forgejo only.

### Gate 3 — Gitleaks must be clean on `main` scope before any push

For each public repo, run from inside the repo:

```
gitleaks detect --log-opts="main" --no-banner
```

Must say `no leaks found`. (Full-repo scan still flags 2 finds in
`dmf-infra`'s `archive/*` reachable history — that is expected and stays
LAN-only.)

### Gate 4 — Scrub script must pass

From the umbrella:

```
bin/scrub-public-repos.sh
```

Must end with `OK — clean for public publish`.

---

## Review checklist (next session, in order)

### Phase A — read

- [ ] Read this handoff in full.
- [ ] Read `docs/architecture/DMF Release and Contribution Model.md`.
- [ ] Skim `docs/decisions/INDEX.md` (especially ADR-0007 secrets-in-argv,
      ADR-0008 OpenBao architecture, ADR-0009 Shamir DR).
- [ ] Read each public repo's `CODEOWNERS` and root `.gitignore`.

### Phase B — per-repo deep review

For each of the 6 public repos:

- [ ] `git log --oneline` — should be exactly 1 commit on `main`.
- [ ] `gitleaks detect --log-opts="main"` → `no leaks found`.
- [ ] `gitleaks detect --no-git`           → `no leaks found`.
- [ ] Spot-check 5 random files for any `<lan-host>`, real IPs, or other
      operator-specific content. (Should be none.)
- [ ] Helm/catalog/role-default review (especially `dmf-cms/charts`,
      `dmf-media/catalog/`, `dmf-runbooks/roles/nmos-cpp/defaults/`,
      `dmf-infra/k3s-lab-bootstrap/roles/.../defaults`) — confirm placeholder
      defaults make semantic sense to a third-party reader.
- [ ] README polish (operator-focused at present; OK for v0.1.0 but worth a
      pass for first-time public viewer).

### Phase C — umbrella scope

- [ ] `bin/scrub-public-repos.sh` → "OK — clean for public publish".
- [ ] `STATUS.md` reflects 1-commit / `v0.1.0` state for each component.
- [ ] No untracked operator drafts that should not go public; if there are,
      they need to be either committed or removed before push.

### Phase D — architectural review

- [ ] **License + NOTICE files.** Apache 2.0 verbatim at root of each public
      repo. NOTICE listing upstream-derived components (e.g. `sony/nmos-cpp`).
      *This step was deliberately deferred — must be done before public push.*
- [ ] **k3s-lab-bootstrap subdirectory** inside `dmf-infra` still has "k3s" and
      "lab" in its name. Not security-critical; consider whether to rename to
      something like `bootstrap/` for consistency with the repo-rename spirit.
- [ ] **forgejo-bootstrap mirror config** is `{}` — confirm option-(b) is the
      strategy (push from operator workstation during born-inventory phase),
      and that this gets implemented at fresh-rollout time.
- [ ] **`bootstrap-operator-approle.sh` not yet exercised** in a fresh
      rollout. Confirm it works end-to-end before public publish (the
      script is committed to `dmf-env/bin/`).
- [ ] **Sub-repo gitleaks pre-commit** is not installed. Umbrella has the
      hook; sub-repos don't. Worth wiring before public.

### Phase E — GitHub-side prep

- [ ] Stand up `dmfdeploy` org on GitHub (<handle> owner).
- [ ] Create 6 empty repos: `dmf-platform`, `dmf-cms`, `dmf-runbooks`,
      `dmf-central`, `dmf-infra`, `dmf-media`. **Start private**; flip to
      public only after successful first push + visual review.
- [ ] Generate a GitHub PAT scoped to the org (repo + workflow scopes only).
- [ ] Configure Forgejo push-mirror per repo with the safe refspec (see Gate 1).
- [ ] Branch protection rules per GitHub repo: require linear history,
      required status checks once CI is in place.

---

## Concrete first-push sequence (after greenlight)

```bash
# 1. on GitHub: create org dmfdeploy and 6 private repos
#    dmf-platform, dmf-cms, dmf-runbooks, dmf-central, dmf-infra, dmf-media

# 2. per repo, on the operator workstation:
cd ~/repos/dmfdeploy/<repo>            # or umbrella for dmf-platform
git remote add github git@github.com:dmfdeploy/<repo>.git
git push github main v0.1.0            # NOT --tags (--tags would push archive/*)

# 3. visually verify on GitHub: 1 commit, v0.1.0 tag, no archive tag

# 4. flip GitHub repo private → public

# 5. configure Forgejo push-mirror (Settings → Mirror Settings → Push Mirror)
#    Refspec:
#      +refs/heads/main:refs/heads/main
#      +refs/tags/v*:refs/tags/v*
#    Auth: GitHub PAT scoped to this org

# 6. set GitHub branch protection
```

---

## What was deliberately deferred

| Item | Why | Where it lives in the model doc |
|---|---|---|
| LICENSE + NOTICE files | Wanted to land defensive layer first; license is a 5-min copy-paste | §2 |
| Conventional Commits + commitlint | Procedural layer; better done after first push when there's signal | §4 |
| Automated CHANGELOG | Same | §4 |
| GitHub Actions CI (gitleaks/scrub on PR) | Local pre-commit covers the same; CI is belt-and-braces | §6 / §8 |
| Sub-repo gitleaks pre-commit | Logical extension; not blocking | §6 |
| Forgejo pre-receive hook (server-side gitleaks) | Defense-in-depth; not blocking for first push | §6 |
| README polish for public reader | Functional but operator-focused | (not in spec yet) |

---

## References

- Canonical spec: `docs/architecture/DMF Release and Contribution Model.md`
- Pre-publish scrub: `bin/scrub-public-repos.sh`
- Gitleaks config: `.gitleaks.toml`
- Pre-commit hook: `.githooks/pre-commit`
- Per-repo `CODEOWNERS`: `<repo>/.github/CODEOWNERS`
- Per-repo `.gitignore` baseline: `<repo>/.gitignore`
- Internal history (LAN-only): `archive/pre-publish-2026-05-07` tag in each public repo
- Operator AppRole bootstrap (post-fresh-rollout): `dmf-env/bin/bootstrap-operator-approle.sh`
- Headscale cleanup (post-teardown): `dmf-infra/k3s-lab-bootstrap/playbooks/322-headscale-cleanup.yml`

---

**End of handoff.** Resume with Phase A; do not skip Gate 1 (push-mirror refspec)
under any circumstance.
