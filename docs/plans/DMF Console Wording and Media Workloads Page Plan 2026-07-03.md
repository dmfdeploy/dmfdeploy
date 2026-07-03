---
status: draft
date: 2026-07-03
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/173
---
# DMF Console Wording and Media Workloads Page Plan (2026-07-03)

> **STATUS: PROPOSED — documents-only round; no dmf-cms edits yet.** First of two
> console plans. This one delivers the **DMF-aligned wording pass** plus the
> **Media Workloads page** (ADR-0037 D4) and retires the standalone MXL Flows page.
> The second plan — `DMF Console Information Architecture Implementation Plan
> 2026-07-03.md` (#174) — does the full 4-rail IA/Workspace restructure and is
> sequenced *after* this one and after #166's rules land.

**Component:** `dmf-cms` (React frontend + FastAPI backend). Doc lives in the umbrella
per convention.
**Supersedes:** `DMF Media Workloads — NetBox-Driven Media Function Inventory Plan
2026-06-03.md` (its D4 page slice is re-planned here against the current codebase; its
D1 model shipped as ADR-0037 and is unchanged).
**Governing design docs:** `../design/DMF Console UX Constitution 2026-05-25.md`
(Art. 3 three-tier vocabulary + §3 hard gates), `../design/DMF Console Information
Architecture 2026-06-23.md` (IA §9 label map), `../decisions/0037-media-workloads-
netbox-instance-inventory.md` (the model), `../decisions/0038-netbox-driven-dynamic-
monitoring.md` (status signals).

---

## 1. Context & motivation

The console today has nine flat routes (`frontend/src/App.tsx`, nav in
`frontend/src/components/Sidebar.tsx`). Two problems this plan fixes:

1. **Vocabulary misalignment (Art. 3 violations at default level).** The live
   `frontend/src/pages/MxlFlows.tsx` renders an `EBU DMF layer stack` heading with rows
   literally titled "Application & UI" / "Media Functions" / "Media Exchange" — the raw
   `dmf-internal` EBU-layer ontology that the UX Constitution says must *earn*
   operator-native status before appearing at default level. The nav label "MXL Flows"
   itself names an SDK, not an operator concept.
2. **The decided media surface doesn't exist.** ADR-0037 (accepted 2026-06-03) decided
   the console surface for media is a **"Media Workloads"** page backed by NetBox
   instance inventory — instances in NetBox, never flows; AWX reconciles; no CRD. The
   2026-06-03 plan specced the page (D4) but was shelved ("planning docs only by
   operator instruction"); no `pages/MediaWorkloads/`, no `/api/media-workloads`
   endpoint exists. The `0.11.0` version slot earmarked for it was consumed by other
   work.

The MXL single-node revival (#17, `DMF MXL Single-Node Revival Plan 2026-07-03.md`)
needs this page as its console surface — that plan's WP6 depends on this plan's WP2/WP3.

## 2. Decisions taken (operator, 2026-07-03)

- **Two plans, not one:** wording + Media Workloads page now; the 4-rail IA/Workspace
  restructure is a separate follow-on plan (#174). Rationale: this slice is
  independently shippable and unblocks #17; the IA restructure depends on #166 signals
  that don't exist yet.
- **MXL Flows page retires into Media Workloads** (ADR-0037 already rejected a bespoke
  MXL page as the home; the IA doc's §9 map agrees).
- Milestone **v0.2** — nothing here gates the v0.1 claim.

## 3. Work packages

### WP1 — DMF-aligned wording pass (no structural changes)
Scope: label/copy changes only, per the Art. 3 three-tier rule and the IA §9 map where
it does **not** require the rail restructure:
- `Sidebar.tsx`: `Facility` → **Facilities**; leave route paths stable (`/facility`
  stays; renaming routes is #174 scope).
- `MxlFlows.tsx` (until WP4 retires it): replace the `EBU DMF layer stack` heading and
  raw layer-row titles with operator/industry-tier equivalents; keep the existing
  plain-language captions (they are the right direction). System/EBU terms move to
  expert-level detail affordances, not default headings.
- **Glossary seeding:** add the terms this pass touches (Media Workload, Media
  Function, Facilities, and the demoted layer terms) to
  `docs/design/DMF Console Glossary.md` with their tier assignments — the Art. 3
  register is the audit trail for every wording call made here.
- Sweep for other default-level system-tier leaks (grep for layer/vertical/lifecycle
  vocabulary in `frontend/src/`); fix or file.

### WP2 — Backend read: `GET /api/media-workloads` (ADR-0037 D4)
- New endpoint in dmf-cms (`src/dmf_cms/main.py` + helper module following the
  existing `catalog.py` pattern): returns Media Function **instance inventory** from
  NetBox — function key, display name, placement (cluster/namespace/service), lifecycle
  status (NetBox tags per ADR-0027/0037), and live status overlay.
- **Server-side scoping is a hard gate:** tenant/site scope enforced in the backend
  (not a frontend filter). **Access gating (v1):** the page and endpoints are gated to
  the existing `engineer` + `admin` roles — dmf-cms today recognizes only the four
  `dmf-console-*` role groups (`src/dmf_cms/security.py`), and the IA §7 role matrix
  puts Media Workloads visibility on the role axis with action depth as the finer cut.
  ADR-0037's dedicated **`media-engineers` Authentik group is a recorded follow-on**
  (seeded blueprint + `groups[]` claim consumer) that lands with the #174 role/groups
  work — not silently dropped, not blocking this slice. Tests cover both: role-gated
  access now; group-present/absent behavior once the group consumer lands.
- Live status overlay: join NetBox instances against the existing status sources
  (catalog deploy state; Prometheus `probe_success` per ADR-0038 where stamped —
  read via the existing `src/dmf_cms/prometheus.py` client).
- Errors are content (Constitution hard gate 4): NetBox unreachable → explicit
  degraded-state payload, never a raw 500 to the UI.

### WP2b — Backend write: "clear for deployment" (the ADR-0037 consequential action)
- `POST /api/media-workloads/{instance}/clear` (single action, no generic write
  surface): flips the instance's NetBox lifecycle tag to the *cleared-for-deployment*
  state per ADR-0027/0037 tag taxonomy. **NetBox is the only thing the console
  writes;** actual convergence is the AWX reconciler's job (ADR-0037: the
  `operate-catalog-drift` loop picks up the desired-state change) — the console never
  touches k3s.
- Captures the **ADR-0028 C5 quartet** (actor/role/request-id/reason — reason is a
  required request field) and enforces the same server-side tenant/site scope +
  role gate as WP2, independently on the write path (hard backend boundary per
  ADR-0037, not a frontend affordance).
- Response closes the loop at the point of action (hard gate 2): returns the new
  NetBox state + the reconcile expectation (what will converge it and how to watch),
  and the action lands in the Changes/Activity record via `request_id`.
- **Acceptance gate:** tag flipped in NetBox with C5 audit trail; out-of-scope or
  under-privileged caller gets a hard 403/404 with no side effect; reconcile loop
  observed converging on a sandbox env.

### WP3 — Frontend: Media Workloads page
- `frontend/src/pages/MediaWorkloads/` + `Sidebar.tsx` entry **Media Workloads**,
  visible to `engineer` + `admin` (v1 gating per WP2); route `/media-workloads`.
- MVP content per ADR-0037: instance count + placement, filter by function, live
  status overlaid. No flow graph, no composition canvas (explicitly deferred in
  ADR-0037 §8).
- The one consequential action ("clear for deployment", backend in WP2b) gets
  graduated friction + impact preview per Constitution hard gate 3, a required
  reason field (the C5 quartet), and closes its loop at the point of action
  (hard gate 2) — showing the WP2b response's new state + reconcile expectation.
- No disruptive list reflow on poll when semantic state is unchanged (hard gate 5 —
  the `/changes` anti-pattern must not be repeated here).

### WP4 — MXL Flows retirement
- Fold the live-flow/test-pattern view into Media Workloads as a **per-instance
  detail panel**, reusing the `src/dmf_cms/mxl.py` status-sidecar fan-out
  (`GET /status`, `GET /preview.jpg`) — the endpoint config
  (`DMF_CONSOLE_MXL_ENDPOINTS`) and graceful degradation logic carry over unchanged.
- `/mxl-flows` route → redirect to `/media-workloads`; delete `MxlFlows.tsx` and its
  nav entry; update `dmf-cms/docs/mxl-flows-page.md` to point at the new home.
- Sequencing note: if WP4 lands before #17's WP6 provides live sidecar endpoints, the
  detail panel simply shows the (already-supported) unreachable state — no hard
  dependency either way.

## 4. Explicitly out of scope (→ #174 or later)
- The 4-rail nav restructure (Workspace/Facilities/Media Workloads/Catalog), the
  Workspace "are we OK?" core, Activity two-lane merge — all #174.
- Route renames beyond adding `/media-workloads` (+ the `/mxl-flows` redirect).
- Localization pass (`zh-Hans`/`zh-Hant`) — the Constitution treats locales as
  co-equal, but the i18n scaffold is a separate decision; wording changes here keep
  strings centralizable.
- Per-user NetBox tokens, flow/composition graph, cross-host fabrics views
  (ADR-0037 §8 deferrals stand).

## 5. Open questions for the cross-check
- **OQ-1 (RESOLVED in WP2, 2026-07-03 review round):** gating is `engineer`+`admin`
  role-based in v1 (matching the code's four `dmf-console-*` groups and the IA §7
  matrix); the dedicated `media-engineers` Authentik group is a recorded follow-on
  with #174. Challenge if role-gating v1 breaks a tenancy assumption ADR-0037 needs
  preserved from day one.
- **OQ-2:** Does the live-status join belong in the backend response (one round-trip,
  server-side truth) or as a second async fetch (page renders inventory fast, status
  hydrates)? Constitution Art. 1 (provenance/freshness shown) applies either way.
- **OQ-3:** WP1 touches `MxlFlows.tsx` copy that WP4 then deletes — worth doing both,
  or land WP1 without the MxlFlows copy fix if WP4 follows within the same release?

## 6. Verification plan
- `npm run build` (strict tsc) + existing vitest suite green; new endpoints covered by
  FastAPI tests — read: non-member 403/404, member gets scoped rows only; write
  (WP2b): C5 fields required, out-of-scope caller rejected with **no NetBox
  side-effect**, tag flip asserted against a NetBox fixture.
- Manual: page renders against a live env with NetBox instances (the #17 plan's WP5
  provides the data); degraded-state render with NetBox stopped.
- Wording: grep-proof that no default-level string contains layer/vertical/lifecycle
  system-tier terms; Glossary entries added.
- Constitution §3 hard-gates checklist walked for the new page before release.

## 7. Delivery & commit plan
- Code PRs in `dmf-cms` referencing **`refs dmfdeploy/dmfdeploy#173`** (fully
  qualified; bare `#N` targets the wrong repo). Umbrella doc PR flips this plan's
  frontmatter `draft → executed` when the completing dmf-cms PR lands, and closes
  #173 in the same change (manual close — cross-repo `Closes` does not auto-close).
- Suggested slicing: WP1 (wording) as its own small PR; WP2+WP3 (read + page) together;
  WP2b (write + reconcile proof) next; WP4 last.
- dmf-cms release: next minor after landing (page gated, so safe to ship dark).

## 8. References
- `../decisions/0037-media-workloads-netbox-instance-inventory.md` — the model this implements.
- `DMF Media Workloads — NetBox-Driven Media Function Inventory Plan 2026-06-03.md` — superseded predecessor (D4 spec).
- `../design/DMF Console UX Constitution 2026-05-25.md` — Art. 3 + §3 hard gates.
- `../design/DMF Console Information Architecture 2026-06-23.md` — §9 label map; #174 implements the rest.
- `DMF MXL Single-Node Revival Plan 2026-07-03.md` (#17) — WP6 consumer of this page.
