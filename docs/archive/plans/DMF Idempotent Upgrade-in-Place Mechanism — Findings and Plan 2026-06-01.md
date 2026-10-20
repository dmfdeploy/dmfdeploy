---
status: historical
date: 2026-06-01
---
# DMF Idempotent Upgrade-in-Place — Findings & Plan (2026-06-01)

**Goal (operator-stated):** be able to re-run the bootstrap stages —
`bootstrap-provision-pre-seed` → `…-post-seed` → `bootstrap-configure` —
**idempotently against a live env to upgrade it to the current `main`**.

**Origin:** investigating a failing catalog teardown on the Hetzner env
`<env>` (provisioned 2026-05-21). The teardown bug was root-caused and
fixed, but doing so exposed that **upgrade-in-place does not currently work for
existing (cloud-lane) envs** — the subject of this doc.

**Status:** assessment only. No mechanism code changed yet. Live forward-fixes
were applied to `<env>` (see §5). Companion agent-memories:
`project_seedbao_bundle_set_bug`, `project_adr0032_catalog_teardown_skew`,
`project_unseal_openbao_use_pty_bug`.

> **Review incorporated — Codex read-only live review, 2026-06-01.** Corrections
> folded in below (marked ⟲): seed-bao is **not** auto-invoked by the bootstrap
> plays (§1, §3.4); the EE issue is a **tag-bump skew** (Zot has `0.1.0`, JT wants
> `0.1.1`), not a vanished image (§3 table); the `bundle_set` root cause is
> **unproven** and the repo-level-`.sops` theory is likely a red herring since the
> failure is *before* the encrypt step (§3.1); g2r6 carries **more MXL drift** than
> first documented (§5); the `unseal --status` helper is itself flaky vs a direct
> `bao status` (§4).

---

## 1. TL;DR recommendation

- **The mechanism is further off than "one bug."** ⟲ Correction: `seed-bao` is
  **not** invoked by any bootstrap play — it appears only in header *comments* as
  the canonical manual step *between* pre-seed and post-seed
  (`# Next step: …bootstrap-secrets.sh seed-bao <env>`). So "re-run pre/post/configure"
  today does **not** backfill secrets at all. Upgrade-in-place needs **both**
  (a) `seed-bao` made part of the (idempotent) upgrade sequence — currently a
  human-in-the-loop step — **and** (b) the `seed-bao` cloud-lane write-back bug
  fixed so it actually persists new secrets (§3.1). Plus failure-masking (§3.2)
  and hard-halt ordering (§3.3). The pieces exist; they are not yet an automated,
  idempotent whole.
- **`<env>`: wipe and redeploy — do NOT rehabilitate it.** It is a
  throwaway May-21 test env now carrying (a) the manual MXL spike Deployment
  override (`915-mxl-cms-override`), and (b) a half-applied set of forward-fixes
  from this session. Its drift is *organic and non-representative*, so it is a
  poor fixture for proving idempotency and not worth the manual surgery.
  Experiment-phase posture (umbrella `CLAUDE.md`) favours a clean baseline.
- **Prove idempotency on a *controlled* skew, not on g2r6.** Deploy a fresh env
  at an older `main` (or a tagged release), then run the three stages to upgrade
  to current `main`, and assert convergence + a clean second run. That is the
  real test the operator wants; g2r6's accidental state can't provide it.

The two are not in tension: fix the mechanism bugs (they are **not**
g2r6-specific), wipe g2r6 for a clean baseline, and validate the upgrade path on
a purpose-built skew env.

---

## 2. The teardown bug (resolved — context for how we got here)

`media-finalise-nmos-cpp` failed at *"Flip NetBox tag to lifecycle:bootstrapped"*
(NetBox `ipam/services/{id}` PATCH → 403). Root cause: **ADR-0032** (`dmf-runbooks
bf332bb`, 2026-05-27) dropped the NetBox admin token; the `nmos-cpp` role now
writes with `vault_netbox_catalog_token`, falling back to the **read-only**
`vault_netbox_api_token`. `g2r6` (2026-05-21) predates ADR-0032 and its AWX
launch credential never injected the scoped writer → read-only fallback → GET
ok, PATCH 403. Verified via `awx-manage`: job 204 `Get` OK, `Flip` FAILED,
`extra_vars` lacked `vault_netbox_catalog_token`.

**Fix (applied):** re-ran `691-netbox-sot` (mints the scoped writer into OpenBao)
+ `693-awx-integration` (rewires the launch JT). The JT now injects
`vault_netbox_catalog_token`. Code fix is correct and in place — but cannot be
*exercised* on g2r6 until the EE image is restored (§3 cascade).

Detail in `project_adr0032_catalog_teardown_skew`. **Any pre-2026-05-27 env hits
this**, which is itself an argument for a working upgrade mechanism.

---

## 3. Why upgrade-in-place is blocked (the actual subject)

Re-running current-`main` stages against the May-21 env surfaced **a cascade of
pre-ADR drift**, each item a newer secret/assumption the env never received:

| # | Drift | Consuming stage |
|---|---|---|
| A | ADR-0032 NetBox catalog token | configure (`691`/`693`) — fixed |
| B | EE-tag-bump skew: cluster Zot has `dmf/awx-ee:0.1.0`; current-main JT + inventory source reference `0.1.1` (404 in Zot) → every catalog/inventory job fails at pod start (`ErrImagePull`) ⟲ | post-seed (`630` re-mirror) |
| C | ADR-0033 `zot_service_password` absent → `630` (zot-svc push) and `191-zot-oidc` (htpasswd) hard-fail | configure / post-seed |

⟲ **Correction (Codex live read):** B is a **tag mismatch**, not a vanished
image — Zot holds `awx-ee:0.1.0`, but current main bumped the EE tag to `0.1.1`
(another forward-skew; see `AWX EE-pin gotchas` memory re: 630 EE-tag fallback
decoupled from the role default). B and C are gated behind the keystone bug (§3.1).

### 3.1 Keystone: `seed-bao` `bundle_set` fails on the cloud lane

`bin/bootstrap-secrets.sh seed-bao <env>` **aborts (real exit 1)** at the
ADR-0033 zot-svc write-back. Evidence:
- Log ends exactly at `apps.zot.service_password: absent in bundle — generating
  … and writing it back…`; the follow-on `generated and persisted` never prints.
- Bundle `~/secure/dmf-bootstrap/<env>.sops.yaml` mtime **unchanged**
  (still May-21); no `.tmp` leftover; no error echoed → it fails at the
  decrypt→python→tmp step (`bundle_set`, ~line 254) *before* the `sops --encrypt`
  guard (which would echo and leave a `.tmp`).
- The exact `bundle_set` pipeline **succeeds when run in isolation** from the
  `dmf-env` CWD with a dummy value → the failure is `bash` + `set -euo pipefail`
  + runtime-context specific, requiring instrumented debug (NOT `set -x`, which
  would leak the decrypted bundle and the generated secret).

**Root cause: UNPROVEN ⟲.** Codex's review correctly flags that the original
theory below is under-proven. The evidence (no `.tmp`, no echoed error) places
the failure **before** the `sops --encrypt` branch — i.e. at the
decrypt→python→`tmp_file` step — which makes the encrypt-step explanation
(repo-level `.sops`/`--config`) **likely a red herring**. The next debugger must
instrument `bundle_set` to find the actual failing command (per-step exit-code
markers on a throwaway bundle; NOT `set -x`, which leaks the decrypted bundle +
generated secret) before committing to a fix.

*Original (now-doubted) theory, retained for the debugger:*
`bundle_sops_config_file()` only checks for a *co-located*
`$(dirname bundle)/.sops.yaml`. Cloud bundles live in `~/secure/dmf-bootstrap/`
with **no** co-located `.sops.yaml`; the SOPS creation-rules live **repo-level**
in `dmf-env/.sops.yaml` (`path_regex: '.*/<env>\.sops\.yaml$'`). This would
make the re-encrypt CWD-dependent — but since the failure appears to precede the
encrypt, treat this as a *secondary* hardening, not the proven cause. The
**sandbox lane works** (co-located `.sops.yaml` per env; earlier fix
`dmf-env 3ab4e50` covered sandbox cold-bootstrap only). Same bug *class* as
`project_sandbox_sops_config_class_bug`, root cause TBD.

**Impact:** new-ADR secrets never persist to a cloud bundle → `export-vars`
can't emit the `vault_*` → consuming playbooks `mandatory`-halt. This is the
single thing standing between "re-run bootstrap" and "upgraded to main."

### 3.2 Failure-masking (correctness hazard for an automated loop)

`seed-bao | tee …` reported **exit 0** while `seed-bao` actually exited **1**
(the pipe's exit was `tee`'s). An automated upgrade loop invoking seed-bao
through any non-`pipefail` wrapper would believe secrets seeded when they did
not. Seed-bao must surface its own failures, and callers must not mask them.

### 3.3 Hard-halt ordering

Deploy playbooks (`630`, `191-zot-oidc`) use the `mandatory` filter and
hard-fail on a missing newer secret, rather than the flow guaranteeing
`seed-bao` ran **and succeeded** before consumers run. The seed→deploy coupling
needs to be explicit (and ideally checked — see §6).

### 3.4 `seed-bao` is not invoked by the bootstrap plays ⟲

Codex's review found — and a `grep` confirms — that every `seed-bao` reference in
`bootstrap-provision-pre-seed.yml`, `…-post-seed.yml`, `lifecycle-provision.yml`,
and `site.yml` is a **header comment** documenting the canonical manual sequence,
not a play that runs it. `seed-bao` is an explicit operator step *between*
pre-seed and post-seed (the "local seed boundary"). Consequence: **re-running
the three stages does not backfill secrets at all** — even with `bundle_set`
fixed, the operator (or an upgrade wrapper) must run `seed-bao` as part of the
sequence. So idempotent upgrade requires *adding* a seed step to the loop (or a
new `upgrade` wrapper that runs `seed-bao` then the stages), not just fixing
`bundle_set`. The earlier "already wired" framing was too optimistic.

---

## 4. Adjacent finding: `unseal-openbao.sh` broken on hardened envs

While unsealing g2r6 for the configure run: `bin/unseal-openbao.sh` fails at
"Feeding shares" on hardened envs. Root cause: `Defaults use_pty` in sudoers
(harden role) makes `sudo` allocate a PTY and **discard piped stdin**, so the
share never reaches `bao operator unseal`. **Not an SSH-key problem** (auth
succeeds; `--status` works because it needs no stdin). Proven with a dummy
payload (`len=0`) across `ssh -T`, pod-side `cat`, and `ssh -tt`.

- **Workaround used:** re-run `playbooks/vertical-security/100-openbao.yml` — the
  openbao role auto-unseals via Ansible `become` + `kubectl exec -- bao operator
  unseal <key>` (key in **argv**, no piped stdin → `use_pty`-immune). The wrapper
  only `sops`-decrypts the local bundle, so it runs fine against a sealed bao.
- ⟲ **`unseal-openbao.sh --status` is itself flaky (Codex):** it failed in
  Codex's session even read-only, while a direct control-node
  `kubectl -n openbao exec openbao-0 -- bao status -format=json` reported
  unsealed. The helper's status path looks weaker than the documented
  remote-kubectl path — prefer the direct `bao status` for verification.
- **Proper fix (TODO):** switch the script from `sudo kubectl exec` to the
  OpenBao HTTP API — `PUT /v1/sys/unseal` body `{"key":"<share>"}` (pre-auth,
  share in body via `curl --data-binary @-`, never argv), run **on the node**
  (no sudo → no use_pty) against the **cluster-internal** endpoint
  (`https://127.0.0.1:8200` / `openbao.openbao.svc:8200`).
- **Security note:** OpenBao is (correctly) **not exposed via ingress** on g2r6
  and must stay that way — it is the platform root of trust. The API fix must be
  node-local/internal, **never** a public `openbao.<domain>` ingress.

Detail in `project_unseal_openbao_use_pty_bug`.

---

## 5. Live state left on `<env>` (this session)

All forward-progress / idempotent; nothing broken further:
- ✅ OpenBao **unsealed** (`100-openbao.yml`).
- ✅ `691` + `693`: NetBox scoped catalog writer minted; teardown JT rewired
  (ADR-0032 fix — `vault_netbox_catalog_token` now in the JT extra_vars).
- ✅ `seed-bao`: seeded OpenBao admin paths; self-healed the zot admin email to
  the canonical identity (ADR-0024/0028). **Did NOT** persist the zot-svc
  password to the bundle (§3.1).
- ⛔ `630`: did **not** re-mirror the EE (blocked on §3.1) → `dmf/awx-ee:0.1.1`
  still missing from Zot → **teardown remains blocked**.
- Console untouched — still on the spike image `0.9.2-mxl-spike` +
  `DMF_CONSOLE_MXL_ENDPOINTS` (the `915` override).
- ⟲ **More MXL drift than first documented (Codex live read):** g2r6 also carries
  extra **non-inventory MXL nodes/workloads**, with at least one MXL Deployment in
  `CrashLoopBackOff`. This is organic spike residue beyond the console override —
  it reinforces the §1 "wipe, don't rehabilitate" recommendation: g2r6 is not a
  clean fixture for proving idempotency.

If g2r6 is wiped (recommended), none of the above matters; if not, the EE
mirror + zot-svc password remain outstanding.

---

## 6. Proposed plan (to make re-run = upgrade)

Ordered by leverage. None is g2r6-specific.

1. **Find the real `bundle_set` failure, then fix it (keystone).** Root cause is
   **unproven** (§3.1) — do not assume the `.sops`/`--config` theory.
   - First instrument safely (per-step exit-code markers on a throwaway bundle;
     **no `set -x`** — it leaks the decrypted bundle + generated secret) to pin
     the exact failing command. Evidence says it's *before* the encrypt step.
   - Fix the confirmed cause. The repo-level `.sops`/`--config` resolution is a
     reasonable *secondary* hardening regardless (make it CWD-independent for
     both lanes), but is not yet the proven fix.
   - Add a smoke test: round-trip a key into a *cloud* bundle and assert
     `export-vars` re-reads it.
2. **De-mask failures.** Ensure `seed-bao` exits non-zero loudly; never invoke it
   through a non-`pipefail` pipe (the `| tee` that hid exit-1 this session). An
   upgrade wrapper must abort on seed-bao failure.
3. **Wire `seed-bao` into the upgrade sequence ⟲.** Today it's a manual operator
   step that the plays only *document* (§3.4). For idempotent upgrade, either add
   a dedicated `upgrade` wrapper (`seed-bao` → pre/post/configure) or have the
   flow invoke+verify seed-bao at the seed boundary. Then tighten
   seed→deploy ordering so consumers fail fast with a clear "run seed-bao"
   message instead of a raw `mandatory` error.
4. **Wire an upgrade-convergence gate.** `playbooks/verify-bootstrap-convergence.yml`
   already exists — extend it to assert post-upgrade invariants (all expected
   `vault_*` present, EE image resolvable in Zot, catalog JT carries the scoped
   token).
5. **Fix `unseal-openbao.sh`** for `use_pty` envs (§4) — internal API POST.
6. **Validate idempotency on a controlled skew** (the real proof): provision a
   fresh env at `main~N`/a tag, run pre/post/configure to upgrade to `main`,
   assert (a) it converges with no manual steps and (b) an immediate second run
   is a clean no-op. Then **wipe + redeploy g2r6** for a clean baseline.

---

## 7. References

- `dmf-env/bin/bootstrap-secrets.sh` — `seed-bao`, `bundle_set`,
  `bundle_sops_config_file`, `export-vars`.
- `dmf-env/bin/unseal-openbao.sh`; skill `dmf-openbao-unseal`.
- `dmf-infra/k3s-lab-bootstrap/{bootstrap-provision-pre-seed,…-post-seed,bootstrap-configure}.yml`,
  `playbooks/630-zot-seed-platform.yml`, `playbooks/691-netbox-sot.yml`,
  `playbooks/693-awx-integration.yml`, `playbooks/vertical-security/{100-openbao,191-zot-oidc}.yml`,
  `playbooks/verify-bootstrap-convergence.yml`.
- `dmf-runbooks bf332bb` (ADR-0032); ADR-0033 (zot-svc machine-write account).
- Agent memories: `project_seedbao_bundle_set_bug`,
  `project_adr0032_catalog_teardown_skew`, `project_unseal_openbao_use_pty_bug`,
  `project_sandbox_sops_config_class_bug`.
