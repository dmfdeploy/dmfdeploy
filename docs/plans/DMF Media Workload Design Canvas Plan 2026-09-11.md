---
status: draft
date: 2026-09-11
---
# DMF Media Workload Design & Plan Canvas — Parked Design Record (2026-09-11)

> **STATUS: DRAFT — PARKED. NOTHING HERE IS AUTHORISED TO START.**
> This record is written and held on a branch deliberately. It is **not filed
> as an issue, not scheduled, and not merged**. Freeze 2 (no new ADRs, no
> reopened non-goals, no consolidation rounds) lifts on **Gate B** — episode
> 001 published *with its evidence bundle* **and** the presenter runbook
> (#379) landed. #379 closed 2026-09-02; **episode 001 has not published**, so
> Gate B is not met.
>
> **On unfreeze:**
> 1. **Settle §10 step 0 first — the container scope posture (§9.1), coupled
>    with the producer question (§9.2). It is an operator decision, not a
>    build, and every other step depends on it.** Record the outcome in this
>    doc before filing anything.
> 2. Then file **one** tracking issue for §10 step 1 — the indivisible
>    visibility + create + delete boundary (`component:dmf-cms`,
>    `workstream:entrance`; milestone per WORKING-MODEL §2). Do not file the
>    later steps yet.
> 3. Add its URL to this file's `tracking_issue` frontmatter.
> 4. Flip `status: draft` → `active`.
> 5. Open the PR.
>
> No `tracking_issue` key is present yet **by design** — `bin/check-docs.sh`
> treats a missing one as a warning, not a failure, which is the correct signal
> for a parked spec.
>
> **Re-verify before building.** Every source claim in this document is pinned
> in §11 to a commit and a line. Those decay silently. Re-check §11's anchors
> before treating any of §4 as current.

## 0. Why this exists now, and what it is not

The design work is cheap and perishable; the build is neither. During
2026-09-07→11 a persistence investigation, an adversarial cross-check, and two
externally-authored concept reviews converged on one arc. Several of their
premises were **wrong against source**, and finding that out cost real reading.
Capturing the corrected version while it is verified costs nothing and saves
rediscovery later.

**Writing this down is not a decision to build it.**

This is **not** an ADR and must not become one under the freeze. It records
design state only. Where it contradicts an accepted ADR it says so explicitly
and defers — it never amends by implication.

## 1. The settled model

Operator decision, 2026-09-07, recorded on #490 and #562:

| Stage | Owns | Commits resources? |
|---|---|---|
| **Create** | A name. Nothing else. | No |
| **Design** | *What* — which media functions, and how they relate | No |
| **Plan** | *Where and with what* — binding to facility resources | Yes |
| **Provision** | Deploy | — |

This is EBU's own Design/Plan boundary, not ours. Create makes a blank
container and lands the operator on its home; template selection happens on
Design, facility selection on Plan, on the regular rail like any other
decision.

Consequences that fall out rather than needing separate decisions: the "draft"
concept disappears (the workload exists from create); #490 and #557 stop
overlapping; per-stage progress counts are honest from the first moment
(`0 elements designed` is true, not a placeholder).

**Deferred by explicit decision, not oversight:**

- **Linking functions / topology authoring.** Design is *selection-only* for
  now. Authoring a topology is a new surface; today `topology_ref` comes from
  the git catalog.
- **Capacity calculation at Plan.** Capacity runs today at provision preflight.
  A plan-time figure is a *projection* that can go stale before Provision runs,
  so if it ever ships it must not read as settled. Undecided.

## 2. Where design intent persists

**The gap.** Today a workload *is whatever is currently running*. Design and
Plan are read-only renderings derived from member services. There is no durable
record of a selection, no per-container facility assignment, and no write seam
for either. Selection lives in browser state and is lost on refresh.

**The answer: design intent persists as declarative artifacts in in-cluster
Forgejo. Save is a commit.**

Load-bearing properties:

- **Not a fourth store.** Both consumers already read Forgejo — AWX SCM-syncs
  projects from it (ADR-0014), and NetBox syncs from it through its own native
  git Data Source, live today.
- **Concurrency is optimistic on the SHA.** Read at a SHA, save with
  expected-SHA. A concurrent save produces a genuine conflict with a real diff,
  never a lock and never a silent overwrite.
- **The commit message carries the C5 quartet** (actor, role, request-id,
  reason). Design history becomes auditable in the platform's existing idiom,
  and `git log` / `git blame` work on a workload design.
- **Incompleteness is a validation verdict derived on read, never a stored
  state.** A half-finished design saves happily; what it cannot do is Plan or
  Provision, and the surface says exactly why. This reuses the mechanism #557
  lands (structural preconditions gate *actions*, not *navigation*) rather than
  inventing one.
- **Local designs never leave the cluster.** Private by construction,
  air-gap-safe. Designs a facility chooses to publish mirror outward. This
  refines ADR-0014's mirror model (inbound for upstream sources, **origin** for
  local designs, outbound for published ones) rather than contradicting it.
- **Layout is stored apart from semantics**, so moving a box on a canvas does
  not dirty the design and does not need a commit per drag.

**The honest limitation.** A git Data Source syncs *files*, not queryable
objects. "Which workloads use function X" is not answered by the sync. An index
is legitimate but must be **strictly derived** — regenerable from the
artifacts, never edited, never a second source of truth. At facility scale
(tens to low hundreds of designs) an index is a performance optimisation, not a
correctness requirement, and can be added later.

**The standing constraint this rests on:**

> **dmf-cms may cache, never own.**

The moment the console stores something authoritative that is not in Forgejo or
NetBox, it becomes a third source of truth. Every "just one small table" is
that moment.

**If unsaved-work loss becomes a real complaint**, escalate to autosave onto a
draft branch, promoted by Save. Still git, still no new store. The availability
of that next step without breaking the cache-never-own rule is the point.

## 3. The graph

Model a workload as a first-class **directed property graph**; the graph is the
canonical design intent and any visual editor is one interface onto it.

- **Strongly typed ports.** Ports advertise machine-readable compatibility
  (essence, formats, resolutions, frame rates, PTP requirement, 2022-7). This
  is what lets the surface reject impossible connections, offer compatible
  targets, and compute requirements before deployment. A graph without typed
  ports is a drawing.
- **Control-plane relationships are first-class** alongside media-plane ones
  (NMOS, Ember+, MXL, REST, GPIO).
- **Constraints are declarative intent** — colocation, anti-affinity, timing
  domain, latency budget, network requirements — never a pre-resolved node
  name.
- **The compiler framing.** The graph expresses intent; the platform resolves
  it into placement and configuration. Design stays logical, Plan resolves,
  Provision creates.

**Build the schema, not the editor.** Functions, typed ports, connections,
constraints, plus the compatibility validation that makes typed ports worth
having, and a handful of reference functions to prove it. Representation before
authoring. **The canvas UI is explicitly not on the critical path.**

## 4. What the source actually says — five reconciliations

Discussion #564 §"Things any answer must reconcile" lists five constraints.
Each is reconciled below: **4.1 is a genuine correction**, **4.5 corrects an
error this document itself made in its first draft**, and **4.2, 4.3 and 4.4
are narrowings** — #564 was directionally right and the detail matters.

*An earlier draft of this section claimed "two of the five are factually wrong",
naming 4.3 as one of them. That overstated the case: #564 item 3 already says
placement is a chart value and that the launcher passes no selector. See 4.3.*

### 4.1 There is no competing edge store — but git holds intent, not live truth

**#564 claims** the launcher persists instance-to-instance edges in NetBox as
`topology-parent:`/`topology-source:` tags, so a new relationship model would be
a second store and we must say which wins.

**Source says** the launcher stamps `topology-parent:<catalog entry key>` and
`topology-source:<declared sources[].id>` — a **catalog entry** and a
**declared element**, neither of which is an instance. The viewer release gets
**neither tag**, deliberately.

So **NetBox records no edge at all.**

**But git does not hold "the edge" either — it holds the *initial declared*
one.** A connection has three distinct representations, and conflating them is
the trap this correction must not create:

| Plane | Where it lives | Example |
|---|---|---|
| **Design intent** — what was declared | git catalog (`viewer.source_selection`) | source-a feeds the viewer |
| **Actuation state** — what was last commanded | the coordinator ConfigMap key the switch playbook writes | active-source is now source-b |
| **Observed** — what is actually happening | read from the running instance | the viewer is receiving source-b's flow |

A switch rewrites actuation state without touching git, so after one switch the
catalog's declared selection is **stale as live truth**. The console already
knows this and says so at the call site: previous-source *"must reflect what was
ACTUALLY running, never the catalog's own (possibly stale)
`viewer.source_selection`"*, with the catalog value kept only as a fallback for
a caller with no observed truth.

**What follows.** Git owns declared design intent; NetBox holds a generic
back-pointer *into* git; neither is a live-state store. That is ADR-0037's split
working as written, and the design-store shape is **already in production on the
one workload we run**. The recommendation inverts: do not invent a relationship
model — *widen the two tags that exist* into a design-ref/design-element pair
over a larger domain. Same semantics, no migration, and #564's "which wins"
question dissolves.

**Hazard.** A design canvas renders *declared intent*. If it renders declared
intent while presenting it as the live signal path, it violates UX Constitution
gate 1 (requested ≠ observed) on its first screen. The three planes above must
stay separable in whatever the canvas reads.

### 4.2 The one-hop star: freeze it, do not grow it

The v1 topology contract does not merely lack chaining — it **asserts
homogeneity**: the viewer object "is not a list", and `source_profile` and
`source_noun` are each "N copies, not N distinct". The binding constraints are
not the YAML but a hard `schema_version == 1` reject in **two** validators
(console and runbooks), a flat release-naming contract, and a chart that knows
only `role=source` and `role=view` — a mixer is neither.

**Decision: `topology_params` v1 is a launch parameter set for one chart, not a
design representation, and it must never become one.** The graph is a new
artifact at a different layer; `topology_params` becomes something the
**compiler emits** for charts that happen to take that shape.

This is what lets the whole arc proceed **without touching the deployed demo
path**.

### 4.3 Chart-level selector inputs exist; the launcher never threads them

**This is a narrowing of #564, not a refutation of it.** #564 item 3 already
says placement *is* a chart value and that the launcher passes no selector — it
is describing the missing end-to-end connection, and that description is
correct. What follows only sharpens which half is missing.

**Source says** the chart accepts `placement.nodeSelector` and
`placement.tolerations` and consumes both in its templates, and a search for
`nodeSelector|affinity|tolerations` across all of dmf-runbooks returns **zero
hits** — the launcher passes only `placementMode`, which selects a
networking/pinning *mode*, not a node.

**So the correction is narrow and must stay narrow:** *chart-level
selector/toleration inputs exist and are unthreaded.* That is **not** a general
placement solution. There is no demonstrated channel or representation for site,
colocation, anti-affinity, timing domain or latency budget — the constraints
§3 wants Plan to own. Do not read "the channel exists" as "the compiler has
somewhere to send its output".

**Hazard.** In split-node mode the templates inject *additional per-role node
selectors* of their own. Any resolved selector mapping has to coexist with those
role pins rather than replace them, and a mapping that silently overwrites them
will schedule correctly in single-node mode and wrongly in split-node.

**Deferred, separately from this correction:** the compiler itself, which subset
of constraints is actually supported, and how a placement decision agrees with
provision-time preflight.

**Decision on #564's question 6 (persist a Plan decision with nothing to
actuate?): persist the constraint, do not emit a resolution.** Plan's output is
a constraint (site, colocation, anti-affinity, timing domain) that the compiler
later resolves into a nodeSelector. Persisting intent is safe and is what Plan
owns. Persisting a *resolved node name* is the mistake — and is currently
unverifiable anyway, since NetBox records neither facility nor node for an
instance (#558).

### 4.4 Typed ports: the stub exists and nothing reads it

`mxl_flows: { produces, consumes }` is declared on the one live catalog entry,
and **no code consumes it** — the console's catalog loader parses the entry and
*drops* the field rather than reading it, and dmf-runbooks never references it.

*(Correction, codex round 1: an earlier draft claimed the field appears only in
that entry and one 2026-05-17 plan. It is also specified in ADR-0017 and
referenced in ADR-0046 — see §11. The no-consumer conclusion is unaffected, but
the field has more decision history behind it than the draft implied, and
ADR-0017 is where its contract was actually written.)*

Its shape was already argued: that plan's §D4 chose **option A** (bare flow
IDs) over **option B** (per-flow `{id, media_type, grain_rate,
max_grain_bytes}`) for one stated reason — *"schema gets ahead of usage."*

**That reason has expired.** Compatibility validation at Design is the usage.
Typed ports are D4 option B arriving on schedule, and the field to grow is
`mxl_flows`, generalised — not a new parallel declaration.

**Hazard — vocabulary collision.** ADR-0047 already says "declared
ports/services match the catalog entry", meaning **IPAM service ports**. Two
different things sharing the word "port" will be conflated in every review
round from here on. Name the new concept distinctly (`interfaces` /
`media_ports`) at the first commit, deliberately.

**Note.** 4.1 and 4.4 are the same mechanism seen from two sides: the viewer's
`mxl_flows.consumes` matches a source's `sources[].flow_id` — an implicit,
UUID-equality edge that nothing validates today. Typed ports are what make it
explicit and checkable.

### 4.5 One catalog entry produces several services

The one live catalog entry declares **three** `netbox_service` records — the
viewer plus two sources. So a designed function maps to **{0, 1, N} service
records**, and there is no 1:1 mapping to recover.

**Correction, 2026-09-11 (codex round 1).** An earlier draft of this section
claimed the source records exist only while a topology launch is live and are
removed by teardown/rollback. **That is false against executable source.**
Normal teardown runs the finalise stage per source, which **PATCHes the
lifecycle tag back to `bootstrapped` and clears monitoring stamps — it does not
DELETE the record.** Rollback is the only path that removes anything, and it
deliberately distinguishes records that pre-existed the run (restore) from those
the run created (attempt deletion). The claim came from a comment in the catalog
entry, which is **misleading against the code it describes** — a reminder that a
declarative file's prose is not a source of truth about runtime behaviour.

**The identity argument, re-derived without the false premise.** Two properties
survive and both still point the same way:

1. **Record presence does not track design-element existence.** A record
   persists across teardown with its lifecycle tag flipped. So "is this designed
   function deployed?" is answered by the **lifecycle tag** (requested state,
   ADR-0013/0037), never by whether a record exists.
2. **One entry yields N records**, so no designed element can be keyed to "its"
   service record.

**What follows** is unchanged: the design store must key nothing on service
records. A design element's identity is the declared-element slug; its binding
to a running service is exactly the two provenance tags from §4.1 — an
independent second argument for widening those tags rather than replacing them.

## 5. The neutral canvas

**Principle** (adopted verbatim from the vendor-UI concept review, §10):

> **The platform owns the graph; vendors own the nodes.**

**The line:** dmf-cms knows the **grammar**, never the **vocabulary**. It knows
that a function declares capabilities and ports; it must not contain the list of
what those are. It knows how to render a capability badge; it must not know what
`ptp.hardware` means.

### 5.1 Who owns what

| Content | Owner | Rule |
|---|---|---|
| Identity — names, nouns, icons, descriptions | Media function package / catalog entry | Read, never hardcoded |
| Requirements — capabilities, typed ports, resource profile, PTP/RDMA/ST 2110 | Media function schema | Declared, platform-bound |
| Instances & placement — what is deployed, which facility, which node | NetBox | ADR-0037 |
| Live state — PTP lock, flow health, throughput | Prometheus / NMOS / MXL runtime | **Never NetBox** |

That last row carries an ADR constraint most likely to be violated while
building this: ADR-0037 holds that **NetBox stores instances only — never
flows, never live state**. Declared intent → NetBox. Observed truth →
telemetry. A PTP *requirement* is schema; a PTP *lock status* is telemetry;
neither is ever a NetBox field.

### 5.2 What legitimately stays in the console

Rendering primitives; the lifecycle rail; the alarm taxonomy; the audit idiom;
the honesty rules (empty vs unreadable vs unknown, null-on-miss, never guessed
from a name); the canvas interaction model; and **the schema contract itself** —
the console must parse and validate a declaration, so it knows the *shape* of a
capability while knowing no capability.

### 5.3 The binding rule

> **The vendor declares; the platform binds.** A package may declare anything.
> Every declaration with a consequence outside the function's own pod is bound
> by the platform at install/admission time. The console never dereferences a
> package-supplied value — it dereferences a platform-bound record.

This is not an exception to neutrality; it is how neutrality is safely
achieved. It is already the platform's posture (ADR-0047 binds publisher
identity in a project-controlled index rather than accepting self-assertion)
and already its mechanism (the ADR-0038 cluster-coordinate custom fields are
stamped by the launcher, not handed over by the package).

**Hazard.** The console currently decides whether an instance has a live view
by testing membership of a hardcoded namespace/port set, and that literal is
simultaneously presentation *and* an SSRF gate — its own docstring says the
gate "is the whole point". It is a hand-rolled binder. Replacing it with a real
one is a strict improvement, but **the allowlist must never become
vendor-declared**. Not-hardcoded ≠ vendor-declared.

### 5.4 Where the console is not neutral today

Five sites, all verified (§11): a hardcoded map of five function keys to display
names — **already stale**, since two of those functions no longer have catalog
entries or are pending retirement; an MXL sidebar icon key; an `/mxl-flows`
route; an MXL-shaped response type family and endpoint; and the sidecar
allowlist above.

**The pattern to follow already exists in-tree, chosen twice.** #401 added a
catalog-declared display noun *specifically* so the console reads the name
instead of hardcoding it, and its own comment refuses to fall back through the
hardcoded map — "a separate, hardcoded, already-stale concern this fix must not
widen" — falling back to the raw key instead, "true, not invented". #452
resolves a source's test pattern server-side from the catalog, null on every
miss, "never derived from the instance's own name". The direction is proven and
the debt is bounded.

**PTP is a clean slate.** There is no PTP, ST 2110, AES67 or 2022-7 anywhere in
console source. It is therefore the ideal first proof of the principle: if PTP
enters only as a declared capability plus a telemetry-sourced lock status, it
arrives correct and sets the pattern for everything after it.

## 6. Vendor adoption — the real blocker is not UI

`dmf-runbooks/playbooks/` contains **nine playbooks, all bespoke**. There is no
generic launcher, and `generic-chart-policy/v1` has **zero lines of
implementation** anywhere — it exists as a normative appendix in ADR-0047, in
the 2026-07-17 roadmap, and in the 2026-07-18 make-vs-adopt OSS evaluation. The
one live catalog entry binds to a playbook by name.

**Worth knowing before anyone starts it:** that OSS evaluation already carries a
recommendation for *how* to build it — author Appendix A as Kyverno policies
evaluated offline by `kyverno apply` against rendered manifests, rather than as a
bespoke validator plus fixture harness. Whoever picks this up should start
there, not from scratch.

**Also narrower than an earlier draft claimed:** ADR-0047 gates vendor
deployment on **both** the generic launcher *and* its ingestion policy, not the
launcher alone.

ADR-0047 makes bespoke launchers **`project`-source-only**. So importing a
generic Docker/Helm media application today means writing an Ansible playbook in
dmf-runbooks — which is, by our own decision, **not a vendor path at all**.

ADR-0047's index entry already names this as the gate:

> Vendor deployability gated on the generic launcher actually existing.

**Recorded so it is not rediscovered:** the highest-leverage vendor-adoption
work is the **generic declarative launcher** (chart + values + netbox_service +
probes), not UI integration tiers. Its contract is backend-agnostic even though
today's implementation would be an AWX playbook.

**Do not start an extension SDK for a platform that cannot yet deploy a vendor
chart.**

## 7. What this deliberately does NOT do

Stated as loudly as the rest, because a reader six weeks from now will quote a
diagram rather than read a caveat.

- **No Argo CD, and no GitOps reconciler in the deployment path.** The
  Argo+AWX hybrid actuator is a named v0.1 non-goal
  (`architectural-commitments-v1.md`: *"Do not build a hybrid framework to
  avoid choosing. AWX is the v0.1 actuator. Argo is a future spike, not a
  dependency."*) — and the last pre-freeze umbrella commit was exactly this
  drift, caught by name. Both external concept reviews route deployment
  through Argo. Their sequences must be re-derived against AWX, not reworded:
  a pull reconciler and a job launcher give different answers about where a
  placement decision is emitted and when a reservation is released.
- **No CRDs** for DeploymentRequest / Reservation / PlacementDecision. ADR-0037
  supersedes ADR-0027 precisely on this and records "no new platform component
  (no CRD, no custom operator)" as the positive consequence. It leaves the door
  open only under a *named* condition, which neither review argues.
- **No console-owned database**, transactional or otherwise (§2's standing
  rule).
- **No migration of `topology_params` v1** (§4.2). It stays a compiler output
  target.
- **No new ADR, no new discussion, and neither external concept document is
  committed to any repo.** Their surviving ideas appear here in our own prose.
- **No vendor extension SDK, no managed vendor workspace, no app-store
  portal.** ADR-0047 already considered and parked external marketplace
  portals. A bespoke `dmf init/validate/test/package/publish` CLI also collides
  with the standing preference for GitHub-native tooling over bespoke scripts
  and with ADR-0041's contribution path.
- **No facility/VPC inventory expansion.** Context only, §9.4.
- **No live-env deployment.** This arc is designed to change no deployed
  surface until it is deliberately released.

### 7.1 Why vendor UI tiers are out, specifically

The vendor-UI review proposes three integration levels. **Level 1 (declarative
native controls) is the architecture. Levels 2 and 3 are commercial
concessions** and should be labelled as such — the review's own strongest
sections argue against them (an embedded app "tells the platform almost nothing
about what the Media Function actually does"; platform truth must survive
vendor-UI failure; a function is a semantic capability, not a container with a
web UI).

**Correction, 2026-09-11 (codex round 1).** An earlier draft claimed a
vendor-rendered surface violates three day-one hard gates **by construction**.
That is an overclaim, and the citations do not support it. The UX Constitution's
gates specify provenance/freshness, action completion, the C5 quartet with
graduated friction, and operator-facing errors — they do **not** require that
rendering code be platform-authored. A vendor renderer that consumes platform
APIs, surfaces their provenance and errors, and routes actions through audited
endpoints could satisfy all four without being a Level-1 declarative renderer.
Art. 15 likewise forbids external *runtime dependencies*, not vendor
*authorship*: bundled in-cluster assets satisfy it.

**The honest form of the exclusion.** Levels 2 and 3 are ruled out here as a
deliberate **product and security scope decision**, not as a constitutional
impossibility. The cost being declined is a real one: an integration contract
that would have to *prove* gate compliance for code we did not write — provenance
attestation, per-action request-id propagation, error-surface shaping, isolation
and CSP, version compatibility — none of which exists, and all of which would be
built for **zero current vendors**. The gates are what make that contract
expensive; they are not what make it impossible.

**Shape for future expansion, so this is not a corner:** declare the extension
points in the schema and implement none of them. A package may carry a
UI-surface declaration; the console records it and states honestly that the
surface is not supported here. One key now prevents a breaking change later,
while the SDK, CSP work and token exchange wait for a **named** vendor. Because
the platform binds declarations at install time (§5.3), adding richer tiers
later changes what the *binder* produces, not how the console reads.

## 8. Acceptance properties

Properties, not procedures. Each is one executable assertion covering several
failure modes.

1. **Existence is read, not inferred.** On a **complete** enumeration, the
   *multiset* of workloads rendered equals the containers NetBox holds within
   the viewer's current authorization — same membership **and** no duplicates —
   with the expected inventory **seeded independently of the code under test**,
   and the flat and grouped reads agreeing. Set equality alone is not enough: it
   admits duplicate tiles, and it must not be asserted at all when the
   enumeration was incomplete (see property 2, which is what an incomplete read
   must produce instead).
2. **Three states are independently representable.** A container with zero
   members reads as healthy-and-empty; one whose member read failed reads as a
   fault; and the two never render identically. The response contract carries
   three independent facts: enumeration was complete enough to claim
   exhaustiveness; this authorized container's member read succeeded and
   returned zero; member data was unavailable or incomplete.
3. **Emptiness never removes a tile.** Having zero members is never a reason a
   container stops rendering. Stated as an absolute this would forbid a tile
   disappearing when the viewer's authorization is revoked — which property 4
   requires — so it is scoped deliberately: within a fixed authorization, a
   container leaves the page only by explicit permanent delete.
4. **Scope widens what exists, never who can see it.** An unscoped enumeration
   must not disclose another tenant's blank workload name. *(See §9.1 — this is
   currently unsatisfiable as stated and is a decision, not an implementation
   detail.)*
5. **Create is attributable and idempotent.** A created container carries an
   audit record with the C5 quartet; a duplicate-slug create has defined
   semantics; a partial success leaves no half-created container.
6. **A design round-trips.** A design saved at SHA *n* and re-read returns the
   same graph; a save against a stale SHA is refused with a diff, never merged
   silently and never overwritten.
7. **Incompleteness gates actions, not navigation.** An incomplete design
   saves, is reachable, states plainly what is missing, and refuses Plan and
   Provision naming the same reason.
8. **A count is never manufactured.** A progress count renders only when the
   authoritative read succeeded; a failed read never becomes zero; no
   `0 of 0` claim appears for a blank container.
9. **Compatibility validation discriminates *in both directions*.** A connection
   between incompatible typed ports is refused and the refusal names the
   incompatible property; **and** a connection between compatible ports is
   accepted. Both halves are required — a validator that rejects *every*
   connection satisfies the negative case and fails the mutation check exactly
   as asked, while leaving every real graph unbuildable. Prove the negative half
   by mutation (a suite that still passes with the validator disabled is not
   testing it) and the positive half against compatible reference functions.
10. **The console names no media function.** No media-domain proper noun
    appears in console source outside a narrow, justified, platform-owned
    binding configuration — a grep-able gate that fails today on five known
    sites (§5.4).

## 9. Hazards

Traps found the expensive way. These are hazards, not prescriptions — framed as
*this will fail an acceptance criterion*, never as a mandated implementation.

### 9.1 Container scope — DECISION GATE, blocks everything in §10

> **⛔ OPERATOR DECISION REQUIRED. Nothing in §10 can start until this is
> settled, including step 1.** This is not a hazard to keep in mind while
> building; it is the first unit of work, and it is a decision, not an
> implementation.

The workload container tag **carries no tenant field at all**, while ADR-0046
requires workload identity to be `(tenant/site scope, slug)` — satisfied today
only *via members*. So "every container is shown, subject to scope" and "scope
may be undefined for a container" are **mutually unsatisfiable**, and an
unscoped enumeration is a tenant-disclosure risk.

**Why this cannot be delegated to an implementer (codex round 1, accepted).**
Property 4 has no operational meaning until "resolves into the viewer's scope"
is defined for a **memberless** container. Source cannot supply it: the console
deliberately *rejects* inferring an owner for a container with no visible
members, and the existing group-to-tenant mapping assigns no tenant or site to a
bare tag. Whoever writes the fixture would therefore invent the mapping — and
invent the implementation's — so the test would establish neither no-leak nor
completeness. **When the mechanism defines the property's terms, the mechanism
belongs in the plan.** This instance is squarely on that side of the line.

**Correction, 2026-09-11 (codex round 1).** An earlier draft argued the tenancy
premise "may be hollow" because ADR-0039 gives every env one shared tenant while
ADR-0020 puts tenancy on a cluster-per-tenant axis. **That misreads ADR-0039**,
which says the opposite in its own consequences: *"the shared `DMF` tenant is
unchanged; ADR-0020 cluster-per-tenant is a different (**media-tenant**) axis and
is not affected."* The two axes are deliberately distinct, so the shared
infrastructure tenant does **not** dissolve the media-tenant question. Do not
reuse the hollow-premise argument.

**What the decision must name:** the authoritative persisted container scope
(tenant *and* site semantics); where it lives, given that the tag itself cannot
hold it (§9.2 — the writer identity holds no `change` on tags); its read and
write authority; behaviour on missing or malformed scope; and an explicit
no-disclosure rule. **Derive from source with file:line evidence; do not design
it in prose.** "Not determinable from source" is a finding to bring back, not a
gap to paper over — a confidently asserted wrong binding encoded into a security
boundary is worse than an admitted one.

### 9.2 Create's producer — leading direction, not a settled decision

The console creates no container tags today; identity is stamped by the deploy
launcher, and the console's NetBox layer states it never creates or deletes tag
objects. The only existing direct write is a narrowly scoped lifecycle PATCH.

**Correction, 2026-09-11 (codex round 1).** An earlier draft recorded this as
**decided** — "the producer is the scoped NetBox writer, not an AWX/launcher
transaction" — on the backend-flip argument. That **overstated what is
settled**, on two counts:

1. **Principal and execution location are different decisions.** An
   AWX/launcher transaction *already uses that same scoped writer identity*, so
   "use the scoped writer" does not by itself choose direct HTTP writes over a
   launcher transaction.
2. **The backend-flip argument does not discriminate here.** The repo already
   demonstrates an actuator-independent domain contract implemented over AWX
   (the switch actuator's `Protocol` seam), so a Temporal move does not by
   itself require design-time writes to bypass the actuator.

**What is confirmed, and it constrains the answer hard.** The catalog writer
identity holds `view, add` on tags — **no `change`, no `delete`**. Deletion
lives with a *separate* identity whose delete is constrained to the
`workload:`-prefixed namespace, and the two identities' non-overlapping powers
are a deliberate, ADR-recorded invariant (the writer never holds delete; the
purge identity never holds add or change).

The consequence is sharp: **a create transaction cannot be "add a tag and record
its scope on that tag"** — the tag carries no scope field (§9.1) *and* the
writer cannot modify a tag once created. So the scope decision in §9.1 and the
producer decision here are **one coupled problem**, not two.

**Leading direction** (not settled): console-side create via the scoped writer,
because it keeps a design-time write off the actuator. **Before it can be
treated as decided, name separately:** the API producer, the principal it acts
as, transaction atomicity across tag-plus-scope, duplicate-slug semantics, retry
and partial-success recovery, and what happens when the audit write fails but
the container create succeeded.

**Confirmed prerequisite regardless of which producer wins.** The console's
NetBox writer credential is required by the console and is set by **no chart and
no role** — the existing writer-dependent endpoint is 503 on every deployed env
(#487).

### 9.3 The delete path breaks the moment blank containers become visible

A scoped caller with zero visible members is **deliberately** told
`workload-not-found` even when the tag exists, specifically to avoid tenant
leakage. Once a blank owned container becomes visible, the current purge path
will refuse to remove it. "Delete permanently is the sole removal transition"
therefore needs a replacement **fail-closed proof**, not a check that the old
path still works.

### 9.4 Facility modelling is thinner than it looks — context, not scope

Born-inventory writes one site, one tenant, one k3s cluster, control-plane and
worker devices, **one** load-balancer device with a single interface, plus
interfaces, IP addresses and about ten platform services. It writes **no**
prefixes, VLANs, VRFs, aggregates, regions, site-groups, locations, racks,
cables or circuits. There is no VPC, no routing domain, no region or AZ, no
rack or room, no provider or uplink, and the load balancer is a name rather
than its targets, listeners or health checks.

Operator position (2026-09-11): wherever the sandbox is deployed it should
eventually take a **real inventory** beyond born-inventory. **Parked as
context, not scope**, for this arc.

One distinction to settle before anyone models anything: *which* facility —
the cloud environment we happen to run on (VPC, region, AZ, router, LB targets:
demo legibility, v0.1-polish-shaped, independent of this arc) or the broadcast
facility the platform exists for (media nodes, NIC/RDMA/PTP capability, NUMA,
SDI ports, fabric bandwidth: the supply side of a capability contract). They are
different objects and should not merge into one "model everything" push. Related
open issues: #558, #469, #302.

### 9.5 Stage gating is largely already done

Navigation is already selectable: a hash target is honoured regardless of state,
step selection refuses only while a job is in flight, and the rail component
already documents "no padlock, locked keys reachable". The classifier still
emits a locked state, but as a **presentation state, not a navigation gate**.
Do not instruct anyone to remove a gate that is absent — state the remaining
property and decide whether the locked state is renamed, removed, or merely
stripped of a stale user-facing reason. Those produce very different diffs.

### 9.6 Method notes

- **A plan doc's job is decisions that are expensive to get wrong and invisible
  in code** — not to pre-derive the implementation. Query shape, ordering, parse
  strategy and control flow belong to the implementer, whose verification (a
  failing test) is far stronger than a reviewer reading prose. **The exception**:
  when the mechanism defines the property's terms — §9.1's authorization
  mapping is the case — withholding it leaves the criterion meaningless.
- **A reported defect is a sample.** Sweep the shared property, not the
  reported sites.
- **Every finding being real is not evidence to keep going.** If findings
  cluster in *how* rather than *what*, and fixes start generating the next
  round's findings, the artifact is the wrong shape — cut, don't patch.

## 10. Sequencing on unfreeze

Strictly ordered; each step is a prerequisite for the next, and **only the
first should be filed as an issue when the gate lifts**.

**0. Settle the container scope posture (§9.1) — a decision, not a build.**
Nothing below may start first, **including enumeration**. An earlier draft put
enumeration first and scope resolution at create; that was wrong, because the
first rendered blank container is already an authorization claim, and the
acceptance property governing it has no meaning until the mapping exists.
Outcome is a written posture covering tenant/site semantics, where scope is
persisted given a tag cannot hold it, missing/malformed-scope behaviour, and the
no-disclosure rule. **Coupled with §9.2's producer question — settle them
together.**

**1. Blank containers become real — one indivisible delivery boundary.**
Visibility, create and delete ship together or not at all:

- **Enumeration** (#562) — existence read from NetBox; the three states of §8.2
  independently representable. Read path only.
- **The writer seam** (#487) — provision the console's NetBox writer credential
  in a chart or role. Prerequisite for anything that creates.
- **Name-only create** (#490) — per the posture settled in step 0.
- **Blank-container delete** — a *scoped* permanent delete that works on a
  container with zero members, with a **fail-closed proof** that it neither
  discloses nor deletes across scope.

The delete is inside this boundary deliberately (codex round 1, accepted). The
current purge path answers `workload-not-found` for a scoped caller with zero
visible members (§9.3), so shipping visibility and create *without* it strands
containers that the promised "delete permanently" cannot remove — the platform
would create a thing it cannot destroy. Note the delete principal is the
separate purge identity, not the writer (§9.2).

**2. Stage behaviour** (#557) — narrowed per §9.5.

**3. The design schema** — functions, typed ports, connections, constraints,
compatibility validation (both directions, §8.9), reference functions. Schema
and validation only; no editor.

**4. Design persistence** — the Forgejo artifact contract of §2.

***Not scheduled:*** the canvas UI; the compiler and its placement emission
(§4.3's deferred half); the generic declarative launcher (§6); everything in §7.

**Backend-flip check.** Steps 1–6 all land left of the AWX/Temporal seam —
git artifacts, a NetBox read path, a NetBox write via a scoped writer, a schema
contract, and resolution logic. Only the eventual placement emission touches
the actuator. That is an independent argument that this is the right work.

## 11. Provenance — what was verified, against what, when

Everything in §4, §5.4, §6 and §9 was read from source on **2026-09-11** at
these anchors. **They decay silently. Re-verify before building.**

| Repo | Commit | Notes |
|---|---|---|
| dmfdeploy (umbrella) | `3193025` | `origin/main` at branch point |
| dmf-cms | `321dd63` | `VERSION` 0.39.0 |
| dmf-runbooks | `17f535a` | tag `v0.4.8` |
| dmf-media | `c0ea827` | tag `v0.1.0` |
| dmf-infra | `e496478` | — |

**Source anchors.** Paths are relative to the umbrella; `../` is a sibling
component repo.

| Claim | Anchors |
|---|---|
| §4.1 tags name a catalog entry + declared element; viewer gets neither | `../dmf-runbooks/roles/mxl/defaults/main.yml:85-110`; `../dmf-runbooks/playbooks/launch-mxl-fabrics-demo.yml:237-247` |
| §4.1 three planes (declared / actuated / observed) | `../dmf-media/catalog/topology-params.j1.yaml:95-100`; `../dmf-runbooks/playbooks/switch-mxl-fabrics-demo.yml:598-609`; `../dmf-cms/src/dmf_cms/switch_source.py:521-534,:777-789` |
| §4.2 `schema_version == 1` hard reject, two validators; flat naming | `../dmf-cms/src/dmf_cms/catalog.py:297`; `../dmf-runbooks/roles/l3_run_guard/filter_plugins/l3_topology.py:50,:114-160` |
| §4.3 chart accepts selector/tolerations; split-node injects per-role pins | `../dmf-media/charts/mxl-fabrics-demo/values.yaml:158-166`, `templates/target.yaml:28-45`, `templates/initiator.yaml:26-41` |
| §4.3 runbooks sets neither | search over `../dmf-runbooks` for `nodeSelector\|affinity\|tolerations` — no hits |
| §4.4 `mxl_flows` declared, parsed-and-dropped, never consumed | `../dmf-cms/src/dmf_cms/catalog.py:192-204`; contract in `docs/decisions/0017-mxl-intra-host-data-plane.md:136,226,247`; referenced `docs/decisions/0046-first-class-media-workload-entity.md:112` |
| §4.5 teardown PATCHes lifecycle, does not delete; rollback distinguishes | `../dmf-runbooks/playbooks/teardown-mxl-fabrics-demo.yml:200-212`; `../dmf-runbooks/roles/mxl/tasks/finalise.yml:46-58`; `../dmf-runbooks/roles/l3_run_guard/tasks/rollback_netbox_surface.yml:116-124`. **The misleading comment:** `../dmf-media/catalog/mxl-videotest-view.yaml:57-60` |
| §5.4 non-neutral sites | `../dmf-cms/frontend/src/lib/labels.ts:57-63` (and the refusal-to-widen note at `:76-79`); `frontend/src/components/Sidebar.tsx:88`; `frontend/src/App.tsx:118`; `../dmf-cms/src/dmf_cms/media_workloads.py:47-48` |
| §6 nine bespoke playbooks, no generic launcher | `../dmf-runbooks/playbooks/` (9 files); `docs/decisions/0047-…:91-103` (gates on launcher **and** ingestion policy); Kyverno recommendation `docs/reviews/DMF v0.2 Make-vs-Adopt OSS Evaluation 2026-07-18.md:88,107` |
| §7 exclusions | `docs/decisions/architectural-commitments-v1.md:70-71`; `docs/decisions/0037-…:111-114`; `docs/decisions/0047-…:169-173`; `docs/design/DMF Console UX Constitution 2026-05-25.md:149-153` (gates), `:138-141` (Art. 15) |
| §9.1 blank-container owner cannot be inferred; scoped identity required | `../dmf-cms/src/dmf_cms/media_workloads.py:981-1000`; `docs/decisions/0046-…:27-31`; `../dmf-cms/src/dmf_cms/settings.py:240-275`; media-tenant axis distinction `docs/decisions/0039-…:82-83` |
| §9.2 writer holds add-not-change on tags; delete is a separate identity | `../dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox-sot/defaults/main.yml:180-205`; `docs/decisions/0032-…:358-372`; actuator-independent contract precedent `../dmf-cms/src/dmf_cms/switch_source.py:14-25` |

**Search scope, stated because exhaustive claims are only as good as it was.**
Code-consumer claims (§4.4) were checked across all nine repos over `*.py`,
`*.ts`, `*.tsx`, `*.yml`, `*.yaml`, `*.md`, excluding `node_modules`. The first
draft's *document* counts were wrong as a result of narrower greps and have been
removed rather than restated — see the corrections in §4.4 and §6. Treat any
"only occurs in N places" phrasing anywhere in this doc as a claim about code
consumers, never about documents.

**Inputs.** Operator decisions recorded on #490 and #562 (2026-09-07); the
adversarial cross-check recorded on #562; discussion #564 (whose §"Things any
answer must reconcile" items 1 and 3 are corrected in §4.1 and §4.3); and two
externally-authored concept reviews (2026-09-11) held outside the repo by
operator decision — a standardised media-node/function schema review and a
vendor media-function UI integration concept. Their surviving contributions are
§3's graph model, §5's ownership principle, the capability trust-state
vocabulary (`discovered / operator-declared / validated / certified / degraded /
unavailable`), the resource-semantics taxonomy (scalar / discrete / topological
/ qualified-access / licensed / shared-bounded — which explains #302's
under-count as a modelling error rather than a calibration error), and the
relationship-versus-internal ownership default. Their rejected proposals are
enumerated in §7.

## 12. Review history

**Round 1 — codex adversarial cross-review, 2026-09-11, against umbrella
`e817a4a`. Verdict: GATE: FAIL (P0 0, P1 3, P2 6). All nine findings verified
against source and folded.**

The three that changed the substance rather than the wording:

| Finding | What the first draft got wrong |
|---|---|
| §4.5 | Claimed source service records are deleted by teardown. **False** — teardown PATCHes the lifecycle tag back to `bootstrapped`; only rollback deletes, and only records the run created. The claim came from a catalog-entry comment that contradicts its own executable source |
| §4.1 | Claimed "the actual edge lives only in git". **Overstated** — git holds the *initial declared* connection; a switch writes actuation state elsewhere and the console already treats the catalog value as possibly stale. Now three planes |
| §9.1 | Deferred the container scope mapping to an implementer. **Wrong side of the line** — the mapping defines the acceptance property's terms, so withholding it left the criterion meaningless. Now an explicit operator decision gate that blocks §10 entirely, including enumeration |

Also folded: the §9.1 claim that ADR-0039 makes the tenancy premise hollow was a
**misreading** — ADR-0039 explicitly keeps the media-tenant axis distinct;
§9.2's producer choice was **downgraded from "decided" to a leading direction**
once it emerged that the writer identity holds no `change` on tags and delete
belongs to a separate principal, coupling it to §9.1; §7.1's "violates the gates
by construction" was an **overclaim** and is now an explicit scope decision with
its cost named; §4.3 was **narrowed** from a refutation of #564 to an agreement
with it; three acceptance properties admitted broken implementations (duplicate
tiles, an authorization-revocation conflict, a reject-everything validator); and
§11's exhaustive document counts were false and are replaced with anchors plus a
stated search scope.

**Not folded, deliberately:** nothing. No finding was judged wrong.

**Open for the operator, carried out of this round:** §9.1's scope posture and
§9.2's coupled producer question. Both are decisions, and neither should be
resolved by whoever implements.
