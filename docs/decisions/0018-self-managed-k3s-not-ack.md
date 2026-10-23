# ADR-0018: Stay self-managed k3s on every cloud, and do not adopt ACK or other managed Kubernetes

**Status:** Accepted
**Date:** 2026-05-08
**Deciders:** @<handle>

**Rule:** Environments run self-managed k3s on every cloud provider. The one exception is ACK Managed Basic, a documented fallback allowed only when self-managed maintenance is the only friction preventing thesis-killer work.

## Context

Installing the Alibaba Cloud Controller Manager (CCM) on self-managed k3s in the
second environment (`aliyun`, May 2026) raised the question of pivoting to the
provider's managed Kubernetes, such as ACK Managed Basic. A pivot per provider
would change the lane shape with each provider and invalidate the ADR-0004
thesis, "DMF runs anywhere our playbooks point." Per-cluster control-plane fees
on SLA-grade tiers also compound across 2–5 concurrent clusters. For the full
context, see the [archive record](../archive/decisions/0018-self-managed-k3s-not-ack.md).

## Decision

The dmfdeploy platform stays on **self-managed k3s** for every environment regardless
of cloud provider. We do **not** adopt managed Kubernetes (ACK, EKS, GKE, AKS,
or equivalents) for any production or experiment environment.

When provider-specific cluster integration is needed (CCM, CSI, ingress class),
it lives in `dmf-env/tasks/<provider>/` task files invoked by the generic
playbooks via `*_provider_tasks` inventory variables. The cluster shape, CNI
(flannel by default), CRI (containerd via k3s), and OS (Debian 13.4 ARM64)
remain identical across providers.

ACK Managed Basic remains a documented **fallback option** (see "Alternatives
considered" in the [archive record](../archive/decisions/0018-self-managed-k3s-not-ack.md#alternatives-considered))
if self-managed maintenance burden on a specific provider becomes the dominant
cost. The bar to invoke it is high: it must be the only friction preventing
thesis-killer work. A general preference for less ops does not meet it.

## Consequences

- **Positive:** the experiment thesis holds, and the platform has no provider
  lock-in at the cluster shape level. Control-plane fees are zero.
- **Negative:** we pay the CCM/CNI/CSI integration cost once per provider.
  Aliyun cost was ~one afternoon (the ACK research established what's actually
  required); future providers will cost similar one-shot effort.
- **Negative:** we run on un-blessed paths on some providers. Aliyun's
  supported OS list is Alibaba Cloud Linux 3, ContainerOS, Ubuntu and CentOS.
  Debian is "you're on your own." We accept this cost in exchange for a
  unified platform.
- **Negative:** Aliyun-specific add-ons (Terway CNI, ALB Ingress, etc.) are
  unavailable to us. We use flannel, Traefik and standard k8s patterns
  instead, which means slightly less native integration with the provider's
  L7 features.
- **Neutral:** the platform plan documents a separate, deferred direction
  (per-resource provider chooser from `dmf-cms`, see
  `docs/plans/dmf-multi-provider-resource-selection-future-direction.md`).
  That direction is compatible with this ADR. It picks providers per resource
  and always provisions self-managed k3s as the cluster shape.

### Enforcement

- New environments, which live operator-local under `~/.dmfdeploy/envs/<env>/`
  (ADR-0035) and use the shared `dmf-env/terraform/` roots, MUST provision bare
  VMs and install k3s via the
  shared `dmf-infra/k3s-lab-bootstrap/playbooks/300-k3s.yml`. Provider-specific
  CCM/CSI/ingress glue lives in `dmf-env/tasks/<provider>/`. PRs that introduce
  provider-managed K8s as the cluster shape are reverted unless they cite this
  ADR as superseded.
- discipline only: no automated CI gate enforces this. Agents should reference
  this ADR when reviewing cross-repo changes that touch cluster bootstrap.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0018-self-managed-k3s-not-ack.md).
