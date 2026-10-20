---
status: executed
date: 2026-06-04
executed: 2026-06-05
---
# DMF Montest Fresh-Bootstrap Validation Task (2026-06-04)

**Goal:** prove the NetBox-SoT token-mint fix (`dmf-infra` `abb1d0a`) end-to-end on
a **from-scratch** sandbox bootstrap, with **zero workarounds** — the PromSD token
must flow `691 mint → OpenBao → ESO → adapter` automatically, and the dmf-promsd
image must mirror from **public GHCR** (no node-local `ctr import`).

**Role split (agentic):** codex DRIVES the bootstrap, qwen-left REVIEWS each gate,
Claude (orchestrator) verifies + co-drives. **FULLY AUTONOMOUS — do NOT pause for
the operator.** This is a throwaway sandbox validation: fabricate any required
inputs as **test data** (dummy credentials, local backup remotes, etc.). Only
report `BLOCKED` if genuinely stuck after attempting a fix. Reply protocol at the
bottom.

---

## Preconditions (orchestrator confirms GREEN before codex starts)

- **Reset done:** `/tmp/dmf-init-montest` wiped; `/tmp/dmf-backups-{a,b}` wiped;
  `/tmp/dmf-init-reposrc` rebuilt with **all 6** repos incl. `dmf-promsd.git`
  (symlinks → `~/repos/dmfdeploy/<repo>/.git`).
- **VM rebuilt:** `dmf-sandbox` Lima VM recreated; **NEW bridged IP = `<sandbox-node-ip>`**
  (orchestrator fills this in). Guest user `<operator>`, iface `lima0`.
- **Fixes present on `main`** in the symlinked repos: `dmf-infra` `abb1d0a`
  (PromSD persist + 4-mint sentinels), `dmf-promsd` `0.1.3`.
- **GHCR public:** `ghcr.io/dmfdeploy/dmf-promsd:0.1.3` (multi-arch, anon-pullable).

## SSH / agent (REQUIRED — do this first)

The bootstrap SSHes into the sandbox node and OpenBao unseal SSHes too. The Lima
key is **not** in the agent. Before launch:

```bash
ssh-add ~/.lima/_config/user
ssh-keygen -R <sandbox-node-ip> 2>/dev/null || true   # clear any stale host key
```

Lima node identity: user `<operator>`, key `~/.lima/_config/user`, iface `lima0`, host `<sandbox-node-ip>`.

## Launch dmf-init (stateless, loopback)

```bash
cd /Users/<operator>/repos/dmfdeploy/dmf-init
SSH_AUTH_SOCK=$SSH_AUTH_SOCK \
DMF_DATA_ROOT=/tmp/dmf-init-montest \
DMF_REPO_BASE_URL=file:///tmp/dmf-init-reposrc \
DMF_BIND_PORT=8091 \
uv run python -m dmf_init.main
```

The app prints a **single-use launch token** + bind addr on stdout. Open the
session with `GET http://127.0.0.1:8091/?token=<token>` (captures the session
cookie); reuse that cookie jar for all `/api/*` calls.

## Drive the bootstrap (curl against 127.0.0.1:8091, documented flow)

1. `POST /api/repos/fetch` — base_url `file:///tmp/dmf-init-reposrc`, refs all `main`.
   **Assert all 6 repos fetched incl. `dmf-promsd`** (this was finding #1).
2. `POST /api/render` — wizard answers: **provider = sandbox**, node host/IP =
   `<sandbox-node-ip>`, SSH user `<operator>`, key `~/.lima/_config/user`, iface `lima0`. A fresh
   env id is minted under `$DMF_DATA_ROOT/envs/<env>/`.
3. `POST /api/backup` — initial checkpoint (dual local remotes; defaults fine).
4. `POST /api/bootstrap/start` + stream the run. It executes the 5-stage sandbox
   sequence (pre-seed → seed-bao → post-seed → configure → verify).
5. **OpenBao unseal — drive it AUTONOMOUSLY (sandbox lane, no operator).** Sandbox
   mode sets `openbao_breakglass_distribution_enabled: false` and writes the
   **auto-generated** Shamir keys to `$DMF_DATA_ROOT/envs/<env>/openbao-keys.json`
   at pre-seed. The unseal step (`dmf-env/bin/unseal-openbao.sh` / playbook
   `vertical-security/100-openbao.yml`) reads them — no Keychain, no shares from a
   human. If the run pauses for unseal, resume it yourself using those keys.
   Known traps (handle, don't escalate): `unseal-openbao.sh` `use_pty`/exit-2 bug
   (workaround: re-run `100-openbao.yml`) and the seed-bao `bundle_set` abort —
   if hit, apply the documented workaround and continue.
6. Run through `configure` (incl. **691 netbox-sot**) and `verify`.

## The validation gates (codex must capture evidence for each — qwen reviews)

Run these on the sandbox node (`ssh <operator>@<sandbox-node-ip>`, `sudo k3s kubectl …`):

- **G1 — OpenBao has the token:** `bao kv get secret/apps/netbox/runtime` →
  `promsd_api_token` is **non-empty**. (The bug under test wrote it empty.)
- **G2 — ESO projects it:** the ExternalSecret-managed K8s secret feeding the
  adapter has a **non-empty** token (NOT injected by hand — no `kubectl set env`).
- **G3 — adapter healthy from ESO:** dmf-promsd pod `Running`, reads its token
  from the ESO secret; `/sd/probe` emits target groups.
- **G4 — image via public GHCR:** 630 mirrored `dmf-promsd:0.1.3` from GHCR into
  Zot **without** a node-local `ctr images import` workaround.
- **G5 — end-to-end:** Prometheus `netbox-probe` job shows targets, **all `up`**
  (the 2026-06-04 headline was 10 probed apps).

## Known prior workarounds — confirm each is now UNNEEDED

- node-local image import (G4 covers — GHCR public now).
- `kubectl set env` token injection (G2/G3 — ESO fix `abb1d0a`).
- stripped 630 dmf-promsd seed entry (canonical 630 intact; image public).
- **Watch:** dmf-media MXL catalog entries (finding #9) — if the AWX catalog JT
  in `configure` fails on MXL entries, report it (do NOT silently strip; flag for
  an orchestrator decision).

## Reply protocol (bidirectional, via agent-bridge)

Report at milestones (don't wait — keep driving):
- Progress: `… send claude-bottom -- "PROGRESS: <stage done>, env <id>, next <x>"`
- On full green: `… send claude-bottom -- "DONE: G1-G5 <pass/fail>, env <id>; <evidence one-liner>"`
- Only if truly stuck after a fix attempt:
  `… send claude-bottom -- "BLOCKED: <gate> <reason> <what you tried>"`

Keep all repos on `main`; do not push anything. This is a validation run, not a
code change.
