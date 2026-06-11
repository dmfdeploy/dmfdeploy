# DMF dmf-runbooks Public Publish (Path A) Handoff

**Date:** 2026-05-21
**Author:** session that ran g2r6-foa9 bootstrap to verify-vertical-resilience and hit the AWX catalog JT 400-error caused by the cluster Forgejo's `dmf-runbooks` repo containing only a README
**For:** the next session/agent that will conduct the first public-publish of `dmf-runbooks` and set up the canonical mirror architecture

> 🛑 **READ FIRST:**
> [`docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07.md`](DMF%20Public%20Publish%20Readiness%20Handoff%202026-05-07.md)
> — the orphan-rebase + push-mirror refspec procedure is non-negotiable.
> This handoff extends that one for the specific case of dmf-runbooks
> being the first repo to actually land on GitHub.

---

## TL;DR

`dmf-runbooks` is the first DMF Platform git repo to be public-published.
Three deliverables:

1. **Fix two `dmf-operator-identity` leaks** on the `main` branch of
   `dmf-runbooks` (operator-stem leaked into role README post-orphan-rebase,
   then the gitleaks rule was tightened, which retroactively flagged the
   prior content).
2. **Push `dmf-runbooks` to `github.com/dmfdeploy/dmf-runbooks`** under the
   pre-existing `dmfdeploy` GitHub org (same org that owns the GHCR images
   already published — `ghcr.io/dmfdeploy/awx-ee:0.1.0`, etc).
3. **Establish lab Forgejo → GitHub push-mirror as the canonical sync
   pattern** (operator pushes to lab Forgejo; Forgejo pushes to GitHub
   automatically). This replaces the "operator manually pushes per repo"
   model and is the pattern the other 5 public DMF repos will adopt next.

This work blocks the g2r6-foa9 bootstrap completion (and every future
fresh-env bootstrap): the in-cluster Forgejo needs a public canonical source
to mirror `dmf-runbooks` from, so AWX project sync finds the catalog
launcher playbooks (`launch-nmos-cpp.yml`, `teardown-nmos-cpp.yml`) and
`bootstrap-configure.yml` clears its AWX-catalog-JT create step.

---

## Why now / decision context

### The triggering failure

`bootstrap-configure.yml` failed at
`stack/operator/awx-integration : Create AWX job templates for catalog
entries (fail loud on missing playbook)` with HTTP 400 from the AWX API.
After surfacing the per-iteration response (commit `a9288ed` in dmf-infra
made the failure observable instead of `no_log` blackout), the cause was
clear: the cluster Forgejo's `dmf-runbooks.git` contained only a README
and no `playbooks/` directory. AWX project sync pulled an empty project →
no playbook files to reference → 400 on JT create.

Inspection of the cluster Forgejo:

```
$ kubectl exec -n forgejo <pod> -- sh -c \
    'cd /data/git/gitea-repositories/forgejo-svc/dmf-runbooks.git && \
     git ls-tree -r HEAD --name-only'
README.md
```

The role's existing `seed-local-repos.yml` mechanism (which can push from
the operator's local checkout via Forgejo API) has a bug: the
`forgejo_seed_repos['dmf-runbooks']` default in
`roles/stack/operator/forgejo-bootstrap/defaults/main.yml` declares `repo`
and `source_path` but **omits `required_files`** — the existence-probe
loop runs zero iterations → `_seed_needed: false` → all push tasks skip.

### Why Path A over Path C / Path B

Three remediation paths were on the table:

- **Path C** — fix the `forgejo_seed_repos['dmf-runbooks']` default by
  adding `required_files`. The role then pushes content from operator's
  local checkout on each bootstrap. **Cheapest** (~5 minutes). Keeps the
  operator-workstation-has-the-checkout dependency.
- **Path B** — configure cluster Forgejo as a pull-mirror of the
  operator's existing lab Forgejo (`forgejo.<operator-stem>.<operator-tld>`).
  Creates a load-bearing dependency on the operator's personal lab
  Forgejo being reachable from new clusters; not portable.
- **Path A (THIS HANDOFF)** — push canonical to `github.com/dmfdeploy`,
  configure lab Forgejo → GitHub auto-mirror, configure cluster Forgejo
  to pull from GitHub. **Aligns with the GHCR image publish model
  (ADR-0025)**: canonical source on public GitHub, runtime mirror in
  cluster. Same architectural pattern across images and source code.

Path A is the right long-term move because:
- Eliminates the operator-workstation-dependency for fresh-env bootstrap
  (cluster pulls from GitHub directly, not from operator's machine).
- Single canonical-source-on-GitHub pattern across all the platform's
  artifacts (image registry + source repos).
- Operator workflow stays single-target: push to lab Forgejo; Forgejo's
  push-mirror handles GitHub.
- Reusable for the 5 other DMF public repos.

Path C remains a useful fallback for flypack-offline scenarios (no
GitHub reach). Keep the seed mechanism in place; it just becomes the
secondary path.

---

## Architecture: lab Forgejo as canonical, push-mirror to GitHub

```
                ┌─────────────────────────────────────┐
                │ Operator workstation                │
                │   git push origin main              │
                └──────────────────┬──────────────────┘
                                   │
                                   ▼
              ┌──────────────────────────────────────┐
              │ Lab Forgejo (operator's, private)    │
              │ <lab-forgejo-host>/forgejo-svc/      │
              │ Push-mirror (Forgejo Settings →      │
              │   Mirror Settings → Push Mirror)     │
              │ Refspec: see Gate 1 below            │
              └──────────────────┬───────────────────┘
                                 │
                                 ▼
              ┌──────────────────────────────────────┐
              │ github.com/dmfdeploy/<repo>          │
              │ Public canonical source              │
              └──────────────────┬───────────────────┘
                                 │
                                 ▼
              ┌──────────────────────────────────────┐
              │ Per-cluster in-cluster Forgejo       │
              │ Pull-mirror via forgejo_mirror_repos │
              │ (role default). 1h sync interval.    │
              └──────────────────┬───────────────────┘
                                 │
                                 ▼
              ┌──────────────────────────────────────┐
              │ AWX project sync (per-env)           │
              │ Source = cluster Forgejo             │
              │ Catalog JTs reference playbooks      │
              └──────────────────────────────────────┘
```

The "push-mirror" half (lab Forgejo → GitHub) is configured **once per
repo, once per lifetime**. The "pull-mirror" half (GitHub → cluster
Forgejo) is configured per-cluster via the `forgejo_mirror_repos`
inventory variable consumed by `roles/stack/operator/forgejo-bootstrap`
(the role already has the mechanism — `tasks/main.yml:272-286` —
currently with an empty default `forgejo_mirror_repos: {}`).

---

## State of `dmf-runbooks` today

### Local repo

```
Path: $DMFDEPLOY_UMBRELLA/dmf-runbooks
Branch: main
HEAD: d928bfe fix(nmos): publish warning reads y/N from /dev/tty; NMOS_FORCE_PUBLISH bypass
Tags (LAN only): v0.1.0, archive/pre-publish-2026-05-07
```

Commits since the `v0.1.0` orphan-rebase (2026-05-07):

```
d928bfe fix(nmos): publish warning reads y/N from /dev/tty; NMOS_FORCE_PUBLISH bypass
1cdc58e refactor(nmos): collapse publish-to-ghcr.sh into thin wrapper
8a1ebdc chore(gitleaks): extend dmf-operator-identity to include <stem> + <tld>
ada0c75 feat(nmos): harden Dockerfiles + add GHCR publish script per public registry plan
36605c9 docs(adr-0025): catalog Helm + EE-runtime pivot — repo-level cross-refs
3852524 chore(release): rel-p0-dmf-runbooks — LICENSE/NOTICE/VERSION/CONTRIBUTING.md baseline
3e9f4f9 Initial public release v0.1.0
```

### Existing remotes

```
local   http://<lan-user>:<lan-pat>@<lan-ip>/<lan-user>/dmf-runbooks.git
origin  https://<lab-forgejo-host>/forgejo-svc/dmf-runbooks.git
```

`local` is the operator's LAN Forgejo, used for offline iteration.
`origin` is the lab Forgejo on Hetzner — **this is the canonical
operator workflow target** and the one that will get the push-mirror.

### Pre-publish defensive layer (in tree, working)

- `.gitleaks.toml` in umbrella root extends defaults + adds custom rules
  including `dmf-operator-identity` (the rule that's catching today's
  leaks).
- `.githooks/pre-commit` in umbrella runs `gitleaks protect --staged`.
  Not installed in `dmf-runbooks` clone; activate per fresh clone via
  `bin/install-hooks.sh` from the umbrella.
- `bin/scrub-public-repos.sh` in umbrella — three-category scanner.
- `.gitignore` baseline in `dmf-runbooks` root: kubeconfigs, `*.tfstate*`,
  `.terraform/`, `*.pem`, `*.key`, `openbao-keys*`, `.vault_pass`,
  `.env*`, `.netrc`, `secret_id*`.
- `.github/CODEOWNERS` present.

### Variabilization

- Mostly done in `3852524` (LICENSE/NOTICE/VERSION/CONTRIBUTING baseline).
- **Two regressions on `main`** introduced after the orphan-rebase
  (see §"Phase 1 — fix the two main-scope leaks" below).

### What's required by the readiness handoff but NOT yet done for dmf-runbooks

| Item | Status |
|---|---|
| `gitleaks detect --log-opts=main` clean | ❌ 2 leaks (this handoff) |
| `gitleaks detect --no-git` (working tree) clean | needs re-check after fix |
| `bin/scrub-public-repos.sh` OK | needs re-run after fix |
| LICENSE + NOTICE files | ✅ landed in `3852524` |
| `github.com/dmfdeploy/dmf-runbooks` exists | ❌ not yet (404 on probe) |
| Forgejo push-mirror configured with safe refspec | ❌ not yet |
| GitHub branch protection | ❌ not yet (post-push) |

---

## Required reads (in order)

1. **`docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07.md`**
   — full readiness procedure (Phases A-E + Gates 1-4). This handoff
   extends that one; do not skip it.
2. **`docs/architecture/DMF Release and Contribution Model.md`** — canonical
   spec for how the public repos relate to internal.
3. **`docs/decisions/0007-secrets-never-in-argv.md`** — affects how you
   handle the GitHub PAT during push-mirror setup.
4. **`docs/decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md`**
   — same architectural pattern (canonical-on-public, mirror-in-cluster).
   This handoff is the source-repo equivalent of the image story landed
   there.
5. **`.gitleaks.toml`** in umbrella root — the rule set that's catching
   the leaks.
6. **`bin/scrub-public-repos.sh`** in umbrella — read the body, you'll
   run it as Gate 4.
7. **`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/main.yml`**
   lines 261-307 (`seed-local-repos` + `forgejo_mirror_repos` mechanisms).
   Defaults are at the role's `defaults/main.yml`.

---

## Procedure

### Phase 1 — fix the two `main`-scope leaks

#### Where they are

```
$ cd $DMFDEPLOY_UMBRELLA/dmf-runbooks
$ gitleaks detect --log-opts="main" --no-banner -v
# Two findings, both:
#   RuleID:  dmf-operator-identity
#   File:    roles/nmos-cpp/README.md
#   Line:    146
#   Commit:  ada0c75 feat(nmos): harden Dockerfiles + add GHCR publish script
```

Inspect the line at HEAD:

```
$ grep -n 'min<lan-user>\|\.lab\.' roles/nmos-cpp/README.md
146:flag) and pushes to `registry.<operator-stem>.<operator-tld>` (env-specific Zot ingress).
```

The literal `registry.<operator-stem>.<operator-tld>` is the operator's lab
cluster's Zot ingress hostname — exactly the kind of operator-specific DNS
the variabilization sweep was supposed to scrub.

#### Fix

Per the umbrella `CLAUDE.md` convention (`§Conventions`), public repos
use the fictitious `dmf.example.com` for prose references. Replace:

```
registry.<operator-stem>.<operator-tld>  →  registry.dmf.example.com
```

Two reasonable strategies:

##### Strategy 1 — forward-fix on HEAD + re-orphan if needed

```bash
cd $DMFDEPLOY_UMBRELLA/dmf-runbooks
sed -i.bak 's|registry\.<operator-stem>\.<operator-tld>|registry.dmf.example.com|g' \
  roles/nmos-cpp/README.md
rm roles/nmos-cpp/README.md.bak
git diff roles/nmos-cpp/README.md
git add roles/nmos-cpp/README.md
git commit -m "$(cat <<'EOF'
chore(scrub): replace operator-stem with example domain in nmos-cpp README

Operator-stem leaked into roles/nmos-cpp/README.md:146 in commit ada0c75
(landed before the gitleaks dmf-operator-identity rule was tightened to
catch operator-stem + TLD in 8a1ebdc). Retroactively flagged by `gitleaks
detect --log-opts=main`.

Replaces with the umbrella's `dmf.example.com` placeholder per the
public-publish variabilization convention (CLAUDE.md §Conventions).

Closes the Gate 3 blocker from
docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07.md.
EOF
)"
```

Re-verify:

```bash
gitleaks detect --log-opts="main" --no-banner -v
# expect: no leaks found
```

**Important:** the leak is still in commit `ada0c75` and reachable from
`main`. The above adds a fixup commit; if Gate 3 requires NO leaks
ANYWHERE in `main`'s reachable history, this is not sufficient.

Per the readiness handoff Gate 3, the requirement is `--log-opts=main`
returns `no leaks found`. The exact semantics of `--log-opts=main`:
gitleaks walks the commit history reachable from `main` and scans each
commit's blobs. The bad string in `ada0c75:roles/nmos-cpp/README.md`
**will still be reported** even after a fixup commit, because
`ada0c75` is reachable from `main`.

So Strategy 1 may not pass Gate 3. Verify by re-running gitleaks; if it
still fails, fall back to Strategy 2.

##### Strategy 2 — orphan-rebase forward to a new `v0.1.1`

```bash
cd $DMFDEPLOY_UMBRELLA/dmf-runbooks
# Save current state for reference
git tag pre-republish-2026-05-21 main

# Re-orphan main with current content (less the leak):
sed -i.bak 's|registry\.<operator-stem>\.<operator-tld>|registry.dmf.example.com|g' \
  roles/nmos-cpp/README.md
rm roles/nmos-cpp/README.md.bak

# Create a fresh orphan commit
git checkout --orphan rebuilt-main
git add -A
git commit -m "v0.1.1 — first public release with operator-identity scrub"
git branch -M rebuilt-main main
git tag v0.1.1

# Verify
gitleaks detect --log-opts="main" --no-banner
# expect: no leaks found
```

Strategy 2 collapses ALL history since `v0.1.0` into a single orphan
commit, mirroring the original 2026-05-07 procedure. Cleaner for first
public publish; loses commit granularity (mitigated by the
`pre-republish-2026-05-21` tag staying on LAN).

**Default to Strategy 2** unless the granularity loss matters. Operator
preference: confirm before executing.

#### Re-run all four gates

```bash
# Gate 3 — gitleaks on main scope
gitleaks detect --log-opts="main" --no-banner    # expect: no leaks found

# Gate 4 — scrub
cd $DMFDEPLOY_UMBRELLA
bin/scrub-public-repos.sh                          # expect: "OK — clean for public publish"

# Working tree scan (extra confidence)
cd dmf-runbooks
gitleaks detect --no-git --no-banner               # expect: no leaks found
```

### Phase 2 — verify pre-publish content

Per the readiness handoff Phase B checklist for dmf-runbooks specifically:

- [ ] `git log --oneline | wc -l` — should be `1` if Strategy 2, or
      `1 + N fixup commits` if Strategy 1.
- [ ] Spot-check 5 random files for `<operator-stem>`, `<operator-tld>`,
      real IPs, `lab.min<lan-user>`, `192.168.*`, `100.64.*`. Should be none.
- [ ] Confirm `LICENSE` (Apache 2.0 verbatim) + `NOTICE` (upstream-derived
      components — specifically `sony/nmos-cpp` for the Dockerfile bases)
      are present.
- [ ] Confirm `.gitignore` covers the secrets-prevention baseline.
- [ ] Confirm `.github/CODEOWNERS` reflects current intent.
- [ ] Read `README.md` as a first-time public viewer. Polish if it's too
      operator-internal-flavoured.

### Phase 3 — GitHub org + repo setup

#### Org

`github.com/dmfdeploy` already exists (verified — owns the public GHCR
images `awx-ee`, `dmf-cms`, `nmos-cpp-*`). Confirm:

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://github.com/dmfdeploy
# expect: 200
```

#### Repo

Create `github.com/dmfdeploy/dmf-runbooks` as **private** first. Flip to
public AFTER successful first push + visual review.

Operator owns the GitHub PAT (in macOS keychain under service `ghcr.io`,
account `<github-user>`). The PAT must have the **`repo`** scope — both
for `gh repo create` and for the push-mirror auth from Forgejo.

Option A — via `gh` CLI (preferred if installed):
```bash
brew install gh                # if missing
echo "$PAT" | gh auth login --with-token
gh repo create dmfdeploy/dmf-runbooks --private \
  --description "Thin AWX launcher playbooks for DMF catalog entries (catalog model — ADR-0014)" \
  --homepage "https://github.com/dmfdeploy"
```

Option B — via GitHub web UI: standard new-repo flow. Don't initialize
with README / .gitignore / license (we have our own).

### Phase 4 — first push from local

Per the readiness handoff §"Concrete first-push sequence", push only
`main` + the new tag (`v0.1.0` if Strategy 1, `v0.1.1` if Strategy 2).
**NEVER `git push --tags`** — it would push `archive/pre-publish-*`
which is the pre-rebase history.

```bash
cd $DMFDEPLOY_UMBRELLA/dmf-runbooks
git remote add github git@github.com:dmfdeploy/dmf-runbooks.git
git push github main
git push github v0.1.1   # or v0.1.0 if Strategy 1

# Verify on GitHub via the web UI:
#   - One (Strategy 2) or `1 + fixups` (Strategy 1) commits on main
#   - v0.1.1 (or v0.1.0) tag visible
#   - NO archive/pre-publish-2026-05-07 tag
#   - LICENSE rendered on the right sidebar
#   - README renders as expected for a first-time viewer
```

If the visual verify passes, **flip GitHub repo to public** (Settings →
General → Danger Zone → Change visibility → Public).

### Phase 5 — configure lab Forgejo push-mirror

This is the architectural change the operator confirmed: lab Forgejo
becomes the canonical operator-workflow target; Forgejo's push-mirror
keeps GitHub in sync automatically.

In the lab Forgejo's web UI:

1. Navigate to the `forgejo-svc/dmf-runbooks` repository.
2. Settings → Mirror Settings → Push Mirror.
3. Click **Add Push Mirror**.
4. Configure:
   - **Git Remote Repository URL:**
     `https://github.com/dmfdeploy/dmf-runbooks.git`
   - **Authorization:** check "Use authentication"
   - **Username:** the GitHub username that owns the PAT (`<github-user>`)
   - **Password:** the GitHub PAT (the same one in macOS keychain under
     service `ghcr.io`)
   - **Sync interval:** 8 hours (or whatever cadence — push triggers
     a sync anyway; this is just the fallback poll interval)
5. **Refspec** — this is **Gate 1** from the readiness handoff. Forgejo's
   default refspec propagates ALL refs, which would leak the
   `archive/pre-publish-2026-05-07` tag's dirty history. After saving the
   mirror config, edit it once more and set the explicit refspec:

   ```
   +refs/heads/main:refs/heads/main
   +refs/tags/v*:refs/tags/v*
   ```

   If the Forgejo UI doesn't expose Refspec editing, fall back to the
   API:

   ```bash
   # From the operator workstation, with lab Forgejo creds:
   curl -s -X PATCH \
     -u "$FORGEJO_USER:$FORGEJO_PASSWORD" \
     -H "Content-Type: application/json" \
     -d '{"sync_on_commit": true, "interval": "8h", "remote_url": "...", "remote_username": "...", "remote_password": "..."}' \
     https://<lab-forgejo-host>/api/v1/repos/forgejo-svc/dmf-runbooks/push_mirrors/<id>
   ```

   (Consult Forgejo API docs for the exact endpoint at the lab Forgejo's
   version.)

6. **Trigger an initial sync**: from the Push Mirror panel, click "Sync
   Now". Verify on GitHub that no `archive/*` tag has appeared. (If it
   has, the refspec is wrong; remove the tag on GitHub immediately AND
   refix the refspec.)

### Phase 6 — enable branch protection on GitHub

After the first push + visibility flip:

- Settings → Branches → Add rule (or Add ruleset)
  - Pattern: `main`
  - Require linear history: yes
  - Require status checks: deferred until CI is in place
  - Restrict force-pushes: yes
  - Restrict deletions: yes
- Settings → Tags → Tag protection (optional but recommended for
  `v*` tags).

### Phase 7 — close the AWX-catalog-JT loop on g2r6-foa9

This is the bootstrap-unblock half. With dmf-runbooks public on GitHub:

#### Update the role default

Edit
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/defaults/main.yml`:

```yaml
forgejo_mirror_repos:
  dmf-runbooks: https://github.com/dmfdeploy/dmf-runbooks.git
```

Commit + push dmf-infra. The default applies to all future envs; for
g2r6-foa9 it'll be picked up when `692-forgejo-bootstrap.yml` next runs
during `bootstrap-configure.yml`.

#### Manually configure the existing cluster Forgejo for g2r6-foa9

The g2r6-foa9 cluster's Forgejo already has an empty `dmf-runbooks` repo.
Rather than wait for the next bootstrap-configure run, configure the
mirror via API directly:

```bash
ssh -i ~/.ssh/id_ed25519_k3s_hetzner k3s-admin@<g2r6-foa9-control-ip> \
  "sudo k3s kubectl -n forgejo exec deploy/forgejo -c forgejo -- \
    curl -s -X POST -u \"\$FORGEJO_USER:\$FORGEJO_PASS\" \
      -H 'Content-Type: application/json' \
      -d '{\"mirror\": true, \"mirror_interval\": \"1h\", \"mirror_remote_address\": \"https://github.com/dmfdeploy/dmf-runbooks.git\"}' \
      http://localhost:3000/api/v1/repos/forgejo-svc/dmf-runbooks"

# Set FORGEJO_USER and FORGEJO_PASS in env first (e.g. via
# bin/get-admin-cred.sh forgejo). Avoids putting credentials in argv per
# ADR-0007.
```

Or use the existing `bin/get-admin-cred.sh forgejo` to fetch creds and
run via the Forgejo Web UI through the private ingress.

Trigger an immediate sync, verify the playbooks are present, then re-run
`bootstrap-configure.yml` on g2r6-foa9. The catalog JT create should
succeed now.

---

## Expansion plan — the other 5 public repos

Per the readiness handoff §Phase E checklist, the remaining DMF public
repos use the same pattern:

| Repo (Forgejo side) | GitHub target | Notes |
|---|---|---|
| `dmf-platform` (umbrella; lab Forgejo path: `<lan-user>/dmf-platform`) | `github.com/dmfdeploy/dmf-platform` | The umbrella. Contains docs + ADRs. |
| `dmf-cms` | `github.com/dmfdeploy/dmf-cms` | Operator console; matching image already on GHCR. |
| `dmf-central` | `github.com/dmfdeploy/dmf-central` | Scaffold today (Phase 0 step 5). |
| `dmf-infra` | `github.com/dmfdeploy/dmf-infra` | Generic playbooks/roles. |
| `dmf-media` | `github.com/dmfdeploy/dmf-media` | Media catalog metadata + (future) Layer 5 roles. |

`dmf-env` **never goes public** (per the readiness handoff Gate 2).

For each repo, the same procedure applies:

1. Run `gitleaks detect --log-opts=main --no-banner` and fix any leaks.
   The `dmf-operator-identity` rule was tightened in `2026-05-19`; expect
   each public repo to have a small number of post-orphan-rebase leaks.
2. Repeat Phases 3-6 from this handoff.
3. Add an entry to `forgejo_mirror_repos` in dmf-infra's role default
   for each repo that the in-cluster Forgejo needs to mirror (today
   that's only `dmf-runbooks`; future repos may add themselves if
   in-cluster consumers need them).

The push-mirror setup itself is identical per repo. Authentication can
reuse the same GitHub PAT (scope `repo`, all-repos-in-org access).

---

## Gates (echoed from the readiness handoff, applied per-repo)

| Gate | What | Why |
|---|---|---|
| Gate 1 | Forgejo push-mirror refspec must be `+refs/heads/main:refs/heads/main` and `+refs/tags/v*:refs/tags/v*` | Default refspec propagates `archive/*` tags, which contain the pre-orphan-rebase secret-bearing history |
| Gate 2 | `dmf-env` never goes public | Inventory, real IPs, OpenBao role_id, hcloud token refs — all in this repo |
| Gate 3 | `gitleaks detect --log-opts=main` returns "no leaks found" | Pre-publish substantive check |
| Gate 4 | `bin/scrub-public-repos.sh` returns "OK — clean for public publish" | Three-category umbrella-side scanner |

Add a fifth for this round:

| Gate 5 | After the first sync from Forgejo → GitHub, confirm no `archive/*` tag has appeared on the GitHub side | If it has, the refspec is wrong; remove the tag on GitHub AND refix the refspec immediately |

---

## What this unblocks downstream

Once dmf-runbooks is publicly mirrored AND the cluster Forgejo's
mirror-from-GitHub is in place, **`bootstrap-configure.yml` clears its
AWX catalog JT create step** for every fresh env. The catalog launcher
playbooks (`launch-nmos-cpp.yml`, `teardown-nmos-cpp.yml`) become
available to AWX automatically.

Same architectural shape as the Zot Stage 4b mirror landed in
2026-05-21 commit `093fbc8`: workstation no longer carries the
canonical content; cluster pulls from GitHub (for source) and from
its own Zot which mirrors from GHCR (for images).

This is the architectural convergence the platform has been building
toward: **canonical artifacts (images + source) live on public GitHub;
clusters pull from cluster-local mirrors of those canonical sources**.
Path A for dmf-runbooks lands the source-repo half of that convergence.

---

## Out of scope / explicit deferrals

- **Other 5 public repos.** Same pattern, but each has its own
  gitleaks/scrub re-check. Expand after dmf-runbooks lands cleanly.
- **CI on PR for gitleaks/scrub.** Local pre-commit hook is enough for
  the first public push. CI is belt-and-braces per the readiness
  handoff §"What was deliberately deferred".
- **Conventional Commits / commitlint / automated CHANGELOG.** Same —
  deferred to post-first-push.
- **`forgejo_seed_repos` removal.** Keep the seed mechanism for
  flypack-offline operators who have no GitHub reach. It becomes the
  fallback; the mirror is the default.
- **Forgejo pre-receive server-side gitleaks.** Defense-in-depth; not
  blocking.

---

## Open questions to surface to the operator at start of session

1. Strategy 1 (forward-fix on HEAD) vs Strategy 2 (re-orphan to v0.1.1)?
   Recommendation: Strategy 2.
2. Are we ready to also expand to the remaining 5 repos in this same
   session, or land dmf-runbooks first and treat expansion as a
   separate follow-on?
3. Confirm GitHub PAT scope is `repo` (full) and that the PAT can
   create repos under the `dmfdeploy` org (the operator owns the org;
   `<github-user>` has admin rights).
4. Forgejo push-mirror sync interval — 8h default is fine for first
   push; consider tightening to 1h post-publish if commits happen
   frequently. Push-on-commit support depends on Forgejo version.

---

## References

- Readiness handoff (read first): [`docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07.md`](DMF%20Public%20Publish%20Readiness%20Handoff%202026-05-07.md)
- Release model: `docs/architecture/DMF Release and Contribution Model.md`
- ADR-0025 (Catalog Helm + EE-runtime, same pattern for images): `docs/decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md`
- Convergence handoff (the GHCR image publish work): [`docs/handoffs/DMF Convergence Run — Lane A + ADR-0025 + Public Registry Handoff 2026-05-19.md`](DMF%20Convergence%20Run%20%E2%80%94%20Lane%20A%20%2B%20ADR-0025%20%2B%20Public%20Registry%20Handoff%202026-05-19.md)
- Gitleaks config: umbrella's `.gitleaks.toml`
- Scrub script: umbrella's `bin/scrub-public-repos.sh`
- Failing role (consumer of this work): `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml:1085`
- Mirror-import mechanism (target): `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/main.yml:272-286`
- Seed-local-repos fallback mechanism: `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/seed-local-repos.yml`

---

**End of handoff.** Resume with Phase 1 (the two main-scope leaks).
Confirm Strategy 1 vs 2 with the operator before re-orphaning.
