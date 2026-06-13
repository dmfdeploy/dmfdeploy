---
status: executed
date: 2026-05-13
executed: 2026-05-13
---
# DMF OpenBao AppRole-Reconciler Implementation Brief - 2026-05-13

> **SUPERSEDED 2026-05-23** — implementation landed `dmf-infra@209601d`
> on 2026-05-13 (same day this brief was written) and was verified live on
> g2r6-foa9 on 2026-05-23. See
> [`docs/handoffs/DMF OpenBao AppRole-Reconciler Live Verification Handoff 2026-05-23.md`](../handoffs/DMF%20OpenBao%20AppRole-Reconciler%20Live%20Verification%20Handoff%202026-05-23.md)
> for the verification matrix.
>
> **§6 (Existing Cluster Recovery Requirement) remains an active reference**
> — it is the only documented procedure for adding the `approle-reconciler`
> identity to an OpenBao instance that was initialised before
> `dmf-infra@209601d` (2026-05-13). g2r6-foa9 and any future env created
> from a wizard after that date does not need §6. Pre-2026-05-13 clusters
> (none are currently live; aliyun-123 + hetzner-arm + aliyun are retired)
> would.

**Status:** Implementation landed `dmf-infra@209601d` 2026-05-13; verified live on g2r6-foa9 2026-05-23
**Primary repo:** `dmf-infra`
**Umbrella decision:** [ADR-0021](../decisions/0021-openbao-approle-reconciler-identity.md)
**Parent plan:** [DMF OpenBao AppRole-Write Reconciler Plan 2026-05-13](DMF%20OpenBao%20AppRole-Write%20Reconciler%20Plan%202026-05-13.md)

This is the handoff-grade implementation brief for a fresh agent. It assumes no
conversation context beyond the workspace files.

---

## 0. Boot Sequence For The Implementing Agent

Start in the umbrella workspace:

```bash
cd "$DMFDEPLOY_UMBRELLA"
git fetch
git pull --ff-only
bin/generate-status.sh --no-fetch
```

Read in this order:

1. `STATUS.md`, especially the OpenBao identity model note.
2. `CLAUDE.md` and `AGENTS.md`.
3. `docs/decisions/INDEX.md`.
4. `docs/decisions/0007-secrets-never-in-argv.md`.
5. `docs/decisions/0008-openbao-secrets-architecture.md`.
6. `docs/decisions/0009-shamir-dr-model.md`.
7. `docs/decisions/0010-run-playbook-as-sanctioned-entry.md`.
8. `docs/decisions/0021-openbao-approle-reconciler-identity.md`.
9. `dmf-infra/CLAUDE.md` and `dmf-infra/AGENTS.md`.
10. `dmf-infra/docs/openbao-bootstrap-security-model.md`.
11. Parent plan and this brief.

Before editing `dmf-infra`, run:

```bash
git -C dmf-infra status --short
```

If it is dirty, stop and ask the operator unless the dirty files are explicitly
yours from this task.

For live cluster or OpenBao operations, also read the relevant skill sections
before running commands:

- `.claude/skills/dmf-cluster-access`
- `.claude/skills/dmf-openbao-unseal`

Do not use local `kubectl` against the cluster. Use the `dmf-env` wrapper or
commands executed by Ansible on the control node.

---

## 1. Problem Summary

Tier A Phase 3 added `base/object-storage-credentials`, which provisions two
ESO-managed object-storage credential paths:

- `openbao_snapshots`
- `app_backups`

Audit credentials are not ESO-managed; they flow through Phase 1 inventory vars.
Do not add audit to this role.

Commit `dmf-infra@6f6cee8` fixed the first OpenBao permission failure by adding
`openbao_session_mode` and routing `bao policy write` through
`policy-reconciler`. That unblocked Step 3. The next live run on `aliyun-123`
then failed at Step 6:

```text
bao write -force auth/approle/role/object-storage-<name>/secret-id -> 403
```

The root cause is architectural: no existing non-root identity should own
AppRole reconciliation.

Current identity model:

| Identity | Current purpose | Must not do |
|---|---|---|
| `root` | First bootstrap only; revoked afterward | Routine post-seed work |
| `policy-reconciler` | Reapply ACL policy-as-code | AppRole creation, secret data |
| `ops-admin` | App/admin/runtime secret administration | ACL policy writes, AppRole minting |
| ESO AppRoles | Runtime read-only secret sync to K8s | Write anything |
| `approle-reconciler` | New identity from ADR-0021 | ACL policy writes, app secret data |

ADR-0021 chooses Option C: add a dedicated `approle-reconciler` identity for
`object-storage-*` AppRole and ESO binding reconciliation.

---

## 2. Security And Compliance Concepts

The implementation must preserve these concepts:

- **No standing root:** ADR-0009 and the OpenBao bootstrap model treat root as
  first-bootstrap-only material. Existing clusters need a deliberate recovery
  ceremony if a new privileged identity must be added after root revocation.
- **Separation of duties:** ADR-0021 preserves NIST 800-53 AC-5 by keeping ACL
  policy reconciliation, AppRole reconciliation, and app-secret administration
  in separate identities.
- **Least privilege:** `approle-reconciler` starts narrowly scoped to the two
  object-storage AppRoles and their ESO binding records. Do not generalize it to
  all AppRoles without a successor ADR.
- **No secrets in argv:** ADR-0007 still applies. Passwords, tokens, and
  `secret_id` values must be passed via stdin and protected with `no_log: true`
  in committed code.
- **Wrapper-only operations:** ADR-0010 says the environment wrapper is the
  sanctioned entry point for Ansible runs.
- **Mode A today, Mode B later:** ADR-0020 is still Proposed, but the operator
  has answered current public work as Mode A experiment. Option C is chosen
  because it ages better toward Mode B/C security claims without overbuilding
  the rest of the platform today.

Important OpenBao syntax fact: OpenBao policy glob `*` is only supported as the
last character of a policy path. Do not write policy rules such as
`auth/approle/role/object-storage-*/secret-id`. Generate explicit HCL blocks for
each supported logical instead. Reference:
<https://openbao.org/docs/next/concepts/policies/>.

The AppRole API paths for role create/read, role-id, and secret-id are described
in the OpenBao AppRole API docs:
<https://openbao.org/api-docs/auth/approle/>.

---

## 3. Known State And Gotchas

### 3.1 Existing `aliyun-123` state

The failed post-seed run may have left partial state:

- reader policies present;
- possibly two partial AppRoles;
- no ESO binding records;
- no ESO auth Secrets;
- no ClusterSecretStores.

The role already has existence checks for AppRole and binding presence. Preserve
those idempotency gates.

### 3.2 Step 5 mystery

The failed run reported Step 5 as `changed` even though `ops-admin` should not
be able to create AppRoles. Before implementation, resolve this. Plausible
causes from the parent plan:

1. Token capture bug after calling `common/openbao-session` twice.
2. Unexpected in-pod environment behavior.
3. Out-of-band policy drift during the live run.

Do not skip this probe. The result determines whether `6f6cee8` has a latent
token-routing issue.

### 3.3 Naming drift to fix

The current role mixes underscored and dashed names:

- KV data paths must remain underscored to match seed-bao:
  `secret/platform/object-storage/openbao_snapshots`,
  `secret/platform/object-storage/app_backups`.
- AppRole names, policy names, ESO binding names, K8s Secret names, and
  ClusterSecretStore names should use dashed logicals:
  `object-storage-openbao-snapshots`,
  `object-storage-app-backups`,
  `openbao-openbao-snapshots`,
  `openbao-app-backups`.

The key correction is that Step 6 and Step 7/9 must reference the same dashed
AppRole and binding names. Today Step 6 uses an underscored AppRole while Step 5
creates dashed names.

---

## 4. Mandatory Probe Before Code Changes

Use a temporary diagnostic task or throwaway probe playbook. Do not commit it.
If you must temporarily set `no_log: false`, remove it before commit.

Probe goals:

1. Run Step 5's exact AppRole create command under the captured
   `_osc_operator_token`.
2. Run the same command under a freshly logged-in `ops-admin` token that does
   not use the `_osc_operator_token` fact.
3. Capture stdout/stderr and token policy identity enough to explain why the
   failed post-seed showed `changed`.
4. Clean up any `probe-test-*` AppRole if it was created.

Probe command shape inside the OpenBao pod:

```sh
bao write auth/approle/role/probe-test-<random> \
  token_policies=default \
  secret_id_ttl=24h \
  token_ttl=1h \
  token_max_ttl=4h
```

Expected result if the model is intact:

- captured operator token: 403;
- freshly logged-in `ops-admin`: 403;
- `policy-reconciler`: 403 for AppRole paths;
- `policy-reconciler`: allowed for `sys/policies/acl/*`.

If the captured operator token succeeds, fix token capture before adding
`approle-reconciler`. Use explicit per-mode facts and avoid any ambiguous
reference to `_openbao_session_client_token` after subsequent role includes.

Record the explanation in either the parent plan or a short handoff note.

---

## 5. Implementation Steps In `dmf-infra`

### 5.1 Add OpenBao role defaults

File:

```text
dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/defaults/main.yml
```

Add defaults near the policy-reconciler defaults:

```yaml
openbao_approle_reconciler_username: approle-reconciler
openbao_approle_reconciler_policy_name: approle-reconciler-writer
openbao_approle_reconciler_password_length: 32

# Keep this intentionally local to the OpenBao role. If new object-storage
# logicals are added later, update this list and object-storage-credentials
# together, or promote the list to inventory.
openbao_approle_reconciler_object_storage_logicals:
  - openbao_snapshots
  - app_backups
```

Do not reuse `object_storage_logicals` directly unless you verify it is visible
to the OpenBao role in every play. Role defaults are not a reliable cross-role
interface.

### 5.2 Preload and generate the password

File:

```text
dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml
```

In the existing break-glass preload block, add:

```yaml
openbao_approle_reconciler_password: >-
  {{ existing_breakglass.approle_reconciler_password | default('') }}
```

Generate a password only during fresh init, mirroring policy-reconciler:

```yaml
- name: Generate approle-reconciler password only on fresh init
  ansible.builtin.set_fact:
    openbao_approle_reconciler_password: >-
      {{ lookup('password', '/dev/null length=' ~ openbao_approle_reconciler_password_length ~ ' chars=ascii_letters,digits') }}
  when:
    - openbao_approle_reconciler_password | default('') | length == 0
    - not openbao_is_initialized | bool
  no_log: true
```

For an already initialized cluster with no `approle_reconciler_password` in the
break-glass JSON, fail early with a clear message. Do not silently broaden
`policy-reconciler` to create the user. Existing clusters need a one-time
privileged recovery ceremony or a fresh rebuild.

### 5.3 Create the approle-reconciler policy

Add a new HCL write/apply block after the policy-writer policy block.

Generate explicit HCL blocks per logical. Example for the loop body:

```hcl
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

Repeat for `object-storage-openbao-snapshots`. Prefer generating this from
`openbao_approle_reconciler_object_storage_logicals` with Jinja so the two
logical names stay together.

Apply the policy with `_openbao_policy_apply_token`, same as the other ACL
policy writes. On fresh init this is root; on rerun this is policy-reconciler.
That is allowed because this is an ACL policy write, not AppRole creation.

### 5.4 Upsert the userpass user

Fresh init path:

- create `approle-reconciler` with root before root revocation;
- bind it only to `openbao_approle_reconciler_policy_name`;
- use `token_ttl=1h token_max_ttl=4h`, matching policy-reconciler.

Existing initialized cluster path:

- if the break-glass JSON already has `approle_reconciler_password`, verify
  login works;
- if it does not, fail with a precise recovery message.

The failure message should say:

- root is intentionally not preserved;
- ADR-0021 forbids broadening `ops-admin` or `policy-reconciler` for this;
- the operator must run a Shamir-backed privileged recovery ceremony to create
  the userpass user and add the password fields to the break-glass JSON, or
  rebuild the cluster from clean bootstrap.

### 5.5 Persist break-glass fields

In `Compose break-glass JSON content`, add:

```yaml
approle_reconciler_username: "{{ openbao_approle_reconciler_username }}"
approle_reconciler_password: "{{ openbao_approle_reconciler_password }}"
```

Do not write these to inventory, docs, logs, or transcripts. The JSON remains
outside git.

### 5.6 Extend `common/openbao-session`

Files:

```text
dmf-infra/k3s-lab-bootstrap/roles/common/openbao-session/defaults/main.yml
dmf-infra/k3s-lab-bootstrap/roles/common/openbao-session/tasks/main.yml
```

Add `approle-reconciler` to the documented modes and validation.

Avoid a third nested ternary if readability suffers. A small mapping is easier
to audit:

```yaml
_openbao_session_username: >-
  {{
    {
      'operator': _openbao_session_breakglass.ops_admin_username | default(''),
      'policy-reconciler': _openbao_session_breakglass.policy_reconciler_username | default('policy-reconciler'),
      'approle-reconciler': _openbao_session_breakglass.approle_reconciler_username | default('approle-reconciler')
    }[openbao_session_mode]
  }}
```

Do the same for password fields. Update the missing-credentials error so it
names the mode and required break-glass fields.

### 5.7 Rewire `object-storage-credentials`

File:

```text
dmf-infra/k3s-lab-bootstrap/roles/base/object-storage-credentials/tasks/main.yml
```

Use three captured sessions:

- `_osc_policy_token`: Step 3 `bao policy write`.
- `_osc_approle_token`: Steps 4-9 AppRole and ESO binding reads/writes.
- `_osc_operator_token`: only if still truly needed after review. Most K8s
  object writes do not need any OpenBao token.

Recommended routing:

| Step | Operation | Token |
|---|---|---|
| 3 | write reader policies | `_osc_policy_token` |
| 4 | check AppRole role-id | `_osc_approle_token` |
| 4b | check ESO binding | `_osc_approle_token` |
| 5 | create AppRole | `_osc_approle_token` |
| 6 | generate secret-id | `_osc_approle_token` |
| 7 | write ESO binding record | `_osc_approle_token` |
| 8 | read role-id | `_osc_approle_token` |
| 9 | read secret-id binding | `_osc_approle_token` |
| 11-14 | K8s Secret / TLS read / ClusterSecretStore / ExternalSecret | Kubernetes API only |

Fix naming while rewiring:

```yaml
logical_dashed: "{{ logical | replace('_', '-') }}"
approle_name: "object-storage-{{ logical_dashed }}"
reader_policy_name: "object-storage-{{ logical_dashed }}-reader"
binding_name: "object-storage-{{ logical_dashed }}"
data_path: "secret/platform/object-storage/{{ logical }}"
```

Use those derived names consistently. The data path remains underscored; the
AppRole, policy, and binding names are dashed.

### 5.8 Update docs in `dmf-infra`

Update:

```text
dmf-infra/docs/openbao-bootstrap-security-model.md
dmf-infra/k3s-lab-bootstrap/roles/base/object-storage-credentials/README.md
```

The security model should mention `approle-reconciler` as:

- bootstrap-only;
- AppRole + ESO binding reconciliation only;
- no ACL policy writes;
- no app secret data.

The role README should fix the existing typo `app_backouts` and document dashed
AppRole/binding names versus underscored data paths.

---

## 6. Existing Cluster Recovery Requirement

This is the main operational trap.

Fresh greenfield clusters are easy: root exists during first init, so the role
can create `approle-reconciler` before root is revoked.

Existing clusters such as `aliyun-123` already revoked root and do not have
`approle-reconciler`. The normal non-root identities cannot create the new
userpass user without violating ADR-0021.

Therefore the live path must be one of:

1. **Preferred:** one-time Shamir-backed privileged recovery ceremony, using the
   `dmf-openbao-unseal`/OpenBao recovery workflow, to create
   `approle-reconciler` and update the break-glass JSON. Do not preserve the
   generated root token.
2. **Alternative:** rebuild the OpenBao instance or cluster from clean
   bootstrap with the new code.

Do not implement a workaround that permanently adds `auth/userpass/users/*` or
AppRole creation powers to `policy-reconciler` or `ops-admin`.

If adding an automated recovery path, gate it with an explicit variable and make
the privileged token a transient operator-provided value with `no_log: true`.
Do not write the token into inventory, argv, or docs.

---

## 7. Verification Plan

### 7.1 Static checks

From the umbrella:

```bash
git -C dmf-infra diff --check
```

Run syntax checks through the environment wrapper where possible. Example shape:

```bash
cd "$DMFDEPLOY_UMBRELLA/dmf-env"
bin/run-playbook.sh aliyun-123 ../dmf-infra/k3s-lab-bootstrap/playbooks/vertical-security/100-openbao.yml --syntax-check
bin/run-playbook.sh aliyun-123 ../dmf-infra/k3s-lab-bootstrap/playbooks/vertical-resilience/100-object-storage-credentials.yml --syntax-check
```

If the wrapper does not pass through `--syntax-check`, use the repo's documented
Ansible syntax-check path, but keep inventory/secrets in `dmf-env`.

### 7.2 OpenBao role verification

Run the OpenBao role/playbook first so policies and the identity exist:

```bash
cd "$DMFDEPLOY_UMBRELLA/dmf-env"
bin/run-playbook.sh aliyun-123 ../dmf-infra/k3s-lab-bootstrap/playbooks/vertical-security/100-openbao.yml
```

Expected on fresh init:

- policy exists;
- userpass user exists;
- break-glass JSON has `approle_reconciler_username` and
  `approle_reconciler_password`;
- root is still revoked at end.

Expected on existing cluster before recovery:

- either policy applies and role fails clearly for missing
  `approle_reconciler_password`, or the operator has already completed recovery
  and login verifies.

### 7.3 Object-storage role verification

After the identity exists:

```bash
cd "$DMFDEPLOY_UMBRELLA/dmf-env"
bin/run-playbook.sh aliyun-123 ../dmf-infra/k3s-lab-bootstrap/playbooks/vertical-resilience/100-object-storage-credentials.yml
```

Then rerun it to prove idempotency.

Expected:

- no `permission denied` in Steps 3-9;
- AppRoles include `object-storage-openbao-snapshots` and
  `object-storage-app-backups`;
- ESO bindings exist at dashed binding names;
- ClusterSecretStores `openbao-openbao-snapshots` and `openbao-app-backups`
  become `Ready=True`;
- ExternalSecrets reconcile in `openbao-system`, `awx`, `netbox`,
  `authentik`, `forgejo`, and `zot`.

### 7.4 Full post-seed verification

Run post-seed:

```bash
cd "$DMFDEPLOY_UMBRELLA/dmf-env"
RUNBOOK_TIMEOUT=5400 bin/run-playbook.sh aliyun-123 ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml
```

Then rerun it once. The second run should not rotate stable secret IDs unless
the binding is missing and the interrupted-state recovery path is intentionally
active.

### 7.5 Negative security probes

Verify these after the successful run:

- `ops-admin` still gets deny/403 for `sys/policies/acl/test`.
- `ops-admin` still gets deny/403 for
  `auth/approle/role/object-storage-app-backups/secret-id`.
- `policy-reconciler` still gets deny/403 for
  `auth/approle/role/object-storage-app-backups/secret-id`.
- `approle-reconciler` cannot write `sys/policies/acl/test`.
- `approle-reconciler` cannot read `secret/data/apps/...`.

Use `bao token capabilities` or direct harmless probes inside the OpenBao pod.
Do not print real token values or secret values.

---

## 8. Acceptance Criteria

- Step 5 mystery is explained in the plan or a handoff.
- `approle-reconciler` policy and user are created on fresh init.
- Existing initialized clusters fail clearly until one-time recovery supplies the
  new identity, or the operator completes recovery and reruns cleanly.
- `common/openbao-session` supports `operator`, `policy-reconciler`, and
  `approle-reconciler`.
- `object-storage-credentials` routes tokens according to ADR-0021.
- Naming drift is fixed: dashed identity/binding names, underscored data paths.
- `vertical-resilience/100-object-storage-credentials.yml` passes.
- Full `bootstrap-provision-post-seed.yml` passes once and then idempotently.
- Negative probes prove `ops-admin`, `policy-reconciler`, and
  `approle-reconciler` did not gain unrelated powers.
- `dmf-infra/docs/openbao-bootstrap-security-model.md` and the role README are
  updated.
- `STATUS.md` is updated if the implementation changes cross-repo state or live
  cluster state.

---

## 9. Do Not Do These

- Do not add `policy-writer` or AppRole powers to `ops-admin`.
- Do not broaden `policy-reconciler` into a general bootstrap identity.
- Do not use root in normal post-seed reruns.
- Do not commit diagnostic `no_log: false` tasks.
- Do not place tokens, passwords, or `secret_id` values in argv, docs, logs, or
  chat.
- Do not use policy paths with mid-path `*` globs.
- Do not add audit bucket credentials to ESO or this role.
- Do not rename docs or role files outside the requested scope.

---

## 10. Key References

- [ADR-0021 - OpenBao AppRole reconciliation uses a dedicated bootstrap identity](../decisions/0021-openbao-approle-reconciler-identity.md)
- [ADR-0007 - Secrets never in argv, env, /tmp, or AI transcripts](../decisions/0007-secrets-never-in-argv.md)
- [ADR-0008 - OpenBao + ESO + AppRole shim as secrets architecture](../decisions/0008-openbao-secrets-architecture.md)
- [ADR-0009 - Shamir DR model](../decisions/0009-shamir-dr-model.md)
- [ADR-0010 - run-playbook wrapper](../decisions/0010-run-playbook-as-sanctioned-entry.md)
- [OpenBao bootstrap security model](https://github.com/dmfdeploy/dmf-infra/blob/main/docs/openbao-bootstrap-security-model.md)
- [Parent AppRole reconciler plan](DMF%20OpenBao%20AppRole-Write%20Reconciler%20Plan%202026-05-13.md)
- [Policy-writer session separation plan](DMF%20OpenBao%20Policy-Writer%20Session%20Separation%20Plan%202026-05-13.md)
- [Tier A Phase 3 implementation handoff](../handoffs/DMF%20Tier%20A%20Phase%203%20Implementation%20Handoff%202026-05-12.md)
- OpenBao policy syntax: <https://openbao.org/docs/next/concepts/policies/>
- OpenBao AppRole API: <https://openbao.org/api-docs/auth/approle/>
