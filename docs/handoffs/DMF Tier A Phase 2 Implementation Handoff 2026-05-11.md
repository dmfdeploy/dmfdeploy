# DMF Tier A — Phase 2 Implementation Handoff (2026-05-11; live-apply 2026-05-12)

**Plan reference:** [DMF Tier A Phase Execution Plan](../plans/DMF%20Tier%20A%20Phase%20Execution%20Plan%202026-05-11.md), §Phase 2 (Object-storage Terraform + seed bundle).

**Phase 2 commit chain on `dmf-env` main:**

```
d341350  feat(object-storage): generic-s3 Terraform module + seed bundle extension   (initial Terraform-managed attempt)
725212b  feat(b2-diag): operator-runnable B2 credential diagnostic script
0dcb263  feat(b2-buckets): native-API bucket setup for hetzner-arm + aliyun envs    (the pivot — buckets live)
```

**Phase 2 commit chain on `dmfdeploy` main:**

```
41a14df  docs(handoff): Tier A Phase 2 implementation record   (this file — initial)
576a938  docs(plan): mark Phase 2 done in execution plan + record commit chain
<this commit>  docs: Phase 2 docs sync to b2-buckets.sh pivot + live-apply state
```

**Status:** Phase 2 of 6 complete. **Six B2 buckets live and configured across
both envs** (`hetzner-arm` + `aliyun`). The original Terraform-managed
approach is **dormant** — the AWS provider's S3 implementation has three
incompatibilities with B2's S3-Compat API that we couldn't work around
cleanly; replacement is a B2-native script (see §2.6).

This handoff records what was delivered, where to look, and how a reviewer
can verify each piece. Some §2 sub-sections describe artefacts that *exist
in the tree* but are currently dormant — read §2.6 (pivot) before §2.1-2.5
for the up-to-date posture.

---

## 1. Purpose

After Phase 2, `dmf-env` knows how to:

- Provision three S3-compatible buckets per environment via a B2-native
  setup script (`bin/b2-buckets.sh`) — six buckets currently live:
  `dmf-{audit,openbao-snapshots,app-backups}-{hetzner-arm,aliyun}` in
  region `us-west-001` (the operator's B2 account region).
- Carry the bucket coordinates + credentials in the SOPS-encrypted
  bootstrap bundle.
- Seed those coordinates into OpenBao at three new paths
  (`secret/platform/object-storage/{audit, openbao-snapshots, app-backups}`).
- Export the audit-bucket subset as the Ansible variables the
  Phase 1 audit-log-archival role already expects (zero-change consumer).

Phase 2 does NOT consume any of this — that's Phase 3.

---

## 2. What landed — file-by-file, reviewer-checkable

### 2.1 — `terraform/modules/generic-s3/object-storage/` (DORMANT — see §2.6)

| File | Purpose |
|---|---|
| `variables.tf` | Six input variables: `bucket_names`, `endpoint`, `access_key_id` (sensitive), `secret_access_key` (sensitive), `region`, `object_lock_retention_days`. |
| `versions.tf` | `terraform >= 1.6`; `hashicorp/aws ~> 5.80` (pinned during the apply attempts; v6 had the same B2 issues so the pin is not load-bearing); provider block with `skip_credentials_validation`, `skip_metadata_api_check`, `skip_region_validation`, `skip_requesting_account_id`, `s3_use_path_style` all `true`; `endpoints { s3 = var.endpoint }`. |
| `main.tf` | Three `aws_s3_bucket` resources. Audit gets `object_lock_enabled = true`, versioning, Object Lock COMPLIANCE config, and SSE AES256. Other two buckets get versioning + SSE only. CORS resources added as workaround for the GetBucketCors casing mismatch; ultimately not used because the pivot moved aux config to the B2 native API. |
| `outputs.tf` | Three individual `*_bucket_id` outputs + a flattened `buckets` map. |

**Status:** This module is retained in the tree as documentation and as a
template for the eventual migration to the b2-native Terraform provider.
The root module's `module "object_storage"` call is **commented out** in
`terraform/hetzner-arm/main.tf` (see §2.2). Re-enabling will fail until
the AWS provider × B2 incompatibilities are resolved — see §2.6 for the
three specific failure modes encountered.

**Reviewer check:**

```
cat dmf-env/terraform/modules/generic-s3/object-storage/{variables,versions,main,outputs}.tf
```

Look for: `object_lock_enabled = true`, `mode = "COMPLIANCE"`,
`depends_on = [aws_s3_bucket_versioning.audit]`, `skip_*` flags all
present, `sensitive = true` on the two credential vars.

### 2.2 — `terraform/hetzner-arm/main.tf` + `versions.tf` (module call COMMENTED OUT)

**`main.tf`:** the `module "object_storage"` call from `d341350` is now
**commented out** in `0dcb263` with an inline explanation pointing at
the AWS provider × B2 incompatibilities. The buckets at B2 are managed
by `bin/b2-buckets.sh` (see §2.6); tofu state no longer tracks them
(removed via `tofu state rm` in the pivot commit).

**`versions.tf`:** the two sensitive input variables
(`object_storage_access_key_id`, `object_storage_secret_access_key`)
remain declared, with `default = ""` added so `tofu plan` doesn't
prompt for values when the module is dormant. If/when the Terraform
path is re-enabled the operator-supplied `-var-file` mechanism is
unchanged.

**Reviewer check:**

```
git -C dmf-env log -1 -p -- terraform/hetzner-arm/main.tf terraform/hetzner-arm/versions.tf
grep -n 'object_storage' dmf-env/terraform/hetzner-arm/main.tf   # block is in comments only
```

### 2.3 — `manifests/hetzner-arm.yaml` + `manifests/aliyun.yaml`

New top-level `spec.object_storage:` block on both. Both envs are
populated with B2 region `us-west-001` (the operator's B2 account
region). EU-region migration is operator-side init-script work,
deferred per the 2026-05-12 operator decision — the operator will
choose region at env-init time once the init script supports it.

```yaml
spec:
  object_storage:
    audit:
      bucket: dmf-audit-<env>            # dmf-audit-hetzner-arm | dmf-audit-aliyun
      endpoint: https://s3.us-west-001.backblazeb2.com
      region: us-west-001
    openbao_snapshots:
      bucket: dmf-openbao-snapshots-<env>
      endpoint: https://s3.us-west-001.backblazeb2.com
      region: us-west-001
    app_backups:
      bucket: dmf-app-backups-<env>
      endpoint: https://s3.us-west-001.backblazeb2.com
      region: us-west-001
```

Both envs share the same B2 account (keys are account-scoped, not
env-scoped) but use distinct bucket names. Credentials live
exclusively in the encrypted bundle, NOT in either manifest.

### 2.4 — `manifests/README.md`

New `## Object Storage` section. Table summarising the three logical
buckets + retention contract. Explicit note that credentials are
NEVER in the manifest; they live in the bundle and seed into OpenBao.

### 2.5 — `bin/bootstrap-secrets.sh`

Four subcommands extended:

- **`init`** — heredoc-emitted bundle template now includes the three
  `object_storage:` blocks with empty bucket / endpoint / region /
  access_key_id / secret_access_key fields. Operator populates via
  `sops edit`.
- **`doctor`** — validates each `object_storage.<logical>.*` block is
  shape-complete; emits a WARN (not FAIL) when `bucket` is set but
  credentials are empty (provisioning-time error rather than 02:00-cron
  silent failure for the audit-log-archival cron in Phase 1).
- **`seed-bao`** — for each non-empty block, writes
  `secret/platform/object-storage/<logical>` to OpenBao with
  `bucket`, `endpoint`, `region`, `access_key_id`, `secret_access_key`
  as kv fields. Mirrors the existing in-pod `kubectl exec | bao kv put`
  pattern (the values reach bao via in-pod argv only; the host shell
  never sees them in its own argv, consistent with the
  `bootstrap_admin` / `k3s/cluster` / provider-token writes already in
  this script).
- **`export-vars`** — emits the audit block as the five inventory
  variables the Phase 1 audit-log-archival role already consumes:
  `audit_log_s3_bucket`, `audit_log_s3_endpoint`,
  `audit_log_aws_region`, `audit_log_aws_access_key_id`,
  `audit_log_aws_secret_access_key`. `openbao_snapshots` and
  `app_backups` are intentionally NOT exported as Ansible vars —
  Phase 3 delivers them to in-cluster consumers via ESO.

**Reviewer check:**

```
git -C dmf-env log -1 -p -- bin/bootstrap-secrets.sh
bash -n dmf-env/bin/bootstrap-secrets.sh
```

### 2.6 — `bin/b2-buckets.sh` + `bin/lib/b2-buckets.py` (THE PIVOT)

The Terraform-managed path attempted in §2.1-2.2 failed on three
distinct AWS-provider × B2 incompatibilities encountered during
live-apply:

1. **`GetBucketCors` casing mismatch.** AWS S3 returns
   `NoSuchCORSConfiguration` (CORS upper-case) when no CORS rule is
   set; B2's S3-Compat returns `NoSuchCorsConfiguration` (Cors mixed
   case). The AWS provider's error-suppression check matches the
   AWS string only, so every `aws_s3_bucket` Read fatals against B2
   when no CORS rule is set.
2. **`PutBucketTagging` returns 501 NotImplemented.** B2's S3-Compat
   does not support bucket tagging; the AWS provider sends a Tagging
   call on bucket create when `tags {}` is in the resource. Removing
   tags from the module made the apply progress past create but the
   CORS issue still blocked Read.
3. **Side-paths in `PutBucketEncryption` clobber CORS state.** When
   the provider sets default SSE, B2's underlying `b2_update_bucket`
   call also resets `corsRules` if they aren't included in the
   request body — meaning even an out-of-band CORS pre-set gets
   wiped on the next tofu apply.

**Replacement:** `dmf-env/bin/b2-buckets.sh` — a bash wrapper that
dispatches to `dmf-env/bin/lib/b2-buckets.py`. The Python script is
pure stdlib (urllib + json), reads bucket names + endpoint + region
from the env manifest, reads credentials from
`${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>/object-storage.tfvars`, and uses
B2's native API to:

- Create each bucket if missing (`b2_create_bucket` with
  `fileLockEnabled: true` on the audit bucket).
- Configure each bucket via a single `b2_update_bucket` call carrying
  both `corsRules` (permissive, see workaround note) and
  `defaultServerSideEncryption: SSE-B2 AES256`. Combining them in
  one call avoids the side-path clobber problem.

Subcommands:

- `bin/b2-buckets.sh ensure <env>` — idempotent create + configure.
- `bin/b2-buckets.sh show <env>` — read-only state probe per env.

**Object Lock retention** is set per-upload via the audit-log-archival
cron's `--object-lock-mode COMPLIANCE
--object-lock-retain-until-date "+365d"` flags, NOT as a bucket-level
default. B2's `b2_update_bucket` does not accept a
`fileLockConfiguration` field, but having Object Lock *enabled* at
bucket creation is enough to allow per-upload retention — the
compliance posture (audit objects irretrievably retained for 365d) is
identical.

**Reviewer check:**

```
git -C dmf-env log -1 -p -- bin/b2-buckets.sh bin/lib/b2-buckets.py
bash -n dmf-env/bin/b2-buckets.sh && echo "bash -n: clean"
python3 -c "import py_compile; py_compile.compile('dmf-env/bin/lib/b2-buckets.py', doraise=True)"
DMF_BOOTSTRAP_BUNDLE_DIR=<your-bundle-dir> dmf-env/bin/b2-buckets.sh show hetzner-arm
DMF_BOOTSTRAP_BUNDLE_DIR=<your-bundle-dir> dmf-env/bin/b2-buckets.sh show aliyun
```

Both `show` calls should return the 3-row per-bucket table
(`rev:`, `corsRules:`, `SSE:`, `Object Lock:`) for the env.

---

## 3. Verification evidence

### 3.1 Offline checks (Terraform-side artefacts)

Run from `dmf-env/terraform/hetzner-arm/`:

```
tofu init      # AWS provider resolves; hcloud + cloudflare also resolved
tofu validate  # Success! The configuration is valid.
```

`tofu validate` passes because the `module "object_storage"` block is
commented out; the module HCL itself remains syntactically valid for
future use.

Run from `dmf-env/`:

```
bash -n bin/bootstrap-secrets.sh                                  # exit 0
bash -n bin/b2-buckets.sh                                          # exit 0
python3 -c "import py_compile; py_compile.compile('bin/lib/b2-buckets.py', doraise=True)"   # exit 0
python3 -c "import yaml; yaml.safe_load(open('manifests/hetzner-arm.yaml'))"   # exit 0
python3 -c "import yaml; yaml.safe_load(open('manifests/aliyun.yaml'))"        # exit 0
```

All clean.

---

## 4. Backblaze B2 operator runbook (Phase 2 → live)

Account region: `us-west-001` (operator's B2 account region as of
2026-05-12). EU-region migration deferred to per-env region choice in
the init script.

1. **Create a per-account B2 application key** in the B2 console with
   the capabilities: `listBuckets`, `listFiles`, `readBuckets`,
   `writeFiles`, `writeFileRetentions`, `readBucketRetentions`,
   `writeBuckets`, `deleteBuckets` (last two needed for
   `b2-buckets.sh ensure`). DO NOT use the master key. Save the
   `keyID` and `applicationKey` values from the one-time creation
   screen.

2. **Save the creds to `~/.config/backblaze/b2.txt`** as a simple
   `field: value` text file (the format the B2 console displays):

    ```
    keyID: <from B2 console>
    keyName: dmfdeply
    applicationKey: <from B2 console>
    ```

3. **Create the per-env tfvars file** (use `bin/b2-buckets.sh` only
   if you've already done this manually — the script reads tfvars):

    ```
    # Parse keyID + applicationKey from b2.txt into a per-env tfvars file.
    install -d -m 0700 "${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>"
    umask 077
    keyID=$(sed -nE 's/^keyID:[[:space:]]+(.+)$/\1/p' ~/.config/backblaze/b2.txt | tr -d '[:space:]')
    appKey=$(sed -nE 's/^applicationKey:[[:space:]]+(.+)$/\1/p' ~/.config/backblaze/b2.txt | tr -d '[:space:]')
    cat > "${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>/object-storage.tfvars" <<TFVARS
    object_storage_access_key_id     = "${keyID}"
    object_storage_secret_access_key = "${appKey}"
    TFVARS
    chmod 0600 "${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>/object-storage.tfvars"
    unset keyID appKey
    ```

   Same tfvars layout for every env — keys are account-scoped. You
   can `cp` the file across envs once created.

4. **Verify key + endpoint match via `b2-diag.sh`**:

    ```
    DMF_BOOTSTRAP_BUNDLE_DIR=... dmf-env/bin/b2-diag.sh auth <env>
    ```

   The `auth` subcommand calls B2's `b2_authorize_account` and reports
   the canonical `s3ApiUrl`. If it doesn't match the manifest's
   `endpoint`, fix one or the other before continuing.

5. **Create + configure buckets** via the b2-buckets.sh script:

    ```
    DMF_BOOTSTRAP_BUNDLE_DIR=... dmf-env/bin/b2-buckets.sh ensure <env>
    ```

   This creates the three buckets at B2 (with Object Lock enabled on
   the audit bucket) and sets `corsRules` + `defaultServerSideEncryption`
   in a single `b2_update_bucket` call per bucket.

6. **Verify the state**:

    ```
    DMF_BOOTSTRAP_BUNDLE_DIR=... dmf-env/bin/b2-buckets.sh show <env>
    ```

   Expected per env: three buckets, audit has `Object Lock: enabled=True`,
   all three have `SSE: mode=SSE-B2 alg=AES256` and `corsRules: 1
   rule(s)`.

7. **Populate the SOPS bundle** with the same credentials (so seed-bao
   can write them to OpenBao for the in-cluster consumers in Phase 3):

    ```
    sops edit "${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml"
    # Fill the three object_storage.<logical>.{access_key_id, secret_access_key} blocks.
    ```

8. **Seed OpenBao** when the cluster is up:

    ```
    dmf-env/bin/bootstrap-secrets.sh seed-bao <env>
    ```

   This writes the three `secret/platform/object-storage/*` paths.

---

## 5. What this phase does NOT change

- No role in `dmf-infra` consumes the three new OpenBao paths yet.
  Phase 3 (vertical-resilience playbooks) wires the consumers.
- The Terraform module remains in the tree but is **commented out** in
  `terraform/hetzner-arm/main.tf`. No `tofu apply` will be issued
  against `module.object_storage` until the AWS provider × B2
  incompatibilities are resolved or we migrate to the b2-native
  Terraform provider.
- The Phase 1 audit-log-archival role will get its inventory vars
  populated automatically once `bootstrap-secrets.sh export-vars`
  is run for an env with the audit block populated.

---

## 6. Suggested reviewer checklist

- [ ] `tofu validate` clean in `dmf-env/terraform/hetzner-arm/` (module
      call is in comments only)
- [ ] `bash -n dmf-env/bin/bootstrap-secrets.sh` exits 0
- [ ] `bash -n dmf-env/bin/b2-buckets.sh` exits 0
- [ ] `python3 -c "import py_compile; py_compile.compile('dmf-env/bin/lib/b2-buckets.py', doraise=True)"`
      exits 0
- [ ] `dmf-env/manifests/hetzner-arm.yaml` and `manifests/aliyun.yaml`
      both parse as YAML
- [ ] `spec.object_storage:` block populated in BOTH manifests with
      `dmf-{audit,openbao-snapshots,app-backups}-{env}` bucket names
      and `us-west-001` endpoint + region
- [ ] `dmf-env/terraform/hetzner-arm/main.tf` has the `module "object_storage"`
      block commented out with a paragraph explaining the AWS-provider × B2
      incompatibilities — `grep -nA 5 'object_storage' dmf-env/terraform/hetzner-arm/main.tf | head -20`
- [ ] The Terraform module under `terraform/modules/generic-s3/object-storage/`
      remains in the tree for the future b2-native migration
- [ ] `dmf-env/manifests/README.md` documents the new schema
- [ ] `bootstrap-secrets.sh seed-bao` writes three new paths under
      `secret/platform/object-storage/*` —
      `grep -n 'secret/platform/object-storage' dmf-env/bin/bootstrap-secrets.sh`
- [ ] `bootstrap-secrets.sh export-vars` emits the five audit-log-archival
      inventory vars — `grep -nE 'audit_log_(s3|aws)_' dmf-env/bin/bootstrap-secrets.sh`
- [ ] Live state for each env — `dmf-env/bin/b2-buckets.sh show <env>`
      returns three buckets per env with the audit bucket showing
      `Object Lock: enabled=True` and all three showing `SSE: mode=SSE-B2
      alg=AES256` + `corsRules: 1 rule(s)`
- [ ] gitleaks pre-commit passed on each staged commit (no operator
      usernames, secure-store paths, or credential values in the diff)

---

## 7. Open items for Phase 3

- Phase 3's first lifting task: write the
  `object-storage-credentials` Ansible role that consumes the three
  OpenBao paths via ESO ClusterSecretStores + ExternalSecrets and
  materializes them into Kubernetes Secrets in the namespaces of
  the four backup-CronJob roles (longhorn-backup-target,
  openbao-raft-snapshot, postgres-backups, zot-mirror).
- Migration to the b2-native Terraform provider (or a fix to the
  AWS provider's `NoSuchCorsConfiguration` casing match) would let
  us re-enable the dormant `module "object_storage"` and remove
  `b2-buckets.sh` as a dependency. Not on the Tier A critical path.
- EU-region migration is deferred to per-env region choice in the
  init script (operator decision 2026-05-12). Buckets currently in
  `us-west-001`; documented in the readiness plan's Aliyun TIA stub
  (Phase 5 docs work).
- The generic-s3 module's module-internal provider pattern is fine
  for single-target use today. If/when a second env (e.g. aliyun)
  also wants its own buckets, refactor to the
  `configuration_aliases` + root-module-provider pattern per the
  Phase 2 research findings (recorded in the agent-bridge transcript
  and the subagent summary). Not a blocker for Phase 3.
- The argv-secrets pattern in `bao kv put` calls inside `seed-bao` is
  pre-existing repo discipline (matches `bootstrap_admin`, `k3s/cluster`,
  provider tokens — all written the same way). Worth a script-wide
  refactor to stdin-fed `bao kv put PATH @-` form as a separate
  cleanup commit; not Phase 2's scope.
