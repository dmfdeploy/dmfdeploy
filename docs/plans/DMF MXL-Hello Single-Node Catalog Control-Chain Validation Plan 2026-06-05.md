---
status: executed
date: 2026-06-05
executed: 2026-06-05
---
# DMF MXL-Hello — Single-Node Catalog Control-Chain Validation Plan

**Date:** 2026-06-05
**Status:** Approved — orchestrated build (Claude orchestrates + verifies, qwen-left lifts)
**Owner:** operator (with Claude; adversarial cross-check by qwen-left, 2026-06-05)
**Env:** sandbox `zmlj-sikn` (single Lima VM, 4 vCPU / 10 GiB / 60 GiB, full platform up)

**Related:**
- `docs/plans/DMF MXL On-Demand Media Function Cycle Plan 2026-06-01.md` — the **2-node
  fabrics** M1 (cross-host); this plan is the **single-node predecessor**, not part of it.
- `docs/plans/DMF MXL M1.1 Catalog Launch Design 2026-06-01.md` — the fabrics control-chain
  build whose playbook/JT/chart pattern we copy.
- ADR-0017 — MXL intra-host data plane (mxl-hello is intra-host, in-pod emptyDir domain).
- ADR-0025 — catalog launcher = in-cluster Helm / EE-as-runtime.
- ADR-0027 — catalog definition vs instance (mxl-hello is a single always-on definition).

---

## 1. Context & framing

Exercise the **MXL catalog deploy cycle through the dmf-cms console** on the **existing
single-node sandbox** *before* committing resources to the 2-node fabrics M1 (which is
cross-host by construction and does **not** fit a single node — distinct `nodeSelector`
labels + `hostNetwork` port 1234 require ≥2 `mxl-processor` nodes).

`mxl-hello` is the right vehicle: Layer-4, intra-host, `replicas: 1`, empty `nodeSelector`,
shared in-pod **memory** domain — no `hostNetwork`, no port 1234, no second node. The
catalog entry + chart already exist on `main` (`dmf-media/catalog/mxl-hello.yaml`,
`dmf-media/charts/mxl-hello/`), but the **control-plane wiring to drive it from the
console was never built** — only the fabrics path got it.

**This validates the CONTROL CHAIN** (catalog → Provision → AWX JT → playbook → helm →
health_probe → Finalise), **NOT the fabrics data plane.** Name it accordingly:
*"MXL catalog control-chain validation"*, not *"fabrics step 1"*. Payoff: prove a NEW
catalog entry + NEW playbooks wire up end-to-end with low blast radius, then reuse the
playbook pattern for fabrics later (different validation criteria, ≥2 nodes).

**Resource verdict (10 GiB VM): feasible but tight — resource limits are mandatory.**
Baseline (WP1S): ~1.1 GiB free idle, node ~76%, EE launcher pod peaks ~192 MiB.
GStreamer v210 1080p29 RSS is the wildcard (~300–600 MiB) and all four containers are
currently **unbounded** → without limits the node risks memory-pressure eviction / OOM
(kubelet can't protect a pod scheduled with 0 requests). The 256 MiB memory-backed
`emptyDir` is kernel page cache — **not** double-counted against container RSS — but it
still consumes node RAM.

## 2. Execution model (orchestrated)

- **Orchestrator = Claude:** decompose into slices, dispatch each to qwen-left via
  agent-bridge with a self-contained on-disk spec, **verify** every diff (ruff / `helm
  template` / `bash -n` / shellcheck-via-uvx, image+chart digests, no-OOM) before it is
  "done", report DONE/BLOCKED through agent-bridge.
- **Lifter = qwen-left:** authors the file edits / playbooks / chart changes; `/clear`
  at each slice boundary, paired with the self-contained spec.

## 3. Scope of changes (5 work items)

### WI-1. Chart: repoint to consolidated image + add resource limits
`dmf-media/charts/mxl-hello/` (`values.yaml`, `templates/deployment.yaml`)

- **Repoint all 4 containers** (writer/reader/info/reaper) at the single published,
  public, multi-arch image **`ghcr.io/dmfdeploy/mxl-fabrics-demo:v1.0.3-fabrics-dev`**
  instead of three stale `*:v1.0.1-dev` images whose publication is unverified.
  Verified from `dmf-media/docker/mxl-fabrics/Dockerfile`: the consolidated image carries
  `/usr/bin/mxl-*` (incl. `mxl-gst-testsrc`, `mxl-info`) **and** `fake-reader.sh` at
  `/usr/local/bin/fake-reader.sh`.
- **Per-container command overrides** (NOT a flat tag swap): writer→`mxl-gst-testsrc`,
  info/reaper→`mxl-info` (reaper `-g`), **reader→`/usr/local/bin/fake-reader.sh`** — a
  bash script, **not** a `mxl-fake-reader` binary, so its current
  `--domain/--video-flow-id/-i` args must be reconciled to fake-reader.sh's real
  interface. **This is the most likely silent-failure point (qwen) — give it a dedicated
  check before committing the deployment spec.**
- **Add resource limits** to all 4 containers (suggested: writer `limits.memory: 512Mi`,
  reader/info/reaper `128Mi` each; modest `requests` so the scheduler accounts for the
  pod). Keep `domainSizeLimit: 256Mi`.

### WI-2. Catalog entry: fix the image block
`dmf-media/catalog/mxl-hello.yaml`

- Replace `provision.image` (currently `mxl-gst-testsrc` + all-zeros digest placeholder)
  with the consolidated image **and a real published digest**. Collapsing to the single
  consolidated image makes the catalog's single-image schema consistent with the chart
  (which runs multiple binaries from one image). Leave `health_probe` as-is (`kind: log`,
  container `info`, pattern `"Active"`).

### WI-3. Launch/teardown playbooks (NEW)
`dmf-runbooks/playbooks/launch-mxl-hello.yml` + `teardown-mxl-hello.yml`

- Copy `launch-mxl-fabrics-demo.yml` / `teardown-mxl-fabrics-demo.yml` but **simpler**:
  no coordinator ConfigMap, no role/placement vars, no host-port handling.
  `helm pull` mxl-hello chart from Zot → `helm upgrade --install mxl-hello` in ns `mxl`
  → `k8s_info` readiness gate. Teardown: `helm uninstall` + namespace cleanup. No MXL
  flow-domain GC step (pod-scoped emptyDir wipes on pod delete).

### WI-4. AWX job templates (NEW)
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml`
(alongside the existing 4 `*-mxl-videotestsrc/view` JTs, ~line 174)

- Add `media-launch-mxl-hello` → `playbooks/launch-mxl-hello.yml` and
  `media-finalise-mxl-hello` → `playbooks/teardown-mxl-hello.yml`, project `dmf-runbooks`.

### WI-5. Zot seed wiring (image + chart)
`dmf-infra/k3s-lab-bootstrap/playbooks/630-zot-seed-platform.yml`
(extend `zot_seed_images` + `zot_seed_charts`, ~line 190 — the file's own comment at
line 19 names "MXL images" as the intended future seed entry)

- Add the consolidated **image** (`ghcr.io/dmfdeploy/mxl-fabrics-demo` → Zot) and the
  **`mxl-hello` OCI chart** (package + push `dmf-media/charts/mxl-hello` →
  `ghcr.io/dmfdeploy/charts/mxl-hello`, then mirror GHCR→Zot like nmos-cpp). The launch
  playbook pulls from `oci://zot.zot.svc.cluster.local:5000/dmf/charts/mxl-hello`, so it
  must be seeded or the deploy 404s.
- **Cross-check first:** whether the fabrics path already seeds the consolidated image to
  Zot via any route — if so, reuse that entry rather than duplicating it.

## 4. Sequencing (matters)

write playbooks (WI-3) → publish chart+image to GHCR & seed to Zot (WI-5) → add JTs
(WI-4) → **AWX project sync** (git pull so the new playbooks resolve at runtime) →
catalog entry goes live (WI-2) → console deploy. WI-1 (chart) lands with WI-5 (it's what
gets packaged + seeded).

## 5. Verification (end-to-end on `zmlj-sikn`)

1. Confirm 630 seed (image+chart present in Zot), 693 (AWX integration / JTs), AWX
   `dmf-runbooks` project sync picked up the new playbooks.
2. dmf-cms console: `mxl-hello` catalog card appears → **Deploy**.
3. `kubectl -n mxl get pods` → pod **Ready** (4/4), **0 OOMKills**; `kubectl top pod`
   confirms footprint within node headroom.
4. Health: `info` container log shows `Active`; NetBox tag flips to `lifecycle:active`.
5. **Teardown** → `helm uninstall`, ns `mxl` clean, tag back to `lifecycle:bootstrapped`.

**Done-criteria:** console Deploy → pod Ready + flow `Active` → console Teardown → clean,
no OOM on the single 10 GiB node. The 2-node **fabrics** data-plane validation is a
separate, later step.

## 6. Risks / open items

- **GStreamer RSS unknown until measured** — limits are a guardrail; if `mxl-gst-testsrc`
  redlines at 512Mi, raise once (as WP1S did for awx-web) or drop the test-pattern res.
- **fake-reader.sh arg interface** must be read from the consolidated image / upstream
  examples before finalizing the reader container command (WI-1) — top silent-break risk.
- **Real image+chart digests** obtained at publish time (no placeholders).
