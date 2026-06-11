# DMF Function Catalog Model

**Status:** Architecture reference for ADR-0013 (catalog), ADR-0012
(Configure stage), ADR-0014 (AWX project layout), ADR-0016 (Path A
control-node SSH execution model — partially superseded by
[ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md)
for `media-*` JTs per the
[2026-05-19 Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan](../plans/DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md)).
**Date:** 2026-05-04 (refreshed 2026-05-07: added `dmf-runbooks` to scope
following 2026-05-06 Path A pivot. 2026-05-19: catalog launcher transport
moving to EE-as-runtime + Helm per ADR-0025; document still applies — the
catalog *model* is unchanged, only the launcher's *transport* changes.)
**Repos in scope:** `dmf-cms`, `dmf-infra`, `dmf-media`,
`dmf-runbooks` (launchers + currently the `nmos-cpp` role; future Layer 5
roles may live in `dmf-media`). Catalog-eligible source repos may grow
over time.

This document is the canonical reference for the catalog model. Read
the linked ADRs for the *decision*; this doc spells out the *shape*.

---

## 1. Concept

A **function catalog** is the set of media functions and applications
that are *available in the cluster but not necessarily running*. Each
entry is a deployable unit — a Helm release plus configuration plus
NetBox SoT updates — that an operator can launch or tear down from
dmf-cms.

The model maps directly onto EBU Figure 4 (Orchestration Model, white
paper p.6):

```
PROVISION column (Layer 5 — Media Functions row):
  ─ Download Media Functions    →   catalog entry registered, image cached,
                                    chart present, lifecycle:bootstrapped
CONFIGURE column (Layer 5 row):
  ─ Launch Media Functions      →   workload running, lifecycle:active
  ─ Configure Media Functions   →   parameters applied, connections set
FINALISE column:
  ─ Stop Media Functions        →   workload removed, lifecycle:bootstrapped
```

The catalog answers the operator-facing question: *"what can I deploy
right now?"* — and answers the corollary: *"what is currently deployed?"*

---

## 2. Catalog entry schema

Each entry lives at `<source-repo>/catalog/<key>.yaml`. v1 schema:

```yaml
# dmf-media/catalog/nmos-cpp.yaml — illustrative
key: nmos-cpp                    # unique within the platform
display_name: "NMOS Registry"    # operator-visible
summary: |                       # 1-2 sentence operator description
  AMWA NMOS IS-04/05 registration & discovery service. Required
  before any media-function flow can be routed.

# EBU placement (must match ADR-0003 vocabulary)
ebu:
  layer: 5                       # 1..6 (typically 4, 5, or 6)
  vertical: orchestration        # one of: orchestration | control |
                                 # monitoring | security (or omitted)
  lifecycle_owner: configure     # which wrapper drives launch:
                                 # provision (Layers 1-3 baseline) or
                                 # configure (Layers 4-6 catalog entries)

# Artifacts the Provision stage ensures are present
provision:
  namespace: nmos                # k8s namespace where the chart deploys —
                                 # source of truth for drift detection and
                                 # any operator that needs to locate the
                                 # workload. Added 2026-05-12 per decision
                                 # catalog-namespace-source-of-truth (Opt A).
  image:
    repository: registry.dmf.example.com/dmf/nmos-cpp
    digest: sha256:...           # MUST be a digest, not a tag (DMF Plan §8f)
  chart:                         # canonical home: dmf-media/charts/<key>/ (ADR-0025)
    name: nmos-cpp
    version: 0.1.0
    source: oci://zot.zot.svc.cluster.local:5000/dmf/charts/nmos-cpp
  netbox_service:
    name: nmos-cpp
    protocol: tcp
    ports: [80]
    parent_object: load_balancer # generic-relation target type from Move 2 learnings
    tags: [dmf, "app:nmos-cpp", "exposure:private", "lifecycle:bootstrapped"]

# Artifacts the Configure stage applies on launch
configure:
  playbook: configure-media/launch-nmos-cpp.yml   # path within source repo
  awx_job_template: media-launch-nmos-cpp         # name as created in AWX
  on_success_tag: "lifecycle:active"              # NetBox tag flip
  health_probe:                                   # how Operate-stage and dmf-cms verify
    kind: http
    path: /x-nmos/query/v1.3/nodes/
    expect_status: 200

# Artifacts the Finalise stage applies on teardown
finalise:
  playbook: configure-media/teardown-nmos-cpp.yml
  awx_job_template: media-finalise-nmos-cpp
  on_success_tag: "lifecycle:bootstrapped"        # back to available-but-inactive

# Soft dependencies — informational for v1, enforced in v2
dependencies: []                  # e.g. [ "ptp-monitor" ] for media functions
                                  # that need PTP before launch makes sense
```

**Field notes:**

- `key` is the unique handle threaded through everything (NetBox tag,
  AWX JT name, dmf-cms button id, role directory name).
- `ebu.lifecycle_owner` is the bridge to ADR-0012: entries with
  `provision` are bottom-3-layer style (auto-launched in
  `lifecycle-provision.yml`); entries with `configure` are catalog-
  driven (registered in Provision, launched in Configure).
- `provision.netbox_service.tags` MUST include exactly one
  `lifecycle:*` tag at any time. The Provision stage writes
  `lifecycle:bootstrapped`; Configure flips it to `lifecycle:active`;
  Finalise flips it back. Drift here is the single load-bearing
  invariant of the catalog model.
- `dependencies` is informational v1 (a TODO list dmf-cms shows the
  operator). v2 may enforce ordering or block deployment until deps
  are `lifecycle:active`. Do not over-design v1.

---

## 3. Source-of-truth split (YAML vs NetBox)

Two stores answer two different questions:

| Question | Source of truth | Lifetime |
|---|---|---|
| What functions exist in the platform? | YAML manifests in source repos | Git history |
| Which are currently deployed in this cluster? | NetBox `ipam.Service` tag | Cluster runtime |
| What does the function look like (image, chart, schema)? | YAML | Git history |
| What endpoint is the deployed instance reachable at? | NetBox `ipam.Service` (description/comments + Helm release output) | Cluster runtime |

Convention: when YAML and NetBox disagree, **NetBox is the truth about
runtime state, YAML is the truth about intent.** Drift means a Configure
or Finalise playbook didn't complete; it's an alert, not a normal state.

dmf-cms reads both: it joins YAML metadata (display name, summary,
schema) with NetBox runtime state (current `lifecycle:*` tag, endpoint).
Catalog entries that exist in YAML but not NetBox are "not provisioned
on this cluster" (a possible future state if the cluster intentionally
omits some functions). Catalog entries that exist in NetBox but not
YAML are an error condition (orphaned runtime record) and should
surface as a warning.

---

## 4. Lifecycle integration

Per ADR-0012, the wrappers are:

| Wrapper | EBU stage | Role for catalog entries |
|---|---|---|
| `lifecycle-provision.yml` | Provision | Walk Layers 1–6 baseline; for each catalog entry, ensure image is in Zot, chart is in OCI, NetBox `ipam.Service` is registered with `lifecycle:bootstrapped`. Workload is **not** deployed for catalog entries with `lifecycle_owner: configure`. |
| `lifecycle-configure.yml` *(new)* | Configure | Per-entry playbook invocation. Default behavior is "no-op for entries already `lifecycle:active`". Tag-scoped: `--tags <key>` runs one entry's launcher. |
| `lifecycle-operate.yml` | Operate / Monitor | Existing behavior (smoke tests, verify). Extended to assert NetBox tag matches Helm release presence per entry — drift detector. |
| `lifecycle-finalise.yml` | Finalise & Review | Existing behavior (full teardown). For per-entry teardown, prefer `lifecycle-configure.yml --tags <key> --extra-vars finalise=true` or an explicit teardown wrapper; v1 keeps it pragmatic. |

Per-function playbooks live in their source repo:

```
dmf-media/
  catalog/
    nmos-cpp.yaml
    ebu-list.yaml                  # future
    ptp-monitor.yaml               # future
  playbooks/
    410-nmos-cpp-provision.yml     # registers catalog entry, no launch
    configure-media/
      launch-nmos-cpp.yml          # invoked by lifecycle-configure
      teardown-nmos-cpp.yml        # invoked by finalise
```

Layer 1–3 + Layer 6 baseline apps (Authentik, Forgejo, AWX, NetBox,
…) keep their current behaviour: their provisioning playbooks both
register and launch in one pass. They MAY be migrated to catalog-style
entries in a v2 sweep, but Move 1 does not require it.

---

## 5. AWX wiring (per ADR-0014; transport per [ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md), 2026-05-19)

The Configure path runs through AWX so the operator's click in dmf-cms
produces an audit trail. **As of 2026-05-19** the launcher runs in a
custom AWX Execution Environment pod inside the cluster (per
[ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md)),
not via SSH-to-control-node. The workload itself ships as a Helm chart in
`dmf-media/charts/`; the launcher in `dmf-runbooks` is thin and does the
NetBox-side work plus a `kubernetes.core.helm` install.

```
dmf-cms (Deploy click)
   │  POST /api/v2/job_templates/<media-launch-nmos-cpp>/launch/
   ▼
AWX
   │  spawns EE pod from zot.zot.svc.cluster.local:5000/dmf/awx-ee:<tag>
   │  in the catalog function's namespace (e.g. nmos) under SA
   │  nmos-cpp-launcher  (per Lane B Container Group / pod_spec_override)
   │  reads project: dmf-runbooks (Forgejo)
   │  runs playbook: launch-nmos-cpp.yml  (thin launcher, hosts: localhost,
   │  connection: local)
   ▼
launcher (dmf-runbooks/playbooks/launch-nmos-cpp.yml)
   │  1. include_role: nmos-cpp  vars: nmos_stage=provision
   │     → NetBox tag taxonomy + ipam.Service (lifecycle:bootstrapped)
   │  2. kubernetes.core.helm:
   │       name: nmos-cpp
   │       chart_ref: oci://zot.zot.svc.cluster.local:5000/dmf/charts/nmos-cpp
   │       release_namespace: nmos
   │  3. include_role: nmos-cpp  vars: nmos_stage=finalise_tags
   │     → flip NetBox tag to lifecycle:active
   ▼
chart (dmf-media/charts/nmos-cpp/templates/)
   │  applies StatefulSet + Services + PVC + ConfigMaps
   │  pulls images from zot.zot.svc.cluster.local:5000/dmf/nmos-cpp-*
```

**Repository split:**
- `dmf-runbooks/playbooks/<launch|teardown>-<key>.yml` — thin AWX launcher
- `dmf-runbooks/roles/<key>/` — NetBox-side role (provision tags, flip lifecycle tag, finalise)
- `dmf-media/charts/<key>/` — Helm chart (canonical home for k8s manifests)
- `dmf-media/catalog/<key>.yaml` — catalog entry metadata (consumed by dmf-cms)

AWX projects:
- `dmf-runbooks` — thin launchers + per-function NetBox-side roles
- `dmf-media` (mirror) — chart source + catalog metadata
- `dmf-infra` (mirror) — canonical roles + playbooks for Layer 2–3 + 6 (still use SSH-to-control-node per ADR-0016 — unchanged)
- (Future) `dmf-central` (mirror) — federation work

**Historical note:** before 2026-05-19, the launcher SSHed to the k3s
control node and ran `kubernetes.core.k8s` against the local kubeconfig
(ADR-0016 Path A). The role at `dmf-runbooks/roles/nmos-cpp/` carried the
manifests inline (`tasks/configure.yml`). The 2026-05-17 `aliyun-123`
failure (AWX job 44) — caused by a Hetzner-specific hardcoded private-IP
map — triggered the move to in-cluster Helm. See
[`docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`](../plans/DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md).

AWX `roles_path` is set so launcher playbooks can `import_role` across
projects. The `awx-integration` role manages project creation and
job-template creation per catalog entry (template name pattern:
`media-launch-<key>` and `media-finalise-<key>`).

---

## 6. dmf-cms responsibilities

dmf-cms is the operator-facing surface. Its responsibilities:

1. **Read the catalog.** Pull YAML manifests from a known source
   (in-cluster Forgejo, served as a manifest endpoint or via a sync
   job) and join with NetBox runtime tags.
2. **Render entries.** One card per entry showing display name,
   summary, current `lifecycle:*` state, dependencies, and (when
   `lifecycle:active`) the health-probe result + endpoint.
3. **Trigger Configure/Finalise via AWX.** Deploy button → POST to
   AWX `/api/v2/job_templates/<media-launch-<key>>/launch/`.
   Teardown button → corresponding `media-finalise-<key>` JT.
4. **Poll status.** Existing pattern from Move 2 (`awx.py` →
   `awx_get_job_status(job_id)`). Update card state from
   AWX job status + NetBox tag re-read after the job completes.
5. **Surface drift.** Catalog entries where YAML and NetBox disagree
   (e.g., NetBox shows `lifecycle:active` but Helm release is missing,
   or vice versa) get a warning badge with a "rerun configure" or
   "rerun finalise" action.

dmf-cms does NOT:
- Apply manifests directly. All cluster mutation goes through AWX.
- Hold catalog state independently of NetBox + YAML. Restart-safe by
  construction.
- Carry per-user audit identity (deferred per Move 2 learnings).

---

## 7. Failure modes & drift detection

| Failure | Symptom | Recovery |
|---|---|---|
| Configure playbook fails mid-flight | NetBox tag unchanged (`lifecycle:bootstrapped`), Helm release partial | Operator clicks Teardown → Finalise cleans up partial state, then Deploy retries |
| Finalise playbook fails mid-flight | NetBox tag flipped to `:bootstrapped`, Helm release still present | Drift detector flags; operator reruns Finalise |
| YAML manifest changes (image bump) without Provision rerun | NetBox unchanged, but Configure would deploy new image | `lifecycle-provision.yml` is the way to apply YAML changes; CI gate or skill check warns when YAML edits aren't followed by a provision run |
| NetBox `ipam.Service` deleted manually | dmf-cms shows "not provisioned" for an entry that has a Helm release | Provision rerun re-creates the SoT record |
| AWX project out of sync with Forgejo mirror | Launcher playbook references a role version that doesn't exist | AWX SCM-sync on every job-template launch (already AWX default) catches this |

Drift detection in v1 = Operate-stage smoke test that walks each
catalog entry and asserts:
- `lifecycle:active` ↔ Helm release exists, health probe returns expected status
- `lifecycle:bootstrapped` ↔ Helm release does NOT exist

---

## 8. v1 scope vs deferred

**v1 (Move 1):**
- One catalog entry: `nmos-cpp`
- `lifecycle-configure.yml` exists with one tagged entry
- `dmf-runbooks` + 2 mirrored AWX projects
- dmf-cms catalog page reads YAML + NetBox, renders one entry, Deploy/Teardown buttons work
- Drift detection in the Operate-stage smoke test

**v2 (post-Move-1, post-commit-gate):**
- Additional Layer 4–5 entries (ebu-list, ptp-monitor, flow-exporters)
- Dependency enforcement (block Configure if deps not active)
- Migration of Layer 6 baseline apps to catalog-style entries (optional —
  evaluate value vs disruption)
- **Schema additions for MXL-consuming entries (per ADR-0017):**
  - `mxl_flows: { produces: [<flow-key>...], consumes: [<flow-key>...] }`
    — declares the data-plane contract; dmf-cms uses this to validate
    that all members of a graph land on the same processor node and to
    surface broken graphs when they don't.
  - `tolerations` and `nodeSelector` (standard k8s shapes) — entries
    that consume MXL must tolerate the `dmf.io/mxl=true:NoSchedule`
    taint and select `dmf.io/role=mxl-processor`. dmf-cms reads these
    from the catalog YAML and surfaces them at Deploy time.
  - These three fields are inert for non-MXL entries (e.g. nmos-cpp v1
    does not consume MXL). Catalog v1 may ignore them; catalog v2
    validates the shape and enforces the co-location invariant.

**v3+ (deferred until forcing function appears):**
- Multi-instance support (e.g. dual NMOS registries for HA)
- Per-user identity propagation through AWX
- Parameterised launches (operator-supplied variables at deploy time)
- Cross-cluster catalog (federation; ties to dmf-central thesis-killer)
- Approval workflow for high-impact deploys (the config-change PR-gated lane from DMF Platform Plan §9, only applies to a subset of catalog entries — most are operations-lane)

---

## 9. References

- ADR-0003 — EBU V2.0 layer/vertical/lifecycle taxonomy
- ADR-0004 — Experiment phase, not hardening (frames v1 scope)
- ADR-0006 — Cluster is the truth, not local kubectl (drives the
  YAML-vs-NetBox split rationale)
- ADR-0010 — `bin/run-playbook.sh` is the only sanctioned ansible entry
- ADR-0012 — Configure stage distinct from Provision (precondition)
- ADR-0013 — Media function catalog model (this doc's decision-of-record)
- ADR-0014 — AWX project layout (execution precondition)
- ADR-0017 — MXL is an intra-host data plane (drives the v2 schema
  additions for MXL-consuming entries)
- `docs/architecture/DMF Platform Plan.md` §9 — two-lane model
  (config-change PR-gated, operations runtime)
- `docs/architecture/DMF EBU Mapping (2026-04-25).md` — vocabulary
- `docs/reviews/dmf-platform-strategic-review-2026-04-30.md` — Move 1
  framing, thesis-killers
- `docs/reviews/dmf-platform-move-2-learnings-2026-05-04.md` — what
  Move 2 taught us; specifically §Q2 (app-contract pivot) and §Q4
  (`ipam.Service` field gaps)
- `docs/plans/dmf-platform-move-1-task-2026-05-04.md` — implementation
  task spec
- `docs/plans/DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md` —
  technical reference for nmos-cpp implementation (Phase 1+2 reusable;
  Phase 3 superseded by the catalog model)
