# DMF Bootstrap Implementation — Progress Handoff

**Date:** 2026-05-08
**Status:** Tier 1 (static scaffolding) complete; Tier 2 (cluster-touching) pending live cluster
**Audience:** Next session picking up bootstrap work
**Review:** `docs/reviews/dmf-bootstrap-tier1-review-2026-05-08.md` — Concern 1 (P0) fixed; Concern 2 (P2) annotated and deferred.

## What's done

### dmf-env (private, no-remote)

| File | What |
|---|---|
| `bin/bootstrap-secrets.sh` | 7 subcommands: `init`, `doctor`, `export-vars`, `seed-bao`, `seed-awx-control-node-ssh`, `status`, `rotate` |
| `.sops.yaml` | SOPS age recipient scaffold (operator must add their public key) |
| `docs/initial-data-gathering.md` | §2b added: SOPS/age key setup operator instructions |

The script is fully functional for:
- `init` — collects provider tokens from existing operator config files, generates bootstrap admin password + k3s token, encrypts bundle with SOPS+age
- `doctor` — validates age key, bundle decryptability, schema, entropy, no break-glass leakage, no plaintext sibling, not-in-git-tree
- `export-vars` — decrypts bundle to 0600 Ansible vars JSON (maps all `vault_*` names, compatibility copies for transition)
- `seed-bao` — reads bundle, checks Bao unsealed, collision detection (fail on differing values, no-op on same), writes platform + app-local admin paths via stdin transport
- `seed-awx-control-node-ssh` — reads SSH privkey from configurable path, validates PEM format, fingerprint-based idempotency, writes to Bao via stdin
- `status` — metadata-only report (no secret values)
- `rotate` — bootstrap_admin.password only; cluster.k3s_token explicitly blocked

### dmf-infra (public)

| File | What |
|---|---|
| `bootstrap-provision-pre-seed.yml` | Thin import_playbook wrapper: 219-host-verify (+bootstrap-preflight tag), 200-baseline, 210-harden, 300-k3s through 339-verify, 100-openbao, 120-network-policies, 100-eso, 110-eso-rotation, 120-ops-admin-rotation, 110-authentik, 190-breakglass-verify, 191-zot-oidc |
| `bootstrap-provision-post-seed.yml` | Thin import_playbook wrapper: monitoring base (prometheus, loki, grafana, promtail, 190-verify) + Layer 6 vanilla apps (600-landing, 610-netbox, 620-forgejo, 640-awx, 650-dmf-cms) |
| `bootstrap-configure.yml` | Thin import_playbook wrapper: 691-netbox-sot, 692-forgejo-bootstrap, 693-awx-integration, 694-born-inventory, 696-698 CMS token wiring, 699-cms-smoke-test |
| `bootstrap-verify.yml` | Stub with placeholder debug play; TODO comment lists target checks |
| `lifecycle-provision.yml` | Refactored: imports the 4 bootstrap wrappers in sequence (compatibility wrapper) |
| `lifecycle-configure.yml` | Converted to doc stub pointing at dmf-runbooks for workload configure |
| `site.yml` | Comments corrected to reflect new bootstrap split |

**All wrappers pass `ansible-playbook --syntax-check`.** `lifecycle-provision.yml` produces 44 plays (was 43; +1 is bootstrap-verify placeholder). Task list is behaviorally equivalent.

### Role defaults — credential elimination

Every `default('changeme')`, `default('admin')`, `default('dev')`, and `default('password')` in credential context has been removed:

| Role | Before | After |
|---|---|---|
| forgejo/defaults | `default('changeme')` | `default(vault_bootstrap_admin_password \| mandatory)` |
| forgejo-bootstrap/defaults | `default('changeme')` | `default(vault_bootstrap_admin_password \| mandatory)` |
| netbox/defaults | `default('changeme')` | `default(vault_bootstrap_admin_password \| mandatory)` |
| netbox-sot/defaults | `"admin"` + `default('changeme')` | `default(vault_bootstrap_admin_username)` + `default(vault_bootstrap_admin_password \| mandatory)` |
| grafana/defaults | `default('admin')` | `default(vault_bootstrap_admin_password \| mandatory)` |
| zot/defaults | `"admin"` + `default('changeme')` | `default(vault_bootstrap_admin_username)` + `default(vault_bootstrap_admin_password \| mandatory)` |
| awx/defaults | `default('changeme')` | `default(vault_bootstrap_admin_password \| mandatory)` |
| awx-integration/defaults | nested `default('changeme')` | `default(vault_bootstrap_admin_password \| mandatory)` |
| cms/tasks/main.yml | `default('admin')` | `default(vault_bootstrap_admin_username \| default('dmfadmin'))` |

**Credential-grep gate: zero hits.**

### dmfdeploy (umbrella docs)

| File | What |
|---|---|
| `docs/baselines/lifecycle-provision-list-tasks-baseline-2026-05-08.txt` | Pre-refactor --list-tasks output |
| `docs/baselines/lifecycle-provision-list-tasks-after-refactor-2026-05-08.txt` | Post-refactor --list-tasks output |
| `docs/questions/DMF Bootstrap Implementation Questions 2026-05-08.md` | 10 Q&A + implementation status matrix |
| `STATUS.md` | HUMAN-START section updated |

## What's queued but not done

### Tier 2 — requires live cluster

1. **seed-bao live test** — `bin/bootstrap-secrets.sh seed-bao hetzner-arm` against running OpenBao. Collision detection needs to be exercised (write once, re-run → no-op, manually change value → fail).

2. **seed-awx-control-node-ssh live test** — `DMF_AWX_CONTROL_NODE_SSH_PATH=<path> bin/bootstrap-secrets.sh seed-awx-control-node-ssh hetzner-arm`. Verify AWX Machine credential creation path works end-to-end.

3. **Role task splits** — The roles still mix provision and configure tasks internally. Target pattern:
   ```
   roles/stack/operator/<app>/
     tasks/main.yml  (dispatches by app_stage var)
     tasks/provision.yml
     tasks/configure.yml
     tasks/verify.yml
   ```
   Apps to split: authentik, zot, grafana, netbox, forgejo, awx. (forgejo-bootstrap and awx-integration are configure-only; netbox-sot is configure-only; cms is provision-only.)

4. **Bootstrap Configure OIDC admin seeding** — Authentik role needs to create the shared bootstrap admin identity and map to admin/superadmin groups. Currently Authentik uses its own `akadmin` pattern.

5. **Audit policy extension** (Specific Fix #19) — Extend Kubernetes audit policy to cover `secret/platform/*` and `secret/apps/*/admin` at Metadata level. Add bootstrap-verify assertion.

### Open questions to resolve

From the plan (`DMF Bootstrap Provision Configure Split Plan 2026-05-07.md`):

- **Plan Q2** (rotation timing) — before Phase 4 complete. Recommendation: keep rotation out of bootstrap, document in `lifecycle-operate.yml` + maintenance runbook.
- **Plan Q9** (Authentik `akadmin` deprecation) — before Phase 3 lands Authentik role change. Recommendation: explicit hardening play in `lifecycle-operate.yml` + Bootstrap Verify warning.
- **Plan Q11 / Design Q7** (audit-policy verification ownership) — when implementing Specific Fix #19.
- **Plan Q1, Q3, Q4** (cosmetic) — defer or decide opportunistically.
- **Plan Q10 / Design Q6** (per-secret data classification) — defer to follow-up framework-plan doc.

### Deferred from the bootstrap work

- `bootstrap-platform.sh` orchestrator (A1 — defer until Phase 4 stabilizes)
- `lifecycle-configure.yml` retention vs removal (A5 — converted to stub, decision deferred)
- `219-host-verify.yml` rename (A8 — retagged only, rename deferred indefinitely)
- AWX `awx-runner-sa` SA + RBAC cleanup (from pivot plan Phase 5)
- NetBox inventory CIDR fix (outstanding follow-up)

## Cluster state

**No live cluster exists.** All work was static/Tier 1. Before any Tier 2 work:

```bash
kubectl config current-context
kubectl -n openbao get pods
kubectl -n openbao exec <pod> -- bao status
kubectl -n openbao exec <pod> -- bao kv get secret/platform/bootstrap_admin 2>&1 | head -5
```

Decision tree (from A9):
- **Fresh / bootstrap_admin absent:** Tier 2 open
- **Mid-state / platform paths exist with different values:** stop, coordinate with user
- **Unclear:** do remaining Tier 1 static work first

## How to resume

1. Boot ritual (git fetch/pull, read STATUS.md, read this handoff, git status in each repo)
2. If live cluster exists: run the 5 kubectl checks above → follow A9 decision tree
3. If no live cluster: continue with remaining static work (role task splits, audit policy)
4. When ready to commit: `dmf-infra` changes are safe to push public; `dmf-env` has no remote
