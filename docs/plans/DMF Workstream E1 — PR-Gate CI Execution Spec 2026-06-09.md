---
status: executed
date: 2026-06-09
executed: 2026-06-09
---
# DMF Workstream E1 — PR-Gate CI Execution Spec

**Date:** 2026-06-09 · **Status:** Draft for codex cross-check → qwen lift
**Author:** umbrella session (claude, orchestrator)
**Parent plan:** [`DMF First Public Release Plan 2026-06-09.md`](DMF%20First%20Public%20Release%20Plan%202026-06-09.md) §Workstream E (E1)
**Pairs with:** [`DMF Workstream D — GitHub-First Governance Execution Spec 2026-06-09.md`](DMF%20Workstream%20D%20—%20GitHub-First%20Governance%20Execution%20Spec%202026-06-09.md)
(D shipped the DCO workflow; E1 ships the remaining PR gates. Both `.github/`
contents **co-export into the same Workstream A orphan commit**, so a public repo
never exists without its gates.)

> **Self-contained.** A lifting agent should execute this end-to-end from the
> templates + the per-repo stack matrix (§7) without reading other docs. Where a
> file must be derived from an existing one, the source path is given.

---

## 0. Scope & non-goals

**In scope — before-flip PR gates, GitHub Actions, hosted runners only:**

1. A **shared security gate** workflow (`.github/workflows/guard.yml`), **byte-identical
   across all 9 repos** (like `dco.yml`): gitleaks (in-repo config), trivy fs scan,
   Conventional-Commits check (inline), and `actionlint`.
2. A **per-stack lint/test** workflow (`.github/workflows/ci.yml`), one of 4 variants
   (python-web / ansible / bash-tf / docs), ported from each repo's existing
   `.forgejo/workflows/ci.yml` logic and **hardened** (hosted runner, `permissions`,
   SHA-pinned actions, `pull_request` trigger).
3. **Fork-PR hardening** applied to every workflow (§1).
4. A committed **Conventional-Commits contract** (the inline check; no external config).

**Non-goals (do NOT do here):**
- **dmf-init appliance bundle build** (`dmf-init/.forgejo/workflows/build-bundle.yml`)
  is **NOT** a PR gate — it needs `secrets.DMF_REPO_TOKEN` + a self-hosted builder, so
  it can never run on a fork PR. Leave it on `.forgejo`. Porting it to GitHub +
  validating the **14 GB hosted-runner disk ceiling** is an **E2 / separate spike**
  (§6). E1 only records the constraint.
- **Release automation** (VERSION→tag→GHCR, CHANGELOG, umbrella release manifest) = **E2**.
- Branch/tag **rulesets**, required-check enablement, secret-scanning, the public flip,
  and merge-method = **Workstream A** (E1 only authors the workflows; A wires them as
  required checks and sets rebase-merge).
- Do **not** delete or rewrite the existing `.forgejo/workflows/*` (LAN CI keeps working).

---

## 1. Hardening rules (apply to EVERY workflow this spec creates)

Public repos accept fork PRs → a malicious PR must not be able to exfiltrate secrets
or weaken its own checks. Non-negotiable for every workflow file:

- **Trigger:** `on: pull_request:` (target `main`) **and** `push:` to `main` only (for
  the main-tip scan). **NEVER `pull_request_target`.** No `branches: ["**"]` (the old
  dmf-cms `ci.yml` runs on every push to every branch — tighten to `main`).
- **Permissions:** top-level **`permissions: contents: read`** (least privilege). Add a
  scoped extra (e.g. `pull-requests: read`) only on the job that needs it.
- **No secrets in any PR-triggered job.** No `secrets.*` references, no registry login,
  no deploy. (Why E1 excludes the bundle build.)
- **SHA-pin every `uses:`** to a full 40-char commit SHA with a trailing `# vX.Y.Z`
  comment — **including `actions/*`** (first-party pinned too, for consistency). No
  floating `@v4`. Resolve SHAs per §3.
- **`pull_request` runs the workflow YAML from the _base_ branch**, so a fork PR cannot
  edit the gate that judges it — good. **But in-repo files the workflow READS are
  PR-controlled:** `.gitleaks.toml`, `commitlint` config, lint configs. So:
  - Security scanners use **pinned tool versions / pinned actions**, never an in-repo
    script a PR could edit (do NOT call `bin/scrub-public-repos.sh` from repo CI — see §2).
  - `.gitleaks.toml`, `.github/`, and lint configs are **CODEOWNERS-protected**
    (Workstream D) so a PR weakening an allowlist requires maintainer review. (Note for
    Workstream A: enable "require review from Code Owners" + "dismiss stale approvals".)
- **`concurrency:`** per ref to cancel superseded runs (cost + speed); harmless.
- **`timeout-minutes:`** on every job (default 15; bump for build jobs).
- Hosted runners only: **`runs-on: ubuntu-24.04`** (use `ubuntu-24.04-arm` only where an
  arm build is required — **dmf-init's `docker-build-smoke` runs on `ubuntu-24.04-arm`**
  (native arm, matches the CAX21 ARM64 target; §4 Variant A). The secret-bearing arm
  appliance bundle build stays E2.

---

## 2. Shared security gate — `.github/workflows/guard.yml` (byte-identical, all 9)

The single most important gate. Identical file in every repo (verify by `md5`/`cmp`,
like `dco.yml`). Four independent jobs so one failure is legible.

> **gitleaks vs. `scrub-public-repos.sh`:** the umbrella's `bin/scrub-public-repos.sh`
> is a **cross-repo, umbrella-side** tool that assumes repos under `UMBRELLA_DIR` — it
> cannot run inside an independent public repo's CI, and (being in-repo if copied) a PR
> could edit it. **The public-safe scrub patterns already live in each repo's
> `.gitleaks.toml`** (rules `dmf-dev-changeme`, `dmf-private-network-literal`,
> `dmf-macos-metadata`, generic-api-key). So **per-repo gitleaks IS the scrub gate**;
> the umbrella scrub stays the pre-publish/pre-receive tool. (Operator-identity rules
> intentionally live only in the private umbrella — public repos must not contain
> operator identity at all; the Workstream A export gate is the backstop.)

**All scanners are inline pinned binaries with SHA256 verification** (codex): the
`aquasecurity/trivy-action` composite calls `setup-trivy` + `actions/cache` by **mutable
tags**, so a top-level SHA pin does **not** satisfy "all `uses:` pinned" (and that chain
was compromised in 2026). So Trivy, gitleaks, and actionlint are all downloaded as
version-pinned binaries with a hard-coded `sha256sum -c` check before execution — no
composite security action. Every `checkout` sets **`persist-credentials: false`** so
untrusted PR code can't read the token from `.git/config`.

```yaml
name: guard
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
permissions:
  contents: read
concurrency:
  group: guard-${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true
jobs:
  gitleaks:
    runs-on: ubuntu-24.04
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@<SHA>  # v4.2.2 — full history for the PR commit range
        with:
          fetch-depth: 0
          persist-credentials: false
      - name: Resolve config from BASE (never trust the PR-controlled .gitleaks.toml)
        env:
          BASE_SHA: ${{ github.event.pull_request.base.sha }}
        run: |
          set -eu
          if [ -n "${BASE_SHA:-}" ]; then
            # pull_request: scan with the base branch's config, not the PR's
            git show "${BASE_SHA}:.gitleaks.toml" > /tmp/gitleaks.toml
          else
            # push to main: the checked-out file IS the trusted config
            cp .gitleaks.toml /tmp/gitleaks.toml
          fi
      - name: gitleaks (pinned binary + sha256)
        env:
          GL_VERSION: "8.21.2"          # lifter: confirm latest stable
          GL_SHA256: "<PIN sha256 of gitleaks_${GL_VERSION}_linux_x64.tar.gz>"
        run: |
          set -eu
          curl -fsSLo /tmp/gl.tgz "https://github.com/gitleaks/gitleaks/releases/download/v${GL_VERSION}/gitleaks_${GL_VERSION}_linux_x64.tar.gz"
          echo "${GL_SHA256}  /tmp/gl.tgz" | sha256sum -c -
          tar -xzf /tmp/gl.tgz -C /tmp gitleaks
          /tmp/gitleaks detect --source . --config /tmp/gitleaks.toml --redact --no-banner --exit-code 1
      - name: Sanity-lint the PR's proposed .gitleaks.toml (non-blocking on content)
        if: github.event_name == 'pull_request'
        run: /tmp/gitleaks detect --no-git --source /dev/null --config .gitleaks.toml >/dev/null 2>&1 || echo "::warning::PR .gitleaks.toml changed — review the allowlist diff (CODEOWNERS-gated)"

  commitlint:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    permissions:
      contents: read
      pull-requests: read
    if: github.event_name == 'pull_request'
    steps:
      - name: Conventional Commits check (inline, PR commits API)
        env:
          GH_TOKEN: ${{ github.token }}
          COMMITS_URL: ${{ github.event.pull_request.commits_url }}
        run: |
          set -eu
          bad=0
          re='^(feat|fix|docs|chore|refactor|test|build|ci|perf|revert|style)(\([a-z0-9._-]+\))?!?: .+'
          page=1
          while :; do
            batch="$(gh api "${COMMITS_URL}?per_page=100&page=${page}" --jq '.[] | @base64')"
            [ -z "$batch" ] && break
            for row in $batch; do
              subj="$(printf '%s' "$row" | base64 -d | python3 -c 'import sys,json;print(json.load(sys.stdin)["commit"]["message"].splitlines()[0])')"
              case "$subj" in "Merge "*) continue;; esac
              if ! printf '%s' "$subj" | grep -qE "$re"; then
                echo "::error::non-conventional commit subject: $subj"
                bad=1
              fi
            done
            page=$((page+1))
          done
          [ "$bad" -eq 0 ] || exit 1

  trivy:
    runs-on: ubuntu-24.04
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@<SHA>  # v4.2.2
        with:
          persist-credentials: false
      - name: trivy fs — vuln only (pinned binary + sha256)
        env:
          TRIVY_VERSION: "0.58.0"       # lifter: confirm latest stable
          TRIVY_SHA256: "<PIN sha256 of trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz>"
        run: |
          set -eu
          curl -fsSLo /tmp/trivy.tgz "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-64bit.tar.gz"
          echo "${TRIVY_SHA256}  /tmp/trivy.tgz" | sha256sum -c -
          tar -xzf /tmp/trivy.tgz -C /tmp trivy
          # vuln scanner only — NOT misconfig/secret (avoid untuned Helm/TF noise as a first-run blocking gate)
          /tmp/trivy fs --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --no-progress .

  actionlint:
    runs-on: ubuntu-24.04
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@<SHA>  # v4.2.2
        with:
          persist-credentials: false
      - name: actionlint (pinned binary + sha256)
        env:
          AL_VERSION: "1.7.7"           # lifter: confirm latest stable
          AL_SHA256: "<PIN sha256 of actionlint_${AL_VERSION}_linux_amd64.tar.gz>"
        run: |
          set -eu
          curl -fsSLo /tmp/al.tgz "https://github.com/rhysd/actionlint/releases/download/v${AL_VERSION}/actionlint_${AL_VERSION}_linux_amd64.tar.gz"
          echo "${AL_SHA256}  /tmp/al.tgz" | sha256sum -c -
          tar -xzf /tmp/al.tgz -C /tmp actionlint
          /tmp/actionlint -color
```

**Notes for the lifter:**
- **Pin the SHA256 of every downloaded artifact** from the release's published checksums
  (`*_checksums.txt` on the GitHub release). `curl -fsSLo` + `sha256sum -c -` is mandatory;
  version-only is not a pin (codex). If a version moved, pin the current stable + its sha256.
- Only **`actions/checkout`** remains as an external `uses:` (first-party) — SHA-pin it (§3).
  No `aquasecurity/trivy-action` / `gitleaks-action` (transitive mutable-tag risk).
- **gitleaks scans the BASE-ref config** on `pull_request` so a PR cannot weaken the
  allowlist that judges it (CODEOWNERS alone is insufficient for a security gate, codex).
- `guard.yml` is **byte-identical in all 9 repos** (incl. umbrella; gitleaks uses whatever
  `.gitleaks.toml`/base config is present).

---

## 3. Action SHA-pinning (resolve before lift)

Pin each `uses:` to the commit SHA of the named release tag. Resolve with:

```bash
gh api repos/<owner>/<repo>/git/refs/tags/<tag> --jq '.object.sha,.object.type'
# if type == "tag" (annotated), deref:
gh api repos/<owner>/<repo>/git/tags/<that-sha> --jq '.object.sha'
```

| Action | Tag to pin | Used by |
|---|---|---|
| `actions/checkout` | `v4.2.2` | guard, ci (all) |
| `actions/setup-python` | `v5.3.0` | ci (python-web, python) |
| `actions/setup-node` | `v4.1.0` | ci (python-web frontend) |
| `azure/setup-helm` | `v4.2.0` | ci (python-web cms, ansible helm-lint) |

> Record the resolved SHA inline as `uses: owner/repo@<40-char-sha>  # vX.Y.Z`. If a
> listed tag has moved, pin the **current latest stable** and update the comment. **No
> floating major tags anywhere.** Same applies to D's `dco.yml` if it grows a `uses:`
> (it currently has none — leave it).
>
> **No `aquasecurity/trivy-action` / `gitleaks-action`** — those composites pull
> `setup-trivy`/`actions/cache`/etc. by mutable tags (uncloseable transitive surface,
> 2026 compromise). The guard scanners are inline pinned binaries (§2). The binary
> SHA256 values (gitleaks/trivy/actionlint) are pinned in `guard.yml` from each release's
> published `*_checksums.txt`.

---

## 4. Per-stack lint/test — `.github/workflows/ci.yml`

Port each repo's existing `.forgejo/workflows/ci.yml` **logic** to a hardened GitHub
workflow. Keep the lint/test commands; change only host/triggers/permissions/pins.
Common header for every variant:

```yaml
name: ci
on:
  pull_request:
    branches: [main]
  push:
    branches: [main]
permissions:
  contents: read
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

**Common to every `ci.yml`:** all `actions/checkout` steps set
`persist-credentials: false` (untrusted-PR token exfil). Match each repo's REAL tooling —
**do not invent a lint target that fails on first run** (codex). Read the repo's
`pyproject.toml`/`requirements.yml`/`.forgejo/ci.yml` to confirm.

### Variant A — python-web (dmf-cms, dmf-init)
- **dmf-cms — HARDEN the existing `.github/workflows/ci.yml`** (do NOT add a 2nd, do NOT
  add ruff — **dmf-cms `pyproject.toml` has no ruff**). Keep its real steps: matrix
  `["3.12","3.13"]`, `pip install -e '.[dev]'`, `python -m compileall src tests`,
  `pip check`, the helm-template renders, `pytest`. Only ADD hardening: top-level
  `permissions: contents: read`, SHA-pin `setup-python`/`setup-helm`/`checkout`,
  `persist-credentials: false`, tighten triggers to `pull_request`+`push:main` (drop
  `branches: ["**"]`), `concurrency`, `timeout-minutes`.
- **dmf-init — port its `.forgejo/ci.yml`** (python: `pip install .[dev]` → `ruff check .`
  → `pytest` — ruff IS configured here; frontend: `npm ci` → `npm run build`;
  docker-build-smoke). Harden as above.
- **`docker-build-smoke` (dmf-init): run NATIVE-ARCH** — the `.forgejo` build uses
  `--platform linux/arm64`, which on x86 `ubuntu-24.04` needs qemu/buildx. Either
  **`runs-on: ubuntu-24.04-arm` + drop `--platform`** (native arm, representative of the
  CAX21 ARM64 target — preferred), or stay x86 with a pinned `docker/setup-qemu-action`
  + `setup-buildx-action` (more pinned surface). **Preferred: ubuntu-24.04-arm, no
  `--platform`.** `needs: [python, frontend]`, `timeout-minutes: 30`, **no registry
  login / no secrets / `persist-credentials: false`** (the smoke build, NOT the
  secret-bearing appliance bundle — §6).

### Variant B — ansible (dmf-infra, dmf-runbooks, dmf-media, dmf-central)
**Every Ansible repo MUST install its collections before lint/syntax-check** — hosted
runners have no `kubernetes.core`/`ansible.posix`/etc. (codex). Per repo:
`pip install ansible ansible-lint yamllint` →
`ansible-galaxy collection install -r <that repo's requirements.yml>` → then lint.

Per-repo concrete paths (confirmed in-tree — **do NOT "port .forgejo" for dmf-runbooks,
it has none**):
- **dmf-infra:** set the job **`working-directory: k3s-lab-bootstrap`** and use
  **relative** paths from there (don't mix `working-directory` with `k3s-lab-bootstrap/…`
  prefixes — pick one; this is the clearer form): `ansible-galaxy collection install -r
  requirements.yml -r ee/requirements.yml` → `yamllint -s .` → `ansible-lint playbooks/ -p`
  → syntax-check loop over `playbooks/*.yml` → **helm-lint `charts/*/`** via find/nullglob
  (skip cleanly if empty). (`actions/checkout` runs at repo root; only the lint job steps
  set `working-directory`.)
- **dmf-runbooks:** `requirements.yml` at root; `yamllint -s playbooks/ roles/`;
  `ansible-lint playbooks/ roles/ -p`; syntax-check `playbooks/*.yml`. **No `charts/` →
  no helm-lint.**
- **dmf-media:** root `requirements.yml`; yamllint/ansible-lint its playbooks+roles;
  **has `charts/` → helm-lint `charts/*/`**.
- **dmf-central:** root `requirements.yml`; yamllint/ansible-lint its content; **has
  `charts/` → helm-lint `charts/*/`**.
- `helm-lint` uses `setup-helm@<SHA>`; iterate charts via `find`/`nullglob` so an empty
  charts dir **skips cleanly** (exit 0), never errors.

### Variant C — bash-tf (dmf-env) — OpenTofu, not Terraform
dmf-env uses **`tofu` (OpenTofu)**. Tracked public surface is only `terraform/hetzner`,
`terraform/modules/`, `terraform/README.md` (aliyun/g2r6/hetzner-arm dirs are untracked
local state — never in CI). New workflow:
- `shellcheck`: install shellcheck (pinned) → collect scripts via **`find`/`nullglob`**
  (`bin/*.sh`, `lib/` if present, `tasks/` actual `.sh`) — **do NOT glob `tasks/**/*.sh`
  (matches nothing today)** and include `bin/`. Skip cleanly if a dir is empty.
- `tofu-validate`: install pinned `tofu` → for the **generic exportable roots only**
  (`terraform/hetzner`, `terraform/modules/hetzner/cluster`, and any other module that
  validates with **no creds/backend**): `tofu fmt -check -recursive` +
  `tofu -chdir=<root> init -backend=false && tofu -chdir=<root> validate`. **Never
  recurse all of `terraform/`.** No `apply`, no backend, no secrets. Lifter confirms each
  root validates credential-free before adding it.
- `tests`: run only **explicitly listed hermetic** scripts (confirm each needs no live
  cluster/secrets) — candidates: `tests/wizard-noninteractive-parity.sh`,
  `tests/bundle-set-roundtrip.sh`. **Do NOT glob-run all `tests/*.sh`**
  (`unseal-openbao-ssh-key.sh`, `remove-env-data-root.sh` may touch state). List them by
  name; the lifter verifies hermeticity and drops any that aren't.

### Variant D — docs (umbrella `.`, dmf-promsd partially)
- **Umbrella:** the `guard.yml` (gitleaks/commitlint/actionlint) is the primary gate.
  Add a light `ci.yml` with a `shellcheck bin/*.sh` job (the umbrella has a real `bin/`).
  Markdown lint is optional — **omit** unless trivial (avoid noisy failures on existing docs).
- **dmf-promsd:** it's Python with `tests/` but no `.forgejo` ci. Add a python `ci.yml`
  (setup-python → `pip install` deps/`.[dev]` → `ruff check .` if configured → `pytest`).
  Confirm the dependency/install command from its `pyproject.toml`/`requirements*.txt`.

> If a variant's tool isn't actually configured in a repo (e.g. `ruff` not in deps),
> the lifter either installs it standalone or drops that step — **do not invent a lint
> target that fails on first run.** Match the repo's reality (read its `.forgejo/ci.yml`
> + `pyproject.toml`). Record any per-repo deviation in the lift report.

---

## 5. Conventional-Commits contract

E1 introduces the contract enforced by `guard.yml`'s inline `commitlint` job. No
external config/action. Allowed types: `feat fix docs chore refactor test build ci
perf revert style`; optional `(scope)`; optional `!`; subject required. Merge commits
skipped. (Matches CONTRIBUTING from Workstream D.) **No separate config file** to keep
the gate uneditable by a PR beyond the base-branch workflow.

---

## 6. dmf-init appliance bundle — explicitly deferred (E2 / spike)

`dmf-init/.forgejo/workflows/build-bundle.yml` builds the self-contained appliance image
on the self-hosted `dmf-builder` runner using `secrets.DMF_REPO_TOKEN`. It is
**host-agnostic** (`${{ github.server_url }}`), so it *ports* to GitHub with a
`runs-on:` change — **but:**
- It carries a **secret** and clones private repos → **must not be a `pull_request`
  job** (fork-PR exfiltration). On GitHub it becomes a **`workflow_dispatch` / `v*` tag**
  job (E2 release path), not a PR gate.
- **14 GB hosted-runner disk ceiling [parent plan]:** the bundle bakes 6 repos + images.
  **Before** relying on a hosted runner for it, run a one-off disk-usage check of the
  built bundle (`docker system df` + bundle tarball size) against 14 GB. If it doesn't
  fit, the bundle build stays self-hosted (GitHub self-hosted runners are **forbidden on
  public repos** for fork-PR RCE — so it would run only on `tag`/`dispatch` with no fork
  exposure, or stay on LAN Forgejo). **E1 records this; the spike is E2.**

E1 leaves `build-bundle.yml` untouched on `.forgejo`. The cheap `docker build .` smoke
(Variant A) is the only image build in E1, and it pushes nothing.

---

## 7. Per-repo matrix

| Local dir | guard.yml | ci.yml variant | Notes |
|---|---|---|---|
| `.` (umbrella) | ✅ identical | **D (docs)** | ci.yml = `shellcheck bin/*.sh` |
| `dmf-cms` | ✅ | **A (python-web)** | **harden the existing `.github/ci.yml`** (don't add 2nd); keep helm renders; py matrix 3.12/3.13 |
| `dmf-init` | ✅ | **A (python-web)** | python + frontend + docker-build-smoke (no push) |
| `dmf-promsd` | ✅ | **D→python** | new python ci.yml from pyproject; pytest tests/ |
| `dmf-infra` | ✅ | **B (ansible)** | paths under `k3s-lab-bootstrap/`; has charts → helm-lint |
| `dmf-runbooks` | ✅ | **B (ansible)** | **no `.forgejo` to port** — direct ansible workflow: root `requirements.yml`, `playbooks/`+`roles/`, no charts (no helm-lint); **see co-export note §8** |
| `dmf-media` | ✅ | **B (ansible)** | charts in `charts/` → helm-lint |
| `dmf-central` | ✅ | **B (ansible)** | port its `.forgejo/ci.yml`; root `requirements.yml`; has `charts/`→helm-lint |
| `dmf-env` | ✅ | **C (bash-tf)** | **OpenTofu (`tofu`)**: `find`-based shellcheck of `bin/`; `tofu validate` of credential-free generic roots only (`terraform/hetzner`, `terraform/modules/hetzner/cluster`); **explicit** hermetic tests (wizard-noninteractive-parity, bundle-set-roundtrip) — not globbed |

---

## 8. Co-export / sequencing (with Workstream D + A)

- E1's `.github/workflows/*` co-export with D's `.github/` into the **same Workstream A
  orphan commit** for the 8 clean-import repos — a public repo never exists without its
  gates (D §0 invariant).
- **`dmf-runbooks` (already public):** D's commit is local-only pending E1. **E1 IS that
  batch** — once E1's `ci.yml`+`guard.yml` land locally for dmf-runbooks, D+E1 together
  form one public PR. Still **do not `git push github` in E1**; the orchestrator commits
  locally, and the dmf-runbooks D+E1 push happens as a single reviewed PR (operator-gated).
- **All E1 commits are LOCAL-ONLY (no push)** — same rule as D.
- Workstream A wires these as **required status checks** + sets **rebase-merge** + the
  rulesets; E1 only authors the files.

> **⚠️ LAN Forgejo push-mirror hazard (operator-flagged, 2026-06-09).** dmf-runbooks
> remotes: `origin` → LAN Forgejo `forgejo-<handle>:<handle>/dmf-runbooks`, `github` →
> `github.com/dmfdeploy/dmf-runbooks`. A **push mirror is a Forgejo server-side setting**
> (repo Settings → Mirror Settings) — invisible to local `git config`. If a
> Forgejo→GitHub push mirror is active, **pushing local `main` to `origin` (Forgejo)
> auto-propagates to GitHub**, publishing the dmf-runbooks D commit before the reviewed
> D+E1 PR — exactly the leak the §0/§8 exception guards against, and a direct violation
> of GitHub-canonical-forward (no "Forgejo push-mirror → GitHub").
> **Required before ANY dmf-runbooks push:** the operator confirms/disables the LAN
> Forgejo push mirror for `<handle>/dmf-runbooks` (delete it in Mirror Settings, or verify
> none exists). **Workstream A retire-to-archive must disable Forgejo→GitHub push
> mirrors on ALL repos** as the repos are created — a stale mirror on any of the other 8
> would auto-leak the moment its GitHub repo exists. Orchestrator: do **not** `git push
> origin` for dmf-runbooks in E1.

---

## 9. Verification (orchestrator runs after qwen lift — grep-proof, do not trust DONE)

> Component repos are independent/gitignored — use **`git -C "$r"`** or direct
> filesystem checks; new files are untracked so `git grep` alone misses them.

```bash
REPOS=(. dmf-cms dmf-runbooks dmf-central dmf-infra dmf-media dmf-init dmf-env dmf-promsd)
```

All checks iterate the REPOS array (so umbrella `.` is included — `git -C "$r"` or
`"$r"/.github/...`, NOT a bare `*/.github` glob that skips `.`):

- **File presence:** every repo has `.github/workflows/guard.yml` + `.github/workflows/ci.yml`.
- **guard.yml byte-identical** across all 9 (`md5`/`cmp` → 1 distinct hash).
- **Hardening, EVERY E1 workflow file** (`guard.yml` + `ci.yml`, all repos) — each a
  FAILING grep (presence = fail):
  - `for r in "${REPOS[@]}"; do grep -l 'pull_request_target' "$r"/.github/workflows/{guard,ci}.yml 2>/dev/null; done`
    → **empty** (any hit fails).
  - `for r ...; do grep -l 'secrets\.' "$r"/.github/workflows/{guard,ci}.yml; done` →
    **empty** (only `secrets.` in the tree is dmf-init's untouched `.forgejo/build-bundle.yml`).
  - **No banned composite actions:**
    `grep -rnE 'aquasecurity/(trivy-action|setup-trivy)|gitleaks/gitleaks-action' "$r"/.github/workflows/`
    → empty.
  - **Every `uses:` SHA-pinned (40-hex):**
    `grep -rhoE 'uses: *[^ ]+' "$r"/.github/workflows/{guard,ci}.yml | grep -vE '@[0-9a-f]{40}( |$)'`
    → empty. (If any composite slips in later, also recurse its repo to ban unpinned
    transitive `uses:` — none expected since scanners are inline binaries.)
  - **Every downloaded binary checksum-verified:** each `curl -fsSLo` is followed by a
    `sha256sum -c -` with a concrete 64-hex value (no `<PIN ...>` placeholders left).
  - every file has a top-level `permissions: contents: read` (nothing broader top-level);
    every `actions/checkout` has `persist-credentials: false`.
  - `runs-on:` ∈ {`ubuntu-24.04`, `ubuntu-24.04-arm`}, never `ubuntu-latest`, never a
    self-hosted label.
- **gitleaks base-config:** `guard.yml` resolves config via `git show
  ${base.sha}:.gitleaks.toml` on `pull_request` (not the PR's working-tree file).
- **actionlint passes** locally on all created files (run the pinned actionlint over each
  repo's `.github/workflows/`).
- **Triggers tightened:** no `branches: ["**"]` anywhere; dmf-cms `ci.yml` no longer
  triggers on all-branch push.
- **No in-repo script as a security gate:** `guard.yml` calls no `bin/…` repo-local script.
- **`.forgejo/` untouched:** `git -C "$r" status` shows no change under `.forgejo/`.
- **Lint targets are real (catch invented steps):** spot-run a representative tool per
  variant locally — `ansible-galaxy collection install -r <req>` then `ansible-lint` for an
  ansible repo; `ruff`/`pytest` only where actually configured (NOT dmf-cms); `shellcheck`
  + `tofu validate` for dmf-env — confirm none fail on first invocation for a
  missing/misnamed target or uninstalled collection.

Then: codex final cross-check → commit per-repo (`ci: PR gates — guard (gitleaks/trivy/
commitlint/actionlint) + per-stack ci (Workstream E1)`), signed off (`-s`), **no pushes**.

## 10. Open items — RESOLVED via codex round 1 (2026-06-09)

1. **Scanner delivery** — ✅ ALL inline pinned binaries + `sha256sum -c` (gitleaks, trivy,
   actionlint); **no** `trivy-action`/`gitleaks-action` (transitive mutable-tag /
   2026-compromise risk). trivy = **vuln scanner only** (no misconfig/secret noise as a
   first-run blocking gate).
2. **Conventional-Commits** — ✅ inline (no node/config, uneditable beyond the base-ref
   workflow). Type list + merge skip confirmed.
3. **`.gitleaks.toml` PR-editability** — ✅ FIXED properly: on `pull_request`, guard scans
   the **base-ref** config (`git show ${base.sha}:.gitleaks.toml`), not the PR's file.
   CODEOWNERS is a second layer, not the gate.
4. **Token exfil** — ✅ `persist-credentials: false` on every checkout.
5. **dmf-init docker-build-smoke arch** — ✅ native `ubuntu-24.04-arm`, drop `--platform`
   (no qemu); no secrets/push.
6. **Per-repo tooling reality** — ✅ dmf-cms keeps no-ruff (harden existing file);
   dmf-runbooks commands specified directly (no `.forgejo` to port); all Ansible repos
   `ansible-galaxy collection install -r <requirements.yml>` first; dmf-env uses **tofu**,
   validates only credential-free generic roots, `find`-based shellcheck, explicit
   hermetic tests.
7. **Verification harness** — ✅ REPOS-loop (incl. `.`), failing-grep form, ban composite
   actions + unpinned transitive `uses:`, require concrete sha256 (no placeholders left).

**LAN Forgejo push-mirror hazard (operator-flagged):** see §8 — disable the dmf-runbooks
Forgejo→GitHub push mirror before any push; Workstream A disables it on all repos.
