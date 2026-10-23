# ADR-0019 archive: Tailscale CGNAT range overlaps Aliyun (and other cloud) internal services — keep an explicit allow rule per cloud

This file holds material moved out of [ADR-0019](../../decisions/0019-tailscale-cgnat-vs-cloud-internal-services.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Context (live-cluster manifestation, moved from the ADR)

In the live cluster this manifested as:

1. Aliyun CCM panicked on the next STS-token refresh (~6h after the
   token was first obtained pre-Tailscale, in the playbook order that
   installs Tailscale *after* CCM) and entered CrashLoopBackOff. No SLB
   reconciliation thereafter.
2. CCM route controller intermittently logged `dial tcp 100.100.0.49:443:
   i/o timeout` against the VPC OpenAPI endpoint.
3. Once CCM was restarted (after manually inserting an IMDS allow rule),
   the SLB vserver groups still showed `ServerCount: 0` because the CCM's
   service controller couldn't query the OpenAPI VPC endpoints either.

## What we considered

| Option | Why rejected |
|---|---|
| Move tailnet to a smaller subnet (e.g. `10.64.0.0/16`) | Tailscale uses CGNAT (RFC 6598) by design; the `100.64.0.0/10` drop rule is hardcoded in `tailscaled`. Headscale chooses *which* CGNAT /32s to hand out but does not change the drop. Even allocating from a `100.64.0.0/16` window still leaves the `100.100.x.x` Aliyun range inside the dropped /10. |
| Move Aliyun's internal services off `100.100.0.0/16` | Not an option — these are VPC anycast addresses fixed by Aliyun's infrastructure. |
| `tailscale up --netfilter-mode=off` | Disables *all* of Tailscale's iptables protections (anti-spoof, MASQUERADE, the CGNAT-source drop that prevents address spoofing). Buys back the IMDS conflict at the cost of the rest of Tailscale's wire-level safety. |
| Switch CCM to AccessKey/Secret auth (avoid IMDS) | Conflicts with ADR-0018's posture (no AK/Secret on the cluster — STS-only). |
| Use Aliyun's `service.beta.kubernetes.io/alibaba-cloud-loadbalancer-backend-label` Service annotation | Tested live — does not bypass the master-label exclusion (that's a *separate* defect, tracked alongside this one in the CCM task). |

## References

- Tailscale GitHub issue [#391](https://github.com/tailscale/tailscale/issues/391) — original AWS IMDS conflict report
- Tailscale GitHub issue [#4233](https://github.com/tailscale/tailscale/issues/4233) — broader CGNAT collision discussion
- Aliyun docs — *ECS instance metadata* (IMDS at `100.100.100.200`)
- Aliyun docs — *VPC private network access to Alibaba Cloud services*
  (OpenAPI VPC endpoints in `100.100.0.0/16`)
- RFC 6598 — *IANA-Reserved IPv4 Prefix for Shared Address Space*
  (`100.64.0.0/10`)

## Moved from the ADR on 2026-10-23

### Context (full original text)

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

#### When this ADR is load-bearing

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
