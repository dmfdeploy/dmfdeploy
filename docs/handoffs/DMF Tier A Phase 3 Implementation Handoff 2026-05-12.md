# DMF Tier A — Phase 3 Implementation Handoff (2026-05-12)

**Plan reference:** [DMF Tier A Phase Execution Plan](../plans/DMF%20Tier%20A%20Phase%20Execution%20Plan%202026-05-11.md), §Phase 3 (vertical-resilience playbooks).

**Phase 3 commit chain on `dmf-infra` main:**

```
438af59  feat(eso): object-storage-credentials role + 2 ClusterSecretStores
c62b923  feat(longhorn): backup-target role with UPPERCASE Secret template
61c9895  feat(longhorn): daily RecurringJob (group=default, retain=7)
0c2109a  feat(openbao): raft-snapshot CronJob role + scoped k8s-auth
f732870  feat(postgres): per-app pg_dump CronJob template
8641b4c  feat(zot): OCI-format registry mirror to B2
b9afb1a  feat(resilience-verify): two-track synthetic round-trip + Object Lock test
9187aeb  feat(playbooks): wire vertical-resilience track into post-seed
e83b135  feat(bootstrap-verify): import resilience-verify
```

**Phase 3 commit chain on `dmf-env` main:**

```
f907a80  feat(b2-buckets): per-bucket lifecycle rules (90d snapshots, 365d app-backups)
```

**Phase 3 commit chain on `dmfdeploy` main:**

```
a23ef7b  docs(plan): Phase 3 per-actor briefs + Frozen Secret Contract
<this commit>  docs(handoff): Tier A Phase 3 implementation record
```

**Status:** Phase 3 of 6 complete in code; pre-flight + live verify
pending operator action (see §6). Every Tier-A backup data class now
has a daily/weekly pipeline landing in the right bucket with provider-
managed SSE. Operator must rerun `b2-buckets.sh ensure <env>` for both
envs before the lifecycle rules apply.

This handoff records what landed and where to look. Bug fixes that
were applied during integration are called out alongside the originating
slice.

---

## 1. Purpose

After Phase 3, the cluster's vertical-resilience track:

- Provisions per-bucket OpenBao AppRoles + ESO ClusterSecretStores +
  ExternalSecrets in consumer namespaces (the **Frozen Secret Contract**
  from the execution plan).
- Deploys four daily/weekly backup CronJobs:
  - `openbao-raft-snapshot` (daily 02:30 UTC, openbao-system)
  - `pg-backup-<app>` (daily 03:00 UTC, per-app namespace × 4 apps)
  - `zot-mirror` (weekly Sun 04:00 UTC, zot)
  - Longhorn `RecurringJob` (daily 01:00 UTC, all volumes via default group)
- Configures Longhorn's `BackupTarget` against the app-backups B2 bucket
  with a UPPERCASE-keyed Secret materialized by a per-namespace
  ExternalSecret template.
- Provides a two-track `resilience-verify` smoke test (in-cluster Jobs
  for ESO buckets, host-side `delegate_to: localhost` for audit with
  Object Lock COMPLIANCE delete-refusal test).

---

## 2. Cross-pane collaboration log

Phase 3 was authored across four actors. Documenting here because the
attribution chain matters for future debugging:

| Slice | Actor | Output |
|---|---|---|
| Longhorn/bao/mc upstream research | Subagent (Explore) | Longhorn 1.10.1 CR shape, `bao operator raft snapshot save` policy minimums, `mc mirror` flag semantics |
| `object-storage-credentials` role | qwen-left | 4 files, 545 lines (then integration fixes applied) |
| 3 backup CronJob roles | qwen-right | 18 files, 886 lines (then integration fixes applied) |
| Longhorn roles + resilience-verify + integration + commits | Claude | 12 files, 9-commit slicing |
| Cross-review (twice) | Claude (middle-left pane) | 10 substantive findings folded back into integration |

The cross-review identified two CRITICAL bugs not visible to the
authors of each slice (BAO_ADDR env-var mismatch + missing script
ConfigMap wiring in openbao-raft-snapshot). Both fixed before
commits.

---

## 3. Integration fixes applied during the orchestrator (Claude) step

These are bugs / refinements that surfaced after qwen-left + qwen-right
reported their work complete. All folded into the originating slice's
commit:

### 3.1 — qwen-left (commit 438af59)

- **Path naming**: brief said `<logical-dashed>` for OpenBao paths;
  Phase 2 `seed-bao` actually stored at `<logical-underscored>`. Fixed
  all OpenBao policy/AppRole/path references to use underscored form;
  K8s resource names still use `logical_dashed` (derived in tasks Step 10).
- **Step 7 SECRET_ID stdin starvation**: original only piped
  `OPENBAO_TOKEN` into `kubectl exec -i`; the inner `read -r SECRET_ID`
  read empty stdin. Fixed: `printf '%s\n%s\n' "$OPENBAO_TOKEN" "$SECRET_ID"`
  with matching `IFS= read -r SECRET_ID` inside the pod.
- **Defaults rot**: stripped dead `object_storage_secret_name_template`
  and `object_storage_openbao_path_template` template vars; corrected
  the misleading "logical-dashed" comment at the top of defaults.
- **Idempotency interrupted-state hazard**: added Step 4b that checks
  binding presence at `secret/platform/eso-bindings/object-storage-
  <logical>`. Modified Step 6's condition to fire when EITHER role-id
  OR binding is missing (force-rotate the secret-id in the recovery
  case). Without this fix, an interrupted run that created the AppRole
  but didn't store the binding would explode on every subsequent run.

### 3.2 — qwen-right openbao-raft-snapshot (commit 0c2109a)

- **BLOCKER — BAO_ADDR**: CronJob template originally set
  `OPENBAO_ADDR` env var; the `bao` CLI reads `BAO_ADDR` (Vault
  legacy). Renamed.
- **BLOCKER — missing script ConfigMap**: `snapshot.sh.j2` existed as
  a raw bash template but was never deployed as a K8s ConfigMap, and
  no `/scripts` volume backed the CronJob's `command:`. Renamed to
  `snapshot-script.yml.j2`, wrapped as a ConfigMap, added a deploy
  task in `tasks/main.yml`, and added `snapshot-script` volume +
  `/scripts` volumeMount in the CronJob template.
- **login endpoint**: original script hit `auth/<mount>/role/<role>`
  (the role-creation endpoint). Replaced with
  `bao login -method=kubernetes role=<role> -token-only` which uses
  the standard login endpoint and auto-detects the SA token at
  `/var/run/secrets/.../token`.
- **image switch**: `python:3.12-slim` → `openbao/openbao:latest` main
  + `amazon/aws-cli` initContainer copying `aws` into a shared-bin
  emptyDir.

### 3.3 — qwen-right postgres-backups (commit f732870)

- **image**: `python:3.12-slim` (no pg_dump, no awscli) → `postgres:16`
  main + `amazon/aws-cli` initContainer (shared-bin pattern).
- **README**: documented pg_dump 16's supported source range
  (PG 9.2 through 16 inclusive; fails against PG 17+).

### 3.4 — qwen-right zot-mirror (commit 8641b4c)

- **Full rewrite from PVC-mount to OCI HTTP API**. qwen-right's first
  draft mounted the Zot data PVC directly (assumed claim name `zot-data`,
  actually `data-zot-0` from the StatefulSet's volumeClaimTemplate).
  Longhorn RWO single-attach would have blocked this even readOnly.
  Rewritten pipeline: `skopeo sync --src docker --dst dir` over Zot's
  in-cluster HTTP API → `aws s3 sync` the OCI dir to B2. No PVC mount.
  Scratch via 25Gi emptyDir (Zot PVC is 20Gi).
- **Zot pull credentials**: new ExternalSecret in `zot` namespace
  pulling password from `secret/apps/zot/admin` via the existing
  `openbao` ClusterSecretStore (eso-reader policy already covers
  `secret/data/apps/+/admin`).
- **Polish from cross-review**: dropped redundant `aws` binary copy
  in initContainer; switched script to `#!/bin/bash` with
  `set -euo pipefail`; fixed README §3 recovery to mandate restoring
  via the HTTP API (not by dumping OCI dir into Zot's filesystem layout —
  different on-disk format).

---

## 4. Frozen Secret Contract (final form)

Both backup-credential paths emit K8s Secrets with this exact shape:

| Secret name | Namespaces | Keys |
|---|---|---|
| `s3-creds-openbao-snapshots` | `openbao-system` | `bucket`, `endpoint`, `region`, `access_key_id`, `secret_access_key` |
| `s3-creds-app-backups` | `awx`, `netbox`, `authentik`, `forgejo`, `zot` | same |
| `longhorn-s3-creds` | `longhorn-system` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINTS`, `VIRTUAL_HOSTED_STYLE` (UPPERCASE, re-keyed via ExternalSecret template) |
| `zot-mirror-creds` | `zot` | `password` (Zot admin plaintext, from `secret/apps/zot/admin`) |

Audit creds: NOT in any in-cluster Secret. They flow via inventory
variables from Phase 1's `bootstrap-secrets.sh export-vars`.

---

## 5. Deliberate deviations from existing repo patterns

| What | Where | Why |
|---|---|---|
| Idempotent AppRole secret-id (no `-force` on reconcile) | `object-storage-credentials/tasks/main.yml` Steps 4-7 | Avoid ExternalSecret reconcile churn; backup CronJobs need stable creds. `-force` only in the interrupted-state recovery path. |
| k8s SA auth (NOT AppRole) for raft snapshot token | `openbao-raft-snapshot` | Identity is the pod's SA; no secret-id to rotate or store. Smaller blast radius. Logged for retroactive `autonomous-decisions.md` entry when the agentic harness goes live. |
| HTTP-API mirror (NOT PVC mount) for Zot | `zot-mirror` | Longhorn RWO single-attach blocks concurrent CronJob mount. HTTP API is source of truth anyway. |
| Two-track resilience-verify (in-cluster + host-side) | `resilience-verify` | Audit creds live in Phase 1 inventory vars, NOT ESO. Forces host-side `delegate_to: localhost` for the audit track. |
| Lowercase Frozen Contract keys + per-consumer UPPERCASE template for Longhorn | `longhorn-backup-target` ExternalSecret | Longhorn 1.10.1 requires UPPERCASE; rest of the Tier A consumers use lowercase. Contract stays clean; consumer-specific quirk contained to the role. |

---

## 6. Operator pre-flight

Before the Phase 3 backup CronJobs land daily/weekly objects:

1. **Apply b2-buckets lifecycle rules** (commit `f907a80` in dmf-env).
   Idempotent — safe to rerun:
   ```bash
   DMF_BOOTSTRAP_BUNDLE_DIR=... dmf-env/bin/b2-buckets.sh ensure hetzner-arm
   DMF_BOOTSTRAP_BUNDLE_DIR=... dmf-env/bin/b2-buckets.sh ensure aliyun
   ```
   Verify with `show <env>`: each bucket's `lifecycle:` line should be
   non-empty for openbao-snapshots (90d) and app-backups (365d); audit
   should show `lifecycle: none` (Object Lock owns retention).

2. **Confirm OpenBao seed paths exist** (Phase 2's output):
   ```bash
   kubectl -n openbao exec openbao-0 -- sh -c '
     bao kv get secret/platform/object-storage/openbao_snapshots
     bao kv get secret/platform/object-storage/app_backups
     bao kv get secret/platform/object-storage/audit
   '
   ```

3. **Run vertical-resilience track** (the 6 imports from
   `bootstrap-provision-post-seed.yml`):
   ```bash
   bin/run-playbook.sh hetzner-arm \
     ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml \
     --tags vertical-resilience
   ```

4. **Run resilience-verify**:
   ```bash
   bin/run-playbook.sh hetzner-arm \
     ../dmf-infra/k3s-lab-bootstrap/bootstrap-verify.yml \
     --tags vertical-resilience
   ```
   For 30-minute payload-path proof instead of 48h calendar soak, add:
   ```
   -e resilience_verify_soak_prewarm=true
   ```

---

## 7. Suggested reviewer checklist

- [ ] All 9 Phase 3 commits present in `dmf-infra` main with the
      expected slice attribution
- [ ] `dmf-env/bin/b2-buckets.sh show <env>` reports `lifecycle:`
      non-empty for openbao-snapshots + app-backups
- [ ] `tofu validate` still clean in `dmf-env/terraform/hetzner-arm/`
      (no Phase 3 churn there)
- [ ] `bash -n` clean for all amended scripts:
      - `dmf-infra/.../resilience-verify/tasks/verify-host-audit.yml`
      - `dmf-env/bin/b2-buckets.sh`
- [ ] `ansible-playbook --syntax-check` (run with run-playbook.sh dry
      mode) passes for the 7 vertical-resilience playbooks
- [ ] After playbook run: `kubectl get clustersecretstore` shows
      `openbao-app-backups` and `openbao-openbao-snapshots` both Ready
- [ ] After playbook run: `kubectl get externalsecret -A` shows all
      ExternalSecrets `SecretSynced=True`
- [ ] After playbook run: `kubectl -n longhorn-system get backuptarget`
      shows `default` reachable
- [ ] After resilience-verify: `Track A` Jobs all show
      "PASS: synthetic round-trip OK"; `Track B` shows
      "PASS: Object Lock COMPLIANCE delete refused as expected"
- [ ] After 48h natural soak: B2 buckets contain one object per
      backup CronJob (verify via `aws s3 ls` per bucket)
- [ ] gitleaks pre-commit passed on every Phase 3 commit
      (no IPs, credentials, operator-identity paths in diffs)

---

## 8. Known open items for Phase 4 and beyond

- **PG version range**: `pg_dump 16` covers source servers PG 9.2-16.
  Bumping any app to PG 17+ requires bumping
  `postgres_backups_image` to a matching major version.
- **Longhorn multi-target binding**: upstream issue #11421 (open as
  of 2026-05-12). If we add a second BackupTarget, RecurringJob will
  need refactoring to use `recurringJobSelector` labels on volumes.
- **--soak-prewarm collision risk for hourly schedules**: documented
  in `resilience-verify/README.md`. If any backup CronJob bumps to
  hourly, add a label-selector guard before `kubectl create job
  --from=cronjob`.
- **PG Secret name conventions**: `postgres_backups_app_overrides`
  in defaults names each app's DB Secret + key. These are conventions
  matching in-tree role defaults; verify against actual deployed
  Secret names before running against prod env (`kubectl -n <app>
  get secret <expected-name>`).
- **AppRole secret-id rotation**: operator-initiated only (no
  reconcile churn). Manual rotation procedure: TBD — Phase 5
  hardening item.
- **OSS publish to Docker Hub**: deferred to Phase 4 (cosign signing
  must happen first so published images carry SBOMs + signatures).
- **Cache hydration from public registries → Zot**: deferred. May
  be implemented as on-demand operator script rather than scheduled.
- **autonomous-decisions.md retroactive entry**: the AppRole →
  k8s-SA auth pivot for `openbao-raft-snapshot` is the kind of
  contract-changing choice the agentic harness's rubric would halt-
  and-surface on. Was approved in-flight via cross-pane discussion;
  log retroactively when the harness goes live.
