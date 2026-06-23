# DMF Console — Information Architecture

**Date:** 2026-06-23 · **Last revised:** 2026-06-23 (first pass, after codex cross-check)
**Status:** **Design spec** (downstream of the UX Constitution). Resolves the Constitution's §7 Open Question #1 (the concrete role set + OIDC-group mapping) and adds the navigation / page model the Constitution deliberately left to a downstream doc. Advisory like its parent, except where it restates an existing §3 hard gate.
**Applies to:** `dmf-cms` (the operator console). Governs top-level navigation, page boundaries, the Workspace widget model, and role-gated visibility.
**Audience:** every agent and human who designs, builds, reviews, or words the console's navigation and pages.
**Reads with:** [UX Constitution](DMF%20Console%20UX%20Constitution%202026-05-25.md) (parent) · [Alarm Philosophy](DMF%20Console%20Alarm%20Philosophy.md) · [Dangerous-Action Spec](DMF%20Console%20Dangerous-Action%20Spec.md) · [Audit / Event-Log Spec](DMF%20Console%20Audit%20and%20Event-Log%20Spec.md) · [Glossary](DMF%20Console%20Glossary.md) · `docs/decisions/architectural-commitments-v1.md` (frozen non-goals).

---

## 0. Why this document exists

The Constitution states *principles* and names the operator model (three axes: Role · Level · Locale) but leaves the **navigation structure, the concrete role set, and the widget taxonomy** as open questions (Constitution §7). Meanwhile the live console has grown **nine flat routes with no spine** — `Overview, Monitoring, MXL Flows, Facility, Workflow, Catalog, Changes, Admin, Settings` — several of which are different lenses on the same underlying thing, and the role-gated Overview variants are mostly placeholders.

This document gives the console a spine: **four primary rails + a small set of role-gated secondaries**, a Workspace built directly on the North Star, and an explicit role→surface matrix. It is intentionally modest in what it asks v0.1 to *build*, and explicit about what it only *names*.

> **North Star (inherited).** *An operator who knows nothing about Kubernetes, Ansible, or NMOS internals can look at the console and always know three things: **is the facility healthy, what just changed, and what — if anything — they need to do.*** The Workspace (§4.1) is the literal home of those three questions.

---

## 1. Spine principle — *name the goal, build only v0.1*

The operator has three forward goals for the platform, and wants the console's *shape and vocabulary* to point at them:

1. **Fleet view** — one console aware of many facilities.
2. **Full create-in-console** — design / plan / provision environments from `dmf-cms`.
3. **Third-party "companion integrations"** — an ecosystem of optional media functions and app-services, native *and* third-party.

All three are **frozen non-goals for v0.1**: `architectural-commitments-v1.md` names single-node / Flypack as the proof surface, with multi-node / cloud / **federation** explicitly out, and instructs new work to follow the committed layout rather than reshape foundations.

**The discipline this spec adopts (after codex cross-check):**

> Future goals appear in the console as **labels, copy, and non-precluding structure only.** They must **never** shape a v0.1 route, data model, or component contract.

The line, drawn concretely:

| Allowed in v0.1 (signposting) | **Not** allowed in v0.1 (smuggled architecture) |
|---|---|
| A plural rail label ("Facilities") | A `facilities[]` collection, a facility-id in the route/path, a multi-facility selector wired to data |
| Copy/framing that says "companion integrations" | A third-party plugin/registry contract, a vendor-extension API |
| A `Widget` contract designed so a future free canvas is additive | A persisted server-side per-user layout (that is a backend change — see §6) |
| A page that *could later* gain a Create action | Create / provision / teardown wiring for environments or sites |

When in doubt, the rule is: **v0.1 builds exactly what single-facility, view-leaning operation needs; everything goal-shaped is text, not structure.**

---

## 2. The axes are unchanged — curation is a *preference*, not a fourth axis

The Constitution is explicit (§1): **three independent axes — Role, Level, Locale — and keeping them separate is what stops the design from sprawling.** This spec does **not** add a fourth.

Widget personalization (show / hide / reorder, §6) is a **per-user preference**, persisted by the **same mechanism as Level and Locale** — it belongs to the Workspace widget system, not to the operator model. It changes *which optional widgets you see and where*, never *which surfaces or actions exist for you* (that is Role) nor *how much detail they show* (that is Level).

| Axis | Scopes | Mechanism |
|---|---|---|
| **Role** | which surfaces/actions exist at all | OIDC groups via Authentik (§7) |
| **Level** | depth of detail (default ↔ expert) | persisted per-user preference |
| **Locale** | language & cultural formatting | persisted per-user preference (`en` · `zh-Hans` · `zh-Hant`) |
| *Widget layout* *(not an axis)* | arrangement of optional widgets around a fixed core | per-user preference, client-side (§6) |

---

## 3. The navigation model

**Primary rails (always the same four; Role gates whether each is populated):**

| Rail | Icon | Replaces / folds | v0.1 scope (single-facility, no new backend) | Named-only future |
|---|---|---|---|---|
| **Workspace** | 9-square app-grid | `Overview` (4 role variants) | pinned health/alarm core + "recent changes" + bounded personalization | full curated canvas |
| **Facilities** | sites | `Facility` (singular) | **this facility only**; drill to device / substrate (NetBox `dcim.site`); **no create** | fleet switcher, full create-in-console |
| **Media Workloads** | flows | `MXL Flows` | active / provisioned media functions + status | interconnection diagram, license status |
| **Catalog** | catalog | `Catalog` | native media functions; *"companion integrations"* framing in copy | third-party integration directory |

**Role-gated secondaries** (present only for roles that own them, per §7): **Activity** (§5), **Monitoring**, **Licenses**, **Users**, **Site settings**, **Admin**, **Settings**.

**Vocabulary tier check (Constitution Art. 3).** Rail labels use the operator's / industry's language, not the DMF-internal EBU ontology. "Facilities", "Media Workloads", "Catalog", "Monitoring" are operator-native or industry-standard; no rail is labelled with `Layer 5`, `orchestration`, `configure`, or other layer/vertical/lifecycle jargon (the §4 anti-pattern that leaked `Layer 5 · orchestration · configure` to an operator). The EBU taxonomy stays an expert/internal organizing idea, not nav copy.

**Why four, and why these.** The nine current routes collapse cleanly: `Overview → Workspace`; `MXL Flows → Media Workloads`; `Workflow` + `Changes → Activity` (two lanes, §5); `Catalog` keeps; `Facility → Facilities`; `Monitoring / Admin / Settings` become role-gated secondaries. Nothing is lost; four redundant lenses become one each. (codex judged this collapse "mostly defensible" — the care is all in §5's two-lane rule and §1's signposting line.)

---

## 4. The primary rails in detail

### 4.1 Workspace — the North Star, made literal
Replaces the four placeholder Overview variants (`pages/overview/*Overview.tsx`). It answers the three North-Star questions in one screen:

- **"Is the facility healthy?"** → a **pinned, non-removable health/alarm core** (§6.1) — severity-classified count tiles + a live *Current Problems* list with **Ack** (Art. 4), updating **in place** (Art. 5).
- **"What just changed?"** → a **pinned "recent changes" widget** — a read of the same audit/history the Activity § History lane shows (Art. 2/10, correlated by `request_id`). First-class, never diluted.
- **"What do I need to do?"** → actionable conditions surface as such in the core (Art. 4 response classes), distinct from mere status.

Around that fixed core, **bounded personalization** (§6.2) lets each role arrange a *bounded set* of optional widgets. Role still decides which widgets exist at all (Art. 1/6).

The 9-square app-grid icon is chosen as a **launcher-into-operations** metaphor; it must not pull the page toward a generic-SaaS "blank canvas" feel — the Constitution's reframe is "control room, **not** a SaaS app" (Constitution §0). The pinned core enforces that.

### 4.2 Facilities — single-facility now, fleet-*labelled*
Drill into **this** facility: sites, devices, substrate (NetBox `dcim.site` is the model). View / inspect; **no create or provision in v0.1** (that is `dmf-init` + `dmf-env`'s job today, and full create-in-console is a frozen non-goal).

> **Data-model guard (codex P1, restating a frozen non-goal).** v0.1 routes and API shapes are **single-facility**: no `facilities[]` collection, no facility-id in the path, no multi-facility selector bound to data. The plural label is presentational signposting only. A plural *data model* or a multi-facility UI surface would cross the federation line and is out.

Any future Create/provision action is a **dangerous action** (Art. 7) — it will require the consequence-class friction + impact preview + the C5 quartet when it is eventually designed; this spec only notes the seam, it does not build it.

### 4.3 Media Workloads — what's running
Lists media functions that are **active / provisioned** (NetBox `ipam.Service` + a `lifecycle:active` lens, joined to the catalog), with status that honours Art. 1 provenance (observed vs requested) and Art. 5 (in-place updates).

- **v0.1:** the list + per-function status/health.
- **Named-only future:** the **interconnection diagram** (EBU Layer-4 Media-Exchange / flow-domain territory — deferred) and **license status** (not yet modelled). The in-flight `nmos-crosspoint` work (Phase 1, visible-only) is the natural seed for the interconnection view; this spec flags that they must converge rather than diverge (§9).

### 4.4 Catalog — native now, "companion integrations" in copy
The set of media functions **available** to deploy (today: native, from `dmf-media/catalog/` + `dmf-runbooks` launchers). Keeps the existing route name **Catalog** for v0.1 honesty — there is no third-party ecosystem yet (no plugin / signing / distribution model; that is v2+).

The "companion integrations" philosophy lives in **copy and framing** only: entries may be *described* as integrations, and the page is *shaped* so a future third-party section is additive. No third-party registry, plugin contract, or vendor-extension API in v0.1.

---

## 5. Activity — one rail, two distinct lenses (do not collapse)

`Workflow` and `Changes` fold into a single **Activity** rail, **but the two meanings stay separate** (codex P2 — collapsing them into a generic job feed would erase the operator's change-history lens and weaken Arts. 2, 5, 10):

- **History lane — "what just changed."** The audit / event-history lens (North Star, Art. 2/10), correlated by `request_id`, requester distinct from executor. First-class; also the source for the Workspace "recent changes" widget (§4.1).
- **Jobs lane — "what is running / launchable."** The action / launch surface (today's `Workflow`).

**Merge condition (binding):** the merge is permitted **only if the UI keeps separate Jobs vs History subviews**; otherwise `Changes` stays as its own (expert/history) rail. A single undifferentiated stream is not acceptable. Whether Activity is one rail with two lanes or two rails is the one open IA decision (§10).

---

## 6. The Workspace widget model

### 6.1 The pinned core (non-removable)
Inspired by the Zabbix overview pattern the operator referenced: **severity-classified count tiles** + a live **Current Problems** list with an **Ack** action. Adapted to DMF canon:
- Severity classes come from the **Alarm Philosophy** (Art. 4 classes + lifecycle), **not** Zabbix's literal set.
- The list updates **in place** — keyed reconciliation, no collapse-and-rebuild (Art. 5; the `/changes` anti-pattern is the regression bar).
- Status carries **provenance** (Art. 1): live vs stale vs last-known; observed vs requested.
- The core is **pinned and non-removable** so "are we OK?" is always answered at a glance (Art. 6). Personalization happens *around* it, never *through* it.

### 6.2 Bounded personalization (v0.1)
- Each role gets a **sensible default layout.**
- The user may **show / hide / reorder a bounded set** of optional widgets — **not** a free drag-anywhere canvas (that is the named-only future).
- **Persistence is client-side only (`localStorage`); no backend change in v0.1** (codex P2). This is stated explicitly because the v0.1 implementation budget is "no new backend": if per-user *server-side* layout persistence is ever wanted, that is a backend change and is **deferred**, not smuggled in under this spec.

### 6.3 The `Widget` contract
Define a single widget contract so the future free canvas is **additive, not a rewrite**:
`{ id, role-availability, default size, data source, refresh discipline (in-place, interval/backoff per Art. 4/5), default-vs-expert content }`.
Pinned-core widgets implement the same contract but declare themselves non-removable.

---

## 7. Role set + OIDC-group → surface matrix (closes Constitution §7 OQ#1)

The console keeps its existing four roles (`api/types.ts`: `viewer | operator | engineer | admin`), derived from Authentik OIDC groups (Art. 1/10). Roles are a **small bounded set**; Role gates *surface existence*, Level gates *depth within* (Art. 3).

| Surface | viewer | operator | engineer | admin |
|---|:--:|:--:|:--:|:--:|
| **Workspace** | ✓ (read) | ✓ | ✓ | ✓ |
| **Facilities** | ✓ (read) | ✓ (read) | ✓ | ✓ |
| **Media Workloads** | ✓ (read) | ✓ | ✓ | ✓ |
| **Catalog** | — | ✓ | ✓ | ✓ |
| **Activity** (History / Jobs) | History (read) | ✓ / ✓ | ✓ / ✓ | ✓ / ✓ |
| **Monitoring** | ✓ (read) | ✓ | ✓ | ✓ |
| **Licenses** | — | — | ✓ (read) | ✓ |
| **Users** | — | — | — | ✓ |
| **Site settings** | — | — | ✓ (read) | ✓ |
| **Admin** | — | — | — | ✓ |
| **Settings** (own prefs) | ✓ | ✓ | ✓ | ✓ |

Notes:
- ✓ vs ✓ (read) distinguishes *can act* from *can only view*; the precise action set per surface is governed by Art. 7 consequence classes, not by this table.
- The matrix is the **default mapping**; the authoritative source is the Authentik OIDC-group → role binding. `groups[]` already exists on `UserIdentity` but is unused in the UI today — wiring it is part of the implementation, not this spec.
- **Current-phase reality (Constitution Art. 10 footnote / Identity Model §1):** multi-user is deferred; `ops-admin` is single-member and undifferentiated today. The four roles are the *target* model the UI should be built against; the live deployment may collapse them until multi-user lands. The matrix must not be read as a claim that differentiated multi-user RBAC is operational now.

---

## 8. Touch / fullscreen / field-use — an explicit, separate decision

This is a **new requirement, not inherited canon** (the Constitution mandates keyboard/no-mouse as first-class in Art. 11 but is silent on touch/mobile/fullscreen). It is recorded here as its own decision item so it does not silently expand scope (codex P3):

- **Responsive + touch tap targets** that **coexist with** keyboard-first operation (Art. 11) — touch is *additive*, never a replacement; a control room may be a keyboard, gloves, or a panel.
- **PWA / `manifest.json` / kiosk / fullscreen mode is explicitly DEFERRED** unless the operator elects it as a discrete v0.1 line item. There is no manifest or service worker today; adding one is a deliberate decision with its own scope, not a free rider on the nav restructure. (Note: any PWA work must still honour Art. 15 — self-contained, air-gap-ready, zero runtime external dependency.)

---

## 9. Migration map (current → target)

| Current route / label | Target |
|---|---|
| `/` Overview (4 role variants) | **Workspace** (pinned core + recent-changes + bounded personalization) |
| `/mxl-flows` MXL Flows | **Media Workloads** |
| `/workflows` Workflow | **Activity** → Jobs lane |
| `/changes` Changes | **Activity** → History lane (or own rail — §10) |
| `/catalog` Catalog | **Catalog** (unchanged name) |
| `/facility` Facility | **Facilities** (single-facility; label plural) |
| `/monitoring` Monitoring | **Monitoring** (role-gated secondary) |
| `/admin` Admin | **Admin** (role-gated secondary, unchanged) |
| `/settings` Settings | **Settings** (role-gated secondary, unchanged) |
| *(new, role-gated)* | **Licenses**, **Users**, **Site settings** |

Implementation touch-points (named for the follow-on, not built here): `components/Sidebar.tsx` (`allNavItems` + icons), `App.tsx` (routes), `pages/overview/*`. No new backend; reuse existing `.panel` / `.metric-card` / `.data-table` and Lucide icons.

---

## 10. Open decisions (to settle before / during implementation)
1. **Activity shape:** one rail with two lanes (History / Jobs) vs. keeping **Changes** as its own rail. (§5 merge condition holds either way.)
2. **Touch / field-use depth:** minimal responsive only, or opt into a PWA / kiosk shell as a discrete v0.1 item (§8)?
3. **`nmos-crosspoint` convergence:** confirm the in-flight Phase-1 (visible-only) crosspoint work is the seed for the Media Workloads interconnection view (§4.3), so the two do not diverge.
4. **Licenses model:** Licenses is named here but unmodelled; its first concrete form (NetBox custom fields vs a dedicated entitlement object) is out of scope for this spec.

---

### Relationship to the Constitution
This spec is **downstream** of the UX Constitution and subordinate to it: where the two appear to differ, the Constitution governs and this spec must be corrected. It **resolves** Constitution §7 Open Question #1 (role set + OIDC mapping, §7 here) and **supplies** the nav/page model the Constitution left open (§6 there). It introduces **no new hard gate**; it restates existing gates (Arts. 1, 2, 4, 5, 6, 7) as they bind navigation and the Workspace.

### Revision history
- **2026-06-23 (pass 1)** — initial IA: spine principle ("name the goal, build only v0.1"), four primary rails (Workspace / Facilities / Media Workloads / Catalog), Activity two-lane rule, Workspace pinned-core widget model + client-side bounded personalization, role→surface matrix (closes Constitution §7 OQ#1), touch/PWA recorded as a separate deferred decision. Drafted after an adversarial codex cross-check (VERDICT: CHANGES-NEEDED → all six findings folded in: dropped a proposed fourth "Curation" axis, hardened the Facilities single-facility data-model guard, preserved the Changes history lens, pinned widget persistence to client-side-only, and split out the touch/PWA decision).
