# DMF Move 1 Gate 2 — Path A Pivot Handoff

**Date:** 2026-05-06
**Author:** session with Kubernetes Operator + Architecture Reviewer agents
**Outcome:** ✅ Catalog launcher pivot validated. Move 1 Gate 2 is unblocked.

---

## What changed today

After ~20 iterative commits in `dmf-runbooks` failed to make in-cluster
ServiceAccount auth work for the catalog launcher (silent failures across
five coupled layers — see commit log `f669415`..`e8bc0f4`), an independent
architecture review recommended pivoting to ADR-0016 Path A. The pivot
landed and is end-to-end validated.

**Pivot summary:**
- Catalog launchers (`media-launch-nmos-cpp`, `media-finalise-nmos-cpp`)
  now run on the k3s control node via SSH (`hosts: device_roles_k3s-control-plane[0]`,
  `become: true`).
- `kubernetes.core.k8s` reads `/etc/rancher/k3s/k3s.yaml` natively under
  `become: true`, via `KUBECONFIG=/etc/rancher/k3s/k3s.yaml` set at the
  play level.
- ADR-0012's Configure-vs-Provision stage split is preserved at the
  *role* level (`provision.yml`, `configure.yml`, `finalise.yml`); the
  launcher merges Provision+Configure into one AWX job for operator
  ergonomics.
- NetBox catalog registration follows the `dmf-born-inventory` pattern:
  `ipam.Service` records with NetBox v4 generic relation
  (`parent_object_type: dcim.device` + `parent_object_id` of `dmf-traefik`),
  not attached to k3s node VMs.

**Implementation plan (canonical):**
[`docs/plans/Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md`](../plans/Move%201%20Gate%202%20-%20Pivot%20to%20Path%20A%20for%20Catalog%20Launchers%202026-05-06.md)
— full findings, agent reviews, cleanup inventory, acceptance criteria.

**ADR-0012 implementation note** added pointing to ADR-0016. The decision
itself (stage split) is unchanged and now confirmed implementable.

**Superseded:** [`docs/plans/Move 1 Gate 2 Fix - AWX EE Pod Service Account Mount.md`](../plans/Move%201%20Gate%202%20Fix%20-%20AWX%20EE%20Pod%20Service%20Account%20Mount.md)
carries a banner pointing here.

---

## End-to-end validation

**AWX job 285** (`media-launch-nmos-cpp`, dmf-runbooks commit `e86ae24`,
2026-05-06 17:55 UTC):
- ✅ Project sync pulled the pivoted launcher
- ✅ NetBox dynamic inventory resolved `device_roles_k3s-control-plane[0]` → `k3s-node-01`
- ✅ SSH succeeded via private IP (10.0.0.4)
- ✅ Provision stage: tags auto-created (`dmf-catalog`, `lifecycle:bootstrapped`, `lifecycle:active`, `exposure:private`, `app:nmos-cpp`); `ipam.Service` `nmos-cpp` registered with parent `dmf-traefik` device
- ✅ K8s namespace + ConfigMaps + PVC + StatefulSet + Deployments + Services applied
- ✅ NetBox tag flipped `lifecycle:bootstrapped` → `lifecycle:active`

**Pods are `ImagePullBackOff`** because the `nmos-cpp` images haven't been
pushed to Zot yet. That's task #13, separate from the pivot/catalog-model
thesis — operator action with documented procedure (see Outstanding work).

---

## Files touched

### `dmf-runbooks/`

- `playbooks/launch-nmos-cpp.yml` — rewrite for Path A; calls role twice (provision + configure stages); workaround for NetBox-supplied CIDR-on-IP and Hetzner firewall blocking public-IP SSH from cluster egress (hardcoded `inventory_hostname` → private IP map).
- `playbooks/teardown-nmos-cpp.yml` — same Path A shape; calls role for finalise stage only.
- `roles/nmos-cpp/defaults/main.yml` — rename platform tag `dmf` → `dmf-catalog`; add `netbox_admin_token` (from `vault_netbox_admin_token`, falls back to AWX-svc token for read-only ops).
- `roles/nmos-cpp/tasks/provision.yml` — drop dead in-cluster slurp block; add NetBox tag taxonomy creation (idempotent GET-then-POST loop); add `ipam.Service` lookup + create (with admin token, NetBox v4 generic relation to `dmf-traefik` device); force string serialization of ConfigMap JSON data via `to_json` filter.
- `roles/nmos-cpp/tasks/configure.yml` — use admin token for `ipam.Service` PATCH (tag flip → `lifecycle:active`).
- `roles/nmos-cpp/tasks/finalise.yml` — drop dead in-cluster slurp block; use admin token for `ipam.Service` PATCH (tag flip → `lifecycle:bootstrapped`).

### `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/`

- `tasks/main.yml` — extract `netbox_admin_token` from `secret/apps/netbox/runtime` alongside the existing AWX-svc token (`netbox_awx_token`).
- `defaults/main.yml` — pass `vault_netbox_admin_token` in `awx_catalog_job_templates` extra_vars; keep AWX-svc token for read-only ops.

### `dmfdeploy/` (umbrella docs)

- `STATUS.md` — operator notes section updated with the pivot validation, outstanding follow-ups, and the new "in-flight" entry for image push.
- `docs/decisions/0012-configure-stage-distinct-from-provision.md` — Implementation note (2026-05-06) appended.
- `docs/plans/Move 1 Gate 2 Fix - AWX EE Pod Service Account Mount.md` — superseded banner.
- `docs/plans/Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md` — the new canonical plan (created during this session).

---

## Outstanding work (tracked, not blocking)

1. **Push `nmos-cpp` images to Zot.** Both images are already built locally
   on Mac mini's Colima `docker-build` profile
   (`registry.dmf.example.com/<operator>/nmos-cpp-{registry,node}:0.1.0`). Operator
   action — documented in
   [`docs/plans/Move 1 Gate 1 — Build NMOS + Run Provision.md`](../plans/Move%201%20Gate%201%20%E2%80%94%20Build%20NMOS%20+%20Run%20Provision.md)
   step 2. Use isolated `DOCKER_CONFIG` per the `dmf-cluster-access` skill
   §0 secrets discipline. Once pushed, re-launch `media-launch-nmos-cpp` to
   confirm pods come up healthy.

2. **Phase 5 cleanup of `dmf-infra` `[BROKEN]` items** — listed in the
   pivot plan's "Artifacts to clean up" section:
   - Remove broken `spec.ee_pod_spec_override` template fragment in
     `roles/stack/operator/awx/templates/awx-instance.yml.j2` (~line 106).
     The AWX CRD silently dropped this field; it never propagated to the
     InstanceGroup. Either delete or comment-out with `TODO(deferred):`.
   - Decide on `awx-runner-sa` SA + ClusterRoleBinding removal (the SA
     was created but never wired into anything; cluster-scoped permissions
     for an unused identity is the worst kind of orphaned grant).

3. **NetBox inventory CIDR fix** (task #12). The launcher's hardcoded
   `inventory_hostname` → private-IP map is a workaround. Durable fix:
   add `k3s_node_ip` custom field to NetBox device, populate for each
   k3s node, then `compose: { ansible_host: custom_fields.k3s_node_ip }`
   on the NetBox Inventory source in the awx-integration role. Then
   remove the workaround set_fact from launchers.

4. **Bootstrap-seed shared catalog tags via 691-netbox-sot** (task #14).
   `dmf-catalog`, `lifecycle:bootstrapped`, `lifecycle:active`,
   `exposure:private`, `exposure:public` are platform-wide invariants;
   currently the nmos-cpp role auto-creates them on first provision
   (idempotent). Move the seed to bootstrap so taxonomy is governed
   centrally.

5. **`dmf-cluster-access` skill node IPs are out of date.** Current
   cluster reality (verified via `kubectl get nodes -o wide`):
   - k3s-node-01 ext **<node-public-ip>** / int 10.0.0.4
   - k3s-node-02 ext **<node-public-ip>** / int 10.0.0.3
   - k3s-node-03 ext **<control-node-public-ip>** / int 10.0.0.2

   The skill table in §1 has a different mapping. Update the skill.

6. **Test `media-finalise-nmos-cpp`** — same pivot shape as launch.
   Should reuse the configure-stage scaffolding and just exercise the
   role's `finalise.yml`. Quick validation now that launch works
   end-to-end.

7. **Provision-stage gap recap** (task #13) — three pieces:
   (a) NetBox service POST in `provision.yml` (DONE this session),
   (b) provision launcher OR merged-into-launch (DONE; merged into
   `launch-nmos-cpp.yml`),
   (c) image build + push (image build DONE earlier; push pending —
   item #1 above).

---

## Decisions made this session (record for future reference)

- **Pivot to Path A.** ADR-0012 stage split is unchanged; auth-mechanism
  implementation detail changed from in-cluster SA to SSH-via-control-node.
  Independent architecture-review consensus.

- **Provision merges into launch in the AWX job.** The role keeps three
  stage files; `launch-nmos-cpp.yml` calls the role twice (provision +
  configure), so a single operator action is "launch from catalog".
  Idempotent on re-run.

- **NetBox parent for catalog services = `dmf-traefik` device.** Same
  pattern as `dmf-born-inventory` (landing, awx, forgejo, etc.) — keeps
  catalog services and platform services consistent in the NetBox UI.

- **Admin token for catalog Provision; AWX-svc token for read-only.**
  `awx_integration_netbox_admin_token` (fetched from
  `secret/apps/netbox/runtime` field `netbox_admin_token`) is needed
  for `ipam.Service` POST/PATCH; the AWX-svc token doesn't have those
  permissions. Both tokens land in the catalog template's extra_vars.

- **Catalog tag taxonomy: dynamic creation in role, with bootstrap-seed
  as a follow-up.** Provision creates any tag it references that doesn't
  exist (idempotent). Bootstrap-time seeding (#14) is an optimization /
  governance move, not a blocker.

- **Hetzner firewall blocks SSH from cluster egress to node public IPs.**
  Cluster pods can reach node private IPs (10.0.0.0/24) directly. The
  launcher uses private IPs via a hardcoded map; tracked as #12 for
  proper inventory-level fix.

---

## How to continue

1. **Build is done; push the images.** Use the documented procedure in
   `docs/plans/Move 1 Gate 1 — Build NMOS + Run Provision.md` step 2,
   adapted for `--password-stdin` to keep secrets out of argv.
2. **Re-launch `media-launch-nmos-cpp`** after push to verify pods come
   up healthy and the registry/node containers actually start.
3. **Run `media-finalise-nmos-cpp`** to verify the teardown path.
4. **Sweep the `[BROKEN]` items in `dmf-infra`** per the pivot plan's
   cleanup ordering.
5. **Decide on the durable fixes** (#12, #14) — they're not blockers but
   they're the natural next iteration on the catalog mechanism's plumbing.

---

## Reference

- Plan: [`docs/plans/Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md`](../plans/Move%201%20Gate%202%20-%20Pivot%20to%20Path%20A%20for%20Catalog%20Launchers%202026-05-06.md)
- Superseded plan: [`docs/plans/Move 1 Gate 2 Fix - AWX EE Pod Service Account Mount.md`](../plans/Move%201%20Gate%202%20Fix%20-%20AWX%20EE%20Pod%20Service%20Account%20Mount.md)
- ADR-0012 (with implementation note): [`docs/decisions/0012-configure-stage-distinct-from-provision.md`](../decisions/0012-configure-stage-distinct-from-provision.md)
- ADR-0016 (Path A): [`docs/decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md`](../decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md)
- Function Catalog Model: [`docs/architecture/DMF Function Catalog Model.md`](../architecture/DMF%20Function%20Catalog%20Model.md)
- Status snapshot: [`STATUS.md`](../../STATUS.md)
