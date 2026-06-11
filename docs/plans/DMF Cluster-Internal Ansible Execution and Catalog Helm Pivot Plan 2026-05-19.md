---
status: active
date: 2026-05-19
---
# DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan
> Supersedes: [DMF In-Cluster Ansible Runner Pod Implementation Plan 2026-05-14.md](DMF%20In-Cluster%20Ansible%20Runner%20Pod%20Implementation%20Plan%202026-05-14.md), [Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md](Move%201%20Gate%202%20-%20Pivot%20to%20Path%20A%20for%20Catalog%20Launchers%202026-05-06.md)

**Date:** 2026-05-19
**Investigator:** Claude (Opus 4.7) + operator
**Scope:** consolidates two prior workstreams — the *In-Cluster Ansible Runner Pod* (plan 2026-05-14, Phases 2–4 pending) and the *NMOS Helm + EE-as-runtime pivot* (first-cut draft 2026-05-19, superseded by this plan) — into a single architectural shift. Touches `dmf-runbooks`, `dmf-media`, `dmf-infra`, `dmf-env`, and the umbrella docs tree.

**Status:** Active parent plan. Lane A landed; Lane B ✅ landed 2026-05-23 and ADR-0025 is Accepted; Lane C remains in flight. ADR-0016 is fully superseded for media catalog launchers and remains canonical for 693-class infrastructure plays.

---

## §1 Trigger

On **2026-05-17** the first AWX-driven `media-launch-nmos-cpp` job on `aliyun-123` failed at the second task with `UNREACHABLE!`. AWX job 44 stdout:

```
TASK [Set ansible_host to node private IP (Hetzner firewall workaround)] *******
ok: [k3s-node-01 -> localhost]

TASK [nmos-cpp : Fetch existing NetBox tags …] ***
fatal: [k3s-node-01]: UNREACHABLE!
```

**Root cause:** `dmf-runbooks/playbooks/launch-nmos-cpp.yml:28-34` hardcodes the Hetzner private subnet (`10.0.0.4 / 10.0.0.3 / 10.0.0.2`). On `aliyun-123` the real private IPs are `10.0.0.42 / 10.0.0.41 / 10.0.0.40`. The set_fact rewrote `ansible_host` to a non-existent IP; the SSH dial in the next task hung at the connection layer.

**Deeper cause:** the launcher uses SSH-to-control-node (Path A, ADR-0016) to deploy what is structurally a Helm-chart-shaped workload (StatefulSet + N Deployments + Services + PVC + ConfigMaps). Nothing about the workload is node-local; `kubernetes.core.k8s` inside `roles/nmos-cpp/tasks/configure.yml:7-214` is talking to localhost-on-control-node, which talks to the in-cluster k8s API anyway. The SSH hop is purely orchestrational — and the per-env `ansible_host` band-aid is a symptom of that hop existing at all.

**Parallel observation:** a separate workstream — the **In-Cluster Ansible Runner Pod** (plan 2026-05-14) — already addresses the same root problem from a different angle: configure-stage bootstrap playbooks (the 69x chain) also suffer from being outside the cluster, with caller-location HTTP problems (ADR-0023 §Scope). Phase 1 (foundation SA/RBAC) landed in `dmf-infra@ff36ee8`. The plan's §10.5 explicitly named "Hosting in the in-cluster Zot registry (closes the supply chain)" as post-spike work — i.e. the same Zot-hosted EE image this plan's catalog path needs.

**Convergence:** the runner pod and the catalog AWX EE pod are the same shape of pod under two orchestrators. One image, two consumers. Treating them as separate workstreams duplicates the EE build, the seeding model, and the Zot wiring.

---

## §2 Decision (one architectural shift)

**Ansible runs in in-cluster pods using a Zot-hosted Execution Environment image. Bootstrap-configure (69x) and catalog-launch (`media-*` JTs) share the same execution substrate.**

Concretely:

1. **Shared EE image** at `zot.zot.svc.cluster.local:5000/dmf/awx-ee:<tag>`. Built from `quay.io/ansible/awx-ee:24.6.1` plus the `kubernetes` Python pkg, `kubernetes.core` collection, and the `helm` binary. One image, one source of truth.
2. **Bootstrap-configure** dispatches via the runner-pod wrapper (`bin/run-playbook-in-cluster.sh`, runner-pod plan §6.1.2). Pod runs in `dmf-bootstrap` ns with `cluster-admin` (spike) → narrow post-spike.
3. **Catalog launchers** dispatch via AWX. The JTs are registered with the custom EE; their pods run in the catalog function's namespace (e.g. `nmos`) under a namespace-scoped ServiceAccount.
4. **NMOS-cpp ships as a Helm chart** at `dmf-media/charts/nmos-cpp/`. The launcher's k8s manifests (today inlined in `configure.yml`) lift into chart templates. NMOS images live at `zot.zot.svc.cluster.local:5000/dmf/nmos-cpp-{registry,node}:<tag>` (arm64 builds; operator confirms these exist locally — §8.5).
5. **Stage 4b — Zot seeding** — a new bootstrap step between "Zot is up" and "Forgejo/NetBox/AWX come up." Pushes the AWX EE image, NMOS-cpp images, and Helm charts into cluster-internal Zot. After Stage 4b, every downstream consumer pulls from Zot only.

ADR-0025 codifies this. It partially supersedes ADR-0016 (for `media-*` JTs only — Path A remains canonical for AWX→infrastructure plays). It realizes ADR-0023 §Future direction (caller-location split collapses). It clarifies the two configure-stage meanings (ADR-0012 amendment).

---

## §3 Architecture

```
                          ┌─────────────────────────────────────┐
                          │  Cluster-internal Zot               │
                          │  zot.zot.svc.cluster.local:5000     │
                          │                                     │
                          │   dmf/awx-ee:<tag>                  │  ← single EE image
                          │   dmf/nmos-cpp-registry:<tag>       │
                          │   dmf/nmos-cpp-node:<tag>           │
                          │   dmf/charts/nmos-cpp:<chart-ver>   │  (OCI Helm)
                          └─────────────────────────────────────┘
                                  ▲                ▲
                                  │                │ image pull
                                  │ image pull     │
                  ┌───────────────┘                └──────────────┐
                  │                                                │
   ┌──────────────────────────┐               ┌──────────────────────────────┐
   │  Runner-pod (Lane C)     │               │  AWX EE pod (Lane B)         │
   │  ns: dmf-bootstrap        │               │  ns: awx → catalog ns        │
   │  Trigger: operator wrapper│               │  Trigger: AWX JT POST         │
   │  bin/run-playbook-in-     │               │  (from dmf-cms catalog page)  │
   │  cluster.sh               │               │                              │
   │                          │               │                              │
   │  SA: ansible-runner      │               │  SA: nmos-cpp-launcher       │
   │  RBAC: cluster-admin     │               │  RBAC: namespace-scoped on   │
   │       (spike) → narrow   │               │       nmos namespace         │
   │                          │               │                              │
   │  Workload: bootstrap-     │               │  Workload:                   │
   │  configure 69x playbooks  │               │  launch-nmos-cpp.yml         │
   │  (cms↔netbox, forgejo,    │               │   ├ provision (NetBox HTTP)  │
   │  authentik tokens, etc.)  │               │   ├ helm upgrade --install   │
   │                          │               │   │  oci://zot/dmf/charts/    │
   │                          │               │   │       nmos-cpp           │
   │                          │               │   └ finalise (NetBox tag)    │
   └──────────────────────────┘               └──────────────────────────────┘
                  │                                                │
                  └─────────────────┬──────────────────────────────┘
                                    │
                                    ▼
                          ┌──────────────────────┐
                          │  k8s API (in-cluster)│
                          │  via CoreDNS         │
                          └──────────────────────┘
```

**Why one image and not two:**
- Same Ansible toolchain (`kubernetes.core`, `community.general`, helm binary).
- Differences (SA, RBAC, code distribution, auth) are orchestration-level, outside the container.
- Single rebuild cadence; single supply-chain story; single security review.

**Why two orchestration shells and not one:**
- Triggers differ: operator wrapper (one-shot, workstation-driven) vs AWX JT (long-running engine, dmf-cms-driven).
- Code source differs: workstation tarball via `kubectl cp` vs AWX SCM project clone from Forgejo.
- Lifecycle differs: runner-pod tied to wrapper exit; AWX EE pod tied to JT completion.

Forcing them into one orchestrator (e.g. driving bootstrap-configure through AWX) is a bigger architectural move with no near-term payoff. Keep two shells, share the image.

---

## §4 Bootstrap sequence

```
1. Layer 1   (tofu provision)              — workstation drives, no cluster yet
2. Layer 2   (k3s)                          — workstation drives via SSH (ADR-0016 Path A — unchanged)
3. Layer 3   (cert-mgr, MetalLB)            — workstation drives via SSH
4a. Layer 4 — bootstrap apps                — workstation drives via SSH
    OpenBao → ESO → Authentik → Zot
                              ▲ Zot now reachable in-cluster
4b. STAGE 4b — Seed Zot           ← NEW    — workstation pushes artifacts
    Push: AWX EE image, NMOS-cpp images, Helm charts
    (seed mechanism: §8 open decision — workstation Ansible play vs script vs Job)
4c. Layer 4 (cont.)                         — workstation drives via SSH
    Forgejo → NetBox → AWX → ansible-runner foundation (050-ansible-runner.yml)
                  ▲ 050 references zot.zot.svc/dmf/awx-ee:<tag>, not quay.io
5. bootstrap-configure (69x chain)          — in-cluster runner pod (Lane C)
   bin/run-playbook.sh dispatches via run-playbook-in-cluster.sh transport
6. Catalog ops (media-launch-nmos-cpp, …)   — AWX EE pod (Lane B)
   AWX JT spawns pod with Zot-hosted EE; deploys Helm chart from Zot
```

**What changes vs today:**
- Stage 4b is new — image+chart seeding is its own step, named in the sequence, not a side-effect of some other playbook.
- Layer 4c's `050-ansible-runner.yml` flips its `ansible_runner_image` default from `quay.io/ansible/awx-ee:latest` to `zot.zot.svc.cluster.local:5000/dmf/awx-ee:<tag>`. Layer 4c depends on Stage 4b's outputs.
- Stage 5 (bootstrap-configure) uses Lane C's wrapper for the 69x chain.
- Stage 6 (catalog) uses Lane B's EE-as-runtime path. No more SSH for catalog launches.

**What stays the same:**
- Layers 1–3 and 4a remain on Path A (operator workstation drives via SSH). The cluster doesn't fully exist during those layers; no in-cluster orchestration is possible.
- `bin/run-playbook.sh` remains the operator entry point (ADR-0010). The wrapper internally dispatches by stage; the user-facing command is unchanged.
- AWX as a long-running engine for catalog/operate work — same role, different EE image.

---

## §5 Work breakdown

Three lanes. Lane A is the shared dependency. Lanes B and C consume A independently.

### Lane A — Shared EE image (`zot/dmf/awx-ee`)

| Artifact | File / location | Purpose |
|---|---|---|
| ansible-builder config | `dmf-infra/k3s-lab-bootstrap/ee/execution-environment.yml` | Defines the EE image build |
| collection requirements | `dmf-infra/k3s-lab-bootstrap/ee/requirements.yml` | `kubernetes.core`, `community.general` |
| python requirements | `dmf-infra/k3s-lab-bootstrap/ee/requirements.txt` | `kubernetes`, `openshift`, `jsonpatch` |
| system requirements | `dmf-infra/k3s-lab-bootstrap/ee/bindep.txt` | `helm`, `git`, `ca-certificates` |
| build playbook | `dmf-infra/k3s-lab-bootstrap/playbooks/630-zot-seed-platform.yml` | Builds the EE image, pushes to Zot |
| README | `dmf-infra/k3s-lab-bootstrap/ee/README.md` | Build process, version bumps |

The build playbook runs on the operator workstation or an on-cluster Kaniko Job — see §8.4.

**Gate:** image pulled successfully from `zot.zot.svc.cluster.local:5000/dmf/awx-ee:<tag>` by a test pod in `dmf-bootstrap` ns.

### Lane B — Catalog Helm path (NMOS first; pattern for future media functions) ✅ Landed 2026-05-23

Lane B landed on `g2r6-foa9`: AWX `media-launch-nmos-cpp` job 131 succeeded,
the Helm release `nmos-cpp` is deployed in `nmos`, images are pulled from
cluster-internal Zot, and the launcher uses an explicit `k8s_info` readiness
gate before the NetBox lifecycle tag flip. The original work breakdown is
preserved below as the implementation map.

| Artifact | File / location | Purpose |
|---|---|---|
| Helm chart | `dmf-media/charts/nmos-cpp/Chart.yaml` + `templates/` + `values.yaml` | Lift `configure.yml:7-214` manifests into chart templates |
| NMOS image push | `dmf-media/bin/build-nmos-images.sh` (or operator-existing tooling) | Push locally-built arm64 NMOS images to Zot |
| Namespace RBAC | `dmf-media/manifests/nmos-rbac.yaml` (or chart helper) | SA + Role + RoleBinding in `nmos` ns (concrete shape depends on §8.7 — pod-placement decision) |
| **AWX pod placement (Container Group or pod_spec_override)** | `dmf-infra/.../awx-integration/tasks/main.yml` + `awx-integration/templates/container-group.yml.j2` (new) | **Routes `media-*` JT pods into the catalog function's namespace with the right ServiceAccount.** Without this, the pods stay in the `awx` ns under the default SA and the RBAC above is dead. Two concrete approaches, see §8.7. |
| AWX EE registration | `dmf-infra/.../awx-integration/tasks/main.yml` + `defaults/main.yml` | POST `/api/v2/execution_environments/`; new vars `awx_ee_image`, `awx_ee_tag` |
| Catalog JT EE + Container Group pin | `dmf-infra/.../awx-integration/tasks/catalog-project.yml` | Set `execution_environment: <custom-ee-id>` **AND** `instance_groups: [<catalog-cg-id>]` on `media-*` JTs |
| Launcher rewrite | `dmf-runbooks/playbooks/launch-nmos-cpp.yml` | `hosts: localhost`, `connection: local`, `kubernetes.core.helm` |
| Teardown rewrite | `dmf-runbooks/playbooks/teardown-nmos-cpp.yml` | `helm uninstall` + NetBox finalise |
| Role slim-down | `dmf-runbooks/roles/nmos-cpp/tasks/configure.yml` | Drop all `kubernetes.core.k8s` tasks; chart owns those now |

**On the AWX-pod-placement row (added 2026-05-19 post-codex-review):** the May-6 SA-mount churn (commits `f669415`..`e8bc0f4`) was the same failure class — registering an EE image and pinning it to a JT does **not** by itself move the AWX job pod into the target namespace. The pod-placement wiring is the actual mechanism, and it has historically been the load-bearing thing that broke. Lane B is **not** complete until this row ships and is gated on the verification check `spec.serviceAccountName == <expected>` (see §7).

**Gate:** AWX `media-launch-nmos-cpp` from dmf-cms succeeds end-to-end on both `hetzner-arm` and `aliyun-123`; Helm release visible via `helm list -n nmos`; image refs show Zot URLs; no `ansible_host` remap in the playbook; job pod's `spec.serviceAccountName` matches the SA from the namespace RBAC row (not `default`).

### Lane C — Runner pod (Phases 2–4 from 2026-05-14 plan)

Lane C is the runner-pod plan §6 verbatim, with **one anchor flip:** the EE image reference moves from `quay.io/ansible/awx-ee:latest` to `zot.zot.svc.cluster.local:5000/dmf/awx-ee:<tag>` after Lane A ships.

| Phase | What | Status |
|---|---|---|
| 1 | `dmf-bootstrap` ns, ansible-runner SA, ClusterRoleBinding, `050-ansible-runner.yml` | **Done** (`dmf-infra@ff36ee8`) |
| 2 | Operator wrapper `bin/run-playbook-in-cluster.sh` + Pod template | Pending |
| 3 | `openbao-session` mounted-secret mode | Pending |
| 4 | End-to-end test on playbook 698; revert `dmf-infra@37dbb56` | Pending |

Anchor flip: when Lane A is green, update `roles/stack/operator/ansible-runner/defaults/main.yml` to point at the Zot-hosted EE. Until then, Phase 2/3/4 work proceeds against `quay.io/ansible/awx-ee:latest`.

**Gate:** playbook 698 reaches `failed=0` via the in-cluster transport with **no** `cms_*_api_url` override flags; internal-DNS defaults restored.

---

## §6 Sequencing

```
   ┌─────────────────────────────────────┐
   │ ADR-0025 placeholder + this plan    │  ← landing first (this PR)
   │ ratified by operator                 │
   └────────────────┬─────────────────────┘
                    │
                    ▼
   ┌─────────────────────────────────────┐
   │ Lane A — Shared EE image            │  ← gate; both B and C consume it
   │ (dmf-infra ee/ + 630-zot-seed-platform.yml)    │
   └─────────────┬───────────────────┬───┘
                 │                   │
                 ▼                   ▼
   ┌──────────────────┐   ┌──────────────────┐
   │ Lane B — Helm    │   │ Lane C — Runner  │
   │ chart + image    │   │ pod Phases 2–4   │
   │ push + launcher  │   │                   │
   │ rewrite          │   │ (independent of B)│
   └──────────────────┘   └──────────────────┘
                 │                   │
                 ▼                   ▼
   ┌─────────────────────────────────────┐
   │ End-state verification (both envs)   │
   └─────────────────────────────────────┘
```

Lane A blocks both consumers. Lane B can ship before C (or vice versa) — they only share the image.

Stage 4b's seeding mechanism is part of Lane A: building+pushing the EE image is the first thing Stage 4b does. NMOS image + chart push are part of Lane B's setup work but technically Stage-4b-shaped (workstation pushes to Zot). The decision in §8.1 picks the seed mechanism for all three.

---

## §7 Verification (end state)

Single AWX `media-launch-nmos-cpp` run from dmf-cms succeeds on both `hetzner-arm` and `aliyun-123` with these properties:

| Check | Expected |
|---|---|
| JT execution_environment | `zot.zot.svc.cluster.local:5000/dmf/awx-ee:<tag>` (not Default `quay.io/...`) |
| Job pod's `spec.serviceAccountName` | namespace-scoped (`nmos-cpp-launcher` or equivalent) |
| Image source on pulled pods | `zot.zot.svc.cluster.local:5000/dmf/...` everywhere |
| Helm release | `helm list -n nmos` shows `nmos-cpp` at chart version `0.1.0` |
| NetBox service tag | flipped to `lifecycle:active` |
| `ansible_host` remap | **not present** in any catalog playbook |
| Runner-pod Phase 4 | `playbook 698` runs in-cluster, `failed=0`, no `cms_*_api_url` overrides |
| ADR-0016 | reads as infra-only after Amendment block; ADR-0025 published as Accepted |
| Doc consistency | **Current-state docs** (`docs/decisions/`, `docs/architecture/`, `docs/processes/`, all `CLAUDE.md`, `README.md`, `STATUS.md`, the active plan + ADR-0025) make no unqualified canonical claim that catalog launchers use Path A / SSH-to-control-node — every such reference must be qualified ("for 693-class infra plays" or "partially superseded" or "historical"). Historical docs (`docs/handoffs/`, `docs/reviews/`, `docs/audits/`, superseded plans with banners, `docs/agentic/loop-log.md`, `docs/agentic/backlog.yaml`) retain their unqualified Path-A references — those describe past state and are *correctly* untouched. Concretely-checkable: pick any current-state doc, `grep -nE 'Path A\|SSH-to-control-node'`, every match must sit inside an amendment, banner, "for 693-class" qualifier, or supersession marker. |

---

## §8 Open decisions (preserved verbatim — not decided in this plan)

Seven items were raised during the 2026-05-19 convergence discussion (six original, plus §8.7 added post-codex-review). Operator deferred all pending more context or implementation evidence. Each is mirrored to `docs/agentic/decisions-open.md` for the queue.

### §8.1 Stage 4b seed mechanism

**Question:** how does the workstation push the AWX EE image, NMOS-cpp images, and Helm charts into Zot?

- (a) **Workstation Ansible playbook** (`600-zot-seed.yml`) — uses `community.docker` or `skopeo` to push from a workstation context. Mirrors playbook 650 (`dmf-cms-build-and-release`). Operator needs `docker`/`skopeo`/`helm` on workstation.
- (b) **Dedicated `bin/seed-zot.sh`** — bash wrapper, no Ansible indirection. Less consistent with bootstrap convention (Ansible-driven). Same workstation prerequisites.
- (c) **In-cluster Job seeded by kubectl cp** — workstation cp's a tarball of `docker save` outputs + chart `.tgz` into a Job pod; Job does the push from inside. No `docker` required on workstation. Most moving parts.

Recommendation deferred. Likely (a) for consistency with 650.

### §8.2 `dmf-media-build-and-release` skill scope/timing

**Question:** should `dmf-media` get a build-and-release skill mirroring `dmf-cms-build-and-release` now, or after a second media function lands?

- (a) **Now** — codify the NMOS arm64 build + push as a sanctioned skill. Sets pattern for future functions.
- (b) **Defer** — document the NMOS build informally in this plan; promote to a skill when needed.

Recommendation deferred.

### §8.3 ADR-0025 scope — operator confirmation requested

**Question:** §2 of this plan currently specifies a **broad** ADR-0025 (NMOS Helm + EE-as-runtime + Stage 4b seeding + runner-pod-image alignment). The ADR-0025 placeholder file is shaped accordingly. **This item asks the operator to ratify (or split) the scope before the placeholder is promoted from Proposed to Accepted.**

- (a) **Keep broad ADR-0025** — one ADR captures the whole shift. The convergence story stays together. *This is what the plan currently assumes.*
- (b) **Split into ADR-0025 + ADR-0026** — ADR-0025 covers the catalog Helm side; ADR-0026 covers the runner-pod / shared-image side. Each ADR is smaller but the convergence story spans both. Requires reserving ADR-0026 (currently free).

Default: (a), unless operator wants finer-grained traceability per lane.

### §8.4 EE build host

**Question:** where does the AWX EE image get built — operator workstation or in-cluster Kaniko?

- (a) **Operator workstation** — buildkit/podman locally; same model as dmf-cms.
- (b) **On-cluster Kaniko Job** — no operator-side build prerequisites.

Recommendation deferred. Likely (a) for symmetry with dmf-cms but operator's preference dominates.

### §8.5 Upstream nmos-cpp arm64 availability

**Operator note (2026-05-19):** "we have been building our own arm nmos64 so the image should exist locally."

**Action:** before plan execution, **confirm** the operator's locally-built arm64 NMOS-cpp images are present and usable. If yes, Lane B's "build" step collapses to a "push" step (image already exists). If the images need rebuilding, factor in the build time + tooling needs.

### §8.6 Zot anonymous-read on `dmf/*`

**Question:** how do in-cluster Pods pull from Zot?

- (a) **Anonymous read on `dmf/*` repos in Zot** — simplest; Zot config allows in-cluster pulls without auth. Push still requires auth.
- (b) **Per-namespace pull-secret injection** — every catalog namespace gets a pull-secret synced from a master secret. More secure, more moving parts.

Recommendation deferred. (a) is operationally simpler and the Zot ClusterIP is not externally exposed.

### §8.7 AWX pod placement — namespace + ServiceAccount wiring

**Added 2026-05-19 post-codex-review.** Codex flagged that Lane B's RBAC item (SA + Role + RoleBinding in `nmos` ns) does not by itself put the AWX job pod into `nmos` ns or attach the SA — registering an EE image and pinning it to a JT is necessary but not sufficient. The May-6 SA-mount churn (commits `f669415`..`e8bc0f4`) hit exactly this gap.

**Question:** which AWX mechanism routes `media-*` JT pods into the catalog function's namespace with the right SA?

- (a) **SA in `awx` ns + cross-namespace RoleBinding** — keeps the pod in `awx` ns where AWX-operator defaults it. The RoleBinding's subject is `ns: awx, sa: nmos-cpp-launcher`; the role lives in `ns: nmos`. The custom EE pod runs under the awx-ns SA and acts on nmos-ns resources. Wiring: an AWX Container Group is still needed to bind the JT to that SA via `pod_spec_override.spec.serviceAccountName`. Simpler RBAC topology; less namespace boundary clarity (the pod and the workload live in different namespaces).
- (b) **SA in `nmos` ns + AWX Container Group with namespace override** — the Container Group's `pod_spec_override` specifies `metadata.namespace: nmos` and `spec.serviceAccountName: nmos-cpp-launcher`. The AWX job pod runs in the same namespace as the workload it manages. Cleaner boundary; more AWX-operator config; the EE pod must be schedulable in `nmos` ns (image pull, network policies).

Default recommendation: **(b)** — cleaner namespace semantics; matches the "each function owns its namespace" pattern that the chart establishes. But (a) has lower AWX-operator coordination cost and may be the right choice if there's a generic catalog Container Group that serves all `media-*` JTs from one config.

**Why this is a real gap and not a detail:** the verification check `spec.serviceAccountName == <expected>` in §7 only passes if this row of Lane B ships. Without it, the JT pod runs in `ns: awx` under SA `default` and either has no rights or has too many rights, neither of which is the intended posture. **Operator must answer this before Lane B implementation starts.**

---

## §9 What this plan does NOT do

- **Does not change `bin/run-playbook.sh`-driven plays for Layers 1–3 / Layer 4a.** Provision-stage SSH-to-control-node remains the model for pre-cluster work.
- **Does not retire ADR-0016 wholesale.** ADR-0016 remains valid for AWX→infrastructure plays (693-class) — those don't have the `ansible_host` problem because they target the actual control node and the inventory is hand-managed.
- **Does not introduce GitOps (Argo/Flux).** Helm install runs imperatively from the AWX EE pod. GitOps is a separate ADR, deferred.
- **Does not address the persistent `vault_netbox_admin_token` extra-var on `media-launch-nmos-cpp`.** Out of scope; tracked under [DMF Aliyun-123 Lifecycle-Configure Follow-Ups Plan 2026-05-17](./DMF%20Aliyun-123%20Lifecycle-Configure%20Follow-Ups%20Plan%202026-05-17.md).
- **Does not address App Admin drift.** Separate workstream tracked under the Aliyun-123 Follow-Ups plan §B.1.
- **Does not migrate every 69x playbook to in-cluster transport.** Lane C ships the substrate; the per-playbook migration cadence is the runner-pod plan's §10.3 follow-on work.

---

## §10 Doc-update register

This plan amends or cross-references the following docs. Each is updated as part of the same PR landing this plan:

**Plans:**
- `DMF In-Cluster Ansible Runner Pod Implementation Plan 2026-05-14.md` — Lane C cross-ref banner; §10.5 updated.
- `Move 1 Gate 2 - Pivot to Path A for Catalog Launchers 2026-05-06.md` — partial-supersession banner.
- `Move 1 Gate 2 — AWX Integration + Launch NMOS.md` — cross-ref to this plan.
- `DMF MXL Single-Node Media Node Spike Plan 2026-05-17.md` — cross-ref noting unified Stage 4b path.
- `DMF Lifecycle-Configure Bootstrap Completion Plan 2026-05-15.md` — cross-ref note.
- `DMF Aliyun-123 Lifecycle-Configure Follow-Ups Plan 2026-05-17.md` — links job 44 + verification target.
- `dmf-platform-move-1-task-2026-05-04.md` — Piece 4 image-push note.
- `dmf-platform-move-2-task-2026-04-30.md` — note about ADR-0016's Move-2-deferred work landing earlier.

**Decisions:**
- `0016-...` — Amendments section.
- `0012-...` — Terminology note (two configure-stage usages).
- `0023-...` — Future direction update.
- `INDEX.md` — ADR-0025 placeholder row; ADR-0016 row notes partial supersession.
- `0025-ansible-in-cluster-pods-and-catalog-helm.md` — NEW placeholder. (ADR-0024 was already informally reserved by the Aliyun-123 follow-ups plan §B.1/§C.3 for "Live-state read pattern for app admin identities"; this plan takes 0025.)

**Component repos:**
- `dmf-runbooks/CLAUDE.md` — Architecture Notes update.
- `dmf-runbooks/README.md` — Catalog Entries note.
- `dmf-runbooks/roles/nmos-cpp/README.md` — lifecycle table update.
- `dmf-media/CLAUDE.md` — Charts directory section.
- `dmf-infra/CLAUDE.md` — note about `ee/` + `630-zot-seed-platform.yml` forward reference.

**Umbrella + agentic:**
- `STATUS.md` operator notes — one-line entry.
- `docs/agentic/decisions-open.md` — six open decisions queued.
- `docs/agentic/autonomous-decisions.md` — convergence call logged.

---

## §11 References

- **Failing job:** AWX job 44 on `aliyun-123` (2026-05-17), `media-launch-nmos-cpp`, `UNREACHABLE!` at "Fetch existing NetBox tags"
- **Failing code:** `dmf-runbooks/playbooks/launch-nmos-cpp.yml:28-34` (hardcoded Hetzner private-IP map)
- **Manifests to lift into chart:** `dmf-runbooks/roles/nmos-cpp/tasks/configure.yml:7-214`
- **Role defaults to update:** `dmf-runbooks/roles/nmos-cpp/defaults/main.yml`
- **Runner-pod prior plan:** [DMF In-Cluster Ansible Runner Pod Implementation Plan 2026-05-14](./DMF%20In-Cluster%20Ansible%20Runner%20Pod%20Implementation%20Plan%202026-05-14.md)
- **Runner-pod Phase 1:** `dmf-infra@ff36ee8` (foundation SA + ClusterRoleBinding + `050-ansible-runner.yml`)
- **Lifecycle-configure completion:** [DMF Lifecycle-Configure Bootstrap Completion Plan 2026-05-15](./DMF%20Lifecycle-Configure%20Bootstrap%20Completion%20Plan%202026-05-15.md) — describes the gaps fixed pre-failure
- **Follow-ups:** [DMF Aliyun-123 Lifecycle-Configure Follow-Ups Plan 2026-05-17](./DMF%20Aliyun-123%20Lifecycle-Configure%20Follow-Ups%20Plan%202026-05-17.md)
- **MXL alignment:** [DMF MXL Single-Node Media Node Spike Plan 2026-05-17](./DMF%20MXL%20Single-Node%20Media%20Node%20Spike%20Plan%202026-05-17.md) — also needs arm64 images in Zot; aligns with Stage 4b
- **ADRs:** [ADR-0010](../decisions/0010-run-playbook-as-sanctioned-entry.md), [ADR-0012](../decisions/0012-configure-stage-distinct-from-provision.md), [ADR-0013](../decisions/0013-media-function-catalog-model.md), [ADR-0014](../decisions/0014-awx-project-layout.md), [ADR-0016](../decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md), [ADR-0023](../decisions/0023-internal-service-dns-for-cross-app-wiring.md)
- **First-cut draft superseded by this plan:** `DMF NMOS Helm Chart and EE-Runtime Pivot Plan 2026-05-19.md` (deleted — content absorbed here)
