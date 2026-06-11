# ADR-0012: Configure is a distinct lifecycle stage from Provision

**Status:** Accepted
**Date:** 2026-05-04
**Deciders:** @<handle>, planning session with Claude

## Context

EBU's *Dynamic Media Facility Reference Architecture* V2.0 lists six
lifecycle stages: Design → Plan → **Provision** → **Configure** → Operate
→ Finalise & Review (white paper Figure 1, p.3). Today
`dmf-infra/k3s-lab-bootstrap/lifecycle-provision.yml` line 1 declares
itself as covering "Provision + Configure stages" — i.e. the project has
been knowingly conflating the two. For Layers 1–3 (Infrastructure, Host
Platform, Container Platform) the conflation is harmless: provisioning
k3s and configuring k3s happen in the same Ansible task graph. For
Layers 4–6 (Media Exchange, Media Functions, Application & UI) the
conflation breaks down: a media function can be *available in the
cluster* (image cached, chart present, role available, manifest
registered) without being *running and wired*. EBU Figure 4 puts these
in distinct PROVISION and CONFIGURE columns. The catalog model (ADR-0013)
needs the distinction to be load-bearing.

## Decision

Promote Configure to a first-class lifecycle wrapper:
`dmf-infra/k3s-lab-bootstrap/lifecycle-configure.yml`. The semantic
split is:

- **Provision** — make artifacts available, register catalog entries
  with `lifecycle:bootstrapped`, leave inactive. Layers 1–3 components
  also do their full bring-up here (their provision-step *is* their
  configure-step). For Layers 4–6 functions, Provision-side playbooks
  must NOT launch the workload.
- **Configure** — given a catalog entry, launch the workload, set
  initial connections, flip the NetBox tag from `lifecycle:bootstrapped`
  to `lifecycle:active`. Invoked per-entry, on operator action through
  dmf-cms (or directly via `bin/run-playbook.sh ... lifecycle-configure.yml
  --tags <key>`).

The header comment on `lifecycle-provision.yml` is updated to drop the
"+ Configure" claim. The split applies prospectively to new functions;
existing Layer 1–3 + 6 baseline apps retain their current behaviour
(provisioned-and-configured in one pass) until/unless a specific reason
to split them appears.

## Consequences

- **Positive** — operator-driven launch (the catalog model) becomes
  representable in EBU-aligned wrapper structure. dmf-cms's Deploy
  button maps to `lifecycle-configure.yml --tags <entry-key>`.
- **Positive** — symmetry with `lifecycle-finalise.yml`: Configure↔Finalise
  is the runtime pair; Provision↔(no symmetric stage) is the artifact-
  registration step. The four wrappers now match the EBU lifecycle
  shape minus Design and Plan (which remain artifact stages — manifests
  in `dmf-env/manifests/`, not playbooks; ADR-0003).
- **Positive** — direct probe of thesis-killer #3 (EBU taxonomy survives
  a hard case): if Configure-as-distinct-stage doesn't hold across
  multiple media functions, that's the falsifying evidence.
- **Negative** — playbook authors must place new Layer 4–6 work in the
  right wrapper. A function registered in `lifecycle-provision.yml`
  when it should have been in `lifecycle-configure.yml` will auto-launch
  during cluster bring-up, defeating the catalog model.
- **Negative** — one more file in the lifecycle root, one more entry
  in the boot ritual mental model.

## Alternatives considered

- **Keep collapsed in `lifecycle-provision.yml`, gate launch via Ansible
  vars** (e.g. `nmos_cpp_enabled: false`). Rejected — pushes the launch
  decision into Ansible variable management, which is harder for dmf-cms
  to drive than a tag-scoped playbook invocation, and obscures the
  EBU lifecycle distinction.
- **No wrapper for Configure — dmf-cms calls per-function playbooks
  directly via AWX**. Rejected — bypasses the lifecycle vocabulary
  ADR-0003 committed to and creates a parallel orchestration surface
  that doesn't match the rest of the platform.

## Enforcement

ADR-0013 (catalog model) is the consumer of this split. The Move 1 task
spec (`docs/plans/dmf-platform-move-1-task-2026-05-04.md`) implements
the first `lifecycle-configure.yml` and the first per-function Configure
+ Finalise playbook pair. If during Move 1 the split feels artificial
for nmos-cpp, the failure is a signal to reshape this ADR rather than
fudge the implementation.

## Implementation note (2026-05-06)

The first implementation attempted to give the AWX EE pod in-cluster
auth via a mounted `awx-ee` ServiceAccount (so `kubernetes.core.k8s`
in the catalog launcher could call the API directly). This proved
fragile across five coupled layers (custom EE image, SA + RBAC,
`InstanceGroup.pod_spec_override` serialization, JT execution-environment
wiring, K8S_AUTH_* env plumbing) — see commit log
`f669415`..`e8bc0f4` in `dmf-runbooks` for ~20 iterative fixes that
never converged. Independent architecture review in
[`docs/plans/Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md`](../plans/Move%201%20Gate%202%20-%20Pivot%20to%20Path%20A%20for%20Catalog%20Launchers%202026-05-06.md)
recommended pivoting catalog launchers to ADR-0016's Path A
(SSH-via-control-node + `become: true` + `KUBECONFIG=/etc/rancher/k3s/k3s.yaml`) —
the same execution model already used for Layer-1..3 layer playbooks.

**This ADR is unchanged.** The decision (Configure-vs-Provision stage
split, per-function Configure + Finalise launcher pair, NetBox tag flip
`lifecycle:bootstrapped` ↔ `lifecycle:active`) survived contact with the
experiment intact. Only the *auth-mechanism implementation detail*
changed: catalog launchers now SSH to the control node and
`kubernetes.core.k8s` reads `/etc/rancher/k3s/k3s.yaml` natively under
become, instead of relying on a SA token mount inside the EE pod.

Note also that the launcher merges Provision and Configure stages into
a single AWX job (`media-launch-nmos-cpp`) for operator ergonomics. The
*role-level* split (`provision.yml`, `configure.yml`, `finalise.yml`)
is preserved, idempotent, and is what defends the ADR-0012 decision.

The in-cluster SA approach remains valid architecture for a mature
K8s-native AWX deployment; it is preserved as deferred capability in
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/`
and `roles/stack/operator/awx/templates/awx-instance.yml.j2`. Trigger
for revisiting it would be a catalog playbook that *must* run in-cluster
for latency / network / blast-radius reasons.

Job 285 (`media-launch-nmos-cpp`, commit `e86ae24` of `dmf-runbooks`)
was the first end-to-end success of the pivot: NetBox catalog tag
taxonomy auto-created, `ipam.Service` registered with parent
`dmf-traefik` device, K8s namespace + ConfigMaps + PVC + StatefulSet +
Deployments + Services applied, NetBox tag flipped to `lifecycle:active`.
That confirms ADR-0012 is implementable; further catalog functions
can follow the same shape.

## Terminology — two configure-stage usages (added 2026-05-19)

The provision/configure/finalise vocabulary appears in two places that are
worth distinguishing:

| Usage | Where | Trigger | Transport (as of ADR-0025) |
|---|---|---|---|
| **Bootstrap-configure** | `bootstrap-configure.yml` → 69x playbook chain (`691-netbox-sot`, `692-forgejo-bootstrap`, `693-awx-integration`, etc.) | Operator runs `bin/run-playbook.sh` once per cluster bring-up | In-cluster runner pod (Lane C of the 2026-05-19 plan) |
| **Catalog-launcher-configure** | Per-function `launch-<key>.yml` playbooks in `dmf-runbooks`; per-function provision/configure/finalise tasks in the function's role | Operator triggers via dmf-cms catalog page → AWX JT POST | AWX EE pod in-cluster (Lane B of the 2026-05-19 plan) |

Both share the EBU provision→configure→finalise vocabulary. They differ in
trigger and transport. ADR-0023 §Scope already named the caller-location
distinction; this clarification names the lifecycle-stage distinction in
the same terms.

**See:**
[`docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`](../plans/DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md)
for the unified architecture; [ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md)
for the decision record.
