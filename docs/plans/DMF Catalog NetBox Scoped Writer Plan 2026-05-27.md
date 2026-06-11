---
status: executed
date: 2026-05-27
executed: 2026-05-27
---
# DMF Catalog NetBox Scoped-Writer Implementation Plan (2026-05-27)

**Status:** Ready (pending codex cross-check), implements [ADR-0032](../decisions/0032-catalog-launcher-scoped-netbox-writer.md)
**Repos:** dmf-infra (netbox-sot + awx-integration), dmf-runbooks (nmos-cpp launcher)

## Root cause (confirmed live on wobe-9n0c)

Catalog Deploy (`media-launch-nmos-cpp`, job 40) failed at the first NetBox call
("Fetch existing NetBox tags") with **403**. The token is **valid** (same token
gets 200 on `/api/ipam/services/` + `/api/dcim/devices/`) but **lacks
`extras.tag` permission** — the read-only svc accounts (`dmf-cms-readonly`,
`awx-readonly`) grant dcim/ipam/tenancy/virtualization views only. Same cause
makes the console's catalog status show **"unknown"** (its NetBox tag read 403s).
**No token is invalid; no re-provision needed.** The launcher additionally
(mis)used `netbox_admin_token` to *create* tags — redundant, since `netbox-sot`
already pre-creates the lifecycle tags (`netbox_sot_catalog_tags`), and a C3
violation (ADR-0032).

## Changes

### A. dmf-infra `netbox-sot` (scoped writer + console read)
1. **New `dmf-catalog-svc` writer** (mirror the AWX svc pattern: group → object
   permission via `manage.py shell` → user → assign):
   - group `dmf-catalog-writer`
   - object permissions (corrected after qwen review + live deploy — the launcher
     CREATEs the per-deployment service and per-function tag, and READS the
     parent LB device, across all 3 stages):
     `ipam.service` (**view+add+change**), `extras.tag` (**view+add**),
     `dcim.device` (**view**, read-only — dmf-traefik LB lookup).
     NOT superuser/staff, no dcim write, no tag change/delete.
2. **Console read fix:** add `extras.tag` (view) to the `dmf-cms-readonly`
   permission set so the catalog page can resolve lifecycle status (kills the
   "unknown").
3. Mint the `dmf-catalog-svc` token (ORM `manage.py shell`, like `awx`/`cms`
   tokens) and persist to OpenBao (`secret/apps/netbox/...` → `catalog_token`).

### B. dmf-infra `awx-integration`
- Read the catalog token from OpenBao (like `awx_integration_netbox_admin_token`
  is read today) → `awx_integration_netbox_catalog_token`.
- Wire it into the catalog JT extra_vars as the launcher's NetBox token
  (e.g. `vault_netbox_catalog_token`); **remove** `vault_netbox_admin_token`
  from catalog JT extra_vars.

### C. dmf-runbooks `nmos-cpp` launcher + role (all 3 stages)
- `netbox_admin_token` → **removed from the role entirely**; every write that
  used it (provision: create-tags `POST /extras/tags/`, create-service
  `POST /ipam/services/`; configure: `PATCH` flip to `lifecycle:active`;
  finalise: `PATCH` flip to `lifecycle:bootstrapped`) now uses the scoped catalog
  token. Reads already use `netbox_api_token`. Simplest: collapse both role token
  vars to one (`netbox_api_token` ← `vault_netbox_catalog_token`).
- **Keep** the create-missing-tags task (it creates `app:nmos-cpp`, which is NOT
  pre-created by netbox-sot) — it just runs under the scoped token (`extras.add_tag`)
  now. Verified: provision.yml DOES `POST /ipam/services/` (needs `add_service`).
- teardown-nmos-cpp: same token swap.

### D. Apply + verify on wobe-9n0c
1. Re-run `691-netbox-sot` (creates dmf-catalog-svc + perms + token; adds
   extras.tag view to cms-svc).
2. Re-run the `awx-integration` configure step (re-wires catalog JT extra_vars).
3. Re-sync the dmf-runbooks AWX project (picks up launcher change).
4. Console catalog status no longer "unknown"; Deploy → AWX job succeeds;
   `helm list -n nmos` shows nmos-cpp; NMOS Query API 200; NetBox service tagged
   `lifecycle:active`. Confirm no `netbox_admin_token` in any catalog JT.

## Out of scope / notes
- The admin token stays bootstrap/break-glass (ADR-0028 C4), removed only from
  steady-state launcher paths.
- A `bootstrap-verify` assertion (dmf-catalog-svc exists, non-superuser, scoped)
  is the ADR-0032 enforcement follow-up.
