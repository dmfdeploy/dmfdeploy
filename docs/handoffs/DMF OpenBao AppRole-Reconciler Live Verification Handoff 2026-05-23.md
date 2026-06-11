# DMF OpenBao AppRole-Reconciler — Live Verification Handoff

**Date:** 2026-05-23
**Origin:** Convergence pass after the operator asked "what are the next steps
with the highest impact?" The original framing — that the OpenBao AppRole-
Reconciler was a stuck Tier A blocker needing ~half a day of new code — was
**stale**. ADR-0021 implementation landed `dmf-infra@209601d` on 2026-05-13;
g2r6-foa9 was bootstrapped 2026-05-21 with that code in place. This session
verified the implementation is live and functioning end-to-end, and retires
the "Step 5 mystery" and the Tier A blocker framing.

## TL;DR

ADR-0021 (OpenBao AppRole-Reconciler identity) is **fully implemented and
verified live on g2r6-foa9**. The Tier A bootstrap-correctness gate is
closed. Verification artefacts:

| Artefact | Outcome |
|---|---|
| `vertical-security/100-openbao.yml` rerun | PLAY RECAP `failed=0`; `Verify approle-reconciler login on rerun path` task `ok` (login succeeded against the existing userpass user) |
| `vertical-resilience/100-object-storage-credentials.yml` rerun | PLAY RECAP `failed=0`; both AppRoles + ESO bindings + ClusterSecretStores + 6 ExternalSecrets converged with `changed=3` (all read-shaped: 1× `bao policy write` no-op + 2× command-module `Read …` reports — no real state mutation) |
| New verifier `playbooks/verify-openbao-identity-model.yml` (this PR) | PLAY RECAP `failed=0 changed=0`; 3 identity logins, 5 AC-5 deny probes, 2 ClusterSecretStores Ready, 6 ExternalSecrets Ready across 6 namespaces (openbao-system, awx, netbox, authentik, forgejo, zot) |

The verifier playbook ships in `dmf-infra` so the next env runs it as part
of post-seed verification, not just g2r6-foa9 today.

## What was found

### 1. Implementation already landed (2026-05-13)

`dmf-infra@209601d` (`feat(openbao): add object storage approle reconciler`)
added on 2026-05-13 16:13 — the same day the Implementation Brief was
written. 8 files changed, +407/−142 lines across:

- `roles/stack/operator/openbao/{defaults,tasks}/main.yml` — password gen on
  fresh init, fail-loud on rerun without credentials, login-verify on
  rerun, policy HCL + apply, userpass user creation, break-glass JSON
  composition.
- `roles/common/openbao-session/{defaults,tasks}/main.yml` — mode parameter
  extended to `approle-reconciler`.
- `roles/base/object-storage-credentials/{defaults,tasks}/main.yml` +
  README — three-session token routing (policy-reconciler for Step 3,
  approle-reconciler for Steps 4-9, Kubernetes API for Steps 11-14);
  dashed/underscored naming convention codified.
- `docs/openbao-bootstrap-security-model.md` — model documentation.

The parent plan's prerequisite work landed earlier in `dmf-infra@6f6cee8`
(2026-05-13 morning) — policy-writer session separation that unblocked
Step 3.

### 2. g2r6-foa9 was bootstrapped with the code in place

The env was created via `init-wizard.sh` on 2026-05-21. Its OpenBao
bootstrap was the first to follow the ADR-0021 path: `approle-reconciler`
userpass user minted during initial init, break-glass JSON populated with
`approle_reconciler_username` + `approle_reconciler_password`,
`approle-reconciler-writer` policy applied. The `bootstrap-configure.yml`
green run on 2026-05-22 (PLAY RECAP `ok=651 changed=20 failed=0`) implicitly
proved the chain works end-to-end — configure depends on a healthy
vertical-security + vertical-resilience.

### 3. Verification matrix on g2r6-foa9 (2026-05-23)

**Probe 1 — `vertical-security/100-openbao.yml` rerun.** 107 tasks; PLAY
RECAP `ok=59 changed=18 failed=0 skipped=48`. Key signals:

- `Fail if approle-reconciler credentials missing on rerun` → **skipped**
  (credentials present in break-glass JSON ✓)
- `Verify approle-reconciler login on rerun path` → **ok** (login
  succeeded against existing userpass user ✓)
- `Upsert approle-reconciler userpass user` → **skipped** (init-only path,
  identity already exists ✓)
- `Apply approle-reconciler-writer policy` → changed (idempotent OpenBao
  policy reapplication; bao API returns `changed` even on identical
  content)
- `Revoke root token` → skipped (root already revoked at first init ✓)

**Probe 2 — `vertical-resilience/100-object-storage-credentials.yml`
rerun.** 50 tasks; PLAY RECAP `ok=47 changed=3 failed=0 skipped=3`. Key
signals:

- `Create AppRole`, `Generate secret-id`, `Store secret-id in OpenBao` →
  all skipped (AppRoles already exist; no rotation; idempotent ✓)
- `Apply OpenBao reader policy` → changed (same bao-API artefact)
- `Read AppRole role-id`, `Read secret-id from OpenBao` → changed
  (Ansible command-module artefact; both read-shaped, no mutation)
- `Wait for ClusterSecretStore to become Ready` → ok for both
  `openbao-openbao-snapshots` + `openbao-app-backups` ✓
- `Create ExternalSecret` → ok for 6 items (matching the 6 consumer
  namespaces × logical assignments in the role defaults)

**Probe 3 — new `verify-openbao-identity-model.yml`.** 47 tasks; PLAY
RECAP `ok=47 changed=0 failed=0 skipped=0`. Verifier output:

```
OpenBao identity model verified on this cluster:
  - 3 identities log in: ops-admin, policy-reconciler, approle-reconciler
  - 5 AC-5 negative probes all return 'deny':
      * ops-admin → sys/policies/acl/test
      * ops-admin → auth/approle/role/object-storage-app-backups/secret-id
      * policy-reconciler → auth/approle/role/object-storage-app-backups/secret-id
      * approle-reconciler → sys/policies/acl/test
      * approle-reconciler → secret/data/apps/forgejo/admin
  - 2 ClusterSecretStores Ready (openbao-openbao-snapshots, openbao-app-backups)
  - 6 ExternalSecrets Ready across 6 namespaces
```

### 4. Step 5 mystery — closed

STATUS flagged "Step 5 mystery (post-seed log shows `changed:` for an op
ops-admin shouldn't be able to do) must be resolved by a targeted probe
before Option C is implemented." The parent plan's §4 already documented
the resolution:

- Live probes on aliyun-123 confirmed `ops-admin` returned `deny` on
  `auth/approle/role/*` paths, twice.
- `policy-reconciler` returned `deny` on the same paths.
- `ops-admin` bound policies were exactly `app-admin-writer,
  app-runtime-writer, default` — no `policy-writer`, no AppRole powers.

The `changed:` in the original log came from a different execution context
before the session-separation refactor was fully in place (likely using
root or an unintended token path). Under current refactored code
(`6f6cee8`+), the same `changed:` cannot be reproduced. The mystery is an
artefact of pre-refactor execution, not a live security gap.

The 2026-05-23 verifier run is the second independent confirmation of
this: the AC-5 deny matrix holds on the live cluster under the current
code path.

## What this closes

- **STATUS.md `### 🛑 OpenBao identity model — Tier A blocker, Option C
  selected (2026-05-13)`** — replaced with a `### ✅ ADR-0021 verified on
  g2r6-foa9 (2026-05-23)` block.
- **Parent plan** `DMF OpenBao AppRole-Write Reconciler Plan 2026-05-13.md`
  — supersession banner pointing here.
- **Implementation brief** `DMF OpenBao AppRole-Reconciler Implementation
  Brief 2026-05-13.md` — supersession banner pointing here; §6 (existing-
  cluster recovery ceremony) explicitly retained as still-active reference
  for any pre-2026-05-13 cluster that gets resurrected.
- **ADR-0021** — `### Enforcement` block appended with a "Verified live on
  g2r6-foa9 2026-05-23" line; no status change (already Accepted).
- **Backlog implication**: `Tier A Phase 3 (vertical-resilience playbooks)`
  no longer has an outstanding OpenBao-side gap. Tier A's remaining work
  is elsewhere (per the 2026-05-12 Tier A Phase 3 implementation handoff).

## New verifier playbook — `verify-openbao-identity-model.yml`

Lands in `dmf-infra/k3s-lab-bootstrap/playbooks/`. Read-shaped assertion
playbook modelled on `verify-oidc-admin-bridge.yml` (ADR-0024 PR2). Three
sections:

1. **Identity logins.** Calls `common/openbao-session` three times (mode
   = `operator`, `policy-reconciler`, `approle-reconciler`) and captures
   each session token to a per-identity fact (`no_log: true`).
2. **AC-5 negative probes.** For each of 5 (identity, path) tuples,
   pipes the token through `kubectl exec -i` into the OpenBao pod's
   shell, runs `bao token capabilities -format=json <path>`, normalises
   the JSON response (handles both `{capabilities: [...]}` and `[...]`
   shapes), and asserts the capability list equals the expected outcome.
   Token never appears in argv or in the playbook log.
3. **Positive ESO reconcile.** k8s_info lookups for the two
   ClusterSecretStores and the six ExternalSecrets, asserting each has a
   `Ready=True` condition.

Tagged `vertical-security` + `verify-openbao-identity`. Belongs in the
post-seed `bootstrap-verify.yml` sweep when it next gets touched (out of
scope this session).

## Followups (non-blocking)

1. **`bin/unseal-openbao.sh` ordering bug.** Line 120 calls `err` before
   the function is defined at line 133 — triggers only when `SSH_TARGET`
   can't resolve. Cosmetic; the script still exits non-zero. Move the
   helper definitions above line 100 or move the SSH_TARGET resolution
   below the helpers. Surfaced when an env-var sanity check tried
   `bin/unseal-openbao.sh --status` against g2r6-foa9 from the wrong cwd.

2. **`bootstrap-verify.yml` should include the new verifier.** Phase 4 of
   this convergence work intentionally did not wire it into the
   post-seed verify wrapper. Once `bootstrap-verify.yml` is next
   touched, include this playbook so any future env automatically
   exercises the AC-5 matrix.

3. **Inadvertent identity echo in the agent transcript.** While running
   pre-flight checks, `cat dmf-env/inventories/g2r6-foa9/hosts.ini`
   printed three Hetzner public IPs (138.105.x.y class). These are
   Hetzner-public addresses, not credentials, but they belong in
   `dmf-env` (private) and shouldn't be in agent transcripts per the
   `dmf-cluster-access` §0 discipline. Going forward: rely on the
   wrapper to read the inventory; don't `cat` private-repo files in
   agent flows.

## Cross-references

- ADR-0021 — OpenBao AppRole-Reconciler identity (Accepted).
- ADR-0007 — Secrets never in argv (the no_log + pipe-via-stdin pattern
  in the verifier).
- ADR-0008 — OpenBao + ESO + AppRole shim secrets architecture.
- ADR-0021 §Enforcement — updated to cross-link this handoff.
- `dmf-infra@209601d` — original implementation commit, 2026-05-13.
- `dmf-infra@6f6cee8` — prerequisite policy-writer session separation,
  2026-05-13.
- `docs/plans/DMF OpenBao AppRole-Write Reconciler Plan 2026-05-13.md`
  — parent plan, now superseded by this handoff.
- `docs/plans/DMF OpenBao AppRole-Reconciler Implementation Brief
  2026-05-13.md` — implementation brief, superseded by this handoff
  except for §6 (recovery ceremony for pre-2026-05-13 clusters, still
  active reference).
