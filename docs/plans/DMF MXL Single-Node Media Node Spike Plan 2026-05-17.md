---
status: superseded
date: 2026-05-17
superseded_by: "DMF MXL Single-Node Loopback Execution Plan 2026-05-29.md"
---
# DMF MXL Single-Node Media Node Spike Plan (2026-05-17)
> **Superseded by** [DMF MXL Single-Node Loopback Execution Plan 2026-05-29.md](DMF%20MXL%20Single-Node%20Loopback%20Execution%20Plan%202026-05-29.md) — see frontmatter.

> **2026-05-29 execution cross-ref:** This plan's **D1 = option A** scope is
> now being executed. The locked decisions, the live `g2r6-foa9` survey,
> the shared terraform-module change (node-role heterogeneity), agent-join,
> build-first sequencing, and the Stage 1 / Stage 2 split are recorded in
> [DMF MXL Single-Node Loopback Execution Plan (2026-05-29)](./DMF%20MXL%20Single-Node%20Loopback%20Execution%20Plan%202026-05-29.md).
> Read that for *what's being built first*; this remains the canonical
> piece-level breakdown.

> **2026-05-19 cross-ref:** Phase A (D2 — arm64 image push to Zot) and any
> Helm-chart authoring this spike requires should use the **unified
> media-image seeding mechanism** (Stage 4b) and **shared EE image** defined
> in the
> [DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19](./DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md).
> Coordinate timing so MXL and NMOS image seeding share one push path; do
> not invent a parallel seed mechanism for MXL.

**Date:** 2026-05-17
**Repo scope:** `dmf-media` (primary — playbooks, catalog entry, Helm chart),
`dmf-infra` (`roles/modules/media/mxl/`, lifecycle wiring, AWX job templates),
`dmf-env` (manifest extension for the MXL processor node), `dmf-cms` (catalog
card rendering of the new `mxl_flows` field).
**Authoring session:** Claude Opus 4.7, 2026-05-17 with operator, off an
initial evaluation of `github.com/dmf-mxl/mxl` (cloned to umbrella sibling
`mxl/`, gitignored).
**Strategic context:** experiment phase (ADR-0004). Move 1 (Gates 1 + 2)
closed 2026-05-06; the catalog model is in service for `nmos-cpp`. This spike
is the first **MXL-consuming** catalog entry and the first real fill-in for
the Layer 4 stubs (`400-mxl-prereq.yml`, `410-libfabric.yml`,
`499-media-exchange-verify.yml`).
**Estimated effort:** 8–12 working days realistic. Bulk is in the one-time
arm64 build path + new role + chart shape; catalog/AWX/cms work is
incremental on top of the Move 1 pattern.
**Executes:** ADR-0017 (intra-host MXL data plane) end-to-end for the first
time. Closes the §Enforcement bullets of ADR-0017 that name
`400-mxl-prereq.yml`, the catalog v2 `mxl_flows` field, the
`dmf-cluster-access` Layer-4 stanza, and the CI arch-flag gate.

> **Note on scope.** This is **not** "MXL across nodes." ADR-0017 already
> rejected that path until Fabric API ships on aarch64 — cross-node
> media stays on ST 2110 / NDI / SRT bridges. This spike does one
> processor node, one flow domain, one writer/reader graph end-to-end,
> wired through the catalog and dmf-cms exactly the way `nmos-cpp` is.

---

## What this is and isn't

### This IS

A **falsifying spike** that simultaneously tests:

1. ADR-0017's intra-host primitive — tmpfs `emptyDir` + nodeSelector +
   processor-node taint — survives a real graph and feels natural to
   operators clicking Deploy in dmf-cms.
2. The catalog v2 `mxl_flows: { produces, consumes }` schema extension is
   the right shape and dmf-cms can render + validate it.
3. The Layer 4 playbook stubs (`400-mxl-prereq.yml` etc.) fill in cleanly
   under the existing Layer 4xx numbering without restructuring.
4. MXL v1.0 builds on Hetzner ARM64 (Neoverse-N1 / armv8.2-a) without
   nasty SIGILLs and runs containerised under k3s + flannel.
5. The reaper requirement (`mxlGarbageCollectFlows()`) can be expressed
   as a normal k8s CronJob that platform-monitoring can alert on later.
6. The "MXL processor node" abstraction in `dmf-env` extends the
   existing OpenTofu Layer-1 pattern without forking the manifest format.

### This is NOT

- Polished. Single processor node, single catalog entry, single flow
  domain. Errors → "see AWX run #N". No HA. No backups.
- Fabric API / cross-node MXL. Explicitly out per ADR-0017.
- Real broadcast traffic. The graph is GStreamer test-source → MXL
  domain → fake-reader + mxl-info. ST 2110 senders/receivers, NMOS
  registration of the MXL flow, and `nmos-cpp ↔ MXL` adaptation are
  follow-up scope (Move 1.5 / a second MXL catalog entry).
- A migration of `nmos-cpp` onto the processor node. The control plane
  (`nmos-cpp`, NetBox, AWX, dmf-cms, OpenBao, Forgejo) stays on the
  existing 3-node CAX21 control cluster as ADR-0017 §5 specifies.
- Apple Silicon / amd64 fallback profile work. Both are tracked in
  ADR-0017 as deferred shapes; first trial uses the default CAX31 arm64
  path only.

---

## What this falsifies (or confirms)

In priority order, six architectural assumptions inherited from ADR-0017:

1. **MXL v1.0 builds and runs on Hetzner Neoverse-N1.** If
   `-DMXL_TARGET_ARCH=armv8.2-a` doesn't actually produce a working
   binary, or if the futex/tmpfs path SIGILLs under load, Layer 4 needs
   a different hardware shape and the CAX31 default in ADR-0017 §5 is
   wrong.
2. **`emptyDir: medium: Memory` is sufficient for the MXL domain.**
   ADR-0017 forbids non-tmpfs bind mounts; this spike is the first time
   the cluster actually creates one. If pod restarts orphan flows in a
   way the reaper can't clean, the volume shape needs revisiting (likely
   toward a node-level tmpfs + `hostPath` with a privileged init —
   ugly).
3. **The catalog `mxl_flows` field reads naturally and validates.**
   If `{ produces: [<flowId>], consumes: [<flowId>] }` ends up needing
   per-flow type info, rate, or topology hints to be useful, the schema
   reshape happens here, not later.
4. **Co-location-as-architectural-primitive feels right in the UI.**
   ADR-0017 §Decision 2 says nodeSelector is "load-bearing, not a
   performance tweak." If the dmf-cms card has nowhere natural to
   surface "this entry requires processor node X," that's a UX gap to
   close before the second MXL entry lands.
5. **Reaper CronJob is the right shape for `mxlGarbageCollectFlows()`.**
   Alternatives are per-pod sidecar (couples reaper lifecycle to pod
   lifecycle, defeats purpose) or systemd unit on the host (escapes
   k8s). If 1×/min CronJob is too slow / too noisy / inadequate, the
   contract in ADR-0017 changes.
6. **Layer 4xx playbook numbering survives.** The reserved numbers were
   picked before there was anything to put in them. If `400` /`410` /
   `499` end up wanting to be `400` / `420` (no libfabric for v1) or
   need a `405-mxl-build.yml` ahead of prereq, restructure now.

---

## Decision points (need your input before execution)

ADR-0017 fixed the big architectural choices (tmpfs, processor-node role,
arm64 default, reaper required). The five open decisions below are about
execution shape — what to actually build, where, and in what order.

### D1 — First MXL-consuming workload

Three workload options for the very first catalog entry:

| Option | Workload | Pros | Cons |
|---|---|---|---|
| **A. Upstream example pair (gst-testsrc writer + fake-reader + mxl-info)** | The exact graph in `mxl/examples/kube-example.yaml` rebuilt for arm64 | Closest possible match to upstream-validated path; falsifies most for least code; mxl-info readouts double as proof of life | Six pods (writer×2, reader×2, info×2) for "hello world" feels heavy on first deploy |
| **B. Minimal custom writer + reader** | Two tiny C / Rust pods we author against the MXL Flow API | Smallest possible footprint; clearest control of what's tested | Authoring time; first contact with the SDK happens *and* the platform path happens in the same PR — two failure modes confounded |
| **C. cbcrc/mxl-hands-on workshop containers** | The published workshop containers | Zero authoring | ADR-0017 calls these out as amd64-only with no arm64 manifest published; would force the amd64 fallback profile to activate |

**Recommendation: A.** It's the path ADR-0017 implicitly assumed (it
says we rebuild upstream example images for arm64 and push to private
registry, then use them; that's exactly what A is). It also lets the
first runtime test be `mxl-info -l mxl:///dev/shm/mxl/loopback` rather
than something we invented, which makes "did MXL actually work?"
unambiguous.

**Action:** confirm A.

### D2 — MXL arm64 build pipeline shape

ADR-0017 §Enforcement names a "Forgejo CI workflow in `dmf-media` that
adds a build matrix entry asserting `-DMXL_TARGET_ARCH=armv8.2-a` is the
active arch." Two shapes for *first build*, with the CI gate landing
after:

| Option | Where | Pros | Cons |
|---|---|---|---|
| **A. One-shot on the new MXL processor node itself** | SSH to the CAX31 node, run the upstream devcontainer recipe, push images to Zot manually | Fastest to first green image; no CI plumbing to debug in parallel with the build itself | Manual run; not reproducible until CI catches up |
| **B. Forgejo Actions runner on the control cluster, building arm64 natively** | Permanent build path; first artifact comes from the same place every future one will | Reproducible from day one; ADR-0017 enforcement closed in one step | Three new things landing simultaneously (build host, CI workflow, arch-flag gate); each can fail; debug surface large |
| **C. Cross-build from a Mac dev host with Docker buildx / qemu** | Operator's local Mac | No new infra | ADR-0017 explicitly notes qemu-x86_64 user-mode emulation crashed during MXL flow setup in the 2026-05-07 smoke test; arm64-on-amd64 buildx has the same risk class; if it fails late we've wasted time |

**Recommendation: A for first green build, then B as Piece 11 of this
plan.** Get one working arm64 image into Zot the fastest way possible;
make it reproducible after we know the build works. Splits two
unknowns instead of stacking them.

**Action:** confirm A → B sequencing.

### D3 — Processor node provisioning

CAX31 doesn't exist in `dmf-env/manifests/hetzner-arm.yaml` yet. Two shapes:

| Option | Where | Pros | Cons |
|---|---|---|---|
| **A. Extend the existing hetzner-arm manifest with an `mxl-processor` node group** | New entry alongside existing control-plane nodes; one `terraform apply` | Same env, same Tailscale subnet, same Authentik IdP — control plane and processor are one cluster as ADR-0017 §5 specifies | Manifest gains a new node-class concept; first time the manifest schema sees node-role variation |
| **B. New parallel `hetzner-mxl` env** | Separate OpenTofu state, separate inventory | Cleanest isolation if the processor node turns hostile | Two clusters to think about; cross-cluster scheduling = federation work that ADR-0018 already deferred |

**Recommendation: A.** ADR-0017 §5 is explicit: processor nodes join
the existing cluster, distinguished by label + taint. The manifest
schema gaining a node-role field is the right shape for the next
several rounds of growth (more processors, eventually flypack
processors).

**Action:** confirm A. If A, also confirm: one CAX31 node or two?
(Recommend one for the spike per ADR-0017's "one processor node is
sufficient.")

### D4 — Catalog `mxl_flows` schema v2 — shape of the field

ADR-0017 §Decision 4 names the field but does not pin its YAML shape.
Two candidates:

| Option | YAML shape | Pros | Cons |
|---|---|---|---|
| **A. Minimal — list of flow IDs only** | `mxl_flows: { produces: [<uuid>], consumes: [<uuid>] }` | Smallest possible v2 extension; dmf-cms validation is "is uuid"; flow defs come from the launch playbook | Doesn't capture rate / media-type / required tmpfs size at catalog-load time; consistency check between catalog and runtime deferred to drift-detector |
| **B. Rich — per-flow record with type, rate, payload size hint** | `mxl_flows: { produces: [{id, media_type, grain_rate, max_grain_bytes}], consumes: [...] }` | Catalog tells the truth about resource requirements before deploy; dmf-cms can warn pre-deploy on tmpfs sizing | Schema gets ahead of usage; second MXL entry might want a different shape and we've locked in early |

**Recommendation: A for v2 (this spike), with B reserved for v2.1 once
a second MXL-consuming entry forces it.** Matches the "experiment
phase" stance — fields earn their place by being needed.

**Action:** confirm A.

### D5 — Reaper shape

`mxlGarbageCollectFlows()` is a normal C API call; it needs the MXL
domain path and a Linux process to run in.

| Option | Shape | Pros | Cons |
|---|---|---|---|
| **A. Per-node k8s CronJob in the `mxl` role's namespace** | One CronJob per processor node (or one with nodeSelector and tolerations), runs `mxl-info -g` against `/dev/shm/mxl/<domain>` every 1 min | Pure k8s; alertable from Prometheus; survives pod restarts | Cross-cuts the per-flow-domain story if we eventually run multiple domains on one node — needs to know all domains |
| **B. Per-MXL-pod-group sidecar** | Reaper container in the same pod-group as the writer/reader set | Tight lifecycle coupling | Couples reaper presence to specific catalog entries — easy to forget, defeats the "Layer 4 contract" point of ADR-0017 |
| **C. Host-level systemd timer outside k8s** | Installed by `400-mxl-prereq.yml` role | Always present even if no MXL pods are scheduled | Escapes k8s; ops surface for it lives in two places |

**Recommendation: A.** ADR-0017 §Decision 4 framed it as "sidecar or
periodic CronJob" and the operator-monitoring story is much cleaner
with the CronJob. Single domain for v1 means the cross-domain concern
isn't real yet.

**Action:** confirm A.

---

## Concrete work breakdown

Assuming D1=A, D2=A→B, D3=A (one CAX31), D4=A, D5=A.

### Piece 1 — Catalog schema v2: `mxl_flows` field (~1 hr)

**File scope:**
- `docs/architecture/DMF Function Catalog Model.md` — MODIFIED — add v2
  `mxl_flows` section per D4 option A; cite ADR-0017
- `dmf-media/catalog/README.md` — MODIFIED — extend "Required fields"
  table with `mxl_flows.produces` / `mxl_flows.consumes` for any entry
  whose `ebu.layer == 4` consumer
- `dmf-cms/src/dmf_cms/catalog.py` — MODIFIED — accept and pass through
  the new field; reject unknown fields only at log level (no hard fail
  for forward-compat)

**Acceptance:** existing `nmos-cpp.yaml` still loads (no `mxl_flows`,
field is optional). A test fixture with `mxl_flows: { produces:
[<uuid>], consumes: [] }` loads and round-trips through the API.

---

### Piece 2 — `dmf-env` manifest: MXL processor node group (~2-3 hr)

**File scope:**
- `dmf-env/manifests/hetzner-arm.yaml` — MODIFIED — new node group
  entry under existing structure: `dmf.io/role=mxl-processor`,
  taint `dmf.io/mxl=true:NoSchedule`, instance type `cax31`, count 1
- `dmf-env/terraform/...` — MODIFIED — propagate the new node group
  through whatever the existing Layer-1 module shape requires
  (codegen status from EBU-3 means this may be hand-rolled)
- `dmf-env/inventories/hetzner-arm/...` — MODIFIED — new node entry,
  same group conventions as control plane

**Acceptance:** `terraform plan` is clean and shows one new instance,
zero changes to existing. After `terraform apply`, `kubectl get nodes
-l dmf.io/role=mxl-processor` returns the new node Ready. Existing
control-plane workload (NetBox / AWX / dmf-cms / etc.) is unmoved by
scheduler.

**Cost:** one new CAX31 = ~€10/mo. Confirm with operator before apply.

---

### Piece 3 — `roles/modules/media/mxl/` (~4-6 hr)

**File scope (new role under `dmf-infra/k3s-lab-bootstrap/roles/modules/media/mxl/`):**
- `tasks/main.yml` — orchestrator: tag/taint the processor node if not
  already, deploy the reaper CronJob, ensure namespace exists
- `tasks/node-prepare.yml` — label + taint via `kubernetes.core.k8s` —
  idempotent
- `tasks/reaper.yml` — render and apply the CronJob manifest
- `templates/reaper-cronjob.yml.j2` — `*/1 * * * *`, runs the
  `mxl-info` image with `-g` against the mounted domain, tolerates
  the processor-node taint, nodeSelector
- `defaults/main.yml` — domain root (`/dev/shm/mxl`), reaper interval,
  image refs
- `README.md` — what the role does and how it's invoked

**Acceptance:** after running the role, `kubectl get cronjob -n mxl`
shows `mxl-reaper` scheduled; manually triggering it produces a job
that completes successfully even on an empty domain.

---

### Piece 4 — `dmf-media/playbooks/400-mxl-prereq.yml` filled in (~2 hr)

**File scope:**
- `dmf-media/playbooks/400-mxl-prereq.yml` — REPLACE stub — calls into
  `modules/media/mxl/` role; gated to run only when the manifest
  declares any `mxl-processor` nodes
- `dmf-media/playbooks/410-libfabric.yml` — REPLACE stub with a
  documented no-op that prints "Fabric API not consumed in v1 — see
  ADR-0017 §Decision 3" — keeps the layer numbering honest, leaves a
  hook for later
- `dmf-media/playbooks/499-media-exchange-verify.yml` — REPLACE stub —
  runs `mxl-info` (via the reaper image) against the processor node's
  domain and asserts the binary returns successfully on an empty
  domain (proves the SDK at least loads)

**Acceptance:** `bin/run-playbook.sh hetzner-arm
../dmf-media/playbooks/400-mxl-prereq.yml` is green. So is `499`.
`410` is green and prints its no-op rationale.

---

### Piece 5 — One-shot arm64 MXL build (~1-2 days wall, mostly waiting)

**Per D2 option A. Manual on the new CAX31 node.**

**Steps (no tracked files; produces Zot artifacts):**
1. SSH to the processor node as `k3s-admin@<node>`.
2. Install Docker + buildx + clang-18 per upstream `.devcontainer/Dockerfile`.
3. Clone `github.com/dmf-mxl/mxl` at the latest `v1.0.x` tag.
4. Build with `cmake --preset Linux-Clang-Release -DMXL_TARGET_ARCH=armv8.2-a`.
5. Build the example tool images (writer, fake-reader, mxl-info) from
   `mxl/examples/Dockerfile` with the same arch flag.
6. Tag each as `registry.dmf.example.com/dmf/mxl-<tool>:v1.0.x-arm64`.
7. `docker push` to Zot.
8. Verify `crane manifest registry.dmf.example.com/dmf/mxl-info:v1.0.x-arm64`
   shows `linux/arm64`.

**Acceptance:** three images in Zot with arm64 manifests. Run
`mxl-info` directly on the host against a freshly-created tmpfs
domain — clean output, no SIGILL.

**Output to capture for write-up:** build log, wall time, any
deviations from upstream Dockerfile, SHA of the source tag built
against.

---

### Piece 6 — First MXL Helm chart (`dmf-media/charts/mxl-loopback-demo/`) (~half day)

**File scope (new chart):**
- `dmf-media/charts/mxl-loopback-demo/Chart.yaml`
- `dmf-media/charts/mxl-loopback-demo/values.yaml` — image refs (Zot),
  domain path, flow ID (configurable; defaults to upstream example UUIDs)
- `dmf-media/charts/mxl-loopback-demo/templates/_helpers.tpl`
- `templates/deployment-writer.yaml` — gst-testsrc video writer, mounts
  `emptyDir: medium: Memory` at `/home/mxl/domain`, nodeSelector
  `dmf.io/role=mxl-processor`, toleration for taint
- `templates/deployment-reader.yaml` — fake reader, same volume / node
- `templates/deployment-info.yaml` — `mxl-info` polling loop per upstream
  example
- `templates/configmap-flow.yaml` — embeds the upstream video flow JSON
  (1080p29 v210)

**Critical:** all three deployments must share the *same node* (single
`emptyDir`'s scope). Use an emptyDir at the **pod** level and put all
three containers into one Pod (single Deployment, three containers) —
this is the simplest way to guarantee co-tenancy without inter-pod
affinity gymnastics. Reassess as a multi-pod chart in v2 when a
catalog entry has writers / readers from genuinely different lifecycles.

**Acceptance:** `helm install --dry-run` renders a single Deployment
with three containers + one tmpfs `emptyDir`. nodeSelector +
toleration present on the pod spec.

---

### Piece 7 — First MXL catalog entry (~2 hr)

**File scope:**
- `dmf-media/catalog/mxl-loopback-demo.yaml` — NEW — second catalog
  entry, mirrors `nmos-cpp.yaml` shape, populates `mxl_flows.produces`
  with the upstream video flow UUID, declares `ebu.layer: 4` and the
  processor-node placement implicitly via the chart's nodeSelector

**Acceptance:** parses; required fields present; `mxl_flows` validates;
dmf-cms `/api/catalog` lists it alongside `nmos-cpp`.

---

### Piece 8 — Lifecycle wiring + AWX job templates (~2-3 hr)

**File scope (mirrors Move 1 Piece 5–6 pattern):**
- `dmf-infra/k3s-lab-bootstrap/lifecycle-provision.yml` — MODIFIED — add
  Layer 4xx block: imports `400-mxl-prereq.yml`,
  `499-media-exchange-verify.yml`, and the per-entry provision step that
  registers the catalog entry's NetBox `ipam.Service` tagged
  `lifecycle:bootstrapped`
- `dmf-infra/k3s-lab-bootstrap/lifecycle-configure.yml` — MODIFIED — add
  `import_playbook` block tagged `mxl-loopback-demo`
- `dmf-media/playbooks/configure-media/launch-mxl-loopback-demo.yml` —
  NEW — helm install, wait for pod Ready, flip NetBox tag to `:active`,
  return endpoint info via `set_stats`
- `dmf-media/playbooks/configure-media/teardown-mxl-loopback-demo.yml` —
  NEW — symmetric teardown
- `dmf-runbooks/launch-mxl-loopback-demo.yml` — NEW launcher per
  ADR-0014 option B (Move 1 D3)
- `dmf-runbooks/finalise-mxl-loopback-demo.yml` — NEW
- `awx-integration/tasks/main.yml` — MODIFIED — register the two new
  job templates (`media-launch-mxl-loopback-demo`,
  `media-finalise-mxl-loopback-demo`); grant `dmf-cms-svc` Execute

**Acceptance:** Mirrors Move 1: provision creates the NetBox record
without launching; AWX job template runs the launcher; teardown is
symmetric and idempotent.

---

### Piece 9 — dmf-cms catalog card surfacing `mxl_flows` (~2-3 hr)

**File scope:**
- `dmf-cms/src/dmf_cms/templates/...` or React component — MODIFIED —
  when an entry has a non-empty `mxl_flows` block, render a small
  "MXL flows" badge listing produced/consumed flow IDs
- `dmf-cms/src/dmf_cms/catalog.py` — MODIFIED if needed — surface
  `mxl_flows` through whatever the existing card serializer is

**Acceptance:** the new card appears next to `nmos-cpp` with a visible
"produces 1 flow" badge. Deploy and Teardown buttons work end-to-end
exactly the same way `nmos-cpp` does.

---

### Piece 10 — End-to-end verification (~2-3 hr)

**Manual operator flow:**
1. Open dmf-cms `/catalog`. Both entries visible.
2. Click Deploy on `mxl-loopback-demo`. Tag flips to `:active` within 30s.
3. SSH to processor node: `kubectl exec -n mxl deploy/mxl-loopback-demo
   -c info -- mxl-info -l mxl:///home/mxl/domain` — flow visible, head
   index advancing.
4. Wait 5 minutes; confirm reaper CronJob has run 5×, each green, each
   reporting 0 stale flows.
5. Click Teardown. Pod gone, tmpfs emptyDir gone, NetBox tag back to
   `:bootstrapped`.
6. Re-deploy. Re-teardown. Re-deploy. Idempotent each time.
7. Kill the writer container mid-flight (`kubectl exec ... kill -9`),
   wait for k8s to reschedule. Verify the reaper cleans the orphaned
   flow dir before the next writer comes up.

**Acceptance:** all 7 steps green. Any failure → captured in the
write-up (Piece 12) — that's the deliverable.

---

### Piece 11 — Promote build to CI (~half-to-full day)

**Per D2 graduation. Now that we know the build works on the node, make
it reproducible.**

**File scope:**
- `dmf-media/.forgejo/workflows/build-mxl.yml` — NEW — arm64 build
  matrix; runs on a self-hosted arm64 runner (likely the processor
  node, dual-purpose for now) or a Forgejo Actions runner pod; asserts
  `-DMXL_TARGET_ARCH=armv8.2-a` is the active arch in the build log;
  pushes to Zot on tag; fails closed if arch flag missing
- `dmf-infra/...` — MODIFIED — if a Forgejo runner pod needs to land
  on the processor node, the role + manifest stanza for it

**Acceptance:** the workflow runs green on a no-op commit; tagging
`mxl-v1.0.x-build-N` produces a fresh image set in Zot identical to
the manual Piece 5 output.

**Note:** Piece 11 is the closing-out of ADR-0017 §Enforcement bullet
2 ("CI workflow that asserts the arch flag"). Could be deferred to a
follow-up plan if the spike's end-to-end finding (Piece 10) reshapes
something. Recommend keeping it in scope because ADR-0017 names it.

---

### Piece 12 — Write-up + ADR-0017 cross-reference closure (~2-3 hr)

**File scope:**
- `docs/reviews/dmf-mxl-single-node-spike-learnings-2026-05-XX.md` —
  NEW — six Q-and-A sections matching the six falsifications in §"What
  this falsifies", plus a §"Bonus learnings" section. Match Move 1's
  learnings doc structure.
- `docs/architectural-commitments-v1.md` (if it exists yet from
  Move 1 wrap-up) — MODIFIED — add MXL processor-node abstraction
  and `mxl_flows` v2 field to the "survived contact with reality"
  list (or move them to "needs reshape" with the reason).
- `docs/decisions/0017-mxl-intra-host-data-plane.md` — MODIFIED if
  warranted — append a "Spike outcome (2026-05-XX)" note recording
  which §Enforcement bullets are now closed and which deviated.
- Update `dmf-cluster-access` skill with the §Layer-4 stanza that
  ADR-0017 §Enforcement bullet 4 promised (tmpfs volume contract,
  reaper requirement, where to look when a flow won't start).

**Acceptance:** doc captures schema decisions, build surprises, the
co-location UX read in dmf-cms, reaper interval suitability, anything
broken. ADR-0017 enforcement bullets either checked off or annotated
with the deviation.

---

## How to execute this — three options

Same pattern Move 1 used; carry it forward.

### Option A — Codex autonomous, with human checkpoints

Hand pieces to codex with STOP gates after each Piece. Codex builds;
operator reviews diff.

**Pros:** Fastest for Pieces 1, 2, 3, 4, 7, 8.
**Cons:** Pieces 5 (manual ARM build), 6 (chart taste), 10 (manual
verify) require humans. Piece 11 CI is taste-heavy.

### Option B — Claude with operator, single session

Sequential. Decisions inline. Eats session context fast for a 12-day
spike.

### Option C — Mixed: codex on mechanical, Claude/operator on taste

**Recommended.** Same as Move 1.

**Sequencing under Option C:**
1. Codex: Piece 1 (catalog schema)
2. Operator (with Claude review): Piece 2 (`dmf-env` manifest + terraform apply)
3. Codex: Piece 3 (mxl role)
4. Codex: Piece 4 (Layer 4 stubs filled)
5. **Manual run:** `lifecycle-provision` runs Pieces 3+4; verify CronJob alive, role idempotent
6. Operator + Claude: Piece 5 (one-shot arm64 build) — eats wall clock; can run in background while Pieces 6+7 land
7. Claude+operator: Piece 6 (chart — taste call on single-deployment-three-containers shape)
8. Codex: Piece 7 (catalog entry)
9. Codex: Piece 8 (lifecycle wiring + AWX)
10. **Manual run:** AWX launch; verify pod up
11. Claude+operator: Piece 9 (cms card)
12. **Manual:** Piece 10 (end-to-end verify) — this *is* the spike
13. Codex: Piece 11 (CI build workflow) — defer if Piece 10 surfaces a reshape
14. Claude+operator: Piece 12 (write-up + ADR-0017 closure)

---

## Acceptance — falsification or confirmation

This spike is "complete" (gate-closed) when **all** of these are true:

- [ ] MXL v1.0.x arm64 images (`mxl-info`, `mxl-gst-testsrc`,
      `mxl-gst-fake-reader`) are in Zot, manifest declares `linux/arm64`
- [ ] One CAX31 node is in the cluster, labeled `dmf.io/role=mxl-processor`,
      tainted `dmf.io/mxl=true:NoSchedule`, control-plane pods unmoved
- [ ] `400-mxl-prereq.yml` / `499-media-exchange-verify.yml` are real
      playbooks that pass under `bin/run-playbook.sh hetzner-arm`
- [ ] `mxl-reaper` CronJob is scheduled, runs every minute, green
- [ ] Catalog has a second entry (`mxl-loopback-demo`); both list in
      dmf-cms `/catalog`
- [ ] Deploy from dmf-cms launches the writer+reader+info pod-group on
      the processor node; `mxl-info -l` against the domain shows the
      flow with advancing head index
- [ ] Teardown is clean; tmpfs is reclaimed; NetBox tag flips back
- [ ] Reaper detects + cleans an orphaned flow (manual writer kill)
      within one reaper interval
- [ ] Catalog v2 `mxl_flows` field is documented, validated, rendered
      in dmf-cms
- [ ] CI build workflow exists in `dmf-media` and produces an artifact
      identical to the manual Piece 5 output (Piece 11; may be deferred
      if Piece 10 reshapes)
- [ ] **Write-up captures what was learned** — the actual deliverable
      per ADR-0004
- [ ] ADR-0017 §Enforcement bullets either marked complete or
      annotated with the deviation

If **any** breaks in a way that requires reshaping ADR-0017 or the
catalog model, that breakage IS the deliverable. Per ADR-0004.

---

## Out of scope (do NOT include in this spike)

- Fabric API / multi-node MXL. Out per ADR-0017 §Decision 3.
- Second processor node. ADR-0017 says one is enough for the
  experiment; HA by duplication waits.
- `nmos-cpp ↔ MXL` adapter (catalog entry that registers the MXL
  flow with NMOS). Real feature; deserves its own plan.
- Real ST 2110 senders/receivers feeding into MXL. Deferred.
- amd64 fallback (CCX13) profile. Tracked in ADR-0017 §5; activate
  only on a real blocker.
- Apple Silicon / Asahi profile. Tracked; not blocking.
- Multi-domain MXL on one processor node. The reaper design (D5 A)
  is single-domain; revisit when a second domain is needed.
- Polished error UX on the MXL catalog card. "Failed: see AWX run #N"
  is enough. Per Move 1's pattern.
- Backups, alerts, monitoring beyond reaper-cronjob success metric.
  Per ADR-0004 (experiment phase).
- Migration of any existing Layer 5 work onto the processor node.
  Control plane stays where it is.

---

## Dependencies on prior work (must be in place)

- ✅ Move 1 closed (Gates 1 + 2 per STATUS.md): catalog model live,
  AWX job-template pattern proven, dmf-cms catalog page exists
- ✅ ADR-0017 accepted (the strategic decision this plan executes)
- ✅ Catalog schema documented in `dmf-media/catalog/README.md`
- ✅ Zot registry running and accessible
- ✅ Forgejo + AWX integrated per Move 2
- ✅ `dmf-env/manifests/hetzner-arm.yaml` exists with the existing
  control-plane node group as a template for adding a new group
- ✅ The umbrella's `mxl/` evaluation clone (2026-05-17, gitignored)
  for offline reference to the SDK headers and example manifests

Not strictly blocking but worth knowing:
- The `dmf-cluster-access` skill does not yet have a Layer-4 stanza;
  this spike adds it (Piece 12).

---

## What to commit (suggested commit shape)

Twelve commits, one per Piece:

1. `feat(catalog): v2 schema — add mxl_flows field (ADR-0017)` (umbrella + dmf-media + dmf-cms)
2. `feat(env): hetzner-arm — add mxl-processor node group (ADR-0017 §5)` (dmf-env)
3. `feat(infra): roles/modules/media/mxl — taint + reaper CronJob` (dmf-infra)
4. `feat(media): fill Layer 4 prereq + verify playbooks (ADR-0017 §Enforcement)` (dmf-media)
5. `chore(mxl): record arm64 build artifacts in Zot (one-shot)` (no code; commits the build notes to `docs/sessions/`)
6. `feat(charts): first MXL chart — mxl-loopback-demo` (dmf-media)
7. `feat(catalog): mxl-loopback-demo catalog entry` (dmf-media)
8. `feat(lifecycle+awx): wire mxl-loopback-demo through provision/configure + JTs` (dmf-infra + dmf-runbooks)
9. `feat(dmf-cms): render mxl_flows on catalog cards` (dmf-cms)
10. *(no commit — manual verification run)*
11. `feat(ci): dmf-media — arm64 MXL build workflow with arch-flag gate` (dmf-media)
12. `docs(reviews): MXL single-node spike learnings + ADR-0017 closure` (umbrella)

Each commit independently testable.

---

## Cross-reference

- ADR-0017 (the strategic decision this plan executes):
  `docs/decisions/0017-mxl-intra-host-data-plane.md`
- ADR-0013 (catalog model — the v2 extension target):
  `docs/decisions/0013-media-function-catalog-model.md`
- ADR-0014 (AWX project layout — pattern reused for launcher/JT):
  `docs/decisions/0014-awx-project-layout.md`
- Move 1 task (template for this plan + pattern for catalog/AWX/cms):
  `docs/plans/dmf-platform-move-1-task-2026-05-04.md`
- Move 1 Gate 2 pivot (Path A precedent for the launcher pattern):
  `docs/plans/Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md`
- EBU mapping (Layer 4 numbering and vocabulary):
  `docs/architecture/DMF EBU Mapping (2026-04-25).md`
- Catalog architecture (schema doc):
  `docs/architecture/DMF Function Catalog Model.md`
- Upstream: `github.com/dmf-mxl/mxl` (Apache-2.0, v1.0.x), local
  evaluation clone at umbrella sibling `mxl/`
- Upstream architecture doc: `mxl/docs/Architecture.md` (notes on
  tmpfs / futex / advisory-lock / reaper)
- Upstream k8s example: `mxl/examples/kube-example.yaml` (the
  pattern Piece 6 chart adapts, *minus* the privileged-init tmpfs
  mount which ADR-0017 has us replace with `emptyDir: medium: Memory`)

---

## Single-line goal

**Stand up one CAX31 MXL processor node + one MXL-consuming catalog
entry (`mxl-loopback-demo`) deployed from dmf-cms exactly the way
`nmos-cpp` is. Prove ADR-0017's intra-host primitive (tmpfs +
nodeSelector + reaper CronJob) works under a real graph. Capture
what broke. That closes ADR-0017's §Enforcement gate.**
