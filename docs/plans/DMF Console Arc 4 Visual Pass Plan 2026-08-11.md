---
status: active
date: 2026-08-11
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/347
---
# DMF Console Arc 4 Visual Pass Plan (2026-08-11)

> **STATUS: ACTIVE.** Arc 4 of the demo-journey UI track (#347). Owns the
> **visual redesign of the demo path** and the supporting doc work. Defines no
> new feature scope: Arc 3 (Operate scheduler) and explicit-facility selection
> remain out. Where this plan and the Console UX Constitution disagree, the
> Constitution wins.

## 1. Why

Arcs 1, 2a and 2b shipped in `dmf-cms` 0.19.0–0.20.0 and are live. The operator's
2026-08-11 review of the live build found the result unfilmable — *"less is more, we need a
minimal modern design"* — and the recording is #347's exit criterion. Making the console
filmable is therefore on the critical path to the only outcome that counts: an outsider
completing the journey unaided.

A supplied mockup informs the visual register. It is **inspiration, not authority** — the
ADRs and the specs in `docs/design/` win wherever they disagree.

## 2. Operator rulings

1. Wordmark reverts to plain and appears on the Workspace/home view only; the logo glyph
   anchors elsewhere. No decorative colour strip anywhere.
2. The "Workspace" breadcrumb is removed entirely.
3. Create becomes a step-by-step wizard; studio name and slug form a first step of their own.
4. The lifecycle rail moves into the header, scoped to workload detail routes.
5. The current step's primary action is promoted into the header — only where exactly one
   eligible primary action exists at runtime.
6. Green stays "ok". A different accent carries primary action.
7. Operate sits inline at the end of the rail, visually distinct.
8. Stage names stay visible; all EBU taxonomy framing leaves default level.
9. The sidebar stays icon-only.
10. Workspace keeps both pinned widgets; health leads with one calm line.
11. Reach is the shell plus the demo path. Admin, Settings, Monitoring and Activity keep
    their layouts and inherit the palette.

Rulings 4, 7 and 8 soften Arc 1 decisions (rail as fully-painted primary nav;
Control:Operate outside the ordinal). That is deliberate and must be stated in the PRs
rather than left to read as drift.

## 3. Binding constraints

- **Art. 11** — colour is never the only signal: colour plus shape/icon plus text plus
  position, legible with colour stripped. A hover-only `title=` tooltip does not satisfy it.
- **Hard gate 2** — an action closes its loop at the point of action. The topbar transient
  region is supplemental only, with a 6-second TTL, and its own module docstring states it is
  never the authoritative record. It cannot discharge this gate.
- **Hard gate 1** — nothing stale presented as current; fail-closed stays fail-closed.
- **Destructive class** — impact preview, typed confirmation, stated rollback.
- **Console IA spec §6.1** — Workspace's health core and recent-changes widget are pinned and
  non-removable.
- **ADR-0015** — the login screen stays one-click passkey. Out of scope.
- **Art. 15** — no runtime dependency on an external host; any new font ships baked in.

**Accepted advisory debt, recorded rather than claimed as met:** Art. 12 wants three co-equal
locales designed and tested from day one. No i18n library exists in the frontend today, and
this pass adds and changes English literals without a translation seam. CSS `text-transform`
addresses literal casing only, not new copy. This pass does not close that gap.

## 4. Work packages

| WP | Repo | Summary |
|---|---|---|
| 0 | umbrella | This doc + issues #378 and #379 |
| 1 | dmf-cms | Prerequisite: three fail-closed corrections on the shipped purge affordance (#378) |
| 2 | dmf-cms | Design tokens, stage-palette relocation, typed route-scoped header slot |
| 3 | dmf-cms | Workload surfaces: rail, header action, create wizard (atomic with WP-7) |
| 4 | dmf-cms | List, tile and facility surfaces |
| 5 | dmf-cms | CI frontend gate + accessibility sweep |
| 6 | dmf-cms | Release 0.21.0 and deploy |
| 7 | umbrella | Glossary amendment (atomic with WP-3) |
| 8 | umbrella | Runbook rewritten incrementally (#379) |
| 9 | — | Record the demo |
| 10 | — | Named outsider completes the journey |

### WP-1 — prerequisite, ahead of all visual work

Tracked as #378. Three gates missing from the Finalise stage's delete-permanently
affordance, all live today: completeness (the grouped read can be 200-with-degraded and
still incomplete), authorization (the list admits a group the purge endpoint's role ladder
does not), and entity identity (the synthetic unassigned bucket resolves to a detail route
that offers a control the backend refuses). Three discriminating tests, each mutated to
prove it fails without its guard. Affordance control only — the server stays authoritative.

### WP-2 — tokens and the header slot

Freeze exact token values and contrast targets rather than leaving the accent to the
implementer. Relocate the six lifecycle-stage colours out of the rail component into tokens
plus a `stagePalette` module, copied byte-for-byte. Add a micro-label size token and a
tile-grid class using `auto-fill` — not `auto-fit` — so a one-item grid renders one small
tile rather than a stretched square. Introduce a typed, route-scoped header slot with an
explicit layout contract (height, overflow, narrow and laptop behaviour); register nothing
into it in this package.

### WP-3 — workload surfaces

Workload detail registers the rail and its header action into the slot, because it already
owns steps, selection, locked reasons, job-in-flight state and slug; rendering a second rail
from the topbar would duplicate the derivation the lifecycle module exists to keep single.
Paint the active stage only. Strip taxonomy from default level, asserted against the
default-level accessibility tree separately from disclosure contents — collapsed `details`
elements remain in the DOM, so a whole-DOM grep cannot express this. The header action comes
from the runtime action model and only when exactly one eligible primary action exists; the
Provision step renders a deploy control per eligible catalog entry, so a source-level count
proves nothing. When an action is promoted, its whole loop moves with it. The create wizard
gets a non-persisted, tab-lifetime draft store, cleared on successful provision, explicit
cancel, and logout — session storage would contradict the draft-loss warning the page
renders.

### WP-4 — list, tile and facility surfaces

The shared tile is a non-interactive container with a sibling primary link and an optional
actions slot, so a future menu is never an interactive descendant of an anchor. Badges
require tone, icon and label together. Facility detail regroups four single-row tables into
two rows of two with each panel's internals byte-for-byte unchanged. One redundant subtitle
is deleted outright; the other stays visible or moves behind a focusable, tappable info
affordance — not a `title=` tooltip.

### WP-5 — the CI gap

No workflow in the console repo currently references npm, node, vitest or the frontend, and
the vitest run is not a typecheck or a build. A frontend that does not compile can reach
`main` with auto-merge armed. Add install, test and build to CI, and run the Python suite
from the repo's own virtualenv after clearing the built static app. CI must fail on a
deliberately introduced type error.

### WP-10 — the forcing function

Name the outsider before WP-2 starts. Their failures are the only input allowed to unlock
new scope.

## 5. Out of scope

Per-tile Terminate (a second destructive entry point needs a shared purge controller
extracted from the Finalise stage, since the dispatch hook returns a 202 and performs no
invalidation — the hardened lifecycle lives in the stage); Arc 3; explicit-facility
selection; the #343 classify fall-through fix; the login screen; and the Admin, Settings,
Monitoring and Activity layouts.

## 6. Do not touch

The unassigned disposal note; the create-flow draft-loss warning; the Provision section's
deliberate structure around a single button; the shared reason-confirm component and every
confirmation it powers; the Operate page's configuration-change paragraph; the health
surface's verified-green versus unverified-quiet split; facility detail's provenance
qualifiers and its two distinct platform-service empty states; every classifier module and
the live-view polling bounds; the shared live-preview frame; the login screen.

## 7. Acceptance

Every status distinction survives with colour stripped. A failing deploy surfaces its
failure persistently at the point of action. Destructive affordances remain fail-closed
under partial, unauthorized and synthetic-entity conditions. CI gates the frontend build.
The running pod reports 0.21.0 from inside the container, with its image digest resolving to
the published index — an ingress 200 is not acceptance. The runbook's every expected result
was observed on the live env. An outsider completes the journey.
