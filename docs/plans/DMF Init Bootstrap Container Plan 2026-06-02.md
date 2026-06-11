---
status: executed
date: 2026-06-02
executed: 2026-06-08
---
# DMF Init/Bootstrap Container Plan 2026-06-02

Day-0 self-contained, **stateless** container that puts a friendly web UI on the
existing `dmf-env` env-creation + bootstrap toolchain, and adds a
passphrase-wrapped, dual-remote backup/restore lifecycle so the operator can
commission a cluster and then **delete the container with nothing left behind**.

## Decisions locked (operator, 2026-06-02)

1. **Stateless container.** No durable host volume; all env state lives in a
   tmpfs scratch `DMF_DATA_ROOT`. After commissioning, the two encrypted
   backups + the passphrase are the only durable artifacts; `docker rm` is safe.
2. **Passphrase wraps the age key.** The age private key rides *inside* the
   backup; the backup is encrypted by an operator **passphrase** (age scrypt).
   Passphrase = the single human-held secret (password manager / memorized).
   Layering: `passphrase → unlock backup → recover age key → age key decrypts
   inner sops bundle`.
3. **Two backups = redundancy/durability, not confidentiality.** Confidentiality
   boundary is the passphrase, held in a *different trust domain* than the two
   backup remotes. Operator is educated on this explicitly.
4. **Manual paste** for the passphrase; no native 1Password/Bitwarden API in v1.
5. **Hardware key (YubiKey/FIDO2) recipient** = roadmap, not v1.
6. **Sandbox profile first** (ADR-0031 single ARM64 node). Its OpenBao is
   Tier-3 Shamir 1/1 with the unseal key already operator-local under
   `~/.dmfdeploy/envs/<env>/openbao-keys` — so folding it into the backup is
   natural and consistent. Cloud (Hetzner, ADR-0009 distributed 5-share Shamir)
   is Phase 2 and forces a separate "Shamir-collapse vs stay-distributed"
   decision the sandbox sidesteps.
7. **Full orchestration** in v1: container drives render → backup → pre-seed →
   unseal/seed-bao → post-seed → configure → verify, with the human-in-the-loop
   steps (CA trust, hosts mapping, passkey enrollment) surfaced as explicit UI
   steps instead of terminal prompts.
8. **Wrap the bash, don't reimplement.** Add `--non-interactive` (answers-file)
   mode to `init-wizard.sh`; the answers-file schema is the shared contract for
   both the web UI and the still-first-class interactive CLI.

## Architecture

### Container image (arm64; multi-arch nice-to-have)
- **Tool layer (static):** opentofu, ansible, sops, age, rclone, kubectl, jq,
  openssh-client, git, python3 + uvicorn/FastAPI, node-built React static assets.
- **Repo layer (pinned):** baked checkouts of `dmf-env` + `dmf-infra`
  (+ `dmf-runbooks` for catalog post-seed) at a **release tag**. The image tag
  == platform release; version coupling is explicit and documented.
- **Public-repo-safe:** no secrets, no env identity baked.

### Runtime (stateless)
- `DMF_DATA_ROOT` → a **tmpfs** mount (RAM-backed; never touches host disk).
  age key, bundle, inventory, openbao-keys, TF state all live here for the
  session only.
- Web server binds **127.0.0.1 only**; a **single-use launch token** (with a
  short TTL, e.g. 5 min — qwen NICE #8) is printed to container stdout; operator
  opens `http://127.0.0.1:PORT/?token=…`.
- Secrets never logged (structured logging + redaction); passphrase held in
  process memory for the session, re-prompted per backup push / per restore.

### Web UI (mirror dmf-cms stack: React + FastAPI)
Day-0 tool runs *before* there is a cluster or Authentik, so it **cannot** use
OIDC for its own auth (chicken/egg) — hence localhost + single-use token.
Landing screen: **Create new** / **Manage**.

## Answers-file contract (the shared CLI/web contract)
`--non-interactive` is **inputs-only**, not a full state dump:
- The answers-file carries **operator inputs only** (identity, label, node IP/
  user/iface, SSH-key material, posture, remotes). It does **not** carry the
  10+ wizard-generated secrets (passwords, tokens, env_id, per-env SSH keypair)
  — those stay **wizard-internal and random**, generated once per env.
- Therefore the web and CLI front-ends are **not** expected to produce
  byte-identical bundles from the same answers (the random secrets differ every
  run). The **backup is the single source of truth for the generated values**,
  since each env is rendered exactly once. Parity testing (Phase 0) asserts
  **structural equivalence** (same keys present, valid sops, valid age, schema)
  — never byte-equality of secrets.  *(qwen MUST-FIX #2)*
- **SSH-privkey base64 encoding ownership:** the wizard's bundle stores SSH
  privkeys base64-encoded (the cluster-breaker bug it just fixed). Decision: the
  **wizard owns encoding** — the answers-file/web UI passes the **raw** key (or
  "generate"), and non-interactive mode base64-encodes internally, identical to
  interactive. The web UI never pre-encodes.  *(qwen SHOULD #6)*

## Backup format
- Tar of the env dir (`bundle.sops.yaml`, `.sops.yaml`, `manifest.yaml`,
  `inventory/`, `ssh/`, `openbao-keys`, `terraform-state/`) **+ the age private
  key** **+ the answers-file that produced it** + a small `MANIFEST.json`
  (env_id, profile, schema version, created-at, sha256). Bundling the
  answers-file enables CLI-replay / restore-to-a-fresh-container without
  reverse-engineering inputs from the bundle.  *(qwen NICE #9)*
- Wrapped with `age --passphrase` (scrypt) → `dmf-backup-<env_id>-<ts>.tar.age`.
- Pushed to **two rclone remotes** (rclone = one tool, any backend: B2, S3,
  SFTP, WebDAV, Google Drive, local mount…). **Write-validated** before commit
  with a zero-byte `rclone touch` + `delete` (proves write perm, not just `lsd`
  list perm).  *(qwen NICE #10)*
- Integrity: sha256 in MANIFEST, verified on restore.
- **Checkpoints capture durable state as it comes into existence** (see flow):
  a render-only backup can decrypt the bundle but **cannot unseal OpenBao**, so
  the unseal key must be captured the moment pre-seed creates it.

## Create-new flow
*(Sandbox has no `tofu apply`; pre-seed provisions k3s on the existing node.
Checkpoint placement reflects that — qwen MUST-FIX #1.)*
1. Collect inputs (web forms mirroring the wizard's sandbox sections): operator
   identity; sandbox subdomain label; node IP / SSH user / iface; **operator
   passphrase** (entered twice). **SSH private key** is pasted OR uploaded via a
   file-upload endpoint that writes it to a **tmpfs `0600`** path before render
   (the container shares no filesystem with the host).  *(qwen SHOULD #7)*
2. Configure the **two backup remotes** (rclone): pick type + creds,
   write-validate (touch+delete).
3. Backend writes an **answers-file** (inputs-only) → `init-wizard.sh
   --non-interactive <answers>` renders bundle/manifest/inventory/sops/keys into
   tmpfs.
4. **Backup checkpoint #1 (render-complete):** wrap + push to both remotes — the
   bundle (incl. age key) is safe before anything touches the node.
5. Orchestrate bootstrap stages with **live streamed logs**:
   - `run-playbook … bootstrap-sandbox-provision-pre-seed.yml` (deploys +
     initializes OpenBao → **the Tier-3 unseal key now exists** under
     `openbao-keys`).
   - **Backup checkpoint #2 (post-pre-seed):** push both remotes **immediately**
     so the unseal key is durable before any later stage can fail. Without this,
     a failed post-seed leaves a backup that decrypts the bundle but can't
     unseal OpenBao to re-run seed-bao.  *(qwen MUST-FIX #1)*
   - unseal (sandbox Tier-3 self-recovering Shamir 1/1) → `bootstrap-secrets.sh
     seed-bao`
   - `bootstrap-sandbox-provision-post-seed.yml`
   - `bootstrap-sandbox-configure.yml`
   - `bootstrap-sandbox-verify.yml`
   - **UI human-in-the-loop steps:** a **"download CA cert" endpoint** that
     serves the in-tmpfs local-CA cert to the operator's browser + per-OS trust
     instructions (the cert lives inside the container, not on the host); show
     `*.<domain>` → **node-IP** hosts mapping (node IP, never a container IP);
     passkey enrollment (first via enrollment URL, second via console
     self-service). **Sandbox has no ntfy topic** (ADR-0031) — the UI must not
     surface a dead ntfy link.  *(qwen SHOULD #5)*
6. **Backup checkpoint #3 (post-verify):** final state → push both remotes.
7. **"Safe to delete this container" screen:** names the two remote locations +
   reminds that the passphrase (stored separately) is required to ever manage
   or recover.

## Manage flow
1. Prompt for a backup source (rclone remote) + **passphrase**.
2. Pull tarball → unwrap → reconstitute env dir in tmpfs. **Restore ordering is
   explicit** (qwen MUST-FIX #3): extract the age key to a tmpfs path, **`export
   SOPS_AGE_KEY_FILE=<that path>`**, *then* `bootstrap-secrets.sh doctor` —
   `doctor` cannot verify the bundle until the key it needs is in place.
3. **Read-verify-before-lock** (qwen MUST-FIX #4): pull the singleton state
   (bundle / openbao-keys / — Phase 2 — TF state) into tmpfs, verify no drift vs
   remote, **then** acquire the **remote lock object**, mutate, write back,
   release. The lock serializes access; the pre-lock read-verify prevents a
   stale-state overwrite when two managers interleave.
4. Offer actions, each shelling to the existing `bin/` script with streamed
   logs: re-run a playbook, `upgrade-in-place.sh`, rotate secrets, teardown
   (`remove-env.sh`), re-backup.
5. On any state change, re-backup to **both** remotes; release lock.

## Phasing
- **Phase 0 (dmf-env):** `--non-interactive` answers mode for `init-wizard.sh`
  + answers-file schema; interactive CLI stays first-class (shared validation).
  Fake-data parity test vs interactive.
- **Phase 1 (new container repo, sandbox):**
  - 1a: image (tools + pinned repos) + FastAPI/React skeleton, localhost+token,
    Create-new **render + dual-remote passphrase backup** (no apply yet).
  - 1b: full orchestration stages with streamed logs + UI pause-points.
  - 1c: Manage mode (restore, lock, actions, re-backup).
- **Phase 2 (cloud / Hetzner):** add provider creds + B2 + TF state to backup;
  decide Shamir-collapse-into-passphrase (lab) vs stay-distributed (container
  can't be fully stateless for cloud). New ADR.
- **Phase 3 (roadmap):** hardware-key (age-plugin-yubikey / FIDO2) recipient;
  native `op`/`bw` passphrase retrieval; multi-recipient backups.

## ADRs to write
- **ADR-00xx: Day-0 stateless init/bootstrap container** — entry-point + backup
  model (passphrase-wrapped, dual-remote, stateless). Records the
  redundancy-not-confidentiality framing and the sandbox-first scope.
- Phase 2 follow-up ADR for the cloud Shamir decision.

## Risks / open items
- **Runtime secret exposure is non-zero:** tofu/ansible need plaintext keys on
  disk during a run. Mitigated by tmpfs + no-log, but persistence is zero, not
  exposure.
- **TF state lives only in backups (stateless):** single-operator-safe with the
  remote lock; document "don't run two managers at once."
- **Image ↔ platform version coupling:** baked pinned repos. Image tag is the
  release; document the bump procedure.
- **Where does the container repo live?** New component repo vs subdir of
  dmf-env. Leaning new repo (`dmf-init` / `dmf-bootstrap-console`) given its own
  release cycle, but it depends on pinned dmf-env/dmf-infra.

## Testing
- Phase 0: answers-file parity vs interactive (fake-data E2E, like the existing
  wizard test).
- Backup round-trip: wrap → push to two *local* rclone remotes → pull → unwrap
  → `doctor` (no real cloud needed).
- Phase 1 E2E: drive Create-new with fake data against the existing
  `dmf-sandbox` Lima VM through `verify`.
