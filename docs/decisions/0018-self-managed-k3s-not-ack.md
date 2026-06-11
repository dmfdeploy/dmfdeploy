# ADR-0018: Stay self-managed k3s on every cloud — do not adopt ACK or other managed Kubernetes

**Status:** Accepted
**Date:** 2026-05-08
**Deciders:** @<handle>

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

## Decision

The DMF Platform stays on **self-managed k3s** for every environment regardless
of cloud provider. We do **not** adopt managed Kubernetes (ACK, EKS, GKE, AKS,
or equivalents) for any production or experiment environment.

When provider-specific cluster integration is needed (CCM, CSI, ingress class),
it lives in `dmf-env/tasks/<provider>/` task files invoked by the generic
playbooks via `*_provider_tasks` inventory variables. The cluster shape, CNI
(flannel by default), CRI (containerd via k3s), and OS (Debian 13.4 ARM64)
remain identical across providers.

ACK Managed Basic remains a documented **fallback option** (see "Alternatives
considered") if self-managed maintenance burden on a specific provider becomes
the dominant cost. The bar to invoke it is high: it must be the only friction
preventing thesis-killer work, not a generic preference for less ops.

## Consequences

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
- **Negative:** we pay the CCM/CNI/CSI integration cost once per provider.
  Aliyun cost was ~one afternoon (the ACK research established what's actually
  required); future providers will cost similar one-shot effort.
- **Negative:** we run on un-blessed paths on some providers. Aliyun's
  supported OS list is Alibaba Cloud Linux 3 + ContainerOS + Ubuntu + CentOS;
  Debian is "you're on your own." We accept this cost in exchange for a
  unified platform.
- **Negative:** Aliyun-specific add-ons (Terway CNI, ALB Ingress, etc.) are not
  available to us. We use flannel + Traefik + standard k8s patterns instead,
  which means slightly less native integration with the provider's L7
  features.
- **Neutral:** the platform plan documents a separate, deferred direction
  (per-resource provider chooser from `dmf-cms`, see
  `docs/plans/dmf-multi-provider-resource-selection-future-direction-2026-05-08.md`).
  That direction is compatible with this ADR — it picks providers per resource
  but always provisions self-managed k3s as the cluster shape.

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

## Enforcement

- ADR-0004 (experiment phase) is the strategic frame this ADR specializes.
- `docs/reviews/dmf-aliyun-readiness-review-2026-05-08.md` and the
  CCM research notes (in handoffs / questions) document what self-managed
  Aliyun CCM actually requires — the cost is paid once.
- New environments added in `dmf-env/inventories/<env>/` and
  `dmf-env/terraform/<env>/` MUST provision bare VMs and install k3s via the
  shared `dmf-infra/k3s-lab-bootstrap/playbooks/300-k3s.yml`. Provider-specific
  CCM/CSI/ingress glue lives in `dmf-env/tasks/<provider>/`. PRs that introduce
  provider-managed K8s as the cluster shape are reverted unless they cite this
  ADR as superseded.
- Discipline only — no automated CI gate enforces this; agents should reference
  this ADR when reviewing cross-repo changes that touch cluster bootstrap.
