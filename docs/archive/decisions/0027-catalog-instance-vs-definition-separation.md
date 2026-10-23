# ADR-0027 archive: Separate catalog-entry, installation, and runtime-instance layers for media functions

This file holds material moved out of [ADR-0027](../../decisions/0027-catalog-instance-vs-definition-separation.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Status quo (Lane B's bootstrap-RBAC pattern).** Acceptable for
  first-party + small N. Fails on 3rd-party contribution friction.
  Lane B keeps this pattern; this ADR is what supersedes it when N>1.
- **AWX namespace CRUD (cluster-scoped).** Widens AWX's RBAC so the
  launcher creates namespaces itself. Cheapest path to "drop YAML +
  chart, no bootstrap change" — but doesn't solve the
  RBAC-template-per-function problem (each function still needs its
  own SA + Role + RoleBinding), just moves the creation point.
  Considered viable as a Stage-1 step toward this ADR.
- **Helm template stamps RBAC from catalog YAML inputs.** A single
  shared chart wraps the function chart and stamps SA + Role +
  RoleBinding from `values.rbac`. Avoids an operator. Works for
  trusted contributors; weaker trust boundary for adversarial 3rd
  parties (the trust check is at PR review time, not runtime).
- **GitOps (Argo CD / Flux Application per function).** Each function
  is an Application; controller handles namespace + RBAC.
  ADR-0025 §9 explicitly deferred GitOps. If GitOps lands later for
  other reasons, this ADR's reconciler can be that GitOps controller
  pattern instead of a custom operator.

## Cross-references

- ADR-0013 — Catalog model (YAML + NetBox tag). This ADR adds the
  installation/runtime split *within* ADR-0013's catalog frame;
  ADR-0013 itself is unchanged.
- ADR-0020 B.3 — Cluster-per-tenant. Solves multi-tenant isolation;
  this ADR solves multi-function contribution friction. Orthogonal.
- ADR-0025 — Catalog Helm + in-cluster execution. This ADR succeeds
  ADR-0025 for the per-function-RBAC question; the chart + EE pattern
  survives unchanged.
- ADR-0025 §9 — GitOps explicitly deferred. If GitOps lands for other
  reasons, the reconciler in this ADR can be GitOps-shaped (Argo
  Application per function) rather than a custom operator.
- ADR-0007 — Secrets never in argv. The reconciler reads the chart
  values from the CR and the catalog YAML; secrets remain in OpenBao
  per ADR-0008.
- ADR-0022 — Flypack-online profile. 3rd-party functions on flypack
  edge are out of scope for v1 of this ADR's reconciler; flypack
  catalog entries stay first-party at first.

## Source notes

The three-layer separation framing originates in a 2026-05-22 design
conversation with GPT-5 about Kubernetes namespace scalability for a
3rd-party media function catalog. Key points captured here:

- Kubernetes SIG Scalability lists 10K namespaces, 150K pods, 10K
  services, 5K nodes as the tested cluster ceiling. Thousands of
  namespaces *can* work; the operational cost lives in per-namespace
  object churn (RBAC, NetworkPolicy, quotas, GitOps state, service
  discovery noise), not namespace count itself.
- For untrusted 3rd-party code, namespace alone is not a security
  boundary. The safe set: per-instance SA, default-deny NetworkPolicy,
  ResourceQuota, LimitRange, Pod Security Admission, image
  signing/admission policy, runtimeClass / nodeSelector / taints for
  workload class, and stronger isolation (Kata, gVisor, separate
  cluster) for high-risk vendors.
- Multi-cluster sharding is preferable to single-cluster
  multi-namespace when workloads differ radically (GPU vs CPU,
  SR-IOV/DPDK vs not, PTP-aware nodes, multicast access, trust
  tiers). ADR-0020 B.3 (cluster-per-tenant) already aligns DMF with
  this guidance for the tenancy dimension.

The conversation is share-only (operator's local Chrome session,
2026-05-22); excerpts have been preserved in operator notes outside the
repo. This ADR captures the load-bearing recommendations so the
conversation is not the only record.

## Context — design-conversation background (moved from the ADR)

The 2026-05-22 GPT-5 design conversation (referenced in operator's offline
notes, share-only link) explicitly warns against catalog-entry-as-namespace
patterns: SIG Scalability has tested 10K namespaces / 150K pods per
cluster as a *threshold*, not a recommendation; the per-namespace object
churn (RBAC, NetworkPolicy, quotas, service discovery, GitOps state)
becomes the real cost long before the namespace count itself is the
bottleneck. The recommended shape is namespace-per-runtime-boundary
(tenant / site / ephemeral job), not namespace-per-catalog-entry.

## Context — background (moved from the ADR)

ADR-0013 established the function catalog model: YAML intent in
`dmf-media/catalog/<key>.yaml` + NetBox runtime tag. ADR-0025 made the
runtime substrate concrete: each catalog function deploys as a Helm chart
from cluster-internal Zot via an AWX EE pod. Lane B's NMOS-cpp
implementation (this PR, 2026-05-22) lifts the first chart and proves the
end-to-end path.

## Moved from the ADR on 2026-10-23

### Context (layer descriptions)

Lane B's RBAC pre-creation block in `awx-integration` creates the
`nmos` namespace + `nmos-cpp-launcher` SA + Role + RoleBinding **at
bootstrap**, regardless of whether the function is ever instantiated.
This pattern **conflates** three distinct layers:

1. **Catalog entry** — "NMOS IS-04/05 registry exists in the DMF
   catalog." Metadata. One YAML file.
2. **Installation** — "This DMF cluster has enabled NMOS." Declared
   desired state. Today: implicit (`always`).
3. **Runtime instance** — "NMOS is actually running, with these pods in
   this namespace." Actual workloads.

For the first function, conflation is acceptable debt — there is no
duplication. For the second, the bootstrap-RBAC pattern requires DMF
maintainer intervention in `awx-integration` per function, which fails
the moment 3rd-party media functions become a contribution channel.

ADR-0020 B.3 (cluster-per-tenant, Proposed) already establishes that
multi-tenancy is solved at cluster boundary, not namespace boundary —
which removes the 3rd-party *isolation* dimension but does not remove
the 3rd-party *contribution-friction* dimension that this ADR addresses.

### Decision (reconciler responsibilities)

The reconciler is responsible for:
- Creating the target namespace (with default-deny NetworkPolicy, Pod
  Security Admission `restricted` or `baseline`, ResourceQuota,
  LimitRange — the 3rd-party-safety set GPT-5 enumerated).
- Creating the per-instance ServiceAccount + Role + RoleBinding
  (replacing the bootstrap-layer block that exists today).
- Installing the chart at the version declared in the catalog entry.
- Reconciling drift; cleaning up on CR deletion.
