# ADR-0017 archive: MXL is an intra-host data plane; multi-node media graphs use ST 2110/NDI/SRT bridges

This file holds material moved out of [ADR-0017](../../decisions/0017-mxl-intra-host-data-plane.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Context (background moved from the ADR)

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
- `docs/plans/dmf-vendor-multi-tenancy-vision.md` — North Star
  that generalises this ADR's node-role topology to per-vendor tenancy;
  records IS-10 (control-plane authz) vs. MXL data-plane separation gap
- Smoke test artifacts (operator-local, left in place for follow-up):
  `mxl/`, `Architecture.md`, `Building.md`, `Exercise1.md`, `compose-tmpfs.yaml`,
  `build-test.sh` under an operator-local `mxl-smoke-tmp/` working dir

## Amendment 2026-06-12 — hygiene (no decision change)

Scrubbed two operator-local filesystem paths (a home-dir Downloads PDF
reference and a home-dir `mxl-smoke-tmp/` working dir) to neutral references
per the repo's no-local-paths discipline. Closes the §5 nit in the
[2026-05-27 ADR Portfolio Review](../../reviews/dmf-adr-portfolio-review.md).

## Context — prior state of Layer 4 (moved from the ADR)

Until now, our
`dmf-media/playbooks/400-mxl-prereq.yml` has been an empty skeleton
and Layer 4 has been hand-waved.
