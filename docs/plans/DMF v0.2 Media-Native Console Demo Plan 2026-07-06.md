---
status: superseded
date: 2026-07-06
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/185
superseded_by: DMF v0.2 EBU Facility-Orchestration Re-anchor Plan 2026-07-07.md
---
# DMF v0.2 Media-Native Console Demo Plan (2026-07-06)

> **STATUS: SUPERSEDED (2026-07-07)** by
> [DMF v0.2 EBU Facility-Orchestration Re-anchor Plan 2026-07-07](DMF%20v0.2%20EBU%20Facility-Orchestration%20Re-anchor%20Plan%202026-07-07.md),
> which re-frames the v0.2 round around the EBU facility-orchestration lifecycle
> and reconciles these work packages under it (WP-A/B shipped and stay; WP-E
> stays as the next code WP; WP-C/D become critical-path lifecycle-observation
> surfaces; WP-G/H drop off the critical path; the media-native "demo" framing
> and the mock-licence idea are dropped). This doc is retained for the WP
> specifications and the codex fold history; the **re-anchor plan is canonical
> for v0.2 scope**. Do not start new work from this framing.
>
> _Original status banner:_ **APPROVED 2026-07-06** after two codex review rounds
> (PLAN-V02 round 1 CHANGES-NEEDED → both P1s + all P2/P3s folded; round 2 PASS).
> The inline WP specs (esp. WP-E/D/C) remain the implementation detail.

## Context

v0.1 is complete (only #36 stranger-deploy-verify pends). On the live env the ops
login resolves to `viewer` (no `dmf-console-*` group), so the IA §7-gated nav hides
Catalog and Media Workloads — no way to deploy or view workloads from the UI. The
operator's v0.2 goal: **a user deploys media functions from the web UI and views
deployed workloads media-natively — MXL functions as tiles with small live
thumbnails and a click-open preview window — with role switching (view-as) and the
dmf-init ops user as super admin.** A recorded v0.2 follow-on ("NetBox-derived MXL
live-view endpoints") is the per-instance preview enabler.

Exploration confirmed all raw material exists: the launcher stamps
`cluster_service`/`cluster_namespace`/`cluster_port`/`probe_path` custom fields per
MXL instance in NetBox; each release exposes a ClusterIP status sidecar
(`GET /status` JSON + `GET /preview.jpg`, receiver side only); dmf-promsd
`sd.py:71-76,154-159` is the canonical NetBox→URL contract to mirror; the console
already has the cache-busted `<img>` live-preview pattern (`MxlDetailPanel`) and the
`.card` grid primitives (Catalog `EntryCard`); role groups are hardcoded in
`security.py:15-27`.

## Work packages (landing order; one dmf-cms PR each, codex gates from G23)

### WP-A — Bootstrap super-admin (dmf-infra, G23)
The dmf-init-created ops user is always console admin.
- `k3s-lab-bootstrap/roles/stack/operator/authentik/templates/blueprints/15-ops-user-webauthn.yaml.j2`:
  add a `dmf-group-console-admin` entry mirroring the existing `ops-admin` block
  (lines 37-46) — upsert group `dmf-console-admin` + `method: add_users` with
  `!KeyOf dmf-user-ops`. Ordering vs the console's startup `ensure_group` seeding is
  safe (both upsert by name).
- **Live-env one-time unblock (operator action, no release):** add the ops user to
  `dmf-console-admin` in Authentik (or rerun the authentik playbook via the Manage
  lane). Next login = admin, Catalog + Media Workloads reappear immediately.
  *Executed 2026-07-06 (operator-authorized, server-side `ak shell`); the ops user
  is deliberately NOT an Authentik admin (two-identity model), so UI group
  management silently fails — the blueprint fix remains necessary for fresh envs.*
- Verify: blueprint render check; live `/api/me` shows `role: admin`.

### WP-B — View-as role switching (dmf-cms, G24)
Admin-only, session-scoped, strictly-downgrade, enforced server-side. Groups stay
real (tenancy + `media-engineers` grant untouched) — simulates "same groups, lower
role" without mutating identity (ADR-0028-safe).
- `security.py`: `effective_user(session)` — if real role `admin` and
  `session["view_as"] ∈ {viewer,operator,engineer}`, return
  `dataclasses.replace(user, role=view_as)`; anything else → real role (fail
  closed). `clear_user()` pops the key, and **every `store_user()` path also
  clears it** (re-auth/identity refresh can never inherit a stale downgrade —
  codex P2).
- `main.py`: `_require_min_role` + `_require_media_workloads_access` +
  `/api/me` switch to `effective_user`. New `POST /api/me/view-as {"role": ...}`
  (403 unless real admin; 400 for admin/unknown) and `DELETE /api/me/view-as`;
  **both authorize against the REAL session user** (reset must work while
  downgraded — codex P2); both audit-logged like the clear-for-deployment C5
  line. `/api/me` gains `real_role` + `view_as_active`; `role` is always the
  effective role.
- Frontend: `types.ts`/`hooks.ts` (mutations invalidate all queries so nav+data
  re-filter), `Topbar.tsx` — "View as" in the avatar menu (shown when
  `real_role === 'admin'`) + persistent amber "Viewing as {role} — Reset" chip.
  Sidebar needs no change (filters on effective `role`).
- Tests: pytest (non-admin 403, invalid 400, downgrade reflected in /api/me and
  enforced on media-workloads read + clear write, reset-while-downgraded,
  re-login clears the overlay, non-admin with a stale `view_as` key is ignored,
  logout hygiene); vitest (switcher admin-only, chip + reset, nav follows
  effective role).

### WP-E — Gate + nav alignment (dmf-cms, G25)
Confirmed mismatch: nav shows Catalog operator+ but `POST /api/catalog/{key}/deploy`
(main.py:1372), `/teardown` (1444), `POST /api/workflows/{name}/launch` (643) are
login-only — a viewer can deploy via curl.
- Move those three writes to `_require_min_role(request, "operator")`. Reads stay
  login-gated.
- **C5 on the AWX writes (codex P1):** deploy/teardown/launch are DMF-initiated
  automated actions, so they gain the same C5 pattern the clear-for-deployment
  write already has — mandatory `reason` in the request body, generated
  `request_id` echoed in the response, audit log line with actor + effective
  role (+ `real_role` when view-as is active). Frontend: Catalog cards and the
  Activity Jobs launch reuse the existing armed-confirm + reason UI from
  clear-for-deployment (graduated friction, hard gate 3); results land in the
  console-local Activity record like clear does.
- **Nav cleanup (operator feedback 2026-07-06):** remove the ungated `Settings`
  entry from the sidebar — personal (own-prefs) settings live in the Topbar avatar
  dropdown only, where they already were pre-#174. The rail slot is reserved for
  **Site settings** (facility-level, admin-gated per IA §7), which appears only
  when that page actually exists (stays named-deferred; no dead link now).
  Recorded as an IA §3 placement clarification: "Settings (own prefs)" is an
  account-menu surface, not a rail secondary — **the WP-E PR amends the IA doc's
  §3 secondary list (or its revision history) with this clarification so the
  docs don't drift from the build (codex R2 note).**
- **RP-initiated logout (handoff §5b fold-in, 2026-07-06 late finding):**
  `/auth/logout` clears the console session but the infra default
  `cms_logout_redirect_url` points at the base-domain homepage, so Authentik's
  SSO session survives and the next login is silent. Fix: point the logout
  landing at Authentik's end-session endpoint for the dmf-console app
  (`/application/o/dmf-console/end-session/`), ideally with `id_token_hint`;
  update the dmf-infra `cms_logout_redirect_url` default in the same round
  (dmf-infra PR alongside if needed). Add a test asserting the logout landing
  targets the end-session URL when OIDC is configured.
- Tests: viewer 403 ×3; operator passes; missing/empty reason 400 with no AWX
  call; request_id echoed; **admin view-as viewer 403** (B+E composition proof);
  nav tests drop `Settings` from expected sidebar sets and assert the
  avatar-menu path still reaches /settings; vitest for the reason-confirm flow
  on Catalog + Jobs launch and the Activity record entry.

### WP-D — NetBox-derived per-instance MXL endpoints (dmf-cms, G26)
- `media_workloads.py`: `_service_to_instance` reads `svc["custom_fields"]`; public
  payload gains ONLY a boolean `live_view` (no coords/URLs ever leave the backend).
  `sidecar_base_url(svc)`: validate `cluster_service`/`cluster_namespace` as DNS
  labels (`^[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?$`), then apply **tight allowlists
  (codex P1): namespace must be in a configured allowlist defaulting to `{mxl}`,
  port in an allowlist defaulting to `{9000}`, and `cluster_service` must equal
  **that specific scoped instance's own release/service name — the concrete
  identity, not merely the same app family (codex R2 note)** — a NetBox writer
  stamping arbitrary coords cannot turn the console into an in-cluster proxy.**
  Compose `http://{svc}.{ns}.svc.cluster.local:{port}`
  (byte-for-byte the dmf-promsd contract); any failure → None. Scope-checked
  instance lookup with the same 404-parity as `clear_for_deployment`. 5s TTL
  cache of the scope-filtered service list keyed by tenant scope.
- `mxl.py`: `fetch_status_one(base_url)` / `fetch_preview_one(base_url)` —
  **hardened (codex P3): short timeouts, response byte caps (e.g. 256KB JPEG /
  32KB JSON), and a JPEG SOI (`\xff\xd8`) check before proxying as image/jpeg.**
- `main.py`, both gated `_require_media_workloads_access`:
  - `GET /api/media-workloads/{instance}/mxl/status` → `{instance, available,
    role, provider, preview, node, mxl_version, flow{head_index, latency_ms,
    latency_grains, active, format, grain_rate}}`; degraded is 200 content
    (`available:false, reason:"no-sidecar"|"unreachable"`); 404 only for
    not-in-scope.
  - `GET /api/media-workloads/{instance}/mxl/preview` → `image/jpeg`, no-store;
    404 for out-of-scope or no preview (source side runs PREVIEW=0; mxl-hello has
    no sidecar).
- Static `DMF_CONSOLE_MXL_ENDPOINTS` + `/api/mxl/*` stay as the split-node
  (tailnet-only) demo fallback; docstring-deprecated, retired with that demo.
- Tests: SSRF matrix (bad labels/ports → never fetched) **plus negative targets
  `default`, `authentik`, `netbox`, `kubernetes.default` and a
  service≠instance-identity case — all asserting `urlopen` never called (codex
  P1)**, out-of-scope 404 parity, composed URL equals promsd contract (assert on
  mocked urlopen), no custom_fields/URL strings anywhere in
  `/api/media-workloads` JSON, preview 404 pass-through + SOI/byte-cap
  rejection, TTL cache behavior.

### WP-C — Media-native tile grid + live modal (dmf-cms, G27; depends on D)
Grid becomes the default view; existing table stays behind a segmented "Grid|Table"
toggle (localStorage) — keeps the proven clear-for-deployment flow intact.
- New `pages/MediaWorkloads/WorkloadTile.tsx`: `.card` tile keyed by `instance`;
  fixed 16:9 thumbnail box (never resizes — hard gate 5; `onError` swaps to a
  placeholder glyph in the same box); catalog `display_name` joined by
  `function_key` (fallback to key); node + requested/observed badges (reuse
  existing maps) + reconcile chip; MXL tiles with `live_view` poll
  `useInstanceMxlStatus` at 2s and tick the thumbnail
  `<img src=/api/media-workloads/{instance}/mxl/preview?t=...>` at 1.5s with a
  freshness/provenance caption; clear-for-deployment lives in the tile footer with
  the identical armed-confirm + mandatory-reason C5 flow. **Polling bounds (codex
  P2): live polling only in grid view and only while the tab is visible
  (`document.visibilityState`), with a cap on concurrently-live thumbnail tiles
  (e.g. 6; others show last frame + a refresh affordance); the 200ms cadence
  exists only inside the single open modal. Reduced-motion (codex P3):
  `prefers-reduced-motion` pauses thumbnail churn, keeping explicit refresh and
  open-preview affordances.**
- New `pages/MediaWorkloads/InstanceLiveModal.tsx`: overlay `.panel` on tile click —
  200ms cache-busted preview + flow stats (head index, latency, role, provider,
  version), provenance line, Esc/backdrop close. Fallback: mounts the existing
  `MxlDetailPanel` when `live_view` is false but the static aggregate is configured
  (split-node demo path).
- Edits: `MediaWorkloads/index.tsx` (responsive `md:grid-cols-2 xl:grid-cols-3`,
  deterministic sort, toggle, modal wiring), `hooks.ts`, `types.ts`.
- Tests (vitest): keyed sorted grid, display-name join, thumbnail tick cadence
  (fake timers), **no polling in table view / hidden tab / beyond the live-tile
  cap, reduced-motion pause**, onError placeholder without size change, modal
  open/close + 200ms src, clear flow from tile (reason required, Activity
  recorded), toggle persistence.

### WP-G — Alarm-surface research doc: EEMUA 191 + related guidelines (umbrella, docs-only)
Operator feedback on the Workspace "are we OK" core: good start; wants a
human-friendly at-a-glance surface with a **clear priority structure** and **no
non-required info on the front page**.
- Run the deep-research harness on: **EEMUA 191 latest edition** (3rd ed. + any
  amendments/current guidance), **ISA-18.2 / IEC 62682** (alarm management
  lifecycle, prioritization, KPIs like alarm rates per operator), **ISA-101**
  (HMI hierarchy: L1 overview → L2/L3 detail, the ~90%-neutral-screen rule),
  plus adjacent at-a-glance dashboard practice (e.g. high-performance HMI grey
  scale, alarm-flood suppression). EEMUA 191 itself is paywalled — research from
  reputable secondary sources and cite what was actually read; never fabricate
  clause numbers.
- Deliverable: `docs/reviews/DMF Workspace Alarm Surface Research (EEMUA 191)
  2026-07-06.md` — findings mapped **concretely to the current HealthCore**
  (tiles/list/verdict): what a compliant priority structure looks like (e.g. max
  3-4 priorities, target rates, what belongs on L1 vs one click away), what to
  remove from the front page, what's missing (shelving/out-of-service concepts —
  which feed the Alarm Philosophy spec, not v0.2 UI).
- This doc is also the graduation input for the `DMF Console Alarm Philosophy`
  design stub (Constitution Art. 4's → detail pointer).

### WP-H — Workspace front-page refinement (dmf-cms; gated on WP-G + operator review)
Apply the research: restructure the pinned core to the guideline priority model —
declutter the front page to only "required at a glance" content (verdict +
priority-bucketed counts + top problems), push everything else one deliberate step
away (Art. 6). Scope stays raw-alert-surface (no Ack/lifecycle — that remains
blocked on the Alarm Philosophy spec). Concrete deltas defined by WP-G's doc;
lands in the same 0.14.0 release if the review round is quick, else next.

### WP-F — IAM section: file the issue only (umbrella)
Issue: "Console IAM — user/group/role management via the Authentik back-channel +
external IdP sources (design spec first; no build in v0.2)". Inputs: existing
`authentik.py` group primitives, WP-B `real_role` plumbing, ADR-0028. The full
surface (memberships from the console, IdP federation, role-change audit) goes
through its own design spec + RFC per the working model.

## Working-model wiring
- Umbrella issues: (1) demo set WPs A–E (v0.2 milestone, `component:dmf-cms` +
  `component:dmf-infra`), (2) WP-F IAM design spec, (3) WP-G/H Workspace alarm
  surface (research + refinement). This plan lands as the `docs/plans/` doc with
  `tracking_issue` frontmatter (INDEX regen via pre-commit).
- Codex gates G23–G27 per code WP (WP-H gets its own when it lands); PR auto-merge
  arms at open (open only when final).
- Release: `dmf-cms 0.14.0` ships after WP-C — **WP-H stays out of the demo
  release gate (codex P2)**; it may ride only as a separately-reviewed add-on PR
  if already done and not touching the demo acceptance path. Operator-authorized
  deploy via the proven GHCR → 630 → 650 Manage-lane path.
- Suggested execution order: WP-A live unblock + WP-G research kick off first (both
  independent), then B → E → D → C, WP-H after the operator reviews the research
  doc.

## Risks (accepted, with mitigations — codex plan review folded)
1. NetBox load / polling scale → 5s scope-keyed TTL cache; grid-only +
   visible-tab-only polling with a live-tile cap; thumbnails 1.5s; 200ms only in
   the open modal.
2. Split-node demo sidecars are tailnet-only → static `/api/mxl/*` fallback stays
   until that demo retires.
3. View-as keeps groups real: an admin in `media-engineers` still sees Media
   Workloads as view-as viewer — correct by design (a real viewer in that group
   would too); documented in the WP-B PR; group suppression belongs to WP-F's spec.
4. Preview-proxy residual authority (codex P1) → namespace/port allowlists
   (default `{mxl}`/`{9000}`) + service-identity binding + negative-target tests;
   a hostile NetBox writer cannot use the console as an in-cluster proxy.

## Live verification (end of round)
1. WP-A: ops login → `/api/me` `role: admin`; Catalog + Media Workloads visible.
2. Deploy 0.14.0 (Manage lane). As ops: Catalog → deploy an MXL function → job
   completes → bootstrapped tile appears → clear-for-deployment (reason, Activity
   entry) → converges → live thumbnail on the receiver tile → modal shows the head
   index ticking at 200ms with latency stats.
3. View-as viewer: Catalog/Admin vanish; `POST /api/catalog/.../deploy` → 403;
   chip visible; reset restores.
4. Devtools/network scan: no `.svc.cluster.local`, tailnet host, or IP in any
   payload (scrub rule).
