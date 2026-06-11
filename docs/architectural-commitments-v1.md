# Move 1 + Catalog — Architectural Commitments v1

> **Status:** Superseded by
> [`docs/reviews/dmf-platform-move-1-learnings-2026-06-04.md`](reviews/dmf-platform-move-1-learnings-2026-06-04.md)
> (2026-06-04). This doc was written **provisionally on 2026-05-05**, before the
> 2026-05-06 **Path A pivot** (ADR-0014/0016) and before the runtime loop was
> verified (2026-05-27/29). Several file references below are pre-Path-A and no
> longer exist under those names — `410-nmos-cpp-provision.yml`,
> `playbooks/configure-media/launch-nmos-cpp.yml`, and the
> `lifecycle-configure.yml` wrapper were obviated when Configure moved from a
> wrapper playbook into the `nmos-cpp` **role** (invoked by an AWX launcher).
> The corrected shape, the evidence, and the ADR-0004 revisit verdict live in the
> superseding learnings doc. Preserved here for decision history.

**Date:** 2026-05-05
**Author:** AI agent session (D4 decisions confirmed by operator)
**Scope:** nmos-cpp as the first catalog entry, proving the full lifecycle loop

---

## 1. What was proven

The following end-to-end path was exercised:

1. **Catalog entry defined** (`dmf-media/catalog/nmos-cpp.yaml`) — YAML manifest with EBU placement, provision artifacts, configure playbooks, health probe
2. **Provision stage** (`lifecycle-provision.yml` + `410-nmos-cpp-provision.yml`) — namespace + ConfigMaps created, zero workloads
3. **NMOS images built** (Sony nmos-cpp from source on ARM64 via Colima) — registry + node binaries pushed to Zot
4. **Configure stage** (`lifecycle-configure.yml` + `launch-nmos-cpp.yml`) — registry StatefulSet + node Deployments launched via AWX UI
5. **NetBox tag flip** (`lifecycle:bootstrapped` → `lifecycle:active`) — automated by the configure playbook
6. **AWX wiring** (`693-awx-integration`) — dmf-runbooks project + job templates created from in-cluster Forgejo
7. **dmf-cms catalog page** (`/catalog` route) — renders catalog entries with lifecycle status
8. **Finalise stage** (`teardown-nmos-cpp.yml`) — workloads removed, tag flipped back to `bootstrapped`
9. **Drift detector** (`lifecycle-operate.yml`) — asserts lifecycle tag matches Helm release presence

---

## 2. Design decisions baked in (the "commitments")

### C1: Configure is distinct from Provision (ADR-0012)
- Provision creates artifacts without launching workloads
- Configure launches on operator action
- Finalise tears down and resets tags
- This split survived the Gate 1 → Gate 2 transition without changes

### C2: Catalog entry = YAML + NetBox tag, joined by dmf-cms (ADR-0013)
- YAML defines intent (image, chart, playbook, health probe)
- NetBox records runtime state (ipam.Service with lifecycle tag)
- dmf-cms reads both to render the catalog page
- v1: dmf-cms uses hardcoded data; v2: reads from ConfigMap

### C3: AWX project layout = hybrid (ADR-0014)
- dmf-runbooks = thin launchers (import_playbook delegates to source repos)
- dmf-media = mirror for AWSC project (roles + playbooks)
- dmf-infra = mirror for AWSC project (infrastructure roles)
- Job templates live in dmf-runbooks project, playbooks delegate via import_playbook

### C4: No v-prefix on image tags (dmf-cms build rules)
- `0.1.0`, not `v0.1.0` — consistent with dmf-cms VERSION convention
- VERSION file at repo root tracks catalog/role version, not upstream image version

### C5: In-cluster Forgejo is the AWX SCM source
- AWX projects point at `forgejo.<lan-host>`, not GitHub
- dmf-media and dmf-infra are mirrored to Forgejo via the forgejo-bootstrap role
- dmf-runbooks is pushed directly to Forgejo by the awx-integration role

### C6: Drift invariant (architecture doc §7)
- `lifecycle:active` ↔ Helm release exists, health probe returns expected status
- `lifecycle:bootstrapped` ↔ Helm release does NOT exist
- The drift detector (`lifecycle-operate.yml`) asserts this for each catalog entry

---

## 3. What was deferred (v2+)

| Item | Reason | Trigger for revisit |
|---|---|---|
| dmf-cms reads catalog from ConfigMap (D4 Option B v2) | v1 hardcoded data is sufficient for single entry | Second catalog entry added |
| Dependency enforcement (Configure blocked if deps not active) | nmos-cpp has no dependencies | First entry with dependencies added |
| Per-user identity propagation through AWX | Single-operator lab | Multi-operator workflow required |
| Parameterised launches (operator-supplied variables at deploy time) | v1 uses role defaults | Operator needs runtime tuning |
| Multi-instance support (dual NMOS registries for HA) | Single registry sufficient | HA requirement emerges |
| Migration of Layer 6 baseline apps to catalog-style | Evaluate value vs disruption | Post-commit gate evaluation |
| Backup/restore policy (RPO/RTO claim) | Experiment-phase stance (ADR-0004); Longhorn replicas + OpenBao Raft are not backup | [Pre-Release Compliance Readiness Plan](plans/DMF%20Pre-Release%20Compliance%20Readiness%20Plan%202026-05-11.md) Tier B.5 — required before first managed-service customer |
| Artifact-side supply chain enforcement (cosign sign-on-push, syft SBOM, Trivy gate at Zot) | Source-side coverage strong; Sony nmos-cpp pin-by-SHA is principle-only today | Pre-Release Compliance Readiness Plan Tier A.5 (bootstrap) → Tier B.6 (CI-enforced) |
| Audit-log retention policy + WORM bucket | k3s audit + S3 archival role exist; bucket is mutable; Loki 7d / Prometheus 6h insufficient for forensic events | Pre-Release Compliance Readiness Plan Tier A.4 |
| Managed-mode OpenBao unseal model | ADR-0011 auto-unseal is acceptable for experiment-phase lab operations, but incompatible with customer-side Shamir custody in managed mode | Pre-Release Compliance Readiness Plan Tier B.1 — retire, supersede, or scope away ADR-0011 automation quorum before first managed-service customer |
| Deployment-mode scope decision | Open question in framework plan §"Open Questions" | **Proposed resolution 2026-05-11 by [ADR-0020](decisions/0020-deployment-scope-and-regulatory-posture.md) — three named modes (OSS / managed `dmfdeploy.io` / flypack); binding once ADR-0020 is Accepted** |

---

## 4. What broke (lessons learned)

### B1: Sony nmos-cpp has no version tags
- **Symptom:** Docker build failed with `--branch v4.1.0`
- **Fix:** Clone master directly (no --branch arg)
- **Commitment:** Pin by commit SHA in production, not tag

### B2: Conan build source in Development/ subdir
- **Symptom:** CMake couldn't find conanfile.txt
- **Fix:** `WORKDIR /src/Development` after clone
- **Commitment:** Document this in the role README

### B3: Colima disk full during build
- **Symptom:** `E: You don't have enough free space in /var/cache/apt/archives/`
- **Fix:** `docker system prune -a -f` reclaimed 17GB
- **Commitment:** Check disk space before any build in the Gate docs

### B4: SSH credential multiline escaping in AWX API
- **Symptom:** AWX Machine credential private key failed to survive escaping layers
- **Fix:** Paste via AWX UI directly (fastest path)
- **Commitment:** Never embed secrets in tracked files (ADR-0007); never attempt multiline secret transport via API when UI is faster

### B5: NetBox drf-spectacular patch partial failure
- **Symptom:** NetBox pod stuck in `Init:0/1`, `FailedMount` for drf-spectacular-patch ConfigMap
- **Fix:** Extract plumbing.py from running pod, apply sed patch, create ConfigMap manually
- **Commitment:** The drf-spectacular patch workflow must fail atomically (ConfigMap creation before Deployment patch)

---

## 5. Files created/modified (by repo)

### dmf-media (7 new, 3 modified)
| File | Action | Purpose |
|---|---|---|
| `catalog/nmos-cpp.yaml` | New | First catalog entry |
| `catalog/README.md` | New | Schema documentation |
| `VERSION` | New | Single source of truth for repo version |
| `roles/nmos-cpp/files/Dockerfile.registry` | New | Registry image build |
| `roles/nmos-cpp/files/Dockerfile.node` | New | Node image build |
| `roles/nmos-cpp/defaults/main.yml` | Modified | Role defaults (namespace, images, logging) |
| `roles/nmos-cpp/tasks/main.yml` | Modified | Lifecycle dispatcher |
| `roles/nmos-cpp/tasks/provision.yml` | New | Provision stage tasks |
| `roles/nmos-cpp/tasks/configure.yml` | New | Configure stage tasks |
| `roles/nmos-cpp/tasks/finalise.yml` | New | Finalise stage tasks |
| `playbooks/410-nmos-cpp-provision.yml` | New | Provision playbook |
| `playbooks/configure-media/launch-nmos-cpp.yml` | New | Launch playbook |
| `playbooks/configure-media/teardown-nmos-cpp.yml` | New | Teardown playbook |
| `playbooks/lifecycle-operate.yml` | New | Drift detector playbook |
| `playbooks/tasks/drift-check.yml` | New | Drift check tasks |
| `roles/nmos-cpp/README.md` | Modified | Role documentation |

### dmf-infra (1 new, 4 modified)
| File | Action | Purpose |
|---|---|---|
| `k3s-lab-bootstrap/lifecycle-configure.yml` | New | Configure stage wrapper |
| `k3s-lab-bootstrap/lifecycle-provision.yml` | Modified | Header updated, nmos-cpp import added |
| `roles/stack/operator/forgejo-bootstrap/defaults/main.yml` | Modified | Mirror repos added |
| `roles/stack/operator/forgejo-bootstrap/tasks/main.yml` | Modified | Mirror config + README push |
| `roles/stack/operator/awx-integration/defaults/main.yml` | Modified | Catalog projects + job templates |
| `roles/stack/operator/awx-integration/tasks/main.yml` | Modified | Forgejo push + job template creation |
| `roles/stack/operator/awx-integration/tasks/catalog-project.yml` | New | Parameterized project creation |
| `playbooks/runbooks/media-launch-nmos-cpp.yml` | New | Forgejo push source |
| `playbooks/runbooks/media-finalise-nmos-cpp.yml` | New | Forgejo push source |

### dmf-runbooks (3 new)
| File | Action | Purpose |
|---|---|---|
| `playbooks/launch-nmos-cpp.yml` | New | Thin launcher (configure) |
| `playbooks/teardown-nmos-cpp.yml` | New | Thin launcher (finalise) |
| `README.md` | New | Project documentation |

### dmf-cms (1 new, 3 modified)
| File | Action | Purpose |
|---|---|---|
| `frontend/src/pages/Catalog/index.tsx` | New | Catalog page component |
| `frontend/src/App.tsx` | Modified | Added `/catalog` route |
| `frontend/src/components/Sidebar.tsx` | Modified | Added "Catalog" nav item |
| `src/dmf_cms/main.py` | Modified | Added `GET /api/catalog/entries` endpoint |

### docs (3 new ADRs, 1 new gate doc, 1 new plan)
| File | Action | Purpose |
|---|---|---|
| `docs/decisions/0012-configure-stage-distinct-from-provision.md` | New | ADR-0012 |
| `docs/decisions/0013-media-function-catalog-model.md` | New | ADR-0013 |
| `docs/decisions/0014-awx-project-layout.md` | New | ADR-0014 |
| `docs/plans/Move 1 Gate 1 — Build NMOS + Run Provision.md` | New | Gate 1 execution guide |
| `docs/plans/Move 1 Gate 2 — AWX Integration + Launch NMOS.md` | New | Gate 2 execution guide |
| `docs/plans/dmf-platform-move-1-task-2026-05-04.md` | New | Task spec |
| `docs/architecture/DMF Function Catalog Model.md` | New | Catalog architecture |

---

## 6. Next steps

1. **Commit all repos** — one commit per repo, related messages
2. **Run the full lifecycle again** (provision → configure → finalise → operate) to prove the drift detector works end-to-end
3. **Add second catalog entry** — triggers v2 ConfigMap data source for dmf-cms
4. **Evaluate Layer 6 baseline apps for catalog migration** — the post-commit gate

---

## 7. References

- Strategic review: `docs/reviews/dmf-platform-strategic-review-2026-04-30.md`
- Move 2 learnings: `docs/reviews/dmf-platform-move-2-learnings-2026-05-04.md`
- NMOS plan: `docs/plans/DMF NMOS Registry + Crosspoint Demo Plan 2026-05-04.md`
- EBU mapping: `docs/architecture/DMF EBU Mapping (2026-04-25).md`
- Platform plan: `docs/architecture/DMF Platform Plan.md`
