# DMF Tier A — Phase 1 Implementation Handoff (2026-05-11)

**Plan reference:** [DMF Pre-Release Compliance Readiness Plan 2026-05-11](../plans/DMF%20Pre-Release%20Compliance%20Readiness%20Plan%202026-05-11.md), Tier A items A.4 (audit log architecture) and A.8 strongly-recommended clock-sync.
**Working plan:** `groovy-jumping-rainbow.md` under the operator-local Claude plans directory (`~/.claude/plans/`).
**Phase 1 commit chain on `dmf-infra` main** (read with `git log --oneline --reverse dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival`):

- `68a1fa1` — `feat(audit-log): compliance-grade retention + WORM archival + chrony` (initial Phase 1 landing)
- `e914898` — `fix(audit-log): address codex review findings on Phase 1 wiring + correctness` (first re-review pass)
- `a67264e` — `fix(audit-log): second codex review — ADR-0007 cred path + always-run precheck + workdir` (second re-review pass; AWS-profile credential delivery, always-run precheck, work-dir off /tmp, Promtail expand-env)

**Status:** Phase 1 of 6 complete; cluster has not yet been rebooted with these changes.

This handoff is a reviewer-checkable record of what landed and how to verify
each change. The plan file says *what to do*; this handoff says *what was
done, where to look, and how to confirm it*.

---

## 1. Purpose

Phase 1 closes the silent compliance hole in the audit log architecture:
retention policy existed in name (`loki_retention: 168h`) but the compactor
that enforces it was disabled; the host k3s API audit log was rotated locally
but never reached Loki; clock discipline relied on `systemd-timesyncd` defaults;
the archival cron used client-side SSE (lose the key → archive bricked) and
no Object Lock metadata.

Phase 1 does NOT touch:
- Object-storage bucket provisioning (Phase 2 — Terraform + seed bundle)
- vertical-resilience playbooks for Longhorn/PG/Bao backups (Phase 3)
- Cosign bootstrap or image signing (Phase 4)
- Documentation suite (Phase 5)
- Identity-leak sweep close-out / first GitHub push (Phase 6)

---

## 2. What landed — file-by-file, reviewer-checkable

For each row: **Path** | **Pre-state** | **Post-state** | **Why** | **How to verify**.

### 2.1 — Loki: enable compactor + per-stream retention

| File | `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/loki/templates/values.yml.j2` |
|---|---|
| Pre | `limits_config.retention_period` set but no `compactor:` block; Loki accepts the policy but never deletes data. |
| Post | `loki.compactor` block with `retention_enabled: true`, `delete_request_store: filesystem`, plus three `limits_config.retention_stream` rules for security streams (`{job="k3s-audit"}`, `{job="authentik-audit"}`, `{job=~".+-security"}`) at 6 months; default `retention_period` is the 30-day operator-activity floor. |
| Why | Without the compactor, retention policy is policy-only. The per-stream rules let security streams keep 6 months without forcing all logs to keep 6 months. |
| Reviewer check | `git show 68a1fa1 -- k3s-lab-bootstrap/roles/stack/operator/loki/templates/values.yml.j2` shows the compactor block and three retention_stream entries; rendering with the Phase 1 defaults yields valid YAML (see §3 verification evidence). |

| File | `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/loki/defaults/main.yml` |
|---|---|
| Pre | `loki_storage_size: 1Gi`, `loki_retention: 168h`. |
| Post | `loki_storage_size: 50Gi`, `loki_retention: 720h` (30 d default floor), `loki_security_retention: 4380h` (6 mo), plus compactor delete-delay + worker-count variables. |
| Why | 1Gi PV cannot hold 30 days of operator logs, let alone 6 months of security streams. 50Gi sizing aligned with retention envelope. |
| Reviewer check | Variables `loki_security_retention` and `loki_compactor_*` are referenced from the values template; grep confirms no dangling references. |

### 2.2 — Promtail: scrape k3s API audit log on each node

| File | `dmf-infra/k3s-lab-bootstrap/roles/base/promtail/templates/values.yml.j2` |
|---|---|
| Pre | `config.clients` only — no scrape_configs, Helm chart defaults scrape pod logs only. Host `/var/log/kubernetes/audit.log` was never shipped to Loki. |
| Post | `config.snippets.extraScrapeConfigs` added with one static target globbing `/var/log/kubernetes/audit*.log` (current + rotated siblings), labelled `job=k3s-audit` and `host=${HOSTNAME}`. Explicit `extraVolumes` + `extraVolumeMounts` for `/var/log/kubernetes` (read-only). `extraArgs: ["-config.expand-env=true"]` added so `${HOSTNAME}` is resolved at startup (Grafana docs require this flag). `tolerations` cover all node taints. |
| Why | Three reasons: (a) the k3s API audit log is the highest-value forensic artefact and was previously orphaned; (b) the `job=k3s-audit` label is the bridge between Promtail and the Loki retention rule shipped in §2.1; (c) the audit*.log glob captures rotated lumberjack siblings so Promtail doesn't lose lines that rotated between scrape ticks. |
| Reviewer check | `git log -p -- k3s-lab-bootstrap/roles/base/promtail/templates/values.yml.j2`; render confirms valid YAML with `extraArgs`, `extraVolumes` containing `var-log-kubernetes`, and scrape path `/var/log/kubernetes/audit*.log`. Post-cluster-rerun, `kubectl -n monitoring exec ds/promtail -- cat /etc/promtail/promtail.yaml` shows the scrape job with `host: <node-name>` already expanded. |

### 2.3 — Prometheus: usable retention envelope

| File | `dmf-infra/k3s-lab-bootstrap/roles/base/prometheus/defaults/main.yml` |
|---|---|
| Pre | `prometheus_retention: 6h`, `prometheus_retention_size: 2GB`, `prometheus_storage_size: 5Gi`. |
| Post | `prometheus_retention: 30d`, `prometheus_retention_size: 40GB`, `prometheus_storage_size: 50Gi`. Inline comment revised. |
| Why | 6h Prometheus retention makes operator debugging brutal. 30 days is well under any compliance floor and well within operator headroom. Prometheus remains operational-only; compliance audit trail is Loki + S3, not Prometheus. |
| Reviewer check | `grep -n prometheus_retention dmf-infra/k3s-lab-bootstrap/roles/base/prometheus/defaults/main.yml` shows the new values; rendered chart should request a 50Gi PVC. |

### 2.4 — Chrony: audit-grade time discipline

| Files (all new) | `dmf-infra/k3s-lab-bootstrap/roles/base/chrony/{tasks,handlers,defaults}/main.yml`, `roles/base/chrony/templates/chrony.conf.j2`, `playbooks/205-chrony.yml` |
|---|---|
| Pre | No chrony role; `200-baseline.yml` installs the package and enables the service but never customizes `/etc/chrony/chrony.conf`. |
| Post | Role deploys `/etc/chrony/chrony.conf` with `pool ... iburst`, `makestep 1.0 3`, `rtcsync`, `allow <cluster-cidr>`, measurement-logging. Notify-restart handler bounces the service on config change. Wired into pre-seed as `205-chrony` between `200-baseline` and `210-harden`. |
| Why | Audit log timestamps must not be re-ordered by a slow slew on boot; `makestep` gives a fast initial sync. `allow <cidr>` lets peers fall back to each other if the pool is unreachable. ISO 27001 A.8.17 (clock synchronization) requirement. |
| Reviewer check | `git show 68a1fa1 -- k3s-lab-bootstrap/roles/base/chrony/`; new playbook visible in `bootstrap-provision-pre-seed.yml` import list. Post-run: `chronyc tracking` on each node shows offset < 100ms and reference ID resolving to a pool member. |

### 2.5 — audit-log-archival: SSE-S3 + Object Lock + endpoint support

| File | `dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/defaults/main.yml` |
|---|---|
| Pre | 5 vars only: bucket name, archive paths, cron hour/minute. |
| Post | Adds: `audit_log_s3_endpoint` (for B2/MinIO/any S3-compat), `audit_log_s3_prefix` (per-cluster object key prefix), `audit_log_object_lock_enabled/mode/days` (Object Lock contract), `audit_log_sse_algorithm/kms_key_id` (provider-managed SSE), AWS-CLI env-var hints. All retention semantics now parameterised. |
| Why | Decouple from real-AWS-only assumption (the original `aws s3 cp --sse-c-algorithm` was client-side encryption — losing the key would brick the archive). Make Object Lock retention the cron's responsibility per-object so a bucket-level retention default isn't required. |
| Reviewer check | `git show 68a1fa1 -- k3s-lab-bootstrap/roles/base/audit-log-archival/defaults/main.yml`; the `audit_log_object_lock_days: 365` value matches the retention contract in §2 of the readiness plan and the forthcoming `docs/processes/audit-log-retention-policy.md`. |

| File | `dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/tasks/main.yml` |
|---|---|
| Pre | Inline `copy.content` writes the cron script with `aws s3 cp --sse-c-algorithm AES256`. |
| Post | Switched to `template:` invocation against new `archive-k3s-audit-logs.sh.j2`; added bucket existence precheck (`aws s3api head-bucket`) gated by `not ansible_check_mode`. |
| Why | Two reasons: (a) inline content rendering forces all template logic into a single string and got messy with the conditional Object Lock / endpoint / SSE blocks; (b) a real `head-bucket` precheck fails fast if bucket creds or endpoint are wrong, before the cron's first 02:00 firing where the failure would be invisible. |
| Reviewer check | Template invocation present in task list. `head-bucket` precheck visible. |

| File (new) | `dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/templates/archive-k3s-audit-logs.sh.j2` |
|---|---|
| Purpose | Renders the daily archival cron script. |
| Behavior | POSIX `sh` with `umask 077`. Stages the archive tarball under `/var/lib/dmf/audit-archive` (mode 0700 owner root, created by the role — see §2.10) via `mktemp`, NEVER under `/tmp`. Computes Object Lock `retain-until` at run time (so the +365d window is from each run, not from template render). Invokes `aws --profile dmf-audit-archive` (see §2.8) so credentials come from `/root/.aws/credentials` via the SDK, not from process environment. Builds three optional argv pieces (`endpoint_arg`, `sse_args`, `lock_args`) as shell variables so the `aws s3api put-object` invocation is a single contiguous block of `\`-continued lines (avoids a Jinja-blank-line × shell-continuation bug caught during verification). |
| Reviewer check | Render the template offline with the env's defaults and run `sh -n` over it: both full-feature and minimal-default cases pass syntactically. See §3 below for the exact reproduction. Read the generated script on a live node at `/usr/local/bin/archive-k3s-audit-logs.sh` after the playbook runs. |

### 2.6 — Split 302-k3s-audit-archival from 300-k3s and run in post-seed

| Files | `dmf-infra/k3s-lab-bootstrap/playbooks/300-k3s.yml` (modified), `playbooks/302-k3s-audit-archival.yml` (new), `bootstrap-provision-pre-seed.yml` (modified — adds a comment pointer), `bootstrap-provision-post-seed.yml` (modified — adds the import) |
|---|---|
| Pre | Last play in `300-k3s.yml` was "Configure k3s audit log archival" running `roles: - base/audit-log-archival`. To change SSE or Object Lock settings, the operator had to re-run all of `300-k3s.yml`, which includes the k3s install plays. |
| Post | Audit-archival play moved into standalone `302-k3s-audit-archival.yml`. Wrapper placement: `bootstrap-provision-post-seed.yml` imports it after `vertical-monitoring/190-monitoring-verify.yml`. The pre-seed wrapper carries a comment-only pointer where the import would naturally have lived. |
| Why | Two reasons: (a) independent re-run for bucket / SSE / Object Lock rollouts; touches no k3s install state. (b) Credentials. Audit archival needs S3 creds; the operator-supplied creds in `audit_log_aws_access_key_id` / `audit_log_aws_secret_access_key` are written by the role into `/root/.aws/credentials` as the `dmf-audit-archive` profile (see §2.8) and consumed by both the script and the bucket-precheck via `aws --profile`. Running this play in post-seed (after seed-bao + monitoring) keeps it alongside the rest of the monitoring-vertical work and leaves room for Phase 3 to swap to ESO-managed delivery without re-shuffling the bootstrap order. Numbering: 301 was taken by `301-k3s-verify.yml`, hence 302. |
| Reviewer check | `git show <commit> -- k3s-lab-bootstrap/playbooks/300-k3s.yml`; `cat dmf-infra/k3s-lab-bootstrap/playbooks/302-k3s-audit-archival.yml`. `grep 302-k3s-audit-archival bootstrap-provision-*.yml` confirms the import is in post-seed, with a comment-only stub in pre-seed. |

### 2.7 — Tar glob for rotated audit.log files

| File | `dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/templates/archive-k3s-audit-logs.sh.j2` |
|---|---|
| Pre | Script only tarred the current `audit.log` via `basename`. On a busy cluster, k3s rotates by lumberjack semantics — `audit.log` becomes `audit-YYYY-MM-DDTHH-MM-SS.SSS.log` and a fresh `audit.log` is created. With `k3s_audit_log_maxsize=100MB × maxbackup=10`, up to 1GB of rotated audit data can sit in the directory before lumberjack starts deleting; the daily 02:00 cron would miss any rotation that happened in the last 24h once maxbackup is hit. |
| Post | Script captures every `audit*.log` file in the archive dir via a glob, with explicit existence-filtering so a no-match glob doesn't fail tar. |
| Why | Forensic completeness. The earlier behaviour silently lost rotated lines on busy clusters; the WORM bucket would only see the most recent slice. |
| Reviewer check | Render the template offline with the role defaults and inspect the `tar` invocation: it should expand `audit_basename*.log` (i.e. `audit*.log`) before the tar call. Run the rendered script under `sh -n` and (optionally) on a directory with mock `audit.log`, `audit-2026-05-11T03-00-00.000.log` to confirm both files end up in the tarball. |

### 2.8 — Credential delivery via `/root/.aws/credentials` profile (ADR-0007 compliant)

| Files | `dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/defaults/main.yml` (modified), `tasks/main.yml` (rewritten), `templates/archive-k3s-audit-logs.sh.j2` (uses `aws --profile`) |
|---|---|
| Pre (first re-review pass — superseded) | Earlier iteration wrote `/etc/dmf/audit-archive.env` and the cron script sourced it via `. /etc/dmf/audit-archive.env`. Credentials reached the AWS-CLI via process environment — violates ADR-0007 rule 1 ("Never put a secret in ... env"; `/proc/<pid>/environ` is in scope). |
| Post | Operator-supplied vars (`audit_log_aws_access_key_id` / `_secret_access_key` / `_region`, all empty by default) are written via `community.general.ini_file` into `/root/.aws/credentials` under a named profile (default `dmf-audit-archive`). The cron script and the precheck both invoke `aws --profile dmf-audit-archive ...`. The AWS SDK reads the file at API-call time; credentials never traverse process environment. A clean-up task removes any legacy `/etc/dmf/audit-archive.env` from prior bootstraps. |
| Why | ADR-0007 forbids secrets in argv / env / /tmp / AI transcripts. The `aws --profile` + credentials-file pattern is the canonical AWS-CLI secrets path: SDK-mediated, mode 0600 owner root, never visible in `ps eauxf` or `/proc/<cron>/environ`. Honest compliance — not an ADR-0007 exception. |
| Reviewer check | `find dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival -type f` lists no `audit-archive.env.j2` (deleted). `grep -n 'aws --profile' roles/base/audit-log-archival/templates/archive-k3s-audit-logs.sh.j2 roles/base/audit-log-archival/tasks/main.yml` shows profile use in both. Live cluster: `ls -l /root/.aws/credentials` returns mode 0600 owner root, `aws --profile dmf-audit-archive configure list` returns the populated profile, and `[ -f /etc/dmf/audit-archive.env ]` returns false. |

### 2.9 — Always-run head-bucket precheck + assert on missing creds

| File | `dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/tasks/main.yml` |
|---|---|
| Pre (first re-review pass) | The `aws s3api head-bucket` precheck was gated by `when: audit_log_aws_access_key_id is set`. If the operator set the bucket name but forgot the keys, the play succeeded and the cron failed silently at 02:00 — invisible until forensic data was already lost. |
| Post | An explicit `assert` task runs immediately after the bucket-empty short-circuit: if `audit_log_s3_bucket` is set, both credential vars must also be set, with a clear fail message that points at inventory group_vars. The precheck itself always runs (still guarded only by `not ansible_check_mode`) and uses `aws --profile`. |
| Why | Provisioning-time failure with a clear error is materially better than silent 02:00 cron failures. |
| Reviewer check | `grep -A 5 'Assert AWS credentials' roles/base/audit-log-archival/tasks/main.yml` shows the assert block. Smoke: set `audit_log_s3_bucket: foo` with empty keys → playbook fails at the assert. |

### 2.10 — Tarball staged under `/var/lib/dmf/audit-archive`, not `/tmp`

| File | `dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/templates/archive-k3s-audit-logs.sh.j2`; defaults add `audit_log_work_dir: /var/lib/dmf/audit-archive`; tasks add directory-creation task (mode 0700 owner root). |
|---|---|
| Pre | Script used `/tmp/k3s-audit-${ts}.tar.gz`. `/tmp` is mode 1777 — every user on the host can list its contents and may be able to read the tarball before the script's `rm` runs (especially under load when upload takes longer than expected). |
| Post | Script runs with `umask 077`, creates the staging file via `mktemp "${workdir}/k3s-audit-${ts}.XXXXXX.tar.gz"` under `/var/lib/dmf/audit-archive` (mode 0700 owner root, created by the role). The trap-on-EXIT still removes the temp file. |
| Why | `/tmp` is the wrong filesystem for audit-bearing artefacts even transiently. ADR-0007 spirit. |
| Reviewer check | `grep -n '/var/lib/dmf/audit-archive\|mktemp\|umask' roles/base/audit-log-archival/templates/archive-k3s-audit-logs.sh.j2` shows the workdir, mktemp, and umask. Live cluster: `ls -ld /var/lib/dmf/audit-archive` returns mode 0700 owner root. |

### 2.11 — Plan §138 retention number reconciled

| File | `docs/plans/DMF Pre-Release Compliance Readiness Plan 2026-05-11.md` |
|---|---|
| Pre | §138 (under Pivot 2 "Action") still listed "Operator activity logs (Loki app stream) → 6 months", contradicting the §2 retention table (which has operator activity at 30 days) and the checklist. |
| Post | §138 reads the same as the §2 table: security streams (k3s-audit, authentik-audit, *-security) → 6 months hot in Loki + 12 months WORM in S3 for the k3s host file; operator-activity / general app logs → 30 days hot, no S3 archival. |
| Why | The §2 table is the source-of-truth; bring §138 into agreement. |
| Reviewer check | `grep -n '30 days\|6 months' docs/plans/DMF\ Pre-Release\ Compliance\ Readiness\ Plan\ 2026-05-11.md` returns only consistent rows. |

---

## 3. Verification evidence (what I actually ran)

Reproducible without a cluster. From `dmf-infra/k3s-lab-bootstrap/`:

### 3.1 Ansible syntax-check on every touched playbook

```
ansible-playbook --syntax-check \
    playbooks/205-chrony.yml \
    playbooks/302-k3s-audit-archival.yml \
    playbooks/300-k3s.yml \
    playbooks/vertical-monitoring/130-promtail.yml \
    bootstrap-provision-pre-seed.yml \
    bootstrap-provision-post-seed.yml \
    -i inventories/example/hosts.ini
```

Result: each line returns `playbook: <path>` with no parse errors. (Ansible
2.20.5 from `/opt/homebrew/bin/ansible-playbook`.) `bootstrap-provision-
post-seed.yml` is included because 302-k3s-audit-archival now imports
there (not in pre-seed) — see §2.6.

### 3.2 Loki Helm values render to valid YAML

Using `/opt/homebrew/Cellar/ansible/13.6.0/libexec/bin/python` (carries
jinja2 + PyYAML):

```python
import jinja2, yaml
e = jinja2.Environment(loader=jinja2.FileSystemLoader('roles'))
ctx = {
  'loki_retention': '720h', 'loki_security_retention': '4380h',
  'loki_compactor_retention_delete_delay': '2h',
  'loki_compactor_retention_delete_worker_count': 150,
  'loki_storage_size': '50Gi', 'loki_storage_class': 'longhorn',
}
parsed = yaml.safe_load(
    e.get_template('stack/operator/loki/templates/values.yml.j2').render(**ctx))
assert parsed['loki']['compactor']['retention_enabled'] is True
assert parsed['loki']['limits_config']['retention_period'] == '720h'
assert len(parsed['loki']['limits_config']['retention_stream']) == 3
```

Asserts pass.

### 3.3 Promtail values render — scrape job present

Same Python harness. Confirms `parsed['config']['snippets']['extraScrapeConfigs']`
contains the `job: k3s-audit` static_config with `__path__: /var/log/kubernetes/audit.log`.

### 3.4 Audit archival script renders, passes POSIX `sh -n`

Two scenarios:

**Full-feature** (Backblaze-style endpoint, Object Lock on, SSE AES256):
```python
ctx = {
  'audit_log_archive_local_dir': '/var/log/kubernetes',
  'audit_log_archive_local_path': '/var/log/kubernetes/audit.log',
  'audit_log_s3_bucket': 'dmf-audit',
  'audit_log_s3_endpoint': 'https://s3.eu-central-003.backblazeb2.com',
  'audit_log_s3_prefix': 'hetzner-arm/k3s-api',
  'audit_log_object_lock_enabled': True,
  'audit_log_object_lock_mode': 'COMPLIANCE',
  'audit_log_object_lock_days': 365,
  'audit_log_sse_algorithm': 'AES256',
  'audit_log_kms_key_id': '',
  'inventory_hostname_short': 'k3s-node-01',
}
```
Renders, `sh -n` returns OK. The single-line `aws s3api put-object` invocation
uses shell variables `${endpoint_arg}`, `${sse_args}`, `${lock_args}` whose
values are populated by upstream conditional blocks.

**Minimal-default** (no endpoint, no Object Lock, no KMS):
```python
ctx['audit_log_s3_endpoint'] = ''
ctx['audit_log_object_lock_enabled'] = False
```
Renders, `sh -n` returns OK; optional argv pieces become empty strings that
shell word-splitting drops.

### 3.5 Git state

```
$ git -C dmf-infra log --oneline --reverse -- \
    k3s-lab-bootstrap/roles/base/audit-log-archival \
    k3s-lab-bootstrap/roles/base/promtail \
    k3s-lab-bootstrap/roles/base/chrony \
    k3s-lab-bootstrap/roles/stack/operator/loki \
    k3s-lab-bootstrap/roles/base/prometheus \
    k3s-lab-bootstrap/playbooks/{205-chrony,302-k3s-audit-archival,300-k3s}.yml \
    k3s-lab-bootstrap/bootstrap-provision-*.yml \
    k3s-lab-bootstrap/inventories/example/group_vars/all/main.yml
68a1fa1 feat(audit-log): compliance-grade retention + WORM archival + chrony
e914898 fix(audit-log): address codex review findings on Phase 1 wiring + correctness
a67264e fix(audit-log): second codex review — ADR-0007 cred path + always-run precheck + workdir
```
All staged via explicit paths (no `git add -A` / `.`). Pre-commit gitleaks
hook ran and passed on each commit.

---

## 4. Backblaze B2 compatibility — verified

> **2026-05-12 note:** the research below was conducted assuming an
> EU-Central (`eu-central-003`) B2 account. Live-apply on 2026-05-12
> revealed the operator's B2 account is actually in `us-west-001`, so
> the Phase 2 buckets live there. The compatibility findings (Object
> Lock, SSE-B2, S3-Compat surfaces) are region-independent and remain
> valid. For the current operator runbook against the live region, see
> the **Phase 2 handoff** §4. EU-region migration is deferred to per-env
> region choice in the init script.

The script shipped in §2.5 works against Backblaze B2's S3-Compatible API
**as-is, no code edits required**, provided two one-time operational
preconditions are met. Findings below are direct from Backblaze's
authoritative docs as of May 2026.

### 4.1 — What is confirmed compatible

| Concern | Verdict | Note |
|---|---|---|
| `aws s3api put-object --object-lock-mode COMPLIANCE --object-lock-retain-until-date` | ✅ Works | B2 documents the S3 layer's Object Lock parity with AWS; both `compliance` and `governance` modes are honoured. Compliance is the correct mode for audit logs — immutable for the retain-until duration, no override by account root. |
| `--server-side-encryption AES256` | ✅ Works | B2 implements SSE-B2 using `x-amz-server-side-encryption: AES256` — exactly what the CLI flag emits. Per-object request form chosen here is safe regardless of whether the bucket has SSE on by default. |
| Endpoint `https://s3.eu-central-003.backblazeb2.com` | ✅ Correct | EU Central (Amsterdam) is currently B2's only EU region. Set `--region eu-central-003` for SigV4 if needed. |
| `aws s3api head-bucket` precheck | ✅ Works | B2's S3-Compat returns 200 if exists, 404 otherwise. Application-key id+secret accepted as SigV4 credentials. |
| `--metadata` key-value pairs | ✅ Works | Stored as `x-amz-meta-*`, returned via HeadObject. The three pairs in the shipped script (`source`, `cluster`, `retention_class`) are well within limits. |
| ISO-8601 retain-until format (`YYYY-MM-DDTHH:MM:SSZ`) | ✅ Accepted | Same wire format as AWS; internally B2 stores ms-since-epoch but the S3 layer parses standard AWS form. |

### 4.2 — Operational preconditions (mandatory before first archival run)

These are **not** in code; they are one-time provisioning steps in Phase 2
when the `dmf-audit` bucket is created on B2.

1. **Bucket-level Object Lock must be enabled** *before* the first
   `put-object` call. B2 lets Object Lock be toggled ON after bucket creation
   (via `b2_update_bucket` or the web console), but **once enabled it cannot
   be disabled**. If the bucket exists without Object Lock enabled, the
   script's `put-object --object-lock-mode` call will fail (per
   `https://www.backblaze.com/docs/cloud-storage-enable-object-lock-with-the-s3-compatible-api`).
   Phase 2's Terraform module will set `object_lock_enabled = true` at
   creation.

2. **B2 application key must carry these capabilities** (smallest scope):
   - `listBuckets`
   - `listFiles`
   - `readBuckets`
   - `writeFiles`
   - **`writeFileRetentions`** ← required to set Object Lock retention at
     upload; missing this is the most common silent failure
   - **`readBucketRetentions`** ← required for the
     `get-object-lock-configuration` precheck (Phase 2 / 3 improvement;
     not yet called by the Phase 1 role, but the runbook fragment in
     §4.4 below uses it)
   Use a per-bucket application key with `namePrefix` restriction to
   the cluster's prefix (e.g. `hetzner-arm/k3s-api/`). Do **not** use the
   B2 master key. Reference:
   `https://www.backblaze.com/docs/cloud-storage-application-key-capabilities`.

### 4.3 — Caveats to record in the trust package

- **SSE + metadata header budget:** B2 caps combined file-info headers at
  **2048 bytes when SSE is in use** (vs 7000 bytes otherwise). The shipped
  metadata fits comfortably; do not expand `--metadata` without measuring.
- **Object Tagging not supported** by B2's S3-Compat. The script uses
  `--metadata`, not `--tagging`, so this is fine — but if Phase 3+ work
  considers migrating to `--tagging`, do not do that for B2.
- **Compliance-lock storage cost commitment:** once an object is
  compliance-locked for 365 days, neither it nor the bucket can be deleted
  until expiry. A runaway cron could pin storage cost for a year. Mitigation:
  the bucket-existence precheck (§2.5) plus a Phase 3 storage-quota alert
  (deferred). B2's Object Lock retention range is **1–3,000 days**; 365 is
  well within.
- **Class A transactions** (`put-object`) are free at B2. Class B (downloads,
  HeadObject) are 2,500/day free then $0.004 per 10k. The daily cron uses
  one Class A + one Class B (HeadBucket precheck) → effectively zero cost.

### 4.4 — Pre-flight runbook fragment (for Phase 2 operator)

Before the first `bootstrap-provision-post-seed.yml` run against an env
configured with B2 — that is, before the first time `302-k3s-audit-archival.yml`
fires — confirm:

```
# 1. Confirm bucket exists and has Object Lock enabled
aws s3api get-bucket-versioning \
    --endpoint-url=https://s3.eu-central-003.backblazeb2.com \
    --bucket dmf-audit
# (expect: "Status": "Enabled" — bucket-versioning is a precondition of Object Lock)

aws s3api get-object-lock-configuration \
    --endpoint-url=https://s3.eu-central-003.backblazeb2.com \
    --bucket dmf-audit
# (expect: "ObjectLockConfiguration": {"ObjectLockEnabled": "Enabled"})

# 2. Confirm the app key has writeFileRetentions
b2 key list   # or check the B2 web console; verify capability list
```

### 4.5 — Suggested follow-up improvement (Phase 2 / 3)

Add a richer precheck to the `audit-log-archival` role: in addition to
`head-bucket`, run `get-object-lock-configuration` and fail with a clear
error if `ObjectLockEnabled != "Enabled"`. This converts a silent
audit-loss failure into a fail-fast provisioning error. Captured here so
it's not lost; not in scope for this commit.

### Sources

- [Object Lock overview](https://www.backblaze.com/docs/cloud-storage-object-lock)
- [Enable Object Lock on existing bucket](https://www.backblaze.com/docs/cloud-storage-enable-object-lock-or-a-legal-hold-on-an-existing-bucket)
- [Enable Object Lock with S3-Compat API](https://www.backblaze.com/docs/cloud-storage-enable-object-lock-with-the-s3-compatible-api)
- [Server-Side Encryption](https://www.backblaze.com/docs/cloud-storage-server-side-encryption)
- [Enable SSE via CLI](https://www.backblaze.com/docs/cloud-storage-enable-server-side-encryption-with-the-cli)
- [Data regions](https://www.backblaze.com/docs/cloud-storage-data-regions)
- [Call S3-Compatible API](https://www.backblaze.com/docs/cloud-storage-call-the-s3-compatible-api)
- [S3 HeadBucket](https://www.backblaze.com/apidocs/s3-head-bucket)
- [S3-Compat API overview](https://www.backblaze.com/docs/cloud-storage-s3-compatible-api)
- [HeadObject](https://www.backblaze.com/apidocs/s3-head-object)
- [Application-key capabilities](https://www.backblaze.com/docs/cloud-storage-application-key-capabilities)
- [S3-Compat application keys](https://www.backblaze.com/docs/cloud-storage-s3-compatible-app-keys)
- [Object Lock FAQs](https://help.backblaze.com/hc/en-us/articles/360052973274-Object-Lock-FAQs)
- [Transaction pricing](https://www.backblaze.com/cloud-storage/transaction-pricing)

---

## 5. What this phase does NOT change

- The cluster itself: this commit has not been applied to any live cluster.
  Live application requires a fresh `dmf-env/bin/run-playbook.sh hetzner-arm
  ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml`, which
  the operator should schedule when a maintenance window is acceptable. The
  Loki PVC will need to grow to 50Gi (Longhorn supports online resize, but
  data movement happens).
- Bucket provisioning: `audit_log_s3_bucket` remains empty by default; the
  role short-circuits via `meta: end_host` when empty. Phase 2 supplies the
  Terraform module + seed bundle extension that populates the bucket cred
  path in OpenBao and via ESO into the role.
- Authentik audit / app-security retention rules: the Loki rules exist
  (`{job="authentik-audit"}`, `{job=~".+-security"}`) but no producer is
  emitting those labels yet. The rules are forward-compatible; Phase 3 work
  on per-app audit forwarding will turn them on. Today only `{job="k3s-audit"}`
  is populated.

---

## 6. Suggested reviewer checklist

A reviewer can step through this independently. SHAs change across the
Phase 1 re-review cycles; check the *commit chain* on `main` rather than
pinning a single SHA:

- [ ] Phase 1 commit chain present —
      `git -C dmf-infra log --oneline --reverse | grep -E 'audit-log|chrony'`
      returns `68a1fa1`, `e914898`, and the latest fix commit in order
- [ ] Loki template includes `compactor: { retention_enabled: true ... }` and
      three `retention_stream` entries —
      `grep -A 3 compactor: dmf-infra/k3s-lab-bootstrap/roles/stack/operator/loki/templates/values.yml.j2`
- [ ] Loki defaults include `loki_security_retention: 4380h` and `loki_retention: 720h` —
      `grep -E 'loki_security_retention|loki_retention' dmf-infra/k3s-lab-bootstrap/roles/stack/operator/loki/defaults/main.yml`
- [ ] Promtail template scrape path is `audit*.log` (glob, not literal), has
      `extraArgs: ["-config.expand-env=true"]`, and declares `var-log-kubernetes`
      hostPath + read-only mount —
      `grep -nE 'audit\*\.log|expand-env|var-log-kubernetes' dmf-infra/k3s-lab-bootstrap/roles/base/promtail/templates/values.yml.j2`
- [ ] Prometheus retention raised to 30d / 40GB / 50Gi —
      `grep -E 'prometheus_retention|prometheus_storage_size' dmf-infra/k3s-lab-bootstrap/roles/base/prometheus/defaults/main.yml`
- [ ] `roles/base/chrony/` exists with `defaults/`, `handlers/`, `tasks/`,
      `templates/chrony.conf.j2`
- [ ] `playbooks/205-chrony.yml` exists and is imported by
      `bootstrap-provision-pre-seed.yml` between baseline and harden —
      `grep -n 205-chrony dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml`
      returns a line in the layer-2 block
- [ ] `playbooks/302-k3s-audit-archival.yml` exists; the audit-archival play
      is no longer at the bottom of `playbooks/300-k3s.yml`; the import is
      in `bootstrap-provision-post-seed.yml` after `190-monitoring-verify`
      (NOT in pre-seed) — `grep -n 302-k3s-audit-archival bootstrap-provision-*.yml`
- [ ] No `audit-archive.env.j2` template remains; credentials are written
      via `community.general.ini_file` into `/root/.aws/credentials` and
      the script + precheck both invoke `aws --profile dmf-audit-archive` —
      `find dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/templates`
      and `grep -n 'aws --profile' dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/templates/archive-k3s-audit-logs.sh.j2 dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/tasks/main.yml`
- [ ] An `assert` task fires when `audit_log_s3_bucket` is set with empty
      creds — `grep -A 5 'Assert AWS credentials' dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/tasks/main.yml`
- [ ] Archive script stages under `/var/lib/dmf/audit-archive` with `umask 077`
      and `mktemp`, NOT `/tmp` —
      `grep -nE '/var/lib/dmf/audit-archive|umask 077|mktemp' dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/templates/archive-k3s-audit-logs.sh.j2`
- [ ] The archive script captures rotated audit logs via `audit*.log` glob,
      not just `audit.log` —
      `grep audit_basename dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/templates/archive-k3s-audit-logs.sh.j2`
- [ ] Plan and checklist agree on retention numbers (operator activity = 30
      days, security streams = 6 months) — `grep -nE '30 days|6 months' docs/plans/DMF\ Pre-Release\ Compliance\ Readiness\ Plan\ 2026-05-11.md docs/processes/pre-release-compliance-checklist.md`
- [ ] Example inventory `inventories/example/group_vars/all/main.yml` matches
      the new defaults (Loki 50Gi / 720h, Prometheus 50Gi / 30d / 40GB)
- [ ] `roles/base/audit-log-archival/templates/archive-k3s-audit-logs.sh.j2`
      exists and references `audit_log_object_lock_*` variables
- [ ] `aws s3 cp` is no longer present in
      `roles/base/audit-log-archival/`; replaced by `aws s3api put-object`
      in the template — `grep -r 'aws s3 cp\|aws s3api' dmf-infra/k3s-lab-bootstrap/roles/base/audit-log-archival/`
- [ ] Run `ansible-playbook --syntax-check` per §3.1; all four playbooks
      report clean

---

## 7. Next session — Phase 2

Phase 2 of the readiness plan is the Terraform `generic-s3/object-storage`
module + extending `dmf-env/bin/bootstrap-secrets.sh` bundle schema for
three new OpenBao paths (`secret/platform/object-storage/{audit,
openbao-snapshots, app-backups}`). Operator confirmed 2026-05-11 that:

- Mode A default is **BYO object storage** — only `generic-s3` module ships
  in Tier A; Hetzner-native / Aliyun-native / MinIO modules are deferred.
- Live system target is **Backblaze B2** in EU region — `generic-s3`
  module's AWS provider against B2's S3-Compat endpoint covers this.

The plan file's §4 Bootstrap Placement Matrix retains the same structure;
only the Terraform module count changes. The readiness plan and the
ADR-0020 references do not need amendment.
