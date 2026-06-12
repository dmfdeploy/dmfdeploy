# ADR-0017: MXL is an intra-host data plane; multi-node media graphs use ST 2110/NDI/SRT bridges

**Status:** Accepted
**Date:** 2026-05-07
**Deciders:** @<handle>, planning session with Claude (smoke test 2026-05-07)

## Context

ADR-0003 adopted EBU DMF V2.0's six-layer model. Layer 4 (Media Exchange)
sits between the Container Platform (Layer 3) and Media Functions (Layer 5),
and the white paper names a single reference implementation: the Media
eXchange Layer (MXL) SDK at `github.com/dmf-mxl/mxl`. Until now, our
`dmf-media/playbooks/400-mxl-prereq.yml` has been an empty skeleton
and Layer 4 has been hand-waved.

MXL hit v1.0.0 in February 2026. It's Apache-2.0, hosted under LF Projects/LLC,
governed by EBU + NABA with a TSC drawing from BBC, EBU, CBC/Radio-Canada,
Grass Valley, AWS, NVIDIA, Lawo, and Riedel. Same NVIDIA TSC member
(Gareth Sylvester-Bradley) maintains nmos-cpp upstream, so the NMOS/MXL
boundary is being drawn by people who know both sides.

A read of `docs/Architecture.md` plus a smoke-test build attempt
(2026-05-07) surfaced facts that bind our Layer 4 plan in concrete ways:

- Today's data plane is **mmap'd files in tmpfs** synchronised via futexes —
  not RDMA, not libfabric, not sockets. Two MXL functions communicate by
  ring-buffering grains through `${mxlDomain}/${flowId}.mxl-flow/data` and
  `grains/${index}` on a shared host filesystem.
- The **Fabric API** for cross-host transport (RDMA/EFA) is roadmap, not
  v1.0. `libfabric 2.2.0` is staged in the build dependency tree but no
  cross-host code path is exposed.
- MXL's CMake auto-selects `-march=armv8.5-a` on ARM. CAX21 is Ampere
  Altra / Neoverse-N1 = **armv8.2-a**. The flag check downgrades silently —
  a wrong build SIGILLs at runtime, not at link.
- Workshop containers (`ghcr.io/cbcrc/mxl-writer`, `mxl-reader`) ship
  amd64-only. There is no published arm64 manifest.
- `/domain` must be tmpfs. Bind-mounting it from a non-tmpfs filesystem
  produces zero output and no error log — the futex/mmap path needs
  RAM-backed memory.
- FlowWriter holds an advisory file lock until close; crashed writers
  leave stale flow directories that need `mxlGarbageCollectFlows()`.

The decision the platform now needs is not *whether* to use MXL — the
EBU TSC has done that work. It's how MXL's intra-host-only constraint
shapes our catalog model and our cross-node plumbing.

## Decision

Adopt MXL v1.0 as the Layer 4 reference implementation, with four
explicit constraints recorded as platform invariants.

**1. Layer placement.** MXL fills Layer 4 (Media Exchange). NMOS
IS-04/IS-05 remains the Layer 5 control plane. MXL writes a
`flow_def.json` shaped per IS-04 but does **not** register it; that
integration is our work, owned by the eventual `nmos-cpp` ↔ MXL
adapter in `dmf-media`.

**2. Intra-host topology.** Until the Fabric API ships, two MXL
Media Functions cannot exchange a flow across k3s nodes. Each MXL
graph is pinned to a single host. **Pod node-affinity / hostname
co-location is a load-bearing architectural primitive, not a
performance tweak.**

**3. Multi-node bridges remain ST 2110 / NDI / SRT.** Cross-node
media transport in DMF goes over the network using existing broadcast
protocols. MXL accelerates the within-node hop only. When the Fabric
API ships and is stable on aarch64, this constraint reopens.

**4. Platform contract for any catalog entry that consumes MXL.**
Recorded so we don't re-derive it per function:

- Pod (or pod-group) declares an `emptyDir: medium: Memory` volume
  mounted at the MXL domain path. Bind mounts from non-tmpfs
  filesystems are forbidden.
- Members of an MXL graph share a `topologyKey: kubernetes.io/hostname`
  affinity rule.
- Build target on Hetzner (CAX21 / Neoverse-N1):
  `-DMXL_TARGET_ARCH=armv8.2-a`. CI gate must reject any MXL build
  artifact without an explicit arch flag.
- Custom workshop and example images are rebuilt for arm64 and pushed
  to our private registry. We do not consume `ghcr.io/cbcrc/mxl-*:latest`
  on Hetzner.
- A reaper — sidecar or periodic CronJob calling
  `mxlGarbageCollectFlows()` — is part of the Layer 4 contract, not
  optional.

**5. Deployment topology — dedicated processor nodes.** Realise the
intra-host constraint operationally by treating "MXL processor" as
a **k3s node role**, not a per-pod placement decision. Processor
nodes are tainted and labelled:

```
labels:  dmf.io/role=mxl-processor
taints:  dmf.io/mxl=true:NoSchedule
```

Platform pods (NetBox, Forgejo, AWX, Authentik, dmf-cms, OpenBao,
monitoring) stay on the existing 3-node CAX21 control plane.
MXL-consuming catalog entries declare a matching toleration plus
`nodeSelector: dmf.io/role=mxl-processor` and the scheduler routes
them. For the experiment phase, **one processor node** is
sufficient to exercise the architecture; HA-by-duplication adds a
second node later, with the same labels and an ST 2110 fan-out
between them.

**Hardware shapes available** (ranked least-resources-first per
ADR-0004):

- **ARM default — Hetzner CAX31** (8 vCPU / 16 GB / armv8.2-a /
  ~€10/mo). Same arch as the rest of the cluster, doubles tmpfs
  headroom over CAX21. Build path identical to the 400-mxl-prereq
  recipe (`-DMXL_TARGET_ARCH=armv8.2-a`). The default first
  processor node.
- **amd64 fallback — Hetzner CCX13** (2 vCPU / 8 GB / x86_64 /
  ~€7/mo). Available, not default. Used only if a real blocker
  prevents the arm64 build or runtime path. Lets us consume
  upstream `cbcrc/mxl-*:latest` workshop containers verbatim.
  Cost: introduces multi-arch image management to the cluster —
  accepted as a scoped escape hatch, not as a default profile.
- **Apple Silicon on Asahi Linux** (M1/M2 Mac mini / Mac Studio).
  A *third* profile, distinct from cloud nodes. Strong fit for
  (a) always-on lab hosts where recurring rental cost outweighs
  capex, and (b) physical-capture bridges (Thunderbolt → SDI /
  IP gateway / DeckLink) which cloud nodes can never provide.
  Build path uses MXL's auto-selected `-march=armv8.5-a` (M1/M2
  native), no flag override needed. Unified-memory bandwidth
  (100–400+ GB/s) is unusually well-matched to MXL's
  shared-memory ring-buffer model. Tracked as a deferred option;
  not required for the first trial. Asahi maturity is the
  gating factor — M1/M2 well-supported (May 2026), M3 workable,
  M4 not yet. Activate when a forcing function appears (physical
  capture, always-on lab host, or a graph that benefits from
  the memory-bandwidth advantage).

The catalog model (ADR-0013) gains three fields in v2 (post-Move-1)
to express this contract: `mxl_flows: { produces: [...], consumes: [...] }`
for graph wiring, plus standard k8s `tolerations` and `nodeSelector`
keys for processor-node placement. dmf-cms uses these to enforce
co-location at deploy time and to surface broken graphs when a
pod-group lands across hosts.

## Consequences

- **Positive** — Layer 4 has a concrete, Apache-2.0 implementation
  with broadcaster + vendor consensus behind it. We don't hand-roll IPC.
- **Positive** — Clean control/data split: NMOS at Layer 5, MXL at
  Layer 4, both speaking IS-04 flow shapes. Catalog entries can pin
  the data-plane contract independently of the control plane.
- **Positive** — Within-node zero/low-copy lets us chain media
  functions (e.g., 2110 receiver → MXL → ML processor → MXL → 2110
  sender) at memory speed, without burning multicast groups or PTP
  slaves for same-host hops.
- **Positive** — Direct probe of ADR-0004 experiment-phase thesis:
  if the intra-host constraint chafes the catalog or operator UX
  in practice, that's a real signal about whether DMF's layer model
  survives contact with reality.
- **Negative** — HA story for MXL-resident functions defers to
  "duplicate the graph on a second node + ST 2110 fan-out" until
  Fabric ships. Single-node failure ends the within-node graph.
- **Negative** — Hetzner build is custom: armv8.2-a target arch +
  arm64 image rebuild. Adds a one-time CI gate to dmf-media and
  ~30–60 min of build time per node-class on first attempt.
- **Negative** — Apple Silicon *dev loop on macOS+Docker* is broken
  until upstream publishes arm64 workshop images (qemu-x86_64 user-
  mode emulation crashes during MXL flow setup, smoke test 2026-05-07).
  Operator local reproductions on Macs with stock macOS go through a
  Hetzner build host or an arm64 CI runner. The Asahi-Linux-on-Mac
  profile (Decision §5) is unaffected — that's bare-metal Linux
  aarch64, not emulation.
- **Negative** — Reaper requirement is footgun-shaped. Crashed-writer
  detritus that goes uncollected accumulates as stale `*.mxl-flow/`
  dirs holding advisory locks; a missing reaper presents as "new
  flows fail to start" several days into a run.
- **Negative** — amd64 fallback (CCX13), if activated, introduces
  multi-arch image-pull complexity to the cluster. Accepted as a
  scoped escape hatch, not a default. Default remains arm64.
- **Negative** — Asahi Linux maturity is the active risk for the
  Apple Silicon profile. PCIe / Thunderbolt driver coverage for
  capture cards is incomplete; suitability for physical-bridge
  use cases must be re-checked at activation time, not assumed.
- **Positive (added)** — Failure domain becomes legible: stale-flow
  detritus, tmpfs OOM, bad MXL build — all contained to the
  processor node, never leaking into the control plane.
- **Positive (added)** — "Processor node" as a role abstraction
  generalises the topology rule: HA by duplication = a second
  processor node + ST 2110 fan-out, no per-graph scheme needed.
  Adding a node is cheaper than re-architecting a graph.
- **Positive (added)** — The Apple Silicon profile, when activated,
  preserves the only credible path to physical-capture hardware
  in the lab at zero current cost.
- **Neutral** — Catalog v1 (Move 1, nmos-cpp) does not use MXL.
  The first MXL-consuming catalog entry is post-Move-1. The v2
  schema extension is queued, not blocking.

## Alternatives considered

- **Use NMOS as Layer 4.** Rejected — NMOS IS-04/05 is control
  plane. Forcing co-located pods to bridge via ST 2110 burns a NIC,
  multicast group, and PTP slave for what could be a memcpy. MXL
  exists precisely to avoid that.
- **Wait until Fabric API ships before adopting MXL.** Rejected
  per ADR-0004. Experiment phase favours putting weight on the
  architecture *now* to learn whether intra-host MXL is sufficient
  for the workloads we have. We are not blocked on Fabric; we
  benefit from learning where its absence pinches.
- **Hand-roll a shared-memory IPC layer.** Rejected. The EBU TSC
  has invested in MXL with broad consensus. Diverging is a
  maintenance burden with no architectural payoff and no NMOS
  alignment story.
- **Defer Layer 4 entirely; rely on ST 2110 between every pod.**
  Rejected. Works for static facility builds but fails the
  experiment thesis around mixed-form-factor (cloud + flypack +
  facility) compute, where intra-host hops dominate the path.
  ST 2110 between sidecars on the same node is a smell.

## Enforcement

- `dmf-media/playbooks/400-mxl-prereq.yml` becomes the install
  path: arm64 build of MXL v1.0 with the arch flag, image push to
  the private registry, tmpfs-volume helpers in
  `roles/modules/media/mxl/`. The playbook fails closed if the
  arch flag is absent.
- The Forgejo CI workflow in `dmf-media` adds a build matrix
  entry that asserts `-DMXL_TARGET_ARCH=armv8.2-a` is the active
  arch for any artifact tagged `arm64`.
- ADR-0013 catalog schema gets an `mxl_flows` extension in its v2
  pass, validated at catalog-load time by dmf-cms. v1 catalog
  ignores the field.
- Skill `dmf-cluster-access` will gain a §Layer-4 stanza covering
  the tmpfs volume contract and the reaper requirement before any
  MXL-consuming function lands in the cluster.
- Re-open trigger: when MXL Fabric API enters a stable release on
  aarch64, this ADR is revisited — likely cuts constraint (3) for
  cluster-internal traffic. Track upstream releases at
  `github.com/dmf-mxl/mxl/releases`.

## References

- Upstream: `github.com/dmf-mxl/mxl` (Apache-2.0, v1.0.0 Feb 2026)
- Architecture: `github.com/dmf-mxl/mxl/blob/main/docs/Architecture.md`
- Governance: `github.com/dmf-mxl/mxl/blob/main/GOVERNANCE/GOVERNANCE.md`
- Workshop: `github.com/cbcrc/mxl-hands-on`
- EBU DMF Reference Architecture V2.0 — EBU White Paper, *The Dynamic Media Facility Reference Architecture*
- ADR-0003 (EBU taxonomy), ADR-0004 (experiment stance), ADR-0006
  (cluster as truth), ADR-0013 (catalog model)
- `docs/architecture/DMF Function Catalog Model.md` §2 — catalog v2
  needs `mxl_flows` field per this ADR
- `docs/plans/DMF Vendor Multi-Tenancy Vision 2026-05-29.md` — North Star
  that generalises this ADR's node-role topology to per-vendor tenancy;
  records IS-10 (control-plane authz) vs. MXL data-plane separation gap
- Smoke test artifacts (operator-local, left in place for follow-up):
  `mxl/`, `Architecture.md`, `Building.md`, `Exercise1.md`, `compose-tmpfs.yaml`,
  `build-test.sh` under an operator-local `mxl-smoke-tmp/` working dir

## Amendment 2026-06-12 — hygiene (no decision change)

Scrubbed two operator-local filesystem paths (a home-dir Downloads PDF
reference and a home-dir `mxl-smoke-tmp/` working dir) to neutral references
per the repo's no-local-paths discipline. Closes the §5 nit in the
[2026-05-27 ADR Portfolio Review](../reviews/DMF%20ADR%20Portfolio%20Review%202026-05-27.md).
