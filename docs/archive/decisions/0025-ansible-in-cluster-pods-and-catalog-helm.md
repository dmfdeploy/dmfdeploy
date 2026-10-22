# ADR-0025 archive: Ansible runs in in-cluster pods using a Zot-hosted EE image; catalog functions deploy as Helm charts

This file holds material moved out of [ADR-0025](../../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Context (continued)

Lane B of the 2026-05-19 convergence plan proved this shape end-to-end on
`<env>` on 2026-05-23. `media-launch-nmos-cpp` ran in an AWX Container
Group EE pod, installed the NMOS Helm chart from in-cluster Zot into the
`nmos` namespace, flipped the NetBox lifecycle tag to active, and the NMOS
Query API returned HTTP 200 with the mock nodes registered. Implementation
evidence: `dmf-infra@cf5ded4`, `d0831cb`, `efa9cd3`, `eb36581`, `b4822ae`;
`dmf-runbooks@1630626`, `c67c955`, `dd1a400`; `dmf-media@07d2df7`,
`b954342`.

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

## Cross-references

- [ADR-0013](../../decisions/0013-media-function-catalog-model.md) — catalog lifecycle model.
- [ADR-0014](../../decisions/0014-awx-project-layout.md) — hybrid AWX project layout.
- [ADR-0016](../../decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md) — Path A,
  now fully superseded for `media-*` JTs only.
- [ADR-0023](../../decisions/0023-internal-service-dns-for-cross-app-wiring.md) — applies to
  pod-to-pod HTTP calls; this ADR records the node-side image-pull exception.
- `docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`
  — convergence parent plan; Lane C remains in flight.
- `docs/plans/dmf-adr-0025-lane-b-implementation-plan.md` — Lane B
  implementation plan and Phase 6 amendment.

## Context — incident and evidence (moved from the ADR)

That
was a reasonable experiment-phase unblock after the 2026-05-05 credential
incident, but the first real `media-launch-nmos-cpp` run on `aliyun-123`
exposed the failure mode. AWX job 44 failed with `UNREACHABLE!` because
`dmf-runbooks/playbooks/launch-nmos-cpp.yml` carried a Hetzner-only private-IP
`ansible_host` remap. Fixing that one map would only create a new per-env
band-aid for the next cluster.

## Decision — where the image-pull tasks live (moved from the ADR)

These tasks now live in the base `k3s` role and the Zot role defaults, so
future envs inherit the working image-pull path.
