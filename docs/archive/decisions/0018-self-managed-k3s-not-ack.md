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
