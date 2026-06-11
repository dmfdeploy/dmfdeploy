# Move 1 Gate 2 — AWX Execution Environment Review

> **Outcome 2026-05-06:** the SA-mount route reviewed below was abandoned in
> favour of Path A (control-node SSH via OpenBao, ADR-0016). See
> [`docs/plans/Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md`](../plans/Move%201%20Gate%202%20-%20Pivot%20to%20Path%20A%20for%20Catalog%20Launchers%202026-05-06.md).

**Date:** 2026-05-05
**Reviewer:** Claude (Opus 4.7, umbrella session)
**Scope:** Read-only review of issues 10–15 in
`docs/plans/Move 1 Gate 2 — Trials and Tribulations 2026-05-05.md`. Pairs with
`dmf-move1-gate2-secrets-rollout-review-2026-05-05.md` (secrets/playbook side).
**For:** the agent currently driving Gate 2 — specifically, the agent stuck on
"build a custom EE with the `kubernetes` Python package" (Issue #14) and the
empty-string kubeconfig problem (Issue #15).

This doc is a checkpoint at an architectural fork the agent walked past, not a
verdict on the work so far. The diagnostic chain through issues 10–15 is
genuinely good debugging — but each fix progressively committed the launcher to
an "EE-as-runtime" execution model that is now demanding new infrastructure
(custom image build, Zot push, ServiceAccount RBAC, ExecutionEnvironment
resource registration). Gate 2's purpose — "prove that launching from the AWX
UI deploys NMOS" — does not require any of that. There's a simpler path.

---

## TL;DR

- **Stop building a custom EE for Gate 2.** Restore the SSH-to-control-node
  execution model that every other 69x playbook already uses. AWX becomes the
  orchestrator (which is what it's designed to be); the control node remains
  the runtime (which is where `kubernetes.core.*` already works).
- **Make the `default(omit)` change anyway.** Issue #15's empty-string kubeconfig
  problem has a one-line fix that's portable across every execution model.
- **Don't bundle the `nmos-cpp` role into `dmf-runbooks`.** It creates drift.
  Use `requirements.yml` against the Forgejo `dmf-media` mirror that 692
  already publishes, or make `dmf-media` itself the launcher project.

If you must commit to EE-as-runtime, the work list is in §"Path B" below — but
do that as a Move 2 capability project, not a Gate 2 blocker.

---

## State as of 2026-05-05

| # | Issue | Resolution path taken | Status |
|---|---|---|---|
| 10 | EE can't see other project dirs | Bundled `nmos-cpp` role into `dmf-runbooks` repo | ✅ unblocked, ⚠️ creates drift |
| 11 | NetBox inventory CIDR notation | `primary_ip4.split('/')[0]` in compose | ✅ resolved |
| 12 | Wrong host group | `device_roles_k3s-control-plane[0]` | ✅ resolved |
| 13 | EE can't SSH externally | Added `connection: local` | ⚠️ silently committed to EE-as-runtime |
| 14 | EE missing `kubernetes` Python package | Building a custom EE | ❌ in progress, scope expanding |
| 15 | `kubeconfig: ""` doesn't trigger in-cluster discovery | "Cleared extra_vars" | ❌ misdiagnosed; real fix is `omit` filter |

The pivotal step is Issue #13. Before that fix, the launcher could have been an
SSH-driven play with a Machine credential — the standard AWX pattern. After
that fix, every subsequent issue is a downstream consequence of running k8s
manifests *inside the EE pod*.

---

## The architectural fork the agent walked past

The platform's existing 69x playbook design assumes:

```yaml
- name: <some role>
  hosts: k3s_control[0]    # or k3s-node-01
  become: true             # required to read /etc/rancher/k3s/k3s.yaml
  tasks:
    - kubernetes.core.k8s:
        kubeconfig: /etc/rancher/k3s/k3s.yaml
        ...
```

Every 69x playbook works that way today. `bin/run-playbook.sh` is the operator's
SSH-into-control-node entry point (ADR-0010). AWX is just *another* SSH
orchestrator with a UI on top.

The thin launcher in `dmf-runbooks/playbooks/launch-nmos-cpp.yml` originally
imported the dmf-media configure playbook, which has `hosts: k3s_control[0]`
+ `become: true`. With an AWX Machine credential pointing at the control node,
this would Just Work via the default EE — no kubernetes pip needed (the control
node has it because the wrapper uses it), no kubeconfig acrobatics, no RBAC.

Issue #13's fix ("EE can't SSH to external IP") jumped to `connection: local`,
which makes the EE pod itself the runtime. From there:

- The EE needs `kubernetes` Python package → Issue #14
- The EE needs valid in-cluster auth → Issue #15
- The EE needs RBAC to create resources in `nmos` namespace → not yet hit
- The EE needs the role bundled because it can't see sibling projects → Issue #10

All four fall away if the launcher SSHes to the control node like everything
else in the platform does.

---

## Path A — SSH-to-control-node (recommended for Gate 2)

The shortest path to a passing Gate 2.

### Why this matches the existing architecture

- 69x playbooks already run on the control node with `become: true`
- `kubernetes.core.k8s_*` modules already work there (the control node has
  `kubernetes` pip — that's why `bin/run-playbook.sh` works)
- ADR-0010 already names the control node as the canonical Ansible target
- AWX's whole premise as a tool is "use Ansible against your fleet over SSH";
  using it without SSH credentials is fighting the design

### Concrete steps

1. **Provision an SSH keypair** for `k3s-admin@k3s-node-01` and persist into
   OpenBao at `secret/apps/awx/control_node_ssh` (or similar, follow the
   Secret Ownership plan's `secret/apps/<system>/...` convention).
2. **Add a task to the awx-integration role** (or a new `awx-machine-credential`
   role) that creates an AWX Machine credential populated from that OpenBao path
   — using the same in-cluster `bao kv get | kubectl exec` stdin pattern the
   forgejo-bootstrap role already uses (preserves ADR-0007).
3. **Attach the Machine credential** to the `media-launch-nmos-cpp` and
   `media-finalise-nmos-cpp` job templates. Attach the NetBox inventory.
4. **Revert `connection: local`** in `dmf-runbooks/playbooks/launch-nmos-cpp.yml`
   and `teardown-nmos-cpp.yml`. The play should target
   `device_roles_k3s-control-plane[0]` (NetBox group) or use the existing
   dmf-media `hosts: k3s_control[0]` pattern (depending on how the inventory
   is composed).
5. **Make the `default(omit)` change** in `dmf-media/roles/nmos-cpp/tasks/`
   anyway (see §"Issue #15 — the real fix" below). This is the only one-line
   change that's portable across paths A, B, and C.

### What disappears from the issue list

- #14 — default EE is fine; control node has the kubernetes package
- #15 — `become: true` + a real kubeconfig path on the control node; no
  in-cluster discovery needed
- (Implicit) custom EE build, Zot push, ExecutionEnvironment registration,
  `nmos`-namespace RBAC for an EE service account

### What remains

- The role-bundling-into-dmf-runbooks decision (Issue #10) — see §"Drift" below.
  Path A doesn't *require* the role to be bundled, since the SSH target is the
  control node and `roles_path` works there. But removing the bundle requires
  unwinding what's already been pushed to the Forgejo `dmf-runbooks` repo.

### Estimated effort

1–2 hours for the SSH keypair + OpenBao persistence + AWX Machine credential +
launcher revert. No new container infrastructure.

---

## Path B — Commit to EE-as-runtime (defer to Move 2)

If the platform later wants AWX to genuinely run k8s ops from the EE without
SSH (legitimate goal — closer to GitOps), the work list is:

1. **Custom EE image** built via `ansible-builder`. Dependencies:
   - `python: kubernetes>=28.0.0`
   - `galaxy: kubernetes.core>=3.0.0`
   - Anything else used by media-function configure plays (e.g. `jmespath`)
2. **Build pipeline.** Decide: built locally and pushed manually, or via a
   Forgejo Actions runner, or via dmf-cms/playbook 650-style bake-and-push.
3. **Zot hosting.** Push to the in-cluster Zot at `zot.dmf.example.com` (the
   role already exists). New repo, e.g. `zot.dmf.example.com/dmf/awx-ee:0.1.0`.
4. **ExecutionEnvironment resource** created in AWX via `ansible.builtin.uri`
   POSTs in the awx-integration role (just like the project/credential/template
   creation already there).
5. **ServiceAccount + Role + RoleBinding** for the EE pod, granting:
   - `create/get/patch/delete` on `pods`, `services`, `deployments`,
     `statefulsets`, `pvcs`, `configmaps` in `nmos` namespace
   - Probably need a `ClusterRole` if media functions span namespaces, or a
     pattern of one Role per media-function namespace
6. **AWX-operator pod template** to inject that ServiceAccount into ephemeral
   EE pods. May require a Custom Resource patch or operator config — verify
   against awx-operator 3.2.x docs.
7. **`default(omit)`** in the role tasks (see §"Issue #15 — the real fix").
   This is mandatory for in-cluster auth; empty-string kubeconfig will not
   trigger discovery.

This is a real chunk of new infrastructure. Probably worth its own ADR
("AWX EE images are built via ansible-builder, hosted in Zot, attached
per-job-template via OpenBao-driven creation"). Not a Gate 2 deliverable.

### Why "use the awx-task pod" doesn't help

The trials doc Issue #14 investigation noted that the awx-task pod has the
same `ModuleNotFoundError` for `kubernetes`. Setting
`run_in_control_plane: true` on a job template (so it runs in the awx-task
pod instead of an ephemeral EE pod) does not solve the missing-package problem.

---

## Path C — kubectl shell-out (escape hatch only)

If both Path A and Path B are blocked for non-technical reasons:

```yaml
- name: Apply registry StatefulSet
  ansible.builtin.shell:
    cmd: kubectl apply -f -
  args:
    stdin: "{{ statefulset_definition | to_yaml }}"
  environment:
    KUBECONFIG: ""
```

The default EE has `kubectl`. No pip dependency. Loses idempotency-by-diff (the
k8s module's `state: present` is smarter than `kubectl apply`), and you write
more YAML-rendering boilerplate. Acceptable as a temporary unblock; not a long-
term home for the role.

Don't ship this. Mention it only because the trials doc Issue #14 named it as
an alternative and dismissed it correctly.

---

## Issue #15 — the real fix (do this regardless of path)

The trials doc Issue #15 lesson:

> "The kubernetes Python client auto-discovers in-cluster auth only when no
> kubeconfig is specified at all. Ansible variable defaults still pass a value."

This is correct as observation but missed the canonical fix. The Ansible `omit`
filter is exactly the magic value that makes a parameter *absent* (not
empty-string, not null — *gone*):

```yaml
kubernetes.core.k8s:
  kubeconfig: "{{ kubeconfig | default(omit) }}"
  state: present
  definition: ...
```

Behavior:

- **Path A (control node, kubeconfig set in inventory):** `kubeconfig` →
  `/etc/rancher/k3s/k3s.yaml` (or wherever inventory points). Works as today.
- **Path B (EE pod, no `kubeconfig` extra_var):** parameter omitted →
  kubernetes client falls through to `KUBECONFIG` env → `~/.kube/config` →
  in-cluster ServiceAccount token (the one you want).
- **Path C (kubectl shell-out):** N/A, but the env-var pattern still applies.

**Action:** in `dmf-media/roles/nmos-cpp/tasks/configure.yml`,
`provision.yml`, and `finalise.yml`, replace every

```
kubeconfig: "{{ kubeconfig | default('/etc/rancher/k3s/k3s.yaml') }}"
```

with

```
kubeconfig: "{{ kubeconfig | default(omit) }}"
```

The trials doc's note that "the role conditional on kubeconfig being set" was
heading the right direction; `default(omit)` is the idiom that does it.

---

## Drift — the role-bundling decision (Issue #10)

Bundling `nmos-cpp` into the Forgejo `dmf-runbooks` repo creates two source-of-
truth copies:

- `dmf-media/roles/nmos-cpp/` (the canonical home, also what 410-nmos-cpp-provision.yml imports)
- `dmf-runbooks/playbooks/roles/nmos-cpp/` (the bundled copy, EE-visible)

Drift is inevitable. The next time someone updates the role for a config-stage
fix, only one of the two copies will get the change. The other will silently
regress, but only when running through AWX (which is the path that *should* be
the most production-aligned of all the launchers).

Two ways to fix:

### Option 1 — `requirements.yml` (cleanest)

The `dmf-runbooks/playbooks/` directory already contains thin import wrappers.
Add a `requirements.yml` at repo root:

```yaml
roles:
  - src: https://forgejo.dmf.example.com/forgejo-svc/dmf-media.git
    scm: git
    name: nmos-cpp
    version: main
```

AWX runs `ansible-galaxy install -r requirements.yml` automatically on project
sync (when "Update Revision on Launch" is enabled). The role is pulled at
project-sync time from the Forgejo mirror that 692-forgejo-bootstrap already
publishes.

### Option 2 — make dmf-media the launcher project

Drop `dmf-runbooks` as a project type entirely. Add the thin launcher playbooks
directly to `dmf-media/playbooks/runbooks/` (they're already there, in
fact: `k3s-lab-bootstrap/playbooks/runbooks/media-launch-nmos-cpp.yml`). Point
the AWX job template at the `dmf-media` project and the playbook at
`playbooks/runbooks/media-launch-nmos-cpp.yml`.

This collapses ADR-0014's "AWX project layout" simplification: one project per
domain repo, no separate launcher project needed for media functions. Worth
revisiting ADR-0014 if you go this way.

---

## Concerns about the current trajectory

1. **The trials doc is becoming an architectural decision log without an ADR.**
   Issue #14's "build a custom EE" decision is a platform-shaping commitment.
   Promote it out of a session log into either an ADR or a deferred-to-Move-2
   plan doc.

2. **Issue #13's fix should be revisited.** The lesson "AWX EEs run inside the
   cluster and can only reach cluster-internal endpoints" is true *if you don't
   give them an SSH credential*. With a Machine credential, the EE has the
   private key and can SSH out. The trials doc framed this as an EE limitation;
   it's actually an "AWX hasn't been told how to authenticate" problem.

3. **The trials doc summary table has drifted again.** The 7-vs-8 cluster-ready
   tasks discrepancy from the previous review is still there. The new entries
   (10–15) match the diff better, but the historical narrative still claims 8.

4. **No verification proof that any of issues 10–15's "✅" fixes survived
   into a green Gate 2.** The trials doc shows fixes-applied; the Gate 2 plan's
   success criteria (lines 261–274 of `Move 1 Gate 2 — AWX Integration + Launch
   NMOS.md`) are still unchecked. Worth deciding what "done" means before
   committing more design effort.

---

## Suggested order of operations

1. **Decision point:** Path A or Path B for Gate 2. Recommend A.
2. **Universal change (free):** apply `default(omit)` to all `kubeconfig`
   parameters in `dmf-media/roles/nmos-cpp/tasks/*.yml`. One-line per call
   site, portable across every path, never wrong.
3. **If Path A:**
   - Provision SSH keypair → OpenBao
   - Add AWX Machine credential creation task to awx-integration role
   - Revert `connection: local` in dmf-runbooks launcher playbooks
   - Decide drift fix (`requirements.yml` or collapse into dmf-media project)
   - Re-run 693, then launch from AWX UI, capture PLAY RECAP
4. **If Path B:**
   - Open a new ADR ("AWX EE images and registry")
   - Stand up ansible-builder workflow + Zot push
   - Add ExecutionEnvironment + ServiceAccount + RBAC tasks to awx-integration
     role
   - This is Move 2 scope; do not block Gate 2 on it
5. **Closure:** append a "10. Closure" section to the trials doc with the
   PLAY RECAP, NetBox tag flip query result, and `kubectl get all -n nmos`
   output proving Gate 2 success criteria.

---

## References

- Trials doc: `docs/plans/Move 1 Gate 2 — Trials and Tribulations 2026-05-05.md`
- Gate plan: `docs/plans/Move 1 Gate 2 — AWX Integration + Launch NMOS.md`
- Companion review: `docs/reviews/dmf-move1-gate2-secrets-rollout-review-2026-05-05.md`
- ADR-0007 (secrets in argv/env/tmp/transcripts): `docs/decisions/0007-secrets-never-in-argv.md`
- ADR-0008 (OpenBao + ESO): `docs/decisions/0008-openbao-secrets-architecture.md`
- ADR-0010 (`bin/run-playbook.sh` is the sanctioned entry): `docs/decisions/0010-run-playbook-as-sanctioned-entry.md`
- ADR-0012 (configure vs provision): `docs/decisions/0012-configure-stage-distinct-from-provision.md`
- ADR-0014 (AWX project layout): `docs/decisions/0014-awx-project-layout.md`
- Secret Ownership plan: `docs/plans/DMF Secret Ownership and OpenBao Migration Plan.md`
- nmos-cpp role: `dmf-media/roles/nmos-cpp/tasks/configure.yml`
- AWX instance template: `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx/templates/awx-instance.yml.j2`
- awx-integration role: `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml`
- Existing dmf-runbooks launcher: `dmf-runbooks/playbooks/launch-nmos-cpp.yml`
