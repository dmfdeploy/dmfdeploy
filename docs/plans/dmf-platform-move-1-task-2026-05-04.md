---
status: executed
date: 2026-05-04
executed: 2026-06-04
---
# Move 1 — NMOS spike + Function Catalog vertical slice
> Supersedes: [DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md](DMF%20NMOS%20Registry%20%2B%20Crosspoint%20Demo%20Plan%202026-05-04.md)

> **2026-05-19 update — multiple Pieces affected by the catalog launcher pivot.**
> The catalog launcher's *transport* moves to EE-as-runtime + Helm per
> [ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md)
> and the [Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19](./DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md).
> Pieces affected:
> - **Piece 4 (NMOS provision-side):** image push to Zot is now **Stage 4b
>   of the bootstrap sequence**; Lane B of the 2026-05-19 plan owns the
>   unified media-image seeding mechanism.
> - **Piece 5 (dmf-media configure-side launch) + Piece 6 (AWX launcher):**
>   the May-04 plan assumed `import_role`-from-`dmf-media` and SSH-to-node
>   execution. Both are superseded by the 2026-05-19 plan: launcher uses
>   `connection: local` in an in-cluster EE pod and calls
>   `kubernetes.core.helm` against a chart in `dmf-media/charts/nmos-cpp/`.
>   The dmf-media `role` reference is replaced by a `chart` reference; the
>   NetBox-side role moves to `dmf-runbooks/roles/nmos-cpp/`.
> - **Catalog model + dmf-cms catalog page + ADR-0013** remain in scope as
>   written — only the launcher's internal implementation changes; the
>   dmf-cms ↔ AWX JT POST contract is stable.
> Read the 2026-05-19 plan before re-deriving any Move 1 narrative.

**Date:** 2026-05-04
**Repo scope:** `dmf-media` (primary), `dmf-infra` (lifecycle wrappers + AWX integration), `dmf-cms` (catalog page), `dmf-env` (inventory vars)
**Reviewer that produced this task:** Claude Opus 4.7, planning session 2026-05-04 with <operator>; supersedes the dmf-cms-integration framing of `docs/plans/DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md` (Phase 3) while preserving its Phase 1+2 technical work as implementation reference.
**Strategic context:** experiment phase (ADR-0004); commit-gate item per `docs/reviews/dmf-platform-strategic-review-2026-04-30.md`. Move 2 closed; Move 1 is the remaining gate.
**Estimated effort:** 3–5 days realistic. Bumps the strategic review's original 1-day NMOS estimate because catalog mechanics are bundled in.
**Closes:** strategic-review commit gate (when paired with `docs/architectural-commitments-v1.md` follow-up).

> **Note on scope expansion:** The original strategic review framed Move 1 as "deploy one NMOS registry on `dmf-media`, run for 24 hours." This task spec expands Move 1 to bundle the **function catalog** mechanism (ADRs 0012, 0013, 0014) in the same experiment. Rationale: the catalog reframe directly probes thesis-killer #3 (EBU taxonomy survives a hard case) which the bare NMOS deploy does not. Bundling is cheaper than two sequential experiments because the lifecycle / AWX / dmf-cms work has to happen once anyway, and a catalog with a single entry is the minimum coherent shape.

---

## What this is and isn't

### This IS

A **falsifying spike** that simultaneously tests:
1. NMOS IS-04/05 deploys cleanly on commodity ARM k3s (the strategic review's #1 thesis-killer).
2. The function catalog model holds shape under one real entry (validates ADRs 0012/0013/0014).
3. The Configure-as-distinct-stage split survives a real Layer 5 function.

### This is NOT

- A polished release. UI minimal, error paths minimal, one TODO per shortcut.
- A full media-function set. ONE catalog entry (nmos-cpp). The other Layer 4–5 stubs (ebu-list, ptp-monitor, flow-exporters, netbox-media-plugin) stay as scaffolds.
- A dual-cluster federation exercise. Single cluster only.
- Real RTP / 2110 traffic. Mock NMOS senders/receivers only — Appendix E of the NMOS plan is explicitly deferred.
- A migration of Layer 6 baseline apps into catalog entries. Out of scope for v1.
- A multi-instance / parameterised-launch story. One instance per entry, no operator-supplied vars at launch time.

---

## What this falsifies (or confirms)

In priority order, six architectural assumptions:

1. **NMOS IS-04/05 deploys on commodity k3s.** If `nmos-cpp` won't build on ARM64 / won't run cleanly under k3s flannel CNI, the entire Layer 4–5 thesis is in question.
2. **The catalog YAML schema accommodates a real Layer 5 function.** If `nmos-cpp.yaml` ends up needing schema extensions (new fields, escape hatches, free-text "extras" blobs), the schema needs a v0 reshape before more entries are written.
3. **Configure-as-distinct-stage holds for nmos-cpp.** If the Provision/Configure split feels artificial (e.g., NetBox `ipam.Service` registration *requires* the workload to be running to know its endpoint), ADR-0012 needs revisiting.
4. **dmf-cms can drive the lifecycle through AWX.** Move 2 closed the AWX path for one runbook; the catalog flow exercises it for a real Helm-deploy. New failure modes: Helm wait timeouts, partial deploys, NetBox-tag drift.
5. **The hybrid AWX project layout (ADR-0014) works.** Specifically: launcher in `dmf-runbooks` can `import_role` from the `dmf-media` mirror project. If `roles_path` resolution fails, ADR-0014 needs revisiting.
6. **The drift detector in `lifecycle-operate` catches NetBox/Helm divergence.** If it doesn't, the catalog's invariant is unenforceable and the model is unsound.

---

## Decision points (need your input before execution)

### D1 — Which NMOS registry implementation

The existing `DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md` Appendix A specs `sony/nmos-cpp` built from source via Conan 2 + CMake on Mac mini Colima. Two options:

| Option | Source | Pros | Cons |
|---|---|---|---|
| **A. Sony nmos-cpp (build from source)** | github.com/sony/nmos-cpp | Canonical upstream; pinned-tag reproducible | Conan build on ARM64 unverified; ~30-60 min build per image |
| **B. NVIDIA fork pre-built (Easy-NMOS path)** | rhastie/easy-nmos | Pre-built images, faster start | Diverged fork; less direct upstream story for the credibility/OSS goal |

**Recommendation: A**, with B as fallback if Conan fails on first build. Per Appendix A.6 of the NMOS plan.

**Action:** confirm A or pick B.

### D2 — `lifecycle-configure.yml` first implementation

The wrapper exists for the first time in this work. Two shapes:

| Option | Shape | Pros | Cons |
|---|---|---|---|
| **A. Tag-driven, single import block per entry** | One `import_playbook` per catalog entry, gated by `--tags <key>`. Default behavior: no entries run unless tagged. | Matches existing wrapper style; simple to read | Adds a line per entry forever; visual clutter as catalog grows |
| **B. Loop over manifest list** | Wrapper reads catalog YAML, dynamically imports per-entry playbooks. | Scales to N entries with no wrapper churn | Ansible's `import_playbook` doesn't accept loops cleanly; would need `include_playbook` (different semantics) or a meta-task pattern |

**Recommendation: A** for v1. B is an evolution that depends on N catalog entries to justify; with one entry it's premature.

**Action:** confirm A.

### D3 — AWX launcher pattern

Per ADR-0014, launchers in `dmf-runbooks` are thin wrappers. Two specific shapes:

| Option | Wrapper body | Pros | Cons |
|---|---|---|---|
| **A. `import_playbook` from mirrored source repo** | `- import_playbook: ../dmf-media/playbooks/configure-media/launch-nmos-cpp.yml` (relies on AWX project parent-dir resolution) | Truly thin; no role-path config | Path traversal across projects is non-standard; AWX may reject `..` |
| **B. `hosts: + roles:` with explicit role from another project** | Wrapper has its own play; `roles: - role: nmos-cpp` resolves via AWX `roles_path` | Standard AWX pattern; works with project boundaries | `roles_path` must be configured per-template or per-inventory |

**Recommendation: B.** Standard AWX practice; survives audit; `roles_path` is one-time setup in `awx-integration`.

**Action:** confirm B (and approve the `awx-integration` role gaining `roles_path` management).

### D4 — dmf-cms catalog source for v1

The catalog architecture (§3) says dmf-cms joins YAML + NetBox. v1 has two paths:

| Option | dmf-cms reads YAML from… | Pros | Cons |
|---|---|---|---|
| **A. In-cluster Forgejo (HTTP raw file)** | GET `https://forgejo.<lan-host>/<owner>/dmf-media/raw/branch/main/catalog/<key>.yaml` | Real federation-ready path; works the same in production | Authentication; YAML parse on every read; cache layer needed |
| **B. Mounted ConfigMap** | Catalog YAML rendered into a ConfigMap by `650-dmf-cms.yml`, mounted at `/etc/dmf-cms/catalog/` | Simplest; restart picks up changes | Provisioning step has to gather YAML across repos; staleness risk |

**Recommendation: B for v1**, A as a v2 evolution. v1 prioritises closing the loop; B closes it in less code. The "rendered into ConfigMap" step lives in the `cms` Ansible role and is one task.

**Action:** confirm B.

---

## Concrete work breakdown

Assuming D1=A, D2=A, D3=B, D4=B.

### Piece 1 — Catalog schema + first entry (~1-2 hr)

**File scope:**
- `dmf-media/catalog/nmos-cpp.yaml` — NEW — first catalog entry, populated per the schema in `docs/architecture/DMF Function Catalog Model.md` §2
- `dmf-media/catalog/README.md` — NEW — documents the schema, points at the architecture reference

**Validation:** `python -c "import yaml; yaml.safe_load(open('catalog/nmos-cpp.yaml'))"` parses; required fields present.

---

### Piece 2 — `lifecycle-configure.yml` wrapper (~30 min)

**File scope:**
- `dmf-infra/k3s-lab-bootstrap/lifecycle-configure.yml` — NEW — header comment per ADR-0012; one `import_playbook` block tagged `nmos-cpp`
- `dmf-infra/k3s-lab-bootstrap/lifecycle-provision.yml` — MODIFIED — drop "+ Configure" from line-1 comment; add NMOS Provision step (registers catalog entry, does NOT launch)

**Acceptance:** `bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/lifecycle-configure.yml --list-tags` lists `nmos-cpp` as a tag.

---

### Piece 3 — Forgejo mirroring + AWX project setup (~2 hr)

**File scope:**
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/main.yml` — MODIFIED — add `dmf-media` and `dmf-infra` as Forgejo mirror repos (uses Forgejo's built-in mirror feature; configure remote URL + sync interval)
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml` — MODIFIED — create AWX projects for `dmf-runbooks`, `dmf-media` (mirror), `dmf-infra` (mirror); set `roles_path` per project
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml` — MODIFIED — add project list as a default

**Acceptance:** AWX UI shows three projects, all with successful initial SCM sync. `dmf-cms-svc` user has read access on all three. `awx_inventory_id` is unchanged from Move 2; only project list extended.

---

### Piece 4 — NMOS provision-side work (~1 day, including build)

**File scope:** as per `DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md` Phase 1 Steps 1–2 (Dockerfile, role tasks, ConfigMaps, StatefulSet/Deployment templates) — REUSED.

**Modifications from the original NMOS plan:**
- Playbook is renamed `410-nmos-cpp-provision.yml` and **does NOT deploy the workload**. It only:
  - Pulls/pushes images to Zot (idempotent)
  - Renders Helm chart into OCI (or kustomize bundle into a known location)
  - Writes the NetBox `ipam.Service` record with tags including `lifecycle:bootstrapped`
- Imported into `lifecycle-provision.yml` under `# ── Layer 5xx — Media Functions ─` (the existing reserved comment).

**Acceptance:** after `lifecycle-provision.yml` runs, `kubectl get all -n nmos` returns nothing (no namespace, no workload). NetBox shows an `ipam.Service` named `nmos-cpp` tagged `lifecycle:bootstrapped`. Image is in Zot.

---

### Piece 5 — NMOS configure-side launch playbook (~3-4 hr)

**File scope:**
- `dmf-media/playbooks/configure-media/launch-nmos-cpp.yml` — NEW — applies the Helm release / kustomize bundle, waits for pods Ready, flips the NetBox tag from `:bootstrapped` to `:active`, returns endpoint info via `set_stats`
- `dmf-media/playbooks/configure-media/teardown-nmos-cpp.yml` — NEW — reverse: removes the workload, flips tag back

**Acceptance:** `bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/lifecycle-configure.yml --tags nmos-cpp` launches the registry. Re-running is idempotent. NetBox tag flips correctly. Manual teardown via the teardown playbook works.

---

### Piece 6 — AWX job templates + launcher in `dmf-runbooks` (~1-2 hr)

**File scope:**
- `dmf-runbooks/launch-nmos-cpp.yml` — NEW (created in in-cluster Forgejo by `awx-integration`) — thin launcher per D3 option B (`hosts:` + `roles: - role: nmos-cpp` with vars from catalog YAML)
- `dmf-runbooks/finalise-nmos-cpp.yml` — NEW — symmetric teardown
- `awx-integration/tasks/main.yml` — MODIFIED — create job templates `media-launch-nmos-cpp` and `media-finalise-nmos-cpp` pointing at the launcher playbooks; grant `dmf-cms-svc` Execute permission on both

**Acceptance:** From AWX UI, manually launch `media-launch-nmos-cpp`. Job runs through the launcher → resolves the `nmos-cpp` role from the `dmf-media` mirror project → completes. Verify NetBox tag flipped.

---

### Piece 7 — dmf-cms catalog page (~1 day)

**File scope:**
- `dmf-cms/src/dmf_cms/catalog.py` — NEW — reads catalog YAML from `/etc/dmf-cms/catalog/` (D4 option B), joins with NetBox tag query
- `dmf-cms/src/dmf_cms/main.py` — MODIFIED — add GET `/api/catalog`, POST `/api/catalog/<key>/deploy`, POST `/api/catalog/<key>/teardown`, GET `/api/catalog/<key>/status/<job_id>` (delegates to existing `awx.py` machinery)
- `dmf-cms/src/dmf_cms/templates/` or React routing — MODIFIED — add a `/catalog` page with one card per entry, Deploy/Teardown buttons, status polling
- `dmf-cms/charts/dmf-cms/templates/configmap-catalog.yaml` — NEW — receives the catalog YAML files as keys
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/cms/tasks/main.yml` — MODIFIED — gather catalog YAML files from mirrored source repos, render into the ConfigMap before `helm upgrade`

**Acceptance:** Open dmf-cms `/catalog`. The single nmos-cpp card shows `lifecycle:bootstrapped`. Click Deploy. Status polls; within ~30s shows `lifecycle:active`. Click Teardown. Within ~30s shows `lifecycle:bootstrapped`.

---

### Piece 8 — Drift-detector smoke test (~1 hr)

**File scope:**
- `dmf-infra/k3s-lab-bootstrap/playbooks/lifecycle/operate-catalog-drift.yml` — NEW — for each catalog entry, fetch NetBox tag and Helm release presence; assert agreement
- `dmf-infra/k3s-lab-bootstrap/lifecycle-operate.yml` — MODIFIED — add the drift check after `test-layer6.yml`

**Acceptance:** `lifecycle-operate.yml` exits green when state is consistent. Manually delete the Helm release without flipping the tag → drift check fails on next run, identifies the entry.

---

### Piece 9 — Write-up (the actual deliverable, per ADR-0004) (~2-3 hr)

**File scope:**
- `docs/reviews/dmf-platform-move-1-learnings-2026-05-XX.md` — NEW — six Q-and-A sections matching the six falsifications in §"What this falsifies", plus a §"Bonus learnings" for unpredicted findings (matching the Move 2 learnings doc structure)
- `docs/architectural-commitments-v1.md` — NEW — drafted now that both Move 1 and Move 2 are closed. List the architecture pieces that survived contact with reality and stop reshaping. Per the strategic review's commit gate.

**Acceptance:** doc captures schema reshape (if any), surprises, deferred items. `architectural-commitments-v1.md` exists and lists the surviving architecture; the project transitions out of pure experiment phase per ADR-0004's revisit criteria.

---

## How to execute this — three options

### Option A — Codex autonomous, with human checkpoints

Hand the spec to codex with STOP gates after each Piece. Codex builds; you review the diff after each Piece.

**Pros:** Fastest wall-clock for Pieces 2, 3, 4, 6, 8.
**Cons:** Pieces 5 and 7 need taste calls — the launch playbook's idempotency / tag-flip semantics, the dmf-cms UI shape. Codex tends to over-engineer or under-handle errors there.

### Option B — Claude with user, single session

You and Claude work through it sequentially in one session. Decisions inline. Eats session context.

**Pros:** Highest quality on Pieces 5 and 7.
**Cons:** Slowest wall-clock; loses parallelism on the mechanical Pieces.

### Option C — Mixed: codex on Ansible, Claude on dmf-cms

Codex executes Pieces 2, 3, 4, 6, 8 autonomously (Ansible scope, mechanical). Claude works with you on Pieces 5 (launch playbook taste) and 7 (dmf-cms UI). Final integration test runs end-to-end after both halves.

**Recommended.** Same pattern that worked for Move 2.

**Sequencing under Option C:**
1. Codex: Piece 1 (catalog YAML)
2. Codex: Piece 2 (lifecycle-configure wrapper)
3. Codex: Piece 3 (Forgejo mirroring + AWX projects)
4. Codex: Piece 4 (NMOS provision)
5. **Manual run:** lifecycle-provision; verify image in Zot, NetBox record present, no workload running
6. Claude+user: Piece 5 (launch playbook — taste-heavy because of idempotency + tag-flip semantics)
7. Codex: Piece 6 (AWX JTs + launcher)
8. **Manual run:** launch from AWX UI; verify workload up
9. Claude+user: Piece 7 (dmf-cms catalog page)
10. Codex: Piece 8 (drift detector)
11. Final test: Deploy + Teardown from dmf-cms UI
12. Claude+user: Piece 9 (write-up + commitments doc)

---

## Acceptance — falsification or confirmation

Move 1 + Catalog is "complete" (gate-closed) when **all** of these are true:

- [ ] `nmos-cpp` registry image builds on ARM64 (or fallback B works) and is in Zot
- [ ] After `lifecycle-provision.yml`, NetBox has an `ipam.Service` for `nmos-cpp` tagged `lifecycle:bootstrapped`, AND no nmos-cpp workload is running
- [ ] `lifecycle-configure.yml --tags nmos-cpp` brings the workload up, flips tag to `:active`
- [ ] AWX job templates `media-launch-nmos-cpp` and `media-finalise-nmos-cpp` exist; `dmf-cms-svc` can launch them
- [ ] dmf-cms `/catalog` page shows the entry with current state, Deploy/Teardown buttons work end-to-end
- [ ] `lifecycle-operate.yml` drift-detector passes when state is consistent and fails clearly when it isn't
- [ ] At least one mock NMOS sender registered to the registry (per the original NMOS plan's Phase 1 Step 5 verification)
- [ ] **A write-up captures what was learned** — schema reshape (if any), Configure-split surprises, AWX project layout edge cases. This is the actual deliverable.
- [ ] `docs/architectural-commitments-v1.md` drafted

If **any** of those breaks in a way that requires reshaping the catalog model or the lifecycle split, that breakage IS the deliverable. The strategic review's commit gate triggers when this loop runs end-to-end *or* when the breakage tells you to redraw the architecture before committing.

---

## Out of scope (do NOT include in Move 1)

- Other Layer 4–5 stubs (ebu-list, ptp-monitor, flow-exporters, netbox-media-plugin). They stay scaffolds.
- Real RTP / 2110 traffic. Mock senders only. Appendix E of the NMOS plan stays deferred.
- nmos_crosspoint UI (the original NMOS plan's Phase 2). Defer to Move 1.5 or fold into a v2 catalog entry.
- Multi-instance NMOS registry (HA). One instance.
- Migration of Layer 6 baseline apps to catalog entries. Out of scope.
- Per-user identity propagation through AWX (Move 2 known gap).
- Polished error UX in dmf-cms catalog page. "Failed: see AWX run #123" is enough.
- Approval workflow / PR-gated deploys for catalog entries. Operations-lane only in v1.
- dmf-central federation. Single cluster.
- Hardening, alerts, backups, rotation. Per ADR-0004.

---

## Dependencies on prior work (must be in place)

- ✅ Move 2 closed (`docs/reviews/dmf-platform-move-2-learnings-2026-05-04.md`)
- ✅ Born-inventory writes `ipam.Service` records (`roles/common/dmf-born-inventory/`)
- ✅ AWX integrated with NetBox + Forgejo (`693-awx-integration.yml`)
- ✅ `dmf-cms-svc` exists with AWX OAuth2 token (`697-cms-awx-token.yml`)
- ✅ Zot registry running and accessible (`331-registry-zot.yml`)
- ✅ Tailscale private lane (for crosspoint UI later, optional for Move 1)
- ✅ ADR-0012, ADR-0013, ADR-0014 accepted
- ✅ Architecture reference: `docs/architecture/DMF Function Catalog Model.md`

All in. Move 1 + Catalog is unblocked.

---

## What to commit (suggested commit shape)

Nine commits, one per Piece:

1. `feat(catalog): schema + first entry for nmos-cpp` (dmf-media)
2. `feat(lifecycle): split Configure from Provision (ADR-0012)` (dmf-infra)
3. `feat(awx): hybrid project layout — dmf-runbooks + mirrored sources (ADR-0014)` (dmf-infra)
4. `feat(nmos): provision-side image + chart + NetBox registration` (dmf-media + dmf-infra)
5. `feat(nmos): configure-side launch + teardown playbooks` (dmf-media)
6. `feat(awx): job templates + launchers for nmos-cpp` (dmf-infra)
7. `feat(dmf-cms): catalog page reads YAML + NetBox, drives AWX deploys` (dmf-cms + dmf-infra)
8. `feat(lifecycle-operate): catalog drift detector` (dmf-infra)
9. `docs(reviews): Move 1 learnings + architectural-commitments-v1` (umbrella)

Each commit independently testable.

---

## Cross-reference

- Strategic review (frame): `docs/reviews/dmf-platform-strategic-review-2026-04-30.md`
- Move 2 learnings (predecessor): `docs/reviews/dmf-platform-move-2-learnings-2026-05-04.md`
- Catalog architecture (the spec you're implementing): `docs/architecture/DMF Function Catalog Model.md`
- ADR-0012 (Configure split): `docs/decisions/0012-configure-stage-distinct-from-provision.md`
- ADR-0013 (catalog model): `docs/decisions/0013-media-function-catalog-model.md`
- ADR-0014 (AWX project layout): `docs/decisions/0014-awx-project-layout.md`
- Existing NMOS plan (Phase 1+2 implementation reference; Phase 3 superseded by this task): `docs/plans/DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md`
- DMF Platform Plan §9 (two-lane model): `docs/architecture/DMF Platform Plan.md`
- EBU mapping (vocabulary): `docs/architecture/DMF EBU Mapping (2026-04-25).md`
- Move 2 task spec (template for this one): `docs/plans/dmf-platform-move-2-task-2026-04-30.md`

---

## Single-line goal

**Deploy nmos-cpp via the catalog model: bootstrapped during Provision, launched on operator click in dmf-cms, NetBox tag flips, drift detector enforces invariant. Capture what broke. That closes the strategic-review commit gate.**
