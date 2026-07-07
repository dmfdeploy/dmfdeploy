# DMF v0.2a WP-C Kickoff Handoff

**Date:** 2026-07-07
**Status:** ✅ **WP-D shipped as a PR** — [`dmfdeploy/dmf-cms#25`](https://github.com/dmfdeploy/dmf-cms/pull/25) (NetBox-derived per-instance MXL live-view endpoints, G26). Codex adversarial cross-check ran **3 rounds** → **GATE-WPD-R3 PASS**. PR is open with auto-merge armed but held by **REVIEW_REQUIRED**; it is **not yet merged**, so issue **#185** stays open and the plan frontmatter is **not yet flipped** (do that on merge). **Next up: WP-C (G27) — media-native tile grid + live modal, depends on D.**

## What landed in WP-D (PR dmf-cms#25, branch `feat/mxl-per-instance-endpoints-g26`)

Two endpoints behind `_require_media_workloads_access` (ADR-0037 §5):
`GET /api/media-workloads/{instance}/mxl/status` and `.../mxl/preview`.

- **SSRF gate** (`media_workloads.sidecar_base_url`): reads NetBox custom fields `cluster_service`/`cluster_namespace`/`cluster_port` (the ADR-0038 Amendment-A / dmf-promsd contract — confirmed against `dmf-runbooks/roles/mxl` where `netbox_service_name == mxl_release == cluster_service`). Composes `http://<svc>.<ns>.svc.cluster.local:<port>` **only** when both are RFC1123 DNS labels (via `fullmatch` — a bare `.match` let a trailing `\n` through and raised `InvalidURL`→500, fixed in R1), namespace ∈ allowlist `{mxl}`, port ∈ allowlist `{9000}`, **and `cluster_service == svc["name"]`** (concrete identity, not app family).
- **Hardened fetchers** (`mxl.fetch_status_one`/`fetch_preview_one`): short timeouts, byte caps (256KB JPEG / 32KB JSON via `read(max+1)`), JPEG SOI check, `http.client.HTTPException` degradation.
- **No leak**: public list carries only boolean `live_view`; status returns a **fixed, bounded** field set via `mxl.shape_status` — strict-slug role/provider, IPv4/FQDN-rejecting `mxl_version`, dot/colon/slash-free `format`, fraction-only `grain_rate`, numeric-or-None flow. **`node` is NOT relayed from the sidecar** — NetBox `placement.node` is the SoT; WP-C must join node from the inventory payload. Degraded is 200 (`available:false`, reason `no-sidecar`|`unreachable`); **404 only** for not-in-scope (parity with `clear_for_deployment`).
- **5s TTL scope-keyed cache** (`ScopedServiceCache`, per-app) so per-tile polling doesn't hammer NetBox.
- **Settings**: `DMF_CONSOLE_MXL_SIDECAR_NAMESPACES` / `_PORTS` allowlists (fail-closed: explicit-but-all-invalid → empty, not silent default). Static `DMF_CONSOLE_MXL_ENDPOINTS` + `/api/mxl/*` stay as the split-node demo fallback.
- 153 backend tests green. Codex R1 caught a real 500 + a status-passthrough leak; R2 caught short-locator strings surviving a length cap (closed with per-field grammars + dropping sidecar `node`); R3 PASS.

## For the next session — WP-C (G27, dmf-cms, depends on D)

Full inline spec: `docs/plans/DMF v0.2 Media-Native Console Demo Plan 2026-07-06.md` under **"### WP-C"** (framing superseded by the EBU re-anchor plan, but the WP spec is the implementation detail). Grid becomes the default Media Workloads view behind a segmented **Grid|Table** toggle (localStorage); the existing table + clear-for-deployment flow stays intact.

- New `pages/MediaWorkloads/WorkloadTile.tsx`: `.card` tile keyed by `instance`; **fixed 16:9 thumbnail box** (never resizes — hard gate 5; `onError` → placeholder glyph in the same box); catalog `display_name` joined by `function_key`; **node + requested/observed badges + reconcile chip** (node from `placement.node`, per WP-D's contract). MXL tiles with `live_view` poll `useInstanceMxlStatus` at 2s and tick `<img src=/api/media-workloads/{instance}/mxl/preview?t=...>` at 1.5s with a freshness/provenance caption; clear-for-deployment in the tile footer reuses the identical armed-confirm + mandatory-reason **C5** flow.
- **Polling bounds (codex P2, still binding)**: live polling only in grid view AND only while the tab is visible (`document.visibilityState`), with a cap on concurrently-live thumbnail tiles (e.g. 6; others show last frame + refresh affordance); the 200ms modal cadence exists only inside the single open modal. **Reduced-motion (codex P3)**: `prefers-reduced-motion` pauses thumbnail churn, keeps explicit refresh + open-preview affordances.
- New `pages/MediaWorkloads/InstanceLiveModal.tsx`: overlay `.panel` on tile click — 200ms cache-busted preview + flow stats (head index, latency, role, provider, version — **not node from status**), provenance line, Esc/backdrop close. Fallback: mount existing `MxlDetailPanel` when `live_view` is false but the static split-node aggregate is configured.
- Edits: `MediaWorkloads/index.tsx` (responsive `md:grid-cols-2 xl:grid-cols-3`, deterministic sort, toggle, modal wiring), `hooks.ts`, `types.ts`.
- Tests (vitest): keyed sorted grid, display-name join, thumbnail tick cadence (fake timers), **no polling in table view / hidden tab / beyond the live-tile cap, reduced-motion pause**, onError placeholder without size change, modal open/close + 200ms src, clear flow from tile (reason required, Activity recorded), toggle persistence. See [[dmf-cms-frontend-test-gotchas]]: vitest setup polyfills localStorage; `rm -rf src/dmf_cms/static/app` before pytest so the built SPA doesn't mask backend fallback tests.

## Process reminders (boot ritual)

- **On WP-D merge**: close nothing (#185 stays open), but flip the WP-D line in the demo plan to done and record it in STATUS. WP-D's `refs` (not `Closes`) is deliberate — [[cross-repo-closes-not-auto]].
- Feature-branch work → run `bin/mxl-sync-check.sh` (note: from a **worktree** it reports siblings "not found" — resolve dmf-cms at the real sibling path `../dmf-cms` next to the umbrella root, not under the worktree). Branch dmf-cms from **fresh `main`**.
- **Codex cross-check via agent-bridge before landing** (codex live at tmux role `codex`; ~15–17 min/round at xhigh — poll the pane for idle, and beware the prompt-echo gotcha: anchor the GATE grep to codex's reply, not the echoed prompt). Reset codex between rounds with `--no-reply-id -- /clear`.
- **Worktree pre-commit clobbers `docs/SCRIPTS.md`** (deletes sibling sections — it can't see siblings from a worktree). If a commit auto-stages SCRIPTS.md, restore it (`git checkout HEAD~1 -- docs/SCRIPTS.md`) and amend with `STATUS_HOOK_SKIP=1`. [[worktree-hook-eats-scripts-md]]
- Umbrella doc work (WP-D status-contract alignment) is on branch **`docs/v02-ebu-reanchor`**, pushed (`efddc9f`), not yet PR'd.
