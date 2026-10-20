# DMF v0.2 Make-vs-Adopt OSS Evaluation (2026-07-18)

**Date:** 2026-07-18
**Author:** operator-directed agent session (Claude orchestrator + adversarial subagent verification)
**Status:** Findings / point-in-time record — informs the v0.2 lifecycle build and the marketplace track
**Scope:** Are the v0.2 media-workload-lifecycle plans (EBU Facility Orchestration Model) hand-building anything a mature open-source project already covers? Evaluation of the active plans and implementation choices against the mid-2026 OSS landscape.
**Related:**
- Tracking: [dmfdeploy/dmfdeploy#245](https://github.com/dmfdeploy/dmfdeploy/issues/245) (watch items filed as a comment), [dmfdeploy/dmfdeploy#201](https://github.com/dmfdeploy/dmfdeploy/issues/201) (BCP-007-03 note filed as a comment)
- Plans evaluated: `DMF v0.2 EBU Facility-Orchestration Re-anchor Plan 2026-07-07`, `DMF v0.2b Multi-Source Switch Spec 2026-07-15`, `DMF L3 Run Preflight and Rollback Plan 2026-07-16`, `DMF v0.2 Presentable Journey Execution Plan 2026-07-12`, `DMF Marketplace Resource Model and Placement Grounded Roadmap 2026-07-17`
- Decisions evaluated against: ADR-0037, ADR-0038, ADR-0043, ADR-0045, ADR-0046, ADR-0047, `architectural-commitments-v1`

---

## 1. Method

Multi-agent evaluation, three phases:

1. **Map** — 3 lanes reading the active v0.2 plans, the ADR/marketplace
   decision record, and a LOC-level custom-code inventory across all
   component repos.
2. **Research** — 5 web lanes surveying the mid-2026 OSS landscape per
   domain: broadcast/NMOS control, Kubernetes platform orchestration,
   scheduling/quota/licensing, supply-chain/air-gap/monitoring-SD, and the
   commercial industry landscape (sanity check).
3. **Adversarial verify** — one skeptic lane per candidate: live web
   maturity checks (releases, governance, license, arm64 support),
   repo/doc reads for real adoption cost, and a fit check against the
   frozen constraint register (roadmap §7: AWX sole actuator, Argo frozen
   non-goal, NetBox SoT but not the reservation ledger, no
   CRD/operator/scheduler for placement, Helm-mandatory packaging with the
   Appendix A deny-list, single-node→small-cluster ARM64 proof surface,
   self-contained/air-gap doctrine, EBU taxonomy, single-operator scale).

Coverage: **40 of 58 candidates fully verified**; the remaining 18 were
skipped with named reasons (duplicates of verified verdicts, scope the
operator already deferred, rejections already on the decision record, dead
or archived projects, wrong-shape tools). Skip reasons are listed in §7.

## 2. Bottom line

**DMF is not reinventing the wheel.** Three independent lanes converged:

1. **No mature open-source facility-orchestration layer exists.** Every
   real-world facility orchestrator (Grass Valley AMPP, Lawo VSM/HOME, EVS
   Cerebrum, Nevion VideoIPath, Imagine Magellan, Riedel, TAG, Skyline
   DataMiner, the new SipMX alliance) is proprietary; SVT's Olympics-proven
   Neo platform is in-house/closed. The open pieces are the standards
   (NMOS, ST 2110) and the transport (MXL — which explicitly disclaims
   orchestration). The EBU/AMWA JT-DMF task force chartered to standardize
   this space has no reference implementation for the orchestration
   horizontal. DMF is *ahead of* a forming standard, not behind an existing
   product.
2. **The custom code is mostly deliberate glue over well-chosen OSS.**
   Roughly 68–70K LOC custom (excl. tests) across the component repos, but
   the heavy machinery is delegated: k3s, AWX, NetBox,
   Prometheus/Grafana/Loki, Authentik, OpenBao + External Secrets Operator,
   Helm, Zot, cert-manager, MXL, nmos-cpp, nmos-crosspoint. The genuinely
   novel concentrations (NetBox-SoT bootstrap + AWX wiring, born-inventory,
   the console, dmf-init orchestration, dmf-env bootstrap) have no OSS
   counterpart — verified by search, not assumption.
3. **The project already litigates make-vs-adopt with discipline, on
   record:** ADR-0037 rejected a CRD/operator/scheduler; ADR-0045 refused a
   mock licence pool; ADR-0047 considered and parked
   Backstage/Devtron-class portals; Argo/GitOps was evaluated in depth and
   frozen as a non-goal; ADR-0038 rejected `netbox-plugin-prometheus-sd`
   with three concrete reasons (and no first-party NetBox SD exists in
   vmagent or Grafana Alloy — the small dmf-promsd adapter is justified).

Effort is well-placed. The steering needed is small: align two *future*
workstreams (live IS-05 switching; ADR-0047 bundle/validator tooling) with
standards and tools forming right now, instead of designing bespoke
equivalents when those builds start.

## 3. Verdict table

| Area (built or planned) | Approach | Mature OSS alternative? | Verdict |
|---|---|---|---|
| NMOS registry/node (IS-04/05) | nmos-cpp via launcher role | It *is* the reference implementation | ✅ adopted — validated correct |
| Routing/matrix UI (Control vertical) | nmos-crosspoint, link-out only, 2 documented forward-patches | Upstream is the alternative | ✅ adopted — validated; retire patches when upstream PR 15 merges |
| Live IS-05 switching (future workstream) | planned nmos-cpp↔MXL adapter | **AMWA BCP-007-03 "NMOS With MXL"** (WIP spec, `urn:x-nmos:transport:mxl`; nmos-cpp support emerging; nmos-crosspoint issue 14 open) | ⚠ target the standard, don't design a parallel bridge — watch with named trigger |
| v0.2b coarse `reconnect` actuator + SwitchSourceCommand | custom seam, actuator-swappable | none (verified) | keep-custom — correctly pre-shaped for a later `nmos-is05` actuator |
| Catalog→deploy chain | console → AWX → launcher → Helm → NetBox tags | Kubeapps (upstream dead), Portainer, Rancher/Fleet, Backstage, Crossplane, KubeVela, Radius, KusionStack, Score, OLM, Nephio, ONAP, OSM, Argo, Flux — all verified reject / keep-custom / watch | keep-custom — nothing does AWX actuation + NetBox write-back; adoption = a second control plane |
| L3 preflight (capacity budget) | custom two-tier check (spec-only) | Kueue ✗, cluster-capacity ✗, kube-scheduler-simulator ✗ (all verified against the L3 §0 non-goals) | keep-custom — optionally native ResourceQuota as a zero-cost floor |
| L3 rollback (3-surface) | custom NetBox + Helm + monitor-target coordinator reusing the shipped idempotent teardown plays | no transactional cross-surface tool exists (verified). helm-diff/Helmfile verified **reject** (L3 already reuses teardown plays, not `helm rollback`; a plugin binary in the EE bypassing `kubernetes.core.helm` is negative value; Helmfile brushes the GitOps non-goal) | keep-custom — cheap win only: `--atomic`/`--cleanup-on-fail` on the existing helm-upgrade path |
| Licensing (ADR-0045 seam) | `LicenceReservationProvider`, provider deferred | keygen = best functional shape but **watch** (first non-OSI dependency would need an explicit decision; docs-vs-images arm64 contradiction unresolved; no build item until a genuinely licensed function exists). Lago = billing, RLM/FlexNet proprietary, license-zero dead | keep seam-first — validated |
| Plan-stage scheduling/booking | deferred (legibility-only this round) | none for calendar-style future-window booking (Volcano/YuniKorn = gang-now; CAMARA = spec only) | correctly deferred |
| ADR-0047 §6 signed index / revocation / offline bundle | shape fixed, tooling deferred | **TUF — verified adopt (high):** §6 is a field-for-field re-derivation of TUF timestamp/snapshot/targets + root rotation; use python-tuf as a library + tuf-on-ci (the shape sigstore/root-signing itself uses), thresholds sized for 2 maintainers. RSTUF verified keep-custom (4-service stack, amd64-only images, stale release). **Zarf — verified integrate-partial:** create-side CLI only (differential signed bundles, binary in the dmf-init tool layer per ADR-0036); its `zarf init`/agent webhook stays out. Hauler = lighter fallback, watch (open bug 667: `store copy` drops cosign signatures) | ⚠ adopt TUF as target design; Zarf create-side for transport |
| ADR-0047 Appendix A `generic-chart-policy/v1` validator | bespoke rendered-manifest validator planned | **Kyverno — verified integrate-partial:** `kyverno apply` evaluates policies fully offline against rendered manifests (no cluster), linux/arm64 CLI assets, cosign-native; ~15–20 ClusterPolicy rules vs a bespoke DSL + fixture harness; same artifact carries into the Stage-5 "Kyverno-class" admission the ADR already names. Sigstore policy-controller = Stage-5 alternative, key-based mode only (keyless default violates the self-contained doctrine) | ⚠ author Appendix A as Kyverno policies, evaluate via CLI |
| Capability classes / resource profiles (unposted RFC) | custom vocabulary planned | **AMWA-TV/jt-dmf-crm** (active, Apache-2.0): resource-manifest / host-capabilities schema — verified | watch — read as vocabulary input when drafting the RFC; do NOT adopt its DRA-driver demo (CRD/controller-class, k8s ≥1.35, x86-only examples — conflicts ADR-0037 + ADR-0047 Appendix A) |
| Monitoring SD | dmf-promsd (~665 LOC) | netbox-plugin-prometheus-sd — already rejected in ADR-0038 with reasons; no first-party NetBox SD anywhere (verified negative) | keep-custom — validated |
| Media Workload entity, C5 audit, console UX | tag-derived grouping, custom FastAPI/React | none (Sofie, BBC BUG, nagare-media = different domains, verified) | keep-custom |

## 4. Highest-value actions (ordered)

1. **Live-switching workstream: implement against AMWA BCP-007-03, not a
   bespoke bridge.** The standard for exactly the planned adapter is
   forming upstream now (spec active; nmos-cpp gaining support;
   nmos-crosspoint issue 14 opened by the nmos-cpp maintainer). Trigger:
   first tagged BCP-007-03 release or nmos-cpp MXL-transport support
   landing. Filed on
   [#201](https://github.com/dmfdeploy/dmfdeploy/issues/201).
2. **ADR-0047 implementation: adopt TUF as the target design for §6**
   (python-tuf + tuf-on-ci, 2-maintainer-sized thresholds; not RSTUF), and
   scope **Zarf to its create-side CLI** for the offline-bundle transport
   (Hauler as lighter fallback after its bug 667 is rechecked). Filed on
   [#245](https://github.com/dmfdeploy/dmfdeploy/issues/245).
3. **Author `generic-chart-policy/v1` as Kyverno policies evaluated
   offline via the Kyverno CLI** instead of a bespoke validator + fixture
   harness; evaluate Kyverno vs Sigstore policy-controller (key-based) at
   Stage-5. Filed on
   [#245](https://github.com/dmfdeploy/dmfdeploy/issues/245).
4. **Proceed with L3 exactly as specced** (custom preflight and 3-surface
   rollback both verified as the right call). Cheap wins only:
   `--atomic`/`--cleanup-on-fail` on the launcher helm-upgrade path,
   optionally native ResourceQuota as a floor.
5. **When the capability-classes RFC is drafted, read jt-dmf-crm's
   manifest schema as one reference input** so the vocabulary tracks what
   EBU/AMWA member companies are converging on (also services the standing
   "JT-DMF tracking" open question).

## 5. Where no wheel exists (custom justified)

- The Facility-Orchestration horizontal (Design→Plan→Provision→Configure→
  Finalise & Review) as a runnable system — nothing open exists; JT-DMF has
  no reference implementation for it.
- NetBox-as-CMDB write-back tied to deploy events; a catalog UI that
  actuates via AWX/Ansible — no surveyed tool has either.
- The Media Workload assembly entity + EBU-native lifecycle legibility.
- Media-function licence check/reserve/release/usage semantics.
- Transactional 3-surface rollback (NetBox + Helm + monitor targets).
- NetBox→Prometheus http_sd across scrape+probe+snmp lanes (dmf-promsd).

## 6. Watch list (named triggers)

| Item | Trigger to revisit |
|---|---|
| BCP-007-03 + nmos-cpp MXL transport | first tagged release / support merged upstream |
| nmos-crosspoint upstream PR 15 | merge → retire the DMF forward-patches |
| JT-DMF other workstreams (Sync, Flow Connection, Business Activity) | any published spec/code |
| KubeVela Workflow step-group/approval-gate design | when a real Design/Plan engine is scoped — mine the design, not the dependency |
| Headlamp (k8s SIG UI) | if an embedded cluster-inspector is ever wanted |
| Koordinator Reservation CRD | reaches CNCF Incubating AND a multi-node lane opens |
| SipMX / Intel Tiber Broadcast Suite | if either becomes genuinely open source / the repo revives |
| keygen (ADR-0045 backend) | (1) a genuinely licensed function is proposed; (2) live arm64 test resolves the docs-vs-images contradiction; (3) explicit operator decision on a first non-OSI (Fair Core) dependency |
| Hauler bug 667 (cosign signatures dropped in `store copy`) | recheck at bundle-tooling build time |
| Sigstore policy-controller | Stage-5 hardening; key-based mode required for air-gap |

## 7. Coverage and skip reasons

40/58 candidate verdicts ran the full adversarial check. The verification
corrected three earlier desk-judgments — RSTUF (accelerator → keep-custom),
helm-diff (adopt-for-preview → reject), helm native rollback (use-as-is →
flags-only) — and confirmed TUF (adopt), Zarf (integrate-partial,
create-side only) and Kyverno (integrate-partial, offline CLI).

The 18 skipped lanes, with reasons: duplicates of verified verdicts (Sofie,
BBC BUG, MXL — adopted and corroborated by two lanes); operator-deferred
scope (Volcano, YuniKorn, Koordinator — the Plan stage is legibility-only
this round); rejections already on the decision record
(netbox-plugin-prometheus-sd per ADR-0038; Artifact Hub-class portals per
ADR-0047); not-adoptable-software (CAMARA — an API spec; GCP Dynamic
Workload Scheduler — proprietary); dead or archived (license-zero,
Bitfusion); wrong-shape (Lago — billing; RLM/FlexNet — proprietary; IBM
License Service — audits IBM products only; Velero — disaster recovery, not
targeted rollback; ORAS — plumbing already implied by cosign; kwok — CI
harness; kube-capacity — report formatting only; OPA/Gatekeeper — duplicate
of the Kyverno role, pick one; Kubernetes ResourceQuota — native and
trivial, use directly).
