---
status: executed
date: 2026-05-15
---
# DMF Lifecycle-Configure Bootstrap Completion Plan

> **SUPERSEDED 2026-05-17** by the
> [DMF Aliyun-123 Lifecycle-Configure Follow-Ups Plan 2026-05-17](./DMF%20Aliyun-123%20Lifecycle-Configure%20Follow-Ups%20Plan%202026-05-17.md)
> as the active tracker. The four gaps named here all shipped (`dmf-infra@a891ecb`,
> `440ec61`, `8d20e71`) and the 2026-05-17 plan absorbs every follow-up surfaced
> by the live-cluster validation run. This document is retained only as the
> investigation-narrative record for those three commits.

**Date:** 2026-05-15
**Investigator:** Qwen Code (session resumed after crash)
**Scope:** `dmf-infra` role gaps discovered on aliyun-123 green-run; affects all fresh clusters

---

## 1. Context

The aliyun-123 green-run (2026-05-14) completed `bootstrap-configure.yml` with `failed=0` and the operator successfully enrolled an Authentik passkey. However, the NMOS deploy path via dmf-cms remained broken. Investigation revealed four suspected root causes, which were narrowed to two codebase gaps:

- ~~#4 (OpenBao userpass/ops-admin missing)~~ — **closed.** False positive. Userpass IS enabled on aliyun-123, `ops-admin` user exists and authenticates with `app-admin-writer` + `app-runtime-writer` policies.
- **~~#1 (NetBox dmf-cms-svc zero perms)~~ — confirmed real, but is a codebase gap, not an aliyun-123-specific misconfiguration.**
- ~~#2 (AWX NMOS job templates missing) + #3 (dmf-runbooks repo empty)~~ — **collapse into one upstream blocker:** the Forgejo dmf-runbooks repo was never populated with playbook content.

These are infrastructure code gaps. They would hit any fresh cluster provisioned through the `lifecycle-configure` chain. Aliyun-123 is not unique — it simply surfaced them because it was the first cluster where the NMOS path was exercised post-bootstrap.

**Related docs:**
- [Green-run handoff 2026-05-14](../handoffs/DMF%20Aliyun-123%20Bootstrap%20Green-Run%20%2B%20ADR-0023%20%2B%20Runner%20Spike%20Handoff%202026-05-14.md)
- [13-walls history](../reviews/) — prior bootstrap attempts on hetzner-arm
- [ADR-0012](../decisions/0012-configure-stage-distinct-from-provision.md) — Configure is a distinct lifecycle stage from Provision
- [ADR-0013](../decisions/0013-media-function-catalog-model.md) — media function catalog model
- [ADR-0014](../decisions/) — AWX project layout and launcher playbook conventions
- [ADR-0016](../decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md) — AWX control-node SSH execution model

---

## 2. Gap A — dmf-runbooks Forgejo repo never populated

### Current state

The `forgejo-bootstrap` role (imported by `692-forgejo-bootstrap.yml`) performs these steps for dmf-runbooks:

1. **Create repo via API** (`roles/stack/operator/forgejo-bootstrap/tasks/main.yml:238`):
   ```yaml
   - name: Create dmf-runbooks repo
     ansible.builtin.uri:
       url: "{{ forgejo_api_base }}/repos/{{ forgejo_svc_user }}/dmf-runbooks"
       method: POST
       ...
   ```

2. **Push README only** (`tasks/main.yml:275-284`):
   ```yaml
   - name: Push initial README to dmf-runbooks repo
     ansible.builtin.uri:
       url: "{{ forgejo_api_base }}/repos/{{ forgejo_svc_user }}/dmf-runbooks/contents/README.md"
       method: POST
       body:
         content: "{{ '# dmf-runbooks\n...' | b64encode }}"
         message: "Initial README for catalog launcher playbooks"
         branch: main
   ```

3. **Mirror repos** (`tasks/main.yml:352-373`) — governed by `forgejo_mirror_repos` variable, which is an **empty dict `{}`** in `roles/stack/operator/forgejo-bootstrap/defaults/main.yml:20`. No environment-level override exists for aliyun-123 (checked `dmf-env/inventories/aliyun-123/group_vars/all/`).

On aliyun-123, verified via Forgejo API:
- `dmf-runbooks` contains **only** `README.md` (single blob).
- No `playbooks/` directory, no launcher yml files.
- AWX project `dmf-runbooks` syncs "successfully" because it has a valid repo — just nothing useful in it.

The local workspace `dmf-runbooks/` directory (sibling to dmf-infra in the umbrella) contains:
- `playbooks/launch-nmos-cpp.yml`
- `playbooks/teardown-nmos-cpp.yml`
- Plus `README.md`, `LICENSE`, `NOTICE`, `VERSION`, `CONTRIBUTING.md`

These files have never been pushed to the in-cluster Forgejo instance on aliyun-123. The local git `origin` remote points at the environment's Forgejo URL (for example `https://forgejo.<cluster-domain>/forgejo-svc/dmf-runbooks.git`) but there is no playbook step that performs the push.

### Downstream consequences

The `awx-integration` role (693) creates catalog job templates by referencing playbooks in the `dmf-runbooks` project:

```yaml
# roles/stack/operator/awx-integration/defaults/main.yml:130-144
awx_catalog_job_templates:
  - name: "launch-nmos-cpp"
    playbook: "playbooks/launch-nmos-cpp.yml"
    project: "dmf-runbooks"
  - name: "teardown-nmos-cpp"
    playbook: "playbooks/teardown-nmos-cpp.yml"
    project: "dmf-runbooks"
```

When AWX receives the JT creation request, it validates that the playbook exists in the referenced project's synced revision. Since dmf-runbooks contains only `README.md`, AWX returns **HTTP 400** (playbook not found). The 693 role silently swallows this with `failed_when: false` on the JT creation task (line ~1092), so the playbook continues and the operator never sees the error.

### Proposed design

**Extend the forgejo-bootstrap role** to seed configured repos from a local workspace checkout path. Add a new task file `roles/stack/operator/forgejo-bootstrap/tasks/seed-local-repos.yml` that:

1. For each repo in a new variable `forgejo_seed_repos` (dict), checks whether the repo's main branch contains content beyond the initial README (idempotency guard: skip if already seeded).
2. If not yet seeded, uses the Forgejo API to create files in the target repo, mirroring the structure from a specified local path.
3. Pushes all files from the seed directory to the Forgejo repo's main branch, preserving the directory structure.

**Idempotency strategy:** After seeding, the repo will contain multiple files. The guard checks for the presence of a sentinel file (e.g., `playbooks/.seeded`) or checks file count > 1. If already seeded, skip.

**Authentication:** Uses `forgejo-svc` credentials already stored in OpenBao (read by 692). No new secrets required.

### Open design questions for operator

1. **Source of seed content:** Where does the role find the local dmf-runbooks checkout?
   - *Option A:* Control-node filesystem path (passed as `forgejo_seed_dmf_runbooks_path` variable). The AWX EE would need the repo mounted or available on the control node.
   - *Option B:* Operator's umbrella workspace (pushed from Mac via SSH/API during playbook run). Adds latency and complexity.
   - *Option C (recommended):* The seed content is already on the control node as part of the dmf-infra checkout (since dmf-runbooks is a sibling directory in the umbrella, it could be rsync'd or the playbook could reference it relative to the playbook root).

2. **Update semantics:** One-shot init, or re-seed on every `lifecycle-configure` run?
   - *Recommendation:* One-shot. Guard checks for sentinel file. Subsequent updates to launcher playbooks flow through normal git push to the Forgejo repo (operator or CI), not through the bootstrap role. This keeps the bootstrap role focused on initial state.

3. **Hook position:** Which playbook number / position?
   - *Recommendation:* Extend 692 (forgejo-bootstrap) since it already creates the repos and holds the `forgejo-svc` credentials. Add seed step after the README push, before the mirror loop (line ~352).

### Codex review answer — 2026-05-16

This plan is directionally aligned with the project goal: it unblocks the core
DMF loop (CMS catalog → AWX launcher → NetBox lifecycle state → NMOS
experiment). That is not polishing or hardening; it directly advances the
current experiment-phase goal of proving the commissioning/catalog model.

Answers to the three operator decisions:

1. **Source of seed content:** choose **Option C in spirit**, but implement it
   as an explicit controller-side seed path rather than assuming
   `dmf-runbooks` is available on the control node or embedded inside the
   `dmf-infra` checkout. The role should take a `forgejo_seed_repos` entry
   with a source path resolved by the controller running Ansible. A default may
   point at the umbrella sibling checkout when present, but the implementation
   must not hardcode an operator home path. Longer term, ADR-0014's cleaner
   shape is canonical git mirror/push; local API seeding is an acceptable
   experiment-phase unblock.
2. **Update semantics:** choose **one-shot init**. Do not use `file count > 1`
   as the guard, and do not require a synthetic sentinel unless there is a
   strong reason. Guard on the required content:
   `playbooks/launch-nmos-cpp.yml`, `playbooks/teardown-nmos-cpp.yml`, and
   optionally `VERSION`/`README.md`. Once those files exist, updates should
   flow through ordinary git push/mirror/CI, preserving traceability.
3. **Hook position:** keep this in **692 `forgejo-bootstrap`**, after repo
   creation and before `693-awx-integration` tries to sync AWX projects and
   create catalog job templates. In the current role, the mirror-config block
   is already before the README-only push, so implement this as "replace or
   extend the README-only seeding step" rather than relying on the stale line
   number in this draft.

Small doc nits folded into this revision:
- ADR-0016 is the AWX control-node SSH execution-model ADR, not the catalog
  lifecycle ADR. ADR-0012 and ADR-0013 are the catalog lifecycle references.
- The AWX variable is `awx_catalog_job_templates`, not
  `awx_catalog_job_configs`.
- Public prose should avoid concrete operator domains and local paths; use
  `<cluster-domain>` and `<secure-store>` placeholders.
- NetBox v4 token probes should use `Authorization: Bearer <token>`, not
  `Authorization: Token <token>`.

---

## 3. Gap B — dmf-cms-svc has zero NetBox permissions

### Current state

The `netbox-sot` role (imported by `691-netbox-sot.yml`) creates groups, users, and object permissions for exactly **two** service integrations:

| Integration | Group | Permission scope | Tasks lines |
|---|---|---|---|
| AWX | `awx-readonly` | `view` on 19 object types | tasks/main.yml:188-475 |
| LibreNMS | `librenms-writer` | `view` + `add`/`change` on select types | tasks/main.yml:233-545 |

The permission creation pattern for AWX (the model to follow):
1. **Group lookup/create** via NetBox REST API (`tasks/main.yml:188-231`)
2. **ObjectPermission script generation** — Python script creates an `ObjectPermission` named `awx-readonly`, assigns object types and actions (`view`), then binds to group (`tasks/main.yml:266-308`)
3. **Script execution** via `kubectl exec` into NetBox pod (`tasks/main.yml:383-387`)
4. **User lookup/create + group assignment** — `awx-netbox` user created/updated, assigned to `awx-readonly` group (`tasks/main.yml:396-475`)

**Zero references to `cms` or `dmf-cms` exist anywhere in the netbox-sot role.** A grep across tasks, defaults, templates, and vars returns no matches.

The `698-cms-netbox-forgejo-tokens.yml` playbook creates the `dmf-cms-svc` user via Django `get_or_create` and generates an API token (lines 122-178), but:
- Does NOT create a NetBox group
- Does NOT create an ObjectPermission
- Does NOT assign the user to any group
- User has default Django settings: no `is_staff`, no `is_superuser`, no permissions

The `697-cms-awx-token.yml` playbook grants `dmf-cms-svc` permissions **inside AWX only** (workflow execution), not in NetBox.

**Confirmed live state on aliyun-123:** `GET /api/dcim/sites/` with the dmf-cms-svc token returns `403 Forbidden: {"detail":"You do not have permission to perform this action."}`

### Proposed design

Extend the `netbox-sot` role to handle `dmf-cms-svc` analogously to `awx-readonly`:

1. **Add defaults** (`roles/stack/operator/netbox-sot/defaults/main.yml`):
   ```yaml
   cms_netbox_enabled: true
   cms_netbox_group: "dmf-cms-readonly"
   cms_netbox_username: "dmf-cms-svc"
   cms_netbox_permissions:
     - name: "dcim-readonly"
       actions: ["view"]
       object_types:
         - "dcim.site"
         - "dcim.device"
         - "dcim.interface"
         - "dcim.cable"
         - "dcim.device_role"
         - "dcim.device_type"
         - "dcim.platform"
         - "dcim.virtualchassis"
     - name: "ipam-readonly"
       actions: ["view"]
       object_types:
         - "ipam.prefix"
         - "ipam.ipaddress"
         - "ipam.vlan"
         - "ipam.vlangroup"
         - "ipam.vrf"
         - "ipam.service"
   ```

2. **Add task block** in `roles/stack/operator/netbox-sot/tasks/main.yml`, following the AWX pattern:
   - Group lookup/create via NetBox REST API (POST to `/api/users/groups/`)
   - ObjectPermission creation script (Python, modeled on lines 268-308)
   - Script execution via `kubectl exec` into NetBox pod
   - User lookup + group assignment (the user already exists from 698, so this is just group binding)

3. **Guard:** `when: cms_netbox_enabled | bool` — allows per-cluster override.

4. **Playbook position:** 691 already runs in `lifecycle-configure`. No new playbook needed — just extend the existing netbox-sot role. The 698 playbook runs later (698 in the configure chain) and creates the user; the group/perm steps in 691 would need to run after user creation OR handle the case where the user doesn't exist yet (create group+perms, user joins later).

   **Ordering consideration:** If 691 runs before 698, the user doesn't exist yet. The ObjectPermission and group can be created before the user exists (they're independent), but the group assignment step needs the user. Three options:
   - *Option A:* Move the group+perm creation into 698 (where the user is created)
   - *Option B:* Keep in 691, make the user group-assignment step conditional on user existence (skip silently if user not yet created)
   - *Option C:* Keep the permission model in 691 and have 691 also create/reconcile the `dmf-cms-svc` NetBox user and group membership before 698 mints the token
   - *Codex recommendation:* **Option C.** Do not skip the user assignment in 691, because that likely requires a second configure run before dmf-cms works. `netbox-sot` should own the NetBox permission model and service-account group membership; `698-cms-netbox-forgejo-tokens.yml` should mint/persist the token for the already-permissioned user. If implementation keeps user creation in 698, then the group assignment must move into 698 as well; silent skip is the weak option.

**Codex scope correction:** The interim read scope must cover what dmf-cms
actually queries today: `dcim.site`, `dcim.device`, and `ipam.service`.
`ipam.service` is required for `/api/catalog`, which joins YAML catalog entries
to NetBox lifecycle tags by querying `/api/ipam/services/?name=...`.

### Future-state north star (operator directive)

> Long-term direction is granular user/group/role-based permission controls in dmf-cms via Authentik backend. This pragmatic broad-read is the interim approach; a future ADR will redesign once Authentik-fronted RBAC is wired into dmf-cms.

The proposed `dcim.*` + `ipam.*` broad-read group is an **interim** measure. The Authentik backend integration (already in place for operator auth) will eventually provide fine-grained RBAC within dmf-cms itself, at which point the NetBox service-account permissions can be tightened to match per-role access patterns.

---

## 4. Bundled fix — 693 failure-masking via `failed_when: false`

### The bug

In `roles/stack/operator/awx-integration/tasks/main.yml`, the job template creation loop (line ~1092) includes:

```yaml
failed_when: false
```

This silently swallows **all** failures from the AWX API, including:
- HTTP 400: playbook not found in project (the dmf-runbooks empty-repo case)
- HTTP 404: project not found
- HTTP 500: internal AWX error
- Network errors: timeout, connection refused

The operator receives no feedback that JT creation failed. The playbook proceeds to `PLAY RECAP` with `failed=0`, creating the illusion of a successful run. This is what burned investigation hours — the failure was present but invisible.

### Proposed fix

Do **not** special-case HTTP 400 as acceptable. AWX uses 400 for actionable
configuration errors such as "playbook not found", so accepting it preserves
the bug.

Preferred pattern:

1. Look up the job template by name first.
2. If missing, create it and accept only `201`.
3. If present, PATCH fields that must converge and accept only `200`.
4. Remove `failed_when: false` from required catalog job-template operations.

The AWX API returns clear error messages in the response body. A failed
playbook run with a 400 error is far more actionable than a silent skip.

**Justification:** This bug directly contributed to the investigation time spent on this issue. The "fail silent" pattern is only appropriate for truly optional steps (e.g., creating a resource that may already exist). Job template creation is a **required** step — if the playbooks referenced by `awx_catalog_job_templates` don't exist, the catalog is broken and the operator must know immediately.

---

## 5. Out of scope (captured for follow-up)

### 5.1 Break-glass JSON missing `root_token`

`DEPLOYMENT.md` §7 (lines 219-220) states:

> "Root token is NOT disposed after bootstrap. It's needed by `app-admin-facts` for per-app secret writes. Disposal is a later operational step."

However, the openbao role's save task (`roles/stack/operator/openbao/tasks/main.yml`, ~line 1530) does **not** include `root_token` in `openbao_breakglass_content`. On aliyun-123, the break-glass JSON at `<secure-store>/openbao-breakglass/aliyun-123/openbao-keys-automation.json` contains unseal keys, AppRole credentials, and service account passwords — but no root token.

This is doc-vs-implementation drift. Needs its own ADR or bugfix: does the live code reflect intent, or do the docs need updating? The `app-admin-facts` role uses the root token for secret writes; if it's not persisted, those writes would fail on rerun. (On aliyun-123 they succeed because the root token was retained in memory during the single bootstrap run.)

### 5.2 Cross-playbook variable-name fragmentation

The green-run handoff (§3.2, §5.4) flags inconsistent variable naming across the 691–698 playbook chain. Examples: `netbox_sot_admin_username` vs `netbox_admin_username`, `forgejo_svc_user` vs `forgejo_admin_user`. Already flagged elsewhere; not part of this plan's scope.

### 5.3 NetBox drf-spectacular partial failure mode

The drf-spectacular patch workflow (`roles/stack/operator/netbox/tasks/main.yml:590-656`) can leave the Deployment stuck if the ConfigMap creation fails silently. Documented in feedback memory; not part of this plan.

---

## 6. Verification plan

After implementation, re-run `bin/run-playbook.sh aliyun-123 bootstrap-configure.yml` (or the subset of plays that cover 691/692/693). Expected post-state:

| Check | Expected result | How to verify |
|---|---|---|
| Forgejo dmf-runbooks contains `playbooks/` | `playbooks/launch-nmos-cpp.yml` + `playbooks/teardown-nmos-cpp.yml` present | Forgejo API: `GET /api/v1/repos/forgejo-svc/dmf-runbooks/git/trees/main:playbooks` |
| AWX dmf-runbooks project synced | `scm_revision` is non-empty, `last_update_failed: false` | AWX API: `GET /api/v2/projects/?name=dmf-runbooks` |
| NMOS job templates exist | `media-launch-nmos-cpp` and `media-finalise-nmos-cpp` (or `launch-nmos-cpp`/`teardown-nmos-cpp`) in AWX | AWX API: `GET /api/v2/job_templates/` |
| dmf-cms-svc has NetBox perms | `GET /api/dcim/sites/` returns 200 with count > 0 | `curl -H 'Authorization: Bearer <cms-token>' <netbox-url>/api/dcim/sites/` |
| dmf-cms /api/catalog returns non-error | HTTP 200 with catalog entries (status != "error") | `curl <cms-ingress>/api/catalog` |
| 693 fails loud on JT error | Playbook exits with non-zero if AWX returns 400/404 for JT creation | Intentionally remove a playbook file from dmf-runbooks, re-run 693, confirm failure |

---

## 7. Test plan

### Molecule tests (dmf-infra)

If molecule tests exist for the affected roles:

- **forgejo-bootstrap:** Add a test case that seeds a local repo and verifies the target repo contains the expected files via Forgejo API assertions.
- **netbox-sot:** Add a test case for `cms_netbox_enabled: true` that verifies the `dmf-cms-readonly` group and ObjectPermission are created.
- **awx-integration:** Add a test case that verifies JT creation fails (not silently) when the referenced playbook is missing from the project.

### Playbook smoke tests

- Run `691-netbox-sot.yml --check --diff` against a test cluster with `cms_netbox_enabled: true` — confirm the group+perm tasks are included in the play.
- Run `692-forgejo-bootstrap.yml --check --diff` with `forgejo_seed_repos` configured — confirm the seed step is included.
- Run `693-awx-integration.yml --check --diff` — confirm JT creation tasks are included and no longer masked by `failed_when: false`.

### Integration test (post-deploy)

After full `bootstrap-configure.yml` run on aliyun-123:
1. `bin/unseal-openbao.sh aliyun-123 --status` — confirm OpenBao healthy
2. Hit `/api/catalog` on dmf-cms — confirm 200 with non-error entries
3. Launch an NMOS job via AWX — confirm playbook executes successfully

---

## 8. Completion status (2026-05-17)

**Status:** Complete. Active tracking moves to
[DMF Aliyun-123 Lifecycle-Configure Follow-Ups Plan 2026-05-17](DMF%20Aliyun-123%20Lifecycle-Configure%20Follow-Ups%20Plan%202026-05-17.md).

### Shipped commits (`dmf-infra@main`)

| Commit | Topic |
|---|---|
| `a891ecb` | feat(lifecycle-configure): seed repos, CMS perms, fail-loud JT — Gap A + B + C from §2/§3/§4 |
| `f1ba770` | fix(forgejo-bootstrap): seed-local-repos exclude .git and binary files — Gap A bug #1 (superseded) |
| `440ec61` | fix(forgejo-bootstrap): seed via deny-list (`.git/`) instead of allow-list patterns — Gap A bug #2 (final) |
| `8d20e71` | fix(awx-integration): trigger AWX project sync per catalog project — follow-on discovered via Gap C's fail-loud behavior |

### Verification (§6 checks, live cluster aliyun-123)

| # | Check | Result |
|---|---|---|
| 7 | Forgejo dmf-runbooks contains `playbooks/` | ✅ implicit (AWX synced revision `aea4a518…` requires those files in the SCM) |
| 8 | AWX dmf-runbooks project synced | ✅ `last_updated=2026-05-17T11:04`, `last_update_failed=false` |
| 9 | Catalog JTs exist | ✅ `media-launch-nmos-cpp` (id=15) + `media-finalise-nmos-cpp` (id=16) with correct project/playbook/EE bindings |
| 10 | dmf-cms-svc has NetBox perms | ✅ HTTP 200 on `/api/dcim/sites/` (count=1) and `/api/ipam/services/` (count=10); previously 403 |
| 11 | dmf-cms `/api/catalog` reachable | ✅ structural (endpoint exists, OIDC-gated as designed; content validation needs browser session) |
| 6 (bonus) | 693 fails loud on real JT error | ✅ proven during run-1: `failed_when: false` removed, surfaced HTTP 400 "Playbook not found for project" — uncovered the catalog-sync gap that became `8d20e71` |

### Session record

[DMF Aliyun-123 Lifecycle-Configure Completion Handoff 2026-05-17](../handoffs/DMF%20Aliyun-123%20Lifecycle-Configure%20Completion%20Handoff%202026-05-17.md)
— per-commit walk, empirical proof of the `8d20e71` design, procedural
notes on worker discipline slips during the session.

### Items from §5 still deferred

- §5.1 Break-glass JSON missing `root_token` → Class D.1 in follow-ups plan
- §5.2 Cross-playbook variable-name fragmentation → Class B.3 in follow-ups plan
- §5.3 NetBox drf-spectacular partial failure → Class D.3 in follow-ups plan

---

### 2026-05-19 cross-ref — NMOS launcher restructuring

This plan unblocked NMOS catalog launches on `aliyun-123`. The first launch
(AWX job 44, 2026-05-17) then failed for a separate reason: the launcher's
hardcoded Hetzner private-IP map doesn't fit aliyun-123. That failure
triggered the
[DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19](./DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md),
which restructures the catalog launcher's *internal* implementation (Helm
chart + EE-as-runtime) without changing the lifecycle-configure chain this
plan delivered. The Forgejo `dmf-runbooks` seeding gap fixed here remains
correct; only the launcher's transport changes.
