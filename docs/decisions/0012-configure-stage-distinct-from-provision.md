# ADR-0012: Configure is a distinct lifecycle stage from Provision

**Status:** Accepted
**Date:** 2026-05-04
**Deciders:** @<handle>, planning session with Claude

## Context

EBU's *Dynamic Media Facility Reference Architecture* V2.0 lists six lifecycle stages: Design → Plan
→ **Provision** → **Configure** → Operate → Finalise & Review (white paper Figure 1, p.3). Today
`dmf-infra/k3s-lab-bootstrap/lifecycle-provision.yml` line 1 declares itself as covering "Provision
+ Configure stages," that is, the project has been knowingly conflating the two. For Layers 4–6 a
media function can be *available in the cluster* without being *running and wired*. The catalog
model (ADR-0013) needs the distinction to be load-bearing.

## Decision

Promote Configure to a first-class lifecycle wrapper:
`dmf-infra/k3s-lab-bootstrap/lifecycle-configure.yml`. The semantic split is:

- **Provision:** make artifacts available, register catalog entries with `lifecycle:bootstrapped`,
  leave inactive. Layers 1–3 components also do their full bring-up here (their provision-step *is*
  their configure-step). For Layers 4–6 functions, Provision-side playbooks must NOT launch the
  workload.
- **Configure:** given a catalog entry, launch the workload, set initial connections, flip the
  NetBox tag from `lifecycle:bootstrapped` to `lifecycle:active`. Invoked per-entry, on operator
  action through dmf-cms (or directly via `bin/run-playbook.sh ... lifecycle-configure.yml --tags
  <key>`).

The header comment on `lifecycle-provision.yml` is updated to drop the "+ Configure" claim. The
split applies prospectively to new functions; existing Layer 1–3 + 6 baseline apps retain their
current behaviour (provisioned-and-configured in one pass) until/unless a specific reason to split
them appears.

### Terminology: two configure-stage usages (added 2026-05-19)

The provision/configure/finalise vocabulary appears in two places that are worth distinguishing:

| Usage | Where | Trigger | Transport (as of ADR-0025) |
|---|---|---|---|
| **Bootstrap-configure** | `bootstrap-configure.yml` → 69x playbook chain (`691-netbox-sot`, `692-forgejo-bootstrap`, `693-awx-integration`, etc.) | Operator runs `bin/run-playbook.sh` once per cluster bring-up | In-cluster runner pod (Lane C of the 2026-05-19 plan) |
| **Catalog-launcher-configure** | Per-function `launch-<key>.yml` playbooks in `dmf-runbooks`; per-function provision/configure/finalise tasks in the function's role | Operator triggers via dmf-cms catalog page → AWX JT POST | AWX EE pod in-cluster (Lane B of the 2026-05-19 plan) |

Both share the EBU provision→configure→finalise vocabulary. They differ in
trigger and transport. ADR-0023 §Scope already named the caller-location
distinction; this clarification names the lifecycle-stage distinction in
the same terms. For the unified architecture, see
[`docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`](../plans/DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md).
[ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md)
is the decision record for the unified architecture.

## Consequences

- **Positive:** operator-driven launch (the catalog model) becomes representable in EBU-aligned
  wrapper structure. dmf-cms's Deploy button maps to `lifecycle-configure.yml --tags <entry-key>`.
- **Positive:** symmetry with `lifecycle-finalise.yml`: Configure↔Finalise is the runtime pair;
  Provision↔(no symmetric stage) is the artifact-registration step. The four wrappers now match the
  EBU lifecycle shape minus Design and Plan. Those remain artifact stages: manifests in
  `dmf-env/manifests/` (ADR-0003). They are not playbooks.
- **Positive:** direct probe of thesis-killer #3 (EBU taxonomy survives a hard case). If
  Configure-as-distinct-stage doesn't hold across multiple media functions, that is the falsifying
  evidence.
- **Negative:** playbook authors must place new Layer 4–6 work in the right wrapper. A function
  registered in `lifecycle-provision.yml` when it should have been in `lifecycle-configure.yml` will
  auto-launch during cluster bring-up, defeating the catalog model.
- **Negative:** one more file in the lifecycle root, one more entry in the boot ritual mental model.

### Enforcement

discipline only: no check or test tells a Provision-side playbook from a Configure-side one, so
reviewers catch a Layer 4–6 function registered in the wrong wrapper. ADR-0013 (catalog model) is
the consumer of this split.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0012-configure-stage-distinct-from-provision.md).
