# DMF dmf-init LAN CI Auto-Build Pipeline Handoff

**Date:** 2026-06-09
**Status:** ✅ **Self-hosted Forgejo Actions pipeline LIVE and proven end-to-end** — auto-builds the dmf-init appliance bundle from the latest repo content on the LAN Forgejo + a dedicated Lima VM. **One open item:** persist the built tarball (currently ephemeral). Builds on the companion handoff `DMF dmf-init Download-Appliance + Image-Slimming Handoff 2026-06-09.md` (the appliance/downloads/slimming work — all pushed).

## TL;DR for a freshly cleared agent

A `workflow_dispatch` or `v*` tag triggers a self-hosted runner that clones the 6 runtime repos fresh from the LAN Forgejo and bakes the self-contained `dmf-init:bundle` image. **Proven:** run #16 = success (~2 min), the CI-built image boots (`/healthz` ok, prints `open http://localhost:8000/?token=…`) and carries a baked provenance manifest of the exact repo SHAs. The **only remaining work** is uploading the built `dmf-init-bundle-*.tar.gz` somewhere durable — right now it dies with the job's `/tmp`.

## Topology (where everything lives)

- **LAN Forgejo** — resolve the host yourself (no literal in tracked docs): the dmf-init git remote is an SSH alias → `git -C "$DMFDEPLOY_UMBRELLA/dmf-init" remote get-url origin`, then `ssh -G <alias>` for the hostname; HTTP API is `http://<host>/api/v1`. Version **14.0.3** (Gitea 1.22 compat). Actions enabled; dmf-init repo `has_actions=true`. API admin needs operator Forgejo creds (ask the operator — the password used during setup should be rotated).
- **Builder VM `dmf-builder`** (Lima, on the Mac) — Debian-12 **arm64**, 4cpu/4G/50G, its **own dockerd** (docker.io 20.10). Operate via `limactl shell dmf-builder …`. **Left RUNNING** for on-demand builds. Separate from colima (colima is stopped; the builder does NOT depend on it).
- **Runner** — `forgejo-runner` **v12.10.2** at `/usr/local/bin/forgejo-runner`, registered to the LAN Forgejo, **host-executor** label `dmf-builder`, running as **root** via systemd unit `forgejo-runner.service` (WorkingDirectory `/etc/forgejo-runner`, `.runner` config there). Check: `limactl shell dmf-builder sudo systemctl status forgejo-runner` and `… journalctl -u forgejo-runner`.
- **CI secret** — dmf-init repo Actions secret **`DMF_REPO_TOKEN`** = a `read:repository` Forgejo token (named `dmf-init-ci-repo-read-*`), used by the workflow to clone the 5 *other* private repos. (The throwaway debug tokens minted during setup were revoked.)

## Code (all on dmf-init `main`, pushed)

- **`bin/build-bundle.sh`** — builds + exports the bundle. Modes:
  - default **fresh** (recommended/CI): `--ref REF` (default `main`) shallow-clones the 6 repos from `--repo-base-url URL`; `DMF_REPO_TOKEN` env injected for private http clones. Clean clones carry no `.terraform`/`node_modules` cruft.
  - `--local`: rsync the local sibling working trees (dev; bakes in-flight uncommitted work).
  - Bakes `build-provenance.json` (image/version/ref/repo SHAs) into the image at `/tmp/dmf-init-data/provenance/build.json`.
  - **Forces `DOCKER_BUILDKIT=1`** (see gotcha).
- **`.forgejo/workflows/build-bundle.yml`** — triggers `workflow_dispatch` (input `ref`, default main) + `push: tags: ['v*']`; `runs-on: dmf-builder`. Derives the instance URL from `${{ github.server_url }}` + `${{ github.repository_owner }}` (**no hardcoded host** → runs unchanged on the future GitHub-hosted setup). Clones dmf-init at the ref, runs build-bundle.sh, prints artifact + provenance. **No artifact-upload step yet.**
- Relevant commits: `4b90d0b` (script fresh-mode + workflow), `3ea8780` (`DOCKER_BUILDKIT=1` fix).

## How to operate

- **Trigger:** `POST <api>/repos/<operator>/dmf-init/actions/workflows/build-bundle.yml/dispatches` body `{"ref":"main","inputs":{"ref":"main"}}` (operator creds/token), or push a `v*` tag.
- **Watch status:** poll `<api>/repos/<operator>/dmf-init/actions/tasks` → `workflow_runs[0].status` (`waiting`/`running`/`success`/`failure`). The API job-log endpoint returned empty; read logs in the web UI run page `…/actions/runs/<n>`.
- **Inspect the build:** `limactl shell dmf-builder sudo docker images dmf-init` (the `dmf-init:bundle` image persists in the VM); provenance: `… sudo docker run --rm --entrypoint cat dmf-init:bundle /tmp/dmf-init-data/provenance/build.json`.

## OPEN ITEM — the next task

**Persist the artifact.** The build produces a valid `dmf-init-bundle-<version>.tar.gz` but it lives in the job's ephemeral `/tmp`. Add an upload step to the workflow. Options (operator to pick; both is fine):
1. **Release asset on `v*` tag** — create/get the tag's Forgejo Release, upload the tarball (Actions auto token has release-write). Mirrors the eventual GitHub plan. Test with a throwaway tag.
2. **Forgejo generic package on every build** — `PUT <api>/packages/<operator>/generic/dmf-init-bundle/<version>/<file>` (needs package-write). Rolling "latest", no tag required.
Then run one build and confirm the artifact actually lands.

## Gotchas

- **BuildKit required.** The Dockerfile uses `FROM --platform=$BUILDPLATFORM`; the classic builder (docker.io 20.10 default in the VM) leaves it empty and fails at step 1. `build-bundle.sh` now exports `DOCKER_BUILDKIT=1`. colima had BuildKit on by default, which masked this locally — this was the first CI failure, caught by the clean runner.
- **gitleaks** (umbrella pre-commit) blocks the LAN IP literal (`dmf-private-network-literal`) and the operator identity (`dmf-operator-identity`). Keep IPs/usernames out of tracked files — resolve via `git remote`/`ssh -G`. That's why the workflow uses `github.server_url`, and why this doc uses `<operator>`/pointers.
- **Eventual GitHub setup:** hosted `ubuntu-24.04-arm` runner, tag-triggered, artifact → Release/GHCR. **Do NOT self-host on the public GitHub repos** (fork-PR arbitrary-code-execution risk). Self-hosted is fine *here* only because the LAN Forgejo is private/trusted. The workflow is already host-agnostic, so it ports over with just a `runs-on:` change.
- **Resources:** Mac is 16 GB; `dmf-sandbox` (10 GiB) + `dmf-builder` (4 GiB) both running is tight — stop one under memory pressure. To pause the builder: `limactl stop dmf-builder` (runner resumes on next `limactl start`).

## Memory

See `project_dmf_init_lan_ci` (the persistent CI infra facts) and `feedback_verify_qwen_done_claims`.
