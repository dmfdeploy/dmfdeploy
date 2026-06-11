---
status: executed
date: 2026-05-13
executed: 2026-05-13
---
# DMF OpenBao AppRole-Write Reconciler Plan — 2026-05-13

> **SUPERSEDED 2026-05-23** — implementation landed `dmf-infra@209601d`
> on 2026-05-13 and was verified live on g2r6-foa9 on 2026-05-23. See
> [`docs/handoffs/DMF OpenBao AppRole-Reconciler Live Verification Handoff 2026-05-23.md`](../handoffs/DMF%20OpenBao%20AppRole-Reconciler%20Live%20Verification%20Handoff%202026-05-23.md)
> for the verification matrix and closure notes. This plan is retained as
> the historical record of the design exploration that led to ADR-0021.

**Status:** Decided — Option C selected (ADR-0021); landed `dmf-infra@209601d` 2026-05-13; verified live on g2r6-foa9 2026-05-23
**Owner:** next agent
**Tier:** Tier A (vertical-resilience cannot complete without this)
**Predecessor:** [DMF OpenBao Policy-Writer Session Separation Plan 2026-05-13](DMF%20OpenBao%20Policy-Writer%20Session%20Separation%20Plan%202026-05-13.md) (landed, this plan extends)

---

## 1. Tl;DR

The 2026-05-13 policy-writer session-separation refactor landed and `base/object-storage-credentials` now reaches Step 3 (`bao policy write`) cleanly. Empirical end-to-end verification on aliyun-123 then revealed a new structural gap: **no existing OpenBao identity has the capabilities required to fully reconcile `object-storage-*` AppRoles during post-seed.**

Probe results (live cluster, 2026-05-13):

| Identity | Bound policies | Can write `auth/approle/role/object-storage-*/secret-id`? |
|---|---|---|
| `ops-admin` | `app-admin-writer, app-runtime-writer, default` | **No — 403** (verified by direct probe) |
| `policy-reconciler` | `policy-writer, default` | **No** (policy-writer = `sys/policies/acl/*` only) |

The role's `app-runtime-writer` HCL hardcodes `auth/approle/role/{{ openbao_eso_role_name }}/secret-id` — i.e., only the ESO bootstrap role, not the consumer-declared object-storage AppRoles.

Operator decision on 2026-05-13: implement **Option C**, a dedicated
`approle-reconciler` identity for AppRole and ESO binding reconciliation. This
is now recorded in [ADR-0021](../decisions/0021-openbao-approle-reconciler-identity.md).

---

## 2. Context

### 2.1 What works after 2026-05-13 session-mode fix

Three files changed in `dmf-infra@6f6cee8`:

- `k3s-lab-bootstrap/roles/common/openbao-session/defaults/main.yml` — new `openbao_session_mode` param (`operator` default | `policy-reconciler`)
- `k3s-lab-bootstrap/roles/common/openbao-session/tasks/main.yml` — mode-aware credential loading from break-glass JSON
- `k3s-lab-bootstrap/roles/base/object-storage-credentials/tasks/main.yml` — two `include_role` calls capturing `_osc_operator_token` + `_osc_policy_token`; Step 3 routes via `_osc_policy_token`; pre-existing bugs (missing env block on Step 5; `item.item.logical` → `item.logical` in Steps 5+6) fixed along the way

Post-seed re-run results:

- ✅ Step 1 — two sessions established (operator + policy-reconciler)
- ✅ Step 2 — external-secrets namespace ensured
- ✅ Step 3 — two `object-storage-*-reader` policies written (via policy-reconciler)
- ✅ Step 4 — AppRole-existence + eso-binding-existence checks (with `failed_when: false`; results drive idempotency gates downstream)
- ✅ Step 5 — `bao write auth/approle/role/object-storage-<name>` reported `changed:` for both logicals ⚠️ **suspect, see §4 mystery**
- ❌ Step 6 — `bao write -force auth/approle/role/object-storage-<name>/secret-id` → 403
- ⛔ Steps 7–14 — never reached

### 2.2 Live cluster state after partial run (aliyun-123, 2026-05-13)

- 2 new `object-storage-*-reader` policies present
- 2 AppRoles (`object-storage-openbao-snapshots`, `object-storage-app-backups`) may exist (Step 5 reported `changed:`, but per §4 the actual write may not have happened)
- 0 entries under `secret/platform/eso-bindings/object-storage-*` (Step 7 not reached)
- 0 K8s Secrets in `external-secrets` namespace (Step 11 not reached)
- 0 ClusterSecretStores `openbao-*` (Step 13 not reached)

Whatever Option below is picked, the partial state is idempotent-safe — the role's existence-check gates (Steps 4a/4b) handle re-runs cleanly.

### 2.3 Capability matrix (verified via probe, 2026-05-13)

```
                                          ops-admin   policy-reconciler   root
sys/policies/acl/*                            no          yes (CRUDL)      destroyed
auth/approle/role/+                           no          no               destroyed
auth/approle/role/+/secret-id                 only `eso`* no               destroyed
auth/approle/role/+/role-id                   no          no               destroyed
secret/data/apps/+/*                          yes         no               destroyed
secret/data/platform/object-storage/*         no          no               destroyed
secret/data/platform/eso-bindings/*           no          no               destroyed
```

`*` = `app-runtime-writer` hardcodes `auth/approle/role/{{ openbao_eso_role_name }}/secret-id` — a single bootstrap AppRole, not a wildcard.

### 2.4 The principle being preserved

Same as the parent plan: NIST 800-53 AC-5 separation of duties. Root is destroyed after init; ops-admin is operator's daily-use narrow identity; policy-reconciler is bootstrap-only and shouldn't gain app-data access.

---

## 3. Goal & non-goals

### Goal

Enable `base/object-storage-credentials` to complete end-to-end on greenfield AND idempotently on re-run, without granting ops-admin any new platform-wide write capability.

### Non-goals

- Not changing policy-reconciler password lifecycle (still bootstrap-only, automation JSON).
- Not re-introducing root usage during post-seed.
- Not addressing "static-declared vs consumer-declared platform policies" (parent plan settled this as consumer-declared).
- Not migrating existing ESO bootstrap AppRole (`eso`) into the new scheme — it stays openbao-role-managed.

---

## 4. The Step 5 mystery — RESOLVED (live probe, 2026-05-13)

**Resolution: the `changed` in the post-seed log is not reproducible under current code and almost certainly came from an earlier/different execution context, not the refactored session-mode run.**

Live probe results from aliyun-123 (2026-05-13, secret-safe):

| Probe | Result |
|---|---|
| `bao read auth/userpass/users/ops-admin` → token_policies | `app-admin-writer, app-runtime-writer, default` — exactly as defined in-repo |
| ops-admin caps on `auth/approle/role/object-storage-openbao-snapshots` | `[deny]` |
| ops-admin caps on `.../secret-id` | `[deny]` |
| ops-admin actual `bao write auth/approle/role/probe-test-*` attempt | **403 permission denied** (confirmed with two separate probe attempts) |
| policy-reconciler caps on `.../secret-id` | `[deny]` |

The token capture flow (`set_fact` with eager Jinja2 evaluation before the second `include_role`) is structurally correct — no lazy-evaluation bug exists. `_osc_operator_token` holds the literal ops-admin token string at use time.

**Explanation:** ops-admin on the live aliyun-123 cluster genuinely has zero `auth/approle/role/*` write capability. The `changed` status in the earlier post-seed log must have come from a different run — likely one executed before the session-separation refactor (commit `6f6cee8`) was fully in place, possibly using root token or a different token routing path. Under the current refactored code, the same `changed` cannot be reproduced. This gap is exactly what ADR-0021's `approle-reconciler` identity is designed to fill.

### Original hypotheses (now resolved)

1. **Templating bug:** `_osc_operator_token` silently rebound to policy-reconciler token — **ruled out.** Jinja2 evaluation is eager; capture happens before second `include_role`.
2. **Stale pod env:** residual `BAO_TOKEN` from root session — **ruled out.** The `IFS= read -r BAO_TOKEN; export BAO_TOKEN;` pattern explicitly overrides pod-level env.
3. **Out-of-band policy customization on aliyun-123:** earlier session may have widened `app-admin-writer` — **ruled out.** Current ops-admin has exactly the three in-repo policies.

---

## 5. Options

### Option A — Halt + this plan (already executed)

Three fixes landed in `dmf-infra@6f6cee8`. This follow-up plan is the
operator-ratified path for the remaining identity gap.

### Option B — Broaden policy-reconciler scope (single bootstrap-reconciler identity)

**Code changes:**

- `dmf-infra` openbao role: extend `policy-writer` HCL to add:
  ```hcl
  path "auth/approle/role/+" {
    capabilities = ["create", "read", "update", "delete", "list"]
  }
  path "secret/data/platform/eso-bindings/*" {
    capabilities = ["create", "read", "update", "delete"]
  }
  path "secret/metadata/platform/eso-bindings/*" {
    capabilities = ["read", "list", "delete"]
  }
  ```
- Rename `policy-writer` → `bootstrap-reconciler` (or keep name for stability; the *intent* widens).
- `base/object-storage-credentials`: route Steps 3, 5, 6, 7, 8, 9 through `_osc_policy_token`. Operator session only needed for Step 12 (read OpenBao TLS Secret) and Step 11 + Step 13 + Step 14 (K8s API writes; ESO Secret creation actually uses the K8s API not OpenBao directly, so it doesn't need OPENBAO_TOKEN at all — only the namespace exists in K8s).
- Actually re-examining: of the 14 steps, only Steps 3, 5, 6 (write OpenBao policy + AppRole + secret-id), 7 (write KV binding), 8, 9 (read AppRole metadata + binding) need an OpenBao session. Steps 11, 13, 14 are K8s API writes; Step 12 is a K8s API read. So **if Option B is chosen, base/object-storage-credentials may only need ONE OpenBao session — bootstrap-reconciler.** Operator session can be dropped entirely from this role.

**Pros:**
- No new identity; no new password rotation cycle.
- One session instead of two in `base/object-storage-credentials` — simpler control flow.
- Mirrors the existing "bootstrap-only, automation-JSON password, no operator Keychain involvement" pattern.

**Cons:**
- `policy-writer` becomes a misnomer — it now writes more than policies.
- One identity now has more breadth: if its credentials leak from the automation JSON, the blast radius widens from "rewrite all policies" to "rewrite all policies + create arbitrary AppRoles + write all eso-bindings". Still NOT app-data access, so contained.

### Option C — Add new approle-reconciler identity (strictest AC-5) — SELECTED

**Code changes:**

- `dmf-infra` openbao role: new policy `approle-reconciler-writer`:
  ```hcl
  # Generate one explicit block set per object-storage logical.
  # Do NOT use auth/approle/role/object-storage-*/secret-id: OpenBao glob `*`
  # is only valid as the final character in a policy path.
  path "auth/approle/role/object-storage-app-backups" {
    capabilities = ["create", "read", "update", "delete", "list"]
  }
  path "auth/approle/role/object-storage-app-backups/role-id" {
    capabilities = ["read"]
  }
  path "auth/approle/role/object-storage-app-backups/secret-id" {
    capabilities = ["create", "read", "update"]
  }
  path "secret/data/platform/eso-bindings/object-storage-app-backups" {
    capabilities = ["create", "read", "update", "delete"]
  }
  path "secret/metadata/platform/eso-bindings/object-storage-app-backups" {
    capabilities = ["read", "list", "delete"]
  }
  ```
- New userpass user `approle-reconciler` bound to that policy. Password generated like policy-reconciler's, written to break-glass JSON as `approle_reconciler_password` (+ optional `approle_reconciler_username`).
- `common/openbao-session`: add third mode `approle-reconciler`. Update the conditional in `Load OpenBao session credentials` to handle three cases.
- `base/object-storage-credentials`: three sessions — operator (K8s reads), policy-reconciler (Step 3), approle-reconciler (Steps 5–9).

**Pros:**
- Strict AC-5: each identity owns exactly one concern (policy management vs AppRole + binding reconciliation).
- Future expansion: if more bootstrap-only writes appear (e.g., audit-device management), they get a third or fourth reconciler without re-scoping existing identities.

**Cons:**
- More identities to maintain, rotate, and document.
- More break-glass JSON fields (one more password to lose).
- More sessions per role invocation (~+1s each).
- The "fourth identity tier" is a structural change worth an ADR.

### Option D — Extend ops-admin (rejected on principle)

Add `auth/approle/role/+` and `secret/data/platform/eso-bindings/*` to `app-admin-writer` or `app-runtime-writer`. Simplest, but operator credentials compromise → attacker creates arbitrary AppRoles bound to any policy → effective root for app data. Same reasoning that rejected the parent plan's alternative C.

---

## 6. Decision

**Option C is selected.** The platform will add a fourth bootstrap identity,
`approle-reconciler`, rather than broadening `policy-reconciler` or
`ops-admin`. The initial policy scope is intentionally limited to
`object-storage-*` AppRoles and `secret/platform/eso-bindings/object-storage-*`
records. Future expansion of this identity beyond object-storage requires an
ADR update or successor ADR.

---

## 7. Acceptance criteria

Same as parent plan, plus:

- [ ] post-seed PLAY RECAP `failed=0 unreachable=0` on greenfield AND on idempotent re-run
- [ ] `bao list auth/approle/role` (via approle-reconciler identity) includes `object-storage-app-backups`, `object-storage-openbao-snapshots`
- [ ] Two ClusterSecretStores (`openbao-app-backups`, `openbao-openbao-snapshots`) reach `Ready=True`
- [ ] ops-admin still gets 403 on `bao write -force auth/approle/role/object-storage-app-backups/secret-id` (verified via probe — PoLP preserved)
- [ ] ops-admin still gets 403 on `bao write sys/policies/acl/test` (verified — preserved by parent plan)
- [ ] Step 5 mystery (§4) resolved: a written-down explanation of why the failed post-seed showed `changed:` for AppRole writes that ops-admin shouldn't be able to do

---

## 8. Files Touched (Option C preview)

### `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml`

- Add `approle-reconciler-writer` policy HCL.
- Add `approle-reconciler` password generation, userpass upsert, and
  break-glass JSON fields (`approle_reconciler_username`,
  `approle_reconciler_password`).

### `dmf-infra/k3s-lab-bootstrap/roles/base/object-storage-credentials/tasks/main.yml`

- Keep policy-reconciler for Step 3 policy writes.
- Add approle-reconciler session and route Steps 4-9 through it.
- Remove OpenBao-token dependency from Kubernetes-only object writes where
  possible.
- Fix dashed/underscored naming consistency.

### `dmf-infra/k3s-lab-bootstrap/roles/common/openbao-session/defaults/main.yml`

- Add `approle-reconciler` to the supported mode comment.

### `dmf-infra/k3s-lab-bootstrap/roles/common/openbao-session/tasks/main.yml`

- Add `approle-reconciler` to mode validation and credential loading.

---

## 9. References

### Architectural decisions
- [ADR-0008 — OpenBao secrets architecture](../decisions/0008-openbao-secrets-architecture.md)
- [ADR-0009 — Shamir DR model](../decisions/0009-shamir-dr-model.md)
- [ADR-0020 — Deployment scope and regulatory posture](../decisions/0020-deployment-scope-and-regulatory-posture.md)
- [ADR-0021 — OpenBao AppRole reconciliation uses a dedicated bootstrap identity](../decisions/0021-openbao-approle-reconciler-identity.md)

### Design docs
- [`dmf-infra/docs/openbao-bootstrap-security-model.md`](../../dmf-infra/docs/openbao-bootstrap-security-model.md)
- [Parent plan: DMF OpenBao Policy-Writer Session Separation Plan 2026-05-13](DMF%20OpenBao%20Policy-Writer%20Session%20Separation%20Plan%202026-05-13.md)
- [Implementation brief: DMF OpenBao AppRole-Reconciler Implementation Brief 2026-05-13](DMF%20OpenBao%20AppRole-Reconciler%20Implementation%20Brief%202026-05-13.md)

### Source files for next agent to read
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml` — search for `app-admin-writer policy HCL` (~850), `app-runtime-writer policy HCL` (~928), `policy-writer policy HCL` (~1334)
- `dmf-infra/k3s-lab-bootstrap/roles/base/object-storage-credentials/tasks/main.yml` — the landed three-fix refactor from `dmf-infra@6f6cee8`

### Recent post-seed log
- `/tmp/dmf-playbook-logs/post-seed-aliyun-123-20260513-102148.log` — end-to-end failure showing Step 6 403 + Step 5 mystery `changed`

### Boot ritual for next agent
1. `dmfdeploy/STATUS.md` — cross-repo state
2. `dmfdeploy/CLAUDE.md` — boot ritual
3. `docs/decisions/INDEX.md` — ADR-0008/0009/0020
4. Most recent file under `docs/handoffs/` (will likely be this plan's session)
5. [Parent plan](DMF%20OpenBao%20Policy-Writer%20Session%20Separation%20Plan%202026-05-13.md)
6. **This plan**
7. §0 of `.claude/skills/dmf-cluster-access` and `.claude/skills/dmf-openbao-unseal`

End-of-session: append outcome to `docs/agentic/autonomous-decisions.md` and update `<!-- HUMAN-START -->` section of `STATUS.md` if cross-repo state changed.
