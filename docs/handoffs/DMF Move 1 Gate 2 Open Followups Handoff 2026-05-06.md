# DMF Move 1 Gate 2 — Open Follow-ups Handoff

> **Item #15 CLOSED 2026-05-07** — `nmos-cpp` ConfigMap schema fix landed; pods
> reach Running and the Query API returns HTTP 200. Three root-cause bugs were
> fixed (see closure handoff). Item #12 (NetBox inventory CIDR fix) remains open.
> See [`DMF Item 15 NMOS ConfigMap Schema Fix Closure 2026-05-07.md`](DMF%20Item%2015%20NMOS%20ConfigMap%20Schema%20Fix%20Closure%202026-05-07.md).

**Date:** 2026-05-06
**Author:** session that closed Move 1 Gate 2 via Path A pivot
**For:** any future agent / operator picking up the residual work

---

## TL;DR

Move 1 Gate 2 closed via Path A pivot — catalog launchers run end-to-end
on the cluster (AWX job 285 + 295 confirmed). Two follow-up items remain;
neither blocks Move 1 closure or further catalog functions:

1. **#12 — NetBox inventory CIDR fix:** durable replacement for the
   hardcoded `inventory_hostname` → private-IP map currently in the
   launcher playbooks. Needs NetBox custom-field setup + inventory
   `compose:` rule on the awx-integration role.
2. **#15 — `nmos-cpp` ConfigMap schema:** pods deploy but crash with
   `Bad command-line settings [json:8]`. The role's `registry.json` /
   `node.json` skeletons don't match Sony nmos-cpp's actual config
   schema. Content correctness, not catalog mechanism.

---

## 0. Required reading before touching either item

**Boot ritual (every session):**
```bash
cd <repos>/dmfdeploy
git fetch && git pull
bin/generate-status.sh --no-fetch    # refreshes STATUS.md
```

Then read in order:
1. `STATUS.md` — current cross-repo state
2. `docs/decisions/INDEX.md` — ADR catalog
3. The most recent file under `docs/handoffs/` (this one, or whatever
   superseded it)
4. The pivot plan: `docs/plans/Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md`
5. The pivot session handoff: `docs/handoffs/DMF Move 1 Gate 2 Path A Pivot Handoff 2026-05-06.md`

**Skills to load before cluster operations or secrets:**
- `dmf-cluster-access` — §0 secrets discipline + §3-§5 cluster ops
- `dmf-openbao-unseal` — only if OpenBao is sealed (rarely)

**Relevant ADRs:**
- ADR-0012 (Configure-vs-Provision stage split, **plus 2026-05-06 implementation note**)
- ADR-0013 (Function catalog model)
- ADR-0014 (AWX project layout — multi-project)
- ADR-0016 (Path A — control-node SSH via cloud-init + OpenBao)

**Memory entries (auto-loaded but worth knowing):**
- `path_a_for_catalog_launchers.md` — settled 2026-05-06
- `dmf_runbooks_awx_sanity_check.md` — **SUPERSEDED**; do not act from it
- `rpi_cluster_not_dmf.md` — <lan-ip> is unrelated

**Cluster facts (verified 2026-05-06):**
- k3s-node-01 ext **<node-public-ip>** / int 10.0.0.4
- k3s-node-02 ext **<node-public-ip>** / int 10.0.0.3
- k3s-node-03 ext **<control-node-public-ip>** / int 10.0.0.2
- SSH default: `k3s-admin@<control-node-public-ip>` (k3s-node-03)
- Cluster pods can reach private IPs (10.0.0.0/24) of other nodes
- Hetzner cloud firewall blocks SSH from cluster egress to node *public* IPs

---

## Item #12 — NetBox inventory CIDR / private-IP fix

### Why this exists

Two coupled problems:

1. **CIDR-on-IP:** The NetBox dynamic inventory plugin in AWX exposes
   each device's primary_ip4 as `<ip>/<prefix>` (e.g. `<node-public-ip>/32`).
   That's not a valid SSH hostname; SSH fails with "Could not resolve
   hostname <node-public-ip>/32".
2. **Public vs private:** NetBox stores the *public* IP as primary_ip4.
   AWX EE pods run *inside* the cluster, where the Hetzner cloud firewall
   blocks SSH to node public IPs but allows direct connections to node
   private IPs (10.0.0.0/24).

### Current workaround (in `dmf-runbooks/playbooks/launch-nmos-cpp.yml` and `teardown-nmos-cpp.yml`)

```yaml
- name: Set ansible_host to node private IP (Hetzner firewall workaround)
  ansible.builtin.set_fact:
    ansible_host: >-
      {{ {'k3s-node-01': '10.0.0.4',
          'k3s-node-02': '10.0.0.3',
          'k3s-node-03': '10.0.0.2'}[inventory_hostname] }}
  delegate_to: localhost
  become: false
```

This works but:
- Hardcoded — every new k3s node added to the cluster requires editing every
  catalog launcher.
- Each new catalog playbook has to remember to include this set_fact.
- Brittle (lookup fails if `inventory_hostname` not in the map).

### Durable fix — recommended approach

**Option A (preferred): NetBox device custom field + inventory compose rule.**

1. **Create a custom field on NetBox `dcim.device` content type:**
   - Name: `k3s_node_ip` (or `private_ip`)
   - Type: `text` (a string, since NetBox doesn't have a "private IP" type)
   - Description: "Internal-network IP for cluster-side SSH"
   - Required: false
   - Filter: ui-visible

   Done via the NetBox UI (Customization → Custom Fields → Add) OR via API:
   ```
   POST {NETBOX_API}/extras/custom-fields/
   {
     "name": "k3s_node_ip",
     "label": "K3s node private IP",
     "type": "text",
     "object_types": ["dcim.device"],
     "description": "Internal-network IP (10.0.0.0/24) for cluster-side SSH",
     "weight": 100,
     "required": false
   }
   ```

   This is a one-time bootstrap operation. Best place to codify it:
   `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox-sot/`
   (the same role that bootstraps NetBox tags — see commit `3f519bc` for
   the tag-bootstrap pattern, and follow the same shape).

2. **Populate the field for each k3s node device:**
   - k3s-node-01 → `10.0.0.4`
   - k3s-node-02 → `10.0.0.3`
   - k3s-node-03 → `10.0.0.2`

   Idempotent PATCH per device:
   ```
   PATCH {NETBOX_API}/dcim/devices/{id}/
   { "custom_fields": { "k3s_node_ip": "10.0.0.4" } }
   ```

   Codify in `dmf-born-inventory` or netbox-sot role. The values are
   already known via Tofu state / `dmf-env/inventories/hetzner-arm/hosts.ini`
   (`k3s_node_ip=10.0.0.4` etc.) — feed them in via a vars dict.

3. **Update the AWX NetBox Inventory source's `source_vars` to expose
   the field via a `compose` rule.** The `awx-integration` role already
   manages this inventory source; find the source_vars block and add:

   ```yaml
   compose:
     ansible_host: custom_fields.k3s_node_ip | default(ansible_host | regex_replace('/.*$', ''))
   ```

   The `default` fallback strips CIDR from the public IP if no private IP
   is set — useful for non-cluster devices that may join the inventory.

4. **Re-run 693:**
   ```bash
   cd ~/repos/dmfdeploy/dmf-env
   bin/run-playbook.sh hetzner-arm \
     ../dmf-infra/k3s-lab-bootstrap/playbooks/693-awx-integration.yml
   ```

5. **Sync the inventory in AWX** (or wait for the schedule) to refresh
   host_vars from NetBox.

6. **Remove the workaround** — delete the `Set ansible_host to node
   private IP` set_fact tasks from `launch-nmos-cpp.yml` and
   `teardown-nmos-cpp.yml`. Verify with a fresh AWX launch run.

### How to verify

1. `kubectl -n awx exec awx-postgres-15-0 -- psql -U awx -d awx -A -t -c \
    "SELECT name, variables::jsonb->'ansible_host' FROM main_host WHERE name LIKE 'k3s-%';"`
   should show `10.0.0.X` (no CIDR).
2. `media-launch-nmos-cpp` runs without the launcher's set_fact (delete it,
   commit, re-launch). Pod-side SSH still succeeds.
3. AWX job event for the first task on the host shows `remote_addr` is the
   private IP.

### Where this work lives

- NetBox custom field setup: `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox-sot/tasks/main.yml` (after the existing tag-bootstrap section that commit `3f519bc` added)
- Per-device value population: `dmf-infra/k3s-lab-bootstrap/roles/common/dmf-born-inventory/` (the role that already registers k3s nodes — extend it)
- Inventory `compose` rule: `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml` (the inventory source vars)
- Workaround removal: `dmf-runbooks/playbooks/{launch,teardown}-nmos-cpp.yml`

### Pitfalls noted from this session

- The launcher's set_fact uses `delegate_to: localhost` + `become: false`
  to avoid triggering SSH connection setup before the fact is set. If
  you replace it with inventory-level data, you can drop the delegate.
- NetBox v4 generic-relation patterns: when reading `custom_fields.foo`
  in Jinja, NetBox returns `null` if unset. Always use `| default(...)`
  to avoid templating errors on hosts that don't have the field
  populated.
- Don't query `custom_fields` from a different content type — the field
  is scoped to the type you registered it for (`dcim.device`).

---

## Item #15 — `nmos-cpp` ConfigMap schema fix

### Why this exists

After the catalog launcher pivot landed (Path A) and images were pushed
to Zot, AWX job 295 succeeded at the *playbook* level. But the
`nmos-cpp-registry-0` pod and the `nmos-cpp-node-{1,2}` pods crash on
startup with:

```
2026-05-06 19:01:51.331: info: Starting nmos-cpp registry
2026-05-06 19:01:51.331: severe error: Bad command-line settings [json:8]
```

Status: `CrashLoopBackOff`. The container is reading its mounted
`registry.json` / `node.json` ConfigMap and rejecting the schema.

### Why the role is wrong

The role's `roles/nmos-cpp/tasks/provision.yml` (in `dmf-runbooks`)
generates these ConfigMaps:

```yaml
# Registry
{"host": "0.0.0.0", "port": 80, "logging": "info"}

# Node
{"host": "0.0.0.0", "port": 80, "registries": [...], "label": "...",
 "description": "...", "logging": "info"}
```

These keys (`host`, `port`, `logging`) are **placeholder names**, not
the actual config keys Sony's nmos-cpp binary expects. The role was
written as a skeleton during the catalog-mechanism design phase and was
never tested against a real built binary until 2026-05-06.

### What the real schema looks like

Source of truth: <https://github.com/sony/nmos-cpp> — specifically the
`registry-config-schema.json` and `node-config-schema.json` under the
`Documents/` directory of the upstream repo (or the equivalent in the
version we built — `NMOS_CPP_VERSION=4.1.0` per
`docs/plans/Move 1 Gate 1 — Build NMOS + Run Provision.md`).

Real keys you will likely need (verify against the schema for v4.1.0):

**Registry:**
- `registry_address` — the bind address (default `0.0.0.0`)
- `http_port` — registry HTTP port (default `8080`, **not 80**)
- `query_ws_port` — WebSocket port for live updates (default `8081`)
- `system_address`, `system_port` — system endpoints
- `registration_expiry_interval` — heartbeat timeout
- `logging_level` — instead of `logging`

**Node:**
- `node_id` — unique UUID per node
- `host_addresses` — list (not single `host`)
- `http_port` — node HTTP port
- `registries` — list of `{address, port}` pairs (the role's current
  shape with `hostname/priority/weight` matches MDNS-style discovery,
  not the configured-registry list NMOS-CPP uses)
- `device`, `senders`, `receivers`, `flows`, `sources` — actual NMOS resources

### How to fix

1. **Read the real schema.** Don't guess. Check the repo at the build
   tag we used. Look at:
   - `Sandbox/registry/config.json` (sample registry config)
   - `Sandbox/node/config.json` (sample node config)
   - `Documents/Configuration.md`

2. **Update `roles/nmos-cpp/tasks/provision.yml`:** replace the
   `to_json` Jinja inline dicts for both ConfigMaps with the real keys.
   Keep the `to_json` filter pattern — it forces string serialization
   which K8s ConfigMap data values require (the YAML literal block `|`
   approach was coerced to dict by Ansible's remote-host serializer; see
   commit `e86ae24` for that fix).

3. **Decide on port strategy.** If you keep `http_port: 8080` (NMOS
   default), update the K8s `Service` and `containerPort` definitions
   in `tasks/configure.yml` to match (currently `port: 80` /
   `containerPort: 80`).

4. **Test by re-launching `media-launch-nmos-cpp`:**
   - Job should succeed
   - `kubectl -n nmos get pods` → all three Running, ready
   - `kubectl -n nmos logs nmos-cpp-registry-0` → no "Bad command-line
     settings"; should show "registration ready" or similar
   - `kubectl -n nmos exec deploy/nmos-cpp-node-1 -- curl -s
     http://nmos-cpp-registry/x-nmos/query/v1.3/nodes/` (or the
     in-cluster service URL) → 200 OK with nodes registered

5. **Verify the catalog model end-to-end:**
   - NetBox `nmos-cpp` service should have tag `lifecycle:active`
   - Health probe at the path defined in `nmos-health-probe` ConfigMap
     (`/x-nmos/query/v1.3/nodes/`, expect 200) should succeed against
     the running registry

### Notes from this session

- The Dockerfiles at `dmf-runbooks/roles/nmos-cpp/files/Dockerfile.{registry,node}`
  build cleanly. Build is done; images are at
  `registry.dmf.example.com/<operator>/nmos-cpp-{registry,node}:0.1.0`.
- The k3s `imagePullSecrets` setup works — pods successfully pulled
  (job 295 confirmed). So you don't need to re-touch image build/push.
- The K8s manifests (StatefulSet, Deployments, Services, PVC) all apply
  correctly. So you don't need to re-touch the configure-stage K8s
  scaffolding either.
- This is a pure data fix: replace ConfigMap content keys.

### Where this work lives

- `dmf-runbooks/roles/nmos-cpp/tasks/provision.yml` — registry + node ConfigMaps (around lines 130–170, give or take after later edits)
- `dmf-runbooks/roles/nmos-cpp/tasks/configure.yml` — Service + Deployment ports (if changing `http_port`)
- `dmf-runbooks/roles/nmos-cpp/defaults/main.yml` — `nmos_namespace`, `nmos_logging_level`, `nmos_node_count` are already there; add new vars for the real config (e.g. `nmos_registry_http_port`, `nmos_query_ws_port`, etc.)

### Pitfalls noted from this session

- ConfigMap `data` values must be strings. Use the `to_json` filter on
  inline dicts to serialize at playbook render time. Multi-line YAML
  literal block scalars (`|`) get coerced to dict by Ansible's remote
  module dispatch in some versions — that wasted ~1 hour this session.
- The launcher merges Provision + Configure into a single AWX job, so
  changes to provision.yml take effect on the next `media-launch-nmos-cpp`
  run. Idempotent — safe to re-launch repeatedly.
- ConfigMap updates don't auto-restart pods. If you change the schema
  and re-launch, also delete the old pods (or restart deploy/StatefulSet)
  so the new ConfigMap content is read on container start:
  ```
  kubectl -n nmos delete pod -l dmf.function=nmos-cpp
  ```
- `kubernetes.core.k8s` strategic-merge can fail in odd ways on a
  ConfigMap whose existing data was created with a different
  serializer. If you hit "cannot unmarshal object into string" on a
  re-run, delete the ConfigMap and let the role recreate fresh:
  ```
  kubectl -n nmos delete cm nmos-registry-config nmos-node-config
  ```

---

## Files / commits to know

- Pivot plan: `docs/plans/Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md`
- Pivot handoff: `docs/handoffs/DMF Move 1 Gate 2 Path A Pivot Handoff 2026-05-06.md`
- This handoff: `docs/handoffs/DMF Move 1 Gate 2 Open Followups Handoff 2026-05-06.md`

Code anchor commits:
- `dmf-runbooks` `e86ae24` — pivot landed end-to-end (job 285 succeeded)
- `dmf-runbooks` `cc08729` — role README rewritten
- `dmf-infra` `b383736` — broken EE pod_spec_override + service-account.yml deferred
- `dmf-infra` `3f519bc` — bootstrap-seed catalog tags in 691 (run 691 to apply)
- `dmf-media` `3c3d25a` — drifted `nmos-cpp` role + 4 playbooks deleted; catalog entry pointing at dmf-runbooks
- `dmfdeploy` `5e40dc3` — skill IPs + trials closure footnote

---

## Suggested order to attack

1. **Item #15 first.** Smaller, self-contained, gives a tangible "media
   layer is alive" win. Closes Move 1's thesis-killer #1 cleanly.
2. **Item #12 second.** Cleanup work — workaround is in place and harmless.
   The durable fix becomes worth the effort once a second catalog function
   joins (otherwise it's just polish on a one-of-one).

---

## What "done" looks like

- **#15 done:** `kubectl -n nmos get pods` shows all three nmos-cpp pods
  Running, ready. Registry HTTP endpoint returns 200 to a node-registration
  probe. NetBox `nmos-cpp` service has `lifecycle:active`.
- **#12 done:** Launcher playbooks have no `Set ansible_host to node
  private IP` set_fact task. NetBox host_vars expose `ansible_host` as
  the private IP directly. A new AWX-driven playbook targeting any
  `device_roles_k3s-control-plane` host works without per-launcher
  workarounds.
- **Both done:** Update `STATUS.md` operator notes, write a closing
  handoff, and consider whether Move 1 itself is done (last decision
  gate before announcing the platform is past Gate 2 cleanly).
