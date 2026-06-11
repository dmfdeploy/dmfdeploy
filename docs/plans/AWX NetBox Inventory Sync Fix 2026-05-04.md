---
status: executed
date: 2026-05-04
executed: 2026-05-04
---
# AWX NetBox Inventory Sync Failure — Investigation & Fix Plan

**Date:** 2026-05-04
**Trigger:** AWX inventory sync from NetBox failing consistently (2 attempts, both `failed (rc=None)`)
**Severity:** High — blocks all playbook execution against NetBox-derived inventory, including the `eso-openbao-health-check` job template

---

## Problem Statement

AWX has a configured Inventory Source ("NetBox Inventory Source") that uses the `netbox.netbox.nb_inventory` SCM plugin to pull hosts/groups from NetBox. Two sync attempts have failed:

| Attempt | Timestamp | Duration | Result |
|---|---|---|---|
| inventoryupdate-10 | 2026-05-03 ~11:19 UTC | ~4 min | `failed (rc=None)` |
| inventoryupdate-13 | 2026-05-04 ~15:05 UTC | ~1 min | `failed (rc=None)` |

Both failures blocked the `eso-openbao-health-check` job (job-8) from running.

---

## Root Cause Analysis

### Issue 1: NetBox OpenAPI schema endpoint timeout (PRIMARY)

The `netbox.netbox.nb_inventory` plugin fetches the NetBox OpenAPI schema (`/api/schema/?format=json`) **before** performing inventory sync. On this deployment (NetBox v4.5.0-Docker-3.4.2), the schema generation:

- Returns **no bytes** and **times out after 120+ seconds**
- Emits large volumes of warnings from `filtersets.py` in the NetBox pod logs
- The `/api/status/` endpoint responds instantly (200 OK), confirming the pod itself is healthy

**Evidence from live cluster:**
```bash
# Status endpoint — responds instantly
curl http://netbox.netbox.svc.cluster.local/api/status/
→ {"django-version":"5.2.9", "netbox-version":"4.5.0", ...}  # ✅ 200

# Schema endpoint — times out after 120s
curl --max-time 120 http://netbox.netbox.svc.cluster.local/api/schema/?format=json
→ (no response, timeout)  # ❌
```

This is a **known issue** already documented in:
- `k3s-lab-bootstrap/docs/netbox-token-journey.md` (§AWX inventory sync depends on schema)
- `k3s-lab-bootstrap/docs/awx-integration-plan.md` (§troubleshooting checklist)

The docs already note: "do not treat an AWX NetBox inventory timeout as automatic proof of broken service discovery or pod networking — set an explicit `timeout` in the generated `inventory/netbox.yml` — if the schema path still fails with a larger timeout, debug NetBox schema generation directly."

The timeout is already set to 180s in the role defaults. The schema still doesn't complete. **This means the schema generation itself is broken, not just slow.**

**Hypothesis:** NetBox v4.5.0 schema generation has a performance regression or misconfiguration. The `filtersets.py` warnings suggest the schema generator is iterating over filter sets for every model, possibly hitting an N+1 query or circular reference.

### Issue 2: NetBox API URL path ambiguity (SECONDARY — may not be active)

The AWX integration role generates an inventory plugin config with:
```yaml
plugin: netbox.netbox.nb_inventory
api_endpoint: "http://netbox.netbox.svc.cluster.local"
```

The `awx_integration_netbox_url` default is `http://netbox.<namespace>.svc.cluster.local` (no path suffix).

Testing confirmed:
- `/api/status/` at this URL ✅ works
- `/netbox/api/status/` ❌ returns 404 "Page Not Found"

**NetBox has no `BASE_PATH` configured** — it's served at the root internally. The `/netbox/` prefix is only added by the Traefik IngressRoute for external access. Internal cluster communication should use the root path.

**Assessment:** The generated `api_endpoint` value is likely correct (no `/netbox/` suffix). The `awx_integration_netbox_path: "/netbox"` default is used for the Traefik route, not the internal API URL. This issue may be a non-issue once we verify the actual Forgejo file content.

---

## Resolution Plan

### Phase 1: Investigate NetBox schema generation (blocks everything)

**Step 1.1** — Check NetBox pod logs for schema-generation warnings/errors
```bash
kubectl -n netbox logs deploy/netbox --tail=1000 | grep -i filterset
kubectl -n netbox logs deploy/netbox --tail=1000 | grep -i schema
```

**Step 1.2** — Check NetBox configuration for any problematic settings
- `PLUGINS` list (third-party plugins can break schema generation)
- `PLUGINS_CONFIG` (misconfigured plugin settings)
- `CUSTOM_VALIDATORS`, `REPORTS`, `SCRIPTS` (custom code loaded during schema gen)

**Step 1.3** — Test schema generation from inside the NetBox pod directly
```bash
kubectl -n netbox exec deploy/netbox -- /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py spectacular --file /dev/null --validate
```

**Step 1.4** — Check if drf-spectacular sidecar is causing issues
- The sidecar container serves static schema files; if misconfigured, it may block generation
- Check `drf_spectacular_sidecar` in installed apps

**Step 1.5** — Consider NetBox version upgrade/downgrade
- v4.5.0 may have a known schema generation bug
- Check NetBox GitHub issues for "schema timeout" or "filtersets"

### Phase 2: Fix inventory plugin config (if needed)

**Step 2.1** — Retrieve the actual `inventory/netbox.yml` from Forgejo
- Verify `api_endpoint` value
- Check `timeout` value (should be ≥ 180, may need to increase further or find alternative)

**Step 2.2** — If schema can't be fixed quickly, explore plugin workarounds:
- `fetch_all: false` (if supported by plugin version)
- `url_filters` to limit scope
- Disable schema validation entirely (plugin may support this)

**Step 2.3** — Update the role's inventory content template if changes are needed
- File: `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml`
- Section: "Set NetBox inventory plugin content" (around line 340-355)

### Phase 3: Re-run and verify

**Step 3.1** — Push updated inventory file to Forgejo (or re-run the integration playbook)
**Step 3.2** — Trigger inventory sync from AWX UI or API
**Step 3.3** — Monitor logs for successful schema fetch and inventory pull
**Step 3.4** — Verify hosts/groups populated in AWX inventory

---

## Files to potentially modify

| File | Purpose |
|---|---|
| `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml` | `awx_integration_netbox_timeout`, `awx_integration_netbox_url` |
| `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml` | Inventory content template |
| `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox-sot/` | NetBox configuration if schema fix requires config changes |
| `dmf-infra/k3s-lab-bootstrap/docs/netbox-token-journey.md` | Update known issue section |
| `dmf-infra/k3s-lab-bootstrap/docs/awx-integration-plan.md` | Update troubleshooting checklist |

---

## Resolution Applied (2026-05-04 16:00 UTC)

### Fix 1: drf-spectacular `plumbing.py` patch (APPLIED ✅)

**Root cause:** NetBox v4.5.0 ships drf-spectacular 0.29.0 which has a bug in
`build_mock_request()` at line 1277 of `plumbing.py`:
```python
request.auth = original_request.auth  # WSGIRequest has no .auth attribute
```
This caused schema generation to either:
- Return HTTP 200 with 0 bytes (error swallowed by the view)
- Hang indefinitely when run via `manage.py spectacular`

**Fix applied live:** Patched the `plumbing.py` file via a ConfigMap volume mount:
```python
request.auth = getattr(original_request, 'auth', None)  # Safe access
```

**Verification:** Schema endpoint now returns 10.8 MB of valid OpenAPI schema:
```bash
curl http://netbox.netbox.svc.cluster.local/api/schema/?format=json
# → 10,809,031 bytes, valid JSON
```

**Persistence:** Added tasks to the NetBox role (`roles/stack/operator/netbox/tasks/main.yml`)
that automatically extract, patch, and mount the fixed `plumbing.py` on every playbook run.

### Fix 2: NetBox API token in AWX inventory file (PENDING ⏳)

**Root cause:** The `inventory/netbox.yml` file in the Forgejo `awx-automation` repo
either has an empty or missing `token` field. The `nb_inventory` plugin requires a valid
NetBox API token to access authenticated endpoints (`/api/dcim/devices/`, etc.).

**Evidence:**
```
Fetching: http://netbox.netbox.svc.cluster.local/api/status/
Permission denied: http://netbox.netbox.svc.cluster.local/api/status/
Failed to parse ... with auto plugin: 'netbox-version'
```
- `/api/status/` returns 200 OK without auth ✅
- `/api/dcim/devices/` returns 403 without auth ❌
- The nb_inventory plugin can't fetch data without a valid token

**Token chain:**
1. `691-netbox-sot.yml` creates token in NetBox → stores in OpenBao at `secret/apps/netbox/runtime` → `netbox_awx_token`
2. `693-awx-integration.yml` reads from OpenBao → generates `inventory/netbox.yml` in Forgejo with the token embedded

**Remediation (COMPLETED ✅):**
```bash
# Step 1: Ensure NetBox AWX token is created and stored
cd ~/repos/dmfdeploy/dmf-env
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/playbooks/691-netbox-sot.yml

# Step 2: Ensure Forgejo service account exists
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/playbooks/692-forgejo-bootstrap.yml

# Step 3: Regenerate AWX inventory file with the token
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/playbooks/693-awx-integration.yml

# Step 4: Trigger inventory sync from AWX UI or API
# Result: ✅ successful, 4 hosts imported
```

## Commits (for rollback reference)

| Repo | Commit | Message |
|---|---|---|
| dmf-infra | `a4f6566` | fix(netbox): patch drf-spectacular to fix schema generation hang |
| dmf-infra | `25ade1f` | fix(awx-netbox): resolve inventory sync failure with timeout + caching |
| dmfdeploy (umbrella) | `2a067af` | docs: add AWX NetBox inventory sync investigation and fix plan |

To rollback the dmf-infra changes:
```bash
cd ~/repos/dmfdeploy/dmf-infra
git revert 25ade1f a4f6566
```

To rollback the live cluster ConfigMap and volume mount:
```bash
ssh k3s-admin@<control-node-public-ip>
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n netbox \
  delete configmap netbox-drf-spectacular-patch
sudo kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml -n netbox \
  patch deployment netbox --type json --patch '[
    {"op": "remove", "path": "/spec/template/spec/volumes/-1"},
    {"op": "remove", "path": "/spec/template/spec/containers/0/volumeMounts/-1"}
  ]'
```

## Result

**Inventory sync now works.** The final successful sync (job 23) completed in
~15 seconds (cached), importing **4 hosts** across **4 groups**:

```
Loaded 4 groups, 4 hosts
  - k3s-node-01 (<node-public-ip>, role: k3s-node)
  - k3s-node-02 (<node-public-ip>, role: k3s-node)
  - k3s-node-03 (<control-node-public-ip>, role: k3s-node)
  - dmf-traefik (<lb-public-ip>, role: load-balancer)
```

Subsequent syncs will use the cached schema (cache_timeout: 3600s = 1 hour)
and complete even faster.

## Success Criteria

1. NetBox schema endpoint (`/api/schema/?format=json`) responds within the configured timeout ✅ FIXED
2. AWX inventory sync completes successfully (status: "successful") ✅ FIXED
3. AWX inventory contains hosts/groups from NetBox ✅ 4 hosts, 4 groups
4. `eso-openbao-health-check` job can run against the NetBox-derived inventory ✅ READY
