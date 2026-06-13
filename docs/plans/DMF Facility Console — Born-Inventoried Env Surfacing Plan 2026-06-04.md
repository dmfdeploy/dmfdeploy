---
status: draft
date: 2026-06-04
---
# DMF Facility Console — Born-Inventoried Env Surfacing Plan (2026-06-04)

> **Status:** PLAN (2026-06-04). **No implementation has started.** Single-session,
> **dmf-cms-only** work package a freshly-cleared agent can pick up. Independent of the
> in-flight NetBox-driven monitoring effort (ADR-0038) — **no dmf-infra / born-inventory
> changes**: the env model already exists in NetBox. Live e2e is the final step, run
> against the env in `STATUS.local.md` after running `bin/generate-status.sh` when a cluster is available.

---

## Context — why this work

The operator wants the dmf-cms **Facility** page to show the **born-inventoried `<env>`**.
A read-only survey (recorded in **ADR-0039**) found:

- The env **already exists** in NetBox as a per-env **Site** (`DMF <label/id>`) and
  **Cluster** (`<env_id>`), each carrying custom fields `dmf_env_id`, `dmf_env_label`,
  `dmf_provider`, `dmf_architecture` (written by `dmf-born-inventory`).
- **No per-env tag exists and none should be added** (ADR-0039): env ids rotate → tag
  sprawl; consumers scope by Site/Cluster (or `cf_dmf_env_id`) and reach leaves by FK.
- **The gap is entirely in dmf-cms.** `Facility.tsx` →
  `/api/facility/summary` + `/api/facility/devices` →
  `netbox.list_sites()`/`list_devices()` query `dcim/sites?brief=1` and `dcim/devices`
  **unscoped**, never read `dmf_env_id`, and only render `dcim.device` objects — which is
  just the lone `dmf-traefik` load balancer. The k3s **nodes are
  `virtualization.virtual-machine`s** and are not queried at all; `ipam.Service`s aren't
  shown. So today the page cannot show "the env".

**Goal:** the Facility page leads with an **Environment** card (the born-inventoried env:
id, label, provider, architecture, counts) and shows the env's real inventory (nodes as
VMs, plus the LB device), read from the Site/Cluster + `dmf_env_id` NetBox already holds —
**no new tags, no born-inventory change.**

**Canonical doctrine to (re)read:** **ADR-0039** (env identity = Site/Cluster +
`dmf_env_id`; no per-env tag), ADR-0037 (Media Workloads scoping precedent),
ADR-0038 (monitoring — site-derived labels; keep env scoping aligned).

---

## Conventions a fresh agent must follow

- **Boot ritual** (umbrella CLAUDE.md): `git fetch && pull` → `bin/generate-status.sh` → read `STATUS.local.md` →
  read newest `docs/handoffs/` (the env-surfacing handoff 2026-06-04 is the pointer) →
  skim `docs/decisions/INDEX.md` (apply **ADR-0039**). `git status` dmf-cms **before
  touching it — ask the operator if it is dirty** (other agents may be mid-change).
- **Branch discipline:** land on `main` in dmf-cms; verify `HEAD == main` first
  (`feedback_verify_main_branch_before_work`,
  `feedback_converge_on_main_no_feat_branches`). No feature branch.
- **dmf-cms build/release is the only sanctioned path** — skill
  `dmf-cms-build-and-release` + `dmf-cms/docs/DEVELOPMENT-AND-BUILD-RULES.md`:
  `VERSION`-driven, image → GHCR via `bin/publish-to-ghcr.sh` → mirrored to cluster Zot by
  playbook **630** → deployed by playbook **650**. Never build/deploy by hand. Bump
  `VERSION` + `scripts/sync-version.sh`.
- **No IPs/DNS in any committed artefact** (gitleaks + scrub on commit); the running app
  reads NetBox URL/token from settings (ESO/OpenBao), not from code.
- **Local checks (no live cluster):** backend `ruff` + a unit test of the JSON shaping
  against a NetBox fixture; frontend `pnpm build` (+ typecheck). Live e2e is the final
  step only.

---

## Reference patterns (study before coding)

| Pattern | Where | Use as template for |
|---|---|---|
| NetBox REST client (auth, SSL skip, list helpers) | `dmf-cms/src/dmf_cms/netbox.py` — `_request`, `_ssl_context`, `list_sites`, `list_devices` | the new `list_*` functions below |
| Facility endpoints + auth gate | `dmf-cms/src/dmf_cms/main.py` — `api_facility_summary` (~L662), `api_facility_devices` (~L702), `_require_user` (~L76) | the new `/api/facility/env` + node inclusion |
| Role gating (if engineer/admin scope wanted) | `main.py` admin endpoints (~L412/486) checking `user.role`; `ROLE_ORDER`/`ROLE_GROUPS` | optional gate on `/api/facility/env` |
| Frontend data hooks | `dmf-cms/frontend/src/api/hooks.ts` — `useFacilitySummary`/`useFacilityDevices` (~L135–151) | `useFacilityEnv()` |
| Frontend types | `dmf-cms/frontend/src/api/types.ts` — `FacilitySummary`, `NetBoxDevice` (~L141–166) | `FacilityEnv`, node row type |
| Facility page layout (hero + summary cards + table) | `dmf-cms/frontend/src/pages/Facility.tsx` | env card + Nodes table |

> **NetBox gotcha:** `list_sites()` uses `?brief=1`, and **brief responses strip
> `custom_fields`**. The env fields require a **non-brief** sites/clusters query.

---

## Implementation (the change — dmf-cms only)

### Backend — `src/dmf_cms/netbox.py`
Add functions mirroring the existing `list_devices` shape (same `_request`/`_ssl_context`
signature, `?limit=100`):

- `list_sites_full(...)` — `GET /api/dcim/sites/?limit=100` (**no `brief=1`**); returns
  sites including `custom_fields` + `status`.
- `list_clusters(...)` — `GET /api/virtualization/clusters/?limit=100` (incl.
  `custom_fields`, `name`).
- `list_virtual_machines(..., cluster_id: int | None = None)` —
  `GET /api/virtualization/virtual-machines/?limit=100[&cluster_id=…]`; project
  `name, status, vcpus, memory, disk, role, primary_ip`.
- `list_services(..., device_id: int | None = None)` *(optional, for the services count/
  list)* — `GET /api/ipam/services/?limit=100[&device_id=…]`.

### Backend — `src/dmf_cms/main.py`
- New `GET /api/facility/env` (gated by `_require_user`; add a `user.role` check only if
  the operator wants engineer/admin-only). For each Site whose `custom_fields.dmf_env_id`
  is non-empty, emit:
  ```json
  { "name", "slug", "env_id", "env_label", "provider", "architecture",
    "status", "node_count", "device_count", "service_count" }
  ```
  - `node_count` = VMs in the matching Cluster (match Cluster by `dmf_env_id`, query
    `list_virtual_machines(cluster_id=…)`).
  - `device_count` = `dcim/devices/?site_id=<site.id>` count.
  - Return a **list** (not a single object) so a NetBox holding several / leftover envs
    renders one card each.
  - Graceful fallbacks identical to the existing endpoints (`netbox.configured` guard,
    `{"error": …}` on exception).
- Extend `/api/facility/devices` to also include **nodes** (VMs) — or add a sibling
  `GET /api/facility/nodes` — so the inventory reflects the cluster, not just the LB.

### Frontend — `api/types.ts`, `api/hooks.ts`
- `FacilityEnv` interface (mirrors the JSON above) + a node row type.
- `useFacilityEnv()` hook (queryKey `['facility','env']`) and, if a nodes endpoint is
  added, `useFacilityNodes()`.

### Frontend — `pages/Facility.tsx`
- Add an **Environment** hero/header card at the top: env id, label, provider,
  architecture, and node/device/service counts — the "born-inventoried env" the operator
  asked for. Reuse the existing `panel` / metric-card styling already in the file.
- Add a **Nodes** table (the k3s VMs) alongside the existing **Physical Devices** table.
- If `/api/facility/env` returns >1 env, render one card per env and group inventory under
  it; with one env, one card.

---

## Out of scope (explicit, deferred)
- **Any dmf-infra / born-inventory change.** The Site/Cluster/`dmf_env_id` model already
  exists; do not modify it (and the monitoring effort owns those files).
- Adding `dmf_env_id` to `ipam.Service` / `dcim.device` — a **future** option in ADR-0039
  if env-scoped service queries get hot; not now.
- Per-user / per-tenant NetBox tokens and media-tenant scoping (ADR-0037 surface).
- Monitoring lanes / PromSD targets (ADR-0038).
- Any new per-env **tag** (ADR-0039 says no).

---

## Verification

**Local (no cluster):**
- `ruff` clean; a backend unit test feeds a NetBox JSON fixture (a Site with
  `custom_fields.dmf_env_id`, a matching Cluster, some VMs) and asserts the
  `/api/facility/env` JSON shape + counts.
- `pnpm build` + typecheck the frontend.

**Live e2e (the env in `STATUS.local.md`, when a cluster exists):**
1. Build + release dmf-cms via the `dmf-cms-build-and-release` skill (VERSION bump → 630 →
   650).
2. Open `/facility`: the Environment card shows `dmf_env_id` / label / provider /
   architecture **matching** the Site/Cluster custom fields; the Nodes table lists the k3s
   VMs; with a single live env, exactly one env card.
3. Cross-check against NetBox directly:
   `GET /api/dcim/sites/?cf_dmf_env_id=<id>` and `GET /api/virtualization/clusters/` return
   the same env_id and counts.
