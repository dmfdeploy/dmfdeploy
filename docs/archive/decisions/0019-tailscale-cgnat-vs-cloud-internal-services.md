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
