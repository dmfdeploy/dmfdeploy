# ADR-0022: Flypack-online profile is a thin local edge agent paired to a cloud DMF hub

**Status:** Proposed
**Date:** 2026-05-13
**Deciders:** @<handle>
**Rule:** `flypack-online` is a separate deployment profile from `flypack-offline`. It is a thin edge agent paired to a cloud DMF hub. It runs no local OpenBao and no local Authentik, and its local services are limited to the data plane and last-mile control plane.

## Context

The dmfdeploy platform supports three deployment profiles: `cloud`, `flypack-offline`, and `flypack-online`, formalised in [`docs/plans/dmf-init-wizard-expansion-survey.md`](../plans/dmf-init-wizard-expansion-survey.md) §"Round 2 clarifications and decisions." The term *flypack* covers two of them, and the difference is architectural. `flypack-offline` runs the full stack on local nodes with no cloud dependency, and its canonical spec binds it: no central reach, no phone-home, sealed embedded OpenBao, embedded Authentik, embedded Zot. The RPi appliance plan is the minimal-sizing variant of that profile. `flypack-online` is an edge agent paired to a cloud DMF *hub*: the edge runs only the services that have to be local, and identity, secrets, the AWX control plane, NetBox truth and monitoring storage live on the hub.

The "no central reach" rule in the offline-lane spec ([`dmf-infra/k3s-lab-bootstrap/docs/flypack-offline-lane.md`](../../dmf-infra/k3s-lab-bootstrap/docs/flypack-offline-lane.md)) was written before flypack-online existed. It binds `flypack-offline` and only `flypack-offline`. This ADR supersedes the round-1 survey framing of flypack-online as a sovereign peer with a hub link.

## Decision

`flypack-online` is a separate deployment profile from `flypack-offline`, defined by these properties.

- **Hub-paired, WAN-dependent at runtime.** The edge cannot operate meaningfully without reach to its hub. This is the deliberate trade for "thin" and the inverse of flypack-offline's sovereignty.
- **No local OpenBao on the edge.** Secrets are materialised locally via ESO whose `ClusterSecretStore` points at the **hub's** OpenBao over a mesh transport (Tailscale, WireGuard, or equivalent), authenticated via a per-edge AppRole identity rotated by the hub. Builds on [ADR-0008](0008-openbao-secrets-architecture.md) and [ADR-0021](0021-openbao-approle-reconciler-identity.md); no new secrets architecture introduced.
- **No local Authentik on the edge.** Edge-resident apps that need identity use the hub's Authentik over the mesh.
- **Local services are scope-limited to data plane and last-mile control plane.** Roles that must run locally are those whose latency, locality, or layer-2 reach requirement forbids hub residence.
- **Ship-now roles:** an AWX execution node (a remote Receptor mesh node against the hub's AWX; hub AWX retains job control), a local Zot pull-through cache that mirrors hub Zot, and a Prometheus agent in `remote_write` mode pointed at the hub (no local TSDB).
- **Deferred-implementation roles** (no Ansible role yet; a separate multi-month track that does not block wizard v2): iSCSI target server, NMOS registry at the edge, Kea DHCP, ZTP, VLAN/SDN control, DNS-SD/mDNS responder, remote-controllable tcpdump, and other Layer-2 broadcast-facility tooling.
- The wizard can *name* `flypack-online` as a profile and collect hub-pairing material from v2, but only enables the ship-now subset until deferred roles land.

### Profile-to-mode mapping (per ADR-0020)

`flypack-online` is a **profile** and is never a deployment mode. Its regulatory posture is inherited from its hub's mode under [ADR-0020](0020-deployment-scope-and-regulatory-posture.md):

- Hub in Mode A (OSS self-host): the edge inherits Mode A. There is no phone-home to `dmfdeploy.io`; the operator self-hosts the hub.
- Hub in Mode B (managed `dmfdeploy.io`): the edge inherits Mode B. Edge to hub traffic is in scope for managed-service obligations.
- Mode C (offline flypack) is incompatible with flypack-online by definition. The edge cannot be Mode C; that is `flypack-offline`.

## Consequences

- The "no central reach" rule binds `flypack-offline` only, which removes a hidden contradiction that would have blocked any flypack-online implementation.
- flypack-online builds on existing platform primitives (ESO + AppRole, AWX Receptor mesh, Zot pull-through, Prometheus `remote_write`) with no new secrets or identity architecture.
- The Layer-2 tooling track is decoupled from wizard v2. The wizard ships when the ship-now roles ship, and L2 tooling ships when its own roles ship; neither blocks the other.
- flypack-online is non-functional during hub outages. This is the defining property of the profile. Operators needing sovereignty deploy `flypack-offline` instead.
- Loss of the hub means loss of edge identity, the same trust model as any cloud-paired edge.
- Per-edge AppRole `secret_id` rotation must be operationally robust before any flypack-online ships in production. The edge cannot reach hub OpenBao if its own credentials expired, so a recovery-from-expired runbook is required before the first production edge.
- Two flypack profiles share one prefix. This ADR is the canonical disambiguation. Treat any ambiguous reference to "the flypack" as defective and require qualification.
- Whether an edge-resident NMOS registry shares code with a central-side NMOS role is an implementation question and outside this decision.
- The `flypack-offline-lane.md` decision-log entry binding "no central reach" reads as: no central reach for flypack-offline; flypack-online is governed by ADR-0022.

### Enforcement

discipline only: no check, wizard prompt or workflow enforces the edge role split. A search of `dmf-init`, `dmf-infra`, `dmf-cms` and `dmf-env` finds `flypack-online` only as a valid profile name (`dmf-env/bin/lib/render-provider-descriptor.py`, `dmf-infra/k3s-lab-bootstrap/providers/tailscale.yaml`). Code that conflicts with the role split, such as shipping local OpenBao with `flypack-online`, must supersede this ADR. The init wizard's profile prompt is the first intended enforcement point: its role-toggle defaults for `flypack-online` must match the ship-now list and refuse the deferred set until those roles exist.

## Status

Proposed

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

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0022-flypack-online-thin-edge-agent.md).
