---
status: historical
date: 2026-06-01
---
# DMF MXL Catalog Media Function Cycle — Spike Plan

**Date:** 2026-06-01 (v3 — split: MXL-specific scope only)
**Status:** Scope re-cut after a codex adversarial review + an OpenTofu/EE feasibility check, then **split** — this doc holds only the **MXL-specific** spike. The non-MXL infrastructure (elastic media nodes / cloud cost controller) is a **separate plan on `main`** (see §4).
**Owner:** operator (with Claude; adversarial cross-check by codex, session `019e81f6`)
**Branch:** `feat/mxl-spike`

**Related:**
- `dmf-media/docs/mxl-fabrics-runbook.md` — M0, the GREEN manual cross-host TCP demo (2026-05-30)
- ADR-0027 — catalog **definition vs instance** separation (the *second* function is its named trigger — we hit it head-on)
- ADR-0025 — catalog launcher = in-cluster Helm / EE-as-runtime (generic runner-pod still in flight)
- ADR-0017 — MXL intra-host data plane; `mxlGarbageCollectFlows()` is part of the Layer-4 contract
- **`docs/plans/DMF Elastic Media Nodes and Cloud Cost Controller Plan 2026-06-01.md`** *(to be authored on `main`)* — owns provisioning, the TTL cost sweeper, and scale-from-zero; this spike **depends** on it (§4)
- `docs/reviews/dmf-mxl-upstream-profile-and-contribution-review-2026-06-01.md` — upstream contribution angle (this cycle feeds #274)

---

## 0. Scope & the split

This is the **MXL spike**: demonstrate two real MXL media functions, deployed from
the dmf-cms catalog, auto-wiring an MXL fabrics (tcp) flow across a **fixed** Aliyun
node pool, viewed on the dmf-cms MXL Flows page.

The adversarial review showed the original "catalog click spins up a node, runs the
flow, tears it down" bundles a **cloud-cost-controller** project into the spike. That
is a real goal — **but it is not MXL-specific and does not belong here.** It is split
out to a separate plan on `main` (§4). What stays in this doc is only what teaches us
about **MXL**: catalog packaging of media functions, fabrics auto-wiring, flow
lifecycle, and the operator view. Provisioning runs **operator-initiated** (laptop
`tf-apply`, as in M0) for the spike; elastic provisioning is out of scope here.

**Decisive feasibility fact (why provisioning is not in this spike):** OpenTofu is
**not** available in-cluster by design — the in-cluster EE
(`dmf-infra/k3s-lab-bootstrap/ee/execution-environment.yml`) is `awx-ee` + ansible
collections only, no tofu in the build context or any EE commit; `tf-apply.sh` is
laptop-only (local creds, JuiceFS single-operator state). That whole problem belongs
to the cloud-controller plan, not here.

## 1. Goal

Two functions, deployed from the catalog, on a fixed 2-node pool:
- **`mxl-videotestsrc`** — produces a v210 test-pattern flow (fabrics initiator).
- **`mxl-videotest-view`** — consumes it (fabrics target) and surfaces an observable output.

## 2. Milestones (MXL scope)

| Milestone | Deliverable | Demo (done-criteria) |
|---|---|---|
| **M0** ✓ | Manual cross-host fabrics TCP transfer | done — see runbook |
| **M1 — the spike** | Two **separate** catalog functions deployable independently with role/placement, **restart-safe** fabrics auto-wiring, MXL flow GC, on a **fixed** 2-node pool; MXL Flows page reflects it | In the console: deploy `mxl-videotestsrc` + `mxl-videotest-view` → flow auto-wires (and **survives a target pod restart**) → MXL Flows page shows the live flow + preview → remove both → clean teardown (uninstall + flow-domain GC) |

(Elastic scale-from-zero and NMOS/crosspoint are tracked elsewhere — §4, and the
deferred NMOS milestone in the upstream review.)

## 3. M1 — detail (ordering corrected by review)

**The critical path is NOT the handshake — it is catalog/instance semantics +
missing artifacts.** Roughly in order:

1. **Catalog definition vs instance split (ADR-0027) — the real first blocker.**
   Today there is **one** `mxl-fabrics-demo` chart (target always-on, initiator
   toggled by a Helm value) and **one** catalog entry; the CMS deploy API only
   launches a *named AWX job template with no role/placement/value payload*
   (`dmf-cms/src/dmf_cms/main.py`). M1 needs **two** catalog definitions deployable
   independently, and the launcher/API must carry **role + placement + value**
   inputs. This is exactly the ADR-0027 trigger — design work, not packaging.
   **Keep it minimal:** build the *smallest* instance/value payload that carries
   role + placement + values for these two functions. Do **not** let this become
   "build the whole future catalog operator" — that is out of spike scope.
2. **Missing launcher/teardown artifacts.** There are **no** `launch-mxl-*` /
   `teardown-mxl-*` runbooks in the tree. Write them (nmos-cpp launchers are the
   pattern); they run the catalog functions, not infra.
3. **Restart-safe fabrics handshake (coordinator, not one-shot ConfigMap).** The
   target **regenerates `target-info` on every restart**. A one-shot init-container
   reading a ConfigMap won't survive target restart, stale target-info, multiple
   flows, or concurrent deploys. Use a **coordinator / lease / versioned-endpoint**
   model; the source **re-attaches when target-info changes**. The coordinator
   must tolerate **either deploy order** (viewer-first and source-first), since
   the catalog deploys are independent.
   **Flow-ID strategy (decide explicitly):** whether flow IDs are *fixed per
   demo* or *generated per instance*. Stale fixed IDs must not collide across
   retries / redeploys; generated IDs must be discoverable through the same
   coordinator the handshake uses.
4. **Role/placement allocation.** Both pods use `hostNetwork`; target binds port
   **1234**. Guarantee producer and receiver on **different** nodes and no two
   receivers on one host's port (anti-affinity + role/port allocator; `Recreate`
   alone is insufficient under dynamic scheduling).
5. **MXL flow-domain GC (ADR-0017, not optional).** tmpfs `emptyDir` + no
   `mxlGarbageCollectFlows()` → stale flow dirs/locks → delayed, ugly failures. Add
   a flow-domain reaper / teardown step.
6. **Consistent image pull path.** ADR-0025 wants Zot-seeded artifacts + containerd
   handling; M0 pulled public GHCR with **no imagePullSecret**. Pick one, make the
   chart consistent.
7. **Observable output — reuse the dmf-cms MXL Flows page.** Per-node cards (IPs
   hidden — disclosure-safe), live head-index + latency, JPEG preview =
   proof-of-receipt. Today it is **static** (`DMF_CONSOLE_MXL_ENDPOINTS` env). For a
   **fixed** pool the dynamic-discovery problem is bounded (known node set), so this
   is lighter than the elastic case. **For the spike, prefer fixed-pool sidecar
   discovery / env wiring** (make the existing sidecar endpoints available without
   hardcoding secrets into git). A **Prometheus exporter is OPTIONAL** here — defer
   it as later hardening, not spike work.
8. **Fix stale artifact:** catalog entry still says `eth1`; reality is `eth0`.

## 4. Dependency: the cloud cost controller (separate plan, on `main`)

The spike provisions **billable** Aliyun instances, so it needs a **cost guardrail**
before it is safe to run. That guardrail — and the larger elastic-node story — is
**not MXL-specific** and is owned by a separate plan on `main`:
**`DMF Elastic Media Nodes and Cloud Cost Controller Plan`** (to be authored). It covers:
- a **cloud-tag Aliyun TTL sweeper** (tags `dmf-owned/env/purpose=mxl-media/created-at/ttl`),
  out-of-cluster, independent of k8s + TF state — the honest fail-safe;
- the **provisioning substrate** for eventual in-cluster scale-from-zero (tofu-in-EE
  or out-of-cluster agent, OpenBao-injected cloud creds, network TF state backend,
  cloud egress, ADR-0024/0033 privilege surface).

**Spike dependency:** only the **tag convention + TTL sweeper** must exist before we
run the spike's fixed pool. Everything else in that plan can proceed on its own
timeline on `main`. The MXL spike is its first *consumer* / motivating use case, not
its owner. **Timing:** M1 *implementation* can start **now** (before the sweeper
exists); only **live billable runs** of the fixed pool gate on the sweeper being in
place.

## 5. Adversarial review findings folded in (2026-06-01)

Codex (gpt-5.5 xhigh, session `019e81f6`) + the EE/tofu check. **MXL-scope findings**
(→ this doc): two-functions-don't-exist + ADR-0027 trigger (§3.1–3.2); weak ConfigMap
handshake / target regenerates on restart (§3.3); hostNetwork port-1234 collision
(§3.4); MXL flow GC ignored (§3.5); Zot-vs-GHCR pull path (§3.6); static MXL Flows
view (§3.7); stale `eth1` (§3.8). **Infra-scope findings** (→ cloud-controller plan on
`main`): provisioning substrate absent / EE has no tofu; k8s reaper insufficient →
cloud-tag sweeper.

**Re-review (2026-06-01, same codex session):** confirmed the split is *materially
clean* and the spike is *genuinely MXL-focused* — autoscaling is no longer smuggled
into M1. Four refinements folded in: keep the ADR-0027 payload minimal (§3.1); mark
Prometheus optional, prefer sidecar discovery (§3.7); coordinator tolerates both
deploy orders (§3.3); decide flow-ID strategy + no-collision-across-retries (§3.3).
Plus the timing nuance: M1 build can start before the sweeper (§4).

## 6. Critical path & open decisions (MXL)

**Critical path:** M1.1 — catalog definition/instance split + a launcher that carries
role/placement. Prototype the two-definition catalog deploy onto the fixed pool first;
the handshake is second, not first.

**Open decisions:** handshake coordinator design (lease vs versioned-endpoint vs
sidecar); MXL Flows view source (Prometheus exporter vs fixed-pool sidecar discovery).
