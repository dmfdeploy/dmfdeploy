---
status: historical
date: 2026-05-29
---
# DMF Vendor Multi-Tenancy & Media-Tenant Separation — North Star Vision (2026-05-29)

**Date:** 2026-05-29
**Status:** Vision / North Star — *not a build target.* Captures design hooks
to protect now and open questions to resolve before any implementation.
**Authoring session:** Claude Opus 4.8, with operator, off a conceptual
discussion of a "vendor role" for the catalog.
**Strategic context:** experiment phase (ADR-0004). The single-tenant catalog
deploy loop (nmos-cpp via ADR-0016 Path A; MXL spike via ADR-0017) is **not yet
proven end-to-end** — there is still a deploy↔finalise race in flight. This
document is explicitly downstream of that: **do not build any of this until the
single-tenant catalog deploys a real media function cleanly.**

> **Why this doc exists.** Most of the vision below is a Phase-2/3 concern. But a
> handful of decisions are *cheap today and expensive later* — catalog data
> model, namespace/identity conventions, image-registry namespacing, node
> labelling. Recording the North Star now lets us get those hooks right so the
> full feature is an *extension* rather than a *rewrite*. The vision must not
> pull the experiment phase into premature hardening.

---

## 1. The vision

Evolve DMF from *"the operator deploys a curated set of apps"* into *"the
platform hosts vendor-published media ecosystems."* A **vendor role** (a
manufacturer / solution provider) can:

- Publish a complete ecosystem of apps they offer (a vendor catalog / app store).
- Request compute resources, and — in the extreme case — specific physical nodes
  for full control.
- Deploy into an isolated slice of the platform (a "virtual cluster").

This is the grown-up form of today's catalog page. It is a coherent broadcast
product: a facility app store / managed media cloud.

### Operator-stated nuances (2026-05-29)

- **Dedicated nodes are the *extreme* case, not the default.** In many cases
  vendors should be able to **share "media nodes"** — and sharing is *desirable*
  precisely because co-resident functions can exchange media via **MXL** at
  memory speed (ADR-0017), rather than burning a multicast group / PTP slave for
  a hop that could be a memcpy.
- A future **libfabric/RDMA fabric** would extend that media-sharing across
  nodes, widening the "shared media substrate" beyond a single host.
- **True customer/tenant media separation, plus authentication and access
  control on shared media hardware, is still a developing field.** This vision
  records what exists, what probably fits, and where the friction is — it does
  not claim the hard problem is solved.

---

## 2. Capability decomposition

The vision factors into three largely independent capabilities. Their maturity
differs sharply, which is the most important takeaway:

| Capability | What it means | Maturity for DMF |
|---|---|---|
| **A. Vendor as a tenant** | A third principal class beside operator and app-local-admin; scoped identity, secrets, RBAC | Net-new, but builds on existing identity stack (§4) |
| **B. Virtual clusters** | Each vendor gets an isolated control plane / namespace boundary | Solved off-the-shelf (§5) |
| **C. Resource / node requests** | Vendor asks for N nodes, specs, or specific physical nodes | Extends existing Terraform Layer-1 + deferred multi-provider goal (§5) |
| **D. Media-tenant separation** | Isolation/authz of the *media itself* on shared hardware | **The hard, developing-field part** (§6) |

The trap is treating all four as one feature. A, B, C are tractable. **D is the
research frontier** and must not gate A–C.

---

## 3. What's solved — the reassuring half

### Kubernetes multi-tenancy (capability B) is off-the-shelf

None of this is novel; the building blocks are mature:

- **Virtual clusters** — `vcluster` (each tenant gets a real API server + CRDs,
  scheduled onto shared nodes), **Kamaji** (hosted control planes), or
  **Capsule** (lighter, namespace-as-a-tenant).
- **Specific nodes / "full control"** — dedicated node pools per vendor via
  taints/affinity + labels. ADR-0017 *already* establishes "MXL processor" as a
  tainted/labelled **k3s node role** (`dmf.io/role=mxl-processor`,
  `dmf.io/mxl=true:NoSchedule`) — the same mechanism generalises to
  per-vendor node pools.
- **Resource requests** — `ResourceQuota` + `LimitRange` inside the tenant
  boundary; instance/provider selection at provisioning time. This dovetails
  with the already-deferred **multi-provider resource selection** goal
  (per-resource provider + instance + pricing from bootstrap and dmf-cms).

### Control-plane media authorization (part of D) — IS-10 is the match

**AMWA IS-10 (NMOS Authorization)** is OAuth 2.0 / JWT bearer-token
authorization for the NMOS **control plane**:

- An Authorization Server issues signed JWTs; NMOS API endpoints (IS-04
  Registration & Query, IS-05 Connection) act as resource servers that validate
  them. Pairs with **BCP-003-01** (TLS) and **BCP-003-02** (authz deployment RP).
- The token's private **`x-nmos` claim** scopes it to specific NMOS APIs
  (`registration`, `query`, `connection`, `node`, `channelmapping`, `events`),
  an access level (read/write), and optionally specific resource paths.

Why it fits DMF cleanly:

- **Authentik is already the platform OIDC provider** — it can serve as the
  IS-10 Authorization Server, minting `x-nmos`-claimed JWTs. This extends the
  [two-layer identity model](operator vs app-local-admin, ADR-0024/0028) to a
  third thing: a **media-control-plane principal**.
- **nmos-cpp** — the chosen Layer-5 implementation (ADR-0014/0016) — has
  upstream IS-10 authorization support. **The capability is already in the
  stack, just not wired.** The DMF nmos-cpp role configures NetBox-driven
  registration but never enables IS-10. Turning it on is config + an AS, not new
  code.

With IS-10, a vendor's functions get tokens scoped to register/query/connect
**only their own** senders, receivers, and flows — vendor A cannot make/break
vendor B's IS-05 connections, or even see B's resources in a query. This
converts the *control-plane* authz piece from "research problem" to
"adopt-and-configure a spec the stack already supports."

### MXL supports the shared-media-node case by design

The operator's instinct that vendors should *share* media nodes aligns with
MXL's design intent (`mxl/docs/Architecture.md`):

- Multiple MXL **domains co-exist on one host**; functions exchange grains at
  memory speed.
- **Container-safe by design**: "the memory mapping model does not require a
  shared IPC or process namespace, making it suitable for safe use in
  containerized environments." Functions in different pods can exchange flows
  without sharing IPC/PID namespaces.
- **Per-flow** *and* **per-domain** isolation primitive exists: UNIX file
  permissions "not only at the mxl domain level but also at the individual flow
  level." So "vendor A's functions (a uid/gid) may read flow X but not flow Y"
  is *expressible today*.
- Readers are read-only (`PROT_READ`, futex-synced) — a reader needs no write
  access to the flow.

---

## 4. Probable architectural matches

| Need | Probable match | Notes |
|---|---|---|
| Vendor control plane isolation | `vcluster` / Kamaji / Capsule | Pick density vs. isolation per threat model |
| Dedicated/shared media nodes | ADR-0017 node-role taints/labels, generalised per-vendor | Already the established pattern |
| Per-node provisioning + specs | Terraform Layer-1 (`dmf-env`) + multi-provider goal | "Request nodes" = the multi-provider feature wearing a vendor hat |
| Vendor identity / SSO | Authentik group/tenant; OIDC | Third principal class beside ADR-0024/0028 |
| Vendor secrets isolation | OpenBao per-vendor namespace/mount | Mirrors existing scoped-SA pattern (ADR-0032/0033) |
| **Media control-plane authz** | **IS-10 + Authentik-as-AS + nmos-cpp** | Already in the stack, unwired |
| Intra-node media exchange | MXL per-flow UNIX perms (ADR-0017) | Cooperative-tenant grade, not hostile-tenant |
| Cross-node media exchange | ST 2110 / NDI / SRT bridges today; MXL Fabric later | ADR-0017 constraint (3) |
| Vendor-published catalog/images | Per-vendor Zot namespaces + signing | Extends ADR-0033 scoped-write model |

---

## 5. Friction & the hard parts

### The media data plane does not virtualize cleanly

This is the DMF-specific friction that generic PaaS multi-tenancy doesn't face:

- A vendor function that *processes media* needs host-level network access —
  SR-IOV / macvlan / Multus secondary nets, hugepages, RT scheduling. That's
  privileged host access, which **breaks soft multi-tenancy.** vcluster isolates
  the *API*, not the *wire*.
- This pushes the design toward **dedicated media node pools per vendor** for
  the hostile-tenant case, rather than cheap dense soft-tenancy — which
  *validates* the operator's "specific nodes" extreme case, but changes the
  economics: no free density, you get per-vendor hardware on the media fabric.

### Shared physical dependencies leak across tenants

- **PTP** is a facility-wide clock domain — shared by definition.
- **Multicast / IGMP** group allocation on a shared media VLAN needs governance
  (per-vendor VLANs? group-range allocation?).
- The **NMOS IS-04 registry** is typically facility-wide — do vendors share one
  registry (IS-10-scoped views) or get their own? Both are answerable; it's a
  real control-plane design choice.

### IS-10 is control-plane only — it does NOT separate media bytes

The critical limit. IS-10 authorizes NMOS API *operations*, not media *bytes*.
It governs who may register/discover/connect a flow. It does **not**:

- Encrypt or gate the actual **ST 2110 RTP multicast** — anyone who knows the
  multicast group receives the media regardless of any token.
- Touch **MXL grains** in tmpfs — that remains the UNIX-permission story, which
  is *filesystem-grade* (no crypto, no authn of the reader, no audit beyond
  `lastReadTime`). A compromised co-resident uid sees the bytes. Fine for
  *cooperating* vendors who *want* to exchange via MXL; **not a hostile-tenant
  boundary.**

### The fabric future widens the trust surface

- MXL `Addressability.md` already defines the remote-flow URI
  (`mxl://<host>:<port>/<domain-path>?id=<flowId>`), so cross-host *addressing*
  is designed.
- But the **transport** (Fabric API over RDMA/EFA) is roadmap, not v1.0
  (`libfabric 2.2.0` staged, no cross-host code path exposed — ADR-0017).
- When Fabric ships, the trust surface jumps from "UNIX perms on one host's
  tmpfs" to "**the network**," and *none* of the current permission model covers
  that. This is the genuinely-developing-field part.

### Supply chain

Vendor-published Helm bundles + images need their own Zot namespaces, signing,
and a vetting story. Opening the registry to third parties is a different threat
model than the current first-party gitleaks/scrub/zot-mirror pipeline.

---

## 6. The data-plane separation gap, tiered by maturity

The single most important framing for the roadmap — ordered most-settled first:

1. **Control-plane tenant separation** (who can register/query/connect) —
   **solved by IS-10**, fits Authentik + nmos-cpp. Adopt-and-configure, not
   invent.
2. **Soft data-plane separation on a shared MXL node** — *buildable today* on
   MXL's per-flow UNIX perms, but filesystem-grade. Good for cooperating vendors
   exchanging via MXL; not a hostile boundary.
3. **Hostile-tenant data-plane separation on shared media hardware** — **not
   solved by MXL or anyone cleanly.** This is the developing field. Dedicated
   nodes remain the only hard boundary until something like encrypted flows or a
   media-aware policy layer exists.
4. **Cross-node fabric tenancy** — **not yet possible** (transport is roadmap);
   when it lands it needs a security model that does not exist today.

---

## 7. Open questions

1. **Tenancy boundary** — namespace (Capsule) vs. virtual cluster (vcluster/
   Kamaji) vs. dedicated cluster? Likely a *spectrum* keyed to trust level and
   whether the vendor touches the media data plane.
2. **Registry topology** — one facility-wide NMOS registry with IS-10-scoped
   views, or per-vendor registries? (Affects discovery, federation, failure
   domains.)
3. **Multicast & VLAN governance** — how are multicast groups and media VLANs
   allocated and isolated per vendor on shared fabric?
4. **Hostile-tenant data-plane boundary** — is there an acceptable answer short
   of dedicated nodes for vendors that don't trust each other? (Open research.)
5. **IS-10 Authorization Server** — Authentik directly, or a thin NMOS-aware AS
   in front of it? What issues the `x-nmos` claim and how is it populated from
   vendor identity?
6. **Catalog → marketplace governance** — who vets vendor-published charts and
   images? What's the signing/verification gate?
7. **Resource accounting / billing** — does "request resources" imply metering?
   (Out of scope for experiment phase, but shapes the data model.)
8. **Fabric security model** — to be designed *before* MXL Fabric is adopted for
   cross-tenant traffic, not after.

These belong in `docs/questions/` as they mature; this section is the seed.

---

## 8. Cheap-now design hooks (do these regardless)

Decisions that cost almost nothing today but ossify if ignored. Getting them
right makes the full vision an extension, not a rewrite:

- **Catalog data model carries an owner/vendor dimension** from the start
  (ADR-0013 / `DMF Function Catalog Model.md`), even if every entry is currently
  owned by the operator.
- **Namespace + identity conventions** that can later become tenant boundaries
  (don't bake single-tenant assumptions into namespace names or RBAC).
- **Image-registry namespacing in Zot** structured so per-vendor namespaces drop
  in cleanly (sibling of ADR-0033).
- **Node-labelling discipline** so "this node belongs to vendor X" is
  expressible — generalise ADR-0017's `dmf.io/role` scheme.
- **Keep IS-10 in view when configuring nmos-cpp** — avoid choices that would
  make enabling authorization later a re-architecture.

---

## 9. Phasing

- **Now (experiment phase):** none of this is built. Prove the single-tenant
  catalog media-function deploy end-to-end first. Adopt only the §8 design hooks.
- **Phase 2 (control-plane tenancy):** enable IS-10 on nmos-cpp with Authentik
  as AS; introduce the vendor principal class; per-vendor Zot/OpenBao scoping;
  catalog owner dimension goes live. This is the high-leverage, low-novelty step.
- **Phase 3 (compute tenancy):** virtual clusters + per-vendor node pools +
  resource requests, riding the multi-provider work.
- **Phase 4 (data-plane tenancy):** the hard part — shared-media-node separation
  beyond cooperative-grade, and a fabric security model. Gated on upstream
  maturity (MXL Fabric, encrypted-flow practice) and the open questions in §7.

---

## 10. References

- **ADR-0004** — experiment stance (this vision must not trigger premature
  hardening).
- **ADR-0013** — catalog model (gains the vendor/owner dimension).
- **ADR-0014 / ADR-0016** — nmos-cpp as Layer-5, Path A launcher transport.
- **ADR-0017** — MXL intra-host data plane; processor-node role; the topology
  this vision generalises.
- **ADR-0024 / ADR-0028** — two-layer identity model (operator vs app-local
  admin); the vendor principal is a third class.
- **ADR-0032 / ADR-0033** — scoped machine-write service accounts (NetBox, Zot);
  the per-vendor scoping pattern.
- **Next free ADR number: 0035** — a "vendor principal + IS-10 control-plane
  authz" ADR is the likely first formalisation when Phase 2 opens.
- `mxl/docs/Architecture.md` §"Security model" — UNIX-permission isolation,
  IPC/namespace-free container model.
- `mxl/docs/Addressability.md` — remote-flow URI scheme (fabric addressing).
- **AMWA IS-10** (NMOS Authorization), **BCP-003-01/02** — control-plane authz.
- `docs/architecture/DMF Function Catalog Model.md` — where the owner dimension
  lands.
