---
name: hardened-github-actions-multi-repo
description: Create hardened, SHA-pinned GitHub Actions workflows (guard + per-stack ci) across multiple independent repos — resolve pins, create byte-identical files, run grep-proof verification
source: auto-skill
extracted_at: '2026-06-09T17:30:00.000Z'
---

# Hardened GitHub Actions Multi-Repo Deployment

When creating security-gated GitHub Actions workflows across multiple independent repos for a public release:

## When to use

- Setting up PR-gate CI for public repos that accept fork PRs
- Creating identical security gate workflows across multiple repos
- Hardening existing CI workflows (tightening triggers, pinning actions, removing secrets from PR jobs)
- Per-stack lint/test workflows (python-web, ansible, bash-tf, docs variants)

## Resolving action SHAs

Use `gh api` to resolve tags to 40-hex commit SHAs. For annotated tags, dereference:

```bash
# Step 1: get the tag object
gh api repos/actions/checkout/git/refs/tags/v4.2.2 --jq '.object.sha,.object.type'
# If type == "tag" (annotated), dereference:
gh api repos/actions/checkout/git/tags/<sha-from-step1> --jq '.object.sha'
# If type == "commit", that's your SHA directly
```

Format in YAML: `uses: owner/repo@<40-char-sha>  # vX.Y.Z`

Common actions and their resolution:
- `actions/checkout`, `actions/setup-python`, `actions/setup-node` — all under `github.com/actions/`
- `azure/setup-helm` — under `github.com/azure/`

## Resolving binary SHA256 pins

For tools downloaded from GitHub releases, get the checksum from the release's `*_checksums.txt`:

```bash
curl -fsSL https://github.com/<owner>/<repo>/releases/download/v<ver>/<name>_<ver>_checksums.txt
# Find the line matching your arch, e.g.:
# 5bc418...  gitleaks_8.21.2_linux_x64.tar.gz
```

Use `curl -fsSLo` + `sha256sum -c -` pattern in the workflow:

```yaml
- name: tool (pinned binary + sha256)
  env:
    TOOL_VERSION: "X.Y.Z"
    TOOL_SHA256: "<64-hex-from-checksums>"
  run: |
    curl -fsSLo /tmp/tool.tgz "https://github.com/.../v${TOOL_VERSION}/..."
    echo "${TOOL_SHA256}  /tmp/tool.tgz" | sha256sum -c -
    tar -xzf /tmp/tool.tgz -C /tmp <binary-name>
    /tmp/<binary-name> ...
```

**Deviation handling:** If a version is yanked (checksums 404), use latest stable and record the deviation. If no checksums published (e.g., shellcheck, opentofu), fall back to apt-get install or version-pinned zip download without sha256.

## Hardening rules (every workflow file)

- **Trigger:** `on: pull_request: branches: [main]` + `push: branches: [main]` only. NEVER `pull_request_target`. NEVER `branches: ["**"]`.
- **Permissions:** top-level `permissions: contents: read`. Add scoped extras only on specific jobs.
- **No secrets** in any PR-triggered job. No `secrets.*` references.
- **SHA-pin every `uses:`** to 40-hex + `# vX.Y.Z` comment.
- **`persist-credentials: false`** on every `actions/checkout`.
- **`runs-on: ubuntu-24.04`** (or `ubuntu-24.04-arm` for native arm builds).
- **`concurrency:`** per ref with `cancel-in-progress: true`.
- **`timeout-minutes:`** on every job.

## Fork-PR security patterns

### gitleaks base-ref config
On `pull_request`, scan the BASE branch's config, not the PR's working file:

```yaml
- name: Resolve config from BASE
  env:
    BASE_SHA: ${{ github.event.pull_request.base.sha }}
  run: |
    if [ -n "${BASE_SHA:-}" ]; then
      git show "${BASE_SHA}:.gitleaks.toml" > /tmp/gitleaks.toml
    else
      cp .gitleaks.toml /tmp/gitleaks.toml
    fi
```

### No in-repo scripts as security gates
`guard.yml` must never call `bin/...` repo-local scripts — a PR could edit them. All scanners must be inline pinned binaries.

### No composite security actions
Avoid `aquasecurity/trivy-action`, `gitleaks-action` — they pull mutable-tag dependencies internally. Use inline pinned binaries instead.

## Per-stack ci.yml variants

### python-web
- `setup-python` + `pip install .[dev]` + lint (ruff only if in pyproject.toml) + pytest
- Matrix for multiple python versions if existing workflow has it
- Helm template renders if the repo has charts (no secrets in --set values)

### ansible
- Install tooling: `pip install ansible ansible-lint yamllint`
- Install collections: `ansible-galaxy collection install -r requirements.yml` (or repo-specific paths)
- yamllint → ansible-lint → syntax-check loop over playbooks/*.yml
- helm-lint charts/ if charts exist (use find/Chart.yaml with nullglob so empty dirs skip cleanly)
- Use `working-directory:` for repos with nested content (e.g., `k3s-lab-bootstrap/`)

### bash-tf (OpenTofu)
- shellcheck via find/nullglob over bin/*.sh
- tofu validate: only credential-free roots, `init -backend=false` then `validate`
- Explicit hermetic tests only (confirm each needs no live cluster/secrets, skip-clean if tools missing)

### docs (umbrella)
- shellcheck bin/*.sh (apt-get install since shellcheck has no checksums)
- No markdown lint (noisy on existing docs)

## Creating byte-identical files across repos

Write once, copy everywhere, verify:

```bash
# Write to one location
# Copy to all sibling repos
for r in repo1 repo2 repo3; do
  mkdir -p "$r/.github/workflows"
  cp .github/workflows/guard.yml "$r/.github/workflows/guard.yml"
done
# Verify byte-identical
for r in . repo1 repo2 repo3; do
  md5sum "$r/.github/workflows/guard.yml"
done | awk '{print $1}' | sort -u
# Should output exactly 1 hash
```

## Grep-proof verification suite

After creating all files, run these checks (all must pass):

```bash
REPOS=(. repo1 repo2 repo3 ...)

# 1. File presence
for r in "${REPOS[@]}"; do
  [ -f "$r/.github/workflows/guard.yml" ] && [ -f "$r/.github/workflows/ci.yml" ]
done

# 2. guard.yml byte-identical (1 distinct md5)

# 3. No pull_request_target
grep -rl 'pull_request_target' "$r"/.github/workflows/  # must be empty

# 4. No secrets.
grep -rl 'secrets\.' "$r"/.github/workflows/  # must be empty

# 5. No banned composite actions
grep -rnE 'aquasecurity/(trivy-action|setup-trivy)|gitleaks/gitleaks-action' "$r"/.github/workflows/

# 6. Every uses: SHA-pinned (40-hex)
grep -rhoE 'uses: *[^ ]+' "$r"/.github/workflows/*.yml | grep -vE '@[0-9a-f]{40}( |$)'  # must be empty

# 7. Top-level permissions: contents: read
grep -A1 'permissions:' "$r"/.github/workflows/*.yml | grep -q 'contents: read'

# 8. persist-credentials: false on every checkout
# Count checkouts vs persist-credentials:false — must match

# 9. runs-on ∈ {ubuntu-24.04, ubuntu-24.04-arm}
grep -rh 'runs-on:' "$r"/.github/workflows/*.yml | grep -vE 'ubuntu-24\.04(-arm)?'  # must be empty

# 10. .forgejo/ untouched
git -C "$r" status --porcelain .forgejo/  # must be empty
```

## Hardening an existing ci.yml

When hardening (not creating new):
- Read the existing file first
- Keep all real steps, change only: triggers, permissions, action refs, runner, concurrency, timeout
- Remove `workflow_dispatch` if not needed for PR gates
- Replace `branches: ["**"]` with `branches: [main]`
- Replace `ubuntu-latest` with `ubuntu-24.04`
- Replace floating `@v4` refs with SHA pins
- Add `persist-credentials: false` to all checkouts
- Do NOT add new lint tools not already configured (e.g., don't add ruff if not in pyproject.toml)

## Hermetic test judgment

For test scripts in CI, confirm each is hermetic before including:
- Uses temp dirs (mktemp), not permanent state
- Uses throwaway keys/certs, not real credentials
- Skips cleanly if required tools not available (exit 0 with SKIP message)
- No live cluster connections, no secrets, no network calls to real services
- Do NOT glob-run all tests/*.sh — list explicitly by name
