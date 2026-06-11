---
status: executed
date: 2026-06-02
---
# DMF Init Phase 1 Implementation Plan 2026-06-02

Implementation-level slicing + decisions for **Phase 1** of the dmf-init
container. Parent/authoritative spec: [`DMF Init Bootstrap Container Plan 2026-06-02`](DMF%20Init%20Bootstrap%20Container%20Plan%202026-06-02.md).
Phase 0 (`init-wizard.sh --non-interactive`) is **done** (dmf-env
`feat/wizard-non-interactive`, commit `2a75774`).

All work lands in `dmf-init/` on branch `feat/phase1-foundation`. Orchestrated by
claude-bottom, lifted by codex, reviewed before commit. Nothing committed until
verified.

## Stack (mirror dmf-cms)

- **Backend:** `src/dmf_init/` Python package, root `pyproject.toml`, FastAPI +
  uvicorn, `requires-python >=3.12`, ruff + pytest. (dmf-cms uses `src/dmf_cms/`
  + the same toolchain.)
- **Frontend:** `frontend/` — React 19 + Vite 5 + TypeScript 5 + Tailwind,
  builds static assets into `src/dmf_init/static/app` (dmf-cms pattern).
- **Container:** single root multi-stage `Dockerfile` (node frontend-builder →
  python runtime), `pip install .`, **but** with two dmf-init-specific layers
  the console doesn't need (tool layer + repo layer, below).

## Key decisions

### D1 — Thin control container: runtime-pull repos at a selected ref; NOTHING baked (operator decision 2026-06-02 → ADR-0036)
**Decision (reverses the earlier "bake the repo layer" stance):** dmf-init is a
**thin control-plane container**. The image bakes **only** the tool layer +
the FastAPI/React app. It bakes **no repos and no app images.**

- **Playbooks/scripts (dmf-env + dmf-infra + dmf-runbooks):** `git clone`d **at
  runtime, at an operator-selected ref**, into the tmpfs scratch — never baked.
  Now: clone from the **LAN Forgejo at a branch/SHA** with **operator-supplied
  creds entered at runtime** (held in tmpfs/process memory, never baked, never
  logged). Later: clone the **public repos at a release tag**. The selected
  **ref + resolved SHA per repo is recorded in the backup `MANIFEST.json`** for
  provenance — that is how "versioned to match releases" is satisfied (by the ref
  the operator deploys, not by the image tag).
- **App images (authentik/netbox/awx/forgejo/zot/grafana/dmf-cms/awx-ee/…):**
  **NOT baked.** They are pulled from **GHCR + upstream at bootstrap** and
  mirrored into the cluster's Zot by `630-zot-seed-platform.yml` (the existing
  model). The init container only drives the playbooks that do this.

**Why thin (not a "huge all-images" container):** the cluster pulls images at
bootstrap (it is not air-gapped); baking GB-scale images would duplicate
GHCR+Zot, version-lock the image, and only pay off for a true air-gap — which is
a **separate future profile** (a portable image bundle alongside the backup),
explicitly **out of Phase 1 scope**.

**This dissolves the private-repo problem:** the image bakes no repos, so it is
**genuinely public-safe / publicly distributable from day 1**; the private
dmf-env never enters the image. No build-time staging, no `stage-repos.sh`, no
repo-layer COPY, no IP-scrub, no operator-internal classification.

**Prerequisite for the fully-public *runtime* story (tracked, not blocking):** a
clean generic **public dmf-env** + **release tags** on the public repos (ties
into public-publish-readiness). Until then, runtime-clone targets the private LAN
Forgejo with operator-supplied creds — which is fine because creds are
runtime-only and nothing private is ever baked.

### D2 — Loopback + single-use launch token
Web server binds **127.0.0.1 only**. A single-use launch token (short TTL, e.g.
5 min) is printed to container stdout; operator opens
`http://127.0.0.1:PORT/?token=…`. No OIDC (Day-0, pre-cluster — chicken/egg).
**The token must NOT leak into logs:** uvicorn's default access log records the
full request line incl. query params. On first valid presentation the backend
exchanges it for a short-lived session cookie/header and **redirects to a
token-free URL**; the access logger is configured to scrub the `token` query
param (and never log it). *(qwen P1)*

### D3 — Stateless tmpfs + secret hygiene
`DMF_DATA_ROOT` → a tmpfs mount; age key, bundle, inventory, openbao-keys, TF
state live there for the session only. The tmpfs is **size-bounded explicitly**
(`--tmpfs <path>:size=…` / documented `docker run`) — the 64 MB default cannot
hold TF state + the bundle + tool scratch. *(qwen P2)*
Secrets never logged (structured logging + redaction); **the passphrase endpoint
and any secret-bearing POST bodies are excluded from request-body logging**, and
the passphrase is held in process memory only, re-prompted per backup/restore.
*(qwen P2)* Documented expectation: operator passphrase is password-manager
generated, **≥20 chars** (age `--passphrase` scrypt work factor is the default).
*(qwen P3)*

## Slicing (incremental, verify between each)

### 1a.1 — Thin container + backend foundation  ← FIRST DISPATCH
**No repo layer. No baked repos.** (Per D1/ADR-0036.)
- `src/dmf_init/` FastAPI app: loopback bind, single-use launch-token middleware
  (TTL + one-shot → session cookie → redirect to token-free URL), settings (env:
  `DMF_DATA_ROOT`, port, token TTL), structured logging with secret redaction,
  `/healthz`.
- Minimal `frontend/` (Vite/React/TS/Tailwind) landing page: **Create new** /
  **Manage** (non-functional placeholders), built into `src/dmf_init/static/app`.
- Multi-stage `Dockerfile`: **tool layer** (opentofu, ansible, sops, age, rclone,
  kubectl, jq, openssh-client, **git**, python3) + **frontend-builder** + the
  FastAPI app. **That's the whole image** — no repo COPY, no `stage-repos.sh`, no
  manifest LABEL.
- `pyproject.toml`, `.gitignore`, tests (pytest: token one-shot + TTL expiry +
  redaction + access-log token-scrub), `VERSION` bump.
- **Keep dmf-init's `.gitleaks.toml` intact** — including the
  `dmf-private-network-literal` rule (the repo is public-safe; that guard stays).
- Update `.forgejo/workflows/ci.yml`: python (ruff+pytest), frontend (build),
  docker-build-smoke — **CI == acceptance suite.** *(qwen P1)*
- **Acceptance:**
  - image builds (**target arm64**); `npm ci` (not `npm install`). *(qwen P2/P3)*
  - container runs; `/healthz` 200; bound to **127.0.0.1** only.
  - valid token admits **once** then rejected; expired token rejected; token
    never appears in access logs. *(qwen P1)*
  - the baked tool layer is present (`git`, `ansible`, `sops`, `age`, `rclone`,
    `tofu`, `kubectl`, `jq` resolve in-container).
  - pytest green; ruff clean; CI green; **no secret/IP/identity in tracked files**
    (dmf-init `.gitleaks.toml` rules — incl. the IP rule — pass).

### 1a.2 — Runtime repo-fetch + Create-new render + dual-remote passphrase backup
**Sub-sliced for review isolation** (the crypto is highest-risk):
- **1a.2-i** = runtime repo-fetch + session-enforcement (low crypto risk).
- **1a.2-ii** = render + dual-remote passphrase backup (the **qwen adversarial
  crypto review** gate lands here, before commit).

**Sandbox repo source = the LAN Forgejo** (`http://<lan-ip>/<operator>/<repo>.git`,
operator decision 2026-06-02): operator supplies base URL (default the LAN
Forgejo) + per-repo ref + creds **at runtime**.

- **Runtime repo-fetch (1a.2-i, the D1 mechanism):** backend clones **dmf-env +
  dmf-infra + dmf-runbooks at an operator-selected ref** into the tmpfs scratch
  (`$DMF_DATA_ROOT/repos/<name>`). Default refs: dmf-env =
  `feat/wizard-non-interactive` (until merged, then `main`); dmf-infra +
  dmf-runbooks = `main`. Creds supplied at runtime, held in process memory only,
  **never baked, never logged, and never persisted into the clone's `.git/config`
  remote URL** (clone the clean URL + supply creds via a one-shot inline
  credential helper / `GIT_ASKPASS` for the command only). Record each repo's
  **ref + resolved SHA** (→ backup `MANIFEST.json`).
  Acceptance: after fetch, `repos/dmf-env/bin/init-wizard.sh --help` runs AND the
  fetched script contains `--non-interactive`; `.git/config` carries no creds.
- **Session-enforcement (1a.2-i):** add a `require_session` dependency; the new
  protected endpoints (fetch/render/backup) reject a session-less request
  (401/403). Landing page + `/healthz` stay open. (Closes the 1a.1
  token-is-exchange-only gap.)
- **Render (1a.2-ii):** generate the env's **age keypair into tmpfs**
  (`age-keygen -o $SOPS_AGE_KEY_FILE` — init-wizard's `check_age_key` requires it
  to pre-exist) → collect inputs → write **answers-file** (inputs-only) → invoke
  the **fetched** `repos/dmf-env/bin/init-wizard.sh --non-interactive` (render
  into tmpfs). The generated age key is what the backup must capture.
- **Backup module:** tar(env dir + age key + answers-file + `MANIFEST.json`)
  → `age --passphrase` (scrypt) → push to **two rclone remotes** = **checkpoint
  #1**.
  - **MANIFEST sha256 contract** *(qwen P1/P2 — chicken/egg):* the `sha256` in
    `MANIFEST.json` covers the **inner env-dir payload** (a deterministic tar of
    the env dir, computed before wrapping), NOT the outer `*.tar.age` that
    contains the manifest. Restore verifies the inner payload hash after
    unwrap. (Outer-tarball integrity, if wanted, is a sidecar `.sha256`, not a
    field inside the thing it hashes.)
  - **Write-validate proves OVERWRITE, not just create** *(qwen P1):* `rclone
    copy` a zero-byte probe to the **same destination name twice** + delete —
    catches append-only / read-only bucket policies that pass a bare `touch`.
  - rclone config lives on a **tmpfs path passed via `--config`** (never the host
    `~/.config/rclone`) *(qwen P3)*.
- Frontend Create-new form (sandbox sections), remote config, passphrase (x2).
- **Acceptance (hermetic, no cluster):** render → backup round-trip to **two
  local rclone remotes** → pull → unwrap → inner-payload sha256 verified →
  `bootstrap-secrets.sh doctor` passes; bundle key set intact; overwrite-validate
  proven. **qwen adversarial review of the backup/crypto module before commit.**

### 1b — Full orchestration with streamed logs + UI pause-points
pre-seed → checkpoint #2 (capture OpenBao unseal key) → unseal → seed-bao →
post-seed → configure → verify, streamed; human-in-the-loop UI steps (CA cert
download, hosts mapping, passkey enrollment); checkpoint #3 post-verify.

### 1c — Manage mode
restore (age-key-export-before-doctor ordering), read-verify-before-lock, remote
lock, actions (re-run playbook, upgrade-in-place, rotate, teardown), re-backup.

## Risks / notes
- Runtime secret exposure is non-zero (tofu/ansible need plaintext keys on disk
  during a run) — mitigated by tmpfs + no-log; persistence is zero.
- Backup crypto (age --passphrase) + restore ordering + remote lock are the
  high-risk areas → warrant qwen adversarial review at 1a.2 / 1c.
- Version coupling lives in the **runtime-selected ref** (recorded in the backup
  `MANIFEST.json`), not the image tag — the thin image is release-agnostic; the
  operator picks which release to deploy at run.
- **Runtime repo-source creds** (private LAN Forgejo, until public repos exist):
  operator-supplied at run, tmpfs/process-memory only, never baked, never logged.
- **Air-gap is out of scope** — app images are pulled from GHCR+upstream at
  bootstrap (mirrored into Zot by 630). A portable image bundle is a separate
  future profile, not Phase 1.
- **Tool-layer version pinning** *(qwen P2)*: experiment-phase posture =
  **floating versions + a documented known-good set** in the Dockerfile (not
  per-tool pins yet). Revisit (lockfile/pins) if a rebuild drifts and breaks
  idempotency.
- **Image size budget** *(qwen P3)*: tool layer + 3 repos + Python + Node can
  exceed ~2 GB. Multi-stage slimming is a **1b** concern, not 1a.
- **age-key-in-backup is circular but correct** *(qwen P3)*: passphrase → unwrap
  → extract age key → decrypt sops bundle. The full restore chain is exercised
  in **1c**; 1a.2 tests unwrap + inner-payload hash + doctor only.

## Review trail
- Parent spec qwen-left-reviewed (2026-06-02, 10 fixes folded).
- **This implementation plan qwen-left-reviewed 2026-06-02** — verdict
  CHANGES-NEEDED (5 P1 / 9 P2 / 3 P3, slicing sound); all P1s + the substantive
  P2/P3s folded above (build-helper assertions + gitleaks + provenance LABEL;
  token-log scrub; tmpfs size bound; passphrase no-log + entropy; repo-layer
  reachability probe; overwrite-validate; MANIFEST sha256 contract; CI==acceptance;
  arm64 + npm ci; version-pinning posture).
