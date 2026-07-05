---
status: executed
date: 2026-07-03
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/17
---
# DMF MXL Single-Node Revival Plan (2026-07-03)

> **STATUS: PROPOSED — documents-only round; no code edits yet.** Makes the MXL media
> functions runnable again on the committed **single-node** proof surface (operator
> decision 2026-07-03: *"single node MXL demo"*). Cross-host fabrics (≥2 nodes,
> verbs/eRDMA) stays deferred per `../decisions/architectural-commitments-v1.md`
> (multi-node is an explicit v0.1 non-goal); the preserved spike learnings live in
> `../sessions/DMF MXL Cross-Cloud Media-Node Spike — As-Built and Fabrics Result
> 2026-05-30.md`.

**Components:** `dmf-media` (catalog + charts), `dmf-runbooks` (launchers),
`dmf-infra` (bootstrap node prep, AWX JT seed — already present), `dmf-cms` (console
surface — via #173, not this plan). Doc lives in the umbrella.
**Tracking:** #17 (existing, v0.2) — this plan is its spec.

---

## 1. Context — why MXL functions don't run today

Survey 2026-07-03 (live env + repos). The chain catalog → AWX JT → launcher → Helm
chart exists end-to-end (JTs seeded from
`dmf-infra/.../roles/stack/operator/awx-integration/defaults/main.yml`; launchers in
`dmf-runbooks/playbooks/launch-*.yml`), but four gaps stop it:

1. **Scheduling:** `charts/mxl-fabrics-demo/values.yaml` hard-codes
   `nodeSelector: dmf.io/role=mxl-processor` + toleration for
   `dmf.io/mxl=true:NoSchedule` — the retired spike nodes. On a single-node env the
   pods are unschedulable.
2. **Images:** catalog Provision digests are `sha256:0000…` placeholders in
   `dmf-media/catalog/mxl-videotestsrc.yaml` and `mxl-videotest-view.yaml` (also
   `nmos-cpp.yaml`); `mxl-hello.yaml` and the launcher default ride the dev tag
   `v1.0.3-fabrics-dev`.
3. **Console:** `DMF_CONSOLE_MXL_ENDPOINTS` defaults empty → the MXL Flows page
   renders nothing (its replacement surface is #173's Media Workloads page).
4. AWX runs scale-to-zero; any launch requires a wake (known cost, not a defect).

## 2. Target demo (acceptance)

On a fresh single-node sandbox env, from the console catalog:
**deploy `mxl-videotestsrc` (initiator) + `mxl-videotest-view` (target) onto the same
node** over the libfabric `tcp` provider; receiver flow reports `Active: true` with a
climbing head index (the spike's own GREEN criterion), and the test-pattern preview is
visible in the console (Media Workloads detail panel once #173 lands). `mxl-hello`
(writer + fake-reader, designed single-node) also deploys and finalises cleanly.

## 3. Work packages

### WP1 — Images: publish + pin
- Build/publish `ghcr.io/dmfdeploy/mxl-fabrics-demo` at a **release tag** (multi-arch
  arm64/amd64, anon-pullable — same bar as dmf-promsd/dmf-cms images); retire
  `v1.0.3-fabrics-dev` from `dmf-media/catalog/mxl-hello.yaml` and
  `dmf-runbooks/playbooks/launch-mxl-fabrics-demo.yml` defaults.
- Replace the `sha256:0000…` placeholder digests with the release-pinned digests in
  `mxl-videotestsrc.yaml` and `mxl-videotest-view.yaml`. (`nmos-cpp.yaml` has the same
  defect but is **out of this slice** — review decision: it belongs to #123 where its
  secret/monitoring siblings live, unless this plan grew an NMOS regression gate,
  which it deliberately does not.)
- Verify the 630 mirror path pulls them into Zot (the launcher installs charts from
  in-cluster Zot).

### WP2 — Single-node scheduling: `placement_mode` (decision taken at review)
**Decision (codex cross-check, 2026-07-03): a chart/launcher placement mode is
required — a label-only approach cannot work.** The chart hard-codes not just
`dmf.io/role=mxl-processor` but **per-role selectors** `dmf.io/mxl-demo-role: source`
(initiator) and `dmf.io/mxl-demo-role: view` (target) — one node cannot carry both
values of the same label key, so "label the node, chart unchanged" is impossible for
the colocated pair.
- Chart + launcher gain **`placement_mode: single-node | split-node`** (default
  `split-node` preserves today's behavior). In `single-node` mode the
  `dmf.io/mxl-demo-role` selector is omitted (both releases schedule by
  `dmf.io/role=mxl-processor` alone); in `split-node` mode the per-role selectors
  render as today.
- The sandbox lane still labels its node `dmf.io/role=mxl-processor` at bootstrap
  (one node-prep task) so placement records stay truthful. **No taint on the only
  node** — the predecessor plan's taint-interaction table (`DMF MXL Single-Node
  Loopback Execution Plan 2026-05-29.md` §4: node-exporter/promtail need explicit
  tolerations, Traefik LB target black-holes) shows a taint there would repel or
  complicate every platform workload; the chart's toleration stays (harmless when
  no taint exists).

### WP3 — Colocated fabrics demo audit
- The initiator/target pair currently assumes `hostNetwork` + host port `1234` and a
  `Recreate` strategy (spike as-built). Same-host colocation audit: fabric port
  collision (initiator connects out, only the target binds — confirm), and
  `mxl-coordinator` ConfigMap contents for same-host addressing.
- **Known second collision (codex cross-check):** both deployments run the status
  sidecar bound `0.0.0.0:$STATUS_PORT` from the same `.Values.status.port` default
  (`9000`) — under `hostNetwork` on one node, source and view **collide on the
  status port even if 1234 is safe**. Fix in `single-node` mode: distinct status
  ports per role/release (values-driven), or better, drop `hostNetwork` for the
  status sidecar entirely and expose it via the WP5 Service — evaluate whether the
  fabric path itself needs `hostNetwork` intra-node at all (pod network may do;
  smaller blast radius on the shared node).
- Success gate = §2 acceptance; measure grain latency for the record (spike baseline:
  ~2-grain/~50 ms cross-VPC; intra-node should beat it comfortably).

### WP4 — `mxl-hello` validation
- Deploy → finalise on the same env (it shares WP1's image + WP2's placement); its
  catalog placement note (requires `mxl-processor` label) stays accurate — WP2 keeps
  that label as the placement key in both `placement_mode`s.

### WP5 — NetBox + monitoring wiring
- **Prerequisite (codex cross-check): the chart currently has no `kind: Service`** —
  ADR-0038 Amendment A stamps `cluster_service` as a Kubernetes **Service** name, so
  WP5 first adds a per-release Service exposing the status sidecar port (this is also
  WP3's preferred fix for the status-port collision), then launchers stamp instance
  records + cluster coords per ADR-0037 D3 / ADR-0038 Amendment A
  (`cluster_service`/`cluster_namespace`/`cluster_port`, probe lane
  `probe_module`/`probe_path` — the sidecar's `/status` is the health surface),
  mirroring the nmos-cpp launcher pattern (dmf-runbooks `e11bd3e`).
- Result: MXL instances appear in the Media Workloads inventory (#173) and the
  "Platform services" dashboard (#166 WP-G) with zero bespoke wiring.

### WP6 — Console surface
- **Primary:** #173's Media Workloads page (inventory from WP5's records; test-pattern
  preview via the existing `mxl.py` sidecar fan-out as the per-instance detail).
- **OQ-1 for the cross-check:** interim-stamp `DMF_CONSOLE_MXL_ENDPOINTS` (a deploy
  task templating the cms env from the launched releases) so the *current* MXL Flows
  page shows the demo before #173 lands — or skip the interim entirely and let the
  demo be console-visible only when #173 merges. Leaning **skip** (throwaway wiring,
  and #173 WP4 deletes the page); challenge if the demo needs to be showable sooner.

## 4. Out of scope
- Cross-host fabrics, second media node, Tailscale join, verbs/eRDMA zero-copy — all
  deferred (commitments-v1 non-goal; spike learnings preserved).
- nmos-crosspoint Phase 2 switchability (#129, #123 track its follow-ups).
- dmf-media catalog-v2 roles (frozen scaffold per commitments-v1).

## 5. Open questions for the cross-check
- **OQ-1:** WP6 interim endpoint stamping — worth it? (see above; leaning skip).
- **OQ-2 (RESOLVED, 2026-07-03 review round):** label-only is impossible (per-role
  `dmf.io/mxl-demo-role` selectors); WP2 is the `placement_mode` chart/launcher
  mechanism, no-taint, label kept.
- **OQ-3 (RESOLVED, 2026-07-03 review round):** `nmos-cpp` digest fix moves to #123 —
  this slice carries no NMOS acceptance gate, so it must not carry the change.
- **OQ-4 (RESOLVED, 2026-07-04 — see Amendment A):** release tag `v1.0.3`, a
  digest-preserving retag of the proven `v1.0.3-fabrics-dev` artifact (a DMF
  demo-artifact tag, not an upstream MXL SDK version claim).

## 6. Verification plan
- **Static:** catalog schema check scoped to the entries this plan touches
  (`mxl-videotestsrc`, `mxl-videotest-view`, `mxl-hello`: digests resolve, no `0000…`
  remains — `nmos-cpp.yaml`'s placeholder is deliberately deferred to #123); launcher
  `ansible-playbook --syntax-check`; chart `helm template` in both `placement_mode`s.
- **Live (single-node sandbox):** console catalog deploy of videotestsrc + view →
  pods Running on the node → receiver flow `Active: true`, head index climbing;
  `mxl-hello` deploy → finalise; NetBox instance records present with cluster coords;
  `probe_success` for the stamped sidecar target; teardown leaves NetBox clean.
- **Regression:** none required beyond the MXL entries — this slice deliberately
  carries no NMOS acceptance gate (nmos-cpp/nmos-crosspoint changes live in #123);
  if a shared launcher file is touched, its syntax-check covers the blast radius.

## 7. Delivery & commit plan
- PRs per component repo (`dmf-media` chart/catalog, `dmf-runbooks` launcher vars,
  small `dmf-infra` node-prep change for the `mxl-processor` label), each referencing
  **`refs dmfdeploy/dmfdeploy#17`** fully
  qualified; the completing PR set closes #17 manually and flips this frontmatter
  `draft → executed` in the umbrella.
- WP1 lands first (publishable independently); WP2+WP3+WP4 as the demo slice;
  WP5 with the launcher edits; WP6 rides #173.

## Amendment A (2026-07-04) — WP1 executed as digest-preserving retag; chart publish moves to the demo slice

Codex-gated (GATE-13, CHANGES-NEEDED → folded; core deviation accepted). Deltas
against §3 WP1 as written:

- **Retag, not rebuild.** `ghcr.io/dmfdeploy/mxl-fabrics-demo:v1.0.3` was created
  as a digest-preserving retag of `v1.0.3-fabrics-dev` —
  `sha256:84980dc0c3e1de0a8f3ce12ce4d5149229c73a44b140c15ed77b8e84fb2108b1`,
  `linux/arm64`, created 2026-05-30: the exact artifact the fabrics spike proved
  GREEN. A rebuild would have produced a different, unproven digest and cost hours
  of native C++/vcpkg compile for no evidence gain.
- **amd64/multi-arch deferred** (not silently dropped): ADR-0031's release gate
  requires `linux/arm64` only; commitments-v1 makes single-node ARM64 the proof
  surface; the Dockerfile pins the `aarch64-linux-gnu` triplet (spike doc records
  the x86 caveat). Revisit only if an amd64 deploy target ever appears.
- **No-rebuild acceptance check** (mechanical, run on any future WP1-touching
  change): `skopeo inspect docker://ghcr.io/dmfdeploy/mxl-fabrics-demo:v1.0.3`
  must report the digest above and `Architecture: arm64`.
- **WP1 is source-level only; the runtime flip rides the demo slice.** The
  published `mxl-hello` chart `0.1.0` (seeded into Zot by dmf-infra 630 with a
  pinned chart digest) still renders the dev tag, and `charts/mxl-fabrics-demo`
  is not published to GHCR at all (nor in 630's seed list) even though the
  catalog entries + launcher expect it from in-cluster Zot. The demo slice
  (WP2+WP3+WP5) therefore additionally carries: republish `mxl-hello` as `0.1.1`
  (tag bump only) and `mxl-fabrics-demo` as `0.2.0` (with the placement_mode +
  Service work), update 630's chart seed digests, **add a 630 image seed entry
  for `mxl-fabrics-demo`** (source digest pinned to `sha256:84980dc0…`, dest tag
  `v1.0.3`), and flip the chart image registry defaults to in-cluster Zot per
  ADR-0025 (mirroring the nmos-cpp pattern) so the catalog digest becomes the
  actual pull contract rather than advisory metadata.

## Amendment B (2026-07-04) — demo-slice design after GATE-14

Codex GATE-14 (CHANGES-NEEDED → folded) reviewed the WP2+WP3+WP5 implementation
design. Locked decisions and the two structural discoveries:

- **WP2 placement:** chart `placementMode: split-node` default (single-node omits
  the per-role `dmf.io/mxl-demo-role` selector; `dmf.io/role=mxl-processor`
  renders in both modes). Launcher passes `--set placementMode=`; the AWX JT
  extra_vars are **profile-derived** (`single-node` only when
  `dmf_release_profile == sandbox-single-node`, else `split-node`) so split-node
  AWX operation stays intact. Node label = idempotent post-install task in
  300-k3s (`kubectl label --overwrite`), inventory/profile-gated; NOT
  `INSTALL_K3S_EXEC --node-label` (install-time only). No taint.
- **WP3 colocation:** in `single-node` mode both deployments drop `hostNetwork`
  (pod network): target binds :1234 in its own netns, the coordinator
  ConfigMap handshake is address-agnostic (pod `eth0` IP flows into
  target-info), and both status sidecars keep :9000 with no collision.
  `split-node` renders byte-identical to today. Live verify must additionally
  prove **target-restart/staleness recovery** (epoch change observed by the
  source, reconnect, `Active: true`, head index climbing post-restart) and
  assert `mxl_interface=eth0` for single-node runs.
- **WP5 Service + stamping:** per-release Service is **role-conditional and must
  select pod-template labels** (`app: <release>-initiator|target` — the
  `dmf.component` label exists only on Deployment metadata; selecting it gets
  zero endpoints). Launch stamps `cluster_service`/`cluster_namespace`/
  `cluster_port=9000` + `probe_module=http_2xx`/`probe_path=/status`; teardown
  clears them (nmos-cpp pattern). **Discovery: MXL has no NetBox provision
  path** — the catalog `netbox_service` block creates nothing; dmf-runbooks
  gains MXL provision/clear tasks (ensure `ipam.Service` with catalog tags
  before flipping lifecycle), mirroring the nmos-cpp role.
- **P1 discovery — AWX catalog lane cannot launch MXL today:** the DMF catalog
  Container Group pod-overrides every catalog JT into the `nmos` namespace
  under the `nmos-cpp-launcher` ServiceAccount, whose RBAC is nmos-scoped. The
  demo slice therefore extends awx-integration: pre-create the `mxl` namespace,
  grant the catalog launcher identity Role/RoleBinding coverage there (all
  chart-rendered kinds incl. the chart's own SA/RBAC objects), without touching
  the nmos grants. (Generalized identity, not a namespace-override swap.)
- **P1 discovery — console preview needs dmf-cms chart plumbing:** the
  v0.12.0 live-view panel reads `DMF_CONSOLE_MXL_ENDPOINTS` (config-driven, not
  NetBox-derived) and the dmf-cms Helm chart exposes neither that nor
  `DMF_CONSOLE_MEDIA_TENANCY`. A dmf-cms **chart-only** PR joins the train:
  value-plumb both env vars; the infra cms role sets tenancy `single` for the
  sandbox profile and points the endpoints at the two per-release Services
  (`http://mxl-videotestsrc.mxl.svc.cluster.local:9000`, `…-view…`). Deriving
  live-view endpoints from NetBox `cluster_*` records is the recorded v0.2
  follow-up (rides the #174 family).
- **Registry flip:** catalog chart image defaults move to the in-cluster Zot
  service-DNS form (`zot.zot.svc.cluster.local:5000/dmf/...`, the catalog-chart
  pattern — containerd `hosts.toml` handles it), while 630 keeps seeding via the
  `registry.<domain>` ingress. `dmf-media/bin/publish-chart-to-ghcr.sh` is
  nmos-hardwired and gets generalized (chart dir + ref args) for the two MXL
  chart publishes.
- **PR train:** dmf-media (chart WP2/3/5 + bumps 0.2.0/0.1.1 + wrapper), then
  dmf-runbooks (launcher + NetBox provision/stamp/clear), then dmf-cms (chart
  env plumbing), then dmf-infra last (node label, mxl RBAC, JT vars, cms-role
  envs, 630 seeds pointing at the *published* chart digests). All base on main
  after the WP1 PRs merge — no stacking (auto-merge trap).

## Amendment C (2026-07-04) — live verify executed; findings and residue

§6 executed on the live single-node env (arm64, `sandbox-single-node`
profile), applied via the dmf-init Manage lane (692-fix → 300 → 630 → 650 →
693) after the operator-approved dmf-cms 0.12.0 deploy. Results:

- **§2 acceptance GREEN:** videotestsrc + view deployed from the console
  catalog, colocated in `single-node` mode over the pod network; initiator
  "Endpoint is now connected" on its pod IP; receiver `Active: true` with the
  head index climbing at grain rate; test-pattern `preview.jpg` served by the
  per-release Service and visible in the Media Workloads live view.
  `mxl-hello` deploy → finalise round-trip clean (AWX jobs successful; NetBox
  record active → back to bootstrapped with all monitoring stamps null; helm
  release + pods gone — teardown leaves NetBox clean).
- **Amendment-B restart check GREEN:** target+initiator restart published a
  new coordinator epoch; the source reconnected; head index climbed again.
- **Monitoring GREEN:** both stamped sidecars discovered by the
  NetBox-driven lane; `probe_success 1`.
- **Live-verify findings, all fixed + merged the same day:**
  1. Forgejo `dmf-infra`/`dmf-media` repos were empty non-mirror stubs (stale
     pre-publish "Move 7" gap) — AWX catalog projects synced an empty tree and
     every infra JT create 400'd (dmf-infra#40).
  2. The status sidecar spoke HTTP/1.0 (`BaseHTTPRequestHandler` default),
     which blackbox `http_2xx` rejects — `probe_success 0` over a healthy
     200 (dmf-media#12 → chart 0.2.1, dmf-runbooks#10, dmf-infra#41).
  3. NetBox rejects `ipam.Service` with `ports: []` — `mxl-hello`'s record
     now carries the conventional status port as intent metadata, no probe
     tag (dmf-runbooks#11, dmf-media#13).
  4. The catalog EE image has no `kubectl` binary — the teardown's
     last-release coordinator-ConfigMap cleanup shelled out to it and died
     between `helm uninstall` and the NetBox finalise, stranding the record
     active with a dead probe target (console teardown, AWX job #164). Fixed
     with `kubernetes.core.k8s` + idempotent uninstall so finalise re-runs
     converge (dmf-runbooks#12).
- **Operational residue (recorded, not code):** waking AWX for API-driven
  work requires patching the AWX CR (the operator reconciles `kubectl scale`
  away) and suspending the awx-autoscale helper for the duration — API calls
  and dependency inventory-syncs don't count as activity and get parked
  mid-run; the console's own wake path fails while the helper is suspended.
  Captured in agent memory + the 693 rerun history on the issue.
- **Capacity note:** with nmos-cpp (registry + 2 mock nodes), nmos-crosspoint,
  the MXL pair AND mxl-hello all running, the single 3-CPU node's request
  budget hit 96% and AWX EE job pods went unschedulable (`Insufficient cpu` →
  inventory-sync worker-stream death → JT "Previous Task Failed"). The full
  demo menu does not fit at once; finalise something first. (v0.2 candidate:
  an EE-schedulability precheck or request-budget alert.)

## 8. References
- `DMF MXL Single-Node Loopback Execution Plan 2026-05-29.md` (historical) — direct
  predecessor: originated the `mxl-hello` chart + catalog entry and the §4
  taint-interaction analysis WP2 builds on; its dedicated-agent-node topology is what
  this plan replaces with same-node placement.
- `../sessions/DMF MXL Cross-Cloud Media-Node Spike — As-Built and Fabrics Result 2026-05-30.md` — as-built + acceptance criteria source.
- `../decisions/architectural-commitments-v1.md` — single-node commitment; multi-node non-goal; "deploys NMOS/MXL from the console" stranger-flow.
- `../decisions/0037-media-workloads-netbox-instance-inventory.md` + `0038-netbox-driven-dynamic-monitoring.md` (Amendments A/B) — the wiring contracts WP5 implements.
- `DMF Console Wording and Media Workloads Page Plan 2026-07-03.md` (#173) — console surface.
- `DMF Are-We-OK Sandbox Observability and Alerting Plan 2026-06-24.md` (#166, Amendment A) — dashboard consumer.
