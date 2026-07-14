---
status: historical
date: 2026-05-13
---
# DMF OpenBao Policy-Writer Session Separation Plan — 2026-05-13

**Status:** Proposed
**Owner:** next agent
**Tier:** Tier A (vertical-resilience cannot complete without this)
**Estimated effort:** S (single-day refactor + verify on live cluster)

---

## 1. Tl;DR

`base/object-storage-credentials` post-seed role currently uses
`common/openbao-session` (which always logs in as **ops-admin**) and then
attempts `bao policy write` on a new per-logical-bucket reader policy
(`object-storage-<logical>-reader`). ops-admin's bound policies are
`app-admin-writer + app-runtime-writer + default` — **no
`policy-writer`** — so every `bao policy write` returns 403, failing
post-seed at `vertical-resilience` step 3.

The correct architecture (per
[`dmf-infra/docs/openbao-bootstrap-security-model.md`](https://github.com/dmfdeploy/dmf-infra/blob/main/docs/openbao-bootstrap-security-model.md)
and the openbao role's design intent) keeps ops-admin's permissions
narrow and routes platform-policy management through the dedicated
**policy-reconciler** identity. The bug is purely in
`common/openbao-session`: it exposes only one mode of authentication,
forcing every consumer to use ops-admin even when the consumer is doing
work that should run as policy-reconciler.

The fix is a one-role refactor in `dmf-infra` to make the session role
aware of an `openbao_session_mode` parameter, plus a consumer update in
the object-storage-credentials role to request the policy-reconciler
mode for its two policy-write tasks while keeping ops-admin for the
ESO/AppRole/KV writes.

The live aliyun-123 cluster does **not** need a teardown — the OpenBao
state (root revoked, ops-admin + policy-reconciler users live, all
policies present) already matches the intended design. Only the role
code is wrong. Re-running post-seed after the role fix should land
vertical-resilience cleanly.

---

## 2. Context

### 2.1 What's running today on aliyun-123 (2026-05-13)

OpenBao policies present (verified via policy-reconciler `bao policy list`):
`app-admin-reader, app-admin-writer, app-runtime-writer,
born-inventory-netbox-runtime-reader, default, eso-reader, policy-writer,
root`.

OpenBao userpass users + bound policies (verified via
`bao write -format=json auth/userpass/login/<user> password=…` then
inspecting `auth.token_policies`):

| User | token_policies | Source secret | Purpose |
|---|---|---|---|
| `ops-admin` | `app-admin-writer, app-runtime-writer, default` | JuiceFS `openbao-keys-automation.json` (`ops_admin_password`) + macOS Keychain (operator quorum) | Operator's daily-use identity |
| `policy-reconciler` | `policy-writer, default` (inferred — confirmed by successful `bao policy list` from this user) | JuiceFS `openbao-keys-automation.json` (`policy_reconciler_password`); bootstrap-only — not distributed | Apply/reconcile platform policies on each post-seed |

Root token has been revoked (per
[ADR-0009](../decisions/0009-shamir-dr-model.md) hardening); regenerating
requires the Shamir quorum via `bao operator generate-root`. The plan
explicitly avoids needing root.

### 2.2 Where the role design diverges from the principle

[`dmf-infra/k3s-lab-bootstrap/roles/common/openbao-session/tasks/main.yml`](../../dmf-infra/k3s-lab-bootstrap/roles/common/openbao-session/tasks/main.yml)
always logs in as ops-admin:

```yaml
- name: Log into OpenBao with operator userpass
  ansible.builtin.shell:
    cmd: >-
      ... bao write -format=json auth/userpass/login/{{ _openbao_session_username | quote }} password="$P"
```

…where `_openbao_session_username` is read unconditionally from the
break-glass automation file's `ops_admin_username` field. No
parameterisation, no option to log in as policy-reconciler.

[`dmf-infra/k3s-lab-bootstrap/roles/base/object-storage-credentials/tasks/main.yml`](../../dmf-infra/k3s-lab-bootstrap/roles/base/object-storage-credentials/tasks/main.yml)
includes the session role once and reuses
`_openbao_session_client_token` for every subsequent OpenBao call —
including the two `bao policy write` tasks (lines ~65 and ~81 region).
Those are the calls that fail with 403.

### 2.3 The principle being preserved

`docs/decisions/0008-openbao-secrets-architecture.md` and
`dmf-infra/docs/openbao-bootstrap-security-model.md` codify:

- **Root token is destroyed** after init. Never persisted.
- **ops-admin** is the operator's day-to-day identity. PoLP-narrow:
  read/write per-app admin secrets only (`app-admin-writer`),
  runtime-secret writes (`app-runtime-writer`).
- **policy-reconciler** is a *bootstrap-only* identity whose sole
  capability is `sys/policies/acl/*`. Its password lives in the
  automation file (not in the operator's Keychain quorum) so it cannot
  be invoked outside an automated post-seed run; its TTL is short
  (`token_ttl=1h`); and it has no app-data access.

This separation matches NIST 800-53 AC-5 (separation of duties). If
ops-admin held `policy-writer`, an operator-creds compromise becomes
equivalent to root: the attacker can grant themselves any policy. The
fix must preserve the separation.

### 2.4 Alternatives considered (rejected)

**A. Statically declare object-storage policies in the openbao role.**
Rejected because it forces the openbao role to know every downstream
consumer's policy schema. Adding a new logical bucket requires two-role
edits, and the central role becomes a registry that doesn't match its
single-stack-component scope.

**C. Add `policy-writer` to ops-admin's bound policies.**
Rejected because it collapses the AC-5 separation. Operator creds gain
the ability to rewrite all policies, including `eso-reader` and
`app-admin-writer` itself. Defeats the openbao-bootstrap-security-model
design intent. Acceptable only as an explicit Mode A relaxation under
ADR-0020, which this plan does not invoke.

---

## 3. Goal & non-goals

### Goal

Make `base/object-storage-credentials` (and any future consumer that
needs to write platform policies during post-seed) able to do so via
the policy-reconciler identity, without granting ops-admin any new
capability.

### Non-goals

- **Not** changing the policy-reconciler password lifecycle (still
  bootstrap-only, stored in automation file).
- **Not** changing root-token policy (still revoked at end of init).
- **Not** introducing a fourth identity tier.
- **Not** touching how ESO AppRoles get their reader policies (ESO is
  the *consumer* of these policies, not the writer — and that part of
  the flow already works).
- **Not** addressing the wider question of statically-declared vs
  consumer-declared platform policies. The chosen direction is
  "consumer-declared, written by policy-reconciler"; revisiting that
  is out of scope.

---

## 4. Concrete actions

All paths are relative to the umbrella `dmfdeploy/`.

### 4.1 Refactor `common/openbao-session` — `dmf-infra`

File: `dmf-infra/k3s-lab-bootstrap/roles/common/openbao-session/defaults/main.yml`

Add a new variable:

```yaml
# Which OpenBao identity to authenticate as.
#   operator           — ops_admin_username/password from break-glass JSON
#                        (PoLP-narrow: app data only). Default.
#   policy-reconciler  — policy_reconciler_username/password from break-glass JSON
#                        (PoLP-narrow: sys/policies/acl/* only).
# Consumers requiring BOTH must call this role twice with different modes
# and capture _openbao_session_client_token into per-mode local facts
# between calls.
openbao_session_mode: operator
```

File: `dmf-infra/k3s-lab-bootstrap/roles/common/openbao-session/tasks/main.yml`

The existing logic loads `_openbao_session_username` and
`_openbao_session_password` from the break-glass JSON's
`ops_admin_username` + `ops_admin_password` fields. Replace those
two `set_fact` lines (around line 12–18) with a conditional that picks
the right field pair based on `openbao_session_mode`:

```yaml
- name: Load OpenBao session credentials from break-glass JSON
  ansible.builtin.set_fact:
    _openbao_session_username: >-
      {{
        (_openbao_session_breakglass.ops_admin_username | default(''))
        if openbao_session_mode == 'operator'
        else (_openbao_session_breakglass.policy_reconciler_username | default('policy-reconciler'))
      }}
    _openbao_session_password: >-
      {{
        (_openbao_session_breakglass.ops_admin_password | default(''))
        if openbao_session_mode == 'operator'
        else (_openbao_session_breakglass.policy_reconciler_password | default(''))
      }}
  no_log: true
```

The downstream tasks (Discover OpenBao pod, Log in, Extract token) need
no changes — they consume `_openbao_session_username` /
`_openbao_session_password` as-is.

Also add a guard near the existing `Assert OpenBao operator credentials
are available` task to give a clear error if the requested mode's
creds are missing in the break-glass JSON:

```yaml
- name: Assert OpenBao session credentials are available
  ansible.builtin.assert:
    that:
      - _openbao_session_username | length > 0
      - _openbao_session_password | length > 0
    fail_msg: >-
      No {{ openbao_session_mode }} credentials found in
      {{ openbao_session_breakglass_file }}. For mode=policy-reconciler,
      the break-glass JSON must contain `policy_reconciler_password` (and
      optionally `policy_reconciler_username`, defaulting to
      'policy-reconciler'). Re-run the openbao role's policy reconciliation
      bootstrap if the field is absent.
  no_log: true
```

### 4.2 Update `base/object-storage-credentials` — `dmf-infra`

File: `dmf-infra/k3s-lab-bootstrap/roles/base/object-storage-credentials/tasks/main.yml`

The role currently includes `common/openbao-session` once at the top
(line ~16) and uses `_openbao_session_client_token` everywhere. Replace
that pattern with **two** session loads, captured into per-mode facts:

```yaml
- name: Establish OpenBao operator session (for KV reads + ESO Secret writes)
  ansible.builtin.include_role:
    name: common/openbao-session
  vars:
    openbao_session_mode: operator

- name: Capture operator session into role-scoped facts
  ansible.builtin.set_fact:
    _osc_pod: "{{ _openbao_session_pod }}"
    _osc_operator_token: "{{ _openbao_session_client_token }}"
  no_log: true

- name: Establish OpenBao policy-reconciler session (for sys/policies/acl writes)
  ansible.builtin.include_role:
    name: common/openbao-session
  vars:
    openbao_session_mode: policy-reconciler

- name: Capture policy-reconciler session into role-scoped facts
  ansible.builtin.set_fact:
    _osc_policy_token: "{{ _openbao_session_client_token }}"
  no_log: true
```

Then thread the right token into each task:

- "Write OpenBao reader policy HCL for `<logical>` in pod" — uses
  no-token (kubectl exec only). Keep as-is.
- "Apply OpenBao reader policy for `<logical>`" — change
  `OPENBAO_TOKEN: "{{ _openbao_session_client_token }}"` to
  `OPENBAO_TOKEN: "{{ _osc_policy_token }}"`.
- All subsequent tasks that referenced `_openbao_session_client_token`
  (AppRole creation, secret-id storage, ESO Secret writes, etc.) →
  change to `_osc_operator_token`.
- Tasks referencing `_openbao_session_pod` → change to `_osc_pod`.

Audit the full task list to ensure no `_openbao_session_*` references
remain after the change. Each reference should be replaced by either
`_osc_operator_token`, `_osc_policy_token`, or `_osc_pod` depending on
intent.

### 4.3 Verify the rest of the post-seed import chain

File: `dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml`

The vertical-resilience track imports `base/object-storage-credentials`
once and a few `vertical-resilience/*` playbooks after it. No changes
needed — those downstream consumers don't write policies (they read
ESO-managed Secrets created by the fixed role).

Grep for other consumers of `_openbao_session_client_token` to confirm
no other role is affected by the change. The fix is backward-compatible
because the default mode remains `operator`.

```bash
cd dmf-infra/k3s-lab-bootstrap/roles
grep -rn '_openbao_session_client_token\|openbao-session' .
```

Expected: only the object-storage-credentials role uses both modes;
other consumers (e.g., `stack/operator/cms`, dmf-runbooks) continue to
get ops-admin.

### 4.4 Live cluster verification (aliyun-123)

After committing the role changes:

```bash
cd $DMFDEPLOY_UMBRELLA/dmf-env
source ~/.config/dmf/env
RUNBOOK_TIMEOUT=5400 bin/run-playbook.sh aliyun-123 \
  $DMFDEPLOY_UMBRELLA/dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml
```

Expected: object-storage-credentials role completes; vertical-resilience
verify play passes; post-seed reaches PLAY RECAP failed=0.

If a previous (failed) run left half-written state (e.g., the
`bao policy write` succeeded with policy-reconciler manually before
the fix shipped), the policies are idempotent — re-running will
overwrite identically and continue. No cluster teardown required.

### 4.5 Verify and document

- Confirm `bao policy list` (run as policy-reconciler) now includes
  `object-storage-audit-reader`, `object-storage-openbao-snapshots-reader`,
  `object-storage-app-backups-reader`.
- Confirm ESO ClusterSecretStores `openbao-audit`,
  `openbao-openbao-snapshots`, `openbao-app-backups` reach `Ready=True`.
- Confirm the consumer namespaces (longhorn-system / openbao /
  vertical-resilience / etc.) have ExternalSecrets reconciled.

Once green, append a one-line entry to
`docs/agentic/autonomous-decisions.md` (or a short handoff under
`docs/handoffs/`) recording the structural choice; no new ADR needed
because this is implementation alignment with ADR-0008.

---

## 5. Acceptance criteria

A fresh `aliyun-123` (or any greenfield env) running post-seed end-to-end:

- [ ] `base/object-storage-credentials` role completes with no
      `permission denied` failures.
- [ ] OpenBao `bao policy list` (as policy-reconciler) returns the
      three `object-storage-*-reader` policies.
- [ ] OpenBao `bao token capabilities <ops-admin token> sys/policies/acl/test`
      returns `deny` (PoLP preserved — ops-admin still cannot write
      policies).
- [ ] OpenBao `bao token lookup` on a fresh ops-admin login shows
      `token_policies = [app-admin-writer, app-runtime-writer, default]`
      (unchanged).
- [ ] OpenBao `bao token lookup` on a fresh policy-reconciler login
      shows `token_policies` includes `policy-writer` (unchanged).
- [ ] ESO ClusterSecretStores for the three object-storage logicals
      reach `Ready=True`.
- [ ] `vertical-resilience/*` verify plays (synthetic round-trip,
      Object Lock test) pass.
- [ ] post-seed PLAY RECAP shows `failed=0 unreachable=0`.
- [ ] `grep -rn _openbao_session_client_token dmf-infra/k3s-lab-bootstrap/roles/base/object-storage-credentials/` returns nothing
      (i.e., the role has migrated fully to `_osc_*_token`).

---

## 6. Risk

- **Backward compatibility:** the openbao-session role's default mode
  remains `operator`, so every other consumer continues to behave
  identically. Only object-storage-credentials changes call shape.
- **Double login overhead:** the object-storage-credentials role now
  does two userpass logins instead of one (~+1s wall-clock). Acceptable
  for a once-per-post-seed bootstrap role.
- **Break-glass JSON schema dependency:** the policy-reconciler login
  path requires `policy_reconciler_password` (and optionally
  `policy_reconciler_username`) in the break-glass automation JSON.
  The openbao role's init flow already writes these fields (see
  `roles/stack/operator/openbao/tasks/main.yml` "Compose break-glass
  JSON content" task). Verify the field is present on every env the
  plan applies to.
- **Live aliyun-123:** the cluster's OpenBao state is consistent with
  the new design (policy-reconciler exists and works). No teardown
  required. If the live state had been mutated (e.g., someone added
  `policy-writer` to ops-admin out-of-band), revert that
  out-of-band change with a fresh ops-admin user-policy write via
  policy-reconciler — but only after `auth/userpass/users/*` write
  capability is mediated through the same separation principle (which
  it currently is not; that's a future plan, not this one).

---

## 7. References

### Architectural decisions

- [ADR-0008 — OpenBao secrets architecture](../decisions/0008-openbao-secrets-architecture.md)
- [ADR-0009 — Shamir DR model](../decisions/0009-shamir-dr-model.md) (root revocation rationale)
- [ADR-0020 — Deployment scope and regulatory posture](../decisions/0020-deployment-scope-and-regulatory-posture.md) (Mode A vs Mode B framing — this plan applies to all modes)

### Design docs

- [`dmf-infra/docs/openbao-bootstrap-security-model.md`](https://github.com/dmfdeploy/dmf-infra/blob/main/docs/openbao-bootstrap-security-model.md) — separation-of-duties principle this plan upholds
- [DMF Pre-Bao Bootstrap Secrets Design 2026-05-08](DMF%20Pre-Bao%20Bootstrap%20Secrets%20Design%202026-05-08.md) — bootstrap-admin shared identity (orthogonal to this plan)

### Source files to touch

- `dmf-infra/k3s-lab-bootstrap/roles/common/openbao-session/defaults/main.yml`
- `dmf-infra/k3s-lab-bootstrap/roles/common/openbao-session/tasks/main.yml`
- `dmf-infra/k3s-lab-bootstrap/roles/base/object-storage-credentials/tasks/main.yml`

### Source files referenced (read-only)

- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml` — search for "policy-writer policy" and "Upsert policy-reconciler userpass user" (~lines 1334–1390) to confirm the policy-reconciler design is as described
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml` — "Compose break-glass JSON content" task to confirm `policy_reconciler_password` is written to the automation file
- `dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml` — to confirm the vertical-resilience import chain

### Live cluster context (aliyun-123, valid as of 2026-05-13)

- ops-admin policies: `app-admin-writer, app-runtime-writer, default`
- policy-reconciler policies: `policy-writer, default` (via token introspection)
- All eight expected platform policies present in OpenBao
- Three Longhorn-backed app PVCs healthy: openbao 5G, zot 20G,
  authentik-postgresql 8G; prometheus 5G + loki 5G after the Mode A
  experiment-phase shrink
- The failing post-seed task that motivated this plan: `base/object-storage-credentials : Apply OpenBao reader policy for <logical>` → 403 permission denied

### Recent handoffs (most recent first; for session context)

- [DMF Tier A Phase 3 Wrap + Init Wizard + aliyun-123 Greenfield Handoff 2026-05-12](../handoffs/DMF%20Tier%20A%20Phase%203%20Wrap%20%2B%20Init%20Wizard%20%2B%20aliyun-123%20Greenfield%20Handoff%202026-05-12.md) — Phase 3 vertical-resilience scope including object-storage-credentials role intent
- [DMF Tier A Phase 3 Implementation Handoff 2026-05-12](../handoffs/DMF%20Tier%20A%20Phase%203%20Implementation%20Handoff%202026-05-12.md)

### Boot ritual for fresh agent

Read in this order before touching any code:

1. `dmfdeploy/STATUS.md` — cross-repo state
2. `dmfdeploy/CLAUDE.md` — boot ritual + workspace map
3. `docs/decisions/INDEX.md` — ADR list, with attention to ADR-0008, 0009, 0020
4. *(amended R4, 2026-07-14: this step originally pointed at the latest
   committed handoff file; read the claimed tracking issue's comments
   instead — `docs/handoffs/` is a frozen archive)*
5. This plan
6. For cluster ops: §0 of `.claude/skills/dmf-cluster-access/` skill
7. For OpenBao: §0 of `.claude/skills/dmf-openbao-unseal/` skill

End-of-session: append a one-line outcome to
`docs/agentic/autonomous-decisions.md` and update the
`<!-- HUMAN-START -->` section of `STATUS.md` if cross-repo state
changed.
