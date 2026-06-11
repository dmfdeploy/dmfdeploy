---
status: superseded
date: 2026-05-06
superseded_by: "DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md"
---
# Move 1 Gate 2 — Pivot to Path A for Catalog Launchers
> Supersedes: [Move 1 Gate 2 Fix - AWX EE Pod Service Account Mount.md](Move%201%20Gate%202%20Fix%20-%20AWX%20EE%20Pod%20Service%20Account%20Mount.md), [Move 1 Gate 2 — AWX Integration + Launch NMOS.md](Move%201%20Gate%202%20%E2%80%94%20AWX%20Integration%20%2B%20Launch%20NMOS.md)
> **Superseded by** [DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md](DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md) — see frontmatter.

> ⚠️ **SUPERSEDED 2026-05-23** by the
> [DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19](./DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md)
> Lane B implementation and [ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md).
>
> Catalog launchers now run in-cluster via an AWX EE pod + Helm chart. Path A
> remains canonical only for **AWX → infrastructure plays** (693-class —
> `awx-integration`, `netbox-sot`, `forgejo-bootstrap`, etc.). Preserved below
> as the historical record of why Path A was chosen on 2026-05-06.

**Date:** 2026-05-06
**Status:** Implemented and validated 2026-05-06 — `media-launch-nmos-cpp` (AWX job 285) ran end-to-end. See STATUS.md operator notes and the closure handoff `DMF Item 15 NMOS ConfigMap Schema Fix Closure 2026-05-07.md`. **Superseded 2026-05-23 — see banner above.**
**Authors:** session with Kubernetes Operator + Architecture Reviewer agents
**Supersedes:** in-cluster service-account auth implementation attempts in `dmf-runbooks` (commits `f669415`..`e8bc0f4`)
**Related ADRs:** ADR-0012 (Configure stage), ADR-0014 (AWX project layout), ADR-0016 (control-node SSH via cloud-init + OpenBao), **ADR-0025 (Accepted 2026-05-23 — supersedes for media catalog launchers)**

---

## TL;DR

Stop trying to make AWX EE pods authenticate to the Kubernetes API via an in-cluster ServiceAccount mount. Pivot the NMOS-CPP catalog launchers to the same execution model the layer playbooks (640, 693) already use: **SSH to the k3s control node and run kubernetes.core.k8s against `/etc/rancher/k3s/k3s.yaml` under `become: true`** (Path A, ADR-0016).

ADR-0012's Configure-vs-Provision stage split is unaffected. Only the auth-mechanism implementation detail changes.

---

## Problem statement

The NMOS-CPP catalog launchers (`launch-nmos-cpp.yml`, `teardown-nmos-cpp.yml`) in `dmf-runbooks` cannot successfully run in AWX. After 20+ commits attempting to fix the in-cluster ServiceAccount auth path, the latest failure is:

```
TASK [Read in-cluster service account token] ***********************************
fatal: [localhost]: FAILED! => {"changed": false,
  "msg": "file not found: /var/run/secrets/kubernetes.io/serviceaccount/token"}
```

The AWX EE pod is running without a ServiceAccount mounted. Each prior fix has revealed the next layer of breakage.

---

## Investigation findings

### Cluster state (verified 2026-05-06 via SSH to control node)

| Check | Expected | Actual |
|---|---|---|
| ServiceAccount `awx-ee` in `awx` namespace | Exists with cluster RBAC | **Does not exist** |
| ServiceAccount `awx-runner-sa` in `awx` namespace | (Created by `service-account.yml` task) | **Exists** (per 640 playbook log line 60-61) |
| `pod_spec_override` on `main_instancegroup` (id=1, controlplane) | YAML with serviceAccountName | **Empty string** |
| `pod_spec_override` on `main_instancegroup` (id=2, default) | YAML with serviceAccountName | **Empty string** |
| `execution_environment_id` on job templates `media-launch-nmos-cpp`, `media-finalise-nmos-cpp` | 2 ("AWX EE (latest)") | **2** (correct) |

### Why pod_spec_override is empty (Kubernetes Operator agent finding)

The `awx` operator role at `<umbrella-path>/dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx/templates/awx-instance.yml.j2` line 106 sets `spec.ee_pod_spec_override` on the AWX CR.

**`spec.ee_pod_spec_override` is not a valid field on the AWX operator CRD.** The 640 playbook log line 70 shows:

```
[WARNING]: unknown field "spec.ee_pod_spec_override"
```

The kubernetes.core.k8s apply succeeds (returns `ok`), but the field is silently dropped. The AWX operator never propagates anything to the InstanceGroup. The three "fix" commits in dmf-infra (`09f979b`, `3db787d`, `1a00671`) iterated on Jinja2 rendering of the template — none checked whether the CRD accepted the field name.

`pod_spec_override` is a column on `main_instancegroup` and must be PATCHed via the AWX REST API at `/api/v2/instance_groups/{id}/`, not via the AWX CR.

### Why awx-ee SA doesn't exist (Kubernetes Operator agent finding)

The SA created by `service-account.yml` is named `awx-runner-sa`, not `awx-ee`. Naming was inconsistent across original ADR-0012 documentation and the implementation. The 640 log shows `awx-runner-sa` was applied successfully — but because pod_spec_override was never propagated, it was never wired into EE pods either.

### Why the 693 awx-integration role didn't fix it

`<umbrella-path>/dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml` contains zero tasks that:
- Create a SA named `awx-ee`
- PATCH an InstanceGroup `pod_spec_override` via `/api/v2/instance_groups/`
- Touch the Kubernetes API for SA / RBAC at all

The role manages credentials, projects, inventories, job templates, SSH keys, OpenBao secrets. The SA / pod-spec work was placed in the `awx` operator role (640), not 693. Re-running 693 will never fix this.

### Commit churn signal (`dmf-runbooks` log)

```
e8bc0f4 fix(launchers): wrap include_role in block to support environment vars
a00db04 fix(nmos-cpp): remove kubeconfig parameter to allow K8S_AUTH_* env vars
c6a39b0 fix(nmos-cpp): add kubeconfig parameter to kubernetes.core.k8s tasks
47fff52 fix: correct in-cluster Kubernetes authentication per expert review
80b749d fix: use environment variables for in-cluster Kubernetes authentication
a3b7d0d fix: configure kubeconfig from in-cluster service account in NMOS launchers
081c9c4 fix: simplify kubernetes.core.k8s tasks for service account auth
5c5fe14 fix: delegate kubernetes tasks to control node with proper kubeconfig
6c40ba1 fix: add explicit in-cluster kubernetes authentication
6a8baa7 fix: remove kubeconfig parameter to enable proper in-cluster auth
2f8f84c fix: define netbox_api_token and add error handling for service lookup
403dd7b Simplify playbooks to use automatic in-cluster authentication
e8cbf17 Remove package install step - kubernetes.core collection handles dependencies
e08ffb4 Use apt to install Python Kubernetes dependencies
e8cfbac Use shell pip instead of ansible.builtin.pip to avoid packaging dependency issue
ef16a3a Install packaging dependency for kubernetes module
d5ee3bd Fix kubeconfig generation with embedded token and CA certificate
98011b1 Install kubernetes Python library before running Kubernetes module tasks
4e712e3 Create in-cluster kubeconfig from service account token
f669415 Remove explicit kubeconfig path to use in-cluster authentication
```

Twenty consecutive commits, each revealing the next layer. This is the signal to step back, not to commit again.

---

## Architecture review (independent agent)

Architecture Reviewer's framing:

> ADR-0012's in-cluster SA token approach is technically correct and is what a mature K8s-native AWX deployment should look like long-term. Nothing in the design is wrong. But the *implementation surface area* required to make it work is large and the failure modes are silent. This is not a one-more-fix situation. Each fix has revealed the next layer.

The five coupled layers required for in-cluster auth to work:

1. Custom EE image with `kubernetes` Python pkg + `kubernetes.core` collection, hosted in Zot, registered as an AWX `ExecutionEnvironment`
2. `awx-ee` ServiceAccount + ClusterRole + RoleBinding in the right namespace(s)
3. AWX `InstanceGroup.pod_spec_override` correctly serialized
4. `execution_environment` set on every catalog job template
5. `K8S_AUTH_*` env plumbing into every k8s task with `default(omit)` for portability

Currently broken: layers 2, 3, and partially 5.

### Why pivot is right *for this phase*

- Project is in **experiment phase** (per `dmfdeploy/CLAUDE.md` and the strategic review). Optimize for *learning whether the architecture survives contact with reality*, not for polish.
- Move 1's thesis-killer questions are: "does the catalog model survive a real launch? Does the EBU Configure-stage split hold up?" Those are dmf-cms ↔ AWX ↔ NetBox-tag-flip questions. **None depend on the EE's auth mechanism.**
- ADR-0016 already chose Path A (SSH-via-control-node) for the layer playbooks. Catalog playbooks diverging is the smell that produced the 20-commit fix loop.

### Tradeoff matrix (from architecture review)

| Axis | (a) Persist with SA token | (b) Pivot to SSH-via-control-node |
|---|---|---|
| Time-to-working | Unknown — 20+ commits, next blocker likely. Days. | Hours. The mechanism is already working for 69x. |
| Operational complexity | High — 5 coupled layers, silent drift modes | Low — one execution model platform-wide |
| Future flexibility | Native K8s-native pattern, GitOps-friendly | Loses pure-K8s aesthetic; gains uniformity |
| Pattern consistency | Diverges from ADR-0016 | Matches ADR-0016 |
| Phase fit (experiment) | Fights infrastructure instead of testing the thesis | Maximizes contact with reality on the catalog model itself |

---

## Decision

**Pivot the NMOS-CPP catalog launchers to Path A (SSH-via-control-node, ADR-0016).**

ADR-0012's Configure-vs-Provision stage split — the actual decision in ADR-0012 — survives intact. Only the auth-mechanism implementation detail changes.

The SA / pod_spec_override work in `dmf-infra` is **preserved as deferred capability**, not deleted. It is correct architecture for a mature platform; it is just not yet load-bearing. ADR-0012 receives an "Implementation note" pointing to ADR-0016.

---

## Implementation plan

### Phase 1 — Rewrite launcher playbooks in `dmf-runbooks`

**Files to change:**
- `playbooks/launch-nmos-cpp.yml`
- `playbooks/teardown-nmos-cpp.yml`

**Pattern (target shape):**

```yaml
---
# NMOS IS-04/05 — Configure: Launch (ADR-0012, ADR-0016)
# Runs on the k3s control node via SSH (Machine credential from ADR-0016).
# kubernetes.core.k8s reads /etc/rancher/k3s/k3s.yaml natively under become.
- name: NMOS-CPP configure — launch workloads
  hosts: device_roles_k3s-control-plane[0]   # NetBox-derived inventory group; verify exact name
  become: true
  gather_facts: false
  vars:
    nmos_stage: configure
  tasks:
    - name: Include nmos-cpp role (configure stage)
      ansible.builtin.include_role:
        name: nmos-cpp
```

**Deletions from current launcher:**
- The `slurp` of `/var/run/secrets/.../token`
- The `K8S_AUTH_HOST`/`K8S_AUTH_SSL_CA_CERT`/`K8S_AUTH_API_KEY` env block
- The `block:` wrapper added in commit `e8bc0f4` (no longer needed without env block)

**Role behavior:** `nmos-cpp/tasks/{provision,configure,finalise}.yml` already use `kubernetes.core.k8s` with no explicit `kubeconfig` parameter (per commit `a00db04`). Under `become: true` on the control node, `kubernetes.core.k8s` will pick up `/etc/rancher/k3s/k3s.yaml` automatically. **No role changes required.**

The slurp tasks at the top of `provision.yml` and `finalise.yml` (lines 7-27 of each) that read `k8s_token_file` and `k8s_ca_file` with `ignore_errors: true` are now dead code; they harmlessly fail silently. Cleaning them up is optional and out of scope for this pivot — leave for a follow-up housekeeping pass.

### Phase 2 — Verify AWX wiring

Both job templates (`media-launch-nmos-cpp`, `media-finalise-nmos-cpp`) need:

- **Inventory:** the NetBox dynamic inventory that resolves `device_roles_k3s-control-plane` (or the equivalent group name — confirm via `kubectl exec awx-postgres-15-0 -- psql ... main_inventory` or a quick `awx` UI check).
- **Machine credential:** the `awx-to-k3s-control-node` SSH credential created by ADR-0016 / 693 awx-integration role. Already attached to the layer 69x job templates; needs to be attached to these too.
- **Execution environment:** can be reverted to default — no longer need a custom EE with kubernetes.core collection mounted in-pod-spec, because the playbook executes against the remote control node, not in the EE pod.

Verification SQL on the control node:
```bash
ssh k3s-admin@<control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n awx exec awx-postgres-15-0 -- \
   psql -U awx -d awx -A -t -c \
   \"SELECT jt.name, jt.unifiedjobtemplate_ptr_id, c.name AS cred
     FROM main_jobtemplate jt
     LEFT JOIN main_jobtemplate_credentials jtc ON jtc.jobtemplate_id = jt.unifiedjobtemplate_ptr_id
     LEFT JOIN main_credential c ON c.id = jtc.credential_id
     WHERE jt.unifiedjobtemplate_ptr_id IN
       (SELECT unifiedjobtemplate_ptr_id FROM main_unifiedjobtemplate
        WHERE name IN ('media-launch-nmos-cpp','media-finalise-nmos-cpp'));\""
```

If the Machine credential is not attached, the awx-integration role's `attach credentials` task pattern (used for 69x) needs a one-line addition for these two templates. **Do that work in `dmf-infra`, not in `dmf-runbooks`.**

### Phase 3 — Test end-to-end

1. Push pivot commits to `dmf-runbooks` `origin/main` (Hetzner Forgejo at `forgejo.dmf.example.com`).
2. Wait for AWX project sync (or trigger manually).
3. Launch `media-launch-nmos-cpp` from AWX UI.
4. Expected: playbook runs on `k3s-node-03` via SSH, creates `nmos` namespace, registry StatefulSet, node Deployments, Services, ConfigMaps; flips NetBox tag from `lifecycle:bootstrapped` → `lifecycle:active`.
5. Verify on cluster: `kubectl -n nmos get all` and check NetBox service tags.
6. Run `media-finalise-nmos-cpp` and confirm teardown.

### Phase 4 — Documentation updates

- Add an "Implementation note" section to `docs/decisions/0012-configure-stage-distinct-from-provision.md` pointing to ADR-0016 and clarifying that catalog launchers currently use SSH-to-control-node, not in-cluster SA.
- Update `STATUS.md` operator notes to reflect the pivot.
- Update `docs/handoffs/` with a 2026-05-06 handoff covering the pivot decision and what was preserved as deferred.
- **Do not edit ADR-0012 itself** beyond an addendum — the stage-split decision is unchanged.

### Phase 5 — Preserve deferred capability

Leave the SA / pod_spec_override work in `dmf-infra` in place. Document it as deferred in the `awx` operator role README (or a comment block in the template) noting:

- The `spec.ee_pod_spec_override` field on the AWX CR is invalid; if revisiting, use the AWX REST API to PATCH `/api/v2/instance_groups/{id}/` with a YAML `pod_spec_override` payload directly.
- The SA name `awx-runner-sa` is what's deployed; don't rename without sweeping callers.
- Re-enable when there is a clear need (e.g., catalog playbooks that *must* run in-cluster for latency / network / blast-radius reasons).

Optionally raise an issue/ticket so this isn't lost.

---

## Risks and open questions

1. **Inventory group name.** The exact resolved group for the k3s control plane in the NetBox-driven inventory needs verification. Best guess: `device_roles_k3s-control-plane`, but this depends on NetBox device role slugs and the AWX inventory plugin's transformation rules. Confirm before the rewrite — getting this wrong means the playbook never reaches a host.

2. **Multiple control-plane nodes.** The cluster has 3 HA control-plane nodes (k3s-node-01/02/03). `device_roles_k3s-control-plane[0]` picks the first. That's fine for these playbooks (idempotent k8s operations against the API server), but document the choice. Alternative: target k3s-node-03 specifically (current SSH default per dmf-cluster-access skill), or use `delegate_to` + `run_once`.

3. **Become privileges.** The `k3s-admin` user has sudo (per cloud-init). `become: true` works. Verify the SSH credential's become method is set correctly (`sudo`).

4. **NetBox API access from control node.** The playbook also calls NetBox to flip lifecycle tags. The control node has outbound HTTPS to `netbox.dmf.example.com` — this works for the layer 69x playbooks today. Same pattern, same network path. No change needed.

5. **`netbox_api_token` variable.** Currently provided via job template extra_vars (per commit `2f8f84c` and the awx-integration role's PATCH for netbox_api_token). Continues to work unchanged in the pivot.

6. **Concurrent launches.** Both launchers operate on the singleton `nmos` namespace. If multiple operators run them simultaneously, expect race conditions. Out of scope for Move 1; flag for future hardening.

---

## What we are explicitly NOT doing

- **Not deleting** the `awx-ee` / `awx-runner-sa` ServiceAccount work, ClusterRoleBinding, or the `pod_spec_override` template fragments in `dmf-infra`. Preserve as deferred capability.
- **Not modifying** ADR-0012's core decision (Configure-vs-Provision stage split). Only adding an Implementation note.
- **Not modifying** ADR-0016. The pivot extends its sanctioned execution model to one more class of playbook; doesn't change the model.
- **Not building** a custom EE image with kubernetes.core baked in. The default AWX EE already has kubernetes.core; the issue was never the collection, it was the auth path.
- **Not switching** to a kubeconfig-from-OpenBao model. SSH-to-control-node is simpler and already proven.
- **Not cleaning up** the dead slurp tasks in `nmos-cpp/tasks/{provision,finalise}.yml`. Out of scope; harmless; trigger a follow-up housekeeping pass after Move 1 lands.

---

## Artifacts to clean up

Inventory of every artifact discovered during the investigation that is dead, broken, misleading, or made obsolete by this pivot. Grouped by repo and by severity. **Severity legend:**

- **`[BLOCKER]`** — must be addressed in Phases 1-2 for the pivot to work
- **`[OBSOLETE]`** — dead code/config; remove during the pivot or as immediate follow-up
- **`[BROKEN]`** — actively wrong; silently fails; preserve only if explicitly deferred and labelled
- **`[STALE-DOC]`** — documentation that no longer reflects reality
- **`[DRIFT]`** — duplicated state across repos that will diverge again
- **`[FOLLOW-UP]`** — safe to leave during pivot; sweep in a later housekeeping pass

### `dmf-runbooks/` (this repo)

| Severity | Artifact | Action |
|---|---|---|
| `[BLOCKER]` | `playbooks/launch-nmos-cpp.yml` — slurp of `/var/run/secrets/.../token`, K8S_AUTH_* env block, `block:` wrapper from commit `e8bc0f4`, `hosts: localhost` | Replace per Phase 1 target shape |
| `[BLOCKER]` | `playbooks/teardown-nmos-cpp.yml` — same as above | Replace per Phase 1 target shape |
| `[OBSOLETE]` | `roles/nmos-cpp/tasks/provision.yml` lines 6-27: three tasks (`Get in-cluster service account token`, `Get in-cluster CA certificate`, `Set in-cluster authentication variables`) under the `# In-cluster Kubernetes authentication setup` banner | Delete entirely; under SSH+become they have no purpose. Variables `k8s_api_key`/`k8s_ca_cert`/`k8s_host` set there are not consumed by the rest of the role anyway. |
| `[OBSOLETE]` | `roles/nmos-cpp/tasks/finalise.yml` lines 6-27: same three-task block | Delete entirely (same reason) |
| `[OBSOLETE]` | Comments in role tasks referencing `# In-cluster authentication` / `# ADR-0012 Phase 8 in-cluster auth` style headers | Remove or reword to reflect SSH-via-control-node |
| `[DRIFT]` | The entire bundled `roles/nmos-cpp/` directory is a copy of the canonical role in `dmf-media/roles/nmos-cpp/`. Code drift between the two has already bitten us once (this session: missing `kubeconfig: default(omit)` in one copy that we then added then removed). | Decision needed (separate from this pivot): either (a) keep this repo as the authoritative copy and delete from dmf-media, (b) make dmf-media authoritative and pull via `requirements.yml` here, or (c) make dmf-media itself the AWX project. ADR-0014 D1 may need revisiting. **Track as `[FOLLOW-UP]` so the pivot is not blocked.** |
| `[FOLLOW-UP]` | 20+ commit log of failed in-cluster auth attempts (`f669415` .. `e8bc0f4`). Not a code artifact, but signals the repo's git log is noisy. | Leave; do not rewrite history. Note in handoff that the trail is informational. |

### `dmf-infra/k3s-lab-bootstrap/`

| Severity | Artifact | Action |
|---|---|---|
| `[BROKEN]` | `roles/stack/operator/awx/templates/awx-instance.yml.j2` ~line 106: `spec.ee_pod_spec_override: ...` | The AWX CRD does not have this field; it is silently dropped (640 log line 70 warning). **Remove entirely OR convert to a commented-out block** with a `TODO(deferred):` referencing this plan. Three commits (`09f979b`, `3db787d`, `1a00671`) iterated this template without ever validating the field name — leaving it in place keeps the bear trap armed. |
| `[BROKEN]` / `[FOLLOW-UP]` | The `service-account.yml` task (in the `awx` operator role) that creates `awx-runner-sa` + ClusterRoleBinding | Currently creates a SA that nothing uses (since `pod_spec_override` was never propagated). Two options: (a) delete the SA + RBAC tasks now to avoid orphaned cluster-scoped permissions, (b) keep as deferred with a clear comment block explaining it is not yet wired. Recommend **(a) delete now** — the cluster carries no value from a permissioned-but-unused SA, and re-introducing it is a 5-minute task when needed. The future ADR for SA-based auth (if ever) should write fresh tasks against the AWX REST API path, not via the CR. |
| `[OBSOLETE]` | Any `defaults/main.yml` or `vars/main.yml` keys feeding the broken template (e.g. `ee_pod_spec_override`, `awx_ee_serviceaccount_name`) | Remove if the task is removed; keep only if the deferred-capability path is preserved. Be consistent. |
| `[OBSOLETE]` | The `awx-integration` role's job-template `execution_environment` setting work (commits `79c0d9d`, `cd558ae`, `1a00671`, `3db787d`, `09f979b`, `8c582c1`) | **Keep** — setting an EE on the job template is correct regardless of auth mechanism. Only the `pod_spec_override` plumbing is obsolete. |
| `[FOLLOW-UP]` | If the awx-integration role doesn't yet attach the Machine credential to `media-launch-nmos-cpp` and `media-finalise-nmos-cpp` job templates | Add the same attachment pattern already used for 69x. **In scope for Phase 2.** |

### `dmfdeploy/` (umbrella docs)

| Severity | Artifact | Action |
|---|---|---|
| `[STALE-DOC]` | `docs/plans/Move 1 Gate 2 Fix - AWX EE Pod Service Account Mount.md` | Add a header banner: `> **Superseded by [Pivot to Path A for Catalog Launchers 2026-05-06](Move%201%20Gate%202%20-%20Pivot%20to%20Path%20A%20for%20Catalog%20Launchers%202026-05-06.md)**. The SA-mount approach proved infeasible in the project's experiment phase; see new plan for findings.` Do not delete the file — it is the failed plan that this one supersedes and the trail matters. |
| `[STALE-DOC]` | `docs/decisions/0012-configure-stage-distinct-from-provision.md` | Add an "Implementation note (2026-05-06)" section pointing to ADR-0016 and clarifying that catalog launchers currently use SSH-to-control-node, not in-cluster SA. The stage-split decision itself is unchanged. **In scope for Phase 4.** |
| `[STALE-DOC]` | `docs/plans/Move 1 Gate 2 — Trials and Tribulations 2026-05-05.md` | Add a closing footnote referring to this plan and the pivot decision; the trials/tribulations entry remains historically accurate. |
| `[STALE-DOC]` | `docs/handoffs/DMF Move 2 Closure + Path A Handoff 2026-05-04.md` and `docs/handoffs/DMF Function Catalog + Move 1 Planning Handoff 2026-05-04.md` | Both pre-date this pivot; safe to leave. The new 2026-05-06 handoff (Phase 4) becomes the authoritative pointer. |
| `[STALE-DOC]` | `docs/architecture/DMF Function Catalog Model.md` | Audit for any prose that assumes EE-pod in-cluster auth; reword to be neutral about execution model (catalog model survives either path). |
| `[STALE-DOC]` | `STATUS.md` operator notes section (`<!-- HUMAN-START -->` block) | Rewrite the "In-flight work" entry for Move 1 + Catalog to reflect the pivot. **In scope for Phase 4.** |
| `[FOLLOW-UP]` | `docs/decisions/INDEX.md` | If the SA-mount path becomes a formally-rejected alternative, add an ADR-0017 (or extend ADR-0012's status) recording the rejection and rationale. Not required for the pivot itself. |

### AWX runtime state on the cluster

| Severity | Artifact | Action |
|---|---|---|
| `[OBSOLETE]` | ServiceAccount `awx-runner-sa` in `awx` namespace (if created by 640) | Removed by re-running 640 after `service-account.yml` is deleted — or via direct `kubectl delete sa awx-runner-sa -n awx` after the role tasks are gone. Verify no other workload references it before deleting. |
| `[OBSOLETE]` | ClusterRole + ClusterRoleBinding granting cluster-scoped access to `awx-runner-sa` | Same — remove with the SA, in the same playbook run. Cluster-scoped grants for an unused identity are the worst kind of orphaned permission. |
| `[OBSOLETE]` | The empty `pod_spec_override` columns on `main_instancegroup` (id=1, id=2) | Already empty; no cleanup. Confirms nothing was applied. |
| `[KEEP]` | Execution Environment "AWX EE (latest)" (id=2, image `quay.io/ansible/awx-ee:latest`) | Still used by job templates' `execution_environment_id`. The EE pod no longer needs a SA mount because the playbook executes on the remote host, not in the EE pod. |
| `[KEEP]` | Machine credential `awx-to-k3s-control-node` (from ADR-0016) | Required for the pivot. Verify it is attached to the two NMOS job templates in Phase 2. |
| `[KEEP]` | Job templates `media-launch-nmos-cpp`, `media-finalise-nmos-cpp` with `execution_environment_id = 2` | Templates themselves are correct; only their attached credential set may need updating in Phase 2. |
| `[FOLLOW-UP]` | `/tmp/openbao-vars-*` files on operator workstation from the many playbook runs (per `dmf-cluster-access` skill §0.6 hygiene) | Sweep with `find /tmp -name 'openbao-vars-*' -mmin +30 -delete` after the pivot lands. Independent housekeeping. |
| `[FOLLOW-UP]` | `/tmp/dmf-playbook-logs/` from the 20+ run cycle | Audit for any leaked secrets per `dmf-cluster-access` §0.6 (`grep -iE 'password\|token\|secret\|api_key'`). Rotate anything found, then delete the offending log. |

### Memory / agent state

| Severity | Artifact | Action |
|---|---|---|
| `[STALE-DOC]` | `~/.claude/projects/-Users-<operator>-repos-dmfdeploy/memory/dmf_runbooks_awx_sanity_check.md` (the "5 operational concerns" memory) | Update or supersede with a new memory recording the pivot decision and that the in-cluster SA path is deferred. The original concerns may now be moot or relabeled. |
| `[STALE-DOC]` | Any other agent memory entries referencing in-cluster SA as the intended path for catalog launchers | Audit `~/.claude/projects/-Users-<operator>-repos-dmfdeploy/memory/MEMORY.md` index for SA-related entries; correct or supersede. |

### Cleanup ordering

To avoid breaking the cluster mid-pivot, do cleanup in this order:

1. **Phase 1-3** (the pivot): rewrite launchers, verify wiring, test end-to-end. This makes the new path live.
2. **Phase 4** (docs): supersede headers + ADR-0012 implementation note + STATUS.md update + handoff. Prevents others from grabbing the wrong plan.
3. **Cleanup `[BROKEN]` items in `dmf-infra`**: remove the broken `spec.ee_pod_spec_override` template fragment, decide on the `awx-runner-sa` removal, re-run 640 to converge cluster state. Verify no regression.
4. **Cleanup `[OBSOLETE]` items in `dmf-runbooks/roles/nmos-cpp/`**: delete dead slurp blocks in `provision.yml` and `finalise.yml`. Re-test launch + finalise to confirm role still works.
5. **`[FOLLOW-UP]` items**: bundle into a single PR / housekeeping pass when convenient. None block subsequent Move 1 work.

---

## Acceptance criteria

**Pivot working:**

1. `media-launch-nmos-cpp` job in AWX completes successfully end-to-end.
2. `kubectl -n nmos get all` shows registry StatefulSet, node Deployments, Services running.
3. NetBox service `nmos-cpp` tag set to `lifecycle:active`.
4. `media-finalise-nmos-cpp` job tears down workloads cleanly.
5. NetBox service tag reset to `lifecycle:bootstrapped`.

**Documentation aligned:**

6. ADR-0012 has an Implementation note pointing to ADR-0016.
7. `STATUS.md` operator notes reflect the pivot.
8. New handoff in `docs/handoffs/` documents the decision.
9. The superseded plan (`Move 1 Gate 2 Fix - AWX EE Pod Service Account Mount.md`) carries a banner pointing to this plan.

**Cleanup verified:**

10. All `[BLOCKER]` artifacts (Phase 1) are addressed.
11. All `[BROKEN]` artifacts in `dmf-infra` are removed or commented-out with `TODO(deferred):` referencing this plan; cluster has no orphaned `awx-runner-sa` SA + RBAC if removal path was chosen.
12. All `[OBSOLETE]` artifacts in `dmf-runbooks/roles/nmos-cpp/tasks/{provision,finalise}.yml` (the dead slurp blocks) are removed; role still passes end-to-end test.
13. `STATUS.md` lists no remaining `[BROKEN]` items from this plan; `[FOLLOW-UP]` items are tracked (in-place doc TODO or issue).
14. `/tmp/dmf-playbook-logs/` swept for leaked secrets per `dmf-cluster-access` §0.6.

---

## Reference material

**Read before reviewing:**
- `<umbrella-path>/docs/decisions/0012-configure-stage-distinct-from-provision.md`
- `<umbrella-path>/docs/decisions/0014-awx-project-layout.md`
- `<umbrella-path>/docs/decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md`
- `<umbrella-path>/docs/architecture/DMF Function Catalog Model.md`
- `<umbrella-path>/docs/plans/Move 1 Gate 2 Fix - AWX EE Pod Service Account Mount.md` (the original failed plan this supersedes)

**Current state of code:**
- `<umbrella-path>/dmf-runbooks/playbooks/launch-nmos-cpp.yml`
- `<umbrella-path>/dmf-runbooks/playbooks/teardown-nmos-cpp.yml`
- `<umbrella-path>/dmf-runbooks/roles/nmos-cpp/`
- `<umbrella-path>/dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml`
- `<umbrella-path>/dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx/templates/awx-instance.yml.j2` (the broken `spec.ee_pod_spec_override` reference, line ~106)

**Cluster verification commands** (for re-checking before/after pivot):

```bash
# Confirm awx-runner-sa exists, awx-ee does not
ssh k3s-admin@<control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n awx get sa"

# Confirm pod_spec_override empty on instance groups
ssh k3s-admin@<control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n awx exec awx-postgres-15-0 -- \
   psql -U awx -d awx -A -t -c \"SELECT id, name, pod_spec_override FROM main_instancegroup;\""

# Confirm execution environment id on job templates (already correct)
ssh k3s-admin@<control-node-public-ip> \
  "sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n awx exec awx-postgres-15-0 -- \
   psql -U awx -d awx -A -t -c \"SELECT name, execution_environment_id
   FROM main_unifiedjobtemplate
   WHERE name LIKE '%media-launch%' OR name LIKE '%media-finalise%';\""

# Read the silent CRD field warning that started everything
grep -A 2 'unknown field' /tmp/dmf-playbook-logs/*640*.log 2>/dev/null | head
```

---

## Estimated effort

- Phase 1 (rewrite launchers): 30 minutes
- Phase 2 (verify AWX wiring + add credential attachment if missing): 30-60 minutes
- Phase 3 (test end-to-end): 15-30 minutes (depends on AWX project sync latency)
- Phase 4 (docs): 30 minutes
- Phase 5 (preserve deferred capability comment): 10 minutes

**Total: ~2-3 hours wall-clock** (vs. unknown days remaining on the in-cluster path).

---

## Approval needed before execution

This is a strategic pivot away from a documented architecture (ADR-0012 implementation as originally written). The *decision* in ADR-0012 stands; the *implementation choice* changes. Operator should confirm:

1. The pivot is acceptable given Move 1's experiment-phase goals.
2. The control-plane inventory group name is correct (or specify the right one).
3. The Machine credential is the right one to attach (or specify alternative).
4. ADR-0012 addendum + new handoff are the right shape for documentation.

Once approved, execute Phases 1-5 in order.
