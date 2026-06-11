---
status: draft
date: 2026-05-27
---
# DMF Zot Machine-Identity Service Account Plan

**Date:** 2026-05-27
**Decision:** [ADR-0033](../decisions/0033-zot-scoped-machine-write-service-account.md) (Zot machine writes use scoped `zot-svc`, not break-glass `admin`). Sibling of [ADR-0032](../decisions/0032-catalog-launcher-scoped-netbox-writer.md).
**Status:** ready for implementation
**Owner:** orchestrating Claude (this pane) writes the decision + plan; the *implementation lifting is dispatched to the second Claude pane via agent-bridge*. This pane verifies.

This plan has **two coupled parts**. Both edit playbook 630's credential handling, so they ship together.

---

## Part A — Playbook 630 runs on the control node (ALREADY DRAFTED, uncommitted)

**Status: done in the dmf-infra working tree by the orchestrator — do NOT redo, build on it.**

`dmf-infra/k3s-lab-bootstrap/playbooks/630-zot-seed-platform.yml` was changed from
`hosts: localhost`/`connection: local` to `hosts: k3s_control[0]`, `become: true`
(matching every sibling stage play 600/610/620/640/650). Rationale: the workstation-side
model assumed Tailscale to reach a CGNAT Zot ingress; that breaks on the single-node
sandbox lane (no Tailscale). The control node resolves + reaches its own ingress
(CoreDNS + Traefik), and 630 *cannot* run in the in-cluster EE pod because it is the play
that seeds awx-ee itself (chicken-and-egg). skopeo is now apt-installed on the node; creds
come from the wrapper-exported `vault_zot_admin_password`; the VERSION lookup runs
controller-side. `ansible-playbook --syntax-check` passed.

The implementer must **preserve these edits** and only change the credential variables
in Part B (admin → zot-svc).

---

## Part B — `zot-svc` scoped machine-write service account

Goal: introduce a write-scoped htpasswd service user `zot-svc`, repoint all machine
writers (630 + zot-mirror) to it, and demote `admin` to dormant break-glass. Per ADR-0033.

### Design constants (locked)
- **Username:** `zot-svc` (`<system>-svc` convention, see `dmf-infra/CLAUDE.md` §Service account naming).
- **Scope:** `["read", "create", "update"]` on `**` repos. No `delete`, no adminPolicy.
- **Secret path (OpenBao):** `secret/apps/zot/service`, exported var **`vault_zot_service_password`** (independent random; NOT the `admin` password).
- **`admin`:** stays as the sole `adminPolicy` user (break-glass), unused by automation.

### Touch-points (file by file)

**dmf-infra:**

1. `roles/stack/operator/zot/defaults/main.yml`
   - Add `zot_service_user: zot-svc` and
     `zot_service_password: "{{ vault_zot_service_password | mandatory }}"`.
   - Keep `zot_admin_user`/`zot_admin_password` as-is (break-glass).

2. `roles/stack/operator/zot/tasks/main.yml` (around lines 120-158)
   - The "Generate bcrypt htpasswd line" task currently emits ONE line for `admin`
     (shells out to `htpasswd -inB -C 10 <user>` via stdin, `delegate_to: localhost`,
     `no_log`). Generate a SECOND line for `zot_service_user` the same way.
   - The `zot-htpasswd` Secret's `stringData.htpasswd` must contain **both** lines
     (newline-joined). Update the StatefulSet's `htpasswd-hash` annotation to hash the
     combined content so a change to either user rolls the pod.

3. `roles/stack/operator/zot/templates/config.json.j2` (accessControl block, lines ~33-68)
   - **`_auth_enabled` (OIDC) branch:** add a `policies` entry under `repositories["**"]`
     for `users: ["{{ zot_service_user }}"]` with `actions: ["read","create","update"]`.
     Keep the existing `ops-admin` group policy and `adminPolicy.users: [admin]`.
   - **`zot_anonymous_read` (OIDC-off, current default) branch:** this is the important
     one. Today it sets `defaultPolicy: ["read","create","update","delete"]` — i.e. ANY
     authenticated user gets full write incl. delete. Tighten: `anonymousPolicy: ["read"]`,
     `defaultPolicy: ["read"]`, a `policies` entry granting `zot-svc`
     `["read","create","update"]`, and an `adminPolicy.users: ["{{ zot_admin_user }}"]`
     with full actions. (Net: anon read; zot-svc push; admin = break-glass full.)
   - Leave the third (`else`, no anonymous) branch consistent with the same shape.

4. `playbooks/630-zot-seed-platform.yml` (Part A already moved it to the node)
   - Repoint the play vars `zot_admin_user`/`zot_admin_password` → `zot_service_user`/
     `zot_service_password` (i.e. use `zot-svc` + `vault_zot_service_password`). Update the
     `_zot_user`/`_zot_pass` set_fact and the header comment block accordingly. The
     manifest HEAD-probes + skopeo `--dest-authfile` then authenticate as `zot-svc`.
   - Keep the ADR-0007 authfile/no_log/cleanup discipline intact.

5. `roles/base/zot-mirror/` (defaults + tasks + ESO secret + README)
   - `defaults/main.yml`: `zot_mirror_pull_creds_openbao_path: secret/apps/zot/service`,
     `zot_mirror_pull_creds_username: zot-svc`.
   - `tasks/main.yml`: the ExternalSecret pulls `property: password` from the admin path;
     repoint to the service path. (Pull is read-only, but mirroring also needs read on all
     repos — `zot-svc` has read, so fine.)
   - Update README references from `admin` → `zot-svc`.

6. `roles/stack/operator/openbao/tasks/main.yml` (eso-reader policy, lines ~1041-1075)
   - The eso-reader policy has globs `secret/data/apps/+/admin`, `.../+/breakglass`,
     `.../+/runtime`. **Add `secret/data/apps/+/service` (read)** so ESO can mount the
     `zot-svc` credential for zot-mirror. (Also check the second policy block near line
     930 that has an explicit `secret/data/apps/zot/admin` — add a matching
     `.../zot/service` if that block gates the same reader.)

**dmf-env (private):**

7. `bin/bootstrap-secrets.sh` — seed-bao `secret/apps/<app>/admin` loop (lines ~1508-1575)
   - This loop writes per-app break-glass admins. Add seeding for the NEW service path
     `secret/apps/zot/service` with `username=zot-svc` and an independently-generated
     random password (mirror however the admin passwords are generated — do NOT reuse the
     admin/bootstrap password).
   - Export `vault_zot_service_password` in the export-vars JSON (the block near line 1047
     that does the "compatibility copies"; add the new var so it reaches Ansible).
   - Follow the existing idempotency/migration guardrails (no-op if same value; the
     fail-closed unknown-username branch).

### Gotchas / cross-checks
- **Two repos.** dmf-infra (items 1-6) + dmf-env (item 7). Both needed or it 401s.
- **ESO glob.** If `secret/apps/zot/service` isn't covered by eso-reader, zot-mirror's
  ExternalSecret silently fails to sync → cron can't auth. Item 6 is mandatory.
- **htpasswd combined secret.** Both bcrypt lines in one `htpasswd` key, newline-joined.
- **OIDC-off branch is the live default** (`zot_oidc_enabled: false`). Get that branch
  right; the OIDC-on branch is currently dormant but keep it correct.
- **Don't touch pulls.** Consumer pods pull anonymously; leave `anonymousPolicy: read`.
- **`admin` stays in the htpasswd + adminPolicy** — it's break-glass, just unused by automation.

### Verification (this pane will confirm)
1. `ansible-playbook --syntax-check` on 630 + the zot role's site include.
2. `bin/bootstrap-secrets.sh` dry path / shellcheck for the dmf-env change.
3. Grep gate: no steady-state path references `secret/apps/zot/admin` or `zot_admin_*`
   except the break-glass/role-default definitions.
4. Live (operator-run, later): re-run zot role + seed-bao on the sandbox env, then 630;
   confirm push succeeds as `zot-svc` and zot-mirror cron authenticates.

### Branch / commit discipline
- Work on a feature branch in **each** repo (both default to `main`); do NOT push.
- Commit per-repo with ADR-0033 references; report back, leave push to the operator.
