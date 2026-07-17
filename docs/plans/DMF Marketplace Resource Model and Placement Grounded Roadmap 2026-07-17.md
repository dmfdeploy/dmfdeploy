---
status: draft
date: 2026-07-17
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/245
---
# DMF Marketplace Resource Model and Placement Grounded Roadmap (2026-07-17)

> **STATUS: DRAFT — design-track roadmap; no implementation lands under this
> doc.** Deliverable of umbrella
> [#245](https://github.com/dmfdeploy/dmfdeploy/issues/245) (marketplace &
> resource-placement RFC track). It anchors the RFC sequence — first
> extraction **complete**:
> [#204](https://github.com/dmfdeploy/dmfdeploy/issues/204) → RFC
> [#248](https://github.com/dmfdeploy/dmfdeploy/discussions/248) → ADR-0047
> — and each RFC→ADR conversion flips its own state, not this doc's.

**Provenance:** grounded revision (internally "v0.4") of an operator-side
proposal draft ("v0.3", 2026-07-17, not in-repo — body references to
"v0.3 §N" point at that draft; its architectural content is carried or
explicitly routed here, so the draft is not required reading). Every claim
was verified against the dmfdeploy decision record (46 ADRs +
`architectural-commitments-v1`), the plans tree, all 4 GitHub discussions,
all 146 umbrella issues, and the code of the 9 component repos, as of
2026-07-17 — then adversarially verified by a five-lane citation audit
(16 corrections applied) and cross-checked by codex (9 further findings,
all incorporated).

---

## 0. What changed from v0.3

v0.3 was written as a free-standing target architecture with explicit working
assumptions. The comparison against the repo found that **the proposal is not
new territory — it is the most complete synthesis so far of a direction the
project has already seeded in four places**:

1. **Discussion #112** — "Open framing: dmfdeploy and the EBU DMF publications"
   (2026-06-21) pre-articulates isolation boundaries, the environment factory,
   licenses-as-resource-pools, media capability classes
   (`mxl.2x.large`-style, declared-vs-validated), and the post-AWX actuator
   question. It names four follow-up RFCs, **none of which have been posted**.
2. **`docs/plans/DMF Vendor Multi-Tenancy Vision 2026-05-29.md`** (historical /
   North Star) decomposes vendor-as-tenant, virtual clusters, resource/node
   requests, and media-tenant separation, with eight open questions and a
   "cheap-now hooks" list — most hooks still unimplemented.
3. **Issue #204** — "RFC track: media function packaging, catalog sources &
   trust tiers" was the marketplace work item (open and unstarted at analysis
   time; since completed — RFC #248 converged into **ADR-0047**, which
   closes it).
4. **ADR-0045** — licensing as a reservable resource behind a
   `LicenceReservationProvider` seam (Proposed, declared-but-not-enforced).

Accordingly, v0.4 makes five changes:

- **Corrects the one contradicted assumption**: Argo CD/GitOps is not the
  deployment mechanism and is a frozen non-goal; AWX is the committed actuator
  (§3, §8.9).
- **Reconciles vocabulary** with the mandatory EBU taxonomy (ADR-0003) and the
  existing decision record — including renaming the proposal's "Profile",
  which collides with three existing meanings of that word (§4).
- **Adds a verified current-state map**: what exists, what is partial, what is
  absent (§6), and a constraint register of frozen decisions any of this work
  must respect (§7).
- **Re-anchors the phase plan to the real backlog** — issues, milestones, and
  the RFC→ADR pipeline — instead of a free-standing phase list (§9).
- **Triages the open-decisions list**: several of v0.3's "open decisions" are
  already decided in ADRs; they are removed from the open list and cited (§11).

The architectural core of v0.3 survives intact: the marketplace as a
publication/selection layer distinct from admission and placement, mandatory
validated resource declarations, conservative accounting for deterministic
media, reservation-before-actuation, and enforcement-maturity marking. Those
ideas are consistent with — and in several cases already prefigured by — the
decision record.

---

## 1. How to read this document

Content is tagged with its evidence level:

- ✅ **Exists** — running code or accepted decision, with a path/ADR cited.
- 🔶 **Committed/partial** — an accepted or in-flight plan, spec, or seam;
  design exists, code does not (or only partially).
- ❌ **Absent** — no counterpart exists today; absence verified by search.
- 🚫 **Frozen** — collides with an explicit non-goal in
  `docs/decisions/architectural-commitments-v1.md`; pursuing it requires a
  dated amendment, not drift.

Referenced repos are siblings under a common parent: `dmfdeploy` (umbrella,
docs + decisions), `dmf-cms` (console), `dmf-media` (catalog + charts),
`dmf-runbooks` (launchers), `dmf-infra` (bootstrap + AWX integration),
`dmf-env`, `dmf-init`, `dmf-promsd`, `dmf-central`.

---

## 2. Verdict summary

**Of the ten "established context / existing direction" claims v0.3 §3 rested
on: eight are confirmed, one is partially true, one is contradicted.**

Confirmed (with the record going further than v0.3 assumed in several cases):

- NetBox as source of truth — ✅ ADR-0013/0037/0038/0039/0032, with two
  boundary rules v0.3 did not know: **NetBox is not the reservation ledger**
  (ADR-0045) and **flows stay runtime-only, never inventory** (ADR-0037).
- Forgejo + Zot present — ✅ ADR-0014/0025/0033/0034; nuance: ADR-0041 made
  Forgejo **archive-only for public contribution** (GitHub-canonical, DCO).
- OpenBao + ESO — ✅ core, not planned (ADR-0008 and satellites).
- Air-gap — ✅ real posture at the runtime/supply-chain layer (ADR-0034
  accepted; flypack-offline lane; the console i18n/air-gap posture ADR-0030
  is still Proposed), deferred at the installer layer (ADR-0036: portable
  bundle is a future profile).
- Vendor isolation spectrum — ✅ already analysed (ADR-0020 mode B.3
  cluster-per-tenant; ADR-0027 third-party safety set; ADR-0017 node roles;
  Vendor Vision isolation ladder).
- Licensing as allocatable resource — ✅ has its own ADR (ADR-0045, Proposed).
- Heterogeneous nodes / NMOS / MXL / PTP / ST 2110 relevance — ✅ (ADR-0017 et al.).
- Kubernetes scheduling insufficient for media — ✅ strongly agreed
  (ADR-0017: co-location is load-bearing; Vendor Vision: "the media data
  plane does not virtualize cleanly") — **but the record's answer is
  "NetBox scopes; k3s schedules; AWX reconciles" (ADR-0037), not "build a
  scheduler"**. ADR-0037 explicitly declined a CRD + custom operator.

Partially true:

- "Vendors publish to their own space; DMFDeploy promotes into trusted
  catalogs" — 🔶 the *model* is now settled (ADR-0047: source classes,
  promotion quorums, cosign at promotion, per-publisher Zot namespacing),
  but no mechanism exists in code; the shipped catalog still has no
  publisher field, and implementation has not started.

Contradicted:

- "Argo CD is the intended or considered GitOps deployment mechanism" — 🚫
  The v0.1 commit gate froze **AWX as the actuator** and names the
  "Argo-for-k8s + AWX-glue hybrid" an explicit non-goal, shelving the
  2026-06-05 reversal plan. ADR-0013 rejected a pure Helm/ArgoCD model.
  Argo CD exists in the codebase only as a stub role marked "STUB — not yet
  implemented" (`dmf-infra/k3s-lab-bootstrap/roles/modules/advanced/argocd/`).
  The question "does AWX remain the actuator post-v0.1?" is legitimately
  parked in Discussion #112 Topic 6 (AWX / Argo CD / Temporal split) — as a
  future RFC, not an assumption.

**The single most consequential correction:** every place v0.3 said "GitOps
performs the approved deployment", read "the actuator (AWX job template →
launcher playbook → Helm from in-cluster Zot → NetBox lifecycle tag) performs
the approved deployment." The admission/reservation/placement architecture is
unaffected by this substitution — which is good news: it means the proposal's
core does not depend on re-litigating a frozen decision.

---

## 3. Corrected established context (replaces v0.3 §3)

### 3.1 What is actually established

- DMFDeploy targets Kubernetes-based (self-managed k3s only — ADR-0018) live
  media infrastructure on heterogeneous nodes, single-node proof surface for
  v0.1 (commitments-v1 §1).
- The **EBU DMF V2.0 taxonomy is mandatory vocabulary** (ADR-0003): 6 layers,
  4 verticals (Orchestration/Control/Monitoring/Security), 6 lifecycle stages
  (Design/Plan/Provision/Configure/Operate/Finalise & Review).
- **The function catalog is the marketplace substrate that already exists**
  (ADR-0013): YAML intent in `dmf-media/catalog/` (4 entries today:
  `nmos-cpp`, `nmos-crosspoint`, `mxl-videotestsrc`, `mxl-videotest-view`)
  joined to NetBox `lifecycle:*` tags, actuated by AWX job templates.
- **The deploy chain is proven end-to-end and live-verified**: console
  Catalog page → `POST /api/catalog/{key}/deploy` (operator role, mandatory
  reason, C5 audit) → AWX JT `media-launch-<key>` → EE pod (ADR-0025 Lane B)
  → thin launcher (`dmf-runbooks`) → `helm pull
  oci://zot.zot.svc.cluster.local:5000/dmf/charts/<key>` → readiness gate →
  NetBox tag flip. A convention-based reconcile
  (`697-cms-awx-token.yml`) grants the console Execute on every
  `media-(launch|finalise)-*` JT automatically — new catalog entries get the
  console wiring for free.
- **Media Workload is the canonical application-assembly entity** (ADR-0046):
  a tag-derived grouping (`workload:<slug>`, 0-or-1 per service) of Media
  Function instances, with workload-level 6-stage lifecycle. The first real
  workload is `videotest` (source + viewer + one flow).
- NetBox owns instance inventory, placement records (`placement.node`),
  lifecycle state, env identity (ADR-0037/0039); monitoring intent derives
  from it continuously (ADR-0038, `dmf-promsd`).
- OpenBao + ESO is the secrets architecture (ADR-0008); every machine writer
  is a scoped service account (ADR-0028/0032/0033).
- Air-gap is a first-class posture at the runtime/supply-chain layer
  (ADR-0034 internal collection mirrors; GHCR→Zot mirror via playbook 630;
  containerd registry rewrite; flypack-offline lane).
- **Two maintainers are active**; a standing demo env exists and the full
  presenter-order demo walkthrough completed 2026-07-17 (#203, closed).

### 3.2 What v0.3 assumed that must be restated

| v0.3 assumption | Verdict | Correction |
|---|---|---|
| Argo CD intended/considered for deployment | 🚫 Contradicted | AWX is the committed actuator; Argo hybrid is a named non-goal; revisit only via Discussion #112 Topic 6 RFC post-v0.2 |
| "GitOps-based deployment" as established context | 🚫 | Actuation = AWX + Helm + NetBox tags. Git remains SoT for *definitions* (catalog YAML, charts) — that part stands |
| NetBox as SoT for infrastructure and services | ✅ | Confirmed, plus: not a reservation ledger (ADR-0045); flows runtime-only (ADR-0037) |
| Vendors publish → DMF promotes to trusted catalogs | 🔶 | Model settled by ADR-0047 (source classes, quorums, signing at promotion); zero mechanism built yet |
| Kubernetes scheduling insufficient | ✅ | Confirmed; but decided division is "NetBox scopes; k3s schedules; AWX reconciles" — no custom scheduler (ADR-0037) |
| Workload profiles resembling cloud instance types | 🔶 | Prefigured as "media capability classes" (#112 Topic 5) and EBU "Resource Profile" (Design-stage output, explicitly deferred in the EBU Mapping); nothing implemented |
| Licensing as allocatable resource | ✅ | ADR-0045 (Proposed): `LicenceReservationProvider` seam, declared-but-not-enforced in v0.2, **mock NetBox-tag pools explicitly rejected** |
| Air-gapped operation may be required | ✅ | Established; installer-layer bundle deferred (ADR-0036) |
| Isolation modes needed per vendor workload | ✅ | Analysed; for the managed mode the recorded constraint is **cluster-per-tenant** (ADR-0020 B.3 — Mode B itself remains Proposed, no work in flight); shared-cluster multi-tenancy for managed deployments was rejected in that analysis |
| Forgejo/Zot/OpenBao/ESO present | ✅ | Confirmed with the ADR-0041 nuance (Forgejo archive-only for contribution, still the runtime SCM/mirror) |

---

## 4. Vocabulary reconciliation (new)

ADR-0003 makes the EBU taxonomy the mandatory naming frame, and ADR-0046
reserves the application-assembly term. v0.3 introduced a parallel vocabulary;
this table is the binding translation. **The right column is what RFCs and
ADRs must use.**

| v0.3 term | DMF canonical term | Source |
|---|---|---|
| Application | **Media Function** (catalog entry) | ADR-0013, ADR-0046 |
| Application (assembly of functions) | **Media Workload** | ADR-0046 (EBU Annex B Fig B1) |
| Application release | **Media Function Package** — signed, digest-pinned chart + image closure + catalog entry + probes + licence block + provenance | ADR-0047 §2 |
| Marketplace | **Catalog** + **classed catalog sources** | ADR-0013 + ADR-0047 |
| Catalog classes (Certified/LTS/Experimental/Vendor Preview/Customer Local) | **Four axes** (ADR-0047 §1): source class `project` / `vendor` / `community`; promotion state `Draft→…→Revoked`; support attribute; launcher privilege. "Testing" is a derived console label for pre-`Approved` states, never a schema value | ADR-0047 (supersedes the draft-era `sanctioned/vendor/testing/community-unsafe` tiers) |
| Publisher | `publisher` identity slug (ownership via the project-controlled catalog-source index) + `origin` provenance + per-publisher Zot namespace | ADR-0047 §7; Vendor Vision §8 |
| Profile | **Resource Profile** (EBU Design-stage output: compute/network/storage/licence requirements) or **capability class** (`mxl.2x.large` style) | EBU Mapping vocabulary canon (deferred); #112 Topic 5 |
| Infrastructure instance type | **Node role** (taints/labels, ADR-0017) + **provider descriptor** (ADR-0026) + hardware profile (CAX31/CCX13/Asahi) | ADR-0017/0026 |
| Capability (discovered vs certified) | **Declared vs validated capability** | #112 Topic 5 (exact same distinction) |
| Workload class (realtime/control/…) | No counterpart; nearest: `ebu.layer` + `vertical`\|`media_function_type` + `lifecycle_owner` | ADR-0046 §6; QoS classes are new scope |
| Resource pool | No counterpart; first instance will be **licence pools** (ADR-0045), generalisation list in #112 Topic 4 | ADR-0045; #112 |
| Admission | **Run preflight** (two-tier: console early check + authoritative launcher first-play gate) | #202 / L3 plan |
| Reservation | `LicenceReservationProvider` seam (check/reserve/release/usage) + facility-scoped run lock (Lease CAS) | ADR-0045; L3 plan |
| Placement | "NetBox **scopes** (tenant/site/cluster + eligibility); k3s **schedules**; AWX **reconciles**" + chart `placementMode`/node roles | ADR-0037; ADR-0017; chart `mxl-fabrics-demo` |
| DeploymentRequest | Console deploy endpoint + C5 reason + launch-time `extra_vars` (the seam #239/#201 are opening now) | dmf-cms `main.py`; v0.2b spec WP3a |
| GitOps handoff | **Actuation handoff**: AWX JT launch with canonical `extra_vars` object; git holds definitions, NetBox holds state | ADR-0025/0037; v0.2b `topology_params` |
| Runtime reconciliation | Monitoring lane: continuous (ADR-0038). Workload lane: Operate-stage drift-detection smoke test, deliberately no controller | ADR-0038; Function Catalog Model §7 |

**Naming hazard, spelled out:** "profile" already carries three meanings in
the repo — facility footprint (Flypack/Site/Cloud, EBU Mapping), release
profile matrix (sandbox/aws, ADR-0031), and monitoring profile
(minimal/full). A fourth unqualified use would be actively harmful. Use
**Resource Profile** (the EBU term, already reserved in the vocabulary canon
and flagged as an open item) for the application-side requirement contract,
and **capability class** for the named, sized, validated supply-side classes.

---

## 5. Architectural principles — revised

v0.3 §6's principles survive with two corrections and three additions.

Retained as written: marketplace/scheduler separation (6.1), declare
requirements not hardware (6.2), infrastructure advertises supply (6.3),
atomic reservations (6.5), conservative accounting for realtime (6.6),
certification against a declared envelope (6.8), inventory vs allocation
authorities (6.9), uncertainty must be visible (6.10 — this is also UX
Constitution Art. 1, a binding gate).

Corrected:

- **6.4 "Admission precedes GitOps" → "Admission precedes actuation."** No
  AWX job template for a catalog entry may launch until preflight passes and
  the required lock/reservation is held. This is exactly the L3 plan's
  two-tier design: the console refuses before AWX is consumed (protecting the
  EE pod's own resource cost), and the launcher first-play is the
  authoritative in-cluster gate that trusts no passed-in verdict.
- **6.7 "Kubernetes remains the runtime, not the entire resource model" →
  keep, but bind it to the decided division of labour (ADR-0037):** NetBox
  scopes, k3s schedules, AWX reconciles. DMFDeploy narrows eligibility and
  accounts for non-k8s resources; it does not replace the scheduler. A custom
  scheduler/CRD-operator was considered and declined.

Added:

- **6.11 NetBox is not the reservation ledger** (ADR-0045). Counts, leases,
  idempotent reserve/release, and rollback need transactional semantics a tag
  cannot carry. Reservation state lives behind a provider seam; NetBox
  records inventory and outcomes.
- **6.12 Declared vs validated supply** (#112 Topic 5). Discovery (NFD,
  NetBox inventory, device plugins) yields *declared* capability; only a
  validation pass promotes it to *allocatable* capability class. This was
  v0.3 §11.4's instinct — it is already project doctrine in draft form.
- **6.13 Enforcement maturity is explicit** (v0.3 §24.3, retained and
  promoted to a principle). Every resource in the model carries its maturity:
  enforceable / externally-enforced / measurable-only / planning-estimate /
  manually-verified. ADR-0045's "declared-but-not-enforced" licence fields
  are the first shipped instance of this pattern — follow it.

---

## 6. Current-state map (new)

Verified 2026-07-17. Absences were established by search, not assumption.

| Concept (v0.3) | Status | Evidence |
|---|---|---|
| Function catalog + deploy chain | ✅ | §3.1 above; `dmf-media/catalog/*.yaml`, `dmf-cms/src/dmf_cms/catalog.py`, `dmf-runbooks/playbooks/launch-*.yml` |
| Catalog metadata schema | ✅ (narrow) | key/display_name/summary/`ebu.*` (fail-closed one-of vertical\|media_function_type)/`mxl_flows`/provision/configure/finalise/dependencies. No publisher/source-class metadata, no resource requests, no licence block yet |
| Deployment parameters at launch | 🔶 claimed | Console posts `body={}` today; #239 (claimed 2026-07-17; three coordinated PRs planned in the claiming comment, none opened yet) + v0.2b WP3a open the `extra_vars` seam; gotcha found: JTs seeded with `ask_variables_on_launch: false` silently ignore vars |
| Deployment-intent contract | 🔶 spec'd | `topology_params` schema_version 1 (`sources[]`, `viewer.source_selection`, `target_facility`) — v0.2b spec; flagged as the future Design-surface input (#231) |
| Placement | ✅ minimal | Chart-level `placementMode: single-node\|split-node`, nodeSelector/tolerations, `dmf.io/mxl` taint + `dmf.io/mxl-demo-role` labels (ADR-0017); NetBox records observed `placement.node`. No engine, no scoring, no multi-node decisions |
| Capacity admission | 🔶 spec-only | L3 plan (#202): headroom = allocatable − Σ requests; FIT/NO-FIT on requests; fail-closed on missing declarations (WP0 adds the currently-absent `resources.requests` to the MXL chart + AWX EE container group); legible budget report; `l3_override` + reason, C5-audited. Explicitly "**not** a scheduler, a cost/quota system, node elasticity, or a generalised admission controller" |
| Reservation | 🔶 seam only | ADR-0045 `LicenceReservationProvider` (Proposed, nothing built); L3 facility-scoped run lock (Lease CAS, TTL, holder) — spec-only |
| Concurrency correctness | 🔶 | Per-entry lifecycle lock #24 (open, reframed as a general transition lock); deploy↔finalise race + double-launch TOCTOU were flagged v0.1-mandatory |
| Resource pools | ❌ | Zero matches for `resource_pool` across all repos. Node roles are the only pooling primitive |
| Capability registry | ❌ | No counterpart; capability-classes RFC (#112 Topic 5) unposted |
| Instance types | ❌ (adjacent: ✅) | No per-workload instance type; ADR-0026 provider descriptors (Proposed) + ADR-0017 hardware profiles are the adjacent supply-side constructs |
| Publisher/vendor onboarding | ❌ code (design settled) | No publisher field in the shipped schema; no vendor principal class; onboarding + quorum model decided in ADR-0047 §3, implementation not started |
| Classed catalog sources | ❌ code (design settled) | Single first-party catalog in code; the source-class/promotion model is decided (ADR-0047), implementation not started |
| Certification pipeline | ❌ | `grep certif` → TLS certificates only. Nearest existing discipline: digest-pinned images, health_probe gates, live-verify culture |
| Signatures/SBOM/admission policy | ❌ deferred | Platform Plan Stage 5 hardening; cosign/Kyverno named as candidates, nothing deployed |
| Runtime reconciliation | 🔶 split | Monitoring: real continuous reconcile (ADR-0038, dmf-promsd). Workloads: Operate-stage drift-detection smoke test only — no desired-state controller (deliberate, with Argo frozen) |
| Licensing | 🔶 seam only | ADR-0045; catalog `licence:{required:[{class,count}]}` block reserved (parse/validate/display); console IA reserves a "Licenses" rail slot ("named here but unmodelled") |
| Multi-tenancy isolation | ❌ (analysed) | Platform is single-tenant. `vcluster` appears in exactly one file (Vendor Vision). Console "tenancy" = NetBox read filter. ADR-0027's safety set (Proposed) and ADR-0020 B.3's Mode-B customer-tenancy constraint are the recorded analyses — neither is an accepted guardrail for vendor/media tenancy today |
| MXL resource modeling | ❌ | "MXL runtime slots" / `mxl.*` profiles have **no precedent**; `mxl_flows` is graph wiring, not capacity; MXL is intra-host only (ADR-0017), cross-node fabric is roadmap |
| Air-gap | ✅ | ADR-0030/0034; flypack-offline lane; #25 tracks the permanent internal collection source |
| Live capacity data point | ✅ | Full demo menu = 96% CPU requests on the 3-CPU sandbox node, AWX EE pods unschedulable — the incident that seeded #202 |

Two additional reality checks worth recording:

- **In code, the word "marketplace" appears only in
  `dmf-infra/.../697-cms-awx-token.yml`** — twice, both describing the same
  idea: catalog expansion as "the GitOps 'marketplace' model: git-add a Zot
  chart/image + Forgejo launcher + its AWX JT." Those comments, plus the
  naming-convention auto-grant, are today's whole marketplace mechanism —
  and it is a good one:
  adding a first-party (`project`-source) function is already a pure-git
  operation.
- **The catalog contract has resisted widening once before.** During Move 2
  the console's app-contract deliberately narrowed into a navigation manifest
  rather than widening into a service catalog. Marketplace work should expand
  the catalog *schema* (fields), not the console's *contract* (surface), until
  an RFC decides otherwise.

---

## 7. Constraint register (new)

Binding constraints any of this work must respect. These are decisions, not
opinions; overriding any of them requires the stated process.

1. **Frozen v0.1 non-goals** (`architectural-commitments-v1.md`): federation
   (dmf-central), multi-node HA + cloud as a release claim, **Argo hybrid
   actuator**, in-place upgrade, dmf-media catalog-v2 roles, drift
   meta-harness. Reversal = dated amendment block with rationale, not drift.
2. **Work-selection rule**: "choose work that makes the proven core runnable
   and legible to an outsider." Marketplace/resource work is v0.2+ design-track
   material by rule; only #202/#201/#239-class items are execution-eligible now.
3. **AWX is the sole actuator** (ADR-0025/0037, commitments-v1). The
   scale-to-zero availability pattern is authorized for AWX only — any other
   workload adopting *that pattern* needs its own ADR (ADR-0043). A
   generalised "scale/allocate anything" framework is pre-emptively fenced;
   ordinary new catalog entries, by contrast, need only a git PR (ADR-0013).
4. **NetBox is not the reservation ledger** (ADR-0045) — and the mock
   NetBox-tag licence pool was explicitly rejected as "teaching the wrong
   model". Any resource-pool MVP must have real counts/leases/rollback or
   carry `declared-but-not-enforced` marking.
5. **Cluster-per-tenant for a future managed service** (ADR-0020 B.3 — the
   recorded constraint for Mode B *customer* tenancy; Mode B itself remains
   Proposed, no work in flight). This does not settle *vendor/media* tenancy
   inside one facility — that axis is open (Vendor Vision). Namespace-grade
   isolation is for cooperating first/second-party workloads (per the
   ADR-0027 safety-set analysis — Proposed prior art, since partially
   ratified as ADR-0047's `generic-chart-policy/v1`; the tenancy remainder
   is still not an accepted guardrail), never hostile tenants.
6. **EBU taxonomy is mandatory vocabulary** (ADR-0003); "Media Workload" is
   reserved (ADR-0046). Use §4's translation table.
7. **UX Constitution gates** bind any marketplace/deployment-request UI.
   Day-one hard gates (§3, binding now): no uncertainty presented as
   certainty (requested ≠ observed), every action closes its loop,
   consequential actions get graduated friction + impact preview + the C5
   audit quartet, raw errors never leak at default level. Near-term gate
   (binding soon): no disruptive refresh of live operational lists. Beyond
   the §3 enumeration, Art. 15 (self-contained operation) is platform
   doctrine via ADR-0030/0034: no runtime calls to external registries — a
   marketplace surface must be servable entirely in-cluster.
8. **Contribution flows through GitHub PRs + DCO** (ADR-0041); Forgejo is
   archive-only for contribution while remaining the runtime SCM mirror. A
   "vendor publisher space" design must reconcile with this split — the
   plausible shape is per-publisher Zot namespaces + git-side catalog-source
   references, not vendor accounts on the runtime Forgejo.
9. **Working model**: work starts at an issue; non-trivial work gets a plan
   doc with `tracking_issue` frontmatter; ADRs are preceded by an RFC in
   Discussions. Live-config/doc mismatch to resolve: WORKING-MODEL.md and
   CONTRIBUTING define an RFC Discussions category, but no such category
   exists on the live repo — both prior RFC threads (#112, #190) went to
   **Ideas**. Post to Ideas until the category is created or the docs are
   corrected; fixing the mismatch is itself a small backlog item.
10. **Operator preferences on record**: GitHub-native over bespoke scripts
    (avoid tooling sprawl); PAYG/spot only for any cloud lane; codex
    cross-check for every non-trivial plan before landing.

---

## 8. Revised architecture

### 8.1 Logical architecture (corrected)

```text
 ┌───────────────────────────────────────────────────────────────────────┐
 │                     Publisher / Contributor side                      │
 │   git (catalog YAML, charts) │ OCI (images, charts) │ evidence        │
 └──────────────────────────────┬────────────────────────────────────────┘
                                │ PR + promotion (source class + state) [ADR-0047]
                                ▼
 ┌───────────────────────────────────────────────────────────────────────┐
 │            Classed catalog sources  (git = SoT)                       │
 │   project │ vendor │ community  (+ promotion states)   [ADR-0047]     │
 └──────────────────────────────┬────────────────────────────────────────┘
                                │ deployment request (console, C5 reason)
                                ▼
 ┌───────────────────────────────────────────────────────────────────────┐
 │       Resource & capability model                                     │
 │   Resource Profiles │ capability classes │ pools (licence-first)      │
 │   declared vs validated supply                 [#112 T4/T5, ADR-0045] │
 └──────────────────────────────┬────────────────────────────────────────┘
                                │ resolve
                                ▼
 ┌───────────────────────────────────────────────────────────────────────┐
 │       Admission, reservation, placement-scoping                       │
 │   two-tier preflight │ facility lock │ reservation seam │ NetBox      │
 │   scoping (tenant/site/cluster/eligibility)      [#202, ADR-0037/45]  │
 └──────────────────────────────┬────────────────────────────────────────┘
                                │ approved launch (extra_vars contract)
                                ▼
 ┌───────────────────────────────────────────────────────────────────────┐
 │       Actuator: AWX JT → launcher playbook → Helm (from Zot)          │
 │       → readiness gate → NetBox lifecycle tag      [ADR-0025/0037]    │
 └──────────────────────────────┬────────────────────────────────────────┘
                                │ schedule (within scoped eligibility)
                                ▼
 ┌───────────────────────────────────────────────────────────────────────┐
 │       k3s + media fabric   (nodes, devices, networks, storage)        │
 └──────────────────────────────┬────────────────────────────────────────┘
                                │ observe
                                ▼
 ┌───────────────────────────────────────────────────────────────────────┐
 │   NetBox inventory │ Prometheus (dmf-promsd) │ NMOS │ sidecars        │
 │   continuous monitoring reconcile; workload drift-detection           │
 └───────────────────────────────────────────────────────────────────────┘
```

The five-layer story of v0.3 (§2) survives; layer 5 is renamed from "GitOps
Deployment and Runtime Reconciliation" to "Actuation and Runtime
Reconciliation". The maxim becomes:

> The catalog determines what may be requested.
> The resource model determines what it needs.
> Admission and scoping determine whether and where it may run.
> **The actuator (AWX) performs the approved deployment.**
> k3s schedules within the approved scope; NetBox records what happened.

### 8.2 Marketplace model → classed catalog sources (settled by ADR-0047)

This section's draft-era single "trust tier" axis converged, via RFC #248,
into ADR-0047's **four axes**. v0.3 §8's five catalog classes map onto them:

| v0.3 class | ADR-0047 mapping | Notes |
|---|---|---|
| Certified | `project` source + `Certified` promotion state | project repo, project-signed |
| Long-Term Support | support attribute `lts` on a `Stable` release line | maintenance commitment, not a trust boundary and not a commercial SLA |
| Experimental | pre-`Approved` promotion states (`Draft`/`Candidate`) | surfaced as the derived "testing" console label |
| Vendor Preview | `vendor` source, pre-`Approved` | vendor-managed source, vendor-signed, project-indexed |
| Customer Local | `community` source | browse-only / disabled by default; audited trust-bypass to deploy |

Two constructs v0.3 lacked, both load-bearing (now binding via ADR-0047):

- **The playbook privilege boundary.** Custom launcher playbooks are
  arbitrary code executing in AWX with control-plane credentials. Therefore:
  **bespoke launchers are `project`-source-only** (ADR-0047 §4); every other
  source class gets the **generic declarative launcher** (chart + values +
  netbox_service + probes only) validated under `generic-chart-policy/v1`
  (ADR-0047 Appendix A). This single rule does most of the marketplace's
  security work.
- **Promotion is a git operation.** Today "publishing" a first-party
  function = a PR adding catalog YAML + chart/image to Zot + launcher + JT
  seeding. That shape is kept: source/state promotion is a reviewed git
  change of a digest-pinned catalog-source reference — plus, per ADR-0047
  §6, one signed fail-closed revocation deny-list for current-state
  enforcement (history proves what happened; the deny-list says what is
  denied now).

On the marketplace *portal* question (v0.3 §8.4: Backstage, Devtron, etc.),
this document's recommendation — not a settled decision — is to deprioritise
adopting an external portal product: the console already has a Catalog rail
in the 4-rail IA, the UX Constitution requires fully self-contained runtime
operation, and the catalog contract deliberately resisted becoming a service
catalog once already. An in-cluster, console-native catalog-source browsing
surface remains open — the Console IA explicitly reserves third-party
integration space under Catalog. Revisit external products only if a real
multi-publisher ecosystem materialises.

### 8.3 Application package → Media Function Package

v0.3 §9's required contents map to: the existing catalog schema (✅ identity,
digest-pinned image, chart source, health/readiness, AWX wiring) plus the
ADR-0047/ADR-0045 deltas (🔶 publisher/origin — source class lives in the
catalog-source index, never on packages — licence block,
signature/provenance refs, validation evidence) plus the L3 delta
(🔶 `resources.requests` declarations — WP0 makes these mandatory-fail-closed
for capacity-gated entries). OCI-as-transport is not an open question in
practice: charts and images already ship via Zot OCI; ADR-0034 defers only
Ansible-collection OCI.

v0.3 §9.3's "raw overrides" concern is already answered in miniature by the
`topology_params` pattern: named, versioned, schema-checked parameter sets
authored in git, projected onto chart values by the launcher — not free-form
value overrides at request time. Extend that pattern rather than inventing an
override taxonomy.

One v0.3 requirement carried forward by name (its §16.3), and since encoded:
**a publisher must not be able to reduce a certified resource declaration in
a later release without revalidation.** This anti-regression rule is now an
enforcement point in ADR-0047 §2, not an override-syntax detail.

### 8.4 Resource Profiles and capability classes (v0.3 §10–12)

Keep v0.3's four-way distinction (profile / instance type / capability /
quantity) — it matches #112 Topic 5's split of generic compute flavor from
media capability. Grounding corrections:

- Start from the EBU **Resource Profile** vocabulary slot (Design-stage
  output covering compute/network/storage/licence), which the EBU Mapping
  already reserves and defers. The proposal's `media.rt.general.large` naming
  can inform the eventual class names; `mxl.2x.large` and
  `st2110.gateway.medium` are the recorded exemplars.
- v0.3 §10.4's compromise (one primary profile + named capabilities +
  explicit quantities + certified overrides) is the right starting shape and
  should be the RFC's proposal.
- **The embryonic resource declaration already has a shipping vehicle**:
  L3 WP0's mandatory `resources.requests` on catalog charts, plus the
  reserved `licence:` block. To be precise: these are admission-preflight
  inputs and a *precursor* to the EBU Resource Profile — whose Design-stage
  schema (compute/network/storage/licence) remains explicitly deferred —
  not the Resource Profile itself. Do not design profile families before
  the precursor lands.
- Profile immutability/versioning (v0.3 §10.6): follow the established
  pattern — digest-pinning and git history are the project's immutability
  mechanisms; immutable profile revisions should be git-tracked documents
  referenced by digest/version from catalog entries.
- Carry v0.3 §13.3's conservative realtime defaults into the RFC as the
  proposed safety position: guaranteed CPU where declared; no overcommit of
  exclusive CPU, accelerators, or guaranteed network/gateway capacity;
  explicit HugePages reservation; topology-aware placement where required.
  The general principle (6.6) is not actionable without this concrete list.

### 8.5 Instance types → supply-side classes (v0.3 §11)

The demand for "what can this installation actually allocate" is real, but
build it on what exists: node roles (ADR-0017 taints/labels), provider
descriptors (ADR-0026, Proposed), and hardware profiles. The
declared-vs-validated ladder (v0.3 §11.4's discovered → operator-declared →
validated → certified → degraded) is exactly #112 Topic 5's "NetBox knows the
NICs exist; the class is only exposed after validation" — carry it into the
capability-classes RFC as the promotion ladder for supply.

Carry also v0.3 §11.3's separate open question: multiple discovery sources
(NetBox, Node objects, NFD, device plugins, SR-IOV operators, storage
systems, NMOS/MXL control, license managers, operator declarations) will
disagree about the same supply; the precedence and reconciliation rules
between sources are unresolved and belong in the same RFC.

### 8.6 Resource pools (v0.3 §15)

v0.3 §15.3's scalar/discrete/topological/qualified/licensed/shared-bounded
typology is good analysis and should survive into the RFC verbatim. Grounding:

- **Licence pools go first** (ADR-0045 exists, has the seam, has the
  fail-closed rules). Everything else in v0.3 §15.2 — fabric bandwidth,
  **multicast state/ranges**, SR-IOV VFs, timing eligibility, media I/O
  (ST 2110 flows, SDI/gateway ports, codec channels), storage
  throughput/latency — is the #112 Topic 4 generalisation list; leave it as
  the roadmap's later column, dropped nowhere.
- **"MXL runtime slots" have no precedent and need a design decision**:
  either they are a capability of the ADR-0045-style reservation seam
  (recommended — the seam is deliberately generic: check/reserve/release/
  usage), or they justify a distinct third model. ADR-0045 already rejected
  one shortcut pool design (NetBox tags); a naive slots model would repeat
  exactly that mistake.
- PTP/timing pools: v0.3 correctly flags PTP as non-scalar ("eligibility, not
  quantity"). Park as a qualified-access pool type in the RFC; no nearer-term
  vehicle exists.

### 8.7 Admission and reservation (v0.3 §17–19)

v0.3's capacity formula (installed − unavailable − reserved − allocations −
pending − failure-reserve − margin = admissible) is the right long-run shape.
The shipped-design reality it must grow from:

- **L3 preflight is the admission MVP** (#202, plan complete, WP0–WP4
  unbuilt, v0.2b-blocking): requests-vs-allocatable on one node, fail-closed
  on missing declarations, legible budget report, audited override. Its
  non-goals line ("not a scheduler, not a quota system, not a generalised
  admission controller") is the current scope fence — v0.3 §18's full
  admission-inputs list is the post-fence roadmap, not the MVP.
- **Admission serialization exists in miniature** — the facility-scoped run
  lock (single run per facility, Lease CAS with TTL + holder) and the
  per-entry transition lock (#24) serialize today's actual races
  (double-launch TOCTOU; deploy↔finalise). To be precise, these are
  concurrency guards, not resource reservations: nothing holds quantities.
  True reservation semantics are the ADR-0045 provider seam (Proposed,
  unbuilt); v0.3 §19.3's reservation state machine
  (Proposed→Held→Committed→Allocated→…) is its eventual generalisation.
- **Reservation store**: v0.3 §19.5 lists candidates (relational DB, CRDs,
  service). Constraint 4 (NetBox is not the ledger) and the ADR-0037
  precedent (no CRD+operator) narrow this; the licence-provider seam
  (ADR-0045) is deliberately store-agnostic. Defer the store choice to the
  first provider implementation's RFC.
- v0.3 §18.3's "degraded option offered" outcome: keep deferred exactly as
  v0.3 said. Also note the record's fourth outcome already exists: **Pending
  (asleep actuator)** — AWX scale-to-zero (ADR-0043) means admission must
  distinguish "no capacity" from "actuator waking" (#134 tracks the console
  side of this).

### 8.8 Placement (v0.3 §20)

Rewritten against ADR-0037's division of labour:

- DMFDeploy's placement responsibility is **scoping**: which
  tenant/site/cluster/namespace, which node-role pool
  (selectors/tolerations), which co-location group (MXL graphs pinned to one
  host — ADR-0017 makes this load-bearing), and which exclusive attachments
  when those exist. That is v0.3 §20.5 integration patterns 1–2.
- k3s performs final node selection inside the scope. Pattern 3 (custom
  scheduler) is not the direction — ADR-0037 declined a CRD + custom
  operator. Patterns 4–5 (DRA, external allocation controllers) are simply
  unaddressed by the record: genuinely open, worth watching-brief notes in
  the capability-classes and pool-model RFCs.
- v0.3 §20.4's soft placement preferences (minimize fragmentation, preserve
  scarce accelerators, spread redundant replicas across failure domains,
  prefer processing near media ingress, balance thermal/power, preserve
  future capacity) are consciously parked with the multi-node freeze — the
  pool-model RFC should carry the list so it resurfaces when multi-node
  scoping reopens, rather than being rediscovered.
- Multi-site placement is 🚫 double-frozen (federation + multi-node/cloud
  claims). It stays in the vision layer until commitments are amended.

### 8.9 Actuation handoff (replaces v0.3 §23 "GitOps handoff")

After admission and locking, the approved request becomes an AWX job launch:

- The **canonical launch object** is the `extra_vars` payload (the
  `topology_params` pattern: named, versioned, schema-checked, authored in
  git, `target_facility`-scoped). The launcher projects it onto chart values.
  Gotcha already found and being fixed: JTs must be seeded with
  `ask_variables_on_launch: true` or AWX silently ignores the payload (#239).
- **The separation of records survives** from v0.3 §23.2, corrected for
  store count: ADR-0037's model is three stores — git definitions (catalog
  YAML, charts, parameter sets), NetBox inventory/lifecycle/placement, k3s
  observed runtime. A future reservation ledger (the ADR-0045 seam) would
  be a deliberate *fourth* store, added by decision — not folded into
  NetBox, and not a substitution within the existing three. The
  reconciliation-across-stores requirement (v0.3 §23.3's failure scenarios)
  stands unchanged and is genuinely open — L3's snapshot-diff rollback
  (three surfaces: NetBox / Helm / monitoring, run-scoped snapshot ConfigMap,
  refuse-if-missing) is its first concrete instalment.
- v0.3 §28.3's removal-ordering rule ("scarce resources released only after
  confirmed termination") is already implemented in miniature: teardown flips
  the lifecycle tag only after `helm uninstall` and cleanup complete, and
  never deletes the NetBox service record.

### 8.10 Certification (v0.3 §22)

Nothing exists (❌); the honest v0.4 framing is a maturity ladder the project
already climbs implicitly:

1. **Now**: schema validation (fail-closed catalog loader), digest-pinning,
   health probes, live-verify discipline, codex cross-check culture.
2. **ADR-0047** (was the #204 RFC): cosign/Sigstore signature + provenance
   verification at promotion, per source class;
   forbidden-privileges check via the generic-launcher boundary.
3. **Later (Stage-5 hardening)**: cosign/Kyverno admission of signed images
   (already named in the Platform Plan as deferred).
4. **Vision**: the full v0.3 §22 pipeline (resource-utilization tests,
   upgrade/rollback validation, certification matrix). Keep v0.3's own
   warning: certification scope must be intentionally constrained — and note
   the project's standing "false guarantees" ethic (declared-but-not-enforced
   marking) applies to certification language too.

Two v0.3 items carried forward by name rather than silently absorbed — and
since settled: the release **promotion state machine** (Draft → Candidate →
Approved → Certified → Stable → Revoked, v0.3 §22.1) and the
Approved/Certified/Stable distinction are now defined in ADR-0047 §3
(with two-maintainer promotion quorums and a one-maintainer emergency
revoke); the anti-regression rule from §8.3 above is encoded in ADR-0047 §2
as a certification enforcement point, not a packaging nicety.

### 8.11 Isolation and multi-tenancy (v0.3 §14)

The five modes of v0.3 §14.1 map onto the recorded ladder:

- Shared node / shared media node → ✅ today's model (namespaces; node roles
  for media nodes). The ADR-0027 third-party safety set was Proposed prior
  analysis; its chart-facing half is now ratified as ADR-0047's
  `generic-chart-policy/v1` (Appendix A), while the tenancy-mechanism
  remainder (vClusters, dedicated pools) still awaits the tenancy work.
- Exclusive device allocation → ❌ future (device plugins/SR-IOV named in the
  Vendor Vision; nothing built).
- Dedicated vendor node → 🔶 the mechanism exists (ADR-0017 taints/labels
  generalise to per-vendor pools per Vendor Vision §8) but no vendor concept
  exists to use it.
- Isolated k8s environment → vcluster/Kamaji/Capsule surveyed as
  off-the-shelf (Vendor Vision, "solved"). Note the axis distinction:
  ADR-0020 B.3's cluster-per-tenant constraint governs *customer* tenancy
  of a future managed service (Mode B, itself Proposed) — it is not a
  decided answer for *vendor/media* tenancy inside one facility, which the
  Vendor Vision leaves open.
- The unsolved research frontier, named precisely in the Vendor Vision:
  **hostile-tenant isolation of the media data plane** (MXL per-flow UNIX
  permissions are cooperative-grade; PTP is facility-wide; multicast needs
  governance; "vcluster isolates the API, not the wire"). v0.3 §14.2's
  "final multi-tenancy model remains unresolved" is thus half-true: the
  control-plane ladder is resolved; the data plane is the open problem.

### 8.12 NetBox integration (v0.3 §21)

v0.3 §21.1's responsibility split is confirmed almost verbatim by
ADR-0037/0038/0039 — with the two ledger/flow boundary rules added
(constraints 4 and §3.2). v0.3 §21.3's staleness policy remains genuinely
open and is worth carrying into the capability-classes RFC (observation
timestamp / confidence / stale threshold / operator override with audit —
the UX Constitution's Art. 1 provenance gate will demand this anyway the
moment capacity data reaches the console).

---

## 9. Roadmap (replaces v0.3 §32)

Re-phased against the real backlog. **Milestones today: `v0.1-polish`
(1 open item — #36 tracker) and `v0.2` only.** A `v0.3` milestone does not
exist; creating one (or explicitly parking post-v0.2 scope) is itself a
roadmap action, to be taken when v0.2 exits.

### Horizon 0 — already scheduled (v0.2, execution)

The proposal's Phase 0/1 largely exists here already:

| Item | Issue | State |
|---|---|---|
| Workload-tag stamping at deploy (opens the extra_vars seam) | #239 | claimed 2026-07-17; 3 PRs planned, none open yet |
| v0.2b multi-source switch (`topology_params`, switch seam) | #201 | spec complete; blocked on #202 |
| L3 run preflight + rollback (capacity admission MVP) | #202 | plan complete; WP0–WP4 to build |
| Per-entry lifecycle transition lock | #24 | open, reframed |
| Media Workload API flip + instances endpoint | #199 | open |
| Launcher tag-preservation role test | #196 | open |
| Finalise & Review record before teardown | #232 | open |
| Design beat v1 — template instantiation over topology params | #231 | open |
| Console asleep-actuator handling | #134 | open |

### Horizon 1 — design tracks to open now (v0.2, RFC→ADR writing)

| RFC | Vehicle | Grounding |
|---|---|---|
| Media function packaging, catalog sources & trust tiers | **DONE** — RFC #248 converged (3 codex rounds → PASS) → **ADR-0047** closes #204 | §8.2–8.3; licence-presence question stays with ADR-0045 |
| Licensing seam ratification | ADR-0045 RFC (named in #189 scope) | declared-but-not-enforced fields in v0.2 |
| Catalog-secret lifecycle | #123 (RFC→ADR noted in-issue) | vendor functions need credential paths |
| Console IAM design spec (vendor/tenant principals later build on it) | #186 (spec-first, no v0.2 build) | ADR-0028 chain |
| Media capability classes & Resource Profile mapping | **new RFC** (named in #112, unposted) | §8.4–8.5; absorb v0.3 §10–12 content |
| License & resource pool model (generalisation) | **new RFC** (named in #112, unposted) | §8.6; absorb v0.3 §15 typology |

Schema hooks (`publisher`/`origin` fields; per-publisher Zot namespace
convention): **settled by ADR-0047 §7** — note there is deliberately no
`trust_tier` package field; source class lives in the project-controlled
catalog-source index. Implementation ordering is post-ADR work under #245
(the catalog-source index is the first deliverable). The owned-tag
namespace bounding is already shipped (`merge_owned_tags`).

### Horizon 2 — post-v0.2 build (needs a v0.3 milestone; some items need commitment amendments)

- First licence provider implementation (converts ADR-0045 from declared to
  enforced; decides the reservation store).
- Capability-class validation harness (declared → validated supply; the
  first "certified capability" instances).
- Generic declarative launcher + `generic-chart-policy/v1` ingestion
  validation (ADR-0047's privilege boundary made real — vendor
  deployability is gated on it).
- Reservation objects beyond the run lock (v0.3 §19 state machine, scoped by
  the pool model RFC).
- Vendor principal class + first vendor-tier catalog source (Vendor Vision
  Phase 2; touches ADR-0028/0041).
- 🚫-gated: multi-node placement, node elasticity (ADR-0043 deferral +
  Elastic Media Nodes plan, historical), any HA/cloud release claim —
  each requires a dated amendment to commitments-v1 first.
- Actuator re-evaluation RFC (#112 Topic 6: AWX / Argo CD / Temporal) — only
  if AWX hits a wall; the record's bar is "post-v0.1 spike, if AWX hits a
  wall", not calendar time.

### Horizon 3 — research frontier (vision layer; no vehicle, correctly)

Hostile-tenant media data-plane isolation; MXL cross-node fabric (RDMA/EFA)
and any MXL capacity model; certification laboratory & compatibility matrix;
environment factory (#112 Topic 2); multi-site placement & federation;
commercial metering. v0.3 §32 Phase 5 content lives here.

---

## 10. First validation scenario — grounded (replaces v0.3 §36)

v0.3 §36 asked for a narrow end-to-end scenario. **The project has already
scheduled almost exactly it** — the v0.2b demo journey on the standing env:

- One `project`-source application: the `videotest` Media Workload
  (`mxl-videotestsrc` + `mxl-videotest-view`) + `nmos-crosspoint`
  (Phase 1 visible-only) on the 3-CPU sandbox node.
- Declared requirements: chart `resources.requests` (L3 WP0) + declared
  ingress/egress stays out until a bandwidth pool exists.
- Admission: L3 preflight FIT/NO-FIT with the legible budget report; the
  L3 acceptance test is a deliberately over-budget launch being refused
  (and rollback verified) — the 96%-of-3-CPU incident supplies the
  realistic fixture for constructing it.
- Reservation: facility run lock + per-entry lock (#24).
- Actuation: console deploy (C5 reason) → AWX → launcher → Helm-from-Zot,
  with `workload:<slug>` stamping (#239) so the deployment lands as a named
  workload, not Unassigned.
- Removal: teardown + snapshot-diff rollback returns NetBox/Helm/monitoring
  to the pre-run state; capacity visibly returns.
- Audit: C5 quartet + run-scoped records throughout.

Success criteria from v0.3 §36 that this does **not** yet cover — carried
forward as acceptance criteria on later work: release cannot enter the
catalog without valid publisher/signature metadata (model settled by
ADR-0047; lands with the catalog-source index implementation);
profile→instance-type resolution (capability-classes RFC); a licence
quantity actually reserved (first ADR-0045 provider).

---

## 11. Open decisions — triaged (replaces v0.3 §33)

### Already decided — removed from the open list

| v0.3 open decision | Decision | Where |
|---|---|---|
| GitOps vs other deployment | AWX actuator; Argo frozen non-goal | commitments-v1; ADR-0025 |
| Is OCI the canonical transport? | In practice yes for charts/images (Zot); collections deferred | ADR-0025/0034 |
| Who owns inventory vs allocation state | NetBox inventory; reservation ledger explicitly not NetBox | ADR-0037/0045 |
| Custom scheduler? | No — scope, don't schedule | ADR-0037 |
| Shared-cluster tenancy for managed mode | No — cluster-per-tenant is the recorded Mode B constraint (Mode B itself remains Proposed) | ADR-0020 B.3 |
| Immutability mechanism | Digest-pinning + git history | catalog schema; ADR-0013 |
| Contribution/legal baseline | GitHub PRs + DCO; Conventional Commits | ADR-0041 |
| Trust/source-class governance & signing gate | Settled — four axes, `project`/`vendor`/`community`, two-maintainer promotion quorum + one-maintainer emergency revoke, cosign/Sigstore at promotion (implementation not started) | ADR-0047 (closes #204) |

### Open with a scheduled vehicle

Licence declaration semantics
(ADR-0045 RFC); catalog-secret lifecycle (#123); vendor/tenant principal
model (#186 spec); reservation store (first ADR-0045 provider); staleness/
confidence policy for capacity data (capability-classes RFC); EBU taxonomy
hard case for shared-data-plane assemblies (#9, paused thesis-killer —
directly constrains co-location modeling).

### Open with no vehicle yet — routed to future RFCs

Every v0.3 §33 question not settled or scheduled above is routed here, by
owning RFC, so nothing silently vanishes:

**→ settled by ADR-0047** (was routed to the #204 RFC): publisher
eligibility and approver quorum (§3 — two maintainers, no self-quorum);
Approved/Certified/Stable semantics (§3); support commitments (support
attribute `none`/`best_effort`/`lts`); Helm-as-mandatory-baseline with
operator bundles excluded from the generic path (§2); the offline bundle's
*shape* (§6 — construction tooling stays deferred with ADR-0036); signature
standard cosign/Sigstore (§2); the anti-regression rule (§2).

**→ capability-classes RFC:** override permission policy and profile
governance; vendor-specific capability representation and implication
hierarchies (ConnectX → RDMA); discovery-source precedence (§8.5);
staleness/confidence policy for capacity data; measured-vs-declared
requirement methodology (v0.3 §16.4); workload/QoS class semantics (v0.3
§13) including the conservative realtime defaults (§8.4).

**→ pool-model RFC:** fabric-bandwidth accounting; multicast state/range
representation; PTP/timing eligibility; storage throughput/latency
guarantees; reservation expiry and capacity-queueing semantics; capacity
observability metrics (v0.3 §30's list: capacity by pool,
reserved-vs-allocated, stranded/fragmented capacity, admission failures by
reason, placement latency, profile utilization, stale inventory sources);
the parked soft-placement-preference list (§8.8).

**→ no owner yet (candidate future RFCs):** runtime-operation policy — which
drift auto-remediates, when operator intervention is required, what happens
when observed consumption exceeds declaration, allocation recovery after
control-plane failure (v0.3 §33 "Runtime operation", untouched by any
current plan); the air-gap set from v0.3 §26.2 beyond revocation propagation
— offline vulnerability-database updates, central-vs-per-site certification,
publisher/promotion signature chaining; vendor support-operations safety
(alongside #186); NUMA/PCIe/NIC topology modeling and redundant-replica
placement (parked with the multi-node freeze).

---

## 12. Risks — revised

Carried from v0.3 (all still valid): excessive model complexity, false
guarantees, stale inventory, split-brain state, profile proliferation,
vendor lock-in via capabilities, certification burden, air-gap revocation lag.

Added by the grounding:

- **Parallel-vocabulary drift** — the biggest realized risk of v0.3 itself:
  a document ecosystem using Application/Profile/GitOps alongside a repo
  using Media Function/Resource Profile/AWX. Mitigation: §4 table; RFCs use
  canonical terms only.
- **Freeze violation by enthusiasm** — multi-node placement, federation, or
  an Argo dependency arriving implicitly inside marketplace work. Mitigation:
  §7 register; amendment protocol.
- **Roadmap-without-a-backlog** — this document (like v0.3) is not a work
  queue; the working model forbids local backlogs. Every Horizon item above
  is either an existing issue or an RFC-to-be-posted; nothing here is
  actionable except through that pipeline.
- **Single-operator bandwidth** — Horizons 1–2 are design-heavy; the record
  shows design tracks sitting unstarted while execution tracks move (#204
  sat untouched for weeks, then converged to ADR-0047 in a day once picked
  up). Sequencing the #112 RFCs one at a time — packaging done first,
  capability-classes next — remains more realistic than opening all lanes.

---

## 13. Process guide — how to advance this document (new)

1. ~~Post the packaging/trust-tiers RFC (#204) to Discussions › Ideas~~ —
   **done 2026-07-17**: RFC #248 (3 codex rounds → PASS) → author decision
   comment → **ADR-0047** (closes #204), following the #190→ADR-0046
   template exactly.
2. **Ratify ADR-0045** (licensing) via its pending RFC — it is the keystone
   for every later pool/reservation concept.
3. **Post the capability-classes RFC** (#112 Topic 5 + this doc §8.4–8.5) —
   after L3 WP0 lands, so the first Resource Profile has a shipped instance.
4. **Keep executing Horizon 0** — #202 and #239/#201 deliver the admission
   MVP and the intent-contract seam this architecture presumes.
5. **At v0.2 exit**: create the v0.3 milestone (or explicit parking), decide
   which Horizon-2 items enter it, and write dated amendments for any frozen
   commitment being reopened.
6. Every RFC/ADR from this document should cite it as input alongside
   Discussion #112 and the Vendor Multi-Tenancy Vision — three generations
   of the same architecture, converging.

---

## Appendix A — source index

**Decisions** (all under `dmfdeploy/docs/decisions/`): ADR-0003 (EBU
taxonomy), 0008 (OpenBao+ESO), 0013 (catalog model), 0014 (AWX projects),
0017 (MXL intra-host + node roles), 0018 (self-managed k3s), 0020
(deployment modes; B.3 cluster-per-tenant), 0025 (in-cluster EE + Helm from
Zot), 0026 (provider descriptors), 0027 (three-layer catalog + 3rd-party
safety set), 0028 (identity chain), 0030 (i18n/air-gap), 0031 (release
profiles), 0032 (scoped NetBox writer), 0033 (scoped Zot writer), 0034
(internal collections), 0036 (dmf-init thin container), 0037 (NetBox
instance inventory; scopes/schedules/reconciles), 0038 (NetBox-driven
monitoring), 0039 (env identity), 0041 (release & contribution), 0043
(scale-to-zero scoping), 0045 (licensing reservable resource), 0046 (Media
Workload entity), `architectural-commitments-v1.md`.

**Plans** (`dmfdeploy/docs/plans/`): Vendor Multi-Tenancy Vision 2026-05-29
(North Star); L3 Run Preflight and Rollback 2026-07-16; v0.2b Multi-Source
Switch Spec 2026-07-15; v0.2 EBU Facility-Orchestration Re-anchor
2026-07-07; MXL Single-Node Revival 2026-07-03; NMOS Crosspoint Media
Function 2026-06-21; Dynamic NetBox-Driven Monitoring 2026-06-04 (executed);
Elastic Media Nodes & Cloud Cost Controller 2026-06-01 (historical);
multi-provider resource selection 2026-05-08 (historical).

**Discussions**: #112 (EBU open framing — six topics, four unposted RFCs),
#190 (Media Workload RFC), #194 (ADR-0046 acceptance), #27 (ADR index).

**Issues** (umbrella): #204, #202, #201, #239, #24, #123, #186, #189, #199,
#196, #193, #231, #232, #200, #134, #25, #29, #9, #36; closed context: #17,
#108, #185, #203.

**Key code paths**: `dmf-media/catalog/*.yaml`;
`dmf-cms/src/dmf_cms/{catalog,main,awx,mxl,media_workloads}.py`;
`dmf-runbooks/playbooks/launch-*.yml`, `roles/netbox_catalog_common/`;
`dmf-media/charts/mxl-fabrics-demo/`;
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/`,
`playbooks/{630-zot-seed-platform,697-cms-awx-token}.yml`,
`roles/modules/advanced/argocd/` (stub); `dmf-promsd/src/dmf_promsd/`.
