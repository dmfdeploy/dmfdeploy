---
status: superseded
date: 2026-06-03
superseded_by: DMF Console Wording and Media Workloads Page Plan 2026-07-03.md
---
# DMF Media Workloads — NetBox-Driven Media Function Inventory Plan

**Date:** 2026-06-03
**Status:** Superseded (2026-07-03) by `DMF Console Wording and Media Workloads Page
Plan 2026-07-03.md` (#173), which re-plans the D4 page slice against the current
codebase; the D1 model shipped as ADR-0037 and is unchanged. Original status follows.
**Status at authoring:** Planning (approved model; **implementation not started — planning docs only by operator instruction**)
**Authoring session:** Claude Opus 4.8 with operator, after reading the EBU DMF Reference Architecture V2.0 whitepaper together.
**Executes / governed by:** [ADR-0037](../decisions/0037-media-workloads-netbox-instance-inventory.md) (amends [ADR-0027](../decisions/0027-catalog-instance-vs-definition-separation.md)).
**Target lane (first proof):** the **`sandbox-single-node`** lane (`dmf-sandbox` Lima Debian-12 ARM64 VM) — see [WP1S](DMF%20OSS%20v0.1%20WP1S%20Single-Node%20Sandbox%20Lane%202026-05-25.md). **Not** a cloud env.

> **Branch policy (2026-06-03).** Pre-public / solo phase — **everything converges
> on `main`**, no feature branches. Component code lands directly on each repo's
> `main`; this plan doc and ADR-0037 land on the umbrella `main` per the doc/code
> split in [CLAUDE.md](../../CLAUDE.md).
>
> **`feat/mxl-spike` retired 2026-06-03.** It turned out to be *fully contained in*
> `main` in every repo (zero feat-only commits — `dmf-cms` / `dmf-env` / `dmf-infra`
> / `dmf-media` / `dmf-runbooks` + umbrella), so the reconcile was a no-op. The
> stale branch, its linked worktrees (`~/repos/dmf-mxl-spike/*`), and the Forgejo
> `feat/mxl-spike` refs were all removed; `main` is fully pushed. All MXL work
> (`mxl-hello` chart, fabrics demo, dmf-cms MXL-view, launchers, JTs) lives on
> `main`. Verify each sub-repo's `HEAD == main` before touching it (shared checkouts).

---

## 0. TL;DR

Make the deployed MXL media function visible in the operator console **the EBU
way**: not as a bespoke "MXL Flows" page, but as a **"Media Workloads"** surface
that answers *"what Media Functions are deployed, how many, and where?"* — scoped
to a **media-engineers** group and the **tenant/site** a user may view, sourced
from **NetBox** (instances + placement only; **no flows in NetBox**). Prove it
end-to-end with the smallest substrate: the single-node intra-host `mxl-hello`
Media Function on the sandbox.

---

## 1. Context — how we got here

The thread, in order:

1. **"Can MXL work on the sandbox lane?"** Yes, for the **intra-host `mxl-hello`**
   demo (tmpfs ring; one pod, multi-container). It was already proven on a
   single-node ARM64 Lima **Debian-12** VM — see
   [DMF MXL Single-Node Loopback Execution Plan §8](DMF%20MXL%20Single-Node%20Loopback%20Execution%20Plan%202026-05-29.md).
   The **cross-host fabrics** demo (`mxl-videotestsrc`/`view`) needs ≥2 nodes by
   design and stays on the `dev/lima` 2-node harness — see
   [DMF MXL On-Demand Media Function Cycle Plan](DMF%20MXL%20On-Demand%20Media%20Function%20Cycle%20Plan%202026-06-01.md)
   and [DMF MXL M1.1 Catalog Launch Design](DMF%20MXL%20M1.1%20Catalog%20Launch%20Design%202026-06-01.md).

2. **OS divergence is a non-issue.** Upstream `mxl/examples/Dockerfile` (the
   stages that build `mxl-info`/`mxl-gst-testsrc`/`mxl-fake-reader`, i.e. the
   `mxl-hello` containers) is `FROM debian:trixie-slim`. Ubuntu only appears in
   `mxl/.devcontainer/Dockerfile` (the *dev* environment). Containers decouple
   image OS from host OS anyway. So the Debian sandbox runs these images natively.

3. **Upstream MXL state** ([github.com/dmf-mxl/mxl](https://github.com/dmf-mxl/mxl) @
   **v1.0.1**): the intra-host **Flow API is stable**; the cross-host **Fabric
   API is still roadmap ("tbc")**; no NMOS/registry in the SDK. ⇒ the single-node
   intra-host demo is the standards-stable thing to lead with.

4. **Exposure rethink.** A standalone "MXL Flows" page (the spike's approach) is
   MXL-specific and built for the cross-host narrative; it shows a lonely card for
   one intra-host node. Reading the **EBU whitepaper** reframed the question:
   *where does a deployed Media Function belong in the console, in EBU terms?*

5. **The EBU answer → "Media Workloads".** A **Media Workload** is "an assembly of
   Media Functions for a production" (whitepaper Fig 1; [EBU Mapping](../architecture/DMF%20EBU%20Mapping%20(2026-04-25).md)).
   The operator's real question is the fleet question — *what/how-many/where* —
   which is what **NetBox** (the facility SoT) answers natively. A **Flow** is
   *live* Media-Exchange state ("Monitor Status of Flows" lives in the
   **Monitoring** vertical, whitepaper Annex C) → it is **observed runtime state,
   not config**, and must **not** be persisted in NetBox.

6. **Simplification (operator):** don't model flows or a workload-graph object in
   NetBox at all — **purely Services (Media Function instances)**: record how many
   of each function are deployed and where, so an operator can **filter by Media
   Function and see the resources**. The composition/flow graph is a *future
   runtime overlay*, not this work.

This is the [ADR-0027](../decisions/0027-catalog-instance-vs-definition-separation.md)
promotion trigger (MXL = the named "second function"), resolved toward
**NetBox instances + AWX reconcile** instead of a `MediaFunctionInstance` CRD +
custom operator. Recorded as [ADR-0037](../decisions/0037-media-workloads-netbox-instance-inventory.md).

---

## 2. Locked architecture model (three stores)

| Store | Owns | Answers |
|---|---|---|
| **git catalog** — `dmf-media/catalog/<key>.yaml` ([ADR-0013](../decisions/0013-media-function-catalog-model.md)) | Media Function **definitions** (versioned, immutable) | what *can* be deployed |
| **NetBox** | Media Function **instances** + **placement** (tenant/site/AZ/cluster/node) + lifecycle status. **No flows, no graph object.** | how many of X, and where |
| **k3s** | **actual runtime** + **scheduling** (nodeSelector/affinity/taints — [ADR-0017 §5](../decisions/0017-mxl-intra-host-data-plane.md)) | places instances within NetBox-scoped eligibility |

- **AWX = reconciler/glue** — translates a *cleared* desired instance-set in NetBox
  into a parameterised Helm deploy, then born-inventory records *where it landed*.
  Reuses the existing NetBox↔AWX loop (`nb_inventory`, `694-born-inventory.yml`,
  `lifecycle/operate-catalog-drift.yml`). **No new engine.**
- **k3s schedules; NetBox scopes.** Don't build a scheduler in NetBox/AWX.
- **Desired-vs-observed:** NetBox = desired + recorded placement; **live flow
  telemetry never enters NetBox** (Monitoring vertical owns it).
- **Authz is a hard backend boundary** ([ADR-0028](../decisions/0028-identity-and-authority-chain.md)),
  not a frontend filter — enforced on read **and** on the consequential "clear for
  deployment" action (C5 quartet: actor/role/request-id/reason; UX Constitution Art. 7).

---

## 3. Workflow documentation (read before implementing)

**ADRs**
- [ADR-0037](../decisions/0037-media-workloads-netbox-instance-inventory.md) — this model (governing).
- [ADR-0027](../decisions/0027-catalog-instance-vs-definition-separation.md) — three-layer split (amended here).
- [ADR-0013](../decisions/0013-media-function-catalog-model.md) — catalog YAML + NetBox tag.
- [ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md) — in-cluster Helm via AWX EE (launch mechanism).
- [ADR-0017](../decisions/0017-mxl-intra-host-data-plane.md) — MXL intra-host + placement contract + reaper.
- [ADR-0028](../decisions/0028-identity-and-authority-chain.md) — identity/authority; C5 quartet for the clear action.
- [ADR-0032](../decisions/0032-catalog-launcher-scoped-netbox-writer.md) — scoped NetBox writer (`dmf-catalog-svc`) for instance writes.
- [ADR-0005](../decisions/0005-version-as-single-source-of-truth.md) — dmf-cms `VERSION` is the single source of truth.
- [ADR-0010](../decisions/0010-run-playbook-as-sanctioned-entry.md) — `bin/run-playbook.sh` is the only sanctioned ansible entry point.

**Architecture / UX**
- [EBU DMF Mapping](../architecture/DMF%20EBU%20Mapping%20(2026-04-25).md) — layer/vertical/lifecycle vocabulary; Media Workload = assembly.
- Whitepaper: `~/Downloads/EBU_White_Paper_The_Dynamic_Media_Facility_Reference_Architecture.pdf` (Figures 1–3, Annex C orchestration grid).
- [DMF Console UX Constitution](../design/DMF%20Console%20UX%20Constitution%202026-05-25.md) — Art. 3 (vocabulary tiers), Art. 7 (consequence/impact preview).
- [DMF Console Glossary](../design/DMF%20Console%20Glossary.md) — the term-tier source of truth (this work promotes "Media Workload"/"Media Function").

**Sandbox + MXL plans**
- [WP1S Single-Node Sandbox Lane](DMF%20OSS%20v0.1%20WP1S%20Single-Node%20Sandbox%20Lane%202026-05-25.md) — the target lane + profile vars.
- [MXL Single-Node Loopback Execution Plan](DMF%20MXL%20Single-Node%20Loopback%20Execution%20Plan%202026-05-29.md) — `mxl-hello` chart + local rehearsal proof.
- [MXL upstream profile & contribution review](../reviews/dmf-mxl-upstream-profile-and-contribution-review-2026-06-01.md).

**Skills (operational workflow — read §0 of each before running)**
- `dmf-cms-build-and-release` — the only sanctioned dmf-cms release path; pairs with `dmf-cms/docs/DEVELOPMENT-AND-BUILD-RULES.md`.
- `dmf-cluster-access` — inspect/change live cluster state.
- `dmf-openbao-unseal` — unseal procedure (if secrets are touched).

---

## 4. Required scripts & files (with paths)

> Component repos are `.gitignore`d siblings of the umbrella; paths below are
> repo-relative. The live spike worktree is `~/repos/dmf-mxl-spike/<repo>/`.

**dmf-cms — release toolchain** (per `dmf-cms/docs/DEVELOPMENT-AND-BUILD-RULES.md` §2 "The Five Scripts" + §4):
- `dmf-cms/VERSION` — **`0.10.0`** as of 2026-06-03 (MXL Flows page release); the Media Workloads page release bumps to **`0.11.0`**.
- `dmf-cms/scripts/sync-version.sh` — propagate VERSION.
- `dmf-cms/scripts/build-image.sh` — local arm64 image build.
- `dmf-cms/scripts/release.sh` — orchestrates: (1) publish to GHCR → (2) mirror GHCR→Zot via **playbook 630** → (3) Helm-deploy via **playbook 650**.
- `dmf-cms/scripts/publish-to-ghcr.sh` — thin wrapper over the umbrella `bin/publish-image-to-ghcr.sh`; asserts `IMAGE_TAG == VERSION` (ADR-0005); token via Keychain/stdin, never argv.
- `dmf-cms/scripts/verify-cluster.sh` — post-deploy cluster check.

**dmf-cms — code to extend**
- `dmf-cms/src/dmf_cms/main.py` — add `GET /api/media-workloads` (pattern: the `/api/catalog` handler at the `api_catalog_list` route).
- `dmf-cms/src/dmf_cms/catalog.py` — `get_lifecycle_status(...)` (NetBox read); add instance-count/placement query helpers here.
- `dmf-cms/src/dmf_cms/settings.py` — settings dataclasses (tenant-scope config lands here; `MXLEndpoint` is the runtime-overlay precedent).
- `dmf-cms/src/dmf_cms/awx.py` — AWX client (only if the page triggers actions).
- `dmf-cms/frontend/src/components/Sidebar.tsx` — add the nav entry (`onlyRoles`/group gate, like the existing `Admin` entry).
- `dmf-cms/frontend/src/pages/MediaWorkloads/` — new page (patterns: `pages/Catalog/index.tsx`, `pages/Facility.tsx`).

**dmf-runbooks — launchers (copy the pattern)**
- `dmf-runbooks/playbooks/launch-nmos-cpp.yml` + `dmf-runbooks/playbooks/launch-mxl-fabrics-demo.yml` → write `launch-mxl-hello.yml`.
- `dmf-runbooks/playbooks/teardown-mxl-fabrics-demo.yml` → write `teardown-mxl-hello.yml`.

**dmf-infra — AWX job templates + reconcile**
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml` — add `media-launch-mxl-hello` / `media-finalise-mxl-hello` JTs (pattern: commit `cfad127` added the fabrics JTs here).
- `dmf-infra/k3s-lab-bootstrap/playbooks/691-netbox-sot.yml` — NetBox SoT/tags.
- `dmf-infra/k3s-lab-bootstrap/playbooks/693-awx-integration.yml` — applies the JTs.
- `dmf-infra/k3s-lab-bootstrap/playbooks/694-born-inventory.yml` — records placement back to NetBox.
- `dmf-infra/k3s-lab-bootstrap/playbooks/lifecycle/operate-catalog-drift.yml` — clone for the reconcile-drift job (D5).
- `dmf-infra/k3s-lab-bootstrap/playbooks/630-zot-seed-platform.yml` / `650-dmf-cms.yml` — mirror + deploy (driven by `release.sh`).
- Sandbox wrappers: `dmf-infra/k3s-lab-bootstrap/bootstrap-sandbox-{configure,verify}.yml`.

**dmf-media — MXL Media Function**
- `dmf-media/catalog/mxl-hello.yaml` — exists; needs a real image ref (or tag + `IfNotPresent`).
- `dmf-media/charts/mxl-hello/` — `values.yaml`, `templates/deployment.yaml` (reaper sidecar + placement already correct for single-node).

**Upstream MXL build**
- `mxl/examples/Dockerfile` (umbrella sibling clone) — multi-stage Debian build; **pre-patch** the hardcoded `x86_64-linux-gnu` lib `COPY` → `aarch64-linux-gnu` for arm64.
- Sandbox side-load: `k3s ctr images import <tar>` (no registry/digest needed for the sandbox).

**dmf-env — entry points**
- `dmf-env/bin/run-playbook.sh <env>` — sanctioned ansible entry (ADR-0010).
- `dmf-env/bin/recreate-sandbox-vm.sh` — sandbox VM lifecycle.

---

## 5. Deliverables (detailed)

### D1 — ADR ✅ done (doc)
[ADR-0037](../decisions/0037-media-workloads-netbox-instance-inventory.md) written; ADR-0027 + INDEX cross-links updated. **Review gates the build:** Architecture Reviewer on the model; Security & Secrets on the tenant-scope authz boundary (§6).

### D2 — MXL substrate: `mxl-hello` deployable on the sandbox
- **Image:** build arm64 `mxl-info` / `mxl-gst-testsrc` / `mxl-fake-reader` from `mxl/examples/Dockerfile` (patch the aarch64 lib `COPY`); **side-load** into `dmf-sandbox` k3s containerd (`k3s ctr images import`); chart references by **tag** + `pullPolicy: IfNotPresent` (sidesteps the all-zeros placeholder digest in `mxl-hello.yaml`).
- **Launchers:** `launch-mxl-hello.yml` / `teardown-mxl-hello.yml` in `dmf-runbooks` — `helm pull` (Zot/local) → `helm upgrade --install` → `k8s_info` readiness; teardown = `helm uninstall` (tmpfs domain dies with the pod; reaper is the in-pod sidecar already in the chart, [ADR-0017](../decisions/0017-mxl-intra-host-data-plane.md)).
- **AWX JTs:** `media-launch-mxl-hello` / `media-finalise-mxl-hello` in `awx-integration/defaults/main.yml`.
- Chart placement defaults already correct (empty `nodeSelector`/`tolerations` = any single node).

### D3 — NetBox records instances + placement, queryable by function
- Reuse the `provision.netbox_service` block + tag convention (`app:<key>`, `dmf-catalog`, `lifecycle:*`) already in `mxl-hello.yaml`.
- Ensure **count-per-function** and **placement** (tenant/site/cluster/node) are queryable; `694-born-inventory.yml` records *where* an instance landed. No flow/graph objects.

### D4 — dmf-cms "Media Workloads" page (+ sanctioned release)
- **Frontend:** `pages/MediaWorkloads/` + `Sidebar.tsx` nav entry gated to **media-engineers**; list instances (count + where), **filter by Media Function**; live status overlay from runtime (degrades gracefully; for `mxl-hello`, the `info` container — a status endpoint is optional/deferrable).
- **Backend:** `GET /api/media-workloads` in `main.py`; instance/placement query helpers in `catalog.py`; **server-side tenant/site scope** (hard authz — not a frontend filter).
- **Release (sanctioned only):** bump `dmf-cms/VERSION` `0.10.0 → 0.11.0`; run `release.sh` (→ `publish-to-ghcr.sh` → 630 mirror → 650 deploy) per the `dmf-cms-build-and-release` skill + `DEVELOPMENT-AND-BUILD-RULES.md`. (`0.10.0` was consumed on 2026-06-03 by the **MXL Flows page** release, which retired the spike's `915-mxl-cms-override` dev-image hack and published `ghcr.io/dmfdeploy/dmf-cms:0.10.0`.)

### D5 — declarative clear→reconcile loop (phase 2 of the slice)
- Templated operator "design" writes a **desired** instance-set + scope + a **"cleared for deployment"** status into NetBox.
- A `media-workload-reconcile` AWX job (scheduled **poll** first; webhook later) reads cleared desired instances and converges via the D2 launchers; drift detection cloned from `lifecycle/operate-catalog-drift.yml`.
- Lead with D2–D4 as a **record/inventory view** (deploy via the existing catalog path, NetBox records, page shows the fleet); add D5 after.

---

## 6. Reviews / risks / open questions

- **Security review (gates D4 release):** tenant/site scope with today's single
  service NetBox token means the console enforces group→tenant mapping; per-user
  NetBox tokens are deferred. The "clear for deployment" action is consequential
  (C5 quartet). Route through `Security & Secrets`.
- **Architecture review (gates D2–D5):** confirm the ADR-0037 three-store model +
  the AWX-as-reconciler choice vs ADR-0027's CRD. Route through `Architecture Reviewer`.
- **Vocabulary (UX Art. 3):** the page promotes "Media Workload"/"Media Function"
  to operator-native — update the [Glossary](../design/DMF%20Console%20Glossary.md) tiers when it ships.
- **Naming truth:** MVP content is a Media *Function* instance inventory; the page
  is named "Media Workloads" (destination); the *assembly/flow graph* arrives with
  the runtime overlay.
- **Sandbox RAM:** `mxl-hello` tmpfs is small, but measure on `dmf-sandbox`
  (AWX/Authentik/NetBox already tight per WP1S §3).

---

## 7. Verification (sandbox, end-to-end)

1. Build + side-load arm64 `mxl-*` images into `dmf-sandbox` k3s.
2. Deploy `mxl-hello` (catalog → AWX JT → `launch-mxl-hello.yml`): pod group Ready; `mxl-info` shows `Active` + advancing head index.
3. NetBox shows 1 `mxl-hello` Service instance with node/site placement.
4. **Media Workloads page** (media-engineers user, scoped tenant/site): `mxl-hello` shows count=1 + where; filter-by-function works; an out-of-scope user does **not** see it (backend-enforced).
5. Teardown → count returns to 0; page reflects it.
6. (D5) mark a templated design "cleared" → reconcile job stands it up.

---

## 8. Explicitly deferred (not this work)

Flow/composition **graph** (future runtime overlay: Media Exchange status → NMOS);
cross-host **fabrics** multi-node demo (stays on `dev/lima`); free interactive
**composition canvas**; per-user NetBox tokens; the standalone **"MXL Flows"** page
(folds into the runtime overlay later); Grafana/Prometheus MXL metrics (future,
once the sandbox monitoring vertical is green).

---

## 9. Cross-reference

- Decision: [ADR-0037](../decisions/0037-media-workloads-netbox-instance-inventory.md) · amends [ADR-0027](../decisions/0027-catalog-instance-vs-definition-separation.md)
- Approved working plan (scratch): `~/.claude/plans/parsed-dazzling-scott.md` (this doc is its canonical, expanded form per the docs/plans convention).
