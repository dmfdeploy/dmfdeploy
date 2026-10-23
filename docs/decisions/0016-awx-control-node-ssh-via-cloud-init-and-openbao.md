# ADR-0016: AWX↔control-node SSH via cloud-init pubkey + OpenBao privkey (Path A)

> **⚠️ Canonical truth for this topic is in
> [ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md).** This ADR's status: **partially superseded by ADR-0025** (canonical for `media-*` JTs; still authoritative for AWX→infra plays).
> Full text is preserved in the [archive record](../archive/decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md) for decision
> history. Do not act on it without reading the canonical ADR and the named successor.

**Status:** Partially superseded by ADR-0025 (canonical for `media-*` JTs; still authoritative for AWX→infrastructure plays)
**Date:** 2026-05-05
**Deciders:** @<handle>
**Partially superseded by:** [ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md).
Catalog/`media-*` job templates move to in-cluster Helm. This ADR (Path A) remains
canonical for AWX-to-infrastructure plays.

## Context

AWX needs a way to drive Ansible playbooks against the DMF cluster's control node (`k3s-node-01`) so that catalog job
templates like `media-launch-nmos-cpp` can stand up media functions on demand. Two execution models were considered
during Move 1 Gate 2. In EE-as-runtime, the AWX EE pod runs the playbook with `connection: local`; it requires a custom
EE image, an in-cluster ServiceAccount with namespace-scoped RBAC, and an ExecutionEnvironment resource in AWX. In
AWX-as-orchestrator, AWX SSHes into the control node with a Machine credential, the model every 69x playbook already
uses. After redeploy, the choice needs a sanctioned
mechanism. Another spike is not one. Evidence: see the
[archive record](../archive/decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md).

## Decision

**AWX drives Ansible against the DMF cluster via SSH-to-control-node, using a Machine credential whose public half is
provisioned by Layer-1 cloud-init and whose private half lives in OpenBao at `secret/apps/awx/control_node_ssh`.**

1. **Public key in cloud-init.** `dmf-env/terraform/modules/hetzner/cluster/` exposes a Terraform variable
   `awx_control_node_ssh_pubkey_path` (the public key file), rendered as a second entry in
   `users[0].ssh_authorized_keys` for `${admin_user}`.
   Changing it requires a `tofu apply`. An Ansible role edit does not do it.
2. **Private key in OpenBao**, key `ssh_key_data` (canonical AWX field name).
3. **AWX Machine credential.** The `awx-integration` role creates it from the OpenBao privkey and attaches it to all
   catalog job templates.
4. **Launcher playbooks** target `device_roles_k3s-control-plane[0]` from the NetBox inventory, with `become: true`.
   **No `connection: local`.** No `default(omit)` games.

**EE-as-runtime is explicitly deferred.** If the platform later wants AWX to run k8s ops from the EE pod without SSH,
a custom EE + RBAC stack can be added as a Move 2 capability project. That work is its own ADR.

### Amendments

- **2026-05-23, fully superseded for `media-*` JTs (ADR-0025 Accepted 2026-05-23).** All catalog launchers now execute
  in-cluster via the AWX EE pod. SSH-to-control-node remains canonical for 693-class infra plays only.
- **2026-05-19, partially superseded for media catalog launchers (ADR-0025).** Scope: AWX Job Templates whose name
  matches `media-*`. Decision item 4 no longer applies to them; they run in an in-cluster AWX EE pod and deploy via
  Helm. Path A remains canonical for **AWX → infrastructure plays** (693-class playbooks). The Machine credential,
  cloud-init pubkey wiring, and OpenBao privkey storage stay in place for those plays.

**See:** [ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md) and the convergence plan
[`docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`](../plans/DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md).

## Consequences

- **Positive:** both key halves have a sanctioned home outside tracked code, so no agent can "spike" by embedding
  either in a defaults file.
- **Negative:** three secret-handling layers (Terraform var, OpenBao path, AWX credential) must be kept in sync. Drift
  between any two is a possible failure mode. The awx-integration role is the single place that reads the privkey for
  AWX and PATCHes AWX, which mitigates it.
- **Negative:** the AWX credential cannot be created until OpenBao is unsealed and holds the privkey.
  `bin/run-playbook.sh` orders OpenBao before AWX.
- **Neutral:** AWX must reach the control node's IP from inside the cluster. The `device_roles_k3s-control-plane`
  group must resolve to a private or internal IP. A public IP the EE pod cannot egress to does not work.

### Enforcement

- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml` is the only place that creates the
  AWX Machine credential, from `secret/apps/awx/control_node_ssh`. `dmf-env/bin/bootstrap-secrets.sh` writes the
  privkey to that path, and the role can also write it from `awx_control_node_ssh_privkey_path`. Drift between the
  cloud-init pubkey and the OpenBao privkey shows up as authentication failures during 693 runs, so it is visible. It
  does not fail silently.
- `dmf-infra/.githooks/pre-commit` runs gitleaks, whose default rules catch private keys, when gitleaks is installed.
- Discipline only: nothing mechanical checks that the AWX EE uses SSH instead of `connection: local`.
  Launcher-playbook review at PR time is the check.

## Status

Partially superseded by ADR-0025 (canonical for `media-*` JTs; still authoritative for AWX→infrastructure plays)

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md).
