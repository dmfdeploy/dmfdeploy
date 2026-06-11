# DMF MXL Upstream Profile & Contribution Review

**Date:** 2026-06-01
**Author:** operator (with Claude)
**Status:** Findings / strategic input — informs how we turn the fabrics spike into upstream contribution
**Scope:** Profile of the upstream `github.com/dmf-mxl/mxl` project (issues, PRs, discussions, governance) and an assessment of where *our* fabrics spike can make the highest-value contribution.

**Related:**
- ADR-0017 — MXL is an intra-host data plane; multi-node uses bridges (this review revisits the Fabrics-API roadmap status that ADR called "roadmap, not v1.0")
- `docs/plans/DMF MXL Single-Node Media Node Spike Plan 2026-05-17.md`
- `docs/plans/DMF MXL Single-Node Loopback Execution Plan 2026-05-29.md`
- `dmf-media/docs/mxl-fabrics-runbook.md` (our GREEN cross-host TCP demo, 2026-05-30)

> **Process note (2026-06-01):** request submitted to join the EBU MXL mailing
> list + Slack; **awaiting approval**. Per upstream `CONTRIBUTING.md`, onboarding
> runs through the EBU group page, and important questions are expected to go
> through GitHub Discussions / the TSC rather than Slack. Contribution actions
> below are sequenced so the low-barrier, list-independent ones (hardware-test
> report, ARM build docs) can proceed as soon as access lands.

---

## 1. Project profile

| | |
|---|---|
| Repo | `github.com/dmf-mxl/mxl` — "Dynamic Media Facility: Media Exchange Layer" |
| License / age | Apache-2.0, created 2025-05; very active (commits daily as of this review) |
| Traction | ~138 stars, ~52 forks, ~35 contributors |
| Stack | C++ core (~1.1 MB) + C API + **Rust bindings** (~243 KB); CMake/vcpkg, devcontainers |
| Formats | V210 video, Float32 audio, ANC (SMPTE 291 / ST 2038) |
| Backing | EBU + NABA "implement-first" initiative under LF Projects; TSC drawn from BBC, EBU, CBC/Radio-Canada, Grass Valley, AWS, NVIDIA, Lawo, Riedel |

**Two APIs — this is the key structural split:**
- **Flow API** — shipped in **v1.0** (Feb 2026). Single-node, zero-copy media via mmap'd tmpfs ring buffers synchronised with futexes. This is what ADR-0017 characterised.
- **Fabrics API** — **the current major workstream, targeting v1.1 beta for EBU NTS** (issue #522). Inter-host media movement over **libfabric**. Providers already in the header (`lib/fabrics/include/mxl/fabrics.h`): `AUTO`, **`TCP`**, `VERBS` (RDMA), `EFA` (AWS), `SHM`.

> **ADR-0017 status update:** the Fabric API is no longer purely roadmap — it is
> implemented, merged, and shipping in the v1.1 beta line. `TCP` is a first-class
> provider, which is precisely the path our spike exercises (kernel TCP/IP, no
> RDMA hardware). Worth a follow-up ADR amendment once v1.1 beta lands.

## 2. Governance & contribution bar

Run by a **TSC** with weekly meetings (nearly every issue carries dated `TSC` status notes), an EBU Slack, and a mailing list. The merge bar is **high**:

- **2 maintainer approvals** (non-author) + **DCO sign-off using an org-domain email** (`git commit --signoff`) + **4 CI checks** (Ubuntu arm64/x86_64 times Clang/GCC). No CLA.
- **No `good first issue` label.** Newcomers are expected to engage via the EBU group / Slack / TSC first.
- Catch2 for tests; Doxygen for docs; SPDX headers required on new files.

Key people: **jonasohland** (Jonas Ohland) — fabrics lead, most active; **vt-tv / felixpou** (Vincent Trussart / Felix, CBC/R-C) — chairing TSC cadence; **garethsb / hursh-nvidia** (NVIDIA, also nmos-cpp maintainer — the NMOS/MXL boundary); **Thomas-video** (AWS/EFA); **KimonHoffmann**.

## 3. Where the energy is (open work, 2026-06-01)

1. **Fabrics v1.1 (dominant):** #179 capability querying / protocol selection, #182 Rust bindings, #184 multicast, #272 graceful shutdown + in-flight accounting, #318 `mxl://`-style URLs, #402 DSCP/traffic-class, **#274 hardware-test tracking (empty — explicitly solicits user reports)**.
2. **GStreamer plugins:** #232 alpha, #240 ANC, #324 multiflow A/V sync, #330 cleanup.
3. **Timed Data** #327 — vt-tv's lockfree ring buffer for non-periodic / 2110-41-style data (design accepted, implementation in progress).
4. **Docs:** #364 GitHub Pages, #400 doc-types, #492 Doxygen, #526 fabrics docs from wiki to repo.
5. **Bugs / flakes:** **#519** intermittent `st2038_round_trip_via_mxl` (reproducible, ~12/50), **#538** SIGSEGV in `valid_gray_pipeline` (CI-only).
6. **Build / ARM:** **#409** "Explain how to build on older ARM CPUs" (empty).

## 4. Our fit — why the spike has leverage

Upstream fabrics testing is overwhelmingly **in-datacenter RDMA on x86** (verbs / EFA / RoCE — NVIDIA, AWS, Intel labs). Our spike sits in a **gap almost nobody is exercising**:

- **TCP provider** (kernel path, no RDMA hardware) — proves the plumbing where RDMA isn't available.
- **ARM** media nodes (Aliyun `g8y`-class) — CI builds arm64, but real fabrics runtime reports on ARM are scarce.
- **Across a real network with latency** (cross-host, Tailscale/WAN-class) — most upstream runs are single-rack.

Our runbook already records a **GREEN cross-host TCP fabrics demo (2026-05-30)**: test-pattern grains produced on one ARM node forwarded over the libfabric `tcp` provider into a receiver's domain on a second ARM node, received flow Active with head index advancing. That is directly reportable.

## 5. Recommended contributions — ranked by value times fit times low-barrier

1. **#274 — report TCP / ARM / WAN fabrics test results.** The issue is *empty* and literally asks users without wiki access to post results for a maintainer to fold into the wiki. We are the ideal reporter; near-zero merge friction; seeds a relationship with the fabrics team. **Can proceed the moment access lands** — does not need a PR.
2. **#409 — document building MXL on (older / cloud) ARM CPUs.** Empty docs task, our exact environment. A clean, self-contained first PR that clears the 2-approval bar easily and builds standing.
3. **Surface (and ideally fix) TCP-provider-over-latency bugs.** A WAN/Tailscale path will likely expose timeout / retry / MTU / keepalive issues the in-DC testers never hit. Well-documented bug reports are treated as first-class here (cf. #519/#538); a fix to the TCP path would be a genuinely differentiated contribution.
4. *(Stretch)* **#519** — a reproducible flaky test is a tidy, scoped way to demonstrate competence, though it lives in the Rust/GStreamer layer rather than our fabrics focus.

**Suggested sequence:** finish the spike then capture clean, reproducible TCP-over-WAN/ARM results (versions: libfabric, kernel, MXL commit) then post to **#274** plus open the **#409** ARM-build docs PR then triage any TCP-path bugs into upstream issues/PRs.

**DCO identity (decided 2026-06-01):** all upstream commits sign off as
`znerol2 <<user-id>+<handle>@users.noreply.github.com>` — the GitHub private
noreply identity already mandated for public-repo commits by
`docs/plans/DMF Public Repo Identity Leak Sweep 2026-05-11.md`. Set per-clone on
the upstream working copy:
```bash
git config user.name  'znerol2'
git config user.email '<user-id>+<handle>@users.noreply.github.com'
git commit --signoff   # DCO Signed-off-by must match the above
```
Caveat: upstream `CONTRIBUTING.md` asks corporate contributors for an
*org-domain* address for copyright tracking; we contribute as an individual, so
the noreply identity is the right call and is consistent with our public-repo
privacy posture. Revisit only if we ever contribute on behalf of a named org.

## 6. Open questions for the operator

- ~~**Identity for upstream PRs:**~~ **Resolved 2026-06-01** — sign off as `znerol2 <<user-id>+<handle>@users.noreply.github.com>` (see §5).
- **Disclosure posture:** how much of our topology do we describe in a public #274 report? Placeholder-only per umbrella convention (no real IPs/DNS/handles); "two ARM cloud nodes, cross-region, libfabric tcp" is enough signal without leaking infra.
- **ADR-0017 amendment:** schedule once v1.1 beta tags, to record that the Fabric API is now real and that we have a working TCP cross-host path.
