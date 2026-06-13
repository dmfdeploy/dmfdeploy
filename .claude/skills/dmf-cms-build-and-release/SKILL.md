---
name: dmf-cms-build-and-release
description: Build and release the DMF Console (dmf-cms). Encodes the only sanctioned path — VERSION-driven, image published to GHCR via publish-to-ghcr.sh, mirrored into cluster Zot by playbook 630, deployed by playbook 650. Never by hand. Pairs with the canonical doc at dmf-cms/docs/DEVELOPMENT-AND-BUILD-RULES.md.
---

# DMF Console — Build and Release

**Authoritative source:** `dmfdeploy/dmf-cms/docs/DEVELOPMENT-AND-BUILD-RULES.md`.
That document is the contract; this skill is the runtime cheat sheet for an AI agent
working in the repo. If they disagree, **the doc wins** — this skill should be updated.

**Scope:** `dmf-cms/` only. The Ansible repos (`dmf-infra`, `dmf-env`, etc.)
don't produce versioned artifacts; their contribution rules live in their own
`CLAUDE.md` files.

---

## 🛑 §0 Secrets Discipline (read first)

The publish pipeline touches GHCR credentials, Zot credentials (read by playbook
630, not by you), and OpenBao. Hard rules:

1. **Never push directly to cluster-internal Zot from your workstation.**
   The 2026-05-19 ADR-0025 convergence retired that path. GHCR
   (`ghcr.io/dmfdeploy/dmf-cms:<VERSION>`) is the canonical public source;
   `playbook 630-zot-seed-platform.yml` mirrors GHCR → Zot using credentials
   it pulls from OpenBao. You publish to GHCR via `scripts/publish-to-ghcr.sh`
   (which delegates to `dmfdeploy/bin/publish-image-to-ghcr.sh` — the umbrella
   helper that handles secrets via stdin and an isolated, auto-cleaned
   `DOCKER_CONFIG`).

2. **Never put a registry password in argv** (`docker login -u user -p pass`,
   `curl -d '{"password":"..."}'`). It lands in shell history and `ps` output.
   `publish-to-ghcr.sh` accepts the GHCR token via stdin; use that path:

   ```bash
   # ✅ token from stdin, no argv exposure (macOS Keychain example)
   security find-generic-password -s "ghcr.io" -a "<github-username>" -w \
     | GHCR_USER="<github-username>" scripts/publish-to-ghcr.sh
   ```

3. **Never invoke `get-admin-cred.sh` (or any other secret-printing tool) through
   an AI agent.** The conversation transcript captures the value. If you need a
   secret, retrieve it in a separate terminal and pass an *opaque reference* to
   the agent (e.g. "creds are in OpenBao at `secret/apps/zot/admin`"), not the
   value itself.

4. **Treat any session that retrieved a secret as compromised for that secret's
   lifetime.** Rotate after, even if "nothing went wrong."

For broader `/tmp` hygiene (playbook log scrubbing, stale openbao-vars files),
see `dmf-cluster-access` §0.

---

## 1. The contract in one paragraph

`VERSION` at the repo root is the **single source of truth**. Five files are derived
from it (`pyproject.toml`, `frontend/package.json`, `charts/dmf-cms/Chart.yaml` ×2 fields,
`charts/dmf-cms/values.yaml` `image.tag`). The image carries the same tag at every
hop — `ghcr.io/dmfdeploy/dmf-cms:<VERSION>` (canonical public source) and
`registry.dmf.example.com/dmf-cms:<VERSION>` (cluster-internal Zot mirror). No
`latest`, no `v` prefix, no `-dirty`/`-rc` suffixes. Bumping `VERSION` is the
**only** way to force a pull (`imagePullPolicy: IfNotPresent`). The release path
is **build locally → publish to GHCR → playbook 630 mirrors GHCR → Zot →
playbook 650 Helm-deploys**. Workstations no longer push to Zot directly; that
path was removed in the 2026-05-19 ADR-0025 convergence.

---

## 2. Decision tree

```
        Is the change being released to the cluster?
                  │
       ┌──────────┴──────────┐
       no                    yes
       │                     │
   §3 local dev          Is the working tree clean?
                              │
                    ┌─────────┴─────────┐
                    no                  yes
                    │                   │
                §4 commit first    §5 release.sh   (build only — no push)
                                        │
                                §6 publish-to-ghcr.sh   (image → GHCR)
                                        │
                                §6 playbook 630   (GHCR → Zot mirror)
                                        │
                                §6 playbook 650   (Helm deploy)
                                        │
                                §7 verify-cluster.sh
```

---

## 3. Local development (no scripts needed)

```bash
# Terminal 1 — FastAPI backend
cd ~/repos/dmfdeploy/dmf-cms
DMF_CONSOLE_DEV_LOGIN_ENABLED=true uvicorn src.dmf_cms.main:app --reload

# Terminal 2 — Vite frontend (proxies /api and /auth to :8000)
cd ~/repos/dmfdeploy/dmf-cms/frontend
npm install     # first run only; on subsequent runs prefer npm ci for reproducibility
npm run dev
# → http://localhost:5173
```

Frontend rules during dev: `npm install` is fine when adding deps; commit both
`package.json` AND `package-lock.json`. **Never** `npm install` in the build path
or in CI — only `npm ci`. Stick to the design tokens in `index.css` and the
component classes (`.panel`, `.card`, `.badge-status-*`) — see `AGENTS.md` for
the full design-system contract.

---

## 4. Pre-release sanity (run on every PR)

```bash
cd ~/repos/dmfdeploy/dmf-cms

# 1. Versions in sync across the 5 files
scripts/sync-version.sh --check

# 2. Working tree clean (or know what you're keeping)
git status --short
```

If `--check` fails, the PR has broken the contract. Fix locally with:

```bash
scripts/sync-version.sh    # propagate current VERSION to all derived files
```

---

## 5. Cutting a release (the only sanctioned path)

```bash
cd ~/repos/dmfdeploy/dmf-cms

# Pick one — patch / minor / major / explicit version
scripts/release.sh patch        # 0.5.0 → 0.5.1
scripts/release.sh minor        # 0.5.0 → 0.6.0
scripts/release.sh major        # reserved until 1.0
scripts/release.sh 0.6.0        # explicit
```

`release.sh` will:
1. Refuse if the working tree is dirty
2. Refuse if `git tag v<NEW>` already exists
3. Sync VERSION to all 5 derived files
4. `git commit -m "release: v<NEW>"`
5. `git tag -a v<NEW> -m "Release v<NEW>"`
6. Run `build-image.sh --no-push` (builds the image locally and tags it as
   `registry.dmf.example.com/dmf-cms:<NEW>` — that prefix is the *expected
   source* for `publish-to-ghcr.sh`; the image does not get pushed to Zot from
   here)

After it finishes:

```bash
# Push commit + tag to Forgejo
git push origin HEAD
git push origin v<NEW>
```

Then publish + mirror + deploy via §6.

### Versioning policy (until release-1)

- **PATCH** — bug fix or refactor; no operator-visible behavior change.
- **MINOR** — additive feature; existing flows unchanged.
- **MAJOR** — breaking change to API/OIDC/env shape. Reserved until release-1.

---

## 6. Publish + mirror + deploy (GHCR → Zot → cluster)

The release path has three steps after `release.sh`. Each is idempotent.

> **`<env-name>` in the commands below** — substitute the current Hetzner test
> env id from the umbrella's generated `STATUS.local.md` (run `bin/generate-status.sh`; env ids rotate as we cut new test
> clusters; this skill stays env-agnostic).

### 6a. Publish the image to GHCR

```bash
cd ~/repos/dmfdeploy/dmf-cms

# Token via macOS Keychain (preferred — no argv exposure)
security find-generic-password -s "ghcr.io" -a "<github-username>" -w \
  | GHCR_USER="<github-username>" scripts/publish-to-ghcr.sh

# Or interactive (token typed at the umbrella helper's prompt)
scripts/publish-to-ghcr.sh
```

`scripts/publish-to-ghcr.sh` asserts that `IMAGE_TAG == VERSION`, then delegates
to `dmfdeploy/bin/publish-image-to-ghcr.sh` which:
1. Sets up an isolated `DOCKER_CONFIG` (not your `~/.docker`)
2. `docker login ghcr.io` with the token on stdin
3. Tags `registry.dmf.example.com/dmf-cms:<VERSION>` (the local tag
   `build-image.sh` produced) as `ghcr.io/dmfdeploy/dmf-cms:<VERSION>` and pushes
4. Cleans the isolated docker config on exit via a `trap`

### 6b. Mirror GHCR → cluster-internal Zot (playbook 630)

```bash
cd ~/repos/dmfdeploy/dmf-env
bin/run-playbook.sh <env-name> \
  ../dmf-infra/k3s-lab-bootstrap/playbooks/630-zot-seed-platform.yml
```

What playbook 630 does (per ADR-0025 Stage 4b):
1. Reads `cms_image_tag` at runtime from `dmf-cms/VERSION` (via the role default's
   `lookup('file', ...)`)
2. Reads Zot admin creds from OpenBao into a tempfile authfile (mode 0600)
3. `skopeo copy` GHCR → Zot, per-arch (`dmf_architecture`), with a HEAD-precheck
   so already-present manifests are skipped
4. Removes the authfile in an `always` block — even on failure

630 also seeds awx-ee, nmos-cpp images + chart in the same pass; that's fine,
they're idempotent too.

### 6c. Helm-deploy via playbook 650

```bash
bin/run-playbook.sh <env-name> \
  ../dmf-infra/k3s-lab-bootstrap/playbooks/650-dmf-cms.yml
```

What playbook 650 does (post-pivot — it no longer builds or pushes):
1. Reads existing runtime Secret keys and Authentik OIDC client creds
2. **HEAD-checks** `registry.dmf.example.com/v2/dmf-cms/manifests/<VERSION>`;
   fails loud with a pointer at 630 if absent (legacy workstation-build
   fallback was removed in the 2026-05-19 convergence)
3. Gathers catalog YAMLs into the Helm ConfigMap values
4. Templates `values.yml.j2`, runs `helm upgrade --install`
5. Waits for the deployment to be ready

### When you only need to re-mirror

If 650 fails at the HEAD check ("image not in Zot") and you just want to
re-run the mirror without walking the rest of post-seed:

```bash
bin/run-playbook.sh <env-name> \
  ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml --tags zot-seed
```

---

## 7. Verify the rollout reached the cluster

```bash
cd ~/repos/dmfdeploy/dmf-cms
scripts/verify-cluster.sh
```

This SSHes to the control node (`k3s-admin@<control-node-public-ip>`), reads the deployed image
spec, and confirms it matches local `VERSION`. Then waits for rollout and curls
`https://console.dmf.example.com/healthz`.

If `verify-cluster.sh` reports drift, **do not** patch the Helm release by hand.
Re-run playbook 650 — the role is idempotent and reads `cms_image_tag` from
`dmf-cms/VERSION` at runtime.

For broader cluster operations, use the `dmf-cluster-access` skill.

---

## 8. The scripts (canonical reference)

| Script | Purpose | When to run |
|---|---|---|
| `scripts/sync-version.sh` | Propagate VERSION → 5 derived files; `--check` for CI | Every PR; after manual VERSION edit |
| `scripts/build-image.sh` | Build a single tag locally; refuses dirty/duplicate | Rarely directly — `release.sh` calls it with `--no-push` |
| `scripts/release.sh` | End-to-end: bump → sync → commit → tag → build (no push) | Every release |
| `scripts/publish-to-ghcr.sh` | Push the locally-built image to `ghcr.io/dmfdeploy/dmf-cms:<VERSION>` | After every `release.sh` |
| `scripts/verify-cluster.sh` | Confirm cluster image matches local VERSION | After every playbook 650 run |
| Local dev | `uvicorn` + `npm run dev` | Daily |

**No other entry points are sanctioned.** If you find yourself running
`docker build`, `docker push`, or `helm upgrade` by hand, stop and use the
script. In particular, do not `docker push registry.dmf.example.com/dmf-cms:*` —
that path was removed in the 2026-05-19 convergence; publish via GHCR + 630.

---

## 9. Anti-patterns (named so you can spot them in PRs)

| Anti-pattern | Why it breaks | Do instead |
|---|---|---|
| `docker build -t dmf-cms:latest .` | No version traceability | `scripts/release.sh` |
| Edit `pyproject.toml` version by hand | Drifts from chart/values | `scripts/sync-version.sh X.Y.Z` |
| `git tag` without bumping VERSION | Image doesn't match tag | `scripts/release.sh` |
| Pushing image with dirty working tree | Can't reproduce later | Commit first, then build |
| Add `frontend/src/` to `.gitignore` | Fresh clones can't build (we got bitten 2026-05-01) | Source belongs in git |
| Re-use a tag (rebuild `0.2.2`) | Pods cache by tag, won't repull | Bump VERSION |
| `imagePullPolicy: Always` to "fix" caching | Hides drift instead of solving it | Bump VERSION |
| `kubectl get` from local Mac to confirm rollout | Wrong context, silent | `scripts/verify-cluster.sh` |
| `npm install` in CI / Dockerfile | Mutates lockfile, breaks reproducibility | `npm ci` only |
| `docker push registry.dmf.example.com/dmf-cms:...` from workstation | Path removed 2026-05-19; no creds, will fail | `publish-to-ghcr.sh` + playbook 630 |
| Re-running 650 to "fix" a missing image | 650 only HEAD-checks Zot, it never pushes | Re-run 630 (or `bootstrap-provision-post-seed.yml --tags zot-seed`) |

---

## 10. Build-reproducibility hard rules

- **Dockerfile is two-stage and fixed.** Stage 1 builds `static/app/` via Vite;
  Stage 2 installs the Python package and copies the bundle into the
  site-packages install location (FastAPI resolves static paths from the
  installed package, not the source tree). Don't change the COPY line without
  testing a fresh clone build.
- **Image labels** carry `org.opencontainers.image.{version,revision,source}` —
  `docker inspect` exposes them; useful for forensics.
- **`package-lock.json` is tracked.** `frontend/src/` is tracked. `VERSION` is tracked.
  Never add any of these to `.gitignore`.
- **Cosign signing** is deferred. When wired, `build-image.sh` adds `cosign sign`
  after `docker push` and the cluster gates pulls on a verified signature.

---

## 11. References

- `dmfdeploy/dmf-cms/docs/DEVELOPMENT-AND-BUILD-RULES.md` — **canonical**, deeper detail
- `dmfdeploy/dmf-cms/docs/IMPLEMENTATION-STRATEGY.md` — release-N planning context (pre-pivot — see banner)
- `dmfdeploy/dmf-cms/AGENTS.md` — frontend design system + React conventions
- `dmfdeploy/dmf-cms/Dockerfile` — two-stage build (do not edit lightly)
- `dmfdeploy/dmf-cms/charts/dmf-cms/` — Helm chart (derived from VERSION)
- `dmfdeploy/bin/publish-image-to-ghcr.sh` — umbrella helper that `publish-to-ghcr.sh` delegates to (isolated DOCKER_CONFIG, stdin token)
- `dmfdeploy/dmf-infra/k3s-lab-bootstrap/playbooks/630-zot-seed-platform.yml` — GHCR → Zot mirror, ADR-0025 Stage 4b
- `dmfdeploy/dmf-infra/k3s-lab-bootstrap/playbooks/650-dmf-cms.yml` — Helm-only deploy, HEAD-checks Zot
- `dmfdeploy/docs/decisions/` — ADR-0025 (convergence), ADR-0007 (secrets discipline)
- `dmfdeploy/docs/plans/DMF Console Initial Implementation Plan 2026-04-26.md` — product context
- Sibling skill: `dmf-cluster-access` — for operating against the cluster

---

**When in doubt:** run `scripts/sync-version.sh --check`. If it fails, the repo
state is broken — fix that before touching the cluster. Then `scripts/verify-cluster.sh`.
If the cluster doesn't match VERSION: if the image is missing from Zot, re-run 630;
if it's in Zot but the deployment is on the old tag, re-run 650. Either way, don't
hand-patch the Helm release.
