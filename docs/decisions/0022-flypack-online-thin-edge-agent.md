# ADR-0022: Flypack-online profile is a thin local edge agent paired to a cloud DMF hub

**Status:** Proposed
**Date:** 2026-05-13
**Deciders:** @<handle>

## Context

The DMF Platform supports three deployment profiles: `cloud`,
`flypack-offline`, and `flypack-online`, formalised in
[`docs/plans/DMF Init Wizard Expansion Survey 2026-05-13.md`](../plans/DMF%20Init%20Wizard%20Expansion%20Survey%202026-05-13.md)
§"Round 2 clarifications and decisions". The term *flypack* is overloaded
across two of them and the difference is architectural, not cosmetic:

- **`flypack-offline`** runs the **full** DMF stack on local nodes with no
  cloud dependency. The canonical spec at
  [`dmf-infra/k3s-lab-bootstrap/docs/flypack-offline-lane.md`](../../dmf-infra/k3s-lab-bootstrap/docs/flypack-offline-lane.md)
  binds it: no central reach, no phone-home, sealed embedded OpenBao,
  embedded Authentik, embedded Zot. The RPi appliance plan
  ([`docs/plans/DMF RPi Flypack Appliance Implementation Plan 2026-05-13.md`](../plans/DMF%20RPi%20Flypack%20Appliance%20Implementation%20Plan%202026-05-13.md))
  is the minimal-sizing variant of this profile.
- **`flypack-online`** is materially different. It is an **edge agent**
  paired to a cloud DMF *hub*. The edge runs only the services that
  *have* to be local — by latency, locality, or layer-2 reach
  requirement; everything else (identity, secrets, AWX control plane,
  NetBox truth, monitoring storage) lives on the hub.

The "no central reach" rule in the offline-lane spec was written assuming
flypack-online did not yet exist (offline-lane line 31-33 defers it).
Now that flypack-online has a concrete definition, the rule needs
scoping: it binds `flypack-offline` and only `flypack-offline`.

A round-1 decision in the wizard survey (decision #2, dated 2026-05-13
before the round-2 clarification) framed flypack-online as "sovereign
with hub link" — a federated peer holding its own identity/secrets. The
operator's clarified intent is the opposite: a *thin* edge that
deliberately depends on the hub. That earlier framing is superseded by
this ADR.

## Decision

`flypack-online` is a separate deployment profile from `flypack-offline`,
defined by these properties.

### Architecture

- **Hub-paired, WAN-dependent at runtime.** The edge cannot operate
  meaningfully without reach to its hub. This is the deliberate trade
  for "thin" — the inverse of flypack-offline's sovereignty.
- **No local OpenBao on the edge.** Secrets are materialised locally via
  ESO whose `ClusterSecretStore` points at the **hub's** OpenBao over a
  mesh transport (Tailscale, WireGuard, or equivalent), authenticated
  via a per-edge AppRole identity rotated by the hub. Builds on
  [ADR-0008](0008-openbao-secrets-architecture.md) and
  [ADR-0021](0021-openbao-approle-reconciler-identity.md); no new
  secrets architecture introduced.
- **No local Authentik on the edge.** Edge-resident apps that need
  identity use the hub's Authentik over the mesh. Acceptable because
  flypack-online is by definition online; loss of hub means loss of
  edge identity, the same trust model as any cloud-paired edge.
- **Local services are scope-limited to data plane and last-mile
  control plane.** Roles that must run locally are those whose
  latency, locality, or layer-2 reach requirement forbids hub
  residence.

### Profile-to-mode mapping (per ADR-0020)

`flypack-online` is a **profile**, not a deployment mode. Its
regulatory posture is inherited from its hub's mode under
[ADR-0020](0020-deployment-scope-and-regulatory-posture.md):

- Hub in Mode A (OSS self-host) → edge inherits Mode A. No phone-home
  to `dmfdeploy.io`; operator self-hosts the hub.
- Hub in Mode B (managed `dmfdeploy.io`) → edge inherits Mode B. Edge ↔
  hub traffic is in-scope for managed-service obligations.
- Mode C (offline flypack) is incompatible with flypack-online by
  definition. The edge cannot be Mode C; that is `flypack-offline`.

### Roles at the edge — ship-now vs deferred-implementation

**Ship-now** (Ansible roles exist today or are trivially adapted from
existing dmf-infra primitives):

- **AWX execution node** — registers as a remote AWX Receptor mesh
  execution node against the hub's AWX. Local provisioning jobs
  (PXE, ZTP, switch config) run on-site without WAN-latency round-trips
  to hub Tower; hub AWX retains job control.
- **Local Zot pull-through cache** — mirrors hub Zot; serves on-site
  k3s/podman/PXE-booted devices without per-pull WAN traffic.
- **Prometheus agent** — `remote_write` mode pointed at hub
  Prometheus / VictoriaMetrics / Mimir. No local TSDB; the edge owns
  the scrape targets, the hub owns the data.

**Deferred-implementation** (no Ansible role yet; collectively a
separate, multi-month track that does not block wizard v2):

- **iSCSI target server** — local block storage for on-site equipment.
- **NMOS registry at the edge** — distinct concern from any
  central-side NMOS registry role; placement-at-the-edge is the novel
  decision.
- **Kea DHCP**, **ZTP (zero-touch provisioning)**, **VLAN/SDN
  control**, **DNS-SD/mDNS responder**, **remote-controllable
  tcpdump**, **other Layer-2 broadcast-facility tooling** — depends on
  the broadcast-facility productisation roadmap, not on wizard v2.

The wizard (per round-2 step 2 of the survey doc) can *name*
`flypack-online` as a profile and collect hub-pairing material from
v2, but only enables the ship-now subset until deferred roles land.

## Consequences

- **Positive**
  - The "no central reach" rule in offline-lane.md is correctly scoped:
    it binds `flypack-offline` only. Removes the hidden contradiction
    that would have blocked any flypack-online implementation.
  - flypack-online builds on existing platform primitives — ESO +
    AppRole, AWX Receptor mesh, Zot pull-through, Prometheus
    `remote_write` — with no new secrets/identity architecture.
  - The broadcast-facility Layer-2 tooling track is decoupled from
    wizard v2. Wizard ships when ship-now roles ship; L2 tooling
    ships when its own roles ship; neither blocks the other.

- **Negative**
  - flypack-online is non-functional during hub outages. Accepted; it
    is the defining property of the profile. Operators needing
    sovereignty deploy `flypack-offline` instead.
  - Per-edge AppRole `secret_id` rotation must be operationally robust
    before any flypack-online ships in production. Builds on ADR-0021
    but adds the *"edge cannot reach hub OpenBao if its own
    credentials are expired"* failure mode. A recovery-from-expired
    runbook is required before first production edge.
  - Two flypack profiles sharing the same prefix will continue to
    confuse new readers. This ADR is the canonical disambiguation;
    treat any ambiguous reference to "the flypack" as defective and
    require qualification.

- **Neutral**
  - Whether a future edge-resident NMOS registry shares code with a
    central-side NMOS role (e.g. the dmf-runbooks `nmos-cpp` role per
    [ADR-0014](0014-awx-project-layout.md) /
    [ADR-0016](0016-awx-control-node-ssh-via-cloud-init-and-openbao.md))
    or is a separate role is an implementation question, not an
    architecture decision.

## Alternatives considered

- **Sovereign-with-hub** (round-1 decision #2 in the wizard survey).
  Defined flypack-online as a peer holding its own identity/secrets
  with telemetry/config sync to a hub. Rejected because (a) it
  duplicated the offline-lane spec at higher operational cost, (b) the
  operator's clarified intent is a thin edge, not a federated peer,
  and (c) OpenBao OSS does not provide Vault Enterprise-style
  performance-replica federation, so embedded-secrets-with-sync was
  non-trivial to build. **Superseded by this ADR.**

- **Thick mirror at the edge** — full DMF stack at the edge plus
  bidirectional sync to hub. Rejected because the resource envelope
  at edge sites (RPi-class to 1U mini-server class) does not
  accommodate a full stack, and because bidirectional sync of
  OpenBao + Authentik + NetBox + AWX is an entire research project.

- **Drop flypack-online entirely** — support only `cloud` and
  `flypack-offline`. Rejected because the broadcast-facility use case
  the operator described (local provisioning, local L2 control,
  local boot-image caching, local data plane) is real and served by
  neither of the other two profiles. Cloud is too far for L2;
  flypack-offline is too thick for low-touch edge sites.

## Enforcement

- This ADR is the canonical reference for what `flypack-online` means.
  Any code in `dmf-infra` defaults, `dmf-cms` UI, wizard renderers, or
  agent prompts that conflicts with the role split above (e.g. shipping
  local OpenBao with `flypack-online`) must supersede this ADR rather
  than contradict it.
- The init wizard's profile prompt (per round-2 step 2 of the
  [survey doc](../plans/DMF%20Init%20Wizard%20Expansion%20Survey%202026-05-13.md))
  is the first concrete enforcement point: its role-toggle defaults for
  `flypack-online` must match the ship-now list above and refuse the
  deferred set until those roles exist.
- The `flypack-offline-lane.md` decision-log entry binding "no central
  reach" (line 484-493 of that doc) requires a scoping clarification
  per the step-1 follow-up list in the survey doc; the canonical
  reading is *"no central reach for flypack-offline; flypack-online is
  governed by ADR-0022."*

Promote from **Proposed** → **Accepted** when:

1. The wizard v2 implementation (per step-4 spike) produces a working
   `flypack-online` profile rendering that matches the ship-now role
   list.
2. The per-edge AppRole rotation path (extension of ADR-0021) has a
   named owner and a documented recovery-from-expired-credentials
   runbook.
3. The first flypack-online site (or representative test deployment)
   has paired to a hub and run an end-to-end AWX execution job
   through Receptor + a Zot pull-through cache hit + a `remote_write`
   metrics scrape, all without local OpenBao or Authentik.
