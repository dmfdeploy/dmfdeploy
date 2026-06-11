---
status: executed
date: 2026-04-30
---
# Codex Task — DMF Platform Chain Hygiene Cleanups

**Date:** 2026-04-30
**Working repo:** `<repos>/dmf-infra` (NOT the operator note store)
**Branch:** check `git status` first; expect `main` with 8 commits ahead and several uncommitted edits in flight (those are unrelated WIP — leave them alone)
**Reviewer that produced this task:** Claude Code (Opus 4.7), critical chain review at `<repos>/dmf-platform-chain-review-2026-04-30.md`
**Strategic context:** DMF platform is in *experiment phase* — pure hygiene only, no architectural commitments. See `<repos>/dmf-platform-strategic-review-2026-04-30.md` and `<repos>/dmf-infra/k3s-lab-bootstrap/docs/dmf-platform-plan.md` if you need framing.

---

## Read this first (5 min)

The chain review identified four problems that block the strategic Move 2 (dmf-cms vertical slice). This task covers the three **fail-fast hygiene cleanups** that lock in nothing architectural and surface silent failures. The fourth (NetBox SoT extension to register apps as `ipam.Service` objects + missing forgejo-svc NetBox user) is **OUT OF SCOPE** here — it requires architectural decisions and belongs in the dmf-cms Move 2 work, not in this hygiene pass.

You are doing **only** Steps 1, 2, 3 below. Each step is one commit. Do them in order. Stop after Step 3.

---

## Hard rules

- **Do NOT run Ansible playbooks against the live cluster.** This is operator territory and requires keychain access you do not have.
- **Do NOT commit edits to files outside the three steps below.** There are 7 in-flight uncommitted files in the repo (Zot OIDC, Authentik blueprints, born-inventory, post-bootstrap-verify) — those are someone else's WIP. Do not stage them, do not include them in your commits.
- **Use `git add <specific paths>` only.** Never `git add -A` or `git add .`.
- **One commit per step.** Three commits total at the end. Each commit message ends with `Co-Authored-By: Codex <noreply@openai.com>`.
- **Run syntax checks before committing.** `ansible-playbook --syntax-check <playbook>` and `ansible-lint <path>` if available. If syntax check fails, fix and recheck — do not commit broken YAML.
- **STOP after Step 3.** Do not attempt #2/#3 from the chain review (NetBox `ipam.Service` extension) or any other "while I'm here" cleanup. That's Move 2 territory and needs the user in the loop.
- **Do not modify tests, CI configs, or unrelated docs.** Touch only what each step says to touch.

---

## Step 1 — Fail-closed assert on the OpenBao-vs-vault mode toggle

**Finding (#5 in chain review):** Three roles have a mode toggle that picks OpenBao if all five env vars are set, else falls through to ansible-vault + vault.yml. The toggle is a boolean computed from `(openbao_url and openbao_role_id and openbao_secret_path and openbao_keychain_service and openbao_keychain_account)`. If exactly *some* of these are set, the role silently uses the legacy vault path — which may not be configured — and secrets land in the wrong store. This violates `initial-data-gathering.md` §"Boundary rules" #3 ("two long-lived stores for the same value is a bug").

### Files to edit

1. `<repos>/dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/main.yml`
2. `<repos>/dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox-sot/tasks/main.yml`
3. `<repos>/dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml`

### Pattern to add

In each role's `tasks/main.yml`, **immediately after the `set_fact` that computes `*_persist_to_openbao`**, add a partial-config check that fails clearly. Example for `forgejo-bootstrap`:

```yaml
- name: Compute OpenBao config completeness for fail-closed assert
  ansible.builtin.set_fact:
    forgejo_openbao_vars_set:
      - "{{ (openbao_url | default('') | length > 0) | ternary(1, 0) }}"
      - "{{ (openbao_role_id | default('') | length > 0) | ternary(1, 0) }}"
      - "{{ (openbao_secret_path | default('') | length > 0) | ternary(1, 0) }}"
      - "{{ (openbao_keychain_service | default('') | length > 0) | ternary(1, 0) }}"
      - "{{ (openbao_keychain_account | default('') | length > 0) | ternary(1, 0) }}"

- name: Assert OpenBao config is all-or-nothing (fail-closed mode toggle)
  ansible.builtin.assert:
    that:
      - (forgejo_openbao_vars_set | map('int') | sum) in [0, 5]
    fail_msg: >-
      Partial OpenBao configuration detected for forgejo-bootstrap.
      Either all five OpenBao vars must be set (openbao_url, openbao_role_id,
      openbao_secret_path, openbao_keychain_service, openbao_keychain_account)
      to persist to OpenBao, or all five must be empty to fall back to
      ansible-vault + vault.yml. Mixing them silently routes secrets to the
      wrong store. See initial-data-gathering.md §Boundary rules #3.
```

Adapt variable name prefix per role (`netbox_sot_openbao_vars_set`, `awx_integration_openbao_vars_set`). Adapt `fail_msg` role name per role.

### Acceptance

- `ansible-playbook --syntax-check <repos>/dmf-infra/k3s-lab-bootstrap/playbooks/692-forgejo-bootstrap.yml` passes
- `ansible-playbook --syntax-check <repos>/dmf-infra/k3s-lab-bootstrap/playbooks/691-netbox-sot.yml` passes
- `ansible-playbook --syntax-check <repos>/dmf-infra/k3s-lab-bootstrap/playbooks/693-awx-integration.yml` passes
- `ansible-lint <each-role>` clean (or no new warnings vs baseline — capture baseline first if needed)

### Commit

```
fix(secrets): fail-closed assert on OpenBao mode toggle in three roles

Roles forgejo-bootstrap, netbox-sot, and awx-integration computed a
*_persist_to_openbao boolean from five OpenBao vars. If any subset was
set, the role silently fell back to ansible-vault, routing secrets to a
store the operator may not have configured. Add an explicit assert that
all five vars are set or none are, with a fail message pointing to the
boundary-rule violation.

Closes finding #5 from the 2026-04-30 chain review.

Co-Authored-By: Codex <noreply@openai.com>
```

---

## Step 2 — Gate librenms-svc on `librenms_enabled`

**Finding (#8 in chain review):** `lifecycle-provision.yml:64-67` comments out the LibreNMS playbook (LibreNMS not currently deployed). But `roles/stack/operator/netbox-sot/tasks/main.yml:417-482` unconditionally creates the `librenms-svc` user in NetBox + a "LibreNMS discovery sync" API token. This produces an orphan service account: a NetBox user that has no service to log into, with a generated token that nothing uses and never rotates.

### File to edit

`<repos>/dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox-sot/tasks/main.yml`

### What to do

1. **Default `netbox_sot_librenms_enabled: false`** in the role's `defaults/main.yml` if not already present (check `roles/stack/operator/netbox-sot/defaults/main.yml`).
2. Wrap **all librenms-svc tasks** in the netbox-sot role with `when: netbox_sot_librenms_enabled | bool`. The relevant tasks include (but verify by reading the role):
   - "Lookup LibreNMS service user"
   - "Create LibreNMS service user"
   - "Fetch LibreNMS service user details"
   - "Set LibreNMS user group ids"
   - "Ensure LibreNMS user is in LibreNMS group"
   - The LibreNMS token-creation `command` task (search for `netbox_sot_librenms_token_cmd`)
   - Any LibreNMS-specific `set_fact` that follows
   - "Ensure LibreNMS object permissions via NetBox pod" (if it exists)
3. Also gate the LibreNMS group creation if it exists upstream of those tasks (search for `netbox_sot_librenms_group`).
4. **Do not gate** the AWX or admin tasks — those are always-on.
5. **Do not modify any other roles or playbooks.** This is netbox-sot only.

### Acceptance

- `ansible-playbook --syntax-check <repos>/dmf-infra/k3s-lab-bootstrap/playbooks/691-netbox-sot.yml` passes
- Reading the role with grep confirms every task that references `librenms` (in name or task body) has `when: netbox_sot_librenms_enabled | bool` or is inside a block with that `when:`
- `ansible-lint roles/stack/operator/netbox-sot` clean

### Commit

```
fix(netbox-sot): gate librenms-svc provisioning on librenms_enabled

LibreNMS is currently disabled in lifecycle-provision.yml but
netbox-sot was unconditionally creating the librenms-svc user and a
"LibreNMS discovery sync" API token in NetBox. This produced an orphan
service account with a token that nothing consumes and never rotates.

Wrap all librenms-svc tasks in netbox-sot with
'when: netbox_sot_librenms_enabled | bool' and default the flag to
false in the role defaults. AWX and admin provisioning unchanged.

Closes finding #8 from the 2026-04-30 chain review.

Co-Authored-By: Codex <noreply@openai.com>
```

---

## Step 3 — Make `339-container-platform-verify.yml` real

**Finding (#4 in chain review):** This playbook is the end-of-Layer-3 gate, but it currently only emits a `debug:` task with intended-checks comments. lifecycle-provision exits "green" for Phase 1 without actually verifying that the wildcard cert is Ready, the registry is reachable, the Longhorn StorageClass is default, or the Hetzner LB is healthy. Operators rely on the manual checklist in `DEPLOYMENT.md §12` instead.

### File to rewrite

`<repos>/dmf-infra/k3s-lab-bootstrap/playbooks/339-container-platform-verify.yml`

### Intended checks (from the existing stub comment)

1. **Wildcard cert is Ready** — `kubernetes.core.k8s_info` against the `Certificate` named `cluster-tls` (or whatever `cert_manager_certificate_name` resolves to) in `kube-system`. Check `status.conditions` has a `Ready: True` condition.
2. **Longhorn StorageClass is default** — `k8s_info` for `StorageClass` `longhorn` (or `longhorn_storage_class_name`). Assert `metadata.annotations.storageclass.kubernetes.io/is-default-class` is `"true"`.
3. **Zot registry is reachable** — `ansible.builtin.uri` to the registry's `/v2/` endpoint (Docker Registry v2 spec — must return 200 or 401 for an authenticated registry; either confirms it's up). Use `registry_external_url` or equivalent var.
4. **Traefik service has a load balancer ingress** — `k8s_info` for `Service` named `{{ traefik_service_name | default('traefik') }}` in `{{ traefik_namespace | default('kube-system') }}` (or `traefik_private_namespace`). Assert `status.loadBalancer.ingress[0].ip | hostname` is non-empty.

### Implementation pattern

Run on `k3s_control[0]` (or `k3s-node-01`) with `become: true` so kubectl works via `/etc/rancher/k3s/k3s.yaml`. Use `kubernetes.core.k8s_info` for cluster checks. Use `ansible.builtin.uri` for the registry HTTP check. Each task should fail loudly with a clear `failed_when` message identifying which check broke and what to fix.

Add 30-60s `retries`/`delay` to the cert and Longhorn checks — these are flaky during cluster bootstrap. The registry check should retry too.

Reference existing real verify playbooks for style:
- `<repos>/dmf-infra/k3s-lab-bootstrap/playbooks/219-host-verify.yml` — gold-standard real verify
- `<repos>/dmf-infra/k3s-lab-bootstrap/playbooks/vertical-monitoring/190-monitoring-verify.yml` — k8s-side checks

Pull variable names from the relevant defaults to avoid hardcoding:
- `roles/base/cert-manager/defaults/main.yml`
- `roles/base/longhorn/defaults/main.yml`
- `roles/stack/operator/zot/defaults/main.yml`
- The traefik role/role-config

If a variable doesn't exist, prefer a reasonable default with a comment over hardcoding without explanation.

### Acceptance

- `ansible-playbook --syntax-check <repos>/dmf-infra/k3s-lab-bootstrap/playbooks/339-container-platform-verify.yml` passes
- `ansible-lint <repos>/dmf-infra/k3s-lab-bootstrap/playbooks/339-container-platform-verify.yml` clean
- Reading the file shows real `assert:` / `failed_when` tasks that would catch each of the four intended-check classes
- The `STUB:` debug message is removed
- File header comment updated to reflect "real verify" not "stub"

### Commit

```
feat(verify): real Layer 3 container-platform verify gate

Replace the debug-only stub with actual verification of the four
intended checks: wildcard cert Ready, Longhorn default StorageClass,
Zot registry /v2/ reachable, Traefik LB ingress assigned. Runs on the
control node, retries on bootstrap-flaky cert and storage checks.

Closes finding #4 from the 2026-04-30 chain review.

Co-Authored-By: Codex <noreply@openai.com>
```

---

## After Step 3 — STOP

When all three commits are in, output a short report:

```
## Cleanup task complete

Commits:
  <hash>  fix(secrets): fail-closed assert on OpenBao mode toggle...
  <hash>  fix(netbox-sot): gate librenms-svc provisioning on librenms_enabled
  <hash>  feat(verify): real Layer 3 container-platform verify gate

Files touched (per commit):
  Step 1: <list>
  Step 2: <list>
  Step 3: <list>

Untouched WIP files (intentionally left alone):
  <list of pre-existing dirty files>

Next steps for operator:
  - Push when ready (no force-push, no rebase)
  - Run lifecycle-provision next time the cluster is rebuilt to exercise the new asserts
  - Move 2 (dmf-cms vertical slice + NetBox ipam.Service registration) is a separate task
```

Do **not** push to remote. Do **not** start Move 2. Do **not** run any playbook against the live cluster. Hand back to the operator.

---

## Out of scope (do NOT touch)

- Anything in `dmf-cms/`, `dmf-central/`, `dmf-media/`, or `dmf-env/`
- The 7 dirty files already present in `dmf-infra/` (Zot OIDC, Authentik blueprints, born-inventory, post-bootstrap-verify) — those are someone else's WIP
- Documentation under `docs/` (chain review, platform plan, strategic review) — informational only, do not modify
- The `694-born-inventory` extension to register apps as `ipam.Service` (finding #2/#3 in chain review) — Move 2 territory
- Renumbering or splitting `lifecycle-provision.yml` — finding #1, deferred to commit phase
- The Resource Profile manifest codegen (finding #7) — Release 5 work
- The dmf-cms integration smoke (finding #6) — Move 2 territory
