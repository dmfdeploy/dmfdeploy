# DMF MXL-Hello Single-Node Catalog Control-Chain — Build Complete, Live Verify Paused

**Date:** 2026-06-05
**Status:** Code-complete on `main`; chart published to GHCR. **Live verify intentionally
paused** (operator) until a confirmed sandbox env is up again.
**Plan:** `docs/plans/DMF MXL-Hello Single-Node Catalog Control-Chain Validation Plan 2026-06-05.md`
**Build model:** orchestrated — Claude verified, qwen-left lifted (3 slices); qwen adversarial
cross-check folded into the plan.

## What this is

Wire `mxl-hello` (Layer-4, intra-host, single-node, in-pod memory domain) to deploy through
the dmf-cms console, to validate the **MXL catalog control chain** (catalog → Provision →
AWX JT → playbook → helm → health_probe → Finalise) on the **single-node** sandbox — the
predecessor to the 2-node fabrics M1. It does **not** test the fabrics data plane.

## What landed (all on `main`)

| Repo | Commit | Change |
|---|---|---|
| dmf-media | `0df3307` | mxl-hello chart → consolidated `mxl-fabrics-demo:v1.0.3-fabrics-dev` image (per-container `command`/`args` mirroring the fabrics chart) + per-container memory limits; catalog `provision.image` real digest |
| dmf-runbooks | `84a7986` | `launch-mxl-hello.yml` + `teardown-mxl-hello.yml` (simplified single-node launchers) |
| dmf-infra | `84be264` | `media-launch/finalise-mxl-hello` AWX job templates |
| dmf-infra | `c2bf31a` | 630 `zot_seed_charts` entry for the mxl-hello chart (chart-only) |
| umbrella | `9257fd3` | the plan doc |

**Published:** `oci://ghcr.io/dmfdeploy/charts/mxl-hello:0.1.0`, digest
`sha256:ecfd201e5c21b68cabe8b32b002fe5915983c99bcc0e49ef3d3d4efa54ec0124`
(via `bin/publish-chart-to-ghcr.sh` with the operator's GHCR keychain credentials).

Verified pre-commit: `helm template` exit 0 (4 containers on the consolidated image, correct
entrypoints, memory limits); playbooks ansible-syntax-clean; AWX/catalog/630 YAML parse clean.
The consolidated image is confirmed public + anon-pullable on GHCR (digest
`sha256:84980dc0…`, **arm64** — matches the Apple-Silicon sandbox).

## Operator follow-ups before / for live verify

1. **Flip the GHCR package `dmfdeploy/charts/mxl-hello` to PUBLIC** — it defaults to private;
   630's anon GHCR→Zot skopeo mirror needs it public (same as the images).
   https://github.com/orgs/dmfdeploy/packages
2. **OPEN DESIGN QUESTION — image pull path (resolve at live time).** The chart pulls its
   *image* from **public GHCR** (`ghcr.io/dmfdeploy/mxl-fabrics-demo`), matching the sibling
   fabrics chart. This assumes the sandbox nodes have egress to ghcr.io at deploy time (M0
   did). If the env turns out egress-restricted, the **ready fallback** is: add the image to
   630 `zot_seed_images` + repoint the chart `image.registry` to the Zot path (nmos-style).
   The chart-from-Zot path is already wired (630 seed). This is the #1 thing to confirm.

## Live verify (when an env is up — currently PAUSED)

1. Ensure fresh sandbox bootstrapped; run/confirm 630 (chart in Zot), 693 (AWX JTs), and an
   AWX `dmf-runbooks` project sync (so the new playbooks resolve).
2. dmf-cms console: `mxl-hello` card → **Deploy**.
3. `kubectl -n mxl get pods` → pod **Ready 4/4**, **0 OOMKills**; `kubectl top pod` within
   node headroom (writer is the GStreamer wildcard; limit is 512Mi — raise once if it redlines).
4. `info` container log shows `Active` (health_probe); NetBox tag → `lifecycle:active`.
5. **Teardown** → ns `mxl` clean; tag → `lifecycle:bootstrapped`.

## Notes / latent bug spotted (out of scope, recorded)

- The **fabrics** `launch-mxl-fabrics-demo.yml` builds its OCI pull ref as
  `{{ mxl_chart_ref }}/{{ mxl_chart_name }}` where `mxl_chart_ref` already ends in the chart
  name → `…/dmf/charts/mxl-fabrics-demo/mxl-fabrics-demo` (doubled) → will **404** when that
  chart is seeded to Zot. Never exercised yet (fabrics chart isn't seeded). The mxl-hello
  playbook does it correctly (`{{ mxl_chart_ref }}` only). Fix the fabrics one before the
  2-node M1 live run.
