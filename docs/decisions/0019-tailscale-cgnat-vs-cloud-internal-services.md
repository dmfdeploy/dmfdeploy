# ADR-0019: Tailscale CGNAT range overlaps Aliyun (and other cloud) internal services — keep an explicit allow rule per cloud

**Status:** Accepted
**Date:** 2026-05-11
**Deciders:** @<handle>
**Related:** ADR-0018 (self-managed k3s), `dmf-env/tasks/aliyun/firewall.yml`,
`docs/archive/architecture/dmf-local-kubectl-via-tailscale.md`.

## Context

Aliyun's `aliyun` environment surfaced an SLB-backend-empty regression
during the 2026-05-11 session: the `dmf-traefik-slb` (`<aliyun-slb-ip>`)
existed and had listeners, but its vserver groups were empty
(`ServerCount: 0`) — apps were reachable only via the private/Tailscale
lane, not via the public hostname.

Root cause (one of two): Tailscale's `ts-input` iptables chain, installed
unconditionally by `tailscaled` on every node, ends with

```
DROP all -- !tailscale0 *  100.64.0.0/10  0.0.0.0/0
```

The CGNAT block `100.64.0.0/10` (RFC 6598) covers `100.64.0.0` through
`100.127.255.255`. Tailscale uses this entire `/10` for its own peer
addressing (controlled by Headscale here) but the daemon installs the
*full /10* drop regardless of which subset is actually allocated to
peers — the rule is hardcoded in the Tailscale Go binary.

Aliyun's documented internal service range sits inside that same /10:

| Address(es) | Service |
|---|---|
| `100.100.100.200` | ECS Instance Metadata Service (IMDS) — RAM role STS tokens |
| `100.100.2.136`, `100.100.2.138` | Internal DNS resolvers |
| `100.100.0.0/16` (broader) | OpenAPI VPC endpoints (VPC, SLB, ECS APIs reached from inside the VPC) |

Effect: when an ECS node makes an outbound call to any of these (e.g.
the Aliyun CCM refreshing its STS token, or calling
`DescribeRouteTableList` to set up flannel routes), the SYN leaves via
`eth0` correctly, but the SYN-ACK reply has source IP in
`100.100.0.0/16` ⊂ `100.64.0.0/10` and arrives on `eth0` — Tailscale's
`ts-input` drops it. `conntrack` confirms the connection is stuck in
`SYN_RECV` indefinitely.

## Decision

Per environment that runs on a cloud whose internal service IPs fall
within `100.64.0.0/10`, install a per-host systemd unit (bound to
`tailscaled.service`) that inserts a narrowly-scoped `RETURN` rule into
Tailscale's `ts-input` chain *above* the CGNAT drop, covering only that
cloud's documented internal service CIDR.

For aliyun this is `100.100.0.0/16`. The unit is implemented by
`dmf-env/tasks/aliyun/firewall.yml` (runs on every k3s node via
`harden_cloud_firewall_tasks` in the generic `roles/base/harden`).
Re-arms on every `tailscaled` start/restart and on reboot via
`PartOf=tailscaled.service` + `WantedBy=tailscaled.service`.

Scope kept tight (one /16) so legitimate CGNAT-source spoofing
protection remains in force for every other Tailscale peer.

### When this ADR is load-bearing

Add or revise this ADR — and the corresponding `dmf-env/tasks/<cloud>/firewall.yml`
helper — whenever any of the following changes:

- **A new cloud env joins DMF.** Check whether the provider's internal
  service range overlaps `100.64.0.0/10`. AWS IMDS at `169.254.169.254`
  is link-local (no conflict). GCP metadata at `169.254.169.254` (no
  conflict). Aliyun, certain Oracle Cloud regions, and some on-prem
  providers using RFC 6598 for "internet-facing" services do collide —
  audit before deploying.
- **Tailscale changes its CGNAT drop rule.** Out of our hands; the
  current behavior was confirmed against `tailscaled` 1.x as of
  2026-05-11. If a future Tailscale release changes scope (e.g. drops
  only a smaller subnet, or moves to nftables natively), this ADR's
  workaround may stop being necessary.
- **Aliyun introduces new internal service IPs outside `100.100.0.0/16`.**
  Widen the allow CIDR in `tailscale-aliyun-internal-allow.sh` and revise
  here.
- **We adopt an in-cluster app that wants to advertise CGNAT routes**
  (e.g. Tailscale Operator with subnet routing). The current allow rule
  is one-way only; bidirectional advertisement would need rethinking.

## Consequences

### Implications

- **Application IPs must not be in `100.100.0.0/16`** on Aliyun-hosted
  DMF clusters — pods/services living there would clash with the very
  carve-out we installed. Flannel pod CIDR (`10.42.0.0/16` default) and
  service CIDR (`10.43.0.0/16` default) are both safe.
- **Tailscale ACLs should not assume `ts-input` is the only filter for
  CGNAT-sourced packets on an Aliyun node** — our RETURN rule lets
  *anything* with source `100.100.0.0/16` past the Tailscale chain. The
  Aliyun Security Group (one tier above) still restricts what can reach
  the host on these ports, and `100.100.0.0/16` traffic only ever
  appears as a *reply* to a connection we initiated (Aliyun does not
  originate inbound to ECS from these addresses).
- **Future "any cloud" abstraction** (per `docs/plans/`'s multi-provider
  selection direction) needs a hook in the generic harden role or
  Tailscale role for "post-tailscale, per-cloud firewall reconcile"
  instead of relying on the `harden_cloud_firewall_tasks` indirection
  alone. Currently we put the install in `firewall.yml` for ergonomic
  reasons (it already runs on all nodes); the conceptual home is
  "Tailscale post-install" if/when such a hook exists.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0019-tailscale-cgnat-vs-cloud-internal-services.md).
