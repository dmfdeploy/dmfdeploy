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
| **E** gate + nav + §5b logout | Security | **next (G25)** | Security **on the Configure/Provision writes**: operator-gated deploy/teardown/launch + C5 audit = the lifecycle's authorise+record |
| **D** NetBox-derived per-instance MXL endpoints | "monitor polish" | **KEEP — critical path** | Monitor vertical; **without it you cannot SEE lifecycle state or a switch** (codex P2) |
| **C** media-native tile + live modal | "monitor polish" | **KEEP — critical path** | The **lifecycle-legible instance view**: tile shows stage (bootstrapped/active) + live preview; the surface a switch is observed on |
| **NEW L1** lifecycle legibility | — | **add** | Surface each instance's lifecycle **stage** as an explicit state (not a collapsed `<details>`); a state timeline backed by NetBox `lifecycle:*`; make deploy→clear→finalise read as Provision→Configure→Finalise |
| **NEW L2** catalog EBU vocab fix | — | **add (bug)** | `mxl-videotest-view`, `mxl-hello`, `mxl-videotestsrc` set `vertical: media-functions`/`media-processing` — **invalid** (those are layer names). README requires vertical ∈ {orchestration, control, monitoring, security}. Fix the entries + **add a catalog schema check** so the console's EBU metadata is trustworthy (codex P2) |
| **NEW L3** run preflight + rollback | — | **add** | Before a live run: report current media workloads + requested CPU/mem vs node budget; a cleanup/rollback path returning NetBox tags + Helm releases + monitor targets to pre-run state (codex P3 — the live env carries residue + CPU-budget pressure) |

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

- Tracking issue **#185** (reframed: the v0.2 demo-set issue now delivers the
  v0.2a honest lifecycle). This plan supersedes the media-native demo plan's
  framing; that doc is flipped to `superseded`.
- **ADR-0045** (licensing seam) — Proposed; should go through a Discussions RFC
  before Accepted (CONTRIBUTING RFC-before-ADR).
- New issues to open when their slice starts: v0.2b connection-intent switch; the
  licence-provider code slice; live IS-05 switching; each with its own acceptance
  gate. WP-F (Console IAM, #186) and WP-G/H (#187) unchanged.
- Codex-gate each code WP (G25 = WP-E next). PR auto-merge arms at open; branch
  each WP from fresh `main`.
