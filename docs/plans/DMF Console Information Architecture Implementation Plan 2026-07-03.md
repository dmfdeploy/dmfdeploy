---
status: executed
date: 2026-07-03
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/174
---
# DMF Console Information Architecture Implementation Plan (2026-07-03)

> **STATUS: EXECUTED (2026-07-05).** All four WPs landed in dmf-cms across three
> PRs, each behind an adversarial codex gate:
> [#18](https://github.com/dmfdeploy/dmf-cms/pull/18) (WP1+WP4 nav spine +
> Workspace home + overview retirement; GATE-20 PASS, two P3s folded —
> Settings as ungated secondary, MXL live-view endpoints behind the ADR-0037
> surface gate), [#19](https://github.com/dmfdeploy/dmf-cms/pull/19) (WP3
> Activity two-lane rail + console-local C5 lane; GATE-21 PASS, zero findings),
> [#20](https://github.com/dmfdeploy/dmf-cms/pull/20) (WP2 Workspace
> "are we OK?" core; GATE-22 round 1 CHANGES-NEEDED → all three findings
> folded — firing-only alerts, full-label-set row identity, `watchdog-missing`
> reason token — GATE-22-R2 PASS). Release: **dmf-cms 0.13.0** (§7 wrote
> "plausibly 0.12.0", but 0.12.0 was earned by #17's Media Workloads deploy).
> The #173 recorded follow-ons landed here: the `media-engineers` group is
> seeded by the console's own Authentik bootstrap (not a dmf-infra blueprint)
> and consumed as the first frontend `groups[]` gate; the console-local
> activity lane carries the clear-for-deployment C5 record.
> Open-question outcomes: OQ-1 one-rail-two-lanes shipped (binding subview
> separation honoured); OQ-2 stood (no Ack of any kind); OQ-3 unchanged —
> nmos-crosspoint stays a separate link-out surface until Phase 2
> switchability, with the Media Workloads detail panel as the convergence
> seam; OQ-4 resolved as "every actually-retired path" = `/facility`,
> `/workflows`, `/changes` (+ the kept `/mxl-flows`), SPA-level redirects
> (backend shell serves deep links; HTTP-permanence explicitly waived at
> GATE-20). Recorded v0.2 seams: key/clear the console-local activity records
> per subject/env/session when multi-user lands (GATE-21 note); frontend
> vitest suite is local-only until wired into CI. Live-env deploy of 0.13.0
> is a separate operator-authorized step (630→650), not part of this plan.
>
> Original preamble (authoring, 2026-07-03): documents-only round; no dmf-cms
> edits yet. Second of two console plans. Implements the 4-rail Information
> Architecture and the Workspace **"are we OK?"** core specified in
> `../design/DMF Console Information Architecture 2026-06-23.md`. **Sequenced
> after** `DMF Console Wording and Media Workloads Page Plan 2026-07-03.md`
> (#173) and after #166's WP-B/WP-C (recording rules + alert suite) land — the
> Workspace core consumes those signals.

**Component:** `dmf-cms`. Doc lives in the umbrella per convention.
**Governing design docs:** the IA doc (above) — this plan turns its spec into work
packages, it does not re-litigate it; `../design/DMF Console UX Constitution
2026-05-25.md` (§3 hard gates); `DMF Are-We-OK Sandbox Observability and Alerting Plan
2026-06-24.md` (#166) — the signal source.

---

## 1. Context

The console has nine flat routes and four placeholder role-variant Overview pages
(`frontend/src/pages/overview/*Overview.tsx`); there is no pinned health surface, so
the Constitution's north-star question — *"is the facility healthy, what just changed,
what do I need to do"* — has no home. The IA doc (2026-06-23) specifies the target:
four primary rails (**Workspace / Facilities / Media Workloads / Catalog**) plus
role-gated secondaries, with Workspace carrying a non-removable "are we OK?" core.
This plan makes it executable now that its two prerequisites are planned: the Media
Workloads rail (#173) and the alert/recording-rule signals (#166).

## 2. Dependency ordering (per-WP, not blanket)

- **WP2 (Workspace core) is hard-gated on #166 WP-B/WP-C** — it reads `ALERTS` +
  recording rules via the existing Prometheus client (`src/dmf_cms/prometheus.py`).
  Building the core against empty rule files would fake health (Constitution hard
  gate 1: no uncertainty presented as certainty).
- **WP1 + WP4 (nav spine, overview retirement) are gated on #173 only** — the Media
  Workloads rail must exist as a page; nothing in redirects or spine swap needs #166.
- **WP3 (Activity)** has no external dependency beyond this repo.
- Recommended landing order stays WP1+WP4 → WP3 → WP2, but only WP2's gate is hard.

## 3. Work packages

### WP1 — Nav spine: 4 rails + role-gated secondaries
- Replace the flat `Sidebar.tsx` list with the IA §4 rail set: **Workspace** (`/`),
  **Facilities** (`/facilities`, absorbing `/facility`), **Media Workloads**
  (`/media-workloads`, from #173), **Catalog** (`/catalog`).
- Secondaries per IA §7 role model: Monitoring, Admin, Settings, Activity — visibility
  from role + `groups[]` (first structural consumer of the groups claim after #173's
  page gate). The IA's remaining named secondaries — **Licenses, Users, Site
  settings** — are **named-deferred**: the rail contract reserves them (IA §3/§7
  stands un-narrowed) but no page is built in this plan; Users/Site settings remain
  inside Admin/Settings until their own slices.
- Route migration map per IA §9 with permanent redirects from every retired path
  (`/facility`, `/workflows`, `/changes`, old `/` overview variants). No bookmark
  breaks.

### WP2 — Workspace "are we OK?" core
- Pinned, non-removable top section of `/`: severity-classified count tiles + a live
  **Current Problems** list (Zabbix-inspired per IA §6.1), consuming
  `ALERTS{alertstate="firing"}` grouped by the #166 severity labels. **No Ack in v1**
  (review decision, 2026-07-03): a browser-local Ack is an open loop — invisible to
  other operators/sessions — violating Constitution Arts. 2+4. Rows get non-mutating
  **Open details / Investigate** actions only; a real acknowledge (persisted, audited,
  `request_id`-correlated, cross-session) arrives when the Alarm Philosophy spec
  graduates from stub.
- **Recent-changes widget** (the IA's third North-Star question, "what just changed"):
  a pinned read-only widget on Workspace showing the last N Activity/History entries,
  linking into WP3's History lane — so Workspace answers all three questions, not two.
- Freshness/provenance shown on the tiles (hard gate 1); zero-alert state renders an
  explicit verified-green, not an empty list (Art. 6: "are we OK?" answered at a
  glance, including "yes").
- Degraded sources are content: Prometheus unreachable → the core says so and shows
  last-known state with age (never a silent green, never a raw error — hard gates 1+4).
- No disruptive reflow on poll when semantic state is unchanged (hard gate 5; the
  measured `/changes` anti-pattern).

### WP3 — Activity: two lanes, one rail
- Merge Workflows (`/workflows`) + Changes (`/changes`) into **Activity** with
  **Jobs** and **History** lanes per IA §4; correlation by `request_id` (the audit
  spec's key) so a job links to the change it caused.
- Carries the loop-closure contract (hard gate 2): anything started from the console
  surfaces its outcome here *and* at the point of action.

### WP4 — Overview retirement
- Delete the four placeholder `pages/overview/*Overview.tsx` variants; Workspace is
  the single role-aware home (content varies by role/groups, not by page fork).

## 4. Out of scope
- Alarm lifecycle/classification (ack/shelve/escalate semantics) — blocked on the
  `DMF Console Alarm Philosophy` design stub graduating; WP2 ships raw-alert tiles
  with **non-mutating detail actions only** (no Ack of any kind until the persisted,
  audited lifecycle exists).
- Localization scaffold; touch/PWA depth (IA §10 open decision — carried as OQ-3).
- Any Grafana-side work (that is #166 WP-E/WP-G).

## 5. Open questions for the cross-check
- **OQ-1 (from IA §10):** Activity as one rail with two lanes vs two secondaries —
  this plan picks one-rail-two-lanes; challenge if the Jobs/History correlation story
  is weaker than two clean lists.
- **OQ-2 (RESOLVED, 2026-07-03 review round):** no Ack in v1 — a non-persisted Ack is
  an open loop (Arts. 2+4); WP2 ships non-mutating detail actions only. Persisted Ack
  lands with the Alarm Philosophy spec.
- **OQ-3 (from IA §10):** nmos-crosspoint convergence — does the interconnection view
  land under Media Workloads (per #173's detail-panel pattern) or stay a separate
  surface until Phase 2 switchability exists?
- **OQ-4:** Redirect depth — permanent redirects for all nine legacy routes, or only
  the four with plausible bookmarks (`/facility`, `/workflows`, `/changes`,
  `/mxl-flows`)?

## 6. Verification plan
- `npm run build` (strict tsc) + vitest green; router tests assert every legacy path
  redirects.
- Workspace core: fixture-driven states (0 alerts / warning-only / critical /
  Prometheus down) each render the specified verdict, freshness stamp, and no raw
  errors — walked against the §3 hard-gates checklist.
- Live check on a sandbox env after #166 lands: induce a warning-tier alert
  (per #166's graceful-degradation drill) and confirm tile + Current Problems entry +
  recovery.
- IA §3 vocabulary tier check re-run on the final rail labels.

## 7. Delivery & commit plan
- Code PRs in `dmf-cms`, referencing **`refs dmfdeploy/dmfdeploy#174`**; the completing
  PR flips this frontmatter `draft → executed` and closes #174 manually (cross-repo
  `Closes` does not auto-close).
- Suggested slicing: WP1+WP4 (spine swap, one PR), WP2 (core), WP3 (Activity).
- This is the release that plausibly earns `dmf-cms 0.12.0`.

## 8. References
- `../design/DMF Console Information Architecture 2026-06-23.md` — the spec this executes.
- `../design/DMF Console UX Constitution 2026-05-25.md` — hard gates cited per-WP.
- `DMF Are-We-OK Sandbox Observability and Alerting Plan 2026-06-24.md` (#166) — signal source.
- `DMF Console Wording and Media Workloads Page Plan 2026-07-03.md` (#173) — prerequisite rail.
- `../design/DMF Console Audit and Event-Log Spec.md` — `request_id` correlation (WP3).
