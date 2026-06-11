---
status: historical
date: 2026-05-29
---
# DMF MXL Single-Node Loopback Execution Plan (2026-05-29)
> Supersedes: [DMF MXL Single-Node Media Node Spike Plan 2026-05-17.md](DMF%20MXL%20Single-Node%20Media%20Node%20Spike%20Plan%202026-05-17.md)

> **Companion to** [DMF MXL Single-Node Media Node Spike Plan (2026-05-17)](./DMF%20MXL%20Single-Node%20Media%20Node%20Spike%20Plan%202026-05-17.md).
> That plan is the canonical 12-piece work breakdown and the falsification
> charter. **This plan does not replace it.** It records the decisions
> locked on 2026-05-29, the live-cluster survey that drove them, and the
> deltas that the 2026-05-17 plan did not yet know (target env, the shared
> terraform-module change, agent-join, build-first sequencing, the
> Stage 1 / Stage 2 split). Read the 2026-05-17 plan for the piece-level
> detail; read this for *what we actually decided to build first and why*.

**Date:** 2026-05-29
**Authoring session:** Claude Opus 4.8 with operator.
**Executes:** [ADR-0017](../decisions/0017-mxl-intra-host-data-plane.md)
§Enforcement, scope = the 2026-05-17 plan's **D1 = option A** (single video
loopback demo), nothing wider.
**Target env:** the **live `g2r6-foa9` Hetzner cloud cluster** (cluster domain `dmf.example.com` in public prose),
*not* the sandbox lane. (`zy9q-1015` in STATUS.md is a local sandbox env —
a different lane; do not confuse the two.)

---

## 1. Locked decisions (2026-05-29)

| # | Decision | Value |
|---|---|---|
| Scope | First-cut sample-function scope | **Minimal loopback only** (2026-05-17 D1=A): `gst-testsrc → tmpfs domain → fake-reader + mxl-info`. Proves the *plumbing*, registers nothing in NMOS. |
| Crosspoint | `nmos_crosspoint` routing UI | **Out of scope.** It routes registered NMOS senders; the minimal demo registers none. Sequenced after the future `nmos-cpp ↔ MXL` adapter. See §6. |
| Processor node | How to obtain it | **Add a 4th node — never repurpose** an existing g2r6-foa9 node. See survey §2. |
| Node shape | Instance type | **Hetzner CAX31** (8 vCPU / 16 GB / armv8.2-a, ~€10/mo). 16 GB for tmpfs headroom per ADR-0017 §5. |
| Node role | etcd member or worker? | **Agent (worker), not an etcd server.** Keeps etcd at 3 (odd, healthy); isolates MXL faults from the control plane. |
| Node labels/taint | Placement contract | `dmf.io/role=mxl-processor` + taint `dmf.io/mxl=true:NoSchedule` (ADR-0017 §5). |
| Build pin | MXL source tag | **`v1.0.1`** (latest release). The local `mxl/` clone sits on the `IBC2025-demos-01` demo branch — reference only. Build fresh at `v1.0.1` with `-DMXL_TARGET_ARCH=armv8.2-a`, fail-closed if the arch flag is absent. |
| Reaper | `mxlGarbageCollectFlows()` shape | **Per-node k8s CronJob** (2026-05-17 D5=A). |
| `mxl_flows` schema | Catalog v2 field shape | **Minimal — list of flow IDs** (2026-05-17 D4=A). |
| Staging | Branch granularity | **Stage 1 first** (node + demo via playbook), **Stage 2 deferred** (dmf-cms card + AWX). See §5. |

---

## 2. Live-cluster survey (g2r6-foa9, 2026-05-29) — why we add, not repurpose

Read-only survey via SSH to the control node (`k3s-admin@<control-node-public-ip>`,
node-01), using the node's own kubeconfig. No secrets touched.

**Topology — it is a genuine 3-member HA etcd cluster:**

```
NAME                ROLES                       VERSION        TYPE
g2r6-foa9-node-01   control-plane,etcd,master   v1.30.6+k3s1   CAX21
g2r6-foa9-node-02   control-plane,etcd,master   v1.30.6+k3s1   CAX21
g2r6-foa9-node-03   control-plane,etcd,master   v1.30.6+k3s1   CAX21
```

The inventory's `[k3s_control] = node-01` was a red herring (ansible
bootstrap node only); the manifest's `ha: true` was the truth.

**RAM pressure — no node to spare:**

```
node-01   6350Mi / 7.75Gi   81%      (kubectl top, live)
node-02   5736Mi / 7.75Gi   74%
node-03   5977Mi / 7.75Gi   77%   (busiest: 69 pods, CPU limits 91%)
```

**Two independent blockers to repurposing a node:**

1. **etcd 3 → 2** is the worst move — quorum stays 2 (zero fault
   tolerance), and the removal transits a fragile state.
2. **No RAM headroom** — the ~6 GiB of platform workload on a removed
   node cannot fit onto two nodes already at 74–81 %. That's
   OOM/eviction territory, *before* the MXL tmpfs domain asks for RAM.

Either alone is disqualifying. **Verdict: add one CAX31 agent (node-04).**
etcd HA stays 3, the live platform is untouched, MXL gets 16 GB and clean
failure isolation.

---

## 3. The shared-module change (highest-risk plumbing)

`dmf-env/terraform/modules/hetzner/cluster` is **homogeneous**:

```
node_names  = var.spec.topology.control_plane.members   # nodes only from control_plane.members
server_type = local.cloud.server_type                   # one type for all
for_each    = toset(local.node_names)                   # every node identical; no agents, taints, or groups
```

Adding a tainted CAX31 agent therefore requires **extending this shared
module** (used by *every* Hetzner env), not just editing the manifest.

**Hard constraints:**

- **Backward-compatible / additive only.** Existing manifests with no node
  group must render byte-identical.
- **Acceptance gate:** `bin/tf-apply.sh plan` shows **exactly +1 node and
  zero changes to the existing three**, and zero diff for other Hetzner
  envs. This is falsification #6 (manifest/module gaining node-role
  variation) — treat the zero-diff plan as the proof.
- **Paired dmf-infra bootstrap change:** node-04 joins k3s **as an agent**,
  a join shape the bootstrap currently never performs (all nodes are
  servers today).
- Manifest extension (`manifests/g2r6-foa9.yaml`): a new optional node
  group declaring `server_type: cax31`, `count: 1`, role `agent`, label
  `dmf.io/role=mxl-processor`, taint `dmf.io/mxl=true:NoSchedule`.

---

## 4. Taint / DaemonSet / load-balancer interactions

node-04 carries `dmf.io/mxl=true:NoSchedule`. Decide per workload:

| Workload | On node-04? | Action |
|---|---|---|
| node-exporter, promtail | **Yes** — processor must be observable | add explicit toleration |
| Longhorn | **No** — MXL is tmpfs, no PVCs here | leave untolerated |
| flannel/CNI, kube-proxy, hcloud CCM | Yes (auto) | already tolerate-all |
| Hetzner LB `g2r6-foa9-traefik` target pool | **No** | node-04 runs no Traefik; verify the CCM target selector **excludes** the tainted node or LB traffic routed there black-holes |

---

## 5. Execution staging + sequencing

### Build-first ordering (corrects the 2026-05-17 piece numbering)

The reaper CronJob, `499-media-exchange-verify`, and the demo chart all
pull an `mxl-*` arm64 image. None can run until the images exist in Zot.
**Therefore the real order is:**

```
Piece 2 (provision node-04)  →  Piece 5 (build v1.0.1 arm64 images on node-04, push to Zot)
                             →  Piece 3 (mxl role + reaper)  →  Piece 6/7 (chart + catalog)
```

### Stage 1 — node + demo via playbook (this branch set)

Blast radius = node-04 only (isolated tainted agent). Closes most of
ADR-0017 §Enforcement.

- **dmf-env** — module heterogeneity (§3) + `g2r6-foa9.yaml` node group +
  rendered inventory; `tofu apply` adds node-04.
- **dmf-infra** — agent-join; `roles/modules/media/mxl/` (taint/label +
  reaper CronJob).
- **dmf-media** — fill `400-mxl-prereq.yml` / `410-libfabric.yml` (no-op) /
  `499-media-exchange-verify.yml`; `charts/mxl-hello/` (single Deployment,
  three containers, one tmpfs `emptyDir`); catalog entry `mxl-hello.yaml`
  with minimal `mxl_flows`.

> **Naming:** the entry is `mxl-hello` (or `mxl-demo-flow`), **not**
> `mxl-loopback` — the demo generates a flow and proves the ring round-trips
> through tmpfs; it does **not** read-and-republish. A true loopback
> function is custom code, deliberately out of this scope.

**Stage 1 acceptance:** `bin/run-playbook.sh g2r6-foa9 …` stands up node-04
and the demo pod-group; `mxl-info -l` shows the flow with an advancing head
index; the reaper CronJob runs green every minute. Existing control-plane
workload unmoved.

### Stage 2 — the Deploy button (deferred to a follow-on branch)

Only after Stage 1 is green. Touches control-plane components, so it waits:
`dmf-cms` catalog card rendering `mxl_flows` + AWX job templates +
lifecycle wiring (2026-05-17 Pieces 8–9). On a cluster already at 74–81 %
RAM, a wiring mistake here must not be able to perturb the platform until
the data-plane half is proven.

---

## 6. Crosspoint — why it is out of scope (recorded so it is not re-litigated)

`3dmedium/nmos_crosspoint` is a Layer-5 NMOS IS-04/05 routing matrix. It
displays and connects **registered NMOS senders/receivers**. The minimal
loopback is pure intra-host tmpfs and (per ADR-0017 §1) **registers nothing
in NMOS** — MXL writes an IS-04-shaped `flow_def.json` but does not register
it. Crosspoint would show an empty matrix beside a running demo.

The bridge is the future **`nmos-cpp ↔ MXL` adapter** (ADR-0017 §1,
2026-05-17 plan §Out-of-scope). Coherent sequence:

```
(1) MXL hello-world   ← this plan. Registers nothing.
(2) nmos-cpp ↔ MXL adapter   ← registers the MXL flow as an NMOS IS-04 sender.
(3) crosspoint UI    ← now has a sender to route. The payoff.
```

Crosspoint can also stand alone on the existing `nmos-cpp` catalog entry as
a pure-NMOS routing demo, independent of MXL, whenever wanted — it just must
not be coupled to this spike.

---

## 7. Branch set

Stage-1 feature branches, all named `feat/mxl-single-node-spike`, created
2026-05-29 off `main`:

- `dmf-env` — module + manifest + inventory + `tofu apply`
- `dmf-infra` — agent-join + mxl role
- `dmf-media` — chart + catalog entry + Layer-4 playbooks

Plan docs (this file + any amendments) land on the umbrella `main` per
convention. `dmf-cms` is **not** branched yet (Stage 2).

---

## 8. Local rehearsal (2026-05-29) — capacity-driven interim

**Why.** On 2026-05-29 Hetzner ARM (CAX) capacity was exhausted across all
three eu-central DCs (nbg1, fsn1, hel1) for **both** cax21 and cax31 — §2's
processor node could not be placed. The dmf-env terraform (§3) is committed
on the branch and **plan-clean** (`3 to add, 0 to change, 0 to destroy`); it
is blocked **only** on stock, not code. To keep the spike's software pieces
moving, the MXL stack was rehearsed on a **local single-node k3s** on an
arm64 Lima Debian-12 VM (Apple M1 host, `<lan-ip>`).

**What it proves (and what it does not):**

- ✅ MXL **v1.0.1 builds and runs** on arm64 Linux under k3s.
- ✅ **Falsification #2 — `emptyDir: medium: Memory` is sufficient.** The
  grain ring round-trips through RAM-backed tmpfs cleanly. Bonus: the volume
  is world-writable, so the image's uid-1000 user writes the domain
  **without** `fsGroup` — `fsGroup: 1000` is optional hygiene, not required.
- ✅ The **single-pod / multi-container co-tenancy** shape (the Piece-6 chart
  design) works — writer + reader + info share one domain volume.
- ✅ **Running persistently:** the video **and** audio flows — `gst-testsrc`
  generator + `fake-reader` + `mxl-info` each (6 containers across 2
  deployments, both verified Active with advancing head index). Separately,
  **`mxl-gst-sink` was exercised once** via an ephemeral `kubectl exec`
  against the live video flow: it read grains and reported latency
  (`autovideosink` falls back gracefully headless; no visual output without a
  display), confirming the reader/preview path — but it is **not** left
  running as part of the demo. **Not exercised:** `mxl-gst-looping-filesrc`
  (needs an input media file — a separate demo).
- ✅ **Falsification #5 — the reaper works from a stock image.** `mxl-info -g`
  (`--garbage-collect`) is the GC CLI; source (`lib/internal/.../Instance.cpp`)
  shows it `flock(LOCK_EX|LOCK_NB)`s each `*.mxl-flow` dir and `remove_all`s
  only those whose **writer lock is free**. A `*/1` CronJob reaped a planted
  orphan within one interval (~30 s); and `-g` run against the **live** domain
  left the active (locked) flow untouched (verified — flow stayed Active,
  head index advancing). **No custom binary needed** — closes ADR-0017's
  reaper-shape question. **But D5=A (a *separate* CronJob) is incompatible with
  the emptyDir model:** a pod-scoped `emptyDir:Memory` cannot be reached by a
  separate pod, so the reaper must be an **in-pod sidecar** — now folded into
  the `mxl-hello` chart (`dmf-media@d0eb1cc`, optional via `values.reaper`). A
  per-node CronJob would only work against a node-level *persistent* domain (the
  hostPath model ADR-0017 rejected). So ADR-0017's "emptyDir **and** CronJob
  reaper" pairing is internally inconsistent — **emptyDir ⇒ sidecar**. Its scope
  narrows too: a full pod restart wipes the ephemeral domain, so the sidecar
  only matters for a container-restart within a surviving pod. See §9/§10.
- ❌ **Does NOT prove falsification #1** (the Hetzner Neoverse-N1 `armv8.2-a`
  build). The M1 build uses MXL's auto-selected `-march` (~armv8.5-a). That
  confirm still waits for Hetzner capacity; the committed terraform is ready.

**Build/packaging learnings (feed the Hetzner build + the `dmf-media` chart):**

- The upstream `examples/Dockerfile` hardcodes the **x86_64** multiarch path
  in its `libmxl*` `COPY`; on arm64 it must be `aarch64-linux-gnu`. This will
  also bite the Hetzner arm64 build — pre-patch it.
- **v1.0.1 tool inventory:** `mxl-info`, `mxl-gst-testsrc`, `mxl-gst-sink`,
  `mxl-gst-looping-filesrc`. **No `mxl-data-probe`** (that exists only on the
  `IBC2025-demos` branch, which is what the local `mxl/` eval clone is on — do
  not assume it in v1.0.1). Only `mxl-info` / `mxl-gst-testsrc` /
  `mxl-fake-reader` have dedicated example-image stages; but the `mxl` base
  stage `COPY`s all `/usr/bin/mxl-*`, so `mxl-gst-sink` /
  `mxl-gst-looping-filesrc` are present as binaries in any image and run via
  `exec` rather than a dedicated image.
- `fake-reader` is a shell script (`examples/scripts/fake-reader.sh`), not a
  `mxl-*` binary.
- Chart shape that worked: `emptyDir: medium: Memory` at the domain path;
  `workingDir: /home/mxl`; flow def via ConfigMap at `config/flow.json`;
  writer `-v` (video) / `-a` (audio); reader `--video-flow-id` /
  `--audio-flow-id`; info loops `mxl-info mxl:///<domain>?id=<flow-id>`.

Images were built + imported into the VM's k3s containerd (no registry). GHCR
push (`ghcr.io/dmfdeploy/mxl-*`) is deferred — it needs an operator PAT, and
the M1-arch images are not Hetzner-reusable anyway (arch mismatch).

---

## 9. Stage 2 design — catalog exposure + dmf-cms

**Catalog (Pieces 1/6/7).** Deployable entry vs. console capability:

- **Deployable entries:** MXL test-flow **generators** (video, audio) — each
  *produces* a flow → `mxl_flows.produces: [<id>]`; plus the bundled
  hello/demo entry. `ebu.layer: 4`. Each carries the processor-node placement
  contract (`nodeSelector: dmf.io/role=mxl-processor` + toleration) so the
  catalog knows it requires a processor node.
- **Not standalone cards:** the inspectors (`mxl-info`, `mxl-gst-sink`) are
  diagnostics run *against* a flow, not long-lived workloads — surface them as
  a **console flow-status capability** (below), not catalog entries.
  (`mxl-data-probe` is N/A in v1.0.1.)

**dmf-cms (Piece 9).**

- **Catalog card:** `mxl_flows` badge (produces/consumes flow IDs) +
  processor-node placement indicator + Deploy/Teardown (ADR-0025 Lane B: AWX
  job template → in-cluster Helm), exactly like `nmos-cpp`.
- **Live flow-status view — the Layer-4-made-visible payoff.** Render the
  `mxl-info` data: **Active**, **head index advancing**, format/rate,
  **latency (grains/ms)**. Show the producer→consumer graph and, critically
  for intra-host MXL, **co-location on the processor node** — surface a broken
  graph when a pod-group lands across hosts (ADR-0017 §5).
- **Optional live preview (stretch, not Stage-2-blocking):** a downscaled
  **MJPEG video preview** and an **audio level meter**, generated by a
  GStreamer reader **on the processor node** (`mxl-gst-sink` lineage). Only the
  compressed preview crosses the network; the raw v210 (~1.5 Gbit/s) and
  float32 audio **never leave the node's tmpfs**. GStreamer `level` →
  peak/RMS per channel over SSE/WebSocket for the meter.
- **Eventual NMOS seam:** once the `nmos-cpp ↔ MXL` adapter registers flows
  (§6), the same flow view can pull from the NMOS registry and feed crosspoint.

---

## 10. Status & resume (2026-05-30)

### Progress

- ✅ **Pieces 6/7 — `mxl-hello` chart + catalog v2 entry.** Authored, `helm
  lint` clean, locally validated end-to-end on the M1 k3s; committed
  (`dmf-media@afe167f`) and **pushed** to the LAN Forgejo on
  `feat/mxl-single-node-spike`.
- ✅ **§3 terraform — agent node-group + DC override.** Committed
  (`dmf-env@3ef2594`), pushed; `tofu plan` clean (`+1 node, 0 change, 0
  destroy`). `apply` blocked **only** on Hetzner ARM stock (§8).
- ✅ **Local rehearsal (§8).** Video + audio MXL flows, `mxl-gst-sink`
  reader, and the reaper (`mxl-info -g`) all validated on the local Lima
  arm64 VM.
- ✅ **Plan doc** — this file, on umbrella `main`. The **`dmf-infra`** feat
  branch was created but carries **no MXL work** (0 commits ahead of
  `origin/main`) — **not pushed**.

### Falsifications scorecard

| # | Claim | State |
|---|---|---|
| 2 | `emptyDir: medium: Memory` sufficient | ✅ confirmed (world-writable; `fsGroup` optional) |
| 5 | Reaper CronJob shape | ✅ confirmed (stock `mxl-info -g`, flock-safe: reaps orphans, spares live) |
| 6 | Manifest gains node-role | ✅ terraform half (plan-clean); Layer-4xx playbook numbering unexercised |
| 1 | Hetzner Neoverse-N1 `armv8.2-a` build | ⏳ capacity-blocked |
| 3 / 4 | Catalog reads naturally / co-location legible in UI | ⏳ need dmf-cms (Stage 2) |

### Resolved: reaper placement

**Folded as an in-pod sidecar** in the `mxl-hello` chart (`dmf-media@d0eb1cc`,
optional via `values.reaper`, default on). A *separate* CronJob is **not**
viable with the pod-scoped `emptyDir:Memory` domain (§8) — emptyDir ⇒ sidecar.
A per-node `dmf-infra` mxl-role reaper remains an option *only* if a future
entry uses a node-level **persistent** domain; revisit at multi-domain.

### Remaining work, by where it can run

- **Local-doable (mostly done):** reaper folded into the chart as a sidecar
  (`d0eb1cc`) — `helm lint` + render + gating verified; the **in-chart live
  deploy is unconfirmed** (local VM stopped mid-rollout) — re-run on next VM
  bring-up.
- **Needs AWX:** launch/teardown playbooks + AWX job templates (Piece 8,
  ADR-0025 Lane B).
- **Needs dmf-cms:** the flow-status / co-location view (§9; falsifications
  #3/#4).
- **Needs the Hetzner node:** falsification #1 (`armv8.2-a` build) + the full
  Stage-1 playbook run.

### How to resume

- **Feature work** lives in a git worktree set at
  `~/repos/dmf-mxl-spike/{dmf-env,dmf-infra,dmf-media}` (branch
  `feat/mxl-single-node-spike`); the canonical umbrella siblings stay on
  `main`. Export `DMFDEPLOY_UMBRELLA` to the umbrella path when running
  tooling from the worktree (preserves the `../dmf-infra` sibling layout).
- **Local rehearsal — VM STOPPED 2026-05-30** (operator freed RAM for another
  VM; restart the Lima VM to resume): single-node k3s on the arm64 Lima VM
  (`<lan-ip>`); demos `mxl-hello` (video) + `mxl-hello-audio` in namespace
  `mxl`; images `ghcr.io/dmfdeploy/mxl-*:v1.0.1-dev` side-loaded into containerd
  (no registry). On restart, a leftover test ns `mxl-reaper-chart` may resurface
  — delete it; and re-run the in-chart reaper deploy to confirm `d0eb1cc`.
- **Hetzner node (closes #1):** when ARM capacity returns, from the dmf-env
  worktree run `bin/tf-apply.sh g2r6-foa9 plan -var
  publish_lb_dns_records=true -out=<plan>` then `apply` — sweep
  `server_type` (cax21/cax31) × `location` (nbg1/fsn1/hel1) via the
  manifest's `node_groups` entry until one DC has stock. **Never commit the
  saved `-out` plan file — it embeds the cloud token.**

---

## 11. Cross-reference

- [ADR-0017](../decisions/0017-mxl-intra-host-data-plane.md) — the decision this executes
- [DMF MXL Single-Node Media Node Spike Plan (2026-05-17)](./DMF%20MXL%20Single-Node%20Media%20Node%20Spike%20Plan%202026-05-17.md) — canonical 12-piece breakdown
- [DMF NMOS Registry + Crosspoint Demo Plan (2026-05-04)](./DMF%20NMOS%20Registry%20+%20Crosspoint%20Demo%20Plan%202026-05-04.md) — crosspoint's home (Phase 2)
- ADR-0013 (catalog model — the `mxl_flows` v2 target)
- Upstream: `github.com/dmf-mxl/mxl` @ `v1.0.1`; local eval clone at umbrella sibling `mxl/`
- `dmf-cluster-access` skill — the read-only survey path used in §2
</content>
