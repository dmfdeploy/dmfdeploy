# ADR-0018 archive: Stay self-managed k3s on every cloud — do not adopt ACK or other managed Kubernetes

This file holds material moved out of [ADR-0018](../../decisions/0018-self-managed-k3s-not-ack.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **ACK Managed Basic on Aliyun (no per-cluster fee).** Single-replica control
  plane, Terway CNI by default, integrated CCM. Resource billing identical to
  self-managed. Rejected for this rollout because it forks the platform shape
  per provider — the Hetzner lane stays self-managed (Hetzner has no managed
  K8s offering of equivalent maturity), so adopting ACK on Aliyun would mean
  two distinct cluster architectures to maintain. Cost-wise it would actually
  *save* effort on aliyun in isolation, but the cross-provider asymmetry
  outweighs that. Kept as a fallback option if Aliyun-specific maintenance
  proves dominant.
- **ACK Managed Pro.** Same reasoning as ACK Basic, plus a per-cluster
  control-plane fee that would set a precedent for paying per-environment for
  managed control planes.
- **ACK Distro (Aliyun's open-source self-managed K8s distribution).** Closer
  to our self-managed posture, but installs via `sealer` and ships Aliyun's
  preset add-ons. Adopting it would replace k3s with a different distribution,
  which in turn doesn't apply on Hetzner. Activity has slowed since 2023 per
  research. Rejected — same fragmentation problem.
- **AutoK3s by CNRancher.** Community installer with first-class Aliyun
  provider. Provisions ECS + installs k3s + wires CCM in one tool. Not
  rejected on technical grounds — it actually does almost exactly what our
  playbooks do — but adopting it means ceding the Layer 1+2+3 install path to
  a third-party tool that we'd need to extend for Hetzner anyway. Our
  Tofu+Ansible split already does the same job and stays portable.
- **EKS / GKE / AKS for future providers.** Same provider-lock-in argument.
  When we add AWS or GCP environments, they will use bare EC2/GCE +
  self-managed k3s, not the managed offerings.

## Moved from the ADR on 2026-10-23

## Context

While bootstrapping the second environment (`aliyun`, May 2026) we hit
provider-specific friction installing the Alibaba Cloud Controller Manager
(CCM) on a self-managed k3s cluster running Debian on bare ECS. That friction
surfaced a strategic question: should we keep fighting upstream CCM
compatibility on each new provider, or pivot environments to the provider's
managed Kubernetes offering (e.g. ACK Managed Basic — which has no per-cluster
fee and ships CCM/CNI pre-wired)?

The pull toward managed K8s is real: ACK Basic on Aliyun, EKS on AWS, GKE on
GCP, AKS on Azure all collapse much of our Layer 2/3 playbook code into a
single `tofu apply` of the provider's managed-K8s resource. The price is
provider-specific cluster shapes (Aliyun ACK uses Terway CNI and ACK-specific
add-ons; EKS uses VPC CNI; GKE uses GKE-shaped IAM and node pools), which
fragments the platform across providers.

The platform's experiment thesis (ADR-0004) is "DMF runs anywhere our playbooks
point — one architecture, many lanes." A managed-K8s pivot per-provider
invalidates that thesis: the lane *shape* would change with each provider, not
just the provisioning credentials and provider tasks.

There is also a recurring-cost axis. Managed Kubernetes' SLA-grade tiers carry
per-cluster control-plane fees (EKS ≈ $73/cluster/month, GKE ≈ $73/cluster/month
beyond the first free cluster, ACK Pro hourly fee, AKS Premium tier). DMF's
experiment phase spins environments up and down deliberately and is likely to
operate 2–5 clusters concurrently across providers; per-cluster fixed costs
compound quickly. Free tiers exist (ACK Basic, AKS Free, GKE first-cluster-free)
but bind us to single-replica control planes whose availability we don't
control. Self-managed k3s control planes ride on instances we already pay for
and have HA baked into the standard 3-node bootstrap.

### Positive consequences (original wording)

- **Positive:** the experiment thesis holds. Provider abstraction has one
  shape: bare-VM provisioning + uniform Ansible bootstrap. Lessons learned on
  one provider apply to every other.
- **Positive:** zero provider lock-in at the cluster shape level. The same
  workloads, same CNI, same CSI, same ingress run on Hetzner Cloud (today),
  Aliyun ECS (today), and any future provider (bare-metal, Hetzner-Robot,
  Azure, AWS) without re-architecture.
- **Positive:** the playbooks remain the canonical source of truth for *how*
  the platform is built. Operators can read one set of plays and understand
  every environment.
- **Positive:** zero recurring control-plane fees across all environments. At
  3+ concurrent clusters this is a non-trivial saving versus SLA-grade managed
  tiers; at 1–2 clusters it's smaller but still real.

### Original Enforcement references

- ADR-0004 (experiment phase) is the strategic frame this ADR specializes.
- `docs/reviews/dmf-aliyun-readiness-review-2026-05-08.md` and the
  CCM research notes (in handoffs / questions) document what self-managed
  Aliyun CCM actually requires — the cost is paid once.
