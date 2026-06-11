---
status: draft
date: 2026-06-10
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/7
---
# DMF dmf-init GitHub Build Workflows — Exec Spec for qwen — 2026-06-10

Add two GitHub Actions workflows (+ an actionlint config) to **`dmf-init`** so the
public GitHub repo builds the container **image → GHCR** and the offline
**appliance bundle → Release/rolling-latest**, replacing the LAN Forgejo build.

## Decisions (operator, 2026-06-10)
- **Image**: build on `v*` tags + manual dispatch only (per-version; image fetches
  component repos at runtime → no rebuild on playbook changes). Multi-arch amd64+arm64.
- **Bundle**: nightly schedule + manual dispatch → rolling `latest` (per-arch
  artifact); `v*` tag → per-arch tarball attached to the GitHub Release. Components
  baked at `main` by default.
- Repo posture: **SHA-pin every action** (the SHAs below are resolved + commented).

## Hard rules (for qwen)
- Work ONLY in `~/repos/dmfgithub/dmfdeploy/dmf-init` (origin `git@github.com:dmfdeploy/dmf-init`).
- Auth as the operator's GitHub account — `gh auth status` should already show it
  (keyring); if not, see the auth section of `DMF Doc-Hygiene PR-Submission Spec 2026-06-10.md`.
- Create the 3 files EXACTLY as below. Branch `<handle>/dmf-init-build-workflows`.
- Commit `-s` (DCO), Conventional Commit, author the operator. **No `Co-Authored-By:
  Claude` / "Generated with Claude Code" trailer** (operator is the author).
- Do NOT merge; just open the PR. STOP + report BLOCKED on any error (no --force/--no-verify).

---

## File 1 — `.github/workflows/publish-image.yml`
```yaml
name: publish-image
# Build the dmf-init container image (amd64+arm64) and push to GHCR per release
# (v* tag) or manual dispatch. Public repo -> free hosted runners; the built-in
# GITHUB_TOKEN publishes to ghcr.io/dmfdeploy/dmf-init (no PAT). The image fetches
# the component repos at RUNTIME, so it needs rebuilding only when dmf-init is
# released, not when playbooks change.
on:
  push:
    tags: ["v*"]
  workflow_dispatch:

permissions:
  contents: read
  packages: write

concurrency:
  group: publish-image-${{ github.ref }}
  cancel-in-progress: false

jobs:
  build-push:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - uses: docker/setup-qemu-action@c7c53464625b32c7a7e944ae62b3e17d2b600130  # v3
      - uses: docker/setup-buildx-action@8d2750c68a42422c14e847fe6c8ac0403b4cbd6f  # v3
      - name: Log in to GHCR
        uses: docker/login-action@c94ce9fb468520275223c153574b00df6fe4bcc9  # v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Image metadata (tags + labels)
        id: meta
        uses: docker/metadata-action@c299e40c65443455700f0fdfc63efafe5b349051  # v5
        with:
          images: ghcr.io/${{ github.repository }}
          tags: |
            type=semver,pattern={{version}}
            type=raw,value=latest
      - name: Build and push (amd64 + arm64)
        uses: docker/build-push-action@10e90e3645eae34f1e60eeb005ba3a3d33f178e8  # v6
        with:
          context: .
          platforms: linux/amd64,linux/arm64
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
```

---

## File 2 — `.github/workflows/build-bundle.yml`
```yaml
name: build-bundle
# Build the SELF-CONTAINED dmf-init appliance bundle (component repos baked in for
# offline/air-gapped use). build-bundle.sh does a single-arch `docker build`, so we
# build per-arch on native runners:
#   - nightly + manual dispatch -> rolling 'latest' (per-arch workflow artifact)
#   - v* tag                    -> per-arch tarball attached to the GitHub Release
# Components are baked at `main` (latest) by default; the build records the exact
# baked refs in the bundle's provenance. Public repos clone with no token.
on:
  push:
    tags: ["v*"]
  schedule:
    - cron: "0 3 * * *"
  workflow_dispatch:
    inputs:
      ref:
        description: "component repo ref to bake"
        default: main

permissions:
  contents: write

concurrency:
  group: build-bundle-${{ github.ref }}
  cancel-in-progress: true

jobs:
  bundle:
    strategy:
      fail-fast: false
      matrix:
        include:
          - arch: amd64
            runner: ubuntu-24.04
          - arch: arm64
            runner: ubuntu-24.04-arm
    runs-on: ${{ matrix.runner }}
    steps:
      - uses: actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683  # v4.2.2
      - name: Build appliance bundle (${{ matrix.arch }})
        env:
          REF: ${{ inputs.ref || 'main' }}
          SERVER_URL: ${{ github.server_url }}
          OWNER: ${{ github.repository_owner }}
        run: |
          set -euo pipefail
          out="$(mktemp -d)"
          bin/build-bundle.sh -o "$out" --ref "$REF" --repo-base-url "${SERVER_URL}/${OWNER}"
          src="$(ls "$out"/dmf-init-bundle-*.tar.gz)"
          dest="${out}/$(basename "$src" .tar.gz)-${{ matrix.arch }}.tar.gz"
          mv "$src" "$dest"
          echo "ASSET=$dest" >> "$GITHUB_ENV"
      - name: Attach to Release (tag builds)
        if: startsWith(github.ref, 'refs/tags/v')
        uses: softprops/action-gh-release@3bb12739c298aeb8a4eeaf626c5b8d85266b0e65  # v2
        with:
          files: ${{ env.ASSET }}
      - name: Upload rolling latest (schedule / dispatch)
        if: ${{ !startsWith(github.ref, 'refs/tags/v') }}
        uses: actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02  # v4
        with:
          name: dmf-init-bundle-latest-${{ matrix.arch }}
          path: ${{ env.ASSET }}
          retention-days: 14
```

---

## File 3 — `.github/actionlint.yaml`
```yaml
# Allow the GitHub-hosted arm64 runner label used by build-bundle.yml so the
# pinned actionlint (1.7.7) in guard.yml does not flag it as unknown.
self-hosted-runner:
  labels:
    - ubuntu-24.04-arm
```

---

## PR
- TITLE: `ci: build dmf-init image (GHCR) and offline bundle on GitHub Actions`
- BODY:
```
Moves the dmf-init build off the LAN Forgejo runner onto GitHub Actions (public
repo → free hosted runners; GHCR via the built-in GITHUB_TOKEN).

- publish-image.yml — builds the dmf-init container image (amd64+arm64) and pushes
  to ghcr.io/dmfdeploy/dmf-init on v* tags + manual dispatch. The image fetches the
  component repos at runtime, so it updates per version, not on playbook changes.
- build-bundle.yml — builds the self-contained offline appliance bundle (the
  component repos baked in) per-arch on native runners: nightly + dispatch → rolling
  `latest` artifact; v* tag → tarball attached to the GitHub Release.
- .github/actionlint.yaml — declares the ubuntu-24.04-arm runner label for the guard.

All actions SHA-pinned per the repo's supply-chain posture.

One-time manual step after the first image build: flip the
ghcr.io/dmfdeploy/dmf-init package to Public in the org Packages UI.
```

## After merge (operator / claude — not part of the PR)
- First image build → flip the GHCR package **public** (one-time, UI).
- Once proven, retire the LAN `.forgejo/workflows/build-bundle.yml` path and turn
  **Actions off on the `dmf-init` LAN mirror** (closes the earlier runner-scope residual).
- Possible follow-ups: promote the rolling `latest` bundle to a stable-URL `latest`
  Release; pin component refs for fully-reproducible tagged bundles; add a disk-cleanup
  step if the bundle build approaches the runner's free disk.
