# ADR-0016: AWX↔control-node SSH via cloud-init pubkey + OpenBao privkey (Path A)

> **⚠️ Canonical truth for this topic is consolidated in the
> [Catalog and execution digest](digests/catalog-and-execution.md).** This ADR's status: **partially superseded by ADR-0025** (canonical for `media-*` JTs; still authoritative for AWX→infra plays).
> Full text preserved below for decision history — do not act on it without
> reading the digest + the named successor.

**Status:** Partially superseded by ADR-0025 (canonical for `media-*` JTs; still authoritative for AWX→infrastructure plays)
**Date:** 2026-05-05
**Deciders:** @<handle>
**Partially superseded by:** [ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md) —
catalog/`media-*` job templates move to in-cluster Helm; this ADR (Path A) remains
canonical for AWX-to-infrastructure plays.

## Context

AWX needs a way to drive Ansible playbooks against the DMF cluster's control
node (`k3s-node-01`) so that catalog job templates like `media-launch-nmos-cpp`
can stand up media functions on demand. Two execution models were considered
during Move 1 Gate 2 (see `docs/plans/Move 1 Gate 2 — Trials and Tribulations
2026-05-05.md`):

1. **EE-as-runtime** — the AWX Execution Environment pod runs the playbook
   itself with `connection: local` and talks to the Kubernetes API directly.
   Requires custom EE image (kubernetes Python pkg + collection), in-cluster
   ServiceAccount with namespace-scoped RBAC, and an ExecutionEnvironment
   resource registered in AWX.
2. **AWX-as-orchestrator** — AWX uses a Machine credential to SSH into the
   control node, where the same `kubernetes.core.*` modules already work via
   `/etc/rancher/k3s/k3s.yaml`. Matches every other 69x playbook's execution
   model (which `bin/run-playbook.sh` already drives that way).

The Gate 2 spike attempted (1) under `connection: local`, hit a string of
issues (custom EE not available, in-cluster auth requires `default(omit)`,
ServiceAccount RBAC absent), then attempted (2) but produced an ADR-0007
violation: a real ed25519 private key was committed in plaintext to
`awx-integration/defaults/main.yml` "for Gate 2 spike." The incident is
documented in
`docs/reviews/dmf-move1-gate2-ssh-credential-incident-2026-05-05.md` and
triggered a complete cluster redeploy (Path Y).

After redeploy, the question of which execution model AWX should use must be
answered with a sanctioned mechanism, not another spike.

## Decision

**AWX drives Ansible against the DMF cluster via SSH-to-control-node, using a
Machine credential whose public half is provisioned by Layer-1 cloud-init and
whose private half lives in OpenBao at `secret/apps/awx/control_node_ssh`.**

Concrete plumbing:

1. **Public key in cloud-init.** `dmf-env/terraform/modules/hetzner-cluster/`
   exposes a Terraform variable `awx_control_node_ssh_pubkey`. The user-data
   template (`templates/user-data.yml.tftpl`) renders this as a second entry in
   `users[0].ssh_authorized_keys` for `${admin_user}` (alongside the operator's
   pubkey). Adding/rotating the AWX pubkey requires a `tofu apply`, not an
   Ansible role edit.
2. **Private key in OpenBao.** Stored at `secret/apps/awx/control_node_ssh`
   with key `ssh_key_data` (canonical AWX field name). Persisted via the
   standard `printf '%s\n…' | kubectl exec -i <openbao-pod> -- sh -c 'IFS=
   read -r X; bao kv put …'` pattern (matches `forgejo-bootstrap/tasks/main.yml`).
3. **AWX Machine credential.** `awx-integration` role reads the privkey from
   OpenBao using the same `bao kv get` pattern that already exists for the
   Forgejo svc token, then creates the AWX Machine credential via
   `ansible.builtin.uri` POST against `awx_external_base_url`. The credential
   is attached to all catalog job templates (`awx_catalog_job_templates`).
4. **Launcher playbooks** target `device_roles_k3s-control-plane[0]` from the
   NetBox inventory (resolves to the control node's reachable IP), with
   `become: true`. **No `connection: local`.** No `default(omit)` games — the
   plays run on the control node where `/etc/rancher/k3s/k3s.yaml` works
   normally with `become: true`.

**EE-as-runtime is explicitly deferred.** If the platform later wants AWX to
run k8s ops from the EE pod without SSH (e.g., for GitOps alignment), a
custom EE + RBAC stack can be added as a Move 2 capability project. That work
is its own ADR.

## Consequences

- **Positive** — the launcher inherits the existing 69x execution model. No
  custom EE build, no in-cluster RBAC for an EE service account, no
  `default(omit)` portability concerns, no per-task `become: true` debate.
  Default `quay.io/ansible/awx-ee:latest` is sufficient.
- **Positive** — both halves of the keypair have a sanctioned home outside
  tracked code: pubkey in Terraform variable + cloud-init, privkey in OpenBao.
  No path through which an agent can "spike" by embedding either half in a
  defaults file.
- **Positive** — pubkey rotation is a single-source operation: change the
  Terraform variable, `tofu apply`, cloud-init re-applies. Privkey rotation is
  a single OpenBao write + a credential PATCH against AWX.
- **Negative** — three secret-handling layers must be kept in sync (Terraform
  var, OpenBao path, AWX credential). Drift between any two is a possible
  failure mode. Mitigated by the awx-integration role being the single place
  that reads OpenBao and PATCHes AWX.
- **Negative** — first-bootstrap chicken-and-egg: the AWX credential cannot
  be created until OpenBao has the privkey, which cannot be written until
  OpenBao is unsealed and the operator has authenticated. The standard
  `bin/run-playbook.sh` flow already handles this ordering (OpenBao before
  AWX), so the addition is just one more KV path in the existing chain.
- **Neutral** — relies on AWX being able to reach the control node's IP from
  inside the cluster. The NetBox inventory's
  `device_roles_k3s-control-plane` group must resolve to a reachable IP
  (private/internal, not a Hetzner public IP that the EE pod cannot egress
  to). Verified during Phase 9 of the redeploy.

## Alternatives considered

- **EE-as-runtime with custom EE.** Closer to native AWX-on-Kubernetes and
  GitOps patterns. Defers to a future ADR: requires `ansible-builder` workflow,
  Zot hosting, ExecutionEnvironment resource, ServiceAccount + RoleBinding,
  awx-operator config to inject the SA into ephemeral EE pods, and
  `kubeconfig: "{{ kubeconfig | default(omit) }}"` plumbing in every k8s
  task. Substantially more infrastructure than Path A; the right answer when
  the platform has more than one media function in production but overkill
  for the experiment phase (ADR-0004).
- **kubectl shell-out.** Replace `kubernetes.core.k8s` with `command: kubectl
  apply -f -` in role tasks. Default EE has `kubectl`; no Python package
  needed. Loses idempotency-by-diff and adds YAML-rendering boilerplate.
  Acceptable as an emergency unblock, not a sustained pattern.
- **Embed private key in role defaults "for Gate 2 spike."** Tried during the
  incident. Violates ADR-0007 §1, leaks via tracked file in a public repo,
  and requires a complete cluster redeploy to remediate. Not an alternative;
  a cautionary example.

## Enforcement

- **`awx-integration` role** is the single place that reads
  `secret/apps/awx/control_node_ssh` and creates the AWX Machine credential.
  Drift between the pubkey in cloud-init and the privkey in OpenBao manifests
  as authentication failures during 693 runs — visible, not silent.
- **Pre-commit hook** (to be added per the incident review's process gates)
  blocks commits whose staged diff contains PEM markers. Any agent attempting
  to revert to "embed key in defaults" hits the hook before `git commit`
  succeeds.
- **§0 Secrets Discipline** of `dmf-cluster-access` and the new
  `dmf-awx-credentials` skill (to be written) names this ADR as the canonical
  mechanism for AWX SSH credentials.
- **No automated check** that the AWX EE actually uses SSH (vs. accidentally
  reverting to `connection: local`). Discipline + launcher-playbook review at
  PR time.

## References

- Incident review:
  `docs/reviews/dmf-move1-gate2-ssh-credential-incident-2026-05-05.md`
- AWX EE review:
  `docs/reviews/dmf-move1-gate2-awx-ee-review-2026-05-05.md`
- Trials doc: `docs/plans/Move 1 Gate 2 — Trials and Tribulations 2026-05-05.md`
- ADR-0007 (secrets never in argv/env/tmp/transcripts)
- ADR-0008 (OpenBao + ESO + AppRole shim)
- ADR-0010 (`bin/run-playbook.sh` is the sanctioned entry)
- ADR-0014 (AWX project layout)
- Cloud-init template: `dmf-env/terraform/modules/hetzner-cluster/templates/user-data.yml.tftpl`
- Reference impl for stdin secret transport: `dmf-env/bin/unseal-openbao.sh`
- Reference impl for OpenBao read pattern:
  `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/main.yml`
  (lines around 467–522, 230–261)

## Amendments

### 2026-05-23 — Fully superseded for media catalog launchers (ADR-0025)

Fully superseded for `media-*` JTs (ADR-0025 Accepted 2026-05-23).
All catalog launchers now execute in-cluster via the AWX EE pod.
SSH-to-control-node remains canonical for 693-class infra plays only.
The Lane B band-aid at `launch-nmos-cpp.yml:28-34` (Hetzner-only private-IP
`set_fact`) is removed.

### 2026-05-19 — Partially superseded for media catalog launchers (ADR-0025)

**Scope of supersession:** AWX Job Templates whose name matches `media-*`
(e.g. `media-launch-nmos-cpp`, `media-finalise-nmos-cpp`).

**What changes:** §Decision item 4 (`Launcher playbooks target
device_roles_k3s-control-plane[0] from the NetBox inventory ... with
become: true`) no longer applies to media JTs. Those JTs now run in an
AWX Execution Environment pod inside the cluster, using a custom EE image
hosted in cluster-internal Zot, and deploy workloads via Helm charts
rather than `kubernetes.core.k8s` over SSH.

**What stays:** Path A remains canonical for **AWX → infrastructure
plays** — the 693-class playbooks (`awx-integration`,
`netbox-sot`, `forgejo-bootstrap`, etc.) that target the control node
directly via the NetBox-supplied inventory. The Machine credential, the
cloud-init pubkey wiring, and the OpenBao privkey storage all remain in
place and continue to be used by those plays.

**Reason:** the first media-launcher run on `aliyun-123` (AWX job 44,
2026-05-17) failed with `UNREACHABLE!` because
`dmf-runbooks/playbooks/launch-nmos-cpp.yml:28-34` hardcoded the Hetzner
private subnet (`10.0.0.4/3/2`); aliyun-123's private subnet is
`10.0.0.40-42`. The `ansible_host` remap is a symptom — the deeper issue
is that the launcher is using SSH-to-control-node for a workload that
has nothing node-local about it. Each new env adds another per-env band-aid
unless the SSH hop is removed for this class of work.

**See:** [ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md) and
the convergence plan
[`docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`](../plans/DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md).
