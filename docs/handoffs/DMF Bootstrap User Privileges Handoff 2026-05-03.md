# DMF Bootstrap User Privileges — Session Handoff 2026-05-03

> **Read this first.** Self-contained handoff for a fresh session with no
> prior chat memory. Picks up after commit `3d8b83d` on `dmf-infra` main.

## 0. The one-line summary

`<operator>` (the OIDC bootstrap user) is not Authentik superuser. Earlier session
left a working plan to fix it via a one-line blueprint flip. Plan is written,
not yet applied. Three scaffolding playbooks need cleanup. Audit of `<operator>`
admin status across the rest of the stack is partly done and deferred.

## 1. Environment at a glance

- **Operator host:** Mac mini. Claude Code runs here. Never SSH back into it.
- **Cluster:** 3-node Hetzner ARM. Control plane #1 is reachable via the
  dmf-env wrapper, which handles inventory + secrets + OpenBao session.
- **Public apex:** `dmf.example.com`. Apps on host-root subdomains
  (`auth`, `forgejo`, `grafana`, `netbox`, `awx`, `librenms`, `registry`,
  `console`).
- **Cluster access from Mac:** **Do not** assume local `kubectl` is wired up.
  Run cluster commands by writing one-shot Ansible playbooks and invoking
  them via `bin/run-playbook.sh hetzner-arm <playbook>`. The wrapper handles
  break-glass loading, OpenBao session, and remote exec via the control node.
- **Working directory:** `<repos>/dmf-infra`.

## 2. Repo state

```
~/repos/dmf-infra    main    HEAD 3d8b83d  (clean)
~/repos/dmf-env      main    (private inventory + run-playbook.sh wrapper)
```

Recent commits worth knowing:

| SHA | Title |
|---|---|
| `3d8b83d` | Add bootstrap user admin privilege audit and promotion playbooks (scaffolding — partial) |
| `fd9407d` | Fix NetBox token creation in 698-cms-netbox-forgejo-tokens.yml |
| `7e0bbf7` | Refactor DMF Console token pipeline and fix playbook numbering |

## 3. The active task: promote `<operator>` to Authentik superuser

### Where things stand

A plan was written and presented; user has not yet approved/applied it.

**Plan file:** `<home>/.claude/plans/ops-admin-superuser-blueprint.md`

### What needs to happen (one-line change + cleanup)

#### Step 1 — flip `is_superuser` on the `ops-admin` group

`k3s-lab-bootstrap/roles/stack/operator/authentik/files/blueprints/10-baseline-groups.yaml`:

```diff
   - model: authentik_core.group
     id: dmf-group-ops-admin
     state: present
     identifiers:
       name: ops-admin
     attrs:
       name: ops-admin
-      is_superuser: false
+      is_superuser: true
       attributes:
         dmf_role: ops-admin
```

That is the entire substantive change. Authentik resolves `is_superuser` at
request time from group membership; the user row's own flag stays `False`,
which is correct Authentik behavior (matches built-in `authentik Admins`).

#### Step 2 — delete the failed scaffolding from commit `3d8b83d`

```bash
git rm k3s-lab-bootstrap/playbooks/promote-<operator>-authentik-admin.yml
git rm k3s-lab-bootstrap/playbooks/audit-<operator>-admin-simple.yml
git rm k3s-lab-bootstrap/playbooks/audit-<operator>-admin-privileges.yml
```

Reason: `promote-<operator>-authentik-admin.yml` was an imperative `ak shell -c`
attempt that never worked because of nested kubectl/sh/Python escaping.
The blueprint flip replaces it. The two `audit-<operator>-admin-*.yml` playbooks
were one-shot survey diagnostics; their findings live in this handoff.

#### Step 3 — apply

```bash
cd ~/repos/dmf-env
bin/run-playbook.sh hetzner-arm \
  ../dmf-infra/k3s-lab-bootstrap/playbooks/vertical-security/110-authentik.yml
```

The Authentik blueprint reconciler picks up the change automatically. No pod
restart needed.

#### Step 4 — verify

Login as `<operator>` via passkey at `https://auth.dmf.example.com`; admin UI at
`/if/admin/` should be visible.

Or, programmatically (write as a one-shot playbook — direct kubectl from the
Mac is not wired up):

```yaml
- name: Verify <operator> superuser status
  hosts: k3s_control[0]
  become: true
  gather_facts: false
  tasks:
    - ansible.builtin.command:
        argv:
          - sudo
          - k3s
          - kubectl
          - -n
          - authentik
          - exec
          - deploy/authentik-worker
          - --
          - ak
          - shell
          - -c
          - >-
            from authentik.core.models import User;
            u = User.objects.get(username="<operator>");
            print(u.is_superuser, list(u.ak_groups.values_list("name", flat=True)))
      register: r
    - ansible.builtin.debug: var=r.stdout
```

Expected output: `True ['ops-admin', ...]`. (Note — `User.is_superuser` is a
property on Authentik that returns `True` if **any** group is superuser, so
the printed value is `True`, not `False`.)

#### Step 5 — commit + push

```bash
git add k3s-lab-bootstrap/roles/stack/operator/authentik/files/blueprints/10-baseline-groups.yaml \
        k3s-lab-bootstrap/playbooks/promote-<operator>-authentik-admin.yml \
        k3s-lab-bootstrap/playbooks/audit-<operator>-admin-simple.yml \
        k3s-lab-bootstrap/playbooks/audit-<operator>-admin-privileges.yml
git commit -m "Promote ops-admin group to superuser in Authentik blueprint

Replaces the imperative promote-<operator>-authentik-admin.yml attempt. Authentik's
native pattern is group-level is_superuser — flipping this flag means every
ops-admin member (including <operator>) inherits superuser at request time, and the
blueprint reconciler keeps it idempotent across rollouts.

Removes three scaffolding files from commit 3d8b83d that were one-shot
diagnostic / experimental work.
"
git push origin main
```

### Why this approach (not user-level)

Two alternatives were considered and rejected:

- **User-level `is_superuser: true` in `15-ops-user-webauthn.yaml.j2`** —
  binds superuser to one specific username, doesn't match Authentik's
  group-driven RBAC pattern, future second admin needs another code change.
- **Imperative Django shell** — what was attempted and abandoned; nested
  shell escaping makes the script unmaintainable.

Group-level matches the rest of the stack (`ops-admin` is already the gate
for admin-level access in Zot, Grafana, NetBox, AWX, Forgejo) and Authentik's
own built-in `authentik Admins` group works the same way.

### Trade-off (deliberate)

Anyone added to `ops-admin` becomes Authentik superuser. That's correct for
this lab — `ops-admin` is the "full operator" tier, not a soft read/write
group; the rest of the stack already grants it total power.

## 4. How to run cluster commands from this environment

Shorthand reminder: **the Mac doesn't have direct kubectl wired up**. Don't
try `kubectl get pods` from the local shell — it will fail with
`connection refused: localhost:8080`. Instead:

```bash
# Always invoke through the wrapper from dmf-env
cd ~/repos/dmf-env
bin/run-playbook.sh hetzner-arm <playbook-path>
```

The wrapper:

1. Sources OpenBao break-glass JSON from `<secure-store>/openbao-breakglass/hetzner-lab/openbao-keys-automation.json`
2. Establishes the OpenBao operator session
3. Renders the kv-v2 secret payload into a temp Ansible vars file
4. Invokes `ansible-playbook` against the Hetzner control node

For ad-hoc cluster checks, write a tiny YAML playbook in
`k3s-lab-bootstrap/playbooks/` (or `/tmp/`) that runs `kubectl exec` via
`ansible.builtin.command` with `argv:` (heredoc + cmd: >- breaks shell
quoting — see §6.1).

## 5. Audit findings: `<operator>` privilege status across the stack

From the survey done before this handoff (commit `3d8b83d`):

| App | Status | Note |
|---|---|---|
| **Authentik** | ⚠ NOT SUPERUSER | Fixed by Step 1 above |
| **Forgejo** | ✗ User not found via public API | Likely OAuth auto-create issue, deferred |
| **NetBox** | ❓ Needs admin token to audit | Deferred |
| **Grafana** | ❓ Needs admin creds to audit | Deferred |
| **Zot** | ✗ OIDC repo-level only | Known design gap (see §7) |
| **AWX** | ❓ Manual UI check | Deferred |
| **LibreNMS** | ❓ Manual UI check | Deferred |

After the Authentik fix, the next audit pass should:

1. Pull NetBox admin token from OpenBao at `secret/apps/netbox/sot/admin`,
   query `/api/users/?username=<operator>`, confirm `is_superuser`.
2. Pull Grafana admin password from OpenBao at `secret/apps/grafana/admin`,
   query `/api/users/lookup?loginOrEmail=<operator>`, confirm `isAdmin`.
3. Investigate why Forgejo doesn't show `<operator>` — OAuth provisioning flow may
   not be auto-creating users, or the user has a different login name.
4. AWX/LibreNMS — likely manual UI verification first, then doctrine.

## 6. Tribal knowledge from the prior session

### 6.1 — Heredoc + Ansible shell module is a footgun

This pattern looks fine but breaks in subtle ways:

```yaml
# DON'T
- ansible.builtin.shell:
    cmd: >-
      sudo k3s kubectl ... exec deploy/foo -- /bin/sh -c "
      cat <<'PY' | python /app/manage.py shell | tail -n 1
      ...python code...
      PY"
```

Two failure modes hit during the prior session:

1. **`cmd: >-` (folded scalar)** strips newlines, so the heredoc collapses
   onto one line and Python sees the body as `manage.py shell` arguments,
   not stdin. `argparse` then fails with
   `unrecognized arguments: import json from users.models...`
2. Even with `cmd: |-` the outer double-quoted shell argument fights the
   heredoc.

Working pattern (used in `698-cms-netbox-forgejo-tokens.yml` after the fix):

```yaml
- name: Build cmd as a literal block
  ansible.builtin.set_fact:
    _the_cmd: |-
      cat <<'PY' | /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py shell | tail -n 1
      ...python...
      PY

- name: Run via argv
  ansible.builtin.command:
    argv:
      - sudo
      - k3s
      - kubectl
      - --kubeconfig
      - /etc/rancher/k3s/k3s.yaml
      - -n
      - netbox
      - exec
      - deploy/netbox
      - --
      - /bin/sh
      - -c
      - "{{ _the_cmd }}"
  register: result
```

### 6.2 — `no_log: true` hides real errors

Several tasks in `698-cms-netbox-forgejo-tokens.yml` had `no_log: true` and
the failure surfaced as a useless `"censored"` line. To debug, temporarily
add a `debug:` task showing `stdout/stderr/rc` *before* the parse step, then
remove it once fixed.

### 6.3 — NetBox v4 User model surprises

- No `is_staff` or (in some queries) `is_active` field on `User.objects.get_or_create(defaults={...})`.
  Strip those — only set fields the model accepts.
- NetBox v4 uses **v2 tokens**: full token = `TOKEN_PREFIX + token.key + "." + token.token`.
  Bearer auth: `Authorization: Bearer <full_token>`. The DB only stores
  `token.key` — the secret half is only available at creation time, so it
  must be captured to OpenBao on the first run.

### 6.4 — Authentik runtime layout

- Image runs Python at `python` (no `/opt/venv/bin/python`).
- Manage entrypoint is `manage.py` at `/manage.py`, not `/app/manage.py`.
- Idiomatic shell is **`ak shell -c '<python>'`**, not `python manage.py shell`.
- For declarative config, the blueprint reconciler is the right tool —
  imperative `ak shell` should only be the escape hatch for one-shot data
  fixes that don't fit a blueprint shape.

### 6.5 — OpenBao session role

`roles/common/openbao-session/` (added in commit `7e0bbf7`) consolidates the
OpenBao operator login pattern. Use it — don't paste the 9-task block.

```yaml
- ansible.builtin.include_role:
    name: common/openbao-session
  vars:
    openbao_session_breakglass_file: <secure-store>/openbao-breakglass/hetzner-lab/openbao-keys-automation.json

# After include, these facts exist:
#   _openbao_session_pod
#   _openbao_session_client_token
```

### 6.6 — Zot known gap (still unresolved)

`<operator>` via Authentik OIDC has **repository** access in Zot (read/create/update/
delete via `ops-admin` group → repo policy), but **no admin API access** for
e.g. token creation. This is because Zot's `adminPolicy.users` only honors
htpasswd accounts, not OIDC group membership.

Deferred. Three options were sketched out previously:
1. Add `<operator>` to the htpasswd file alongside `admin` (breaks pure-OIDC model)
2. Extend Zot config to support `adminPolicy.groups` (may need upstream/custom image)
3. Separate htpasswd service account for token APIs (cleanest split, more creds to rotate)

The bootstrap htpasswd `admin` user's password is at OpenBao
`secret/apps/zot/admin` (managed by `roles/common/app-admin-facts` from
`vertical-security/191-zot-oidc.yml`). Retrieve via the OpenBao session
pattern above.

## 7. Layer-6 token pipeline status (context, not active work)

The DMF Console token wiring stack is in place after commit `7e0bbf7`:

```
650 dmf-cms                    (CMS deploy)
691 netbox-sot                 (NetBox SoT users + tokens)
692 forgejo-bootstrap          (Forgejo admin token)
693 awx-integration            (AWX integration)
694 born-inventory             (NetBox-driven inventory)
696 cms-authentik-api          (CMS ↔ Authentik API token)
697 cms-awx-token              (CMS ↔ AWX token)
698 cms-netbox-forgejo-tokens  (CMS ↔ NetBox + Forgejo tokens)  ← fixed in fd9407d
699 cms-smoke-test             (final integration smoke)
```

698 was failing on NetBox token creation before commit `fd9407d` — root cause
was the heredoc footgun in §6.1 and the NetBox v4 model surprise in §6.3.
Now passes end-to-end.

## 8. Where everything lives

- **Plan file (active):** `<home>/.claude/plans/ops-admin-superuser-blueprint.md`
- **Authentik blueprint to edit:** `k3s-lab-bootstrap/roles/stack/operator/authentik/files/blueprints/10-baseline-groups.yaml`
- **Files to delete:**
  - `k3s-lab-bootstrap/playbooks/promote-<operator>-authentik-admin.yml`
  - `k3s-lab-bootstrap/playbooks/audit-<operator>-admin-simple.yml`
  - `k3s-lab-bootstrap/playbooks/audit-<operator>-admin-privileges.yml`
- **Apply playbook:** `k3s-lab-bootstrap/playbooks/vertical-security/110-authentik.yml`
- **OpenBao break-glass JSON:** `<secure-store>/openbao-breakglass/hetzner-lab/openbao-keys-automation.json`
- **Wrapper:** `~/repos/dmf-env/bin/run-playbook.sh hetzner-arm <path>`
- **Lifecycle entry:** `k3s-lab-bootstrap/lifecycle-provision.yml` (canonical layer/vertical map; new playbooks register here)
- **EBU mapping reference:** `<note-store>/DMF EBU Mapping (2026-04-25).md`
- **Memory index:** `<home>/.claude/projects/-Users-<operator>-repos-dmf-infra/memory/MEMORY.md`

## 9. Pickup steps for a fresh agent

1. Read this whole document.
2. Read `<home>/.claude/plans/ops-admin-superuser-blueprint.md` (plan).
3. Confirm with user before applying — they last said "plan mode" and have
   not yet approved.
4. On approval: do §3 Steps 1–5 in order.
5. After verifying, ask whether to continue with the deferred audits
   (NetBox / Grafana / Forgejo / AWX / LibreNMS — see §5).

## 10. Things to NOT do

- Don't try `kubectl` directly from the Mac shell.
- Don't reach for `ak shell -c '...'` for things a blueprint can express.
- Don't use `cmd: >-` with heredocs (see §6.1).
- Don't add `is_staff` or other Django-User-style fields when creating
  NetBox v4 users.
- Don't paste the OpenBao login block into new playbooks — use the
  `common/openbao-session` role.
- Don't promote `<operator>` at the user level in the blueprint instead of at the
  group level — the group-level approach is the chosen design (see §3 "Why
  this approach").
