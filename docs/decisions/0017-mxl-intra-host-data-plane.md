# ADR-0017: MXL is an intra-host data plane; multi-node media graphs use ST 2110/NDI/SRT bridges

**Status:** Accepted
**Date:** 2026-05-07
**Deciders:** @<handle>, planning session with Claude (smoke test 2026-05-07)

## Context

ADR-0003 adopted EBU DMF V2.0's six-layer model. Layer 4 (Media Exchange) sits between the Container Platform (Layer 3) and Media Functions (Layer 5), and the white paper
names a single reference implementation: the Media eXchange Layer (MXL) SDK at `github.com/dmf-mxl/mxl`. The EBU TSC has already settled whether to use MXL. The decision
the platform needs now is how MXL's intra-host-only constraint shapes our catalog model and our cross-node plumbing.

## Decision
Adopt MXL v1.0 as the Layer 4 reference implementation, with four explicit constraints recorded as platform invariants.

**1. Layer placement.** MXL fills Layer 4 (Media Exchange). NMOS IS-04/IS-05 remains the Layer 5 control plane. MXL writes a `flow_def.json` shaped per IS-04 but does
**not** register it; that integration is our work, owned by the eventual `nmos-cpp` ↔ MXL adapter in `dmf-media`.

**2. Intra-host topology.** Until the Fabric API ships, two MXL Media Functions cannot exchange a flow across k3s nodes. Each MXL graph is pinned to a single host. **Pod
node-affinity / hostname co-location is a load-bearing architectural primitive. It does not exist to tune performance.**

**3. Multi-node bridges remain ST 2110 / NDI / SRT.** Cross-node media transport in DMF goes over the network using existing broadcast protocols. MXL accelerates the
within-node hop only. When the Fabric API ships and is stable on aarch64, this constraint reopens.

**4. Platform contract for any catalog entry that consumes MXL.** Recorded so we don't re-derive it per function:

- Pod (or pod-group) declares an `emptyDir: medium: Memory` volume mounted at the MXL domain path. Bind mounts from non-tmpfs filesystems are forbidden.
- Members of an MXL graph share a `topologyKey: kubernetes.io/hostname` affinity rule.
- Build target on Hetzner (CAX21 / Neoverse-N1): `-DMXL_TARGET_ARCH=armv8.2-a`. CI gate must reject any MXL build artifact without an explicit arch flag.
- Custom workshop and example images are rebuilt for arm64 and pushed to our private registry. We do not consume `ghcr.io/cbcrc/mxl-*:latest` on Hetzner.
- A reaper (sidecar or periodic CronJob calling `mxlGarbageCollectFlows()`) is part of the Layer 4 contract. It is required.

**5. Deployment topology: dedicated processor nodes.** Realise the intra-host constraint operationally by treating "MXL processor" as a **k3s node role**. A per-pod
placement decision does not do this. Processor nodes carry the label `dmf.io/role=mxl-processor` and the taint `dmf.io/mxl=true:NoSchedule`. Platform pods (NetBox,
Forgejo, AWX, Authentik, dmf-cms, OpenBao, monitoring) stay on the existing 3-node CAX21 control plane. MXL-consuming catalog entries declare a matching toleration plus
`nodeSelector: dmf.io/role=mxl-processor`. For the experiment phase, **one processor node** is sufficient; HA-by-duplication adds a second node later, with the same
labels and an ST 2110 fan-out between them.

**Hardware shapes** (ranked least-resources-first per ADR-0004):

- **ARM default: Hetzner CAX31** (8 vCPU / 16 GB / armv8.2-a / ~€10/mo). Same arch as the rest of the cluster. The default first processor node.
- **amd64 fallback: Hetzner CCX13** (2 vCPU / 8 GB / x86_64 / ~€7/mo). Available as an alternative. Used only if a real blocker prevents the arm64 build or runtime path.
  It introduces multi-arch image management to the cluster, accepted as a scoped escape hatch. It is not a default profile.
- **Apple Silicon on Asahi Linux** (M1/M2 Mac mini / Mac Studio). A third profile, distinct from cloud nodes. Tracked as a deferred option; not required for the first
  trial. Asahi maturity is the gating factor. Activate when a forcing function appears (physical capture, always-on lab host, or a graph that benefits from the
  memory-bandwidth advantage).

The catalog model (ADR-0013) gains three fields in v2 (post-Move-1): `mxl_flows: { produces: [...], consumes: [...] }` for graph wiring, plus standard k8s `tolerations`
and `nodeSelector` keys. dmf-cms uses these to enforce co-location at deploy time and to surface broken graphs when a pod-group lands across hosts.

## Consequences
- **Positive:** Layer 4 has a concrete, Apache-2.0 implementation with broadcaster and vendor consensus behind it. We don't hand-roll IPC. NMOS at Layer 5 and MXL at
  Layer 4 give a clean control/data split.
- **Negative:** HA for MXL-resident functions defers to "duplicate the graph on a second node + ST 2110 fan-out" until Fabric ships. Single-node failure ends the
  within-node graph.
- **Negative:** Hetzner build is custom: armv8.2-a target arch + arm64 image rebuild. Adds a one-time CI gate to dmf-media and ~30-60 min of build time per node-class on
  first attempt.
- **Negative:** the Apple Silicon dev loop on macOS+Docker is broken until upstream publishes arm64 workshop images (qemu-x86_64 user-mode emulation crashes during MXL
  flow setup, smoke test 2026-05-07). Operator local reproductions on stock macOS go through a Hetzner build host or an arm64 CI runner. The Asahi-Linux-on-Mac profile
  (Decision §5) is unaffected, because it is bare-metal Linux aarch64.
- **Negative:** the reaper requirement is footgun-shaped. Uncollected crashed-writer detritus accumulates as stale `*.mxl-flow/` dirs holding advisory locks; a missing
  reaper presents as "new flows fail to start" several days into a run.
- **Negative:** the amd64 fallback (CCX13), if activated, introduces multi-arch image-pull complexity. Default remains arm64. Separately, Asahi Linux maturity is the
  active risk for the Apple Silicon profile. PCIe / Thunderbolt driver coverage for capture cards is incomplete; re-check suitability for physical-bridge use cases at
  activation time.
- **Neutral:** catalog v1 (Move 1, nmos-cpp) does not use MXL. The first MXL-consuming catalog entry is post-Move-1. The v2 schema extension is queued and blocks nothing.

### Enforcement
- Discipline only: none of the planned mechanical checks exist yet. `dmf-media/playbooks/400-mxl-prereq.yml` is a stub that sets no arch flag, no component repo contains
  `MXL_TARGET_ARCH`, `dmf-media/.forgejo/workflows/ci.yml` has no arch gate, and dmf-cms does not read `mxl_flows`. Review at PR time carries the platform contract in
  Decision §4.
- Re-open trigger: when the MXL Fabric API enters a stable release on aarch64, this ADR is revisited, likely cutting constraint (3) for cluster-internal traffic. Track
  upstream releases at `github.com/dmf-mxl/mxl/releases`.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0017-mxl-intra-host-data-plane.md).
