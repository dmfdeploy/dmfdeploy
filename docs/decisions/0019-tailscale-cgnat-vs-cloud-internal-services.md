# ADR-0019: Tailscale CGNAT range overlaps Aliyun (and other cloud) internal services: keep an explicit allow rule per cloud

**Status:** Accepted
**Date:** 2026-05-11
**Deciders:** @<handle>
**Related:** ADR-0018 (self-managed k3s), `dmf-env/tasks/aliyun/firewall.yml`,
`docs/archive/architecture/dmf-local-kubectl-via-tailscale.md`.

## Context

Tailscale's `ts-input` iptables chain, installed unconditionally by `tailscaled` on every node, ends with a drop
rule for the whole CGNAT block `100.64.0.0/10` (RFC 6598) on any interface except `tailscale0`. Aliyun's documented
internal services (instance metadata at `100.100.100.200`, DNS resolvers at `100.100.2.136` and `100.100.2.138`,
and the OpenAPI VPC endpoints in `100.100.0.0/16`) sit inside that block. An outbound call to them leaves `eth0`,
but the reply arrives on `eth0` with a CGNAT source address and `ts-input` drops it, so the connection stays in
`SYN_RECV`. This is one of two root causes of the empty SLB backend (`ServerCount: 0`) seen in the 2026-05-11
`aliyun` session. Full details are in the archive record.

## Decision

Per environment that runs on a cloud whose internal service IPs fall within `100.64.0.0/10`, install a per-host
systemd unit (bound to `tailscaled.service`) that inserts a narrowly scoped `RETURN` rule into Tailscale's
`ts-input` chain *above* the CGNAT drop, covering only that cloud's documented internal service CIDR.

For aliyun this is `100.100.0.0/16`. The unit was implemented by `dmf-env/tasks/aliyun/firewall.yml` (run on every
k3s node via `harden_cloud_firewall_tasks` in the generic `roles/base/harden`), and it re-armed on every `tailscaled`
start or restart and on reboot via `PartOf=tailscaled.service` and `WantedBy=tailscaled.service`. dmf-env no longer
carries that file, so this safeguard is not implemented today. An Aliyun environment that runs Tailscale needs the
unit restored before Tailscale starts on its nodes.

The scope stays tight (one /16) so that legitimate CGNAT-source spoofing protection remains in force for every other Tailscale
peer.

### When this ADR is load-bearing

Add or revise this ADR, and the corresponding `dmf-env/tasks/<cloud>/firewall.yml` helper, whenever any of the
following changes:

- **A new cloud env joins DMF.** Check whether the provider's internal service range overlaps `100.64.0.0/10`.
  Aliyun, certain Oracle Cloud regions, and some on-prem providers using RFC 6598 for "internet-facing" services do
  collide. Audit before deploying. AWS and GCP metadata at `169.254.169.254` is link-local and does not conflict.
- **Tailscale changes its CGNAT drop rule.** The current behavior was confirmed against `tailscaled` 1.x as of
  2026-05-11. If a future Tailscale release changes scope, this ADR's workaround may stop being necessary.
- **Aliyun introduces new internal service IPs outside `100.100.0.0/16`.** Widen the allow CIDR in
  `tailscale-aliyun-internal-allow.sh` and revise here.
- **We adopt an in-cluster app that wants to advertise CGNAT routes** (for example Tailscale Operator with subnet
  routing). The current allow rule is one-way only; bidirectional advertisement would need rethinking.

## Consequences

- **Application IPs must not be in `100.100.0.0/16`** on Aliyun-hosted DMF clusters. Pods or services living there
  would clash with the carve-out. Flannel pod CIDR (`10.42.0.0/16` default) and service CIDR (`10.43.0.0/16`
  default) are both safe.
- **Tailscale ACLs should not assume `ts-input` is the only filter for CGNAT-sourced packets on an Aliyun node.**
  The RETURN rule lets *anything* with source `100.100.0.0/16` past the Tailscale chain. The Aliyun Security Group
  (one tier above) still restricts what can reach the host on these ports, and `100.100.0.0/16` traffic only ever
  appears as a *reply* to a connection we initiated (Aliyun does not originate inbound to ECS from these addresses).
- **A future "any cloud" abstraction** (per `docs/plans/`'s multi-provider selection direction) needs a hook in the
  generic harden role or Tailscale role for "post-tailscale, per-cloud firewall reconcile" instead of relying on the
  `harden_cloud_firewall_tasks` indirection alone. Currently the install lives in `firewall.yml` for ergonomic
  reasons (it already runs on all nodes); the conceptual home is "Tailscale post-install" if or when such a hook exists.

## Enforcement

discipline only: no check, test or workflow in this repository or the component repositories asserts the allow
rule (a search for `ts-input` and `tailscale-aliyun-internal-allow` finds no match outside the dmf-infra
`ingress-private` comment). The Aliyun unit is not implemented today (see the Decision), so a reviewer checks any
environment that runs Tailscale on a cloud with an internal CGNAT range, and any new cloud's range, by hand.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0019-tailscale-cgnat-vs-cloud-internal-services.md).
