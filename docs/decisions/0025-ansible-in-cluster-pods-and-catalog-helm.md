# ADR-0025: Ansible runs in in-cluster pods using a Zot-hosted EE image; catalog functions deploy as Helm charts

**Status:** Accepted
**Date:** 2026-05-23
**Deciders:** @<handle> (with Claude/Codex implementation handoff)
**Partially supersedes:** [ADR-0016](0016-awx-control-node-ssh-via-cloud-init-and-openbao.md): catalog/`media-*` job templates move to in-cluster Helm; ADR-0016 (Path A) remains canonical for AWX-to-infrastructure plays.
**Rule:** `media-*` catalog launchers run in-cluster in AWX-spawned execution-environment pods (never by SSHing to a node), and catalog functions deploy as Helm charts from in-cluster Zot.

## Context

ADR-0016 adopted Path A for AWX-driven catalog launchers: AWX would SSH to the k3s control node using a Machine credential, then run Kubernetes tasks from the node where `/etc/rancher/k3s/k3s.yaml` is already available. Problem statement and evidence: see the [archive record](../archive/decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md).

## Decision

Media catalog launchers (`media-*` AWX Job Templates) execute in-cluster via AWX-spawned Execution Environment pods. They do not SSH to a control node. The shared EE image is hosted in cluster-internal Zot as `zot.zot.svc.cluster.local:5000/dmf/awx-ee:<tag>` and is selected through an AWX Container Group for catalog jobs.

Catalog functions deploy as Helm charts. Function images and chart artifacts are published outside the cluster, then Stage 4b seeds them into the cluster-local Zot registry before AWX catalog jobs consume them. `nmos-cpp` is the reference implementation: chart in `dmf-media/charts/nmos-cpp/`, launcher playbooks and NetBox lifecycle tasks in `dmf-runbooks`, and environment defaults in the `awx-integration` role.

The AWX controller ServiceAccount needs the following complete target-namespace RBAC set for Container Group operation: `pods` (`create`, `get`, `list`, `watch`, `delete`), `pods/log` (`get`, `list`, `watch`), `pods/exec` (`create`) and `pods/attach` (`create`). The current role does not grant `pods/portforward: create`, because the Container Group path does not use port-forwarding. Add it only if a future Container Group implementation starts invoking pod port-forwards.

The image-pull path has one important exception to ADR-0023's service-DNS rule. Pod-to-pod HTTP calls can use `*.svc.cluster.local`, but containerd pulls images from the node host network namespace before the pod exists. Nodes cannot resolve CoreDNS-only names by default. Therefore every env using cluster-internal Zot image references must have:

1. A pinned Zot Service `clusterIP`.
2. A node-side `/etc/hosts` entry mapping `zot.zot.svc.cluster.local` to that pinned ClusterIP, so kube-proxy can route the pull.
3. A containerd `certs.d/.../hosts.toml` override that marks the Zot endpoint as plain HTTP.

For catalog launchers, `kubernetes.core.helm wait: true` is not the readiness gate. It returned false-negative "Deployment status: Unknown" errors for workloads that were actually becoming ready. The launcher pattern is: run the Helm install/upgrade with `wait: false`, use explicit `kubernetes.core.k8s_info` readiness checks for the deployed objects, and only then run the configure/tag-flip stage. `dmf-runbooks@dd1a400` is the template for this pattern.

ADR-0016 remains canonical for AWX-to-infrastructure plays, especially the 693-class configure-stage playbooks that intentionally target the control node through the NetBox inventory. It is fully superseded only for `media-*` catalog Job Templates.

Lane C of the convergence plan, the generic in-cluster runner-pod work for configure-stage Ansible, remains in flight. It inherits the same Zot-hosted EE and node image-pull constraints, but Lane B closure does not require Lane C to be complete.

## Consequences

- **Positive:** Makes AWX Container Group RBAC explicit. The initial plan missed cross-namespace pod creation and `pods/attach`; both are now binding requirements. They are no longer tribal knowledge.
- **Positive:** Consolidates on one EE image for AWX catalog launchers and the future runner-pod lane.
- **Positive:** Cluster-internal image pull URLs are viable only with pinned Zot ClusterIP, node `/etc/hosts`, and containerd plain-HTTP override.
- **Negative:** Adds an artifact-seeding requirement before catalog jobs can run. Stage 4b must mirror the EE image, function images, and charts into Zot.
- **Negative:** Adds target-namespace RBAC surface for AWX controller pods. The blast radius is bounded to the catalog namespace and the verbs above, but it is still broader than the old SSH-only launcher.
- **Neutral:** Path A is not deleted. It remains the sanctioned mechanism for infrastructure playbooks until the separate runner-pod lane replaces it.

### Enforcement

Mechanical, for the cluster side:

- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml` is the enforcement point for the shared EE image (`awx_ee_catalog_image`), the `dmf-catalog-cg` Container Group, catalog Job Template instance-group pinning, the target-namespace RBAC (including `pods/attach`) and, through its defaults, the in-cluster role defaults. It must keep the RBAC set in the Decision section complete.
- `dmf-infra/k3s-lab-bootstrap/roles/base/k3s/tasks/containerd-registries.yml` writes the node `/etc/hosts` entry and the containerd `hosts.toml` plain-HTTP override, and `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/zot/tasks/main.yml` pins the Zot `clusterIP`. Removing any of the three breaks node-side pulls from `zot.zot.svc.cluster.local:5000`.

Discipline only: no test or workflow in `dmf-runbooks` checks a launcher's hosts or credentials. Code review for any `media-*` launcher must reject:

- `hosts:` targeting a real node or NetBox inventory group.
- `ansible_host` rewrites.
- SSH/Machine credential dependencies.
- Direct public ingress URLs when the consumer is an in-cluster EE pod and a cluster-internal Service URL exists.

Catalog launchers must follow the `dmf-runbooks@dd1a400` pattern: local execution in the EE pod, Helm install/upgrade with `wait: false`, explicit `kubernetes.core.k8s_info` readiness checks, then NetBox configure/finalise tasks.

[ADR-0016](0016-awx-control-node-ssh-via-cloud-init-and-openbao.md) is amended to mark `media-*` JTs as fully superseded by this ADR. Any future media launcher that reintroduces Path A needs a new ADR amendment. An inline exception is not allowed.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md).
