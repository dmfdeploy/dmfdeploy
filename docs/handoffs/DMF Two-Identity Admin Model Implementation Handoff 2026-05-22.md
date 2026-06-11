# DMF Two-Identity Admin Model — Implementation Handoff

**Date:** 2026-05-22
**Author:** session that surfaced the 697-cms-awx-token 401 failure on `g2r6-foa9`, ran the two-identity model design-vs-state survey, and wrote ADR-0024 stub
**For:** the next session/agent that will land ADR-0024 + the helper role + per-app adoption + smoke test

> 🛑 **READ THE THREE PRIOR DESIGN/AUDIT DOCS FIRST** (linked below in §Required reads).
> The two-identity model is documented from 2026-05-07; this handoff knits the
> documented intent + observed drift + the open ADR-0024 reservation into one
> executable plan. Skipping the priors risks re-litigating decisions that are
> already made.

---

## TL;DR

The DMF Platform's app-admin identity is **two identities sharing one human**:

1. **Local admin** — uniform username and password across every app that has a
   local admin surface. Set by the wizard from `OPERATOR_USERNAME`; written
   to the SOPS bundle as `bootstrap_admin.username`; exported to Ansible as
   `vault_bootstrap_admin_username`. Purpose: pre-Authentik bootstrap +
   break-glass after OIDC is live.

2. **OIDC user** — same human, same name, enrolled in Authentik via passkey
   (`authentik_bootstrap_passkey_username` = `OPERATOR_USERNAME`); mapped to
   the `ops-admin` group; projected as admin/superadmin across each
   OIDC-backed app via the blueprint at
   `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/20-app-providers.yaml.j2`.
   Purpose: day-to-day SSO across all apps.

**Three sanctioned exceptions** (apps that deliberately do NOT use
`vault_bootstrap_admin_username` for their local admin):

- **Authentik** — `akadmin` (Authentik bootstrap convention; humans never log
  in as this; they enroll a passkey under `authentik_bootstrap_passkey_username`).
- **Zot** — `admin` (htpasswd format constraint + 2026-05-14 bug-fix
  comment trail at `roles/stack/operator/zot/defaults/main.yml:25-38`).
- **Grafana** — `admin` (Helm chart default; OIDC is the day-to-day path).

Today's `bootstrap-configure.yml` failure on `g2r6-foa9` at
`697-cms-awx-token.yml:121` (HTTP 401 because the playbook sent
`awx-local-admin:<password>` instead of the deployed `<operator-user>:<password>`)
is the proximate trigger. The fallback chain in 697 is the only role-level
divergence from the design across the whole `dmf-infra` tree.

This handoff ships five deliverables:

1. **ADR-0024** — formal codification of the model + the live-state read pattern for drift envs.
2. **PR1 (same-day g2r6-foa9 unblock)** — 1-line fallback-chain fix in `697-cms-awx-token.yml`.
3. **PR2** — new helper role `roles/common/admin-identity-resolve/` + adoption in AWX-integration / NetBox / Forgejo.
4. **Smoke-test playbook** — read-only OIDC bridge assertions.
5. **STATUS.md update** — record completion in the umbrella's HUMAN-START section.

---

## Why now / triggering failure

`bootstrap-configure.yml` ran on `g2r6-foa9` and progressed FAR past where it
was failing yesterday (the AWX catalog JT create step cleared after the
dmf-runbooks GitHub publish and cluster Forgejo mirror landed — see
[Path A handoff](DMF%20dmf-runbooks%20Public%20Publish%20Path%20A%20Handoff%202026-05-21.md)).
570 ok / 16 changed / 138 skipped on the control node before failing at:

```
TASK [Lookup AWX service user]
fatal: g2r6-foa9-node-01: HTTP 401
URL: https://awx.<cluster-domain>/api/v2/users/?username=dmf-cms-svc
detail: "Authentication credentials were not provided."
```

Verified empirically by `curl` against the AWX API with HTTP Basic auth:
`awx-local-admin` returns 401; the operator's bootstrap-admin username
returns 200, using the **same** password from the K8s Secret. The Secret
at `awx/awx-admin-password` holds the right password; the playbook just
sends the wrong username. Survey of the wider tree found this is the ONLY
role-level divergence — every other admin chain correctly resolves
`vault_bootstrap_admin_username` to the operator's identity.

---

## Required reads (in order)

1. **`docs/plans/DMF Pre-Bao Bootstrap Secrets Design 2026-05-08.md`** —
   especially §3 "One shared bootstrap admin identity" (lines 166-200).
   The canonical design statement.
2. **`docs/plans/DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md`** —
   the operational record of drift on `aliyun-123` + the Path 1/2/3 framing
   for remediation.
3. **`docs/plans/DMF Aliyun-123 Lifecycle-Configure Follow-Ups Plan 2026-05-17.md`**
   §B.1 (lines ~210-224) — proposes the ADR-0024 title and scope.
4. **`docs/decisions/0000-template.md`** — ADR template.
5. **`docs/decisions/INDEX.md:48`** — the ADR-0024 reservation row to update
   from "Reserved" → "Proposed" → "Accepted".
6. **`docs/decisions/0021-openbao-approle-reconciler-identity.md`** and
   **`docs/decisions/0008-openbao-secrets-architecture.md`** — adjacent
   identity ADRs; their tone + length sets the bar.
7. **`docs/decisions/0007-secrets-never-in-argv.md`** — affects how the
   helper reads + decodes K8s Secret values (`no_log: true`, no argv).
8. **`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml`**
   lines 57-65 — the existing Path 3 template
   (`awx_integration_read_admin_password_from_cluster=true`, secret-ns,
   secret-name vars).
9. **`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml`**
   — find the existing tasks gated on that flag; that's the pattern the new
   helper generalizes.
10. **`dmf-infra/CLAUDE.md`** — STATUS.md update convention + canonical entry
    rules (ADR-0010, `bin/run-playbook.sh`).

---

## Coordination

- **Path A claude** (tmux pane `claude` in `agent-bridge`) landed dmf-infra
  commit `a604812` (Forgejo migrate-API fix) earlier today as part of
  publish + mirror work. **Rebase on Path A's tip**, do not parallel-branch.
- **Operator's interim mirror config on g2r6-foa9** was applied via API call
  from the workstation pane; it persists in the cluster Forgejo but doesn't
  touch dmf-infra. Ignore.
- This handoff's PR2 touches `forgejo/tasks/main.yml` or `forgejo-bootstrap/tasks/main.yml`
  (whichever resolves the admin user) — if Path A is concurrently editing
  the same file, coordinate via `agent-bridge send claude` before opening
  the edit.

---

## Authoritative source map (current state)

All paths relative to `$DMFDEPLOY_UMBRELLA` (the umbrella workspace root).
In-repo paths use the `dmf-infra/k3s-lab-bootstrap/` prefix.

| App | Role default for admin user | Current g2r6-foa9 deployed value | Status |
|---|---|---|---|
| **AWX** | `roles/stack/operator/awx/defaults/main.yml:8` → `vault_bootstrap_admin_username \| default('dmfadmin')` | `<operator-user>` | ✅ matches design |
| **AWX-integration** | `roles/stack/operator/awx-integration/defaults/main.yml:57` | inherits | ✅ has existing Path 3 template at lines 59-65 |
| **697 cms-awx-token** | `playbooks/697-cms-awx-token.yml:121` → `awx_admin_user \| default('awx-local-admin')` | sends wrong user → 401 | ❌ **THE BUG** |
| **NetBox** | `roles/stack/operator/netbox/defaults/main.yml:5` | `<operator-user>` (g2r6-foa9); `admin` (aliyun-123 — drift) | ✅ g2r6-foa9 / ❌ aliyun-123 drift |
| **Forgejo** | `roles/stack/operator/forgejo/defaults/main.yml:38` | `<operator-user>` (g2r6-foa9); legacy username on drift envs | ✅ g2r6-foa9 / ❌ drift |
| **Authentik** | `roles/stack/operator/authentik/defaults/main.yml:59` — hardcoded `akadmin` | `akadmin` | ✅ sanctioned exception |
| **Zot** | `roles/stack/operator/zot/defaults/main.yml:39` — hardcoded `admin` | `admin` | ✅ sanctioned exception |
| **Grafana** | Helm chart default `admin` | `admin` | ✅ sanctioned exception |
| **Prometheus** | n/a (no local user) | n/a | n/a |
| **dmf-cms** | OIDC-only (`cms_dev_login_enabled: false`) | n/a | n/a |

OIDC half lives at:
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/20-app-providers.yaml.j2`
— defines clients for AWX (SAML), NetBox, Forgejo, Grafana, Zot, dmf-cms;
all map the `ops-admin` group to each app's admin role.

---

## Per-env reconciliation matrix

| Env | Current state | Action |
|---|---|---|
| **g2r6-foa9** | Greenfield (bootstrapped 2026-05-21). Deployed admin = `<operator-user>` matches design. Only the 697 playbook fallback chain is wrong. | **PR1 only.** No drift; no Path 3 needed; just fix 697. |
| **aliyun-123** | Documented drift on AWX (legacy username + password mismatch), NetBox (`admin` user), Forgejo (legacy username). Path 1/2 workarounds in place. See App Admin Drift Audit §3 for the specific accounts. | **PR2 + set `awx_read_admin_from_cluster: true`, `netbox_read_admin_from_cluster: true`, `forgejo_read_admin_from_cluster: true`** in `dmf-env/inventories/aliyun-123/group_vars/all/main.yml`. |
| **hetzner-arm** | Same drift class as aliyun-123 (hand-rolled env, multiple bootstrap-configure runs). | **PR2 + same opt-in flags** in `dmf-env/inventories/hetzner-arm/group_vars/all/main.yml`. |

Per-env workarounds documented in the App Admin Drift Audit
(`docs/plans/DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14.md`
§5 Path 1) become unnecessary once PR2 lands + the flags are set.

---

## Deliverables

### Deliverable 1 — ADR-0024

**Path:** `docs/decisions/0024-two-identity-admin-model.md`

**Status at land time:** Proposed (Accepted after PR2 + one drift env reconciles).

**Skeleton** (mirror the style of ADR-0021):

```markdown
# ADR-0024: Two-identity admin model + live-state read for drift envs

**Status:** Proposed
**Date:** 2026-05-22
**Deciders:** @<operator>, planning session with Claude

## Context
[design intent from Pre-Bao Secrets Design §3; drift reality on aliyun-123;
 today's g2r6-foa9 697 failure as the proximate trigger; ADR-0024 was
 reserved on 2026-05-17 per Aliyun-123 Follow-Ups Plan §B.1]

## Decision
Adopt the two-identity admin model explicitly:

- **Local admin (per-app):** uniform `vault_bootstrap_admin_username` and
  `vault_bootstrap_admin_password` materialized into each app at first
  install via the per-role admin-creation task. Username comes from the
  wizard prompt `OPERATOR_USERNAME`; password is a 32-char random
  generated by the wizard.

- **OIDC user:** the same human enrolled in Authentik under
  `authentik_bootstrap_passkey_username` (= `OPERATOR_USERNAME`), mapped
  to the `ops-admin` group; `ops-admin` projected as admin/superadmin
  across each OIDC-backed app via
  `roles/stack/operator/authentik/templates/blueprints/20-app-providers.yaml.j2`.

- **Sanctioned exceptions:** three apps deliberately do NOT use the
  uniform local admin username — Authentik (`akadmin`), Zot (`admin`),
  Grafana (`admin`). The exceptions are enumerated here; adding a fourth
  requires an amendment.

- **Live-state read pattern for drift envs (Path 3):** per-app
  `*_read_admin_from_cluster=true` flag opts the role into reading the
  deployed admin's username + password from the cluster's K8s Secret at
  runtime, overriding role defaults. Implemented by the
  `roles/common/admin-identity-resolve/` helper. Default false; greenfield
  envs ignore the helper entirely.

## Consequences
- Positive: single source of truth for app admin identity; greenfield
  envs always conform; drift envs reconcile without fresh rollout.
- Negative: one new role + adoption surface; helper task adds one K8s
  Secret read per adopting role when flag is on.
- Neutral: greenfield envs pay no runtime cost; ADR's per-env matrix
  lives in the implementation handoff, not the ADR.

## Alternatives considered
- **Fresh rollout of drift envs.** Heavy. Several hours per env. Rejected;
  ADR doesn't preclude it but makes it optional.
- **Inline live-state reads per role.** Replicates the AWX-integration
  pattern 3×; DRY violation. Helper role chosen instead.
- **Read live state in role defaults.** Default would have runtime cluster
  dependency. Rejected. Opt-in flag preserves the greenfield path.

## Promotion criteria (Proposed → Accepted)
1. PR1 lands; `697-cms-awx-token.yml` succeeds on g2r6-foa9.
2. PR2 lands; AWX-integration / NetBox / Forgejo adopt the helper.
3. At least one drift env (aliyun-123 or hetzner-arm) reconciles via the
   helper (`bootstrap-configure.yml` runs to completion without the prior
   `-e *_admin_user=...` workarounds).

## Cross-references
- ADR-0007 (secrets never in argv) — helper compliance.
- ADR-0010 (run-playbook.sh sanctioned entry).
- ADR-0021 (OpenBao AppRole reconciler identity) — adjacent identity ADR.
- DMF Pre-Bao Bootstrap Secrets Design 2026-05-08 — design source.
- DMF App Admin Account Drift Audit 2026-05-14 — drift catalog.
```

**Also update:** `docs/decisions/INDEX.md` line 48 — change status from `Reserved` to `Proposed` + add a link to the new ADR file.

---

### Deliverable 2 — PR1: 697-cms-awx-token fallback chain fix

**Same-day g2r6-foa9 unblock. No role-API changes. No new dependencies.**

**File:** `dmf-infra/k3s-lab-bootstrap/playbooks/697-cms-awx-token.yml`

**Change** at line 121:

```yaml
# Before:
_cms_awx_admin_user: "{{ awx_admin_user | default('awx-local-admin') }}"

# After:
_cms_awx_admin_user: "{{ awx_admin_user | default(vault_bootstrap_admin_username | default('dmfadmin')) }}"
```

**Rationale:** matches the chain used by `awx/defaults/main.yml:8` and the
rest of the AWX role chain. `'dmfadmin'` ultimate fallback matches role
defaults. `'awx-local-admin'` was an outlier with no precedent.

**Commit message:**

```
fix(697-cms-awx-token): align admin fallback with vault_bootstrap_admin_username

The playbook defaulted _cms_awx_admin_user to the literal
'awx-local-admin' when awx_admin_user was unset — an outlier in the
DMF admin chain, which everywhere else falls back to
vault_bootstrap_admin_username | default('dmfadmin').

On g2r6-foa9 (greenfield env, bootstrapped 2026-05-21), the AWX
deployment correctly uses the operator's identity (the wizard's
OPERATOR_USERNAME → vault_bootstrap_admin_username) as the local
admin username. The 697 playbook sent 'awx-local-admin:<password>'
and AWX returned 401. Direct curl with the operator username + same
password returns 200; the password chain is fine, only the username
fallback was wrong.

Aligns 697 with the design captured in ADR-0024
(two-identity admin model).
```

**Verification** (manual after merge):

```bash
cd ~/repos/dmfdeploy/dmf-env
bin/run-playbook.sh g2r6-foa9 \
  ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml
```

Expect: PLAY RECAP shows `failed=0`; the "Lookup AWX service user" task at
697:279 returns 200 instead of 401; the play advances past 697 into
born-inventory / verify.

---

### Deliverable 3 — PR2: helper role + adoption

**New role:** `dmf-infra/k3s-lab-bootstrap/roles/common/admin-identity-resolve/`

Two files:

#### `defaults/main.yml`

```yaml
---
# admin-identity-resolve — read the live admin user + password from a
# cluster K8s Secret, falling back to the caller's vault_* defaults.
#
# All inputs must be supplied by the caller; this role has no defaults
# (so misuse fails loud rather than picking an unintended Secret).
#
# Inputs (caller-supplied via `vars:`):
#   admin_resolve_app                : free-form app name (used in log msgs)
#   admin_resolve_secret_ns          : K8s namespace containing the Secret
#   admin_resolve_secret_name        : K8s Secret name
#   admin_resolve_username_key       : Secret data key for the username
#                                       (default 'username')
#   admin_resolve_password_key       : Secret data key for the password
#                                       (default 'password')
#   admin_resolve_fallback_username  : value used if Secret missing/incomplete
#   admin_resolve_fallback_password  : value used if Secret missing/incomplete
#
# Outputs (set_fact at end):
#   _resolved_admin_user
#   _resolved_admin_password
#
# ADR-0007 compliance:
#   - Reads via kubernetes.core.k8s_info (delegate_to: k3s_control[0]).
#   - All tasks that touch the password have no_log: true.
#   - Passwords never enter argv.
admin_resolve_username_key: "username"
admin_resolve_password_key: "password"
```

#### `tasks/main.yml`

```yaml
---
- name: "Read live admin Secret for {{ admin_resolve_app }}"
  kubernetes.core.k8s_info:
    kubeconfig: /etc/rancher/k3s/k3s.yaml
    api_version: v1
    kind: Secret
    namespace: "{{ admin_resolve_secret_ns }}"
    name: "{{ admin_resolve_secret_name }}"
  register: _admin_secret_lookup
  delegate_to: "{{ groups['k3s_control'][0] }}"
  no_log: true

- name: "Resolve admin identity from Secret or fallback for {{ admin_resolve_app }}"
  ansible.builtin.set_fact:
    _resolved_admin_user: >-
      {{
        (_admin_secret_lookup.resources[0].data[admin_resolve_username_key] | b64decode)
        if (_admin_secret_lookup.resources | length > 0
            and admin_resolve_username_key in _admin_secret_lookup.resources[0].data)
        else admin_resolve_fallback_username
      }}
    _resolved_admin_password: >-
      {{
        (_admin_secret_lookup.resources[0].data[admin_resolve_password_key] | b64decode)
        if (_admin_secret_lookup.resources | length > 0
            and admin_resolve_password_key in _admin_secret_lookup.resources[0].data)
        else admin_resolve_fallback_password
      }}
  no_log: true

- name: "Log resolved admin source for {{ admin_resolve_app }}"
  ansible.builtin.debug:
    msg: >-
      {{ admin_resolve_app }} admin resolved from
      {{ 'cluster Secret ' ~ admin_resolve_secret_ns ~ '/' ~ admin_resolve_secret_name
         if (_admin_secret_lookup.resources | length > 0)
         else 'fallback (vault_bootstrap_admin_*)' }}.
```

#### Adoption sites (PR2 patches)

In each adopting role, add an `include_role` at the top of `tasks/main.yml`
that gates on the opt-in flag:

##### AWX-integration

`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml`
— replace the existing inline live-state read (search for
`awx_integration_read_admin_password_from_cluster`) with:

```yaml
- name: Resolve AWX admin identity
  ansible.builtin.include_role:
    name: common/admin-identity-resolve
  vars:
    admin_resolve_app: awx
    admin_resolve_secret_ns: "{{ awx_namespace | default('awx') }}"
    admin_resolve_secret_name: "{{ awx_admin_secret_name | default('awx-admin-password') }}"
    admin_resolve_fallback_username: "{{ vault_bootstrap_admin_username | default('dmfadmin') }}"
    admin_resolve_fallback_password: "{{ vault_bootstrap_admin_password | default('') }}"
  when: awx_read_admin_from_cluster | default(false) | bool
```

Then use `_resolved_admin_user` / `_resolved_admin_password` in place of
the existing `awx_integration_admin_user` / `_password` references downstream.
Preserve the existing variable names by setting them from the resolved values:

```yaml
- name: Override awx_integration_admin_* when resolved from cluster
  ansible.builtin.set_fact:
    awx_integration_admin_user: "{{ _resolved_admin_user }}"
    awx_integration_admin_password: "{{ _resolved_admin_password }}"
  when: awx_read_admin_from_cluster | default(false) | bool
  no_log: true
```

##### NetBox

`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox/tasks/main.yml`
(or `netbox-sot/tasks/main.yml` if the admin lookup happens there) — same
pattern, with:

```yaml
admin_resolve_app: netbox
admin_resolve_secret_ns: "{{ netbox_namespace | default('netbox') }}"
admin_resolve_secret_name: "{{ netbox_admin_secret_name | default('netbox-superuser') }}"
```

Opt-in flag: `netbox_read_admin_from_cluster | default(false) | bool`.

##### Forgejo

`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo/tasks/main.yml`
(or `forgejo-bootstrap/tasks/main.yml`) — same pattern, with:

```yaml
admin_resolve_app: forgejo
admin_resolve_secret_ns: "{{ forgejo_namespace | default('forgejo') }}"
admin_resolve_secret_name: "{{ forgejo_admin_secret_name | default('forgejo-admin') }}"
```

Opt-in flag: `forgejo_read_admin_from_cluster | default(false) | bool`.

##### 697-cms-awx-token (supersede PR1's narrow fix)

`dmf-infra/k3s-lab-bootstrap/playbooks/697-cms-awx-token.yml` — replace the
PR1 set_fact at line 121-122 with:

```yaml
- name: Resolve AWX admin identity for CMS token provisioning
  ansible.builtin.include_role:
    name: common/admin-identity-resolve
  vars:
    admin_resolve_app: awx-for-cms-token
    admin_resolve_secret_ns: "{{ cms_awx_namespace | default('awx') }}"
    admin_resolve_secret_name: "{{ cms_awx_admin_secret_name | default('awx-admin-password') }}"
    admin_resolve_fallback_username: "{{ awx_admin_user | default(vault_bootstrap_admin_username | default('dmfadmin')) }}"
    admin_resolve_fallback_password: "{{ vault_bootstrap_admin_password | default('') }}"
- name: Alias resolved values to playbook's local fact names
  ansible.builtin.set_fact:
    _cms_awx_admin_user: "{{ _resolved_admin_user }}"
    _cms_awx_admin_password: "{{ _resolved_admin_password }}"
  no_log: true
```

The helper always runs here (no opt-in flag) because 697 needs to work
across both greenfield (Secret present, helper reads it) and drift envs
(Secret may have a different username) — the helper handles both with
the same code path.

#### Per-env inventory updates (PR2)

For drift envs, add the opt-in flags to the env's `group_vars/all/main.yml`:

`dmf-env/inventories/aliyun-123/group_vars/all/main.yml`:
```yaml
# ADR-0024: read live admin identity from cluster Secrets (drift env)
awx_read_admin_from_cluster: true
netbox_read_admin_from_cluster: true
forgejo_read_admin_from_cluster: true
```

`dmf-env/inventories/hetzner-arm/group_vars/all/main.yml`: same.

Greenfield envs (g2r6-foa9, future wizard-generated envs) leave the flags
unset / false; they use the wizard-set `vault_*` chain as before.

---

### Deliverable 4 — Smoke-test playbook for the OIDC bridge

**New file:** `dmf-infra/k3s-lab-bootstrap/playbooks/verify-oidc-admin-bridge.yml`

**Scope:** assertion-only. Read group memberships + client provisioning via
the Authentik API. No mutations. No headless browser. No login round-trip
— that's a follow-on workstream.

Per-app checks:

1. The operator's Authentik user (resolved from
   `authentik_bootstrap_passkey_username`) is a member of `ops-admin`.
2. For each app in `[awx, netbox, forgejo, grafana, zot, dmf-cms]`: the
   OIDC client is provisioned in Authentik (GET via Authentik API).
3. For each app: the blueprint's mapping from `ops-admin` to the app's
   admin role is present.

**Tag:** `vertical-identity`. Tag wires it into a future
`bootstrap-verify.yml` vertical-identity sweep without changing existing
verify behavior.

**Auth pattern:** read Authentik admin token from OpenBao via
`bin/get-admin-cred.sh <env> authentik`. Per ADR-0007, use the token via
`Authorization: Bearer ...` header passed via `headers:` (never argv).

**Run via:**

```bash
bin/run-playbook.sh <env> \
  ../dmf-infra/k3s-lab-bootstrap/playbooks/verify-oidc-admin-bridge.yml
```

**Expected output:** every check returns "OK"; the closing debug task
summarizes "OIDC bridge verified for N apps".

---

### Deliverable 5 — STATUS.md update

`STATUS.md` in the umbrella has a `<!-- HUMAN-START -->` section
(per `dmf-infra/CLAUDE.md` convention). After all four deliverables land,
update it with a short note:

```
- ADR-0024 (two-identity admin model + live-state read) landed
  2026-05-22. g2r6-foa9 unblocked via PR1; drift envs reconcile via
  PR2's helper role + opt-in flags in dmf-env inventory.
```

---

## Verification

### Per-deliverable

**ADR-0024:** `gitleaks protect --staged` clean; `docs/decisions/INDEX.md`
shows the updated row with status `Proposed`.

**PR1:** `bash -n dmf-infra/k3s-lab-bootstrap/playbooks/697-cms-awx-token.yml`
clean. Then:

```bash
cd ~/repos/dmfdeploy/dmf-env
bin/run-playbook.sh g2r6-foa9 \
  ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml
```

Expect: PLAY RECAP `failed=0`. 697's "Lookup AWX service user" returns 200.

**PR2:** YAML-parse all touched files. Then on a drift env (aliyun-123):

```bash
bin/run-playbook.sh aliyun-123 \
  ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml
```

Expect: the helper's "Log resolved admin source" task fires for AWX,
NetBox, Forgejo. Each shows "resolved from cluster Secret <ns>/<name>".
PLAY RECAP `failed=0`. The previously-required `-e *_admin_user=...`
workarounds (documented in the App Admin Drift Audit §5 Path 1) no longer
needed.

**Smoke-test playbook:**

```bash
bin/run-playbook.sh g2r6-foa9 \
  ../dmf-infra/k3s-lab-bootstrap/playbooks/verify-oidc-admin-bridge.yml
```

Expect: all asserts pass; debug task confirms OIDC bridge for 6 apps.

### Per-env reconciliation

| Env | Verify command | Expected |
|---|---|---|
| g2r6-foa9 | `bin/run-playbook.sh g2r6-foa9 ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml` | clears 697; runs to verify |
| aliyun-123 | same, with PR2 + opt-in flags | helper resolves cluster admin; no `-e` overrides needed |
| hetzner-arm | same, with PR2 + opt-in flags | same |

---

## Sequencing recommendation

**Land in this order:**

1. **PR1 same day** (g2r6-foa9 unblock; ~3 lines + commit message; no review burden). Operator can re-run `bootstrap-configure.yml` immediately after.
2. **ADR-0024 + Deliverable 5 STATUS bump** in a second commit (docs-only). Status: Proposed.
3. **PR2** as a follow-on session — helper role + 3-role adoption + drift-env opt-in flags. Larger; warrants its own review pass.
4. **Smoke-test playbook** alongside PR2 (or immediately after). Same review pass.
5. After PR2 + smoke-test land + aliyun-123 reconciles via the helper: ADR-0024 status → Accepted; STATUS update.

The PR1 unblock is genuinely 1-line; do it first regardless of when PR2 is ready.

---

## Out of scope / explicit deferrals

- **Wizard prompt help-text** clarifying the two-identity model — UX nicety; not blocking.
- **Wizard password-length prompt** — current 32-char random is fine.
- **Grafana SSO admin user alignment** — currently `admin`; sanctioned exception per ADR-0024. Could be brought into the uniform scheme later if/when a Helm chart override lands. Not a drift issue today.
- **Fresh-rollout policy for drift envs** — ADR-0024 leaves the per-env decision to the operator. Doesn't mandate Path 3 over fresh rollout; just provides Path 3 as a no-fresh-rollout option.
- **OIDC login round-trip test** (the headless-browser path) — the assertion-only smoke test is sufficient for first-pass verification. Real login round-trip is a separate workstream.
- **Per-app password rotation workflow** — orthogonal; covered by ADR-0021 (OpenBao AppRole reconciler identity).
- **`forgejo_seed_repos` fallback for offline operators** — orthogonal; covered by the Path A handoff.

---

## Open questions to confirm with operator at start of session

1. **Helper role at `roles/common/admin-identity-resolve/`** — confirmed in the planning session; ready as-spec.
2. **PR1 + PR2 split** — confirmed split: PR1 same-day, PR2 follow-on.
3. **Smoke-test assertion-only scope** — confirmed assertion-only.
4. **ADR-0024 promotion criteria** — three explicit gates (PR1 + PR2 + one drift env reconciles); operator may want to refine before landing.

---

## References

- [DMF Pre-Bao Bootstrap Secrets Design 2026-05-08](../plans/DMF%20Pre-Bao%20Bootstrap%20Secrets%20Design%202026-05-08.md) — design source (§3 "One shared bootstrap admin identity")
- [DMF App Admin Account Drift Audit and Realignment Plan 2026-05-14](../plans/DMF%20App%20Admin%20Account%20Drift%20Audit%20and%20Realignment%20Plan%202026-05-14.md) — drift catalog + Path 1/2/3 framing
- [DMF Aliyun-123 Lifecycle-Configure Follow-Ups Plan 2026-05-17](../plans/DMF%20Aliyun-123%20Lifecycle-Configure%20Follow-Ups%20Plan%202026-05-17.md) — ADR-0024 reservation context (§B.1)
- [DMF dmf-runbooks Public Publish Path A Handoff 2026-05-21](DMF%20dmf-runbooks%20Public%20Publish%20Path%20A%20Handoff%202026-05-21.md) — parallel workstream; coordination context
- `docs/decisions/INDEX.md` line 48 — ADR-0024 reservation
- `docs/decisions/0021-openbao-approle-reconciler-identity.md` — adjacent identity ADR
- `docs/decisions/0007-secrets-never-in-argv.md` — affects helper implementation
- `docs/decisions/0010-run-playbook-as-sanctioned-entry.md` — affects smoke-test invocation
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml:57-65` — existing Path 3 template
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/20-app-providers.yaml.j2` — OIDC client + group mapping blueprint

---

**End of handoff.** Resume with §"Required reads", then execute Deliverable 2
(PR1) for the same-day g2r6-foa9 unblock before opening any larger PRs.
