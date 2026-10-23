# ADR-0012 archive: Configure is a distinct lifecycle stage from Provision

This file holds material moved out of [ADR-0012](../../decisions/0012-configure-stage-distinct-from-provision.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

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

## Implementation note (2026-05-06)

The first implementation attempted to give the AWX EE pod in-cluster
auth via a mounted `awx-ee` ServiceAccount (so `kubernetes.core.k8s`
in the catalog launcher could call the API directly). This proved
fragile across five coupled layers (custom EE image, SA + RBAC,
`InstanceGroup.pod_spec_override` serialization, JT execution-environment
wiring, K8S_AUTH_* env plumbing) — see commit log
`f669415`..`e8bc0f4` in `dmf-runbooks` for ~20 iterative fixes that
never converged. Independent architecture review in
[`docs/plans/Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md`](../../plans/Move%201%20Gate%202%20-%20Pivot%20to%20Path%20A%20for%20Catalog%20Launchers%202026-05-06.md)
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

**Console label.** The operator-facing console calls that combined launch
action **Provision**: one action dispatches the merged Provision+Configure
job. Configure remains the distinct EBU lifecycle stage at the role and
playbook level beneath that operator-facing action.

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

## Moved from the ADR on 2026-10-23

### Context (full text)

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

### Plan and ADR-0025 pointer from the terminology section

**See:**
[`docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`](../../plans/DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md)
for the unified architecture; [ADR-0025](../../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md)
for the decision record.

Implementation detail: see the [archive record](0012-configure-stage-distinct-from-provision.md).

### Enforcement section as it stood

ADR-0013 (catalog model) is the consumer of this split. The Move 1 task
spec (`docs/plans/dmf-platform-move-1-task.md`) implements
the first `lifecycle-configure.yml` and the first per-function Configure
+ Finalise playbook pair. If during Move 1 the split feels artificial
for nmos-cpp, the failure is a signal to reshape this ADR rather than
fudge the implementation.
