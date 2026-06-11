# DMF Session Handoff — Tier A Phase 3 wrap + `init-wizard.sh` + aliyun-123 in flight (2026-05-12)

**Status:** Phase 3 of 6 of the [Tier A execution plan](../plans/DMF%20Tier%20A%20Phase%20Execution%20Plan%202026-05-11.md)
has landed (code + handoff doc). New `init-wizard.sh` greenfield tool
shipped in `dmf-env/bin/`. Operator mid-deploy on a fresh `aliyun-123`
environment, currently between Terraform apply and pre-seed playbook.

This handoff records the cross-repo work since the
[Phase 2 sync handoff](DMF%20Tier%20A%20Phase%202%20Implementation%20Handoff%202026-05-11.md)
so a returning operator (or future agent) can pick up cleanly.

---

## 1. Commit chain across repos

### `dmfdeploy` (umbrella)

```
07cb2be  docs(todos): init-wizard.sh follow-ups + close Longhorn BackupTarget
52411ed  docs(runbook): wire init-wizard.sh into TL;DR + §0.1 of deploy quickstart
f11269a  docs(handoff): Tier A Phase 3 implementation record + plan-doc updates
a23ef7b  docs(plan): Phase 3 per-actor briefs + Frozen Secret Contract
<this commit>  docs(handoff): session wrap — Phase 3 + wizard + aliyun-123
```

### `dmf-env`

```
ddbd0d6  feat(aliyun-123): greenfield env scaffold + agentic forgejo config
6c5bb19  fix(init-wizard): zombie-proof bundle write (atomic mv + -s exists check)
039454d  fix(init-wizard): plain alphanumeric password charset + clearer breakglass prompt
7a3aa41  fix(init-wizard): quote all interpolated values in bundle YAML
5aec1f0  fix(init-wizard): name SOPS input file <env>.sops.yaml in tmp dir
d148959  fix(init-wizard): isolate gen_password/gen_token from set -o pipefail
2ec5423  feat(init-wizard): interactive greenfield env bootstrap
7e93d28  docs(readme): add TL;DR quickstart with init-wizard.sh as entry point
f907a80  feat(b2-buckets): per-bucket lifecycle rules (90d snapshots, 365d app-backups)
```

### `dmf-infra`

```
03c1e17  fix(playbooks): move vertical-resilience after layer 6 apps
e83b135  feat(bootstrap-verify): import resilience-verify
9187aeb  feat(playbooks): wire vertical-resilience track into post-seed
b9afb1a  feat(resilience-verify): two-track synthetic round-trip + Object Lock test
8641b4c  feat(zot): OCI-format registry mirror to B2
f732870  feat(postgres): per-app pg_dump CronJob template
0c2109a  feat(openbao): raft-snapshot CronJob role + scoped k8s-auth
61c9895  feat(longhorn): daily RecurringJob (group=default, retain=7)
c62b923  feat(longhorn): backup-target role with UPPERCASE Secret template
438af59  feat(eso): object-storage-credentials role + 2 ClusterSecretStores
```

---

## 2. Phase 3 (vertical-resilience playbooks) — done in code

See the
[Phase 3 implementation handoff](DMF%20Tier%20A%20Phase%203%20Implementation%20Handoff%202026-05-12.md)
for the canonical record. Headlines:

- ESO `object-storage-credentials` role + 2 per-bucket ClusterSecretStores
  + ExternalSecrets in 5 consumer namespaces (Frozen Secret Contract).
- Longhorn `BackupTarget` + UPPERCASE-key ExternalSecret template +
  daily `RecurringJob` (default group, retain=7).
- OpenBao Raft snapshot CronJob via k8s-auth (NOT AppRole; deliberate
  divergence documented in the role README).
- Per-app `pg_dump` CronJob template (netbox/awx/authentik/forgejo).
- Zot OCI-format mirror to B2 via skopeo + aws CLI (NOT PVC mount —
  Longhorn RWO blocks concurrent attach).
- Two-track `resilience-verify` (in-cluster Jobs for ESO buckets;
  host-side `delegate_to: localhost` for audit-bucket Object Lock test).
- `bootstrap-provision-post-seed.yml` ordering fix (commit `03c1e17`):
  vertical-resilience now lands AFTER layer 6 apps so consumer
  namespaces + Secrets exist when CronJobs deploy.

Pre-flight that was deferred: `b2-buckets.sh ensure` for both envs to
apply the new lifecycle rules. Operator confirmed this ran cleanly for
the env currently being deployed.

---

## 3. `dmf-env/bin/init-wizard.sh` — new tool

Interactive greenfield env wizard. Collects every unique-non-generable
input in one pass, auto-generates passwords/tokens, writes the
encrypted bundle + per-env tfvars + manifest stub + inventory main.yml
+ openbao_secrets.yml + appends recipient rule to `.sops.yaml`.

Refuses to run if the bundle for the named env already exists —
protects against accidentally rotating passwords ESO is already wired
against.

### 3.1 In-flight fix log

Five bugs surfaced during the wizard's acceptance run against
`aliyun-123` and were fixed in sequence:

| Commit | Bug | Root cause |
|---|---|---|
| `d148959` | SIGPIPE → exit 141 | `tr ... \| head -c N` trips `set -o pipefail`; head closes the pipe before tr finishes |
| `5aec1f0` | sops "no matching creation rules" | sops matches `.sops.yaml` against the INPUT file path; generic `mktemp` path didn't match `*/<env>.sops.yaml$` |
| `7a3aa41` | yaml "did not find expected node content" | unquoted `*foo` password = invalid YAML alias |
| `039454d` | yaml "unknown escape character" | `tr -dc 'A-Za-z0-9!@#%^*-_=+'` has a hidden range `*-_` (0x2A..0x5F) that pulled in `\`, `[`, `]`, etc. |
| `6c5bb19` | manual rm dance after each failure | shell redirect created zero-byte file before sops ran; atomic mv-on-success now |

The current wizard is shippable end-to-end for the bundle + tfvars
path. The five fixes above are baked in.

### 3.2 Known v2 work (captured in [TODOS](../../TODOS.md) §init-wizard.sh follow-ups)

- **Manifest stub** — only 3 of 12 `spec.*` keys are rendered;
  per-provider Terraform modules need the full schema (`topology`,
  `provider`, `network`, `domain`, etc.). Operator workaround for the
  aliyun-123 deploy: surgical `sed` over the existing
  `manifests/aliyun.yaml` (see §4.3 below).
- **Terraform per-env scaffold not created** — operator copies
  `terraform/<existing-env>/` to `terraform/<new-env>/` by hand and
  edits the manifest path + backend state path + runs `tofu init
  -reconfigure`.
- **Inventory `group_vars/all/` only renders 2 of 6 files** — operator
  copies `eso.yml` / `openbao.yml` / `tailscale.yml` / `bootstrap.yml`
  from an existing env.
- **`tf-apply.sh` doesn't read the wizard's per-env tfvars** —
  sources from `~/.secure/<provider>/.ay-dmfdeploy` legacy paths.
- **`.sops.yaml` accumulates stale rules** from failed env-name
  attempts. The wizard's idempotency guard worked for repeat attempts
  with the same env name but not across env-name variants.

---

## 4. `aliyun-123` deploy — current state

### 4.1 What's committed in dmf-env

`dmf-env@ddbd0d6` (`feat(aliyun-123): greenfield env scaffold + agentic
forgejo config`) lands:

- `manifests/aliyun-123.yaml` — full 233-line manifest, sed-derived
  from `manifests/aliyun.yaml` (the Phase 2 baseline). Both manifests
  now coexist in the repo.
- `inventories/aliyun-123/group_vars/all/{main,openbao_secrets}.yml`
  — wizard-rendered.
- `terraform/aliyun-123/{main,outputs,versions}.tf` + `.terraform.lock.hcl`
  — operator-copied from `terraform/aliyun/` with the manifest-path
  and backend-state-path updated.
- `.sops.yaml` cleaned: hetzner-arm + aliyun + aliyun-123 only
  (dropped duplicates and dead env-name rules from failed wizard
  attempts).
- `agentic/forgejo.env` — agentic-harness coordinates that umbrella
  commit `784e69c` (`fix(agentic): source forgejo config from dmf-env,
  not local sibling`) expects to find here.

### 4.2 What's NOT committed

- Encrypted bundle at `${DMF_BOOTSTRAP_BUNDLE_DIR}/aliyun-123.sops.yaml`
  (operator-side SOPS store; never in git).
- `${DMF_BOOTSTRAP_BUNDLE_DIR}/aliyun-123/object-storage.tfvars` and
  `aliyun.tfvars` (provider creds; operator-side).
- The original `~/.secure/aliyun/.ay-dmfdeploy` legacy Alicloud creds
  file (operator-side; `tf-apply.sh` reads it directly).

### 4.3 Step-by-step state (against
[the deploy quickstart TL;DR](../runbooks/dmf-deploy-quickstart.md))

| TL;DR step | State |
|---|---|
| 1. `init-wizard.sh` | ✅ done (env `aliyun-123` bundle + tfvars + stub manifest + inventory + terraform scaffold) |
| 1a. Operator-side manifest fix | ✅ done (sed-derived `aliyun-123.yaml` from the Phase 2 `aliyun.yaml` template) |
| 1b. Operator-side terraform/<env>/ scaffold | ✅ done (copied + path-edited + `tofu init -reconfigure`) |
| 2. `bin/bootstrap-secrets.sh doctor aliyun-123` | ✅ all passed |
| 3. `bin/b2-buckets.sh ensure aliyun-123` | ✅ three buckets live (audit + openbao_snapshots + app_backups) with lifecycle rules |
| 4. `bin/tf-apply.sh aliyun-123 apply -auto-approve -lock=false` | 🔄 IN FLIGHT (retry pending after manifest fix landed) |
| 5+. pre-seed → seed-bao → export-vars → post-seed → bootstrap-verify | ⏳ ahead |

---

## 5. Where to pick up

1. **Operator runs the retry** at step 4 above:
   ```bash
   cd $DMFDEPLOY_UMBRELLA/dmf-env
   bin/tf-apply.sh aliyun-123 apply -auto-approve -lock=false
   ```
   Expected: ~1 minute, creates VPC + vSwitch + Security Group + key
   pair + 3× ECS instances + RAM role.

2. **Then step 4 of the TL;DR** (pre-seed playbook). The runbook §2
   describes the expected 5400-second timeout for the cert-manager
   DNS-01 + Longhorn pull + OpenBao init+unseal serialised path.

3. **At step 5** (Shamir share capture) — operator-only manual step.
   `pre-seed` produces 5 new shares for the fresh `aliyun-123` OpenBao
   instance. Distribute per
   `dmf-env/inventories/aliyun-123/group_vars/all/openbao_secrets.yml`
   (3 to macOS Keychain `openbao-breakglass-share-3-aliyun-123`, 2 to
   USB `/Volumes/OPENBAO/aliyun-123/`, 1+2 to the JuiceFS path).

---

## 6. Files that may still need attention

- **`dmf-env/manifests/aliyun-123.yaml.wizard-stub`** — deleted by this
  session's cleanup. If you want to recover the wizard's literal stub
  output for v2 reference, it's reproducible from `init-wizard.sh`'s
  `render_manifest` function.
- **`${DMF_BOOTSTRAP_BUNDLE_DIR}/{aliyun,new-aliyun,newest-aliyun}.sops.yaml`**
  — bundles from earlier wizard attempts. Operator can `rm` once the
  aliyun-123 deploy is fully verified. The `aliyun.sops.yaml` may have
  legitimate content from the Phase 2 work; check with `sops --decrypt`
  before removing.
- **dmf-env/.sops.yaml** — kept the `aliyun` recipient rule so the
  Phase 2 baseline bundle remains decryptable; remove the rule if you
  decide to abandon the `aliyun` env permanently.
- **B2 side: `dmf-{audit,openbao-snapshots,app-backups}-aliyun`
  buckets** — created Phase 2, still live, currently empty. Lifecycle
  rules also apply. Can leave indefinitely (B2 cost on empty buckets
  is ~0) or `b2 delete-bucket` once you're sure the aliyun env is
  truly dead.

---

## 7. References

- [Tier A Phase 3 Implementation Handoff 2026-05-12](DMF%20Tier%20A%20Phase%203%20Implementation%20Handoff%202026-05-12.md) — Phase 3 canonical record
- [Tier A Phase Execution Plan 2026-05-11](../plans/DMF%20Tier%20A%20Phase%20Execution%20Plan%202026-05-11.md) — phase sequence + per-actor briefs
- [DMF Platform Deploy Quickstart](../runbooks/dmf-deploy-quickstart.md) — 9-step TL;DR (updated this session)
- [TODOS](../../TODOS.md) §`init-wizard.sh` follow-ups — v2 work captured
- `dmf-env/bin/init-wizard.sh` — the wizard itself
- `dmf-env/bin/b2-buckets.sh` — B2 native-API bucket configure + lifecycle
- `dmf-env/bin/bootstrap-secrets.sh` — bundle init/doctor/seed-bao/export-vars
