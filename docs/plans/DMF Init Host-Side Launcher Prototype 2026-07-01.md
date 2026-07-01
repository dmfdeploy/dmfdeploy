---
status: executed
date: 2026-07-01
executed: 2026-07-01
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/154
---

# DMF Init Host-Side Launcher Prototype

## Context

First-run of dmf-init requires a stranger to paste a multi-flag `docker run …`
command and then extract a one-time token URL from verbose container logs. Since
the ADR-0044 tmpfs guard landed, omitting `--tmpfs` hard-fails with a raw Python
traceback — bouncing exactly the non-expert audience the localhost web UI targets.

This prototype adds a thin host-side launcher that hides Docker: one command
starts the container correctly, waits for readiness, extracts the launch token,
and opens the browser. It must work against the **already-published**
`ghcr.io/dmfdeploy/dmf-init:latest` with **no container change**.

Security invariants that must NOT be weakened (they are the model):

- Loopback-only publish `-p 127.0.0.1:<port>:8000` (never a routable interface).
- tmpfs data root `--tmpfs /tmp/dmf-init-data` (secrets stay in RAM; ADR-0044).
- The one-time launch token is surfaced, never bypassed.

Design was adversarially cross-checked with codex (agent-bridge); its P1/P2/P3
findings are folded into the mechanics below.

## Deliverable

New bash script **`dmf-init/bin/dmf-init`** — user-facing command name (no `.sh`,
a deliberate deviation from the `bin/*.sh` convention). Idiom copied from
`dmf-init/bin/build-bundle.sh`: `#!/usr/bin/env bash` + `set -euo pipefail`;
header-comment doubling as `--help` via `sed -n`; `BASH_SOURCE`-relative root;
`while/case` arg parser; preflight `docker info` check.

### Subcommands
- **`up`** — preflight → run detached, named + labelled container → wait for BOTH
  a launch line and host `/healthz` under one deadline → synthesize the host URL
  from the parsed token → best-effort open browser → always print the URL.
- **`down`** — `docker rm -f dmf-init` (container is NOT `--rm`).
- **`link`** — start `docker logs --tail 0 -f` **before** SIGHUP, read the next
  token line from that fresh stream, reopen browser; `trap`-kill the follower.
- **`logs`** — `docker logs -f dmf-init`.
- **`status`** — running? + current URL.

### `up` mechanics (hardened)
1. **Preflight:** docker present + `docker info`; `--port` numeric `1-65535`.
2. **Named + labelled, NOT `--rm`** so a startup crash doesn't self-delete before
   logs are read:
   `docker run -d --name dmf-init --label org.dmfdeploy.launcher=dmf-init
   -p 127.0.0.1:${host_port}:8000 --tmpfs /tmp/dmf-init-data [env] <image>`.
   Container keeps internal `DMF_BIND_PORT=8000` — only the host mapping changes.
   Reuse guard fails closed on an **unlabelled** `dmf-init` name; verifies
   loopback + tmpfs (via `docker inspect`) before reusing a labelled one.
3. **Single-deadline readiness:** loop until BOTH a token line is in logs AND host
   `/healthz` returns 200 (`curl -fsS`; `-kfsS` for `--tls`). Container exit →
   dump logs, fail.
4. **Parse the TOKEN, not the URL** (printed URL carries internal `:8000`, wrong
   under remap): anchored POSIX match
   `^open https?://[^[:space:]]*/\?token=([A-Za-z0-9_-]{32,})$`, **last** match
   (survives SIGHUP dup lines). Extraction wrapped as `if token=$(extract); then`
   to not trip `pipefail`; `docker logs` status checked; CLI stderr kept separate.
5. **Synthesize** `http(s)://127.0.0.1:${host_port}/?token=${token}` — open/print
   this, never the scraped URL.
6. **Browser open best-effort:** `open`/`xdg-open` (backgrounded) / optional WSL;
   never gates success; URL always echoed.

### Flags
`--image` (default `ghcr.io/dmfdeploy/dmf-init:latest`), `--tls`
(`-e DMF_TLS_ENABLED=true`), `--repo-base-url`, `--port` (default 8000),
`--dev-no-tmpfs` (**double-gated:** refused unless `DMF_INIT_DEV_NO_TMPFS=1` also
set; default path always keeps `--tmpfs`), `-h`. Note: no
`DMF_REQUIRE_TMPFS_DATA_ROOT` var exists — only `DMF_ALLOW_NON_TMPFS_DATA_ROOT`.

## Files
- **New:** `dmf-init/bin/dmf-init`.
- **New:** `dmf-init/test/launcher/` — unit tests with a fake `docker` on `PATH`.
- **Edit:** `dmf-init/README.md` §"Run it" — a "Quick start (launcher)" block
  above the raw `docker run` (which stays as the explicit/advanced path).

## Verification
- `bin/dmf-init up` on a Docker host → browser opens to the synthesized token URL;
  no manual `--tmpfs`, no traceback, no log-hunting. `link`/`status`/`down` work.
- `--tls up` → `https://…`. Docker stopped → actionable error, non-zero exit.
- `shellcheck bin/dmf-init` clean; `--help` renders.
- Launcher unit tests (fake docker) cover: healthz-before-token, missing token
  (timeout), SIGHUP dup lines (last-match), exited container, `--port` remap,
  TLS readiness, `--dev-no-tmpfs` refused without the env gate.

## Deferred (out of scope)
- Machine-readable launch output (`DMF_LAUNCH_JSON`/sentinel) to replace
  log-scraping — the robust fast-follow (needs container rebuild + republish).
- `curl | sh` / Homebrew distribution; native menubar wrapper.
