# DMF dmf-init Download-Appliance + Image-Slimming Handoff

**Date:** 2026-06-09 (work done 2026-06-08 evening)
**Status:** ⚠️ **All on `dmf-init` `main`, NOT pushed** — 8 commits ahead of `origin` (the LAN Forgejo). Umbrella `CLAUDE.md` edit **staged but not committed**. The appliance **boots clean and serves** (verified on a from-scratch image); the **clean-host bootstrap test is the next step** and the only thing that fully exercises the curated Ansible collections.
**Build model:** orchestrated — Claude drove + verified; **qwen-left** lifted the big code change; **codex** did 4 review passes. Later UX/appliance/slimming work done directly by Claude (interactive debugging with the operator).

## What this was

A pivot of **dmf-init** from "localhost container that uploads backups to two rclone remotes" into a **downloadable, self-contained appliance** a new user runs with one command and browses in a web browser. Driven by operator asks across the session.

## Shipped (all on `dmf-init` `main`, unpushed)

1. **`9e9815b` — the core change** (qwen-lifted, codex-reviewed): HTTPS/secure-context (self-signed TLS), **backups become browser downloads** (dual-remote rclone model removed; session-gated path-safe `no-store` artifact endpoint; restore via file upload), **repo-source panel hidden** (`ensure_runtime_repos` skips fetch when all 6 repos present, records dirty provenance), **manage lock + drift removed** (were remote-backed; replaced by an in-process `active_runs` env-keyed mutex), and **Change 4 CA cert** (shared `CaInstall` with Windows `certutil`/macOS/Debian+Fedora/Firefox steps on both the mid-run pause and a retryable post-verify card via `GET /api/ca-cert/{env_id}`).
2. **`98a4ea0` — docs:** README/CLAUDE reworded off the dual-remote model.
3. **`b3953df` — auth TTLs:** session 5min→**12h** (the old cookie expired mid-bootstrap, locking the operator out since the launch token is single-use), launch link 5min→30min, styled expired/used/invalid pages instead of bare plaintext.
4. **`d60f5e6` — UI fix:** `readError` read the body twice (`.json()` then `.text()`) → "body stream already read" masked the real error; now reads once.
5. **`630dee2` — appliance:** **HTTP by default** (`http://localhost` is a secure context, no cert warning; HTTPS opt-in via `DMF_TLS_ENABLED=true`), container binds `0.0.0.0` so `docker run -p 127.0.0.1:8000:8000` needs no flags, browsable launch URL printed, **`bin/build-bundle.sh`** bakes the 6 repos + exports a `docker save` tarball.
6. **`9895909` — image slim (−680 MB):** `ansible` (full meta-pkg, 436 MB of unused collections) → **`ansible-core` + 3 curated collections** (`kubernetes.core`, `community.general`, `ansible.posix` — the only ones the bootstrap calls as modules; netbox/docker/netcommon are in-cluster AWX EE concerns), **dropped dead `rclone`** (apt + 58 MB binary, unused since dual-remote removal), `--no-cache-dir`. Kept `tofu` (cloud lanes).
7. **`2c6e117` — dep fix:** declared **`python-multipart`** (+ `pydantic`). The manage-restore `UploadFile` route needs it; it was undeclared, so a clean container crashed at startup ("Form data requires python-multipart") — masked locally because `.venv` had it.

## Bugs caught by verification (not by green recaps)

- qwen's first two DONE reports **falsely claimed Change 4 shipped** — it was absent (wrong payload, zero Windows instructions). Caught by codex + Claude re-verifying against code.
- codex found a real **path-traversal** (`env_id` from an uploaded backup → `rmtree`/`copytree`) → `validate_env_id` at every boundary; and an **active-runs leak** class → broad-except cleanup + atomic reserve.
- **`python-multipart`** missing — caught only by running the **from-scratch image** (40 unit tests passed because `.venv` had it). The clean-build smoke is the gate.

## Appliance facts

- Image **1.09 GB**, tarball **`dmf-init/dmf-init-bundle-0.1.2.tar.gz` ≈ 211 MB gz** (gitignored). Clean host: `docker load -i …` then `docker run --rm -p 127.0.0.1:8000:8000 dmf-init:bundle` → open the printed `http://localhost:8000/?token=…`.
- Baked repos: lean copy (rsync excludes `.terraform`/`node_modules`/`.venv`/`dist`) — the scary 2.3 GB in `dmf-env` was darwin `.terraform` providers (re-downloaded by `tofu init`, wrong arch). Real repo content ≈ 45 MB.

## Next steps

1. **Clean-host test** (operator's next action): copy the tarball, `docker load` + `docker run`, browse, **Create new**, then **bootstrap against a node** — the curated 3-collection set's real validation. A missing module = legible "couldn't resolve" error → one line in `dmf-init/requirements-collections.yml` + rebuild. Any other missing Python dep = one line in `pyproject.toml` (same class as the multipart fix).
2. **Push** when satisfied: `dmf-init` 8 commits → the LAN Forgejo `origin` (the public-GitHub orphan-rebase dance does NOT apply to the LAN Forgejo). Commit + push the umbrella `CLAUDE.md` edit too.

## Gotchas

- **colima must be running** to build/run on the Mac (`colima start`); it was stopped at end of session. A clean Linux host needs no colima (Docker is a system service).
- The **bundle embeds non-public repo source** — pre-release only; keep the tarball offline (no public registry) until the repos are published.
- **Loopback safety** is the `-p 127.0.0.1:…` publish, not the in-container bind (now `0.0.0.0`) — never publish to a non-loopback host interface.

## Memory

`feedback_verify_qwen_done_claims` (re-verify qwen DONE reports against code). Update `project_dmf_init_*` if the clean-host test changes the picture.
