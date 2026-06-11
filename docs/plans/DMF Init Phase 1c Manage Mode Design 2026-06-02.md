---
status: executed
date: 2026-06-02
---
# DMF Init Phase 1c — Manage Mode Design (2026-06-02)

Implementation design + slicing for **Phase 1c** of dmf-init: take an *already
commissioned* env that the container no longer holds (the container was deleted
after 1b's "safe to delete" screen) and **manage** it from a fresh container —
restore the env from a passphrase-wrapped backup, verify it, serialize against
concurrent managers via a remote lock, run lifecycle actions (re-run playbook,
upgrade-in-place, rotate, teardown), and re-backup on every state change.

Parent: [`DMF Init Phase 1 Implementation Plan 2026-06-02`](DMF%20Init%20Phase%201%20Implementation%20Plan%202026-06-02.md) §1c
and [`DMF Init Bootstrap Container Plan 2026-06-02`](DMF%20Init%20Bootstrap%20Container%20Plan%202026-06-02.md) §"Manage flow".
Builds on 1a (`backup.py` — `restore()`/`RestoreResult.cleanup()`) and 1b
(`orchestrate.py` — the streamed step engine).

**Scope decision (operator 2026-06-02, mirrors 1b):** build **hermetically
against the mock `CommandExecutor` seam + two local rclone remotes**. The live
`dmf-sandbox` exercise of both 1b and 1c happens in a later operator-gated
session. Everything below the executor seam is real; only the playbook/`bin/`
runs are mock-substituted in tests.

---

## 1. What's new vs Create-new + Bootstrap

Create-new (1a) and Bootstrap (1b) both **own the env**: they render it into
tmpfs, hold the age key + passphrase for the run, and push checkpoints. Manage
(1c) **starts from nothing in tmpfs** — the env must be *reconstituted from a
remote backup* before anything can touch it, and a **second manager may exist**
(another operator, another container) so mutations must be serialized.

Three genuinely new mechanisms:

1. **Restore-then-verify** — pull the `*.tar.age` from a remote, unwrap with the
   passphrase, reconstitute the env dir + age key in tmpfs, **export
   `SOPS_AGE_KEY_FILE` BEFORE `bootstrap-secrets.sh doctor`** (the doctor can't
   read the sops bundle without the age key), then doctor-verify.
2. **Read-verify-before-lock → remote lock** — a best-effort advisory lock object
   on the remote that serializes managers, gated by a re-read that confirms the
   restored state still matches the remote (no drift since restore).
3. **Action step-graphs + re-backup** — each lifecycle action is a small
   `orchestrate` step graph that ends in a re-backup checkpoint and releases the
   lock.

Everything else (subprocess→redacted NDJSON, secret-set redaction, the
`BootstrapRun` engine, the two-remote `backup()`) is reused as-is.

---

## 2. The restore-then-verify flow (1c.1)

New module `manage.py` (mirrors `createnew.py`'s shape: pydantic request models,
a streaming generator, a one-shot runner, `ManageError`).

`restore()` already exists in `backup.py` and returns a `RestoreResult` with
`restore_root`, `env_dir`, `age_key_path`, `answers_file_path`, `manifest`,
`inner_sha256`, `verified`, plus `.cleanup()`. **Do not reimplement it.** 1c.1
wraps it.

### Sequence
1. `POST /api/manage/restore` (session-protected) with: the **source remote**
   (one `RcloneRemoteSpec` + the artifact name / `remote:path`), the
   **passphrase**, and the **two destination remotes** for later re-backups
   (same two-remote contract as 1b — captured now so actions can re-backup).
2. Write an rclone config to a **tmpfs path** (`--config`, never
   `~/.config/rclone`) — reuse `backup._write_rclone_config`.
3. Call `restore(source, passphrase, dest_dir=$DMF_DATA_ROOT, rclone_config_path=…)`.
   `restore()` verifies the **inner-payload sha256** against the manifest and
   raises `BackupIntegrityError` on mismatch / `BackupDecryptError` on a wrong
   passphrase. Map those to **HTTP 422** (bad passphrase) / **409** (integrity).
4. **Relocate** the restored `env_dir` from `RestoreResult.env_dir` to the
   canonical `$DMF_DATA_ROOT/envs/<env_id>/` (so the existing `run-playbook.sh`
   / `bootstrap-secrets.sh` invocations resolve it), and the age key +
   answers-file to a `runs/<env_id>/` layout that mirrors what `createnew`
   produces (so a `render.json` equivalent exists for re-backup). `env_id` comes
   from `manifest.env_id` — **do not parse it from logs.**
5. `export SOPS_AGE_KEY_FILE=<relocated age key>` in the doctor command's env,
   **then** stream `bootstrap-secrets.sh doctor <env_id>` via the engine.
6. Emit a terminal `restored` event carrying `{env_id, profile, schema_version,
   manifest.checkpoint, manifest.repos (provenance), doctor: ok|failed}`.

### Secret hygiene
- The passphrase is held in process memory for the request only; **never logged,
  never persisted, excluded from request-body logging** (same posture as 1b).
- **Cleanup ordering invariant (qwen P2):** relocate the age key + answers file
  to the canonical `$DMF_DATA_ROOT/runs/<env_id>/` paths **by copy (not move),
  BEFORE** calling `RestoreResult.cleanup()`. The `doctor` command references the
  **relocated** age key, never the staging copy. `cleanup()` then wipes the
  `restore_root` staging tree only — no race with a still-reading `doctor`
  because `doctor` never touches staging.
- **Assert `$DMF_DATA_ROOT` is tmpfs at restore time (qwen P2):** if it is a
  host-mounted path the relocated plaintext age key + answers file would persist
  beyond container lifetime. Warn loudly (or refuse) when the data root is not a
  tmpfs mount.
- Before streaming `doctor`, seed the redaction set from the restored
  `openbao-keys.json` (reuse `bootstrap_steps._iter_secret_strings`) so any key
  echoed by doctor is redacted — same invariant as 1b checkpoint #2.

### Manage session object
A `ManageSession` (parallel to `BootstrapRun`, stored in
`app.state.manage_sessions[session_id]` under a lock) holds: `env_id`,
`restore manifest`, the **dest remotes**, the **age key path**, the
**lock state** (1c.2), and the **passphrase** (wiped on terminal / TTL GC /
explicit `DELETE`). Actions (1c.3) attach to this session. Reuse the lazy-TTL GC
pattern from `main.py`.

> **Why a session, not a `BootstrapRun`:** Manage is *multiple* discrete actions
> over one restored env, interleaved with operator decisions — not a single
> linear run. The session is the env+lock+passphrase holder; each action spawns
> its own short-lived `BootstrapRun` against the engine.

---

## 3. Read-verify-before-lock + the remote lock (1c.2) — HIGHEST RISK

This is the slice that gets the **qwen adversarial review gate** before commit
(like 1a.2 / 1b.2). The honest constraint:

> **rclone has no portable atomic compare-and-swap / conditional-put.** Over B2 /
> S3 / local, "list then create" is inherently TOCTOU. We therefore do **NOT**
> claim a hard mutex. Phase 1 posture (parent plan §178) is **single-operator,
> advisory lock + drift detection + loud refusal**, explicitly documented as
> "don't run two managers at once." The lock narrows the race window and turns
> the *common* collision into a clean refusal; it is not a distributed lock.

### Lock object
A small JSON object written to a **fixed key on the primary dest remote**
(`<prefix>/MANAGE.lock`), containing:

```json
{ "holder": "<random nonce, secrets.token_urlsafe>",
  "env_id": "<env_id>",
  "acquired_at": "<iso8601 UTC>",
  "ttl_seconds": 3600,
  "container": "<hostname-ish, non-identifying>" }
```

The lock lives on **one canonical remote** (dest remote #0), not both — a lock
split across two backends can't be made consistent and would double the race
surface. Backups still go to both remotes; the lock is the single serialization
point.

### Acquire (best-effort CAS emulation)
1. **Read** `MANAGE.lock` (rclone `cat` to tmpfs; absent ⇒ free).
2. If present and **not expired** and `holder != ours` → **refuse** (HTTP 409,
   surface holder age + ttl). Do **not** steal a live lock. **Expiry uses a
   5-minute clock-skew tolerance (qwen P2):** treat a lock as *still live* unless
   `now - acquired_at > ttl_seconds + 300`, so a modestly-skewed clock can't
   prematurely steal a genuinely-held lock without NTP guarantees.
3. If absent, or expired (past the tolerance), or already ours → **write** our
   lock object (`rclone copyto`).
4. **Read-back after a 3s settle delay** and confirm `holder == ours`. If the
   read-back's `holder` field is **not ours**, a competing writer interleaved →
   **refuse immediately** ("lost race to competing writer"); do not proceed.

**Backend consistency (qwen P1) — why 3s + read-back is sound for the documented
posture, not for multi-operator:**
- The lock key is a **fixed path** (`MANAGE.lock`). S3 (strong read-after-write
  since 2020) and B2 both give **strong read-after-write on a single key**, so
  the read-back reliably sees a rival's landed write; `list` lag (eventually
  consistent on B2) doesn't matter because we read the fixed key, not a listing.
  Local is strong everywhere.
- The 3s settle is belt-and-suspenders for propagation; the read-after-write
  guarantee is what actually makes the lost-race detection work.
- **Residual race:** the read→write TOCTOU window is *narrowed* not *eliminated*
  — this is an **advisory** lock for the **single-operator** posture (parent plan
  §178). Before any multi-operator use, a real coordination service
  (etcd/Consul/an HTTP lock service) is required. Document this in the UI + code.

### Read-verify-before-lock (drift guard) — corrected primitive (qwen P1)
The drift check answers **"is our restored state still the latest on the
remote?"** — *not* "does our artifact still exist?" Backups are timestamp-named
(`dmf-backup-<env>-<stamp>.tar.age`), so a sibling's newer push is a **different
key**; re-fetching our own artifact would never see it.

Correct primitive, between restore (§2) and the first mutation:
1. `rclone lsf <remote>:<prefix>/` filtered to `dmf-backup-<env_id>-*.tar.age`.
2. Parse the `<stamp>` from each filename; pick the **newest by timestamp**
   (mtime as a fallback only).
3. If the newest remote artifact **is ours** (same name we restored) → fresh,
   proceed.
4. Else download **that newest artifact's manifest** (decrypt just enough, or
   read a sidecar `.sha256` if we add one) and compare its `inner_sha256` to our
   restored manifest's. **Differs** → a different manager mutated + re-backed-up
   since our restore → our in-tmpfs env is **stale** → **refuse, tell the
   operator to re-restore.**

Only after the drift check passes do we acquire the lock — verify freshness
*first* so we never take a lock on top of stale state.

> **Implementation note:** decrypting a sibling artifact's manifest needs the
> passphrase (held for the session) — fine. If that proves heavy, add an
> **unencrypted `*.sha256` sidecar** next to each backup at `backup()` time (a
> tiny `backup.py` addition carrying only the inner-payload hash, no secrets) so
> drift detection is a cheap `cat`. Decide in 1c.2b; default to decrypt-manifest
> to avoid touching `backup.py` unless the sidecar is clearly cheaper.

### Release
Delete `MANAGE.lock` iff `holder == ours` (re-read before delete). On a crashed
manager, the **ttl expiry** is the recovery path (next manager sees it expired).

### Lock + action coupling
Acquire happens once, after restore + drift check, when the operator chooses to
manage (not at restore time — a read-only restore+doctor shouldn't lock).
Every mutating action runs **under** a held lock; re-backup + release close it.

---

## 4. Manage actions + re-backup (1c.3)

Each action = a small `orchestrate` step graph built like `bootstrap_steps`,
spawned as its own `BootstrapRun` against the existing engine + endpoints
(`/api/manage/action/start|stream|resume`). Actions reuse `CommandStep`,
`SubprocessExecutor`, the redaction set, and a terminal `CheckpointStep` that
re-backups (checkpoint **#4+**, monotonic per action) to **both** dest remotes,
then releases the lock.

| Action | Command (shelled to fetched `dmf-env/bin`) | Mutating? |
|---|---|---|
| re-run playbook | `run-playbook.sh <env> <playbook>` | yes |
| upgrade-in-place | `upgrade-in-place.sh <env>` | yes |
| rotate AppRole secret-id | `rotate-approle-secret-id.sh <env>` (or `cluster-rotate-…`) | yes |
| teardown | `remove-env.sh <env>` | yes (terminal) |
| re-backup only | (no command — just the checkpoint) | n/a |

Design points:
- **Every mutating action graph ends in a re-backup CheckpointStep + a release
  step**, so "on any state change, re-backup to both remotes; release lock"
  (parent §5) is structural, not a caller responsibility.
- **Teardown is terminal**: `remove-env.sh` `rm -rf`s the whole `envs/<env_id>/`,
  so a backup *after* it is impossible (`backup()` needs `env_dir.is_dir()`).
  Order is **re-backup final pre-teardown state → `remove-env.sh` → release lock
  → wipe session**. Whether to keep or purge the remote backups afterward is an
  **operator choice surfaced in the UI** — default keep
  (redundancy-not-confidentiality framing). The age key under `runs/<env_id>/`
  survives `remove-env`, so the final backup still encrypts.
- **Lock is re-validated at action start** (re-read `MANAGE.lock`, confirm still
  ours + not expired) — a long operator pause between acquire and action could
  outlive the ttl; if so, refuse and force re-acquire. **TTL is configurable**
  (settings, default 3600s; bump to 7200s if upgrade-in-place routinely exceeds
  ~45 min). **No heartbeat in Phase 1 (qwen P2)** — documented known limitation:
  *the same operator running two actions in succession with a TTL gap between
  them may need to re-acquire*; the action-start re-validation handles a TTL that
  lapses mid-flight by forcing a clean re-acquire on the next action.
- Reuse 1b's checkpoint backup path (`backup()` with `BackupManifestMeta`,
  monotonic `checkpoint=n`). The re-backup must re-seed the redaction set from
  the (possibly rotated) `openbao-keys.json` **before** streaming, same as 1b #2.

---

## 5. Frontend Manage view (1c.4)

Today `App.tsx` is a single Create-new→Bootstrap flow with **no mode switch**.
1c.4 adds:
- A **landing mode switch**: *Create new* (existing flow) / *Manage* (new).
- **Restore form**: source remote config + artifact selector + passphrase; the
  two dest-remote configs (reuse the Create-new remote form components).
- **Verified-state panel**: env_id, profile, checkpoint, repo provenance (the
  refs/SHAs from the manifest), doctor result.
- **Lock banner**: free / held-by-us / held-by-other(refused, with age).
- **Action buttons** (re-run playbook, upgrade, rotate, teardown, re-backup),
  each opening a **streamed log console** — reuse `BootstrapView`'s NDJSON
  reader + pause-modal machinery (extract the shared console if it's cheaper
  than duplicating; otherwise a thin `ManageView` that imports the same
  `readNdjson` + console subcomponent).
- **Teardown confirmation** (destructive) + the keep/purge-remote-backups choice.
- **No dead ntfy link** for sandbox (ADR-0031) — same rule as 1b.

---

## 6. Slicing (verify between each; commit only on operator go-ahead)

- **1c.1 — restore + doctor backend.** `manage.py` + `ManageSession` + restore
  endpoint + doctor stream + relocation + redaction seeding + tests (round-trip:
  1a/1b backup → restore → relocate → doctor against a **mock executor**;
  wrong-passphrase→422; integrity-mismatch→409; `cleanup()` wipes restore_root).
  Moderate risk. Reuses `restore()`.
- **1c.2 — remote lock + read-verify-before-lock** (split per qwen P3 to keep the
  two high-risk primitives in separate, separately-testable slices):
  - **1c.2a — lock module.** acquire (read → decide w/ 5-min skew tolerance →
    copyto → 3s settle → read-back refuse-on-different-holder), release-only-if-
    ours, ttl expiry, configurable ttl. Tests over a **local rclone remote**:
    acquire-free, refuse-live-foreign, steal-expired-past-tolerance,
    lost-race-on-readback, release-only-if-ours.
  - **1c.2b — drift detection.** `lsf` prefix → newest-by-stamp → compare
    `inner_sha256`. Test by planting a newer backup on the remote and asserting
    refusal; planting an identical/older one and asserting proceed.
  - **qwen adversarial review gate before commit** (covers both 1c.2a + 1c.2b).
- **1c.3 — manage actions + re-backup.** Action step-graph builders + action
  endpoints + monotonic checkpoint backups + lock re-validate + release; teardown
  terminal path. Tests against the mock executor + local remotes.
- **1c.4 — frontend Manage view.** Mode switch + restore form + state panel +
  action consoles + teardown confirm. `npm run build` gate.

Each slice: `/clear` codex → dispatch on-disk spec → review diff → run ALL gates
(ruff · `uv run … pytest` · gitleaks · `docker build --platform linux/arm64` for
backend-affecting slices · `npm run build` for 1c.4) → fix/bounce → qwen review
for 1c.2 → commit (dual Co-Authored-By: codex + Claude) on operator go-ahead.

---

## 7. Resolved by qwen-left review (2026-06-02 — all folded above)
1. **Drift-detection primitive** (§3): **CONFIRMED wrong as first drafted** →
   replaced with *list-prefix → newest-by-stamp → compare `inner_sha256`* (§3).
2. **Lock TTL** (3600s) vs long upgrade-in-place: **no heartbeat in Phase 1**;
   configurable TTL + action-start re-validation + 5-min skew tolerance (§3/§4).
3. **Where does `render.json` come from on restore?** createnew writes it; restore
   has only the manifest + answers-file. **Grounded resolution (confirm):**
   `BootstrapContext.from_data_root` reads `render.json` for
   profile/schema_version/age_key_path/answers_file_path (+ optional
   node_ip/base_domain used only by the hosts-map *pause*, which manage actions
   don't run). The manifest carries env_id/profile/schema_version; age_key/answers
   paths are set by our relocation. So **reconstruct a minimal `render.json` from
   the manifest on restore — no `backup.py` change needed.** qwen: probe whether
   any action path actually needs node_ip/base_domain.
4. **Teardown re-backup ordering** — **grounded resolution (confirm):**
   `remove-env.sh` `rm -rf`s the entire `envs/<env_id>/` dir, and `backup()`
   requires `env_dir.is_dir()`, so a re-backup *after* teardown is impossible and
   pointless. Therefore teardown = **re-backup the final pre-teardown state →
   `remove-env.sh` → release lock → offer remote-backup purge (default keep).**
   The age key lives under `runs/<env_id>/` (survives remove-env), so the final
   backup can still encrypt. qwen: confirm this ordering is the right terminal
   shape.
5. **Restore should NOT auto-lock** — restore+doctor is **read-only and
   lock-free**; the lock is a separate explicit "begin managing" step (§3 lock +
   action coupling). (Unchallenged by review; retained as designed.)

## 8. Review trail
- **STATUS: Phase 1c IMPLEMENTED + COMMITTED 2026-06-02** (hermetic). dmf-init
  `main`: `56678df` 1c.1 · `ba36f8f` 1c.2 · `e9a989c` 1c.3 · `b5fa77b` 1c.4.
  All gates green per slice (ruff · pytest w/ real rclone+age · gitleaks · npm
  build). Live `dmf-sandbox` exercise remains the operator-gated follow-up.
- qwen-left adversarial **code** review of 1c.2 (`manage_lock.py`) 2026-06-02 —
  verdict **CHANGES-NEEDED** (2×P1 / 2×P2 / 4×P3). Folded before commit:
  check_drift decrypt-vs-other differentiation; malformed-lock mtime recovery;
  non-identifying container tag; expired=None for malformed; settle-delay +
  malformed-recovery tests; same-name sub-second drift limitation documented.
  Review file: `/tmp/qwen-1c2-codereview.md`.
- qwen-left adversarial **design** review 2026-06-02 — verdict **CHANGES-NEEDED**
  (4×P1 / 2×P2 / 1×P3). All folded: drift primitive corrected (§3); lock acquire
  3s settle + backend-consistency note + refuse-on-different-holder (§3); 5-min
  clock-skew tolerance + configurable TTL + no-heartbeat limitation (§3/§4);
  cleanup-by-copy-before-cleanup() invariant + tmpfs assertion (§2); render.json
  reconstruction confirmed (node_ip/base_domain null — no action path reads
  them); teardown ordering confirmed (re-backup immediately before remove-env);
  1c.2 split into 1c.2a (lock) / 1c.2b (drift) (§6). Review file:
  `/tmp/qwen-1c-review.md`.
</content>
</invoke>
