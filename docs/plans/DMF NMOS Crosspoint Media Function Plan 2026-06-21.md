---
status: executed
date: 2026-06-21
executed: 2026-06-22
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/108
---
# DMF NMOS Crosspoint Media Function Plan

**Date:** 2026-06-21
**Owner:** operator (with Claude `claude-top`; adversarial cross-check by codex
against live upstream commit `564ca41`, 2026-06-20)
**Branch:** `feat/nmos-crosspoint-media-function` (all touched repos)
**Tracking:** [dmfdeploy/dmfdeploy#108](https://github.com/dmfdeploy/dmfdeploy/issues/108) (closed 2026-06-22)

**Status:** **Executed 2026-06-22.** Phase 1 (visible-first) validated live
end-to-end on sandbox env `sl2p-e8sm`: catalog **Deploy** button → AWX autowake →
JT → Helm → `wss` → registry subscriptions → matrix with both nmos-cpp mock
nodes, plus a full teardown→redeploy lifecycle. Switching stays Phase 2 (MXL).
Live validation surfaced + fixed: `ws://` mixed-content, nmos-cpp registry `:81`
query-ws port, launcher IngressRoute RBAC, console RBAC grant, env-specific JT
inputs, and the sandbox autowake default. Follow-ups filed as
[#119–#127](https://github.com/dmfdeploy/dmfdeploy/issues). Landing PRs:
dmf-media#9, dmf-infra#26, dmf-env#13. Published: image `nmos-crosspoint:0.1.1`,
charts `nmos-crosspoint:0.1.1` + `nmos-cpp:0.1.2`. The original "wiring-only,
deferred-live" framing below is superseded by this live execution.

## Context

Make [`3dmedium/nmos_crosspoint`](https://github.com/3dmedium/nmos_crosspoint) —
a Svelte UI + Node/Express(TypeScript) WebSocket server that discovers NMOS
senders/receivers from a registry (IS-04) and routes them in a crosspoint matrix
(IS-05) — a first-class **DMF media function**: registered in the catalog,
deployable/tearable from the dmf-cms console, reachable behind the private
(Tailscale) lane.

The operator's north star is *"see MXL producers and consumers and switch them."*
Crosspoint only routes **NMOS-registered** senders/receivers. DMF MXL (ADR-0017)
is a **Layer-4 intra-host data plane** (tmpfs ring buffers) that does **not**
register with NMOS — so MXL flows will not appear in crosspoint until an
`nmos-cpp ↔ MXL` adapter exists. The work is therefore **staged**:

- **Phase 1 (this plan):** crosspoint deployable as a media function; the existing
  `nmos-cpp` registry + mock nodes become **visible/listable** in the matrix.
  **Switching is NOT a Phase-1 acceptance criterion** — IS-05 PATCH routing
  depends on the mock nodes advertising `controls[].href` values routable from the
  crosspoint pod, which is unproven and likely won't work for the mock nodes.
  Operator confirmed: *visible-first is the goal; switching comes with
  real/MXL-backed senders.*
- **Phase 2 (separate issue, documented only):** the `nmos-cpp ↔ MXL` adapter.
  Much larger than a `flow_def.json`→registry shim (see §Phase 2).

This is a multi-repo change mirroring the proven `nmos-cpp` catalog pattern
(ADR-0013 catalog model, ADR-0014 AWX layout, ADR-0025 in-cluster EE + Helm).
Scope: **catalog card + link-out** for CMS surfacing; **wiring + local static
checks only** this round (no live AWX deploy — cluster is mid
control-plane-stability work, see #106).

Canonical reference: [`docs/architecture/DMF Function Catalog Model.md`](../architecture/DMF%20Function%20Catalog%20Model.md).

## The catalog pattern we copy (per `nmos-cpp`)

| Artifact | Path | Template |
|---|---|---|
| Catalog entry | `dmf-media/catalog/<key>.yaml` | `nmos-cpp.yaml` |
| Helm chart | `dmf-media/charts/<key>/` | `charts/nmos-cpp/` |
| NetBox-side role | `dmf-runbooks/roles/<key>/` | `roles/nmos-cpp/` |
| Launch/teardown | `dmf-runbooks/playbooks/{launch,teardown}-<key>.yml` | `launch-nmos-cpp.yml` |
| AWX JT + image wiring | `dmf-infra/.../awx-integration/defaults/main.yml` + `630-zot-seed-platform.yml` | `nmos-cpp` entries |

dmf-cms renders it automatically: reads catalog YAML, joins the NetBox
`ipam.Service` `lifecycle:*` tag, shows a card, Deploy/Teardown POST to the
`media-launch-<key>` / `media-finalise-<key>` AWX job templates. **Key
`nmos-crosspoint`** is threaded through everything (catalog file, NetBox tag
`app:nmos-crosspoint`, AWX JT names, chart name, role dir).

## Step 0 — Worktree, branches, tracking issue ✔

- Branch (all repos): `feat/nmos-crosspoint-media-function`, worktrees under
  `~/repos/dmfgithub/worktrees/nmos-crosspoint/` (isolated from other live
  agents' shared trees), all off `origin/main`.
- Tracking issue #108 opened (`workstream:catalog`, `component:cross-repo`,
  `component:dmf-media`, `component:dmf-cms`, milestone `v0.2`).
- Component-repo commits reference it fully qualified: `Refs dmfdeploy/dmfdeploy#108`.

## Step 1 — Build the crosspoint image (`dmf-media`)

No official image; build ARM64 from upstream at a **pinned commit**.

- `dmf-media/docker/nmos-crosspoint/Dockerfile` (multi-stage):
  - Build: clone at pinned commit (`ARG`, default `564ca41`). Build `/ui`
    **first** (its `vite.config.ts` writes the built UI to `../server/public`),
    then `/server` (`tsc` → `dist/`). Dev deps in this stage.
  - **Node:** upstream Dockerfile uses Node 24; Vite/Rolldown require
    `^20.19.0 || >=22.12.0`. Pin **`node:24`** (or `node:20.19+`) — not floating
    `node:20`.
  - Runtime: copy `server/dist`, **`server/public`** (without it the server runs
    but renders nothing), production-only deps. `WORKDIR /app/server`, `EXPOSE 80`,
    `ENTRYPOINT ["node","./dist/server.js"]`. Config at `/app/server/config`;
    writable `state/`.
- `dmf-media/bin/publish-nmos-crosspoint.sh` → `ghcr.io/dmfdeploy/nmos-crosspoint:<tag>`.
- **This round:** build locally (Colima arm64) at the pinned ref; assert
  `server/public/index.html` is in the image; capture digest. GHCR push + Zot
  mirror are deferred.

## Step 2 — Helm chart (`dmf-media/charts/nmos-crosspoint/`)

Single Deployment (not a StatefulSet). Templates:

- `Chart.yaml` (`name: nmos-crosspoint`, `version: 0.1.0`).
- `values.yaml`: image repo/tag (default Zot
  `zot.zot.svc.cluster.local:5000/dmf/nmos-crosspoint`), namespace `nmos`,
  ingress host, registry endpoint.
- `deployment.yaml` (port 80, mounts config + state), `service.yaml` (ClusterIP).
- `ingressroute.yaml` — Traefik **private** entrypoint (`websecure`) **plus the
  private ingressclass annotation**
  `traefik.ingress.kubernetes.io/router.ingressclass: traefik-private` (mirror
  `dmf-infra/.../roles/services/netbox`); entrypoint alone is insufficient.
- `configmap.yaml` — **`settings.json`** (upstream reads `./config/settings.json`
  and exits if missing; there is no `nmos.json`). Registries under
  `staticNmosRegistries[]`, `ip` = **bare hostname** (no scheme/port):
  ```json
  { "staticNmosRegistries": [
      { "ip": "nmos-cpp-registry.nmos.svc.cluster.local",
        "port": 80, "priority": 10, "domain": "" } ] }
  ```
- `secret.yaml` — **full `users.json` object** (`users.<name>.password` SHA256 +
  groups + permission blocks); the upstream example grants `__noAuth` write —
  **tighten** so IS-05 PATCH requires the admin/operator group. Admin password
  from OpenBao at deploy time; SHA256 computed by the role; plaintext never in
  git/logs.
- **Single chart version** wired identically across catalog YAML, the 630 seed
  list, and the runbook `helm pull` (avoid the nmos-cpp 0.1.0↔0.1.1 drift).

## Step 3 — NetBox role + launchers (`dmf-runbooks`)

- `roles/nmos-crosspoint/` (copy `roles/nmos-cpp/`): NetBox-side only — create
  `ipam.Service`, flip the single load-bearing `lifecycle:*` tag; compute the
  crosspoint admin SHA256 from an OpenBao-sourced password.
- `playbooks/launch-nmos-crosspoint.yml`: role provision → `helm pull` from Zot
  `--plain-http` → `kubernetes.core.helm` install (`wait: false`) → explicit
  `k8s_info` readiness gate on the Deployment → role configure (tag → active).
- `playbooks/teardown-nmos-crosspoint.yml`: helm uninstall → role finalise (tag →
  bootstrapped).
- `ansible-playbook --syntax-check` both.

## Step 4 — Catalog entry (`dmf-media/catalog/nmos-crosspoint.yaml`)

- `key: nmos-crosspoint`, `display_name: "NMOS Crosspoint"`.
- `ebu: { layer: 5, vertical: control, lifecycle_owner: configure }`.
- `provision`: namespace `nmos`, image `.../dmf/nmos-crosspoint` + digest from
  Step 1, chart `nmos-crosspoint` 0.1.0, `netbox_service` name `nmos-crosspoint`,
  ports `[80]`, exactly one `lifecycle:*` tag.
- `configure`: `media-launch-nmos-crosspoint`, `on_success_tag: lifecycle:active`,
  `health_probe: { kind: http, path: /, expect_status: 200 }` — a **liveness**
  signal only (proves the SPA shell serves, not registry/IS-05 health).
- `finalise`: `media-finalise-nmos-crosspoint`.
- `dependencies: [ "nmos-cpp" ]` (informational v1).

## Step 5 — AWX + Zot wiring (`dmf-infra`)

- `awx-integration/defaults/main.yml`: append `media-launch-nmos-crosspoint` /
  `media-finalise-nmos-crosspoint` to `awx_catalog_job_templates`
  (`project_name: dmf-runbooks`, same `netbox_api_url` / scoped
  `vault_netbox_catalog_token` extra_vars, ADR-0032); add `nmos_crosspoint_*`
  image/chart vars next to the `nmos_cpp_*` block.
- **`630-zot-seed-platform.yml`:** add crosspoint entries to the
  **`zot_seed_images` and `zot_seed_charts` lists** — the AWX defaults vars are
  not what 630 mirrors; without these the launcher is wired but the chart/image
  never reach cluster Zot.

## Step 6 — dmf-cms surfacing: catalog card + link-out

Deploy/Teardown render automatically. The **link-out is not free**:
`catalog.py:CatalogEntry` drops unknown top-level YAML fields and `_entry_to_dict`
returns only known fields, and the card has no generic runtime-URL rendering.
Either:

- **(A, preferred)** stamp the endpoint URL on the NetBox `ipam.Service` (a field
  CMS already surfaces for active entries) and render it — *verify first* in
  `main.py`/`index.tsx`.
- **(B)** extend the schema end-to-end: add `ingress` to `CatalogEntry` +
  `_entry_to_dict` (`catalog.py`, `main.py`), `types.ts`, and an "Open" link on
  `lifecycle:active` cards (`pages/Catalog/index.tsx`).

No new page, no NMOS proxy, no native matrix.

## Phase 2 (documented only — not built here): `nmos-cpp ↔ MXL` adapter

Reading MXL flow defs and POSTing IS-04 resources gives *visibility*, not
*switchability*. A real adapter must expose genuine NMOS Node/Connection
behaviour for MXL endpoints:

- IS-04 Node lifecycle (registration + heartbeats) and ownership of the full
  resource tree (Node → Device → Source → Flow → Sender/Receiver).
- A **routable Node API** and **IS-05 Connection API** endpoints (so a PATCH to
  `/single/receivers/<id>/staged` lands and reconfigures the MXL graph).
- Sender manifests / transport params, stale-flow cleanup, MXL co-location policy
  (`dmf.io/mxl=true` taint + processor-node selector, ADR-0017), and a decision
  on how MXL Fabrics / libfabric-TCP v1.1 fits ADR-0017.

Cross-ref ADR-0017, [`DMF MXL Single-Node Loopback Execution Plan 2026-05-29.md`](./DMF%20MXL%20Single-Node%20Loopback%20Execution%20Plan%202026-05-29.md) §6,
and [`docs/reviews/dmf-mxl-upstream-profile-and-contribution-review-2026-06-01.md`](../reviews/dmf-mxl-upstream-profile-and-contribution-review-2026-06-01.md).
Open a separate tracking issue + plan.

## Verification (this round — local/static only)

1. `docker build` on Colima arm64 at the pinned ref → succeeds;
   `server/public/index.html` present; record digest.
2. `helm lint` + `helm template` render cleanly.
3. `ansible-playbook --syntax-check` on both new playbooks.
4. `yamllint` the catalog entry + role defaults; confirm exactly one `lifecycle:*`
   tag.
5. `bin/check-docs.sh` passes (this doc's frontmatter parseable; `INDEX.md`
   regenerated).
6. dmf-cms catalog loader parses the new YAML (matches `catalog.py:CatalogEntry`).

**Deferred to a later live round:** GHCR push + `630` Zot mirror, AWX JT
registration run, launching `media-launch-nmos-crosspoint` on the sandbox env,
confirming crosspoint **lists** the mock nodes. Switching is a *stretch* check
(inspect `controls[].href`, curl from an in-cluster pod, PATCH a receiver
`/staged`), expected to fail on mock nodes — acceptable for this step.

### Local functional test — PASSED 2026-06-22 (off-cluster, Mac Colima)

Throwaway `docker-compose` harness (`~/repos/dmfgithub/worktrees/nmos-crosspoint-localtest/`,
uncommitted): crosspoint + GHCR `nmos-cpp` registry + 2 mock nodes. Result: UI
served (`<title>NMOS Crosspoint</title>` → `server/public` shipped), crosspoint
opened **6 Query-API subscriptions**, registry held **10 senders / 10 receivers**,
and the **matrix listed both mock nodes** (node-1 receivers as rows, node-2
senders as columns). Zero impact on any cluster.

### Post-review fixes (codex pre-landing cross-check, 2026-06-22)

- **Admin password fails closed:** launcher asserts `vault_nmos_crosspoint_admin_password`
  is non-empty and drops the `changeme-dev` fallback (AWX supplies the
  OpenBao value).
- **ADR-0038 probe stamping complete:** role now stamps
  `cluster_service`/`cluster_namespace`/`cluster_port` (+ `probe_module`), all
  cleared on finalise — so dmf-promsd probes the in-cluster Service, not the
  ingress.
- **CMS Open link:** suppressed for `*.example.com` placeholder hosts (no dead
  link); lights up only with a real env host (future: stamped from the NetBox
  runtime endpoint).

## Live deploy runbook (.134 constrained node) — deferred, gated

**Pre-flight:** (1) rebase all branches on `origin/main` (constrained-node +
AWX direct-scaling #110); (2) GHCR push image + chart and **replace the
placeholder digests** in `catalog/nmos-crosspoint.yaml`, awx-integration
defaults, and `630`; (3) AWX must supply the OpenBao admin password.

**Sequence (verify `kubectl` context = the .134 env first):**
1. **Snapshot** monitoring replicas (`kubectl -n monitoring get deploy,sts`).
2. Suppress external alerting; **scale DOWN** high-memory monitoring (Prometheus,
   Loki, dmf-promsd, exporters). **Do NOT scale** NetBox, Zot, Forgejo,
   Traefik/private-ingress, External-Secrets/OpenBao, or the AWX-autoscale
   helper. Promtail is a **DaemonSet** — handle separately or leave.
3. Run `630` Zot mirror (real digests) + AWX JT registration.
4. Deploy **nmos-cpp first**; verify registry + 2 mock nodes registered. **Then**
   crosspoint; verify the matrix lists the nodes. (createNamespace:false assumes
   nmos-cpp already created the `nmos` namespace — ordering matters.)
5. Teardown crosspoint + nmos-cpp; **restore** monitoring to the snapshotted
   counts; wait for dmf-promsd ready + Prometheus targets.

Footprint added during the window ≈ 384Mi req / 768Mi limit (nmos-cpp
registry+2 nodes + crosspoint) — all on-demand, reclaimed on teardown.

## Out of scope

- The `nmos-cpp ↔ MXL` adapter (Phase 2, separate issue).
- Embedded iframe page or native crosspoint rebuild in dmf-cms.
- Real RTP/ST-2110 senders, PTP, multicast.
- Public exposure of NMOS/crosspoint (private/tailnet lane only).
