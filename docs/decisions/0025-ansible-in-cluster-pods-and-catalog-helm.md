# ADR-0025: Ansible runs in in-cluster pods using a Zot-hosted EE image; catalog functions deploy as Helm charts

**Status:** Accepted
**Date:** 2026-05-23
**Deciders:** @<handle> (with Claude/Codex implementation handoff)
**Rule:** `media-*` catalog launchers run in-cluster in AWX-spawned execution-environment pods (never by SSHing to a node), and catalog functions deploy as Helm charts from in-cluster Zot.

## Context

ADR-0016 adopted Path A for AWX-driven catalog launchers: AWX would SSH to
the k3s control node using a Machine credential, then run Kubernetes tasks
from the node where `/etc/rancher/k3s/k3s.yaml` is already available. That
was a reasonable experiment-phase unblock after the 2026-05-05 credential
incident, but the first real `media-launch-nmos-cpp` run on `aliyun-123`
exposed the failure mode. AWX job 44 failed with `UNREACHABLE!` because
`dmf-runbooks/playbooks/launch-nmos-cpp.yml` carried a Hetzner-only private-IP
`ansible_host` remap. Fixing that one map would only create a new per-env
band-aid for the next cluster.

The deeper issue is that catalog functions are Kubernetes workloads. They do
not need a node-local SSH hop. The right execution substrate is already
inside the cluster: an AWX Execution Environment pod with Kubernetes modules,
namespace-scoped RBAC, and access to cluster-internal services. This also
aligns catalog functions with ADR-0013's catalog model and ADR-0023's rule
that cross-app HTTP wiring uses cluster-internal service DNS from in-cluster
callers.

Lane B of the 2026-05-19 convergence plan proved this shape end-to-end on
`g2r6-foa9` on 2026-05-23. `media-launch-nmos-cpp` ran in an AWX Container
Group EE pod, installed the NMOS Helm chart from in-cluster Zot into the
`nmos` namespace, flipped the NetBox lifecycle tag to active, and the NMOS
Query API returned HTTP 200 with the mock nodes registered. Implementation
evidence: `dmf-infra@cf5ded4`, `d0831cb`, `efa9cd3`, `eb36581`, `b4822ae`;
`dmf-runbooks@1630626`, `c67c955`, `dd1a400`; `dmf-media@07d2df7`,
`b954342`.

## Decision

Media catalog launchers (`media-*` AWX Job Templates) execute in-cluster via
AWX-spawned Execution Environment pods, not by SSHing to a control node. The
shared EE image is hosted in cluster-internal Zot as
`zot.zot.svc.cluster.local:5000/dmf/awx-ee:<tag>` and is selected through an
AWX Container Group for catalog jobs.

Catalog functions deploy as Helm charts. Function images and chart artifacts
are published outside the cluster, then Stage 4b seeds them into the
cluster-local Zot registry before AWX catalog jobs consume them. `nmos-cpp`
is the reference implementation: chart in `dmf-media/charts/nmos-cpp/`,
launcher playbooks and NetBox lifecycle tasks in `dmf-runbooks`, and
environment defaults in the `awx-integration` role.

The AWX controller ServiceAccount needs the following complete target-namespace
RBAC set for Container Group operation:

| Resource | Verbs |
|---|---|
| `pods` | `create`, `get`, `list`, `watch`, `delete` |
| `pods/log` | `get`, `list`, `watch` |
| `pods/exec` | `create` |
| `pods/attach` | `create` |

`pods/portforward: create` is not part of the current role because the
Container Group path does not use port-forwarding. Add it only if a future
Container Group implementation actually starts invoking pod port-forwards.

The image-pull path has one important exception to ADR-0023's service-DNS
rule. Pod-to-pod HTTP calls can use `*.svc.cluster.local`, but containerd
pulls images from the node host network namespace before the pod exists.
Nodes cannot resolve CoreDNS-only names by default. Therefore every env using
cluster-internal Zot image references must have:

1. A pinned Zot Service `clusterIP`.
2. A node-side `/etc/hosts` entry mapping `zot.zot.svc.cluster.local` to that
   pinned ClusterIP, so kube-proxy can route the pull.
3. A containerd `certs.d/.../hosts.toml` override that marks the Zot endpoint
   as plain HTTP.

These tasks now live in the base `k3s` role and the Zot role defaults, so
future envs inherit the working image-pull path.

For catalog launchers, `kubernetes.core.helm wait: true` is not the readiness
gate. It returned false-negative "Deployment status: Unknown" errors for
workloads that were actually becoming ready. The launcher pattern is:

1. Run the Helm install/upgrade with `wait: false`.
2. Use explicit `kubernetes.core.k8s_info` readiness checks for the deployed
   objects.
3. Only then run the configure/tag-flip stage.

`dmf-runbooks@dd1a400` is the template for this pattern.

ADR-0016 remains canonical for AWX-to-infrastructure plays, especially the
693-class configure-stage playbooks that intentionally target the control
node through the NetBox inventory. It is fully superseded only for `media-*`
catalog Job Templates.

Lane C of the convergence plan, the generic in-cluster runner-pod work for
configure-stage Ansible, remains in flight. It inherits the same Zot-hosted
EE and node image-pull constraints, but Lane B closure does not require Lane C
to be complete.

## Consequences

- **Positive** — Removes the per-cloud `ansible_host` band-aid class from
  media launchers. A media catalog job no longer cares which private subnet
  or control-node address a cluster uses.
- **Positive** — Turns catalog functions into releasable chart + image
  artifacts. Runtime deployment becomes a Helm release, while NetBox remains
  the lifecycle/status source of truth.
- **Positive** — Consolidates on one EE image for AWX catalog launchers and
  the future runner-pod lane.
- **Positive** — Makes AWX Container Group RBAC explicit. The initial plan
  missed cross-namespace pod creation and `pods/attach`; both are now binding
  requirements, not tribal knowledge.
- **Positive** — Captures the containerd DNS finding. Cluster-internal image
  pull URLs are viable only with pinned Zot ClusterIP, node `/etc/hosts`, and
  containerd plain-HTTP override.
- **Negative** — Adds an artifact-seeding requirement before catalog jobs can
  run. Stage 4b must mirror the EE image, function images, and charts into Zot.
- **Negative** — Adds target-namespace RBAC surface for AWX controller pods.
  The blast radius is bounded to the catalog namespace and the verbs above,
  but it is still broader than the old SSH-only launcher.
- **Neutral** — Path A is not deleted. It remains the sanctioned mechanism
  for infrastructure playbooks until the separate runner-pod lane replaces it.

## Alternatives Considered

- **Keep Path A and fix the `ansible_host` map per environment.** Rejected.
  It fixes one symptom and preserves the wrong execution boundary for
  Kubernetes-native workloads.
- **Use public registry image references directly from catalog jobs.** Rejected
  for runtime. Public registries remain publication sources, but clusters pull
  from local Zot for reproducibility and reduced external dependency during
  operations.
- **Expose Zot through ingress or a node port for image pulls.** Rejected for
  Lane B. The pinned ClusterIP plus kube-proxy path is enough for node-local
  containerd pulls and avoids adding a LAN/external exposure dependency.
- **Use `kubernetes.core.helm wait: true` as the only readiness gate.** Rejected
  after Phase 6 false negatives. The explicit `k8s_info` gate is clearer and
  tied to the workload's actual readiness signal.
- **Move NetBox lifecycle logic into the Helm chart.** Rejected. The chart owns
  Kubernetes resources; the launcher role owns catalog lifecycle state and
  NetBox tagging.

## Enforcement

Code review for any `media-*` launcher must reject:

- `hosts:` targeting a real node or NetBox inventory group.
- `ansible_host` rewrites.
- SSH/Machine credential dependencies.
- Direct public ingress URLs when the consumer is an in-cluster EE pod and a
  cluster-internal Service URL exists.

Catalog launchers must follow the `dmf-runbooks@dd1a400` pattern: local
execution in the EE pod, Helm install/upgrade with `wait: false`, explicit
`kubernetes.core.k8s_info` readiness checks, then NetBox configure/finalise
tasks.

The `awx-integration` role is the enforcement point for the shared EE image,
AWX Container Group, catalog Job Template instance-group pinning, target
namespace RBAC, and in-cluster role defaults. It must keep the RBAC set in the
Decision section complete.

The base `k3s` role and Zot role are the enforcement points for Zot image
pullability: pinned Zot `clusterIP`, node `/etc/hosts` entry, and containerd
`certs.d` plain-HTTP override. Removing any of those three pieces breaks
node-side containerd pulls from `zot.zot.svc.cluster.local:5000`.

`docs/decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md` is
amended to mark `media-*` JTs as fully superseded by this ADR. Any future
media launcher that reintroduces Path A needs a new ADR amendment, not an
inline exception.

## Cross-references

- [ADR-0013](0013-media-function-catalog-model.md) — catalog lifecycle model.
- [ADR-0014](0014-awx-project-layout.md) — hybrid AWX project layout.
- [ADR-0016](0016-awx-control-node-ssh-via-cloud-init-and-openbao.md) — Path A,
  now fully superseded for `media-*` JTs only.
- [ADR-0023](0023-internal-service-dns-for-cross-app-wiring.md) — applies to
  pod-to-pod HTTP calls; this ADR records the node-side image-pull exception.
- `docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`
  — convergence parent plan; Lane C remains in flight.
- `docs/plans/DMF ADR-0025 Lane B Implementation Plan 2026-05-22.md` — Lane B
  implementation plan and Phase 6 amendment.
