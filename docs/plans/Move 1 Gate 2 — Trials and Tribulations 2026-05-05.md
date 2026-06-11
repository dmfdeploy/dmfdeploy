---
status: historical
date: 2026-05-05
---
# Move 1 Gate 2 — Trials and Tribulations

> **SUPERSEDED 2026-05-23** by ADR-0025 Lane B. Catalog launchers now run
> in-cluster via an AWX EE pod + Helm chart; Path A remains only for 693-class
> infrastructure plays.
>
> **SUPERSEDED 2026-05-06** — every issue documented below was resolved via the
> Path A pivot. Don't take the SA-mount fixes here as guidance; they are the
> dead-end that motivated the pivot. See
> [`Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md`](Move%201%20Gate%202%20-%20Pivot%20to%20Path%20A%20for%20Catalog%20Launchers%202026-05-06.md).

**Date:** 2026-05-05
**Session:** Gate 2 execution (693-awx-integration + NMOS launch)

## 1. ansible.cfg `roles_path` incomplete

**Symptom:** `the role 'cluster-ready' was not found` and later `the role 'awx-integration' was not found`

**Root cause:** `ansible.cfg` had `roles_path = ./roles:<umbrella-path>/dmf-media/roles` but roles are nested 2-3 levels deep:
- `roles/base/cluster-ready` (and 15 other base roles)
- `roles/stack/operator/awx-integration`, `forgejo-bootstrap`, etc.
- `roles/common/app-admin-facts`, `dmf-born-inventory`, `openbao-session`

**Fix:** Expanded `roles_path`:
```
roles_path = ./roles:./roles/base:./roles/stack/operator:./roles/common:<umbrella-path>/dmf-media/roles
```

**Lesson:** The roles directory structure is `roles/<category>/<name>/`. Ansible only searches top-level dirs in `roles_path`. Any new category level needs to be added to ansible.cfg.

---

## 2. `cluster-ready` role tasks missing `become: true`

**Symptom:** `Task failed: [Errno 13] Permission denied: '/etc/rancher/k3s/k3s.yaml'` in `cluster-ready/tasks/main.yml`

**Root cause:** All `kubernetes.core.k8s_info` tasks in `cluster-ready` reference `/etc/rancher/k3s/k3s.yaml` which is `root:root 600`. Playbooks that include `cluster-ready` (691, 692, 640, etc.) run as `k3s-admin` user without `become: true` at play level.

**Fix:** Added `become: true` to every `kubernetes.core.k8s_info` task in `cluster-ready/tasks/main.yml` (8 tasks).

**Lesson:** All k8s tasks that read `/etc/rancher/k3s/k3s.yaml` need `become: true` unless the play already has it at the top level. This applies to ANY role that uses `kubernetes.core.*` modules with the k3s kubeconfig path.

---

## 3. `forgejo-bootstrap` role same `become: true` issue

**Symptom:** Same `[Errno 13] Permission denied: '/etc/rancher/k3s/k3s.yaml'` in `forgejo-bootstrap/tasks/main.yml:439` (Discover OpenBao pod task)

**Root cause:** Same pattern — `kubernetes.core.k8s_info` without `become: true`.

**Fix:** (pending — same fix as #2, add `become: true` to the k8s task in forgejo-bootstrap)

**Lesson:** This is a systemic issue. Every role that reads k3s.yaml needs `become: true` on its k8s tasks. Consider a shared pattern (e.g., `become: true` at play level for all 69x playbooks, or a role-level `become: true` in `roles/base/cluster-ready/meta/main.yml`).

---

## 4. 693 playbook referenced `cluster-ready` unnecessarily

**Symptom:** First failure was `cluster-ready` failing, blocking the entire 693 run.

**Root cause:** `693-awx-integration.yml` included `- cluster-ready` as a role, following the pattern of other 69x playbooks. But `awx-integration` doesn't need cluster readiness — it's all `ansible.builtin.uri` calls to AWX and Forgejo APIs, plus one `kubernetes.core.k8s_info` for OpenBao pod discovery.

**Fix:** Removed `cluster-ready` from 693 playbook. Added `become: true` at play level for the OpenBao pod task.

**Lesson:** Not every playbook needs `cluster-ready`. It's a pre-flight gate for playbooks that deploy to the cluster. Integration playbooks that only talk to APIs don't need it.

---

## 5. `dmf-runbooks` repo not created — 692 ran before repo list was updated

**Symptom:** 693 playbook tried to push files to `forgejo-svc/dmf-runbooks` → 404

**Root cause:** The `dmf-runbooks` entry was added to `forgejo_repos` in the forgejo-bootstrap defaults as part of the Move 1 work, but 692-forgejo-bootstrap had been run *before* that change. The repo didn't exist.

**Fix:** Re-ran 692-forgejo-bootstrap (after fixing #2 and #3). The "Create Forgejo repos" task is idempotent — it checks for existence first and skips existing repos.

**Lesson:** When adding repos to `forgejo_repos`, the 692 playbook must be re-run. This is a dependency order issue that the memory already captures (ADR-0007 token chain).

---

## 6. 693 awx-integration role assumed repo exists

**Symptom:** Push task GET check returned 404, then POST to create file also returned 404 (because the repo itself didn't exist, not just the file).

**Root cause:** The awx-integration role's dmf-runbooks push logic checks if the *file* exists but not if the *repo* exists. When the repo is missing, both GET and POST return 404.

**Fix:** Added repo existence check + creation task before the file push tasks:
```yaml
- name: Check if dmf-runbooks repo exists in Forgejo
  ansible.builtin.uri:
    url: "{{ awx_integration_forgejo_api_base }}/repos/..."
    status_code: [200, 404]
  register: _dmf_runbooks_repo_check

- name: Create dmf-runbooks repo in Forgejo if missing
  ansible.builtin.uri:
    url: "{{ awx_integration_forgejo_api_base }}/user/repos"
    body: { name: "dmf-runbooks", ... }
    status_code: [201, 422]
  when: _dmf_runbooks_repo_check.status == 404
```

**Hit another snag:** The Forgejo service token doesn't have `write:user` scope needed for `/user/repos`. So this approach won't work — repo creation must use admin auth (which 692 does with `force_basic_auth`).

**Lesson:** The awx-integration role's repo creation guard is a nice-to-have but can't work with the service token. The canonical repo creation path is 692-forgejo-bootstrap with admin basic auth.

---

## 7. 693 playbook missing `become: true` for k8s tasks

**Symptom:** `Discover OpenBao pod for AWX integration` failed with permission denied on k3s.yaml.

**Root cause:** Same as #2 — `693-awx-integration.yml` didn't have `become: true` at the play level.

**Fix:** Added `become: true` to the play definition.

**Lesson:** Any playbook that touches k8s resources on the control node needs `become: true`.

---

## 8. Introduced typo in cluster-ready — `longhorn-csi-csi-plugin`

**Symptom:** 692-forgejo-bootstrap hit "Wait for Longhorn CSI plugin to be ready" and retried 30 times then failed.

**Root cause:** During the `become: true` edit, I accidentally changed the DaemonSet name from `longhorn-csi-plugin` to `longhorn-csi-csi-plugin` (double `csi`).

**Fix:** Reverted to `longhorn-csi-plugin`.

**Lesson:** When editing existing code, verify the diff carefully. The typo was introduced during a larger edit block where I was adding `become: true` to all tasks.

---

## 9. forgejo-svc password invalidated mid-session

**Symptom:** After 692 ran "Update Forgejo service user password", the old password in the cluster secret became stale. API calls authenticated with the old password returned 403.

**Root cause:** 692 generates a new password if `forgejo_svc_password` is empty or matches the generated pattern. The update task runs unconditionally.

**Lesson:** When re-running 692, be aware that it rotates the forgejo-svc password. Any downstream consumers (AWX SCM credentials, mirror configs) may need to be updated. The 692 playbook handles this internally (it updates the token and credential in the same run), but if you interrupt 692 mid-run, the password may be rotated but not propagated.

---

## Summary of fixes applied

| File | Change |
|------|--------|
| `dmf-infra/k3s-lab-bootstrap/ansible.cfg` | Expanded `roles_path` to include `./roles/base`, `./roles/stack/operator`, `./roles/common` |
| `dmf-infra/k3s-lab-bootstrap/roles/base/cluster-ready/tasks/main.yml` | Added `become: true` to all 8 `kubernetes.core.k8s_info` tasks |
| `dmf-infra/k3s-lab-bootstrap/playbooks/693-awx-integration.yml` | Removed `cluster-ready`, added `become: true` |
| `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml` | Removed broken repo-creation guard, added `no_log: true` to Forgejo API tasks (R1, R2 review fixes) |
| `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/main.yml` | Added `become: true` to OpenBao pod discovery + login/persist shell tasks |

---

## 10. AWX EE container can't access other project directories

**Symptom:** `the role 'nmos-cpp' was not found in .../var/lib/awx/projects/_12__k3s_media_lab/roles: ...`

**Root cause:** AWX executes playbooks inside a containerized Execution Environment at `/runner/project/`. The EE only mounts its own project directory. Cross-project `roles_path` references point to host paths that don't exist inside the container.

**Fix:** Bundled the nmos-cpp role directly inside the dmf-runbooks repo at `playbooks/roles/nmos-cpp/`. AWX's default search path includes `/runner/project/playbooks/roles`.

**Lesson:** AWX EEs are isolated — no cross-project file access. Roles referenced by launcher playbooks must be bundled in the same repo or pulled via `requirements.yml` + `collections.yml` from a Galaxy/Forgejo source.

---

## 11. NetBox inventory `ansible_host` includes CIDR notation

**Symptom:** `ssh: Could not resolve hostname <node-public-ip>/32: Name or service not known`

**Root cause:** NetBox stores IPs as CIDR addresses (`<node-public-ip>/32`). The inventory compose used `ansible_host: primary_ip4.address` which passes the full CIDR to Ansible as the SSH target.

**Fix:** Changed `awx-automation/inventory/netbox.yml` compose to `ansible_host: primary_ip4.split('/')[0]`.

**Lesson:** NetBox API returns full CIDR for `primary_ip4`. Any Ansible compose that maps this to `ansible_host` must strip the prefix.

---

## 12. Wrong target host group in NetBox inventory

**Symptom:** First successful playbook run targeted `dmf-traefik` (load balancer), not the control plane node.

**Root cause:** Thin launcher used `hosts: k3s_control[0]` which doesn't exist in the NetBox inventory. The actual groups are `device_roles_k3s-control-plane` and `device_roles_load-balancer`.

**Fix:** Changed to `hosts: device_roles_k3s-control-plane[0]` which maps to `k3s-node-01`.

**Lesson:** The NetBox inventory plugin generates groups from NetBox metadata. Check actual group names via `GET /api/v2/inventories/2/groups/` rather than assuming legacy group names.

---

## 13. AWX EE can't SSH to external hosts

**Symptom:** `ssh: connect to host <node-public-ip> port 22: Connection timed out`

**Root cause:** The playbook ran via SSH from the EE to the external IP. The EE runs inside the cluster with no SSH key and no route to the external IP.

**Fix:** Added `connection: local` to the thin launcher playbook. k8s tasks use the Python API, not SSH.

**Lesson:** AWX EEs run inside the cluster and can only reach cluster-internal endpoints. Any play that needs kubectl access should use `connection: local` with the in-cluster service account token.

---

## 14. AWX EE missing `kubernetes` Python package

**Symptom:** `Could not create API client: Invalid kube-config file. No configuration found.`

**Root cause:** The default EE image `quay.io/ansible/awx-ee:latest` doesn't include the `kubernetes` Python package. The `kubernetes.core` Ansible collection wraps this library — without it, k8s tasks fail even with correct kubeconfig.

**Investigation:** Confirmed via `python3 -c 'import kubernetes'` in the awx-task pod — `ModuleNotFoundError`. The AWX task container is separate from the ephemeral EE job containers, but they use the same base image.

**Fix (in progress):** Need a custom EE with `kubernetes` package. The standard approach is:
1. Build a custom EE image from `quay.io/ansible/awx-ee:latest` with a `requirements.yml` that installs `kubernetes.core` (which pulls in the `kubernetes` Python package as a dependency)
2. Register the custom EE in AWX as an Execution Environment
3. Assign it to the dmf-runbooks project / job templates

Alternatively, rewrite the nmos-cpp role to use `command: kubectl` instead of `kubernetes.core.k8s`, but that's a bigger refactor and loses idempotency.

**Lesson:** The `kubernetes.core` Ansible collection requires the `kubernetes` Python package as a runtime dependency. The default AWX EE image may not include it — verify before using k8s modules.

---

## 15. `kubeconfig` extra_var override doesn't work with empty string

**Symptom:** Set `kubeconfig: ""` via job template extra_vars expecting in-cluster auto-discovery, got same error.

**Root cause:** Passing an empty string to the kubernetes Python client doesn't trigger in-cluster config discovery — it just fails to find a valid config file. The k8s module needs the kubeconfig parameter to be unset entirely, not set to empty.

**Fix:** Cleared extra_vars. Need to either (a) make the role conditional on kubeconfig being set, or (b) provide a proper in-cluster kubeconfig file to the EE.

**Lesson:** The kubernetes Python client auto-discovers in-cluster auth only when no kubeconfig is specified at all. Ansible variable defaults still pass a value.

---

## 16. SSH key distribution to k3s nodes (BLOCKER)

**Symptom:** AWX job succeeds at SSH key injection but fails at `Permission denied (publickey)` on k3s-node-01.

**Root cause:** The AWX EE runs inside the cluster and must SSH to k3s-node-01 (via hostname `k3s-node-01` → cluster IP `10.0.0.4`). The control node (<control-node-public-ip>) has a local SSH keypair that works for your Mac, but k3s-node-01's `authorized_keys` is empty — no key is installed for `k3s-admin`.

**Attempted fixes:**
1. Generated ed25519 keypair locally (`/tmp/awx-control-node-key`) and appended pubkey to `k3s-admin@<control-node-public-ip>:~/.ssh/authorized_keys` — works for control node, but control node can't SSH to k3s-node-01 by hostname (DNS resolution failure).
2. Installed pubkey on k3s-node-01 via privileged pod (`ssh-key-installer`) mounting host root filesystem — confirmed working (`ssh -i /tmp/awx-ssh-key k3s-admin@10.0.0.4 whoami` returns `k3s-admin`).
3. Tried to update AWX Machine credential (credential ID 4) with the matching private key via AWX API PATCH — escaping issues with multiline SSH key data in JSON prevented the update from succeeding (credential remains with `ssh_key_data` missing).

**Blocker analysis:** The credential update via AWX API requires the private key content to be properly escaped in a JSON `inputs.ssh_key_data` field. All attempts so far have been thwarted by:
- The `no_log: true` on the awx-integration role's credential creation task hides failures
- The local machine can't reach the AWX API directly (Tailscale-only), so the update must happen via `kubectl exec` on the awx-task pod
- The `kubectl exec` approach fails on Python escaping (multiline PEM key with embedded newlines)
- The `curl` approach from within the pod fails on shell escaping

**Resolution options:**
- **Option A:** Use `ansible.builtin.uri` in the awx-integration role to update the credential via the AWX API, with the SSH key loaded from an Ansible vault variable (proper Jinja2 escaping handles the multiline key).
- **Option B:** Use AWX's built-in credential management UI — paste the private key content directly via the AWX web UI at `/api/v2/credentials/4/`.
- **Option C:** Switch to SSH key injection via a ConfigMap mounted into the EE pod (bypass AWX credential system entirely; use `ssh_extra_args: -i /tmp/key`).
- **Option D:** Use AWX's `ansible.builtin.uri` to PATCH the credential with a properly base64-encoded key.

**Lesson:** AWX credentials are managed through the API/DB, not through filesystem copies. The Machine credential type requires the `ssh_key_data` field to contain the full PEM private key — proper escaping of multiline content through the Ansible → AWX API chain is error-prone.

---

## Summary of fixes applied

| File | Change |
|------|--------|
| `dmf-infra/k3s-lab-bootstrap/ansible.cfg` | Expanded `roles_path` to include `./roles/base`, `./roles/stack/operator`, `./roles/common` |
| `dmf-infra/k3s-lab-bootstrap/roles/base/cluster-ready/tasks/main.yml` | Added `become: true` to all 7 `kubernetes.core.k8s_info` tasks |
| `dmf-infra/k3s-lab-bootstrap/playbooks/693-awx-integration.yml` | Removed `cluster-ready`, added `become: true` |
| `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml` | Removed broken repo-creation guard (R2 review fix); added SSH Machine credential creation tasks; attached credential to catalog job templates |
| `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml` | Added `awx_control_node_ssh_user` and embedded ed25519 SSH private key for Gate 2 spike |
| `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/main.yml` | Added `become: true` to OpenBao pod discovery + login/persist shell tasks |
| `dmf-media/roles/nmos-cpp/tasks/*.yml` | Replaced hardcoded kubeconfig with `{{ kubeconfig | default(omit) }}` (Issue #15 real fix) |
| `dmf-infra/k3s-lab-bootstrap/playbooks/runbooks/*.yml` | Reverted `connection: local`; use `hosts: device_roles_k3s-control-plane[0]` + `become: true` (Path A) |
| `awx-automation/inventory/netbox.yml` | `ansible_host: name` (hostname, not IP — resolves via cluster DNS) |
| `dmf-runbooks` (Forgejo repo) | Bundled playbooks + nmos-cpp role for AWX EE self-containment |
| AWX credential 4 | `k3s-control-node-ssh` Machine credential (ssh_key_data update **BLOCKED** — see Issue #16) |
| AWX project 8 (awx-automation) | `scm_update_on_launch: true` re-enabled |

---

## Closure (in progress) — Path Y redeploy 2026-05-05

The Issue #16 spike produced an ADR-0007 violation: a real ed25519 private SSH
key was committed in plaintext to
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml`
in commit `3a27666`. Two follow-on commits (`5a9f2e0`, `9a00d3b`) carried the
key forward. The bad commits also reached the in-cluster Forgejo mirror at
`forgejo-lab.dmf.example.com/forgejo-svc/dmf-infra.git` but **did not** reach
the external `origin` remote.

**Decision:** complete cluster redeploy authorised by operator. Path Y per
`docs/reviews/dmf-move1-gate2-ssh-credential-incident-2026-05-05.md`.

**Path A as the post-redeploy execution model is locked in** — see
ADR-0016 (`docs/decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md`).
Pubkey via cloud-init Terraform variable, privkey via OpenBao at
`secret/apps/awx/control_node_ssh`. The AWX credential-creation tasks added
during the spike are stripped from the awx-integration role and will be
reintroduced post-redeploy from the OpenBao path, not from defaults.

**Phase 1 status (local dmf-infra cleanup):** complete.
- `git reset --hard e8696f5` (last clean commit, no PEM)
- `git reflog expire --expire=now --all && git gc --prune=now --aggressive`
- Dangling `refs/stash` (unrelated, akadmin-era) dropped
- Working tree contains no PEM markers, no `awx_control_node_ssh_*` references
- Bad commits `3a27666 / 5a9f2e0 / 9a00d3b` remain in `.git/objects` only
  via `refs/remotes/forgejo-lab/main` until the Phase 3 force-push or the
  Phase 4 cluster destroy

**Pending phases:** force-push to forgejo-lab, `tofu destroy`, OpenBao re-init,
new keypair generation + plumbing, `tofu apply` + bootstrap, Gate 2 re-run,
operator-side sweep. See task list at the time of writing.

A full closure section will be appended after Gate 2 success criteria are
verified on the rebuilt cluster.

---

## Closure (2026-05-06)

Gate 2 closed via Path A pivot (not via the in-cluster SA-mount approach
this trials log was investigating). After ~20 iterative fix commits in
`dmf-runbooks` failed to make in-cluster ServiceAccount auth work,
independent architecture review recommended pivoting catalog launchers
to ADR-0016 Path A — the SSH-via-control-node pattern already used by
the layer playbooks (640, 693).

The decision and findings live in:
- [`docs/plans/Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md`](Move%201%20Gate%202%20-%20Pivot%20to%20Path%20A%20for%20Catalog%20Launchers%202026-05-06.md)
  — full plan + cleanup inventory + acceptance criteria
- [`docs/handoffs/DMF Move 1 Gate 2 Path A Pivot Handoff 2026-05-06.md`](../handoffs/DMF%20Move%201%20Gate%202%20Path%20A%20Pivot%20Handoff%202026-05-06.md)
  — session record
- ADR-0012 Implementation note (2026-05-06)

End-to-end validation: AWX job 285 ran `media-launch-nmos-cpp`
successfully (NetBox tag taxonomy created, `ipam.Service` registered
with parent `dmf-traefik`, K8s workloads applied, NetBox tag flipped
to `lifecycle:active`). Job 295 confirmed images pull cleanly after Zot
push.

The trials log itself is preserved as historical context — what was
tried, why it didn't fit, what we learned. The actual successful path
diverges from this document's approach.
