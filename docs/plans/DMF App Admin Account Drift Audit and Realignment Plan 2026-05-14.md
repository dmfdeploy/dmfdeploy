---
status: executed
date: 2026-05-14
executed: 2026-05-23
---
# DMF App Admin Account Drift Audit and Realignment Plan

> **SUPERSEDED 2026-05-23** — the 6-flag override tax was an `aliyun-123`-
> specific artefact and was retired when that env was retired. `g2r6-foa9`
> (wizard-fresh) runs `bootstrap-configure` with **zero** `-e` overrides;
> live admin identity audit
> (`dmf-infra/k3s-lab-bootstrap/playbooks/audit-admin-identities.yml`)
> confirms no drift across 5 apps. See
> [`docs/handoffs/DMF App-Admin Drift Realignment Handoff 2026-05-23.md`](../handoffs/DMF%20App-Admin%20Drift%20Realignment%20Handoff%202026-05-23.md)
> for the closure narrative.
>
> **§5 (Path 1/2/3 remediation framework) remains an active reference**
> for any future drift incident on a future env. The audit playbook
> mechanises §4 (per-app drift detection); operator-side remediation
> still follows §5's three paths.

**Date:** 2026-05-14
**Author:** session-collaborative (Claude + qwen-right + operator)
**Status:** Plan + audit template — implementation closed 2026-05-23
**Scope env:** `aliyun-123` (retired); `g2r6-foa9` confirmed clean 2026-05-23

---

## 1. Context

Multiple `bootstrap-configure` runs on `aliyun-123` have surfaced a systemic
pattern: **live cluster admin accounts no longer match what the playbook
source-of-truth expects.** Two concrete cases discovered in this session,
with distinct drift shapes:

### 1.1 NetBox — username-only drift

- Live superuser: `admin`
- Role default resolves to: `vault_bootstrap_admin_username | default('dmfadmin')`
- Password for `admin` in the live DB matches the OpenBao-stored value
- **Workaround:** `-e netbox_sot_admin_username=admin` on every playbook
  invocation. Cheap, reversible, env-specific.
- **Status:** confirmed today via `User.objects.filter(is_superuser=True)`
  shell call against `deploy/netbox`.

### 1.2 AWX — username + password drift

- Live superuser: `<handle>` (not `dmfadmin`, not `admin`)
- k8s Secret `awx-admin-password` (sha256 prefix `e4512a9b76ea`, created
  `2026-05-13T05:35:44Z`) does **not** match the DB-stored password for `<handle>`
  (user `date_joined` = `2026-05-13T05:41:43Z`, ~6 min after Secret creation)
- Three probes from inside `awx-web` pod (read-only, password fed via stdin):
  - `dmfadmin` + Secret password → 401 (user doesn't exist)
  - `<handle>`      + Secret password → 401 (password mismatch)
  - `<handle>`      + `admin`         → 401 (wrong password)
- **Workaround:** `-e awx_integration_admin_user=<handle>` *and* a one-time
  password resync via `awx-manage update_password` inside the pod, feeding
  the Secret value via stdin.
- **Status:** confirmed today via qwen-right diagnostic dispatch.

### 1.3 Why a doc

A fresh cluster rollout would realign live state with playbook intent, but is
heavy (Layer-1 reset + full bootstrap on aliyun-123, several hours, plus a
separate decision about *when* — likely an ADR). In the meantime we need:

- A **per-app audit** of which live admin accounts exist and whether the
  Secret/OpenBao password actually authenticates.
- A **workaround inventory** — minimum `-e` overrides and one-time in-pod
  resyncs needed to unblock `bootstrap-configure` end-to-end.
- A consistent structure so a fresh agent can read this cold, execute the
  audit, fill in the per-app result blocks, and propose remediations
  without needing today's session context.

---

## 2. Cluster access pattern (minimal)

Full canonical procedure lives in `.claude/skills/dmf-cluster-access/SKILL.md`
(read §0 Secrets Discipline + §3 read-only operations before running anything
here).

For `aliyun-123` specifically:

- **SSH bastion:** `k3s-admin@<aliyun-control-node-public-ip>` (look up
  concrete IP in `dmf-env/inventories/aliyun-123/hosts.ini`)
- **SSH key:** `~/.ssh/id_ed25519_k3s_aliyun` (env-defined by
  `ansible_ssh_private_key_file` in
  `dmf-env/inventories/aliyun-123/group_vars/all/main.yml` — that's why
  ansible works without an entry in `~/.ssh/config`)
- **kubeconfig on node:** `/etc/rancher/k3s/k3s.yaml` (root-owned → `sudo`)
- **Mode:** all commands in §4 below are **READ-ONLY**. No `kubectl apply`,
  no `kubectl exec` that mutates state. Path 2 in §5 (one-time password
  resync) is the only write path and is explicitly called out.

Standard one-shot pattern:

```bash
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<aliyun-control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n <ns> <verb> <args>"
```

### 2.1 Secrets discipline (non-negotiable)

- **Never echo a password or token to stdout in this conversation transcript.**
- For Secret comparison, use length + 12-char sha256 prefix only:
  ```bash
  kubectl ... -o jsonpath='{.data.password}' | wc -c
  kubectl ... -o jsonpath='{.data.password}' | base64 -d | sha256sum | cut -c1-12
  ```
- For auth probes, run `curl` **inside the target pod** so the password
  stays on the pod's stdin and never appears in argv visible to `ps` on
  the bastion host.
- Use heredoc + shell variable assignment to pass values, never argv.

---

## 3. Apps in scope

Six apps with local admin accounts that `bootstrap-configure.yml` depends on:

| App        | Role-default username                                            | Password source                                                      | Bootstrap chain step      |
|------------|------------------------------------------------------------------|----------------------------------------------------------------------|---------------------------|
| Authentik  | `akadmin` (hardcoded)                                            | `common/app-admin-facts` → OpenBao `secret/apps/authentik/admin`     | `110-authentik`           |
| AWX        | `vault_bootstrap_admin_username \| default('dmfadmin')`          | `vault_awx_admin_password \| default(vault_bootstrap_admin_password)` + k8s Secret `awx-admin-password` (when `read_admin_password_from_cluster=true`) | `693-awx-integration` |
| Forgejo    | `vault_bootstrap_admin_username \| default('dmfadmin')`          | `vault_forgejo_admin_password \| default(vault_bootstrap_admin_password)` | `692-forgejo-bootstrap` |
| NetBox     | `vault_bootstrap_admin_username \| default('dmfadmin')`          | `vault_netbox_superuser_password \| default(vault_bootstrap_admin_password)` | `691-netbox-sot`     |
| Zot        | `admin` (hardcoded; role comment notes historical bug)           | `vault_zot_admin_password \| default(vault_bootstrap_admin_password)` | `191-zot-oidc`            |
| LibreNMS   | `admin` (hardcoded)                                              | `librenms_admin_password` (set via inventory; expected from OpenBao) | (monitoring vertical)     |

### 3.1 Asymmetry note

**Authentik** (and Zot's OIDC step) uses the canonical
`roles/common/app-admin-facts` role, which reads + writes the OpenBao secret
on every run. Those apps are **less likely** to drift — the run-time
reconciles secret → state.

The other four (**AWX, Forgejo, NetBox, LibreNMS**) use direct `vault_*`
defaults and trust whatever was set at original create time. **That's where
drift hides.** AWX and NetBox are confirmed drifted; Forgejo and LibreNMS
should be audited under suspicion.

---

## 4. Per-app audit procedure

For each app, run three checks: **(a) intended username**, **(b) live
superuser(s)**, **(c) auth probe with the Secret/OpenBao password**. Then
fill in the result block at the end of each subsection.

### 4.1 Authentik

```bash
# (a) intended username — read role default
grep authentik_bootstrap_admin_username \
  /Users/<operator>/repos/dmfdeploy/dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/defaults/main.yml

# (b) live admin group members — Authentik uses group membership, not is_superuser field
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<aliyun-control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n authentik \
    exec deploy/authentik-server -- ak shell -c \
    \"from authentik.core.models import Group; g=Group.objects.filter(name='authentik Admins').first(); \
     [print(u.username, 'active='+str(u.is_active)) for u in (g.users.all() if g else [])]\""

# (c) auth probe (from inside pod, password via stdin)
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<aliyun-control-node-public-ip> <<'EOF'
PW=$(sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n openbao exec openbao-0 -- \
       bao kv get -field=password secret/apps/authentik/admin)
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n authentik \
  exec deploy/authentik-server -- curl -sS -o /dev/null -w 'http:%{http_code}\n' --max-time 5 \
   -u "akadmin:$PW" http://localhost:9000/api/v3/core/users/me/
EOF
```

```
Intended username: akadmin (hardcoded)
Live admin users:  <handle>, akadmin, break-glass (all in "authentik Admins" group, all active)
Live auth probe:   pass (akadmin + OpenBao password → http:200)
Drift shape:       none
Workaround:        none needed
Permanent fix:     no fix needed
```

### 4.2 AWX

Pre-filled from session 2026-05-14:

```bash
# (a) intended username
grep -E "awx_admin_user|awx_integration_admin_user" \
  /Users/<operator>/repos/dmfdeploy/dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx*/defaults/main.yml

# (b) live superusers — Django shell against AWX User model
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<aliyun-control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n awx \
    exec deploy/awx-web -- awx-manage shell_plus -c \
    \"from django.contrib.auth import get_user_model; U=get_user_model(); \
     [print(u.username, u.is_superuser, u.is_active, u.last_login) \
      for u in U.objects.filter(is_superuser=True)]\""

# (c) auth probe (Secret-backed)
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<aliyun-control-node-public-ip> <<'EOF'
PW=$(sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n awx \
       get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d)
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n awx \
  exec deploy/awx-web -- sh -c \
  "curl -sS -o /dev/null -w 'http:%{http_code}\n' --max-time 5 \
   -u <handle>:$PW http://localhost:8052/api/v2/me/"
EOF
```

```
Intended username: dmfadmin (role default fallback)
Live username:     <handle>
Live auth probe:   fail (Secret password does not authenticate)
Drift shape:       both (username AND password)
Workaround:        -e awx_integration_admin_user=<handle>
                   + one-time `awx-manage update_password --username <handle>
                     --password-stdin` inside deploy/awx-web (Path 2)
Permanent fix:     Path 3 — patch awx-integration role to read admin_user
                   from AWX CR spec (qwen-right's "Option A"), mirroring
                   the existing read_admin_password_from_cluster=true
                   pattern. Long term: fresh cluster rollout.
```

### 4.3 Forgejo

```bash
# (a) intended username
grep -E "forgejo_admin_username" \
  /Users/<operator>/repos/dmfdeploy/dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo*/defaults/main.yml

# (b) live admin users — gitea CLI inside the forgejo pod
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<aliyun-control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n forgejo \
    exec deploy/forgejo -- /usr/local/bin/gitea admin user list --admin --config /data/gitea/conf/app.ini"

# (c) auth probe
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<aliyun-control-node-public-ip> <<'EOF'
PW=$(sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n forgejo \
       get secret forgejo-admin -o jsonpath='{.data.password}' | base64 -d)
# Pipe password via stdin to avoid argv exposure
echo "$PW" | sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n forgejo \
  exec -i deploy/forgejo -- sh -c \
  'U=$(cat); curl -sS -o /dev/null -w "http:%{http_code}\n" --max-time 5 \
   -u "<handle>:$U" http://localhost:3000/api/v1/user'
EOF
```

```
Intended username: dmfadmin (via vault_bootstrap_admin_username default)
Live username:     <handle> (only admin user)
Live auth probe:   pass (<handle> + forgejo-admin secret password → http:200)
Drift shape:       username-only
Workaround:        -e forgejo_admin_username=<handle> (Path 1)
Permanent fix:     Path 3 candidate — patch forgejo-bootstrap role to read
                   live admin username from cluster state (analogous to AWX
                   Option A). Long term: fresh cluster rollout.
```

### 4.4 NetBox

Pre-filled from session 2026-05-13 / 2026-05-14:

```bash
# (a) intended username
grep -E "netbox_superuser_username|netbox_sot_admin_username" \
  /Users/<operator>/repos/dmfdeploy/dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox*/defaults/main.yml

# (b) live superusers
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<aliyun-control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n netbox \
    exec deploy/netbox -- python /opt/netbox/netbox/manage.py shell -c \
    'from users.models import User; \
     [print(u.username, u.is_superuser, u.is_active) \
      for u in U.objects.filter(is_superuser=True)]'"

# (c) auth probe — NetBox uses Token auth primarily, but Basic works for
# /api/users/users/me/. Adjust if the role's auth chain uses tokens instead.
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<aliyun-control-node-public-ip> <<'EOF'
# NetBox admin password normally bootstrapped via `manage.py changepassword`;
# the Secret pattern varies. Check what the role actually reads.
PW=$(sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n netbox \
       exec deploy/openbao-0 ... bao kv get -field=password secret/apps/netbox/admin 2>/dev/null)
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n netbox \
  exec deploy/netbox -- sh -c \
  "curl -sS -o /dev/null -w 'http:%{http_code}\n' --max-time 5 \
   -u admin:$PW http://localhost:8080/api/users/users/?is_superuser=true"
EOF
```

```
Intended username: dmfadmin (role default fallback)
Live username:     admin
Live auth probe:   pass (password matches)
Drift shape:       username-only
Workaround:        -e netbox_sot_admin_username=admin (Path 1)
Permanent fix:     Path 3 candidate — patch netbox-sot role to read live
                   admin username from cluster state (analogous to AWX
                   Option A). Long term: fresh cluster rollout.
```

### 4.5 Zot (registry)

Zot has no Django shell or admin CLI — users live in an htpasswd file
(mounted via Secret). Zot container is a Go binary with no shell or curl —
auth probe must run from the bastion node to the ClusterIP.

```bash
# (a) intended username (role hardcodes 'admin')
grep -E "zot_admin_user" \
  /Users/<operator>/repos/dmfdeploy/dmf-infra/k3s-lab-bootstrap/roles/stack/operator/zot/defaults/main.yml

# (b) live username — read from htpasswd Secret (just the username field)
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<aliyun-control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n zot \
    get secret zot-htpasswd -o jsonpath='{.data.htpasswd}' | base64 -d | cut -d: -f1"

# (c) auth probe against /v2/_catalog — from node to ClusterIP (zot has no shell)
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<aliyun-control-node-public-ip> <<'EOF'
# Read password from OpenBao via AppRole (external-secrets credentials)
SECRET_ID=$(sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n external-secrets \
  get secret openbao-approle -o jsonpath='{.data.id}' | base64 -d)
TOKEN=$(sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n openbao exec openbao-0 -- \
  bao write auth/approle/login role_id=f7322dda-1851-a915-5caf-04337449b84a secret_id="$SECRET_ID" -format=json | \
  python3 -c "import sys, json; print(json.load(sys.stdin)['auth']['client_token'])")
PW=$(sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n openbao exec openbao-0 -- \
  bao kv get -token="$TOKEN" -field=password secret/apps/zot/admin)
# Probe from node to zot ClusterIP
CLUSTER_IP=$(sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n zot get svc zot -o jsonpath='{.spec.clusterIP}')
curl -sS -o /dev/null -w 'http:%{http_code}\n' --max-time 5 -u "admin:$PW" http://$CLUSTER_IP:5000/v2/_catalog
EOF
```

```
Intended username: admin (hardcoded)
Live username:     admin (htpasswd secret)
Live auth probe:   fail (OpenBao password sha256:7a86d4744a06/35 chars → http:401)
Drift shape:       password-only
Workaround:        Path 2 — one-time in-pod htpasswd regeneration using the
                   OpenBao password value. See §5.2 below for remediation.
Permanent fix:     The zot role already recreates the htpasswd Secret from
                   the OpenBao value on each run (reconcile pattern). The
                   drift likely occurred because the htpasswd was generated
                   with a different password at initial bootstrap, before
                   OpenBao was seeded. Re-running the role with correct
                   OpenBao values should reconcile.
```

### 4.6 LibreNMS

LibreNMS is **not yet deployed** on aliyun-123. The `monitoring` namespace
contains only Grafana, Loki, Prometheus, and Promtail pods. No LibreNMS
deployment, secret, or service exists. The `191-zot-oidc.yml` and related
monitoring vertical playbooks that provision LibreNMS have not run on this
environment.

```bash
# (a) intended username
grep librenms_admin_username \
  /Users/<operator>/repos/dmfdeploy/dmf-infra/k3s-lab-bootstrap/roles/modules/infra-monitoring/librenms/defaults/main.yml

# (b) live users — not applicable (not deployed)
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<aliyun-control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n monitoring get pods -l app.kubernetes.io/name=librenms"
# → No resources found
```

```
Intended username: admin (hardcoded)
Live username:     N/A (not deployed)
Live auth probe:   N/A
Drift shape:       not deployed (defer until monitoring vertical is provisioned)
Workaround:        N/A
Permanent fix:     Audit again after LibreNMS playbook runs on aliyun-123.
```

---

## 5. Remediation strategy

Three paths, ranked by invasiveness. Pick per-app based on the drift shape
recorded in §4.

### 5.1 Path 1 — `-e` override (username-only drift, no role change)

For each drifted app where the password still works but the username
mismatches, document the override and add it to the operator's invocation.
Cheap, reversible, env-specific (not committed to repo).

NetBox is the model:

```bash
bin/run-playbook.sh aliyun-123 \
  ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml \
  -e netbox_sot_admin_username=admin
```

If multiple overrides accumulate (probable on aliyun-123 given the AWX+NetBox
combination), consider a follow-up wrapper (§5.4) so they don't have to be
remembered per invocation.

### 5.2 Path 2 — in-pod password resync (password drift, one-time)

When the live DB password no longer matches the Secret/OpenBao value, run
the app's password-reset command inside the pod, feeding the Secret value
via stdin. This is the **only write path** in this doc and explicitly
requires operator confirmation per `dmf-cluster-access` skill §0.

Per-app commands (extend as new apps are audited):

| App     | In-pod resync command                                                                                  |
|---------|--------------------------------------------------------------------------------------------------------|
| AWX     | `kubectl -n awx exec -i deploy/awx-web -- awx-manage shell -c "import sys; from django.contrib.auth import get_user_model; U=get_user_model(); u=U.objects.get(username='<u>'); u.set_password(sys.stdin.read()); u.save()"` <br> (stdin-piped, `--password-stdin` not available on AWX 24.6.1) |
| NetBox  | `kubectl -n netbox exec -i deploy/netbox -- python /opt/netbox/netbox/manage.py changepassword <u>`   |
| Forgejo | `kubectl -n forgejo exec -i deploy/forgejo -- /usr/local/bin/gitea admin user change-password --username <u> --password <stdin> --config /data/gitea/conf/app.ini` (verify exact flag set on this Forgejo version) |
| Authentik | App-admin-facts already handles this on every run — should not drift.                                |
| Zot     | Rebuild htpasswd Secret from OpenBao value + trigger rolling restart. The zot role already does this on every run (generates bcrypt from `vault_zot_admin_password` → patches Secret with hash annotation → pod restarts). A one-time `kubectl delete secret -n zot zot-htpasswd && bin/run-playbook.sh ... 331-registry-zot` should reconcile. |
| LibreNMS | `kubectl -n librenms exec -i deploy/librenms-frontend -- su -s /bin/sh librenms -c '/opt/librenms/lnms user:passwordreset <u> --password-stdin'` (verify on installed LibreNMS version) |

For AWX (confirmed — already executed 2026-05-14):

```bash
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<aliyun-control-node-public-ip> <<'EOF'
PW=$(sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n awx \
       get secret awx-admin-password -o jsonpath='{.data.password}' | base64 -d)
printf '%s' "$PW" | sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n awx \
  exec -i deploy/awx-web -- awx-manage shell -c "
import sys
from django.contrib.auth import get_user_model
U = get_user_model()
u = U.objects.get(username='<handle>')
u.set_password(sys.stdin.read())
u.save()
"
EOF
```

For Zot (confirmed password drift — 401):

```bash
# Option A: delete the stale htpasswd Secret and re-run the zot role
ssh -i ~/.ssh/id_ed25519_k3s_aliyun k3s-admin@<aliyun-control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n zot delete secret zot-htpasswd"
# Then re-run bootstrap-configure or just the zot playbook:
bin/run-playbook.sh aliyun-123 \
  ../dmf-infra/k3s-lab-bootstrap/playbooks/vertical-security/331-registry-zot.yml
```

Run **once** per app; the next `bootstrap-configure` run with any Path 1 overrides
should then authenticate successfully.

### 5.3 Path 3 — role-side patch (when the role assumes the wrong source)

If the role assumes a source for username/password that doesn't match the
live pattern, patch the role to **read live state** instead of assuming the
default. The existing precedent is `awx_integration_read_admin_password_from_cluster=true`
which reads the password from the k8s Secret rather than trusting a
`vault_*` default.

Concrete Path 3 candidates from today's session:

- **`awx-integration`** — add a task reading
  `awx_integration_admin_user` from the AWX CR spec
  (`kubectl -n awx get awx <name> -o jsonpath='{.spec.admin_user}'`)
  before the auth-wait task. qwen-right's "Option A". Mirrors the
  password-from-cluster pattern.
- **`forgejo-bootstrap`** — analogous: read the actual Forgejo admin username
  from the `forgejo-admin` k8s Secret (contains both `username` and `password`
  base64-encoded fields) before assuming `vault_bootstrap_admin_username`.
- **`netbox-sot`** — analogous: read the actual NetBox superuser name from
  the NetBox `manage.py shell` output (or from a known k8s Secret/CR
  field if one exists) before assuming `vault_bootstrap_admin_username`.
  Lower urgency than AWX because the workaround is just `-e ...=admin`.
- **`zot` (registry)** — the role already regenerates htpasswd from
  `vault_zot_admin_password` on every run and annotates the Secret with a
  hash annotation to trigger pod restart. The drift occurred because the
  initial htpasswd was generated before OpenBao was fully seeded. No role
  change needed — just ensure the Secret is deleted and the role re-runs.
  Path 3 here would be to add a reconciliation check that verifies the
  htpasswd hash matches the OpenBao value on each run.

Path 3 patches stay valuable *after* fresh rollout — they make the roles
robust to future drift, regardless of who creates the admin user.

### 5.4 Companion finding: cross-playbook variable-name fragmentation

Surfaced during run 9 / run 10 (2026-05-14): the same admin identity is
referenced under **different variable names** by different playbooks/roles,
so a single `-e` override does NOT cover every place the identity is needed.

| App | Provisioning roles (691-693) | CMS token playbooks (697-698) |
|---|---|---|
| AWX | `awx_integration_admin_user` (in `awx-integration` role) | `awx_admin_user` (in `697-cms-awx-token.yml:121` defaulting to `vault_bootstrap_admin_username \| default('dmfadmin')`) |
| Forgejo | `forgejo_admin_username` (in `forgejo` + `forgejo-bootstrap` roles) | `cms_forgejo_admin_user` (in `698-cms-netbox-forgejo-tokens.yml:399,414,438` defaulting to `'dev'`) |
| NetBox | `netbox_sot_admin_username` (in `netbox-sot` role) | `cms_netbox_admin_user` (hardcoded `'admin'` in `698-cms-netbox-forgejo-tokens.yml:27` — happens to match aliyun-123 live, so no override needed) |

**Effect on the workaround inventory:** when the live admin username
differs from the playbook default, each playbook that uses a *different*
variable name needs its own `-e` flag. On aliyun-123 this expands the
Path 1 override list from 3 to 5 username overrides:

```
-e netbox_sot_admin_username=admin       # 691-netbox-sot
-e forgejo_admin_username=<handle>            # 692-forgejo-bootstrap (covers both roles)
-e awx_integration_admin_user=<handle>        # 693-awx-integration
-e awx_admin_user=<handle>                    # 697-cms-awx-token  (NEW — same identity, different var)
-e cms_forgejo_admin_user=<handle>            # 698-cms-netbox-forgejo-tokens (NEW — same identity, different var)
```

**Path 3 candidate (codebase-level, low urgency until rollout):**
Consolidate to one canonical admin-username variable per app across roles +
playbooks. Options:

1. **Canonical var per app, set role-side, referenced everywhere.** E.g.
   define `awx_admin_user` once (in `awx` role defaults), have
   `awx-integration` + `697-cms-awx-token` both read it. Same for forgejo.
   `cms_*` playbooks become thin renamers if the underlying `*_admin_user`
   is set.
2. **Per-app set_fact at top of bootstrap-configure.yml.** A pre-play that
   resolves the canonical username for each app from a single source
   (live cluster query, OpenBao, or override) and exports a stable fact
   name for downstream plays. One override surface, all plays read the
   fact.
3. **Read-live pattern (Option A from §5.3 extended).** Each playbook
   queries the live cluster for the admin username at the start, ignoring
   role defaults entirely. Most robust against drift but most invasive
   change.

After a fresh rollout (§5.6) most of these `-e` overrides become
unnecessary anyway — the live cluster aligns with role defaults. Path 3
consolidation remains useful only as defense-in-depth.

### 5.5 Follow-up: per-env override wrapper (out of scope here)

Once §4 is filled in for `aliyun-123`, the set of `-e` overrides will be
stable per-env. A small wrapper under `dmf-env/bin/` could read a
per-env `drift-overrides.yml` and prepend the right flags automatically.
**Not in scope for this doc** — note it and defer.

### 5.6 Long term — fresh rollout

Layer-1 reset + full bootstrap aligns live state with playbook intent.
Burns aliyun-123 down. After rollout:

- Path 1 + Path 2 entries become deletable.
- Path 3 patches remain (they make future drift impossible by design).
- The audit doc collapses to a single "all green" snapshot per env.

The decision *when* to rollout aliyun-123 needs an ADR — explicitly
out of scope for this doc.

---

## 6. Acceptance criteria

This audit is "done" (for the current env) when:

1. All six per-app result blocks in §4 are filled in for `aliyun-123`.
2. For each app with `Drift shape ≠ none`, the workaround section gives
   a concrete `-e` override and/or Path 2 resync command. If the override
   isn't expressible with existing role vars, an issue is opened on the
   relevant repo and linked here.
3. `bin/run-playbook.sh aliyun-123 .../bootstrap-configure.yml <overrides>`
   completes all imported playbooks (`692 → 691 → 693 → 694 → 696 → 697
   → 698 → 699`) without authentication failures.
4. The audit is repeatable for a new env: just substitute the SSH key
   path, control-node IP, and run §4 commands top-to-bottom.

---

## 7. Out of scope (explicit)

To prevent scope creep:

- Implementing the per-env drift-overrides wrapper script (§5.4).
- Layer-1 realignment / fresh-rollout planning (§5.5).
- The forgejo-svc service user fix — already landed today as
  `dmf-infra@1d9d1eb`; that's a service user, not a human admin.
- AWX OIDC-vs-Basic-auth question — Basic auth works; OAuth client_credentials
  is a separate (larger) refactor. Today's session confirmed Basic auth is
  still accepted; the 401 was purely a credential issue.
- Other envs (hetzner-arm). The procedure here applies, but values + overrides
  will differ; audit those separately when the env is touched.

---

## 8. Critical files

Read-only references (don't edit these as part of the audit; edits belong
to the role-patch task once Path 3 is approved):

- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/{authentik,awx,awx-integration,forgejo,forgejo-bootstrap,netbox,netbox-sot,zot}/defaults/main.yml`
  — intended username/password resolution per app
- `dmf-infra/k3s-lab-bootstrap/roles/common/app-admin-facts/{defaults,tasks}/main.yml`
  — canonical app-admin reconcile pattern (used by Authentik + Zot-OIDC only)
- `dmf-infra/k3s-lab-bootstrap/roles/modules/infra-monitoring/librenms/defaults/main.yml`
  — LibreNMS admin defaults
- `dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml` — playbook chain
  order: `692 → 691 → 693 → 694 → 696 → 697 → 698 → 699`
- `dmf-env/inventories/aliyun-123/{hosts.ini,group_vars/all/main.yml}`
  — SSH wiring + env overrides (no `vault_bootstrap_admin_username`
  override here today; confirmed via grep)
- `.claude/skills/dmf-cluster-access/SKILL.md` §0 + §3 — secrets discipline
  + read-only operations pattern

---

## 9. Today's session — already-known commits (context for fresh agent)

Five fixes landed on `dmf-infra@main` 2026-05-13 / 2026-05-14 fixing the
NetBox datasource sync chain (separate workstream from this audit, but the
context that surfaced the drift pattern):

| Commit    | Fix                                                                                |
|-----------|------------------------------------------------------------------------------------|
| `46a57a7` | `netbox-sot`: block/rescue with `timeout: 30` around datasource sync wait          |
| `685b32b` | `netbox-sot`: compare `.status.value`, not the status dict, in until/assert        |
| `07d0e00` | `netbox-sot`: correct Forgejo internal DNS name (`forgejo-http` not `forgejo`)     |
| `1d9d1eb` | `forgejo-bootstrap`: PATCH includes `active: true` to keep service user activated  |
| `7b006ee` | `netbox-sot`: PATCH `source_url` alongside parameters; `default(.., true)` for empty `forgejo_internal_host` |

These are unrelated to admin-account drift but are mentioned so a fresh agent
doesn't re-discover them as "new" findings during the audit.
