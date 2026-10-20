---
status: draft
date: 2026-10-20
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/562
---
# DMF Media Workload Design Canvas Plan

This plan records the design state for the Design and Plan stages of a media
workload: what a workload is before anything is provisioned, where its design
lives, and what the console must prove before it shows one. The work is
scheduled under the `v0.3` milestone ("design and plan in the console"), and
the tracking issue is [#562](https://github.com/dmfdeploy/dmfdeploy/issues/562).

The plan records design state, not decisions. Where it depends on an open
question, it names the question (the RFCs from
[Discussion #564](https://github.com/orgs/dmfdeploy/discussions/564) and the
issues in §7) and doesn't settle it by implication.

## 1. The model

Operator decision, 2026-09-07, recorded on
[#490](https://github.com/dmfdeploy/dmfdeploy/issues/490) and
[#562](https://github.com/dmfdeploy/dmfdeploy/issues/562):

| Stage | Owns | Commits resources? |
|---|---|---|
| **Create** | A name. Nothing else. | No |
| **Design** | *What*: which media functions, and how they relate | No |
| **Plan** | *Where and with what*: binding to facility resources | Yes |
| **Provision** | Deploy | — |

This follows the EBU Design/Plan boundary. Create makes a blank container and
takes the operator to its home page. Template selection happens on Design and
facility selection on Plan. Because the workload exists from the moment it's
created, the "draft" concept disappears, and a count such as `0 elements
designed` is true rather than a placeholder.

Deferred by explicit decision:

- **Linking functions and authoring topology.** Design is selection-only for
  now; `topology_ref` comes from the git catalog.
- **Capacity calculation at Plan.** Capacity runs at provision preflight. A
  plan-time figure is a projection that can go stale before Provision, so if it
  ever ships, it must not read as settled.

## 2. Where design intent persists

**The gap.** A workload exists today only as a grouping derived from its member
service records. There is no independent container to enumerate, and a Design
selection lives in browser state until the page reloads. Member records survive
teardown with their lifecycle tag flipped, so the grouping is over inventory
records, not over what is running.

**Proposed direction (not settled):** design intent persists as declarative
artifacts in the in-cluster Forgejo, and Save is a commit. This needs an ADR
before any build, and it competes with the NetBox media plugin
([#563](https://github.com/dmfdeploy/dmfdeploy/issues/563); the question is
RFC [#605](https://github.com/dmfdeploy/dmfdeploy/issues/605)).

Whatever store is chosen must have these properties:

- **The console may cache, never own.** If dmf-cms stores something
  authoritative that isn't in the chosen store or NetBox, it becomes another
  source of truth.
- **Concurrent saves conflict visibly.** A save against a stale version is
  refused with a diff: never merged silently, never overwritten, never locked.
- **History is attributable.** Each save carries the C5 quartet (actor, role,
  request-id, reason).
- **Incompleteness is derived on read, never stored.** A half-finished design
  saves; it can't Plan or Provision, and the surface says why.
- **Local designs stay local** unless a facility chooses to publish them.
- **Layout is stored apart from semantics.** Moving a box doesn't change the
  design.
- **Any index is derived:** regenerable from the artifacts and never edited.

**The write path doesn't exist yet.** The console's Forgejo client and its
Forgejo identity are both read-only, by deliberate design. Choosing Forgejo
means a new write-scoped console credential and a git write client, with a
security argument for relaxing that posture. The consumers (AWX and NetBox)
already read from Forgejo, but the write side is new work.

## 3. Reconciliations with source

Discussion #564 lists five constraints any answer must reconcile. Each one is
checked here against the code.

### 3.1 NetBox records no edge; git holds declared intent, not live truth

The launcher stamps `topology-parent:<catalog entry key>` and
`topology-source:<declared sources[].id>`. Both name catalog content, not an
instance, and the viewer release gets neither tag. So NetBox records no
instance-to-instance edge, and a design model wouldn't be a second edge store.

A connection has three representations, and they must stay separable:

| Plane | Where it lives | Example |
|---|---|---|
| **Design intent**: what was declared | git catalog (`viewer.source_selection`) | source-a feeds the viewer |
| **Actuation state**: what was last commanded | the ConfigMap key the switch playbook writes | active source is now source-b |
| **Observed**: what is happening | read from the running instance | the viewer receives source-b's flow |

A switch rewrites actuation state without touching git, so the declared
selection goes stale as live truth after one switch. Git owns declared intent,
NetBox holds a back-pointer into git, and neither stores live state: the
ADR-0037 split. The direction is to widen the two existing tags into a
design-ref and design-element pair, not to invent a relationship model.

**Hazard.** A canvas that presents declared intent as the live signal path
fails gate 1 of the UX Constitution (requested is not observed).

### 3.2 The one-hop star: freeze it, don't grow it

The v1 topology contract asserts homogeneity: the viewer is not a list, and
sources are "N copies, not N distinct". Behind it sit a hard
`schema_version == 1` reject in two validators, a flat release-naming contract,
and a chart that knows only `role=source` and `role=view`.

`topology_params` v1 is a launch parameter set for one chart, not a design
representation, and it must not become one. The design graph is a new artifact
at a different layer; `topology_params` becomes something the platform emits for
charts of that shape. The deployed path doesn't change.

### 3.3 Selector inputs exist in the chart; the launcher never passes them

The chart accepts `placement.nodeSelector` and `placement.tolerations`; the
runbooks pass only `placementMode`, a networking mode. There is still no
channel for site, colocation, anti-affinity, timing domain or latency budget.

In split-node mode the templates add their own per-role node selectors. A
resolved selector must coexist with those pins. A mapping that overwrites them
schedules correctly in single-node mode and wrongly in split-node mode.

Plan persists a constraint, not a resolved node name. A resolution isn't
verifiable today anyway, because NetBox records neither facility nor node for
an instance ([#558](https://github.com/dmfdeploy/dmfdeploy/issues/558)).

### 3.4 Typed ports: the stub exists and nothing reads it

`mxl_flows: { produces, consumes }` is declared on the live catalog entry and
specified in ADR-0017, and no code consumes it. Its shape was kept to bare flow
IDs so the schema wouldn't get ahead of usage; compatibility validation at
Design would be that usage. The viewer's `consumes` matching a source's
`flow_id` is an implicit edge that nothing validates today.

ADR-0047 already uses "ports" for IPAM service ports, so a new concept needs a
distinct name from its first commit. Whether typed ports belong in the package
spec is open: [RFC #601](https://github.com/dmfdeploy/dmfdeploy/issues/601),
now [Discussion #621](https://github.com/orgs/dmfdeploy/discussions/621).

### 3.5 One catalog entry produces several services

The live catalog entry declares three `netbox_service` records, so a designed
function maps to zero, one or many records. Teardown patches each record's
lifecycle tag rather than deleting it. Record presence therefore doesn't track
deployment, and the tag is desired state, so "is it deployed?" needs an observed
read.

The design store keys nothing on service records. A design element's identity
is its declared-element slug, and its binding to a running service is the tag
pair from §3.1.

## 4. The neutral canvas

> **The platform owns the graph; vendors own the nodes.**

dmf-cms knows the grammar, never the vocabulary. It knows that a function
declares capabilities and ports, and it can render a capability badge, but it
doesn't contain the list of capabilities or know what `ptp.hardware` means.

| Content | Owner | Rule |
|---|---|---|
| Identity: names, nouns, icons, descriptions | Media function package or catalog entry | Read, never hardcoded |
| Requirements: capabilities, typed ports, resource profile, PTP/RDMA/ST 2110 | Media function schema | Declared, platform-bound |
| Instances and placement | NetBox | ADR-0037 |
| Live state: PTP lock, flow health, throughput | Prometheus, NMOS, MXL runtime | Never NetBox |

A PTP requirement is schema; a PTP lock status is telemetry; neither is a NetBox
field. The console keeps rendering primitives, the lifecycle rail, the alarm
taxonomy, the audit idiom, the honesty rules (empty, unreadable and unknown are
different; never guessed from a name) and the schema contract itself.

**The binding rule.**

> **The vendor declares; the platform binds.** A package may declare anything.
> Every declaration with a consequence outside the function's own pod is bound
> by the platform at install or admission time. The console never dereferences
> a package-supplied value; it dereferences a platform-bound record.

This is already the platform's posture: ADR-0047 binds publisher identity in a
project-controlled index, and the launcher stamps the ADR-0038 cluster fields.

**Hazard.** The console decides whether an instance has a live view by testing a
hardcoded namespace and port set, and that set is also an SSRF gate. A real
binder can replace it, but the allowlist must never become vendor-declared.

**Where the console isn't neutral today.** Five sites: a hardcoded map of five
function keys to display names (four no longer have catalog entries), an MXL
sidebar icon key, an `/mxl-flows` route, an MXL-shaped response type and
endpoint, and the allowlist above. The fix pattern already exists: a
catalog-declared display noun, and a value resolved server-side from the
catalog with null on every miss.

## 5. Acceptance properties

Each property is one executable assertion that covers several failure modes.

1. **Existence is read, not inferred.** On a complete enumeration, the multiset
   of workloads rendered equals the containers NetBox holds within the viewer's
   authorization, with no duplicates, against an inventory seeded independently
   of the code under test. The flat and grouped reads agree. On an incomplete
   enumeration, property 2 applies instead.
2. **Three states are independently representable.** A container with zero
   members reads as healthy and empty; one whose member read failed reads as a
   fault; the two never render alike. The response carries three facts:
   enumeration was complete; this container's member read returned zero;
   member data was unavailable.
3. **Emptiness never removes a tile.** Within a fixed authorization, a container
   leaves the page only by explicit permanent delete.
4. **Scope widens what exists, never who can see it.** An unscoped enumeration
   doesn't disclose another tenant's blank workload. This holds trivially under
   the single-tenant posture (§6.1) and becomes load-bearing if it's lifted.
5. **Create is attributable, idempotent and visible.** A created container has
   an audit record with the C5 quartet and appears in the console's Activity
   lane. A duplicate-slug create has defined semantics, and a partial success
   leaves no half-created container.
6. **A design round-trips.** A design saved at version *n* reads back as the
   same graph; a save against a stale version is refused with a diff.
7. **Incompleteness gates actions, not navigation.** An incomplete design
   saves, is reachable, says what is missing, and refuses Plan and Provision
   with the same reason.
8. **A count is never manufactured.** A count renders only when the read
   succeeded; a failed read never becomes zero; a blank container never shows
   `0 of 0`.
9. **Compatibility validation discriminates both ways.** A connection between
   incompatible ports is refused with the property named, and one between
   compatible ports is accepted. Prove the refusal by mutation and the
   acceptance against compatible reference functions.
10. **The console names no media function.** No media-domain proper noun
    appears in console source outside a narrow, platform-owned binding
    configuration. This fails today on the five sites in §4.

## 6. Rulings

### 6.1 Container scope (operator, 2026-09-11)

**Ownership is the media tenant; placement is not ownership.** Every authorized
media operator sees every workload in the tenant, including empty ones. The
tenant may span sites and clusters, placement is decided at Plan, and the
tenant boundary is recorded explicitly in configuration, never inferred.

**One installation, one media tenant.** A second tenant means a second
installation: isolation by separation, not by filtering a shared inventory.
This is a declared deployment posture, not a property of the code; the
console's `single` tenancy mode applies no filter at all. Under the posture a
container needs no tenant stamp, but `scoped` mode, the tenant and site terms
of the existing contract, and property 4 all stay. Lifting the posture
re-introduces a real ownership join.

Three things are called "tenant" and must not be conflated: the shared NetBox
tenant `DMF` (ADR-0039), the media tenant (ADR-0020), and the console's media
tenancy setting (empty keeps the surface dark, `single`, `scoped`).

### 6.2 Create's producer (operator, 2026-09-11)

**Creation is a direct write through the console backend.** Naming a workload
is not an orchestration event, and it must work while AWX is scaled to zero
(ADR-0043). It uses a scoped NetBox writer identity. Deletion stays with the
separate purge identity: the writer never holds delete, and the purge identity
never holds add or change (ADR-0032).

The console has no writer identity yet; its credential is set by no chart or
role ([#487](https://github.com/dmfdeploy/dmfdeploy/issues/487)). It has never
created a NetBox object either, so its writer's permission set is decided
against its own code paths, not copied from the AWX catalog writer.

Before implementation, define three behaviours:
- **Duplicate names.** Two workloads that derive the same slug merge silently
  today. Uniqueness must rest on the store's own constraint, not a
  read-then-write check.
- **Retries.** The writer makes one unretried call today.
- **Audit failure.** Decide what happens when the container is created but its
  audit record is not.

Under the single-tenant posture, a blank container is deleted through the
existing tag-only purge path. The work is to verify and integrate that flow,
not replace it.

### 6.3 Permissions direction (operator, 2026-09-15)

The direction is per-action permissions assignable by role, group or user. For
now, create uses the existing Media Workloads access check: `engineer` or
higher, or membership of `media-engineers`. That deliberately admits a viewer
in `media-engineers`, the same principals who can already read workloads and
clear them for deployment; create commits no resources.

Hold this loosely. Role gating and user management are v0.2 work
([#186](https://github.com/dmfdeploy/dmfdeploy/issues/186),
[#389](https://github.com/dmfdeploy/dmfdeploy/issues/389),
[#436](https://github.com/dmfdeploy/dmfdeploy/issues/436)), and ADR-0028, today's
anchor for human authorization, may be revised or replaced by it (see
[OPEN-QUESTIONS](../OPEN-QUESTIONS.md)). Don't scope identity work against
today's model. Whatever replaces it keeps these properties:

- **Roles are capability; groups are tenancy.** Grants don't collapse the two.
- **Read, create and delete keep separate authorization contracts.**
- **A grant to an empty group admits nobody,** so a test of the create gate
  constructs its principals explicitly.
- **Whether a refused action is audited is stated and justified,** not assumed.
- **Nothing here is a v0.1 capability claim;** ADR-0031 excludes enterprise
  RBAC from v0.1.

A pre-existing asymmetry needs its own issue: a bare `operator` can permanently
purge a media workload but can't list one, because the purge gate is `operator`
or higher with no group check, and `operator` ranks below `engineer`.

## 7. Sequencing

Each step is a prerequisite for the next.

| Step | Scope | Issue | State |
|---|---|---|---|
| 0 | Wire the console's NetBox writer credential | [#487](https://github.com/dmfdeploy/dmfdeploy/issues/487) | `v0.1-polish`; done when a chart or role sets it and the writer-dependent endpoint works on a deployed env |
| 1 | Blank containers: enumeration, name-only create, blank-container delete | [#562](https://github.com/dmfdeploy/dmfdeploy/issues/562), [#490](https://github.com/dmfdeploy/dmfdeploy/issues/490) | `v0.3`, ready |
| 2 | Stage behaviour: preconditions gate actions, not navigation | [#557](https://github.com/dmfdeploy/dmfdeploy/issues/557); facility and node recording in [#558](https://github.com/dmfdeploy/dmfdeploy/issues/558) | `v0.3`, ready |
| 3 | Design schema: functions, typed ports, connections, constraints, two-way validation, reference functions; no editor | none yet | **Parked** until v0.2 role gating and packaging land |
| 4 | Design persistence (§2) | none yet | **Parked** until v0.2 role gating and packaging land and the persistence ADR is decided |

- **Step 1 is one delivery boundary.** Enumeration, create and delete ship
  together or not at all; a container that can't be deleted is worse than none.
- **Property coverage.** Step 1 satisfies properties 1, 2, 3, 5 and 8, and
  step 2 satisfies property 7. Steps 3 and 4 own properties 6 and 9. Property
  10 can be worked independently.
- **Steps 3 and 4 wait for decisions, not effort.** Step 3 depends on the
  package spec and typed ports (ADR-0047, RFC #601). Step 4 depends on the
  persistence ADR and the plugin question (#563, RFC #605). Both depend on the
  v0.2 identity model for who may save a design.
- **The delete leg depends on the actuator.** Permanent delete wakes AWX and
  launches a job; the rest of steps 1 to 4 doesn't.

## 8. Not in this plan

- The canvas editor UI. Build the schema first.
- The placement compiler (§3.3's deferred half).
- The generic declarative launcher. ADR-0047 gates vendor deployment on it and
  its ingestion policy; it, not the UI, blocks vendor adoption.
- A GitOps reconciler in the deployment path, CRDs, or a console-owned
  database (v0.1 commitments, ADR-0037, §2).
- Migrating `topology_params` v1 (§3.2).
- A vendor extension SDK, vendor-rendered UI tiers, or a marketplace portal.
- Facility inventory expansion. First settle which facility is meant: the
  cloud environment or the broadcast facility (#558).
