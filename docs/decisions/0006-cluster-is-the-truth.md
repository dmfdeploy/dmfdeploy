# ADR-0006: The cluster is the truth; local kubectl is not

**Status:** Accepted
**Date:** 2026-05-02 (formalized after a drift incident)
**Deciders:** @<handle>

## Context

The Mac's local `kubectl` context can point at any cluster, and historically
has pointed at the wrong one. "The rollout is done" reported by local kubectl
has, more than once, been about a *different* cluster than the one we cared
about. Silent context drift is worse than no context: it produces confident
wrong answers.

## Decision

For every read or write that depends on cluster state, the **only**
authoritative source is the control node. The Mac's local `kubectl` is not.
Reads happen via SSH to the control node and `sudo kubectl --kubeconfig
/etc/rancher/k3s/k3s.yaml`. Writes happen through Ansible playbooks (which
likewise authenticate against the control node and never use a local kubeconfig).

The kubeconfig at `/etc/rancher/k3s/k3s.yaml` is **not** copied off the control
node. It's a full cluster-admin certificate.

## Consequences

- **Positive:** no context-drift class of bug. The control node IP is part of
  the ADR; it's an explicit choice each time.
- **Positive:** the path is the same whether the operator is on the Mac, in CI,
  or in an SSH session to a peer node. The path is always SSH-to-control + sudo kubectl.
- **Negative:** every read costs an SSH round-trip. ~200 ms latency. Worth it.
- **Negative:** local `kubectl` is not configured for the lab cluster, by
  design. Discomfort for operators who expect it to work.

### Enforcement

`dmf-cms/scripts/verify-cluster.sh` SSHes to the control node and confirms the cluster's
image matches local `VERSION`. The `dmf-cluster-access` skill mandates the SSH path for
reads (iron rule) and forbids copying the kubeconfig (§0 rule 4). Nothing blocks a local
`kubectl` call, so the rule otherwise rests on discipline. ADR-0007 reinforces no-copy.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0006-cluster-is-the-truth.md).
