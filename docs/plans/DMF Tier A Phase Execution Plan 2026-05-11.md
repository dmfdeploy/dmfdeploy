---
status: draft
date: 2026-05-11
---
# DMF Tier A Phase Execution Plan

**Status:** Living. Updated as each phase progresses.
**Date:** 2026-05-11
**Pairs with:**
[Pre-Release Compliance Readiness Plan](DMF%20Pre-Release%20Compliance%20Readiness%20Plan%202026-05-11.md)
(the *what*), [ADR-0020](../decisions/0020-deployment-scope-and-regulatory-posture.md) (deployment scope), [`docs/processes/pre-release-compliance-checklist.md`](../processes/pre-release-compliance-checklist.md) (operator gate list).

This doc is the *how* — agent-ready per-phase briefs that a fresh
sub-agent, Qwen pane, or future Claude session can pick up cold without
needing the full conversation history. Each phase below is self-contained:
goal, inputs, outputs, dispatch matrix, per-actor briefs, acceptance.

---

## How to use this document

Each phase has the same shape:

| Section | Purpose |
|---|---|
| **Goal** | One paragraph. What is true at end of phase that wasn't before. |
| **Inputs** | Decisions / ADRs / files the actor must read before touching anything. |
| **Outputs** | New files + amended files + expected commits. Verifiable. |
| **Dispatch matrix** | Which actor (subagent / qwen-left / qwen-right / Claude) does which slice. |
| **Per-actor briefs** | Copy-paste-ready prompts for the lifting actors. Self-contained: an actor reading only their brief should be able to execute. |
| **Acceptance criteria** | What must be true to call the phase done. Verifiable, not handwaved. |

**Dispatch convention** (per `feedback_delegate_lifting_work.md` memory):

| Actor | Best for | Tool call |
|---|---|---|
| **Subagent (Explore)** | Read-heavy lookups, multi-area research, parallel exploration | `Agent` tool with `subagent_type: Explore` |
| **Subagent (general-purpose)** | Bounded, one-shot code/doc writing where the spec fits in one prompt | `Agent` tool with `subagent_type: general-purpose` |
| **`qwen-left`** (pane 0, `dmfdeploy` cwd) | Multi-file edits, parallel inline lifting; operator can watch | `~/.claude/skills/agent-bridge/bin/agent-bridge send qwen-left -` |
| **`qwen-right`** (pane 1, `dmfdeploy` cwd) | Same as qwen-left; second parallel lane | `~/.claude/skills/agent-bridge/bin/agent-bridge send qwen-right -` |
| **Claude (this pane)** | Plan-holding, gate sequencing, verification, commits, pushes, handoffs | direct |

**Every dispatch brief MUST include the safety-rail blocks from**
[`docs/processes/agent-prompt-templates.md`](../processes/agent-prompt-templates.md).
Choose a profile (READ_ONLY_RESEARCH / CODE_EDIT / LIVE_INFRA_MUTATION /
CLUSTER_OPS / DOCS_ONLY), copy its rails verbatim into the brief. Per
the operator's 2026-05-11 direction, there is no external review gate;
the orchestrator's pre-commit discipline + the rails are the only
safety net. The templates doc also logs the four real incidents from
Phase 1 + Phase 2 that drove each rail.

**Always `/clear` a Qwen pane before sending a new brief:**

```
~/.claude/skills/agent-bridge/bin/agent-bridge send qwen-X /clear
```

Then send the brief. Qwen panes accumulate context across uses;
without `/clear` the new brief gets interpreted in the shadow of the
prior task.

Verify Qwen panes are still in `dmfdeploy` cwd before dispatching:

```
~/.claude/skills/agent-bridge/bin/agent-bridge list
```

If a pane shows a different cwd, either retarget it or fall back to a
subagent for that slice.

**Codex re-review** is the standard gate after each phase commit. Ping
via `agent-bridge send codex - <<'EOF' … EOF`. Treat codex output as
authoritative; address all findings before moving to the next phase.

---

## Phase 1 — Audit-log policy correctness ✅ DONE

**Commit chain on `dmf-infra`** (Phase 1 final):

```
68a1fa1  feat(audit-log): compliance-grade retention + WORM archival + chrony
e914898  fix(audit-log): address codex review findings on Phase 1 wiring + correctness
a67264e  fix(audit-log): second codex review — ADR-0007 cred path + always-run precheck + workdir
2320046  docs(promtail): clarify Loki compactor deletes (not archives) past-retention entries
```

**Commit chain on `dmfdeploy`** (handoff + plan/checklist updates):

```
d1fc51a  docs(handoff): Tier A Phase 1 implementation record + B2 compatibility check
e901ba5  docs: address codex review feedback on Phase 1 handoff + checklist
a700db2  docs: second-pass codex review — plan §138 retention + handoff SHAs + audit-log §
9a34ce0  docs(handoff): drop stale /tmp + env-file + pre-seed references
```

**Reviewer-checkable record:**
[`docs/handoffs/DMF Tier A Phase 1 Implementation Handoff 2026-05-11.md`](../handoffs/DMF%20Tier%20A%20Phase%201%20Implementation%20Handoff%202026-05-11.md).

**Codex reviews passed:** initial + 2 re-review passes + 1 cleanup pass.

Cluster has not yet been rebooted with these changes. Reapplication is
out of scope for the phase; operator schedules the run.

---

## Phase 2 — Object-storage setup ✅ DONE (with pivot)

**Commit chain on `dmf-env`:**

- `d341350` — `feat(object-storage): generic-s3 Terraform module + seed bundle extension` (initial Terraform-managed attempt)
- `725212b` — `feat(b2-diag): operator-runnable B2 credential diagnostic script`
- `0dcb263` — `feat(b2-buckets): native-API bucket setup for hetzner-arm + aliyun envs` (the pivot — buckets live)

**Commit chain on `dmfdeploy`:**

- `41a14df` — `docs(handoff): Tier A Phase 2 implementation record` (initial)
- `576a938` — `docs(plan): mark Phase 2 done in execution plan + record commit chain`
- 2026-05-12 chain: Phase 2 docs sync to b2-buckets.sh pivot + live-apply state

**Reviewer-checkable record:** [`docs/handoffs/DMF Tier A Phase 2 Implementation Handoff 2026-05-11.md`](../handoffs/DMF%20Tier%20A%20Phase%202%20Implementation%20Handoff%202026-05-11.md).

**What landed live:** Six B2 buckets across both envs
(`dmf-{audit,openbao-snapshots,app-backups}-{hetzner-arm,aliyun}`) in
region `us-west-001`. Audit buckets have Object Lock enabled; all six
have SSE-B2 AES256 + a permissive CORS rule. Verified via `bin/b2-buckets.sh
show <env>` for both envs.

**The pivot:** The Terraform-managed approach landed initially (commit
`d341350`) but live-apply hit three distinct AWS-provider × B2
incompatibilities (`NoSuchCorsConfiguration` casing mismatch on every
bucket Read; `PutBucketTagging` 501; `PutBucketEncryption` side-paths
clobber CORS state). Pivoted to a B2-native script at
`dmf-env/bin/b2-buckets.sh` (+ `lib/b2-buckets.py`, pure-stdlib) that
calls B2's native API directly. The Terraform module is retained in the
tree but commented out in `terraform/hetzner-arm/main.tf` — kept as a
template for the eventual migration to the b2-native Terraform provider.

**Region note:** Both envs are pinned to `us-west-001` (the operator's
B2 account region). EU-region migration deferred to per-env region
choice in the init script (operator decision 2026-05-12).

**Dispatch executed:** Subagent (B2 + AWS-provider research) + qwen-left
(Terraform module + main.tf wiring) + qwen-right (bootstrap-secrets.sh +
manifests + README) ran in parallel for the initial Terraform attempt.
Claude integrated, ran the live-apply attempts that surfaced the
incompatibilities, then wrote the b2-buckets.sh replacement and the
documentation sync.

### Goal

`dmf-env` knows how to provision three S3-compatible buckets per env via
Terraform against any S3-compatible endpoint (Backblaze B2 for the live
`hetzner-arm` env per the 2026-05-11 BYO-object-storage decision), and
the seed bundle schema is extended so OpenBao learns those bucket
coordinates + credentials at `seed-bao` time. After Phase 2, OpenBao
contains `secret/platform/object-storage/{audit,openbao-snapshots,app-backups}`
ready for Phase 3 to consume via ESO.

### Inputs

Required reading before any edit:

- [ADR-0020](../decisions/0020-deployment-scope-and-regulatory-posture.md) — Mode A "no outbound to dmfdeploy.io" + customer-side credential custody constraint.
- [ADR-0007](../decisions/0007-secrets-never-in-argv.md) — secrets discipline.
- Existing Terraform module pattern: `dmf-env/terraform/modules/hetzner/cluster/` (the cluster module that the existing `hetzner-arm/main.tf` consumes).
- Existing bundle script: `dmf-env/bin/bootstrap-secrets.sh` — read the `init`, `doctor`, and `seed-bao` subcommands to understand the existing schema before extending it.
- Existing manifest: `dmf-env/manifests/hetzner-arm.yaml` — read top-level keys so the new `object_storage:` block fits the convention.
- §3.3 + §3.4 of the readiness plan for the per-bucket retention contract and the AWS-provider-against-B2 design intent.
- Phase 1 audit-log-archival role: `dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/{defaults,tasks}/main.yml` — Phase 2 must produce credentials that satisfy this role's variables (`audit_log_aws_access_key_id`, `_secret_access_key`, `_region`, `_s3_endpoint`, `_s3_bucket`).

### Outputs

**New files:**

- `dmf-env/terraform/modules/generic-s3/object-storage/` — Terraform module:
  - `variables.tf` — `bucket_names` (map: audit / openbao_snapshots / app_backups → string), `endpoint`, `access_key_id`, `secret_access_key`, `region`, `object_lock_retention_days` (default 365).
  - `versions.tf` — `aws` provider pinned to a recent stable (≥ 5.x) with `s3_use_path_style = true` and `skip_credentials_validation = true` so the provider works against non-AWS endpoints.
  - `main.tf` — three `aws_s3_bucket` resources; `aws_s3_bucket_versioning` (enabled) on all three; `aws_s3_bucket_object_lock_configuration` (COMPLIANCE) only on the audit bucket; `aws_s3_bucket_server_side_encryption_configuration` (AES256) on all three.
  - `outputs.tf` — bucket-id outputs + a flattened map suitable for the manifest.

**Amended files:**

- `dmf-env/terraform/hetzner-arm/main.tf` — add `module "object_storage"` call passing the bucket names + endpoint + credentials (sourced from a fresh Terraform variable file or environment, NOT committed).
- `dmf-env/manifests/hetzner-arm.yaml` — add `spec.object_storage:` block recording bucket names + endpoint + region (NOT credentials).
- `dmf-env/bin/bootstrap-secrets.sh` — extend the bundle schema to accept three new blocks under a new `object_storage:` key (audit / openbao_snapshots / app_backups), each with `bucket`, `endpoint`, `region`, `access_key_id`, `secret_access_key`. Extend `init`, `doctor`, and `seed-bao` to handle them. Seed paths:
  - `secret/platform/object-storage/audit`
  - `secret/platform/object-storage/openbao-snapshots`
  - `secret/platform/object-storage/app-backups`
- `dmf-env/manifests/README.md` — document the new `object_storage:` schema block (one paragraph + example).

**Expected commits:**

- `dmf-env@<hash>` — `feat(object-storage): generic-s3 Terraform module + seed bundle extension`

**Companion umbrella commit:**

- `dmfdeploy@<hash>` — `docs(handoff): Tier A Phase 2 implementation record` (handoff per the Phase 1 template, including B2 bucket-provisioning operator runbook fragment).

### Dispatch matrix

| Slice | Actor | Why |
|---|---|---|
| Research the Terraform `aws` provider's S3-Compat compatibility surface for B2 (Object Lock, SSE, versioning, path-style addressing) | **Subagent (general-purpose)** | Web-research + spec writing; one-shot. |
| Write the `generic-s3/object-storage` Terraform module + wire it into `hetzner-arm/main.tf` | **qwen-left** | Multi-file edit within `dmf-env`; bounded but cross-references. |
| Extend `bootstrap-secrets.sh` (init/doctor/seed-bao for `object_storage:`) + amend the hetzner-arm manifest + manifests/README.md | **qwen-right** | Multi-file edit within `dmf-env`; parallel to qwen-left, no overlap. |
| Integrate, verify, commit, push, write Phase 2 handoff, ping codex | **Claude** | Plan-holding. |

### Per-actor briefs

> **2026-05-12 note:** the briefs below are the original dispatch text
> from the 2026-05-11 attempt. They assume an EU-Central B2 endpoint
> and a Terraform-managed flow. **Both assumptions were superseded
> during live-apply** — the operator's B2 account turned out to be in
> `us-west-001` and the Terraform path was pivoted to a B2-native
> script (`dmf-env/bin/b2-buckets.sh`). The Phase 2 status section
> above + the Phase 2 handoff §2.6 + §4 are the current source of
> truth; the briefs below are kept as a historical record of what was
> dispatched. Do NOT re-use them verbatim for a re-run.

#### Subagent (research)

```
Research the Terraform AWS provider (hashicorp/aws ≥ 5.x) against
Backblaze B2's S3-Compatible API for the resources we need:

  aws_s3_bucket
  aws_s3_bucket_versioning
  aws_s3_bucket_object_lock_configuration   (COMPLIANCE mode)
  aws_s3_bucket_server_side_encryption_configuration   (AES256)

For each resource, confirm:
  1. Whether the resource works against B2's S3 endpoint at
     https://s3.eu-central-003.backblazeb2.com when the provider has
     skip_credentials_validation = true, skip_metadata_api_check = true,
     skip_region_validation = true, and s3_use_path_style = true.
  2. Any B2-specific behaviour gotchas — e.g. is bucket creation atomic
     with Object Lock enablement, or does it require two steps? Does B2
     accept the AES256 SSE config as a no-op (because B2 has SSE-B2 at
     bucket level) or does it require special handling?
  3. The minimum AWS-provider config block needed at the module level
     so a single provider instance can talk to B2 without inheriting any
     env-level AWS credentials.

Also confirm the AWS-provider's `endpoints { s3 = "..." }` block syntax
versus the older `endpoints` per-service form. Use the latest stable
release (>= 5.x).

Produce a 250-300 word reference design with example HCL snippets
(variables.tf + versions.tf + a sample aws_s3_bucket block) ready to
paste into the new module. Include 1-2 citations to current Backblaze
docs (backblaze.com/docs/*) and 1-2 to the Terraform AWS provider docs
(registry.terraform.io/providers/hashicorp/aws/latest/docs/*).
```

#### qwen-left (Terraform module)

```
Implement the generic-s3 object-storage Terraform module per the
DMF Tier A Phase Execution Plan, Phase 2. Run from the dmfdeploy
umbrella cwd. Read first (paths are repo-relative to that cwd):

  docs/plans/DMF Tier A Phase Execution Plan 2026-05-11.md   (the plan, especially §Phase 2)
  dmf-env/terraform/modules/hetzner/cluster/                  (existing module shape — mirror it)
  dmf-env/terraform/hetzner-arm/main.tf                       (where the new module call lands)

Create:

  dmf-env/terraform/modules/generic-s3/object-storage/variables.tf
  dmf-env/terraform/modules/generic-s3/object-storage/versions.tf
  dmf-env/terraform/modules/generic-s3/object-storage/main.tf
  dmf-env/terraform/modules/generic-s3/object-storage/outputs.tf

variables.tf:
  - bucket_names: object({ audit = string, openbao_snapshots = string, app_backups = string })
  - endpoint:               string  (e.g. "https://s3.eu-central-003.backblazeb2.com")
  - access_key_id:          string  (sensitive)
  - secret_access_key:      string  (sensitive)
  - region:                 string  (e.g. "eu-central-003")
  - object_lock_retention_days: number  (default 365)

versions.tf:
  - terraform required_version >= 1.6
  - aws provider source = hashicorp/aws, version >= 5.0
  - configured with skip_credentials_validation = true,
    skip_metadata_api_check = true, skip_region_validation = true,
    s3_use_path_style = true, endpoints { s3 = var.endpoint }
  - The credentials come from the module variables, NOT from env or
    ~/.aws/credentials at apply time.

main.tf — three buckets:
  1. var.bucket_names.audit              — Object Lock COMPLIANCE, versioning, SSE AES256
  2. var.bucket_names.openbao_snapshots  — versioning, SSE AES256, NO Object Lock
  3. var.bucket_names.app_backups        — versioning, SSE AES256, NO Object Lock

For the audit bucket: set object_lock_enabled = true at creation, then
the aws_s3_bucket_object_lock_configuration with rule.default_retention.mode
= "COMPLIANCE", days = var.object_lock_retention_days.

outputs.tf — emit a flattened map keyed by logical name with
{ bucket, endpoint, region } for each, plus separate top-level outputs
for the three bucket IDs.

Then amend dmf-env/terraform/hetzner-arm/main.tf:
  - Add module "object_storage" { source = "../modules/generic-s3/object-storage" ... }
  - Pass values from the manifest (read with yamldecode pattern already
    used in main.tf — the existing locals.manifest is the precedent).
  - Add output blocks to surface the buckets back to the caller.

DO NOT touch:
  - dmf-env/bin/bootstrap-secrets.sh
  - dmf-env/manifests/*.yaml         (qwen-right's slice)
  - any file under dmf-infra/        (Phase 3+'s territory)
  - the existing hetzner cluster module

Verify with `cd dmf-env/terraform/hetzner-arm && tofu init && tofu validate`.
Report exit codes back. Do not apply. Commit nothing — Claude integrates
+ commits.
```

#### qwen-right (bundle schema + manifests)

```
Extend the dmf-env seed bundle for object-storage credentials per the
DMF Tier A Phase Execution Plan, Phase 2. Run from the dmfdeploy
umbrella cwd. Read first (paths are repo-relative to that cwd):

  docs/plans/DMF Tier A Phase Execution Plan 2026-05-11.md   (the plan, especially §Phase 2)
  dmf-env/bin/bootstrap-secrets.sh                            (existing init / doctor / seed-bao)
  dmf-env/manifests/hetzner-arm.yaml                          (existing manifest layout)
  dmf-env/manifests/README.md                                 (manifest schema doc)

The bundle is an age/SOPS-encrypted YAML at
$DMF_BOOTSTRAP_BUNDLE_DIR/<env>.sops.yaml. The schema lives implicit in
the bootstrap-secrets.sh `init` heredoc + `doctor` validator + `seed-bao`
mapping logic.

Extend the schema with a new top-level key:

    object_storage:
      audit:
        bucket: dmf-audit-hetzner-arm
        endpoint: https://s3.eu-central-003.backblazeb2.com
        region: eu-central-003
        access_key_id: <REDACTED in bundle>
        secret_access_key: <REDACTED in bundle>
      openbao_snapshots:
        bucket: dmf-openbao-snapshots-hetzner-arm
        endpoint: https://s3.eu-central-003.backblazeb2.com
        region: eu-central-003
        access_key_id: <REDACTED in bundle>
        secret_access_key: <REDACTED in bundle>
      app_backups:
        bucket: dmf-app-backups-hetzner-arm
        endpoint: https://s3.eu-central-003.backblazeb2.com
        region: eu-central-003
        access_key_id: <REDACTED in bundle>
        secret_access_key: <REDACTED in bundle>

bootstrap-secrets.sh changes:

  1. `init` — extend the heredoc-generated template so a fresh init
     produces the three blocks with empty access/secret strings (operator
     fills them in via `sops edit`).
  2. `doctor` — validate the new keys are present and non-empty when the
     audit-archival role is expected to run. Add a flag like
     --object-storage-required or auto-detect when audit_log_s3_bucket
     is set in inventory.
  3. `seed-bao` — for each of the three blocks, write a JSON document
     to OpenBao at:
        secret/platform/object-storage/audit
        secret/platform/object-storage/openbao-snapshots
        secret/platform/object-storage/app-backups
     containing { bucket, endpoint, region, access_key_id,
     secret_access_key }. Use the existing `bao kv put` pattern from
     other paths in this script (see how seed-bao writes
     secret/platform/bootstrap_admin). NO secrets in argv per ADR-0007 —
     pass via stdin / `-` reads.
  4. `export-vars` — export the audit block's fields into the Ansible
     vars JSON so the audit-log-archival role gets:
         audit_log_aws_access_key_id, audit_log_aws_secret_access_key,
         audit_log_aws_region, audit_log_s3_bucket, audit_log_s3_endpoint
     The other two blocks are NOT exported as vars (they get to consumers
     via ESO in Phase 3, not via inventory).

Amend dmf-env/manifests/hetzner-arm.yaml: add a NEW `spec.object_storage`
block with bucket NAMES + endpoint + region only (no credentials —
credentials live in the bundle). The Terraform module reads from this
manifest (qwen-left's slice produces the module that consumes it).

Amend dmf-env/manifests/aliyun.yaml the same way for symmetry, even
though the operator is not actively using aliyun for buckets yet —
leave bucket names empty so the consumer treats it as not-configured.

Amend dmf-env/manifests/README.md: add a §"Object Storage" section
documenting the new `spec.object_storage` schema block with an example.

DO NOT touch:
  - dmf-env/terraform/**            (qwen-left's slice)
  - dmf-env/inventories/**           (out of Phase 2 scope)
  - dmf-infra/**                      (Phase 3+'s territory)

Verify:
  - `bash -n dmf-env/bin/bootstrap-secrets.sh` exits 0
  - `dmf-env/bin/bootstrap-secrets.sh doctor hetzner-arm` (after a fresh
    init) returns clean once the new keys are populated (a smoke run with
    placeholder values is fine — the goal is to confirm the schema parses).

Commit nothing — Claude integrates + commits.
```

### Acceptance criteria

- `tofu validate` clean in `dmf-env/terraform/hetzner-arm/`
- `bash -n dmf-env/bin/bootstrap-secrets.sh` clean
- A fresh `bootstrap-secrets.sh init test-phase2` produces a bundle template that includes the three `object_storage:` blocks
- `bootstrap-secrets.sh doctor` reports missing-creds when those blocks are empty + present when filled in
- `dmf-env/manifests/README.md` carries the new schema doc
- ADR-0007 check: grep for `access_key_id\|secret_access_key` in the diff returns only schema/key declarations, never literal credential values
- gitleaks pre-commit passes on the staged commit

### Done definition

OpenBao on a freshly-bootstrapped cluster contains the three
`secret/platform/object-storage/*` paths populated from the seeded
bundle, AND `tofu apply` against `hetzner-arm` produces the three
buckets in B2 (or whichever S3-compatible target). No code in
`dmf-infra` consumes them yet — that's Phase 3.

---

## Phase 3 — vertical-resilience playbooks

### Goal

After Phase 3, every Tier-A backup data class has a daily/weekly pipeline
landing in the right bucket with provider-managed SSE, daily smoke-tested
end-to-end on each `bootstrap-verify.yml` run. The 24h RPO claim is
honest.

### Inputs

- Phase 2 outputs (the three OpenBao paths + buckets must exist).
- §3.3 of the readiness plan for the per-class primitive choice.
- §5.1 of the readiness plan for the role tree.
- Existing patterns to mirror:
  - `dmf-infra/k3s-lab-bootstrap/roles/base/external-secrets/` — ESO ClusterSecretStore template, AppRole pattern.
  - `dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/` — Phase 1 reference for the "host cron + AWS profile" pattern.
  - `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/` — `bao operator raft snapshot save` is the OpenBao subcommand we'll call from a CronJob.

### Outputs

**New roles** (each under `dmf-infra/k3s-lab-bootstrap/roles/base/`):

- `object-storage-credentials/` — three ESO ClusterSecretStores + ExternalSecrets, one per bucket path; per-AppRole policies in OpenBao (read-only on the specific path).
- `longhorn-backup-target/` — Longhorn `BackupTarget` CR + credential secret + per-namespace `RecurringJob` resources.
- `openbao-raft-snapshot/` — daily CronJob running `bao operator raft snapshot save` and uploading via AWS SDK.
- `postgres-backups/` — per-app `pg_dump` CronJob template; defaults list (`netbox`, `awx`, `authentik`, `forgejo`).
- `zot-mirror/` — weekly `mc mirror` CronJob.
- `resilience-verify/` — smoke-test playbook role exercising one round-trip per bucket.

**New playbooks** (under `dmf-infra/k3s-lab-bootstrap/playbooks/vertical-resilience/`):

- `100-object-storage-credentials.yml`
- `110-longhorn-backup-target.yml`
- `111-longhorn-recurring-jobs.yml`
- `120-openbao-raft-snapshot.yml`
- `130-postgres-backups.yml`
- `140-zot-mirror.yml`
- `190-resilience-verify.yml`

**Amended:**

- `bootstrap-provision-post-seed.yml` — import the seven new playbooks after `vertical-monitoring/190-monitoring-verify.yml`.
- `bootstrap-verify.yml` — import `vertical-resilience/190-resilience-verify.yml`.

**Expected commits:**

- `dmf-infra@<hash>` — `feat(resilience): vertical-resilience playbook track + per-class backup primitives`
- `dmfdeploy@<hash>` — `docs(handoff): Tier A Phase 3 implementation record`

### Dispatch matrix

| Slice | Actor |
|---|---|
| Research Longhorn `BackupTarget` + `RecurringJob` CR shape, OpenBao `raft snapshot` CLI semantics, `mc mirror` flags | Subagent (Explore) ×1 with three sub-questions |
| ESO ClusterSecretStore + ExternalSecret + OpenBao policy work (object-storage-credentials role) | **qwen-left** |
| OpenBao Raft snapshot + per-app PG-dump + Zot mirror CronJobs (the three "in-cluster CronJob" roles) | **qwen-right** |
| Longhorn BackupTarget + RecurringJob roles + resilience-verify | **Claude** (touches the verification gate; do not delegate) |
| Wire into bootstrap-provision-post-seed.yml + bootstrap-verify.yml; integrate, verify, commit, push, handoff | **Claude** |

### Per-actor briefs

> Authored 2026-05-12 after cross-pane agreement on dispatch + sequencing
> + post-Phase-2 catches (versioning/lifecycle gap, AppRole idempotency,
> two-secret split for openbao snapshots, zot-mirror direction). Briefs
> are copy-paste-ready for `agent-bridge send <pane> -` (qwen-left /
> qwen-right) or `Agent` tool dispatch (subagent). The Claude self-brief
> is an execution checklist, not a prompt.

#### Frozen Secret Contract (referenced by all three implementer briefs)

Both backup-credential paths emit K8s Secrets with this exact shape:

| Secret name | Namespaces | Keys |
|---|---|---|
| `s3-creds-openbao-snapshots` | `openbao-system` | `bucket`, `endpoint`, `region`, `access_key_id`, `secret_access_key` |
| `s3-creds-app-backups` | `awx`, `netbox`, `authentik`, `forgejo`, `zot` | `bucket`, `endpoint`, `region`, `access_key_id`, `secret_access_key` |

`longhorn-system` is intentionally NOT in the qwen-left consumer-namespace
loop: Longhorn 1.10.1's `BackupTarget` CR requires UPPERCASE Secret keys
(`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINTS`). Claude's
`longhorn-backup-target` role creates its own `ExternalSecret` in
`longhorn-system` with a `template:` block that re-keys the lowercase
Frozen Contract values into Longhorn's UPPERCASE expectation. Same
OpenBao path, different Secret-side projection.

Audit is NOT in the contract — Phase 1's `audit-log-archival` role
consumes its credentials via inventory vars (`bootstrap-secrets.sh
export-vars`), not ESO. ESO scope = `openbao_snapshots` + `app_backups`
only. Each Secret is materialized by ESO from the corresponding OpenBao
path `secret/platform/object-storage/<logical>` (Phase 2 already seeds
these).

Snapshot CronJob secondary credential (separate from the contract):

| Source | Auth method | Policy scope |
|---|---|---|
| Pod ServiceAccount `openbao-raft-snapshot` in `openbao-system` | OpenBao Kubernetes auth (already enabled in `roles/stack/operator/openbao/`, line 699+) | `path "sys/storage/raft/snapshot" { capabilities = ["update", "sudo"] }` only |

The CronJob mounts the SA token + uses `bao login -method=kubernetes
role=openbao-raft-snapshot` at runtime. No long-lived AppRole token,
no env-var credential.

#### Subagent (Explore — research only)

Dispatch via `Agent` tool, `subagent_type=Explore`. Profile:
READ_ONLY_RESEARCH.

```
[Profile: READ_ONLY_RESEARCH]

Research three implementation surfaces for DMF Tier A Phase 3
(vertical-resilience playbooks). Pure information-gathering — do not
write or modify any file. Run from the dmfdeploy umbrella cwd ($DMFDEPLOY_UMBRELLA).

Read first:
  docs/processes/agent-prompt-templates.md   (apply READ_ONLY_RESEARCH rails)
  docs/plans/DMF Tier A Phase Execution Plan 2026-05-11.md   (§Phase 3)

Apply rails: SECRETS, IDENTITY, REPORTING.

Three sub-questions, each with a concrete deliverable:

1. Longhorn BackupTarget + RecurringJob CR shape (current: Longhorn
   1.6.x or whatever ships in dmf-infra's lifecycle pin).
   Find: dmf-infra/k3s-lab-bootstrap/playbooks/330-longhorn.yml +
   any chart values in the Longhorn role for the version pin. Then
   look up the corresponding upstream CR YAML for:
     - BackupTarget (apiVersion, spec fields, credentialSecret reference shape)
     - RecurringJob (cron, retain, concurrency, backupTarget binding)
   Deliver: a minimal-viable YAML for each CR (≤30 lines each) with
   the secret-reference convention noted explicitly.

2. `bao operator raft snapshot save` CLI semantics. Find: any existing
   reference in dmf-infra/dmf-env. Then determine:
     - Does `snapshot save` write to stdout, a file path, or both?
     - What policy capabilities are needed (sys/storage/raft/snapshot
       sudo+update; anything else?)
     - Behavior when called against a non-leader Raft node — error out
       or auto-forward?
   Deliver: a 5-line bash snippet showing the canonical invocation +
   a one-paragraph note on the leader-vs-follower behavior.

3. `mc mirror` flag semantics for backup direction (PVC source → S3
   target). Specifically:
     - `--overwrite` semantics (overwrite at-target if differs?)
     - SSE flag handling — does `mc mirror` propagate the target's
       `defaultServerSideEncryption` automatically, or do we need
       --encrypt-key / --enc-s3?
     - How `--remove` differs (and why we are NOT using it per Phase 3
       agreement: backup follows prod into the grave).
   Deliver: a 3-line `mc mirror` invocation + a one-paragraph note on
   SSE propagation.

Report findings as a single message back. ≤500 words total. Cite
upstream docs by URL, not snippets pasted inline.
```

#### qwen-left (object-storage-credentials role)

Dispatch via `agent-bridge send qwen-left -`. Profile: CODE_EDIT.
**Always `/clear` qwen-left before sending.**

```
[Profile: CODE_EDIT]

You are picking up the object-storage-credentials role for DMF Tier A
Phase 3. Run from the dmfdeploy umbrella cwd ($DMFDEPLOY_UMBRELLA).

Read first (paths repo-relative):
  docs/processes/agent-prompt-templates.md   (apply CODE_EDIT rails verbatim)
  docs/plans/DMF Tier A Phase Execution Plan 2026-05-11.md   (§Phase 3, especially the Frozen Secret Contract)
  dmf-infra/k3s-lab-bootstrap/roles/base/external-secrets/tasks/main.yml   (existing single-AppRole + ClusterSecretStore pattern; mirror for the new ones)
  dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml   (lines 1055–1095 + 1184–1225 — AppRole creation pattern; lines 940–960 — policy doc)
  dmf-infra/k3s-lab-bootstrap/roles/stack/operator/authentik/tasks/main.yml   (lines 237+, 282+ — ClusterSecretStore + ExternalSecret reference)

Apply rails: SECRETS, SCOPE, GIT, IDENTITY, REPORTING.

Task: create a new role `object-storage-credentials` that provisions
two OpenBao AppRoles (one per logical bucket: openbao_snapshots,
app_backups), creates two ClusterSecretStores (one per AppRole), and
creates ExternalSecrets in each consumer namespace per the Frozen
Secret Contract above.

Create:
  dmf-infra/k3s-lab-bootstrap/roles/base/object-storage-credentials/defaults/main.yml
  dmf-infra/k3s-lab-bootstrap/roles/base/object-storage-credentials/tasks/main.yml
  dmf-infra/k3s-lab-bootstrap/roles/base/object-storage-credentials/README.md
  dmf-infra/k3s-lab-bootstrap/playbooks/vertical-resilience/100-object-storage-credentials.yml

defaults/main.yml:
  - object_storage_logicals: ["openbao_snapshots", "app_backups"]
  - object_storage_consumer_namespaces:
      openbao_snapshots: ["openbao-system"]
      app_backups: ["awx", "netbox", "authentik", "forgejo", "zot"]
      # longhorn-system NOT here — Claude's role writes its own
      # uppercase-key ExternalSecret per the Frozen Contract note above.
  - object_storage_secret_name_template: "s3-creds-{{ logical | replace('_', '-') }}"
  - openbao_approle_secret_id_ttl: "8760h" (one year — backup creds are long-lived; rotation is operator-initiated, not reconcile-driven)
  - object_storage_openbao_path_template: "secret/platform/object-storage/{{ logical | replace('_','-') }}"

tasks/main.yml — for each logical:
  1. Write a per-logical OpenBao policy granting read on exactly
     `secret/platform/object-storage/<logical-dashed>/*`. Policy name:
     `object-storage-<logical-dashed>-reader`. Use the same `bao policy
     write` pattern as openbao role line 940+.
  2. Idempotent AppRole creation (DEVIATES FROM EXISTING PATTERN):
        a. `bao read auth/approle/role/<role-name>/role-id` — if exit 0,
           AppRole exists; SKIP secret-id generation. (role-id is the
           witness; not secret-id.)
        b. If `bao read` fails (not-found): create the role with
           `bao write auth/approle/role/<role-name> token_policies=
           object-storage-<logical-dashed>-reader secret_id_ttl=
           {{ openbao_approle_secret_id_ttl }} token_ttl=1h token_max_ttl=24h`
           THEN generate exactly one secret-id with `bao write -force=false`
           (no -force flag — the existing repo pattern uses -force; do
           NOT mirror that here).
        c. Store the freshly-generated secret-id at
           `secret/platform/eso-bindings/<role-name>` for the operator
           to inject into the K8s Secret consumed by the ClusterSecretStore.
           Use stdin-fed `bao kv put PATH @-` form (NOT argv).
     Why this deviates from existing -force pattern: backup CronJobs
     read these creds on every fire; rotating secret-id every reconcile
     would churn ExternalSecret reconciles + risk a missed rotation
     leaving CronJobs unable to authenticate.
  3. K8s-side: create the ESO auth Secret in `external-secrets-system`
     namespace containing role-id + secret-id (from step 2c — reuse
     the existing `eso_approle_secret_name` convention, prefixed with
     `<logical-dashed>-`).
  4. Create ClusterSecretStore named `openbao-<logical-dashed>` in the
     OpenBao/Vault provider/AppRole shape used by the existing
     external-secrets role (lines 85–110).
  5. For each namespace in object_storage_consumer_namespaces[logical]:
     create an ExternalSecret named `s3-creds-<logical-dashed>` that
     materializes a K8s Secret of the same name, with the five keys
     from the Frozen Secret Contract.

playbooks/vertical-resilience/100-object-storage-credentials.yml:
  - Standard hosts: + roles: [object-storage-credentials] shape.
  - Mirror playbooks/vertical-monitoring/100-*.yml as the format
    reference.

DO NOT touch:
  - dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/   (existing AppRole/policy work)
  - dmf-infra/k3s-lab-bootstrap/roles/base/external-secrets/    (existing single-AppRole role)
  - dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/  (Phase 1; no ESO)
  - dmf-env/                                                     (out of scope; the contract reads from manifests already present)
  - bootstrap-provision-post-seed.yml                            (Claude wires this)
  - any qwen-right slice (the three CronJob roles)

Acceptance check (do NOT run; describe expected output):
  - `ansible-playbook --syntax-check 100-object-storage-credentials.yml`
    via dmf-env/bin/run-playbook.sh would pass (don't actually run).
  - The role's tasks file is idempotent — running it twice yields no
    AppRole secret-id rotation.
  - Each ExternalSecret references its ClusterSecretStore by name +
    the OpenBao path `secret/platform/object-storage/<logical-dashed>`.

REPORTING:
  - Per-file diff stat (lines added/changed).
  - Any place the existing pattern conflicted with the brief —
    flag for orchestrator.
  - Confirm: NO -force on secret-id generation. NO credentials in argv.
  - Redact any access-key-shaped string in output as <redacted-keyid>.

DO NOT commit. Report when done; orchestrator integrates.
```

#### qwen-right (3 backup CronJob roles)

Dispatch via `agent-bridge send qwen-right -`. Profile: CODE_EDIT.
**Always `/clear` qwen-right before sending.**

```
[Profile: CODE_EDIT]

You are picking up the three backup-CronJob roles for DMF Tier A
Phase 3. Run from the dmfdeploy umbrella cwd ($DMFDEPLOY_UMBRELLA).

Read first (paths repo-relative):
  docs/processes/agent-prompt-templates.md   (apply CODE_EDIT rails verbatim)
  docs/plans/DMF Tier A Phase Execution Plan 2026-05-11.md   (§Phase 3, especially the Frozen Secret Contract)
  dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/   (Phase 1 reference for the "host-cron + AWS profile" pattern; you are doing the in-cluster CronJob equivalent)
  dmf-infra/k3s-lab-bootstrap/roles/stack/operator/openbao/tasks/main.yml   (lines 699–790 — Kubernetes auth method; the openbao-raft-snapshot CronJob uses this for its bao token)
  dmf-infra/k3s-lab-bootstrap/playbooks/330-longhorn.yml   (existing Longhorn install — your zot-mirror role's mc image pattern can mirror Longhorn's image-pull conventions)

Apply rails: SECRETS, SCOPE, GIT, IDENTITY, REPORTING.

Task: create three new roles, each with a CronJob that consumes the
Frozen Secret Contract. NO inline credential handling — every
credential is mounted as a Secret volume or fetched via in-pod
`bao login`.

Create:
  dmf-infra/k3s-lab-bootstrap/roles/base/openbao-raft-snapshot/{defaults,tasks,templates}/{main.yml,...}
  dmf-infra/k3s-lab-bootstrap/roles/base/openbao-raft-snapshot/README.md
  dmf-infra/k3s-lab-bootstrap/roles/base/postgres-backups/{defaults,tasks,templates}/{main.yml,...}
  dmf-infra/k3s-lab-bootstrap/roles/base/postgres-backups/README.md
  dmf-infra/k3s-lab-bootstrap/roles/base/zot-mirror/{defaults,tasks,templates}/{main.yml,...}
  dmf-infra/k3s-lab-bootstrap/roles/base/zot-mirror/README.md
  dmf-infra/k3s-lab-bootstrap/playbooks/vertical-resilience/120-openbao-raft-snapshot.yml
  dmf-infra/k3s-lab-bootstrap/playbooks/vertical-resilience/130-postgres-backups.yml
  dmf-infra/k3s-lab-bootstrap/playbooks/vertical-resilience/140-zot-mirror.yml

# Role 1: openbao-raft-snapshot

  - Daily CronJob in `openbao-system` namespace.
  - Pod uses ServiceAccount `openbao-raft-snapshot` with this OpenBao
    Kubernetes-auth role binding (create in tasks via the bao CLI):
       bao write auth/kubernetes/role/openbao-raft-snapshot
         bound_service_account_names=openbao-raft-snapshot
         bound_service_account_namespaces=openbao-system
         policies=openbao-raft-snapshot
         ttl=10m
    Policy `openbao-raft-snapshot`:
       path "sys/storage/raft/snapshot" {
         capabilities = ["read"]
       }
    NO other capabilities. NO read on any kv path. The pod authenticates
    at runtime, calls snapshot save, then exits. (The snapshot save CLI
    calls the `read` endpoint on `/sys/storage/raft/snapshot` to stream
    the snapshot; `update`+`sudo` apply only to the `snapshot-auto`
    config endpoint which we do not use. Confirmed by subagent research,
    2026-05-12.)
  - Pod mounts `s3-creds-openbao-snapshots` Secret (Frozen Contract)
    as a volume at `/etc/s3-creds/`.
  - CronJob script (template):
       1. `bao login -method=kubernetes role=openbao-raft-snapshot`
          (token comes from /var/run/secrets/kubernetes.io/serviceaccount/token)
       2. `bao operator raft snapshot save /tmp/snapshot.snap`
       3. Build the AWS CLI invocation reading creds from the mounted
          Secret files (NOT env vars per ADR-0007); upload with
          `aws s3 cp /tmp/snapshot.snap s3://<bucket>/<cluster>/<timestamp>.snap`
          using `--endpoint-url` from the mounted Secret.
       4. `rm /tmp/snapshot.snap`. Exit non-zero if any step fails.

# Role 2: postgres-backups

  - Per-app CronJob template (defaults: `postgres_backups_apps:
    ["netbox", "awx", "authentik", "forgejo"]`).
  - Each CronJob runs in the app's own namespace, mounts that namespace's
    `s3-creds-app-backups` Secret.
  - CronJob script: `pg_dump` against the in-cluster Postgres service
    (each app already has one — service name pattern: `<app>-postgres`
    on port 5432; verify by reading each app's role defaults).
  - Object key format: `pg/<app>/<timestamp>.sql.gz` (timestamp-prefixed
    to make versioning + B2 lifecycle rules effective per the Phase 3
    catch — never overwrite a fixed key).
  - PG credentials: read from the existing per-app DB-creds Secret
    (each app has one — name pattern varies; mirror the app's own
    Deployment Secret refs).

# Role 3: zot-mirror

  - Weekly CronJob in `zot` namespace.
  - **Direction: backup** (PVC zot-data → s3://dmf-app-backups-<env>/zot/).
    NOT hydration (upstream → Zot).
  - mc mirror invocation:
       mc mirror --overwrite \
         /zot-data/ \
         dmf-b2/dmf-app-backups-<env>/zot/
    Explicitly NOT `--remove`. Reason: an accidental Zot image deletion
    would otherwise propagate to B2 on the next mirror — backup follows
    prod into the grave. B2 lifecycle rules (b2-buckets.sh) handle
    long-tail expiry.
  - mc client config: alias `dmf-b2` configured at script start from
    the mounted `s3-creds-app-backups` Secret values:
       mc alias set dmf-b2 "$(cat /etc/s3-creds/endpoint)" \
         "$(cat /etc/s3-creds/access_key_id)" \
         "$(cat /etc/s3-creds/secret_access_key)"
    NEVER pass the access key on argv directly with quotes — the
    cat-from-file form is the only acceptable path.
  - README.md must explicitly document the recovery story:
    "To restore Zot from B2: scale down Zot deployment, run
    `mc mirror --overwrite dmf-b2/dmf-app-backups-<env>/zot/ /zot-data/`
    in a one-shot pod, scale Zot back up. Deleted images stay in B2
    by design — see Phase 3 design notes in the execution plan."

# Per-playbook 1XX yml file

Each is a standard hosts: + roles: [<role-name>] shape, mirror
playbooks/vertical-monitoring/*.yml.

DO NOT touch:
  - dmf-infra/k3s-lab-bootstrap/roles/base/object-storage-credentials/   (qwen-left's slice)
  - dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/            (Phase 1; complete)
  - dmf-infra/k3s-lab-bootstrap/roles/base/longhorn-backup-target/        (Claude's slice)
  - dmf-infra/k3s-lab-bootstrap/roles/base/longhorn-recurring-jobs/       (Claude's slice)
  - dmf-infra/k3s-lab-bootstrap/roles/base/resilience-verify/             (Claude's slice)
  - bootstrap-provision-post-seed.yml + bootstrap-verify.yml              (Claude wires)
  - dmf-env/                                                                (out of scope)

Acceptance check (do NOT run against the cluster; describe expected output):
  - `ansible-playbook --syntax-check` would pass for each new playbook.
  - Each CronJob template's Secret references match the Frozen Contract
    Secret names + key names exactly.
  - openbao-raft-snapshot uses k8s ServiceAccount auth, NOT a
    long-lived AppRole token.
  - zot-mirror invocation does NOT include `--remove`.

REPORTING:
  - Per-file diff stat.
  - Any place an in-cluster Secret reference disagreed with the Frozen
    Contract — flag for orchestrator.
  - Redact any access-key-shaped string in output as <redacted-keyid>.

DO NOT commit. Report when done; orchestrator integrates.
```

#### Claude (longhorn + resilience-verify + integration — execution checklist)

Not a delegated brief — execution checklist for the orchestrator.

1. **`longhorn-backup-target` role** (`dmf-infra/k3s-lab-bootstrap/roles/base/longhorn-backup-target/`).
   - Creates `BackupTarget` CR (`longhorn.io/v1beta2`) in
     `longhorn-system` with:
       `backupTargetURL: s3://dmf-app-backups-<env>@<region>/`
       `credentialSecret: s3-creds-app-backups`
       `pollInterval: 5m0s`
   - Also creates an `ExternalSecret` named `s3-creds-app-backups` in
     `longhorn-system` (qwen-left does NOT — see Frozen Contract note),
     with a `template:` block that re-keys the lowercase Frozen Contract
     values into Longhorn's expected UPPERCASE Secret keys:
       `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_ENDPOINTS`,
       plus `VIRTUAL_HOSTED_STYLE: "true"` (B2 uses path-style).
   - References: subagent research deliverable
     (`https://longhorn.io/docs/1.10.1/snapshots-and-backups/backup-and-restore/set-backup-target/`).
2. **`longhorn-recurring-jobs` role** (`.../longhorn-recurring-jobs/`).
   - One `RecurringJob` (`longhorn.io/v1beta2`) bound to the default
     `BackupTarget` via Longhorn's volume `recurringJobSelector`
     labels — NOT via a `backupTargetName` field. Longhorn 1.10.1 has
     no multi-target binding (upstream issue #11421 is open). Single
     RecurringJob is sufficient for Tier A.
   - Cron: daily, retain=7 (one week of dailies — well within the 365d
     B2 lifecycle window). `task: backup`, `concurrency: 2`,
     `groups: [default]`.
3. **`resilience-verify` role** (`.../resilience-verify/`).
   - Synthetic round-trip per bucket (`audit`, `openbao_snapshots`,
     `app_backups`):
       (a) PUT a small object,
       (b) HEAD it and assert
           `x-amz-server-side-encryption: AES256` present (catches
           silent SSE drift),
       (c) GET it,
       (d) DELETE it.
   - Audit-bucket-specific: PUT with `--object-lock-mode COMPLIANCE
     --object-lock-retain-until-date "+1m"`; verify DELETE is refused;
     wait the minute; clean up. Proves Object Lock teeth, not just
     credential validity.
   - `--soak-prewarm` flag: `kubectl create job --from=cronjob/<name>`
     for each backup CronJob — proves payload paths in 30 min instead
     of waiting for the natural 48h soak.
4. **Wire** into top-level orchestration:
   - Append `vertical-resilience/100-...` through `190-...` imports to
     `dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml`
     after the `vertical-monitoring/190-monitoring-verify.yml` import.
   - Append `vertical-resilience/190-resilience-verify.yml` import to
     `dmf-infra/k3s-lab-bootstrap/bootstrap-verify.yml`.
5. **Pre-flight**: confirm `b2-buckets.sh ensure <env>` has been re-run
   for both envs since the lifecycle-rules commit (`f907a80` in
   dmf-env). The brief's bucket assumptions depend on it.
6. **Commit slicing** — 9 commits in `dmf-infra`, headers locked from
   the cross-pane agreement:
   ```
   1. feat(eso): object-storage-credentials role + 2 ClusterSecretStores       (qwen-left)
   2. feat(longhorn): backup-target role + credential wiring                    (Claude)
   3. feat(longhorn): per-namespace recurring-jobs role                         (Claude)
   4. feat(openbao): raft-snapshot CronJob role + scoped k8s-auth role         (qwen-right)
   5. feat(postgres): per-app pg_dump CronJob role                              (qwen-right)
   6. feat(zot): blob-store mirror CronJob role                                 (qwen-right)
   7. feat(resilience-verify): synthetic round-trip + lock-test + prewarm      (Claude)
   8. feat(playbooks): vertical-resilience track wiring                         (Claude)
   9. feat(bootstrap-verify): import resilience-verify                          (Claude)
   ```
   Plus one in `dmfdeploy`:
   ```
   docs(handoff): Tier A Phase 3 implementation record                          (Claude)
   ```

### Acceptance criteria

- `bootstrap-verify.yml` synthetic round-trip passes for all three
  buckets (PUT/HEAD/GET/DELETE), with HEAD asserting
  `x-amz-server-side-encryption: AES256` on each
- Audit-bucket-specific Object Lock delete-refusal test passes
- `--soak-prewarm` mode lands one object per backup CronJob in 30 min
- Each backup CronJob runs at least once in a 48h natural-schedule
  soak and lands an object
- ESO `SecretSynced` for both new ClusterSecretStores
  (`openbao-openbao-snapshots`, `openbao-app-backups`)
- Longhorn shows `BackupTarget` reachable, RecurringJobs `Active`
- An OpenBao Raft snapshot exists in
  `s3://dmf-openbao-snapshots-<env>/<cluster>/<timestamp>.snap`
- A `pg_dump` tarball exists in
  `s3://dmf-app-backups-<env>/pg/<each-app>/<timestamp>.sql.gz`
- Zot mirror produces a `s3://dmf-app-backups-<env>/zot/` tree
  matching the live `zot-data` PVC
- B2 lifecycle rules visible via `b2-buckets.sh show <env>` —
  openbao-snapshots: 90d, app-backups: 365d, audit: none

### Done definition

The OSS clone, with the BYO-object-storage configured, gets a full
backup pipeline on first bootstrap. The 24h RPO claim is testable.

---

## Phase 4 — Cosign bootstrap + first signed image + SBOM

### Goal

Every release-tagged image pushed to Zot from Phase 4 onward is signed
by cosign and carries a syft SBOM attestation. Verification at admission
is Tier B work (deferred).

### Inputs

- ADR-0020 Mode A "no outbound" constraint — keypair lives in OpenBao,
  not Sigstore Fulcio.
- §5.1 of the readiness plan for the role placement.
- Existing build pipelines:
  - `dmf-cms/scripts/build-image.sh` + `dmf-cms/scripts/release.sh`
  - `dmf-runbooks/roles/nmos-cpp/scripts/push-nmos-images.sh`
- Existing OpenBao path convention: `secret/platform/cosign/{signing-key,public-key}`.
- Existing skill: `.claude/skills/dmf-cms-build-and-release/SKILL.md` —
  Phase 4 extends this skill's flow.

### Outputs

**New role:**

- `dmf-infra/k3s-lab-bootstrap/roles/base/cosign-bootstrap/` — idempotent keypair generation; private to OpenBao, public to a ConfigMap + a committed file in `dmf-infra/`.

**Amended:**

- `dmf-cms/scripts/build-image.sh` — append `cosign sign` + `syft attest` post-push.
- `dmf-runbooks/roles/nmos-cpp/scripts/push-nmos-images.sh` — same.
- `dmf-infra/k3s-lab-bootstrap/playbooks/650-dmf-cms.yml` — fetch the signing key from OpenBao and pass via stdin to `build-image.sh` per ADR-0007 (no env, no argv).
- `bootstrap-provision-pre-seed.yml` — insert `vertical-security/105-cosign-bootstrap.yml` after `100-openbao.yml`.
- `commitments-v1.md` §B1 — pin-by-SHA principle promoted to rule, and the per-repo CONTRIBUTING.md picks it up in Phase 5.

**Expected commits:**

- `dmf-infra@<hash>` — `feat(cosign): bootstrap role + first signed image pipeline`
- `dmf-cms@<hash>` — `chore(build): cosign sign + syft SBOM post-push`
- `dmf-runbooks@<hash>` — `chore(build): cosign sign + syft SBOM for nmos-cpp images`

### Dispatch matrix

| Slice | Actor |
|---|---|
| cosign-bootstrap role | **qwen-left** |
| dmf-cms build-image.sh + release.sh + playbook 650 wiring | **qwen-right** |
| dmf-runbooks nmos-cpp script | Subagent (general-purpose) |
| Integration, verification (`cosign verify` end-to-end against Zot), commits across three repos, handoff | **Claude** |

### Per-actor briefs

To be filled in when Phase 4 begins.

### Acceptance criteria

- `cosign verify --key env://COSIGN_PUBLIC_KEY <image>@<digest>` succeeds for one fresh dmf-cms release and one fresh nmos-cpp release.
- `cosign verify-attestation --type spdxjson` succeeds for both.
- ADR-0007 check: no secret in argv anywhere in the build pipeline.

### Done definition

Every image pushed to Zot is signed + SBOM-attested. Pin-by-digest
is the documented rule.

---

## Phase 5 — Documentation suite

### Goal

Every Tier A documentation gate item in the readiness checklist
(§Tier A) exists, is reviewer-checkable, and accurately describes the
shipped state. The OSS clone consumer can read the framework + ADRs +
SELF-HOST-DISCLAIMER and form an honest understanding.

### Inputs

- Readiness plan §Tier A items A.3, A.4, A.5, A.6, A.7, A.8 — the doc
  list.
- ADR-0020 — Mode A regulatory posture (the disclaimer's source-of-truth).
- Operator decision on backup RPO/RTO claim (default: "no RTO claimed
  until Tier B").

### Outputs

**New umbrella docs:**

- `docs/processes/audit-log-retention-policy.md` — §2 retention table verbatim + per-class implementation references.
- `docs/processes/backup-retention-policy.md` — §3 backup model verbatim + restore-procedure summary.
- `docs/runbooks/loss-of-shamir-recovery.md` — loss-of-share branch of `dmf-openbao-unseal` skill, dry-run rehearsal recorded as a handoff note.
- `docs/runbooks/restore-from-backups.md` — Tier A documented (not rehearsed); rehearsal is a Tier B gate.
- `docs/inventory/supplier-register.md` — initial seed table.
- `docs/processes/dpia-operator-identity.md` — 1-page CNIL-PIA-tool stub.
- `docs/processes/aliyun-tia.md` — Schrems II analytic frame paragraph.

**New per-repo files (×6 public repos: `dmfdeploy`, `dmf-cms`, `dmf-infra`, `dmf-central`, `dmf-media`, `dmf-runbooks`):**

- `SELF-HOST-DISCLAIMER.md` at root.

**Amended:**

- Each public repo's `README.md` — "Deployment modes" section per ADR-0020.
- ADR-0020 status → **Accepted** (after operator review confirms cluster-per-tenant economics + the three promotion criteria).

**Expected commits:** at least one per public repo (six), plus the umbrella commit for the new umbrella docs.

### Dispatch matrix

| Slice | Actor |
|---|---|
| Audit-log + backup retention policies, supplier register | **qwen-left** (umbrella) |
| DPIA + Aliyun TIA + loss-of-share recovery + restore-from-backups | **qwen-right** (umbrella) |
| SELF-HOST-DISCLAIMER ×6 + README amendments ×6 | Subagent (general-purpose) — one prompt per repo or one batch | 
| ADR-0020 promotion + integration + commits across seven repos + handoff | **Claude** |

### Acceptance criteria

- Every readiness-plan Tier A doc item exists on disk
- Every public repo has a `SELF-HOST-DISCLAIMER.md`
- ADR-0020 status reads `Accepted`
- `bin/check-public-repo-hygiene.sh` (built in Phase 6's Release & Contribution Plan Phase 2) passes once it lands

### Done definition

A reviewer reading only `docs/` + `README.md` + `SELF-HOST-DISCLAIMER.md`
can answer every reasonable security question a Mode A operator would
ask.

---

## Phase 6 — Identity-leak sweep close-out + first GitHub push

### Goal

The first public GitHub push lands. The umbrella + six component repos
are visible on `github.com/dmfdeploy/*` at v0.1.0.

### Inputs

- Phase 0-2 of the Release & Contribution Model Implementation Plan complete (LICENSE + NOTICE + VERSION + CONTRIBUTING + gitleaks per repo + `bin/check-public-repo-hygiene.sh` + `bin/sync-to-github.sh`). These are in flight per `docs/plans/DMF Release and Contribution Model Implementation Plan 2026-05-11.md`.
- `docs/handoffs/DMF Public Publish Readiness Handoff 2026-05-07.md` — orphan-rebase to v0.1.0 + push-mirror refspec gate.
- Identity-leak sweep close-out (per 2026-05-11 handoff).

### Outputs

- The `dmfdeploy` GitHub organisation exists with six empty repos.
- Each of the six public repos has been pushed via `bin/sync-to-github.sh`.
- Each push verified by `gh repo view` before the next push.

### Dispatch matrix

| Slice | Actor |
|---|---|
| Run `bin/check-public-repo-hygiene.sh` across the six public repos; resolve findings | Mostly **Claude** (operator-facing; needs judgement on each finding) |
| Run `bin/sync-to-github.sh --dry-run` per repo | **Claude** |
| Manual `gh repo view` after each push | **Operator** (manual confirm step) |

This is mostly an operator-facing step; delegate sparingly.

### Acceptance criteria

- `gh repo view dmfdeploy/<repo>` returns content for each of the six repos
- No `<secure-store>`, `<operator>`, `<wireguard-key>`, or other scrubbed-placeholder tokens leak in any pushed commit
- `bin/check-public-repo-hygiene.sh` exits 0 on all six repos

### Done definition

Tier A is complete. The OSS clone is downloadable; the framework plan
+ ADR-0020 + SELF-HOST-DISCLAIMER answer questions honestly; Mode B
preparation (Tier B) can begin.

---

## Cross-phase invariants

These rules apply to every phase. Verify before each commit:

1. **ADR-0007:** secrets never in argv / env / /tmp / AI transcripts. Pipe via stdin; use AWS SDK profile reads; OpenBao path delivery.
2. **ADR-0010:** all cluster mutation goes through `bin/run-playbook.sh`. Phase work does not bypass.
3. **ADR-0020 Mode A "no outbound":** no public-repo file references `dmfdeploy.io` as a required dependency. Grep before commit.
4. **gitleaks:** pre-commit hook is the canonical gate. Never `--no-verify`. Identity-leaking tokens (operator usernames, secure-store paths) are scrubbed before staging.
5. **`git add` by explicit path** — never `-A` / `.`. Pre-existing dirty files in the working tree (`.qwen/settings.json`, `.claude/scheduled_tasks.lock`, the prior LLM-restricted git pipeline plan) are not the phase's commits.
6. **Codex re-review** is mandatory after each phase commit pair. Ping via agent-bridge. Address every finding before moving to the next phase.
7. **Per-phase handoff** lands on `dmfdeploy` `docs/handoffs/` after Codex clears. The Phase 1 handoff is the template.

## How a fresh agent picks this up

If you are reading this for the first time:

1. Read this entire file once, then re-read the §Phase N that's next-up.
2. Read the Phase 1 handoff (`docs/handoffs/DMF Tier A Phase 1 Implementation Handoff 2026-05-11.md`) for the template.
3. Read the inputs listed in your phase's §Inputs.
4. Pick up the right slice from the dispatch matrix — if the actor for a slice is `qwen-left`/`qwen-right`/`subagent`, your job (as the orchestrator) is to send the per-actor brief; if it says `Claude`, you do the work directly.
5. Verify acceptance criteria before declaring done.
6. Update §Phase N status here (DONE + commit chain) when the phase clears codex.

If a phase brief is incomplete (Phase 3-5 "to be filled in when phase
begins"), the orchestrator's first task on starting that phase is to
flesh out the brief by mirroring Phase 2's format. Commit the fleshed-out
brief BEFORE starting any lifting.
