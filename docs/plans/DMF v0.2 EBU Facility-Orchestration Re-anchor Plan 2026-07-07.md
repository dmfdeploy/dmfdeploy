---
status: active
date: 2026-07-07
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/185
---
# DMF v0.2 EBU Facility-Orchestration Re-anchor Plan (2026-07-07)

> **STATUS: ACTIVE.** Re-frames the v0.2 round around the EBU Dynamic Media
> Facility **facility-orchestration model** (whitepaper Fig. 4). Supersedes the
> framing of `DMF v0.2 Media-Native Console Demo Plan 2026-07-06.md` (now
> `superseded`) — the work packages there are not discarded; they are
> **reconciled** below under the lifecycle lens. Adversarially reviewed by codex
> (RESCOPE round 1: CHANGES-NEEDED → all P1/P2/P3 folded; see §Review trail).

## 1. North star — the destination (kept in view, NOT one sprint)

The eventual goal, against which every v0.2+ slice is measured:

> **A user takes two *licensed* media functions (a test source + a viewer) and
> a switching function through the full EBU lifecycle — Design → Plan → Provision
> → Configure → Operate → Finalise & Review — switches the viewer live between
> sources via the nmos-crosspoint function's IS-05 Connection API, with the whole
> journey monitored and every consequential action authorised and audited.**

This exercises the entire EBU model on one concrete, demoable scenario. Note the
two figures' framings: Figure 1's Media Workload Lifecycle has **six** stages
(Design, Plan, Provision, Configure, **Operate**, Finalise & Review, + continuous
Monitor & Update); Figure 4's Orchestration Model places **five** of them under the
**Facility Orchestration** horizontal (Design / Plan / Provision / Configure /
Finalise & Review) and lifts **Operate** into the **Control** vertical. So the
scenario touches: the Facility Orchestration horizontal (the five orchestration
stages), the **Control** vertical (Operate — make/break flow connections = the
live switch), the **Monitor** vertical (flow/function status + preview), and the
**Security** vertical (authorise + audit).

It is **too large for one sprint** (codex RESCOPE P1.3). Two parts are each a
workstream of their own — *live IS-05 switching* (the nmos-cpp↔MXL adapter, which
the executed crosspoint plan calls *"much larger than a shim"*) and *real licence
reservation*. So we walk to it in honest slices, each independently demoable, each
naming exactly what it does and does not yet do. The north star stays fixed; the
slices approach it.

## 2. Why re-anchor

The lifecycle **vocabulary and engine already exist** — the console just doesn't
use them as its organizing spine:
- DMF's stage names match EBU exactly (ADR-0003, ADR-0012); the backend has
  `lifecycle-provision/configure/operate/finalise.yml` playbook wrappers and
  NetBox `lifecycle:*` tags; catalog entries carry `ebu:{layer,vertical,
  lifecycle_owner}` metadata.
- But that metadata is **cosmetic** in the console (collapsed `<details>`), the
  UI is organized by nav rails (Workspace/Facilities/Media Workloads/Catalog/
  Activity) rather than the lifecycle journey, and the current v0.2 WPs A–H serve
  the **verticals** (Security: A/B/E/F; Monitor: G/H) + Operate-polish (C/D)
  while **leaving the orchestration horizontal invisible**.

Grounded console coverage (from a code survey, 2026-07-06):

| Stage / Vertical | Coverage | Reality |
|---|---|---|
| Provision | ~80% | catalog deploy → AWX → NetBox tag |
| Finalise & Review | ~80% | teardown job; no "review/record" surface |
| Configure | ~60% | clear-for-deployment flips intent; no "connections" surface |
| **Design** | ~20% | metadata only, no resource-profile view |
| **Plan** | ~20% | no scheduling / reservation / **licence** surface |
| Operate / Control | ~40% | job launcher; **no make/break flow control** |
| Monitor | 100% | Prometheus + NetBox + alerts |
| Security | ~60% | roles + audit (WP-A/B/E); no workload-level authz view |
| **Licensing thread** | **0%** | acknowledged; no model, no ADR (until ADR-0045) |

## 3. The roadmap (honest slices toward the north star)

| Slice | Proves | Honest name / what it does NOT do |
|---|---|---|
| **v0.2a** (this sprint) | Authorized, monitored **single** MXL media-function **lifecycle**, end-to-end. | "authorized, monitored MXL media-function lifecycle." No switching, no licence enforcement. |
| **v0.2b** (next) | **Connection intent** — a gated/audited "switch source" **control** action, coarse **reconnect** actuator behind a durable seam. | "coarse source-reconfigure control." NOT live IS-05; NOT a real crosspoint switch. |
| **later — licence provider** | Real `LicenceReservationProvider` (check/reserve/release/usage) with failure semantics. | Turns "declared" licences into enforced ones. |
| **later — live switching** | nmos-cpp↔MXL IS-05 adapter; sub-second make/break. Upgrades v0.2b's `reconnect` actuator to `nmos-is05`. | The "much larger than a shim" workstream; own issue + gates. |
| **later — Design/Plan engine** | Workload authoring + resource scheduling/reservation. | Out of v0.2 entirely (see §6). |

Sequencing rule (codex RESCOPE P2 stage-ordering): **v0.2a first and alone.**
Then v0.2b (connection intent) OR the licence provider — **operator picks one, not
both, per slice.** Operator decision 2026-07-07: **v0.2b = connection intent**;
licensing stays ADR-only (§5) until a genuinely licensed function exists.

## 4. v0.2a scope — the first honest EBU end-to-end (this sprint)

**Goal:** one MXL media function (`mxl-videotest-view`, the existing shipped pair)
goes Provision → Configure → Operate → Finalise **visibly and load-bearingly** in
the console, authorised and monitored throughout. This is the current WPs
**A/B/E/D/C reconciled under the lifecycle lens**, plus three additions codex
required to make it *real* rather than label-polish.

Reconciled work packages:

| WP | Was | v0.2a status | Reframe |
|---|---|---|---|
| **A** super-admin | Security | ✅ done (merged #42) | Security vertical (authorise) |
| **B** view-as | Security | ✅ done (merged dmf-cms#23) | Security vertical (authorise/audit) |
| **E** gate + nav + §5b logout | Security | ✅ done (merged dmf-cms#24, dmf-infra#43) | Security **on the Configure/Provision writes**: operator-gated deploy/teardown/launch + C5 audit = the lifecycle's authorise+record. RP-initiated logout (end-session) + Settings→avatar nav; codex 2-round PASS |
| **D** NetBox-derived per-instance MXL endpoints | "monitor polish" | ✅ done (merged dmf-cms#25, G26; codex 3-round PASS) — critical path | Monitor vertical; **without it you cannot SEE lifecycle state or a switch** (codex P2) |
| **C** media-native tile + live modal | "monitor polish" | ✅ done (merged dmf-cms#26, G27; codex 3-round PASS) | The **per-instance function view**: tile shows run-state + live preview; the surface a switch is observed on |
| **W0** Media Workload entity | — | **→ RFC (filed separately)** | The missing anchor (EBU: a Media Workload is an *assembly of Media Functions for a production*, Fig B1). Introduce it as a first-class entity, membership by NetBox tag `workload:<name>`; `videotest` = `mxl-videotestsrc` + `mxl-videotest-view` + their flow. **Amends** ADR-0037 (which deliberately modelled the page as a Function *inventory* and deferred the assembly) — as a tag-derived virtual grouping, no NetBox graph object. **Blocker (codex P1):** launcher configure/finalise tasks PATCH exact tag lists, so `workload:*` must be made owned/preserved or it's erased mid-lifecycle. **Not a v0.2a WP** — RFC→ADR |
| ~~L1~~ lifecycle legibility | — | **reframed → W0/RFC** | Corrected: the EBU 6-stage lifecycle (Design→Plan→Provision→Configure→Operate→Finalise&Review) is a **workload-level** property, not per-function-instance, and is not the 3-stage collapse first sketched. A *function* has a run-state; the *workload* has a lifecycle stage. Lands on W0, not as a standalone WP |
| ~~L2~~ catalog EBU vocab fix | — | **reframed → RFC (schema)** | Corrected (codex, from the whitepaper): verticals are cross-cutting and apply at **every** layer, so Layer-5 *support/control* functions legitimately keep one (`nmos-cpp`=orchestration, `nmos-crosspoint`=control). The bug is narrower — the mxl entries' `media-functions`/`media-processing` values aren't verticals at all. Rule: Layer-5 *media-processing* functions get **Layer + a media-function type/role** and omit `vertical`. Touches ADR-0003/0013; filed separately as a catalog-schema change |
| **NEW L3** run preflight + rollback | — | **add (stays v0.2a)** | Before a live run: report current media workloads + requested CPU/mem vs node budget; a cleanup/rollback path returning NetBox tags + Helm releases + monitor targets to pre-run state (codex P3 — the live env carries residue + CPU-budget pressure). Operational safety — stays in v0.2a |

**v0.2a acceptance (load-bearing, codex P2):**
1. ops login authorised; a viewer **cannot** deploy/clear/finalise by curl (403);
   every write carries a mandatory reason + request_id + audit line (C5).
2. The console shows `mxl-videotest-view` moving Provision→Configure(active)→
   Finalise as **explicit lifecycle state**, backed by NetBox `lifecycle:*`.
3. Live preview + status visible on the instance (Monitor).
4. Catalog schema check passes; the three MXL entries carry valid EBU verticals.
5. Preflight reports budget; a finalise/rollback returns the env to pre-run state.
6. Devtools/network scan: no cluster/tailnet/IP strings in any payload.

**Explicitly NOT in v0.2a:** switching, licence enforcement, Design/Plan authoring.

### 4a. Terminology correction — Media Workload vs Media Function (2026-07-08)

Operator + Claude review against the EBU whitepaper (Annex B, Fig B1) surfaced a
vocabulary drift that reshapes the former "L1/L2" additions:

- **A Media Workload is an *assembly of Media Functions for a production*** (canon:
  `docs/architecture/DMF EBU Mapping (2026-04-25).md`), not a single deployed
  function. DMF has no such entity today — ADR-0037 deliberately modelled the
  console's "Media Workloads" page as a Media *Function* **instance inventory**
  and deferred the assembly. The page is named for the workload concept but its
  rows are Functions.
- This is now promoted to a standalone **RFC → ADR** ("first-class Media Workload
  entity"), membership by NetBox tag `workload:<name>` (operator decision: NetBox
  for now, no new store). First worked example: the **`videotest`** workload =
  `mxl-videotestsrc` + `mxl-videotest-view` + the MXL flow between them (2
  functions + 1 flow — the smallest demonstrator of the B1 pattern, not a literal
  miniature of B1's many-role production).
- **L1** (lifecycle) is reframed onto that entity: the 6-stage EBU lifecycle is a
  **workload-level** property (Fig 1 is titled *Media Workload Lifecycle*); a
  function-instance's `lifecycle:*` tag is desired/run intent. NB the whitepaper
  also defines function-orchestration activities, so this is a console rule, not
  an absolute ontology claim.
- **L2** (catalog vocab) is reframed as a **schema** question: verticals are
  cross-cutting (every layer), so Layer-5 *support/control* functions may keep one;
  the actual bug is the mxl entries' non-vertical values. Media-*processing*
  functions get Layer + a function type/role and omit `vertical`.

L1/L2 + the Workload entity leave the inline v0.2a scope and are filed
separately (RFC + their own issues). L3 (preflight/rollback) stays in v0.2a.

## 5. v0.2b scope — connection intent (the next slice, sketch)

The switch the platform can honestly perform *today* is a **coarse reconnect**, not
live IS-05 (crosspoint is visible-only; MXL flows don't appear in it without the
adapter; the catalog/chart use a fixed flow id and the launcher exposes no source
selection — codex P1.1). So v0.2b builds the **durable seam**, not a throwaway UI:

- Backend domain command **`SwitchSourceCommand(receiver_instance, source_instance,
  reason)`** with a pluggable **actuator**: `actuator=reconnect` (v0.2b, coarse) →
  `actuator=nmos-is05` (later, live). The domain action is a **Configure/Control
  reconfigure**, NOT Finalise→Provision (codex P2 — a teardown/redeploy modelled
  as workload destruction won't reconcile with live IS-05). Status:
  `pending → reconnecting → active → failed_rollback_required`.
- Gated (operator+) + C5-audited like every consequential write; the switch shows
  a **deterministic visible proof** (distinct test patterns / a status field that
  changes with the selected source; preview captured before/after).
- **Honest UI copy:** "coarse reconfigure / reconnect actuator." nmos-crosspoint
  stays visible-only; "switched via nmos-crosspoint IS-05" is a **tracked follow-on
  claim** with its own acceptance gate (codex P1.1, P3).

Full v0.2b spec is written when we start it (needs two sources + viewer topology +
launcher source-selection parameterisation — real data-plane work, not UI).

## 6. Pruned from the v0.2 critical path

- **G** (alarm research) — done + merged; **background reference only**. **H**
  (Workspace refinement) — out of the v0.2 demo release gate (codex P3). Neither
  proves the orchestration horizontal.
- **Forgejo commit/PR history** in Activity and the **generic AWX workflow
  launcher** ("Release 2" placeholder) — outside the EBU model; not on the
  critical path, do not invest further this round.
- **Design/Plan authoring + resource scheduling/reservation** — legibility only in
  v0.2 (surface declared intent); no authoring/planner engine (operator decision
  2026-07-07).

## 7. Licensing — declared-but-not-enforced (see ADR-0045)

Per operator decision + codex P1.2/P2: v0.2 does **not** build a licence subsystem
and does **not** ship a mock licence pool of NetBox tags (a fake that can't prove
counts/leases/rollback would teach the wrong model). Instead:
- **[ADR-0045](../decisions/0045-media-function-licensing-reservable-resource.md)**
  names the seam (catalog declares required licence classes; a
  `LicenceReservationProvider` with `check/reserve/release/usage`; a
  `reservation_id` threaded to launchers; idempotent release on finalise/failed
  launch; deny-on-exhaustion).
- v0.2 **reserves the catalog/schema fields** so a real provider slots in later
  without rework. Concrete v0.2 shape (the ONLY licensing work in v0.2 — parse,
  validate, display; **no** provider call, **no** deny, **no** NetBox lease/tag):

  ```yaml
  # optional top-level block in a catalog entry; absent or empty = no licence requirement
  licence:
    required:
      - class: <string>      # licence class identifier, e.g. "acme-codec-pro"
        count: <integer ≥ 1> # instances/seats needed per deployment
  ```
  The catalog schema check validates the block when present; the console may
  display "requires N × <class>" as **declared** intent. Nothing reserves,
  assigns, denies, or releases in v0.2.
- "licensed" is a **tracked follow-on claim**, kept out of the v0.2 demo headline.

## 8. Review trail (codex RESCOPE, do not re-litigate)

Round 1 CHANGES-NEEDED, all folded: P1.1 Stage-3 over-claimed the switch → v0.2b
is a connection-intent seam (reconnect actuator), crosspoint stays visible-only;
P1.2 mock licence pool is a misleading fake → ADR/seam-first, code-deferred, no
tag-based fake; P1.3 Stages 0–3 bundle three hard problems → v0.2a alone, then one
of {switch, licence}; P2 Stage-1 load-bearing (schema check + state timeline +
curl-can't-launch test); P2 C/D are critical path not polish; P2 switch is
Configure/Control not Finalise→Provision; P2 split licensing into ADR-now + code-
later; P3 prune G/H from the gate; P3 name the demo honestly; P3 add budget/
rollback preflight.

## 9. Working-model wiring

- Tracking issue **#185** = the **A–E demo set** (super-admin, view-as, gate/nav,
  WP-D endpoints, WP-C grid). A–E is **complete once dmf-cms#26 merges → close
  #185 there.** The Media Workload entity + L1/L2 are *not* A–E scope; they move to
  their own RFC + issues (§4a). This plan supersedes the media-native demo plan's
  framing; that doc is flipped to `superseded`.
- **RFC: first-class Media Workload entity** (§4a) — Draft; goes through a
  Discussions RFC → ADR (extends ADR-0037; touches ADR-0003/0013). L1 (workload
  lifecycle) and L2 (catalog Layer/type vs vertical) land under it.
- **ADR-0045** (licensing seam) — Proposed; should go through a Discussions RFC
  before Accepted (CONTRIBUTING RFC-before-ADR).
- New issues to open when their slice starts: the Media Workload entity (post-RFC);
  the L2 catalog-schema correction; v0.2b connection-intent switch; the
  licence-provider code slice; live IS-05 switching; each with its own acceptance
  gate. WP-F (Console IAM, #186) and WP-G/H (#187) unchanged.
- Codex-gate each code WP. **G25 = WP-E ✅ merged 2026-07-07** (dmf-cms#24 +
  dmf-infra#43, codex 2-round PASS); **G26 = WP-D ✅ merged 2026-07-07**
  (dmf-cms#25, NetBox-derived per-instance MXL endpoints, codex 3-round PASS);
  **G27 = WP-C ✅ merged 2026-07-07** (dmf-cms#26, media-native tile grid + live
  modal, codex 3-round PASS, approved by lkirc). **That completes the A–E demo
  set — #185 is ready to close** (pending operator close-vs-retitle call).
  PR auto-merge arms at open; branch each WP from fresh `main`.
