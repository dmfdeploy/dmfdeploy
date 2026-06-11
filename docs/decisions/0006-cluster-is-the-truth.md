# ADR-0006: The cluster is the truth, not local kubectl

**Status:** Accepted
**Date:** 2026-05-02 (formalized after a drift incident)
**Deciders:** @<handle>

## Context

The Mac's local `kubectl` context can point at any cluster — and historically
has pointed at the wrong one. "The rollout is done" reported by local kubectl
has, more than once, been about a *different* cluster than the one we cared
about. Silent context drift is worse than no context: it produces confident
wrong answers.

## Decision

For every read or write that depends on cluster state, the **only**
authoritative source is the control node, not the Mac's local `kubectl`.
Reads happen via SSH to the control node and `sudo kubectl --kubeconfig
/etc/rancher/k3s/k3s.yaml`. Writes happen through Ansible playbooks (which
likewise authenticate against the control node, not via local kubeconfig).

The kubeconfig at `/etc/rancher/k3s/k3s.yaml` is **not** copied off the control
node — it's a full cluster-admin certificate.

## Consequences

- **Positive:** no context-drift class of bug. The control node IP is part of
  the ADR; it's an explicit choice each time.
- **Positive:** the path is the same whether the operator is on the Mac, in CI,
  or in an SSH session to a peer node — always SSH-to-control + sudo kubectl.
- **Negative:** every read costs an SSH round-trip. ~200ms latency. Worth it.
- **Negative:** local `kubectl` is not configured for the lab cluster, by
  design. Discomfort for operators who expect it to "just work."

## Alternatives considered

- **Trust local kubectl but verify before each session.** Adds a verification
  step that's easy to skip. The mistakes happen on routine operations, not on
  ceremonial ones.
- **Distribute the kubeconfig to each operator's machine.** Each copy is a
  full cluster-admin cert; each is an attack surface. Centralizing on the
  control node minimizes copies of high-value credentials.

## Enforcement

`dmf-cms/scripts/verify-cluster.sh` exists for this exact purpose: SSH to the
control node and confirm the cluster's image matches local `VERSION`. The
`dmf-cluster-access` skill (§0 rule 4) mandates the SSH path for reads. ADR-0007
(secrets discipline) reinforces the no-copy rule for the kubeconfig.
