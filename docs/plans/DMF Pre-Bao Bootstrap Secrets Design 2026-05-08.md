---
status: executed
date: 2026-05-08
---
# DMF Pre-Bao Bootstrap Secrets Design

**Date:** 2026-05-08
**Status:** Design plan (revision 1)
**Scope:** `dmf-env`, `dmf-infra/k3s-lab-bootstrap`, future `dmf-cms` wizard
**Audience:** A freshly cleared implementation agent

**Revision 1 (2026-05-08, later same day):** After compliance review against
`dmf-infra/docs/security-compliance-framework-plan.md`,
`dmf-infra/docs/openbao-bootstrap-security-model.md`, and ADR-0011, the
encrypted bootstrap bundle was relocated **out of the `dmf-env` git tree**
to an operator-local secure path
(`${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml`, defaulting to a sibling
directory of the OpenBao break-glass material under the operator's secure
JuiceFS mount). Rationale: `dmf-env` is a private, no-remote,
operator-local clone treated as temporary (it can be wiped and recreated);
bundle persistence and confidentiality must not depend on it. The
relocation also eliminates the gitleaks / scrub-script interaction risk —
encrypted ciphertext that might coincidentally match secret regexes never
enters a working tree. Open Question 1 re-resolved accordingly. Other
compliance updates: explicit acceptance of the layered laptop-state risk
per ADR-0011, tmpfs/permissions guidance for the export-vars temp file,
and added Required Context pointers to the
security-compliance-framework-plan and openbao-bootstrap-security-model
documents.

## Goal

Create a secure, repeatable way to gather, generate, store, export, and migrate
all secrets needed before OpenBao exists.

The design must support today's CLI bootstrap and the future DMF Console wizard.
The same data model should serve both.

The core chain is:

```text
operator input or generated once
  -> encrypted pre-Bao bundle at ${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml
  -> run-playbook export vars
  -> OpenBao seed after Bao is initialized, unsealed, and policy-ready
  -> OpenBao/ESO as steady-state source of truth
```

OpenBao's own Shamir shares, root token, and break-glass automation material are
explicitly outside this chain. They remain governed by ADR-0009 and the existing
OpenBao disaster-recovery design.

**Execution model clarification (2026-05-08):** this design is aligned with
Revision 4 of `DMF Bootstrap Provision Configure Split Plan 2026-05-07.md`.
Fresh bootstrap is not one uninterrupted Ansible playbook run. It is a
`dmf-env` orchestration sequence: pre-seed provision, `seed-bao`, post-seed
provision, Bootstrap Configure, then Bootstrap Verify.

## Required Context

Read these before implementing:

- `docs/decisions/0002-two-repo-model.md`
- `docs/decisions/0007-secrets-never-in-argv.md`
- `docs/decisions/0008-openbao-secrets-architecture.md`
- `docs/decisions/0009-shamir-dr-model.md`
- `docs/decisions/0010-run-playbook-as-sanctioned-entry.md`
- `docs/decisions/0011-auto-unseal-tradeoff.md`
- `docs/plans/DMF Secret Ownership and OpenBao Migration Plan.md`
- `docs/plans/DMF Bootstrap Provision Configure Split Plan 2026-05-07.md`
- `dmf-infra/docs/security-compliance-framework-plan.md` — control-register
  baseline (CIS, NIST CSF, ISO 27001, GDPR, NIS2, SOC 2)
- `dmf-infra/docs/openbao-bootstrap-security-model.md` — separation of
  duties, root-token disposal, ESO AppRole posture
- `dmf-env/bin/export-openbao-vars.sh`
- `dmf-env/docs/initial-data-gathering.md`
- `dmf-infra/k3s-lab-bootstrap/lifecycle-provision.yml`
- `dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml` — target
  pre-seed wrapper to add.
- `dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml` — target
  post-seed wrapper to add.

Check `git status` in every repo before editing. `dmf-env` is a private,
no-remote, operator-local clone treated as temporary (it can be wiped and
recreated). The encrypted pre-Bao bootstrap bundle therefore lives
**outside the `dmf-env` git tree** at
`${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml` (see Design Decision 1) so
its persistence does not depend on the clone surviving and so encrypted
ciphertext never enters any working tree.

## Current Problem

The current bootstrap has three problems:

1. `dmf-env/bin/export-openbao-vars.sh` reads some provider tokens from local
   operator files and self-generates `vault_k3s_token`,
   `vault_zot_admin_password`, and `vault_awx_admin_password` on every run.
2. Some app roles still carry known fallback credentials such as
   `default('changeme')`, `default('admin')`, or `dev`.
3. There is no durable pre-Bao source of truth. Values exist in laptop-local
   files, generated process state, Kubernetes Secrets, or OpenBao after the
   fact, depending on which stage has run.

That makes fresh bootstrap fragile. It also conflicts with the desired wizard
model, where the operator should collect all required initial information once,
validate it, and then let the system execute predictably.

## Design Decisions

### 1. Use an encrypted pre-Bao bootstrap bundle outside any git tree

The encrypted bundle lives at an operator-local secure path **outside any
git repository**:

```text
${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml
```

`DMF_BOOTSTRAP_BUNDLE_DIR` defaults to a directory adjacent to the
existing OpenBao break-glass material under the operator's secure JuiceFS
mount (per ADR-0009 custody — typically a sibling of the
`openbao-breakglass/` tree). Concrete operator-local paths must not appear
in this design doc.

Recommended encryption: `sops` with `age` recipients. The age public
recipient(s) for each environment are committed in `dmf-env/.sops.yaml`
so tooling can encrypt without holding the private key. The age private
key lives in the operator's macOS Keychain or as a strict-permissioned
file outside any DMF repo.

Rationale for living outside the `dmf-env` git tree:

- `dmf-env` is a private, no-remote, operator-local working clone treated
  as temporary. Bundle persistence and confidentiality must not depend on
  the clone surviving.
- Avoiding any git tree eliminates the gitleaks / scrub-script footgun:
  encrypted ciphertext can coincidentally match secret regexes; if the
  bundle never enters a working tree, the pre-commit hooks cannot fire on
  it.
- Co-location with the existing break-glass material aligns custody with
  ADR-0009 patterns: the operator already protects this directory.
- The future DMF Console wizard targets the same external path; nothing
  in the design depends on `dmf-env` hosting the bundle.

Layered laptop-state risk (per ADR-0011): this design adds an age private
key as a second operator-machine-bound credential alongside the existing
OpenBao auto-unseal automation JSON. ADR-0011 already accepts laptop-state
collapse from 3-of-5 Shamir to effectively 1-of-1 during the experiment
phase (ADR-0004). The age key extends that acceptance — losing the
operator's machine loses both runtime unseal AND day-zero seed material.
Re-evaluate when the same triggers ADR-0011 lists fire (public/OSS,
external collaborators, move-2 hardening).

### 2. Pre-Bao secrets are generated or imported before Ansible changes state

Avoid dynamically creating pre-Bao secrets inside playbooks.

Values needed before OpenBao exists should be either:

- imported from the operator through a hidden prompt or from an existing local
  provider config file, then encrypted into the bundle; or
- generated once by the bootstrap secrets script, then encrypted into the
  bundle.

The k3s token belongs in this bundle. It is a cluster identity and join secret,
it is needed before Bao exists, and it must remain stable across reruns.
Letting k3s generate it dynamically and then trying to rescue it later is
possible but inferior. Define it up front and keep it stable.

### 3. One shared bootstrap admin identity

Every enabled app with a local admin surface should receive identical local
admin credentials at first install:

```text
vault_bootstrap_admin_username
vault_bootstrap_admin_email
vault_bootstrap_admin_password
```

This is an environment-level bootstrap identity, not an app-specific password.

The same human identity must also be seeded in Authentik and mapped to
admin/superadmin groups for all apps that support OIDC:

- Authentik: superuser or equivalent platform-admin group
- Forgejo: site admin
- NetBox: superuser or admin group with required permissions
- Grafana: GrafanaAdmin or equivalent
- AWX: system administrator or organization admin as required
- Zot: registry admin where the app supports admin semantics
- DMF Console: platform admin

If an app cannot technically use the shared local credential, the implementation
must document the exception in the role README and in the bootstrap verify
output.

### 4. OpenBao becomes the steady-state source as soon as it exists

After OpenBao is initialized, unsealed, and policy-ready, the bootstrap bundle
is seeded into OpenBao at canonical paths. Future runs become Bao-first:

1. Try OpenBao.
2. If Bao is unavailable or the key does not exist, use the encrypted pre-Bao
   bundle as day-zero fallback.
3. Never silently generate a new value when a stable value should already
   exist.

The encrypted bundle remains useful for rebuilds and disaster recovery, but the
running cluster treats Bao as the source of truth.

### 5. OpenBao break-glass material is excluded

Do not put these values in the pre-Bao bundle:

- Shamir shares
- OpenBao root token
- root-token recovery material
- OpenBao automation JSON used by the unseal and policy bootstrap design
- long-lived offline escrow data intentionally separated from runtime secrets

Those values are governed by ADR-0009 and remain in the existing JuiceFS,
macOS Keychain, and USB distribution model.

## Secret Classes

### Pre-Bao required secrets

These must exist before or during the first bootstrap pass:

| Secret | Source | Durable pre-Bao store | OpenBao target |
|---|---|---|---|
| Shared bootstrap admin username | operator input or default | encrypted bundle | `secret/platform/bootstrap_admin` |
| Shared bootstrap admin email | operator input | encrypted bundle | `secret/platform/bootstrap_admin` |
| Shared bootstrap admin password | generated once or hidden prompt | encrypted bundle | `secret/platform/bootstrap_admin` |
| k3s token | generated once | encrypted bundle | `secret/platform/k3s/cluster` |
| HCloud token | imported, not generated | encrypted bundle | `secret/platform/hetzner` |
| Cloudflare DNS token | imported, not generated | encrypted bundle | `secret/platform/cloudflare` |
| Tailscale or Headscale auth key | imported or generated through provider command | encrypted bundle | `secret/platform/tailscale` |
| Alertmanager ntfy URL/token | imported or prompt | encrypted bundle | `secret/platform/notifications` |
| Healthchecks URL/token | imported or prompt | encrypted bundle | `secret/platform/notifications` |
| AWX control-node SSH private key | dedicated operator-bootstrap source | not in the generic bundle for the first implementation | `secret/apps/awx/control_node_ssh` |

Provider API tokens should not be generated by the bootstrap script unless the
operator supplies a higher-power token that can create scoped tokens. Usually
the script imports and validates them.

### Post-Bao generated secrets

These should not live in the pre-Bao bundle unless there is a hard bootstrap
dependency:

| Secret | Creator | OpenBao target |
|---|---|---|
| NetBox API/service/AWX tokens | NetBox SoT configure play | `secret/apps/netbox/runtime` |
| Forgejo admin/service tokens | Forgejo bootstrap configure play | `secret/apps/forgejo/runtime` |
| AWX service token | AWX integration configure play | `secret/apps/awx/runtime` |
| Authentik OIDC client secrets | Authentik blueprints/runtime discovery | app-specific runtime paths |
| CMS integration tokens | CMS configure plays | `secret/apps/dmf-cms/runtime` or current runtime Secret path |

These values are created only after the owning app exists. They should be
written directly to Bao and consumed through ESO, app-specific reads, or the
DMF Console API path.

### Unavoidable dynamic secrets

If a chart or app creates a secret dynamically before the implementation can
control it, treat that as an exception:

1. Read it once with `no_log`.
2. Write it to Bao immediately.
3. Switch the role to read from Bao on every later run.
4. Add a follow-up to remove the dynamic path if possible.

Do not normalize dynamic pre-Bao generation as an architecture pattern.

## Bundle Schema

The encrypted file should use a stable schema. Example with placeholder values:

```yaml
apiVersion: dmfdeploy.dev/v1alpha1
kind: BootstrapSecretBundle
metadata:
  environment: hetzner-arm
  created_at: "2026-05-08T00:00:00Z"
  schema_version: 1

bootstrap_admin:
  username: dmfadmin
  email: admin@example.com
  password: <encrypted>

cluster:
  k3s_token: <encrypted>

providers:
  hcloud:
    token: <encrypted>
  cloudflare:
    dns_token: <encrypted>
  tailscale:
    authkey: <encrypted>

notifications:
  ntfy_url: <encrypted-or-empty>
  healthchecks_url: <encrypted-or-empty>

metadata:
  last_validated_at: null
  last_seeded_to_bao_at: null
  external_sources:
    awx_control_node_ssh: dedicated-operator-bootstrap
```

Do not store real values in documentation. The actual file is SOPS-encrypted.

## Canonical OpenBao Paths

Use stable, environment-neutral paths in the generic playbooks:

```text
secret/platform/bootstrap_admin
secret/platform/k3s/cluster
secret/platform/hetzner
secret/platform/cloudflare
secret/platform/tailscale
secret/platform/notifications
secret/apps/<app>/admin
secret/apps/<app>/runtime
secret/apps/awx/control_node_ssh
```

For the shared local admin, prefer one canonical platform path:

```text
secret/platform/bootstrap_admin
```

If existing roles need app-local paths, materialize identical copies to:

```text
secret/apps/forgejo/admin
secret/apps/netbox/admin
secret/apps/grafana/admin
secret/apps/awx/admin
secret/apps/zot/admin
secret/apps/authentik/admin
```

Those app-local documents should contain the same username, email, and password
unless an app-specific exception is documented.

## Script Contract

Add a new script in `dmf-env`:

```text
dmf-env/bin/bootstrap-secrets.sh
```

Required subcommands:

### `init <env>`

Creates or updates `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml`.

Responsibilities:

- check `sops` and `age` availability
- resolve `DMF_BOOTSTRAP_BUNDLE_DIR` and refuse to operate if the
  resolved path is inside any git working tree (use `git rev-parse
  --is-inside-work-tree` from that directory)
- create the directory with `0700` permissions if missing
- load existing encrypted bundle if present
- prompt for missing provider tokens with hidden input
- optionally import provider tokens from existing local files
- generate `bootstrap_admin.password` once if missing
- generate `cluster.k3s_token` once if missing
- never print secret values
- write the encrypted bundle atomically

This command may ask for non-secret display values such as username or email.
It must not accept secret values as command-line arguments.

### `doctor <env>`

Validates the bundle and local prerequisites.

Checks:

- encrypted bundle exists and decrypts
- age recipient/key is available
- required fields are populated
- no plaintext sibling file exists
- file permissions are safe
- provider token scopes can be validated where APIs allow it
- generated values meet length/entropy requirements
- OpenBao break-glass material is not present in the bundle

Output must be pass/fail and field names only. Do not print secret values.

### `export-vars <env> <output-json>`

Decrypts the bundle and writes a `0600` Ansible vars JSON file for
`run-playbook.sh`.

Expected variable mapping:

```text
vault_bootstrap_admin_username
vault_bootstrap_admin_email
vault_bootstrap_admin_password
vault_k3s_token
vault_hcloud_token
vault_cloudflare_dns_token
vault_tailscale_authkey
vault_alertmanager_ntfy_url
vault_alertmanager_watchdog_url
```

`vault_awx_control_node_ssh_private_key` is not emitted by the generic bundle
export in the first implementation. If a dedicated operator-bootstrap step
needs to pass it to a seeding play, that flow must be separate, no-log, and
documented in `dmf-env`.

Legacy variables such as `vault_awx_admin_password`,
`vault_zot_admin_password`, `vault_forgejo_admin_password`,
`vault_netbox_superuser_password`, and `vault_grafana_admin_password` may be
emitted during transition, but they must all map to the shared bootstrap admin
password.

### `seed-bao <env>`

Runs after OpenBao is initialized, unsealed, and policy-ready.

Responsibilities:

- decrypt the bootstrap bundle locally
- write platform paths to Bao
- write app-local admin copies when required by current roles
- verify or seed the AWX control-node SSH key from the dedicated
  operator-bootstrap source, not from the generic bootstrap bundle
- update bundle metadata `last_seeded_to_bao_at`
- be idempotent: do not rotate values unless an explicit rotate command is used

This command must use stdin transport into Bao operations. No secrets in argv,
stdout, logs, or long-lived temp files.

Collision behavior:

- missing target paths are written from the encrypted bundle
- existing target paths with the same value are left unchanged
- existing platform paths with different values fail and require explicit
  `rotate`
- existing app-local admin paths with different values fail and require a
  deliberate app-account migration play that changes the application account
  and Bao value together

`seed-bao` must not silently overwrite app-local admin paths. Bao-only changes
can desynchronize the recorded credential from the app's internal user database.

### `status <env>`

Reports only metadata:

- bundle exists
- decryptable yes/no
- required fields present yes/no
- last validation timestamp
- last Bao seed timestamp

It must not print secret values.

### `rotate <env> <field>`

Optional later subcommand. Do not implement broad rotation in the first pass
unless required. Rotation has app-specific consequences and must be deliberate.

## Integration With `run-playbook.sh`

`dmf-env/bin/run-playbook.sh` should stop calling
`export-openbao-vars.sh` directly for self-seeded values. Target flow:

1. `run-playbook.sh <env> <playbook>` creates a secure temp JSON path.
2. It calls `bin/bootstrap-secrets.sh export-vars <env> <temp-json>`.
3. It injects `-e @<temp-json>`.
4. It cleans the temp file with a trap.
5. For post-Bao runs, it may merge Bao-fetched runtime values with the
   bootstrap bundle exports, but stable bootstrap values must not rotate.

The existing `export-openbao-vars.sh` can either:

- become a thin compatibility wrapper around `bootstrap-secrets.sh export-vars`;
  or
- be retired after all callers are moved.

Do not create a second secret-resolution path.

## Bootstrap Sequence

The canonical fresh bootstrap sequence is orchestrated from `dmf-env`. The
future implementation may wrap these commands in `bin/bootstrap-platform.sh`,
but the seed boundary remains explicit.

### Phase A: Preflight and bundle initialization

Operator-run commands:

```bash
cd dmf-env
bin/bootstrap-secrets.sh init hetzner-arm
bin/bootstrap-secrets.sh doctor hetzner-arm
```

Agents may implement and review this code, but should not run secret-collecting
commands that would expose values to transcripts.

### Phase B: Pre-seed provision through OpenBao and ESO

Use existing sanctioned wrappers:

```bash
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml
```

During this stage, k3s and provider-facing components consume values exported
from the encrypted bundle. This stage stops after OpenBao and ESO are
initialized, unsealed, policy-ready, and able to receive the bundle seed. It
does not install Layer 6 apps that need shared local admin credentials.

### Phase C: Seed OpenBao

Once OpenBao is initialized, unsealed, and policy-ready:

```bash
bin/bootstrap-secrets.sh seed-bao hetzner-arm
```

The implementation may call a generic dmf-infra seeding play through
`bin/run-playbook.sh`, but `dmf-env` owns decryption and bundle handling.

### Phase D: Post-seed app install

```bash
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml
```

Layer 6 app roles must consume the shared bootstrap admin identity rather than
app-specific known defaults.

Required role changes:

- Forgejo local admin uses `vault_bootstrap_admin_*`
- NetBox local superuser uses `vault_bootstrap_admin_*`
- Grafana local admin uses `vault_bootstrap_admin_*`
- AWX local admin uses `vault_bootstrap_admin_*`
- Zot local htpasswd admin uses `vault_bootstrap_admin_*`
- Authentik bootstrap admin uses `vault_bootstrap_admin_*`

During transition, app-local Bao paths may be materialized with identical
values for compatibility.

For existing clusters, the Authentik role must not silently rename or delete the
legacy `akadmin` user. It should create or verify the shared bootstrap user as
an admin first; disabling or deleting `akadmin` is a separate explicit
hardening/migration step.

### Phase E: Bootstrap Configure and OIDC admin seeding

```bash
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml
```

Bootstrap Configure must create or verify the same operator identity in
Authentik and grant admin/superadmin rights in every app.

The verify stage must confirm both:

- local admin login path works where local admin is supported
- OIDC login for the seeded operator identity has admin/superadmin access

### Phase F: Bootstrap Verify

```bash
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/bootstrap-verify.yml
```

`lifecycle-provision.yml` remains an Ansible compatibility wrapper for
already-seeded clusters and re-runs. It is not the canonical first-run path
unless an outer `dmf-env` orchestrator handles the seed boundary before
post-seed app install.

## Future Wizard Contract

The future wizard should be a UI over the same contract, not a new secret
model.

Wizard responsibilities:

- collect environment name, domain, ingress mode, provider choices, and
  non-secret inventory inputs
- collect provider tokens through browser controls that never log values
- validate token scopes
- choose or generate the shared bootstrap admin identity
- generate the k3s token
- write `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml`
- run the equivalent of `doctor`
- start or hand off to the bootstrap workflow
- seed Bao when the OpenBao readiness gate passes
- show only status and retrieval instructions, never raw secrets unless the
  operator explicitly requests a reveal outside AI transcript context

The wizard output should match the CLI artifacts:

- `manifests/<env>.yaml` for non-secret design inputs
- `inventories/<env>/...` for rendered inventory/config
- `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml` for pre-Bao secrets
  (operator-local, outside any git tree)
- OpenBao KV paths after seeding

## Security Rules

These rules are mandatory:

- No secret values in command-line arguments.
- No secret values printed to stdout/stderr.
- No secret values in AI transcripts.
- No plaintext committed to `dmf-env`, even though `dmf-env` is private.
  The encrypted bootstrap bundle is not committed either — it lives
  outside any git tree at `${DMF_BOOTSTRAP_BUNDLE_DIR}`.
- No known fallback passwords in public `dmf-infra`.
- No generated stable secret may rotate silently on rerun.
- Any temp vars file must be `0600`, short-lived, and removed by trap.
- Scripts must fail closed if the encrypted bundle is missing required values.
- Provider token validation must report scope status without echoing the token.
- OpenBao Shamir/root/break-glass material must remain outside the bundle.

## Implementation Plan

### Step 1: Add encrypted-bundle scaffolding

Files (and locations):

```text
dmf-env/.sops.yaml                   # age public recipients per env
dmf-env/bin/bootstrap-secrets.sh     # the script
${DMF_BOOTSTRAP_BUNDLE_DIR}/         # operator-local secure dir, outside git
${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml   # encrypted bundle per env
```

The script must `mkdir -p ${DMF_BOOTSTRAP_BUNDLE_DIR}` with `0700`
permissions if missing, and refuse to operate if the resolved bundle
directory is inside any git working tree.

Decisions to make before coding:

- age recipient source for the first operator (and how additional
  recipients are added later)
- whether AWX control-node SSH private key belongs in the bundle or
  remains in a separate operator-bootstrap source until Bao migration
  (see Open Question 2 — currently resolved to "keep separate")

Resolved defaults:

- bundle path: `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml`, default
  sibling of OpenBao break-glass material under the operator's secure
  JuiceFS mount, never inside a git tree
- age private key: operator's macOS Keychain or strict-permissioned file
  outside any DMF repo
- AWX control-node SSH private key: not in the generic bundle for the
  first implementation

### Step 2: Implement `init`, `doctor`, and `export-vars`

This closes the current self-generation footgun without requiring Bao changes.

Acceptance:

- repeated `export-vars` calls return the same k3s token and admin password
- missing required values fail with clear field names
- no secret appears in stdout, logs, shell history, or git diff

### Step 3: Wire `run-playbook.sh`

Replace or wrap the current `export-openbao-vars.sh` behavior so playbook runs
source stable values from the encrypted bundle.

Acceptance:

- `run-playbook.sh` still injects Ansible vars through a temp JSON file
- temp file is created with `umask 077` (mode `0600`) and removed by a
  `trap` on `EXIT ERR INT TERM`; on Linux prefer tmpfs (`/dev/shm`) so a
  `kill -9` of the wrapper does not leave plaintext on persistent disk;
  on macOS rely on FileVault-encrypted volume + trap (no convenient
  default tmpfs)
- current playbooks receive all existing `vault_*` names during transition
- no direct `ansible-playbook` entry point is introduced

### Step 4: Add OpenBao seeding

Implement `bootstrap-secrets.sh seed-bao <env>` and, if useful, a generic
dmf-infra playbook that writes the received vars to Bao.

Acceptance:

- platform paths exist in Bao after OpenBao readiness
- app-local admin paths exist and all contain the shared bootstrap admin
  credential
- rerunning seed is idempotent for missing or matching values
- seed fails on differing platform values unless an explicit rotate operation
  is requested
- seed fails on differing app-local admin values unless an explicit
  app-account migration play updates both the app account and Bao
- seed does not reveal values in logs

### Step 5: Refactor app roles away from known defaults

Update `dmf-infra` roles so Layer 6 apps use the shared bootstrap admin
identity and fail if it is absent.

Initial targets:

- `roles/stack/operator/forgejo`
- `roles/stack/operator/forgejo-bootstrap`
- `roles/stack/operator/netbox`
- `roles/stack/operator/netbox-sot`
- `roles/base/grafana`
- `roles/stack/operator/awx`
- `roles/stack/operator/awx-integration`
- `roles/stack/operator/zot`
- CMS token paths that fall back to known admin defaults

Acceptance:

```bash
grep -rnE "default\(\s*['\"](changeme|admin|password|dev)['\"]" \
  dmf-infra/k3s-lab-bootstrap/roles/ \
  | grep -vE 'acme_email|@example\.com'
```

returns zero credential-context hits, or every remaining hit is explicitly
documented as non-secret.

### Step 6: Seed OIDC admin rights

Bootstrap Configure must ensure the same bootstrap operator has admin rights in
every app through OIDC.

Acceptance examples:

- Authentik user exists and belongs to platform admin groups.
- Forgejo OIDC login maps to site admin.
- NetBox OIDC login maps to superuser/admin-equivalent group.
- Grafana OIDC login maps to GrafanaAdmin.
- AWX OIDC/SAML login maps to system admin or required organization admin.
- DMF Console login maps to platform admin.
- Verify playbook checks these mappings or exposes a clear manual gate.

### Step 7: Update docs

Update:

- `docs/plans/DMF Bootstrap Provision Configure Split Plan 2026-05-07.md`
- `docs/plans/DMF Secret Ownership and OpenBao Migration Plan.md`
- `dmf-env/docs/initial-data-gathering.md`
- repo-local `CLAUDE.md` / `AGENTS.md` if operator workflow changes

The old statement that the k3s token is dynamically generated by the bootstrap
playbook should be replaced. The k3s token is generated once by the pre-Bao
bundle flow.

Implementation phase mapping against
`DMF Bootstrap Provision Configure Split Plan 2026-05-07.md`:

| This design | Split-plan phase | Notes |
|---|---|---|
| Steps 1-4 | Phase 4 | bundle, export-vars, run-playbook, seed-bao |
| Step 3 + Bootstrap Sequence | Phase 1 | add pre-seed/post-seed wrappers and dmf-env orchestrator |
| Step 5 | Phase 3 | refactor app roles and remove credential fallbacks |
| Step 6 | Phase 2 | Bootstrap Configure owns OIDC/admin mappings |
| Step 7 | Phase 5 | update docs and cleanup stale secret boundaries |

## Verification Checklist

Static checks:

- encrypted bundle decrypts only with authorized age key
- `bootstrap-secrets.sh doctor <env>` passes
- `bootstrap-secrets.sh export-vars <env> <tmp>` produces required variable
  names without printing values
- no plaintext secret files under `${DMF_BOOTSTRAP_BUNDLE_DIR}` or
  anywhere on disk; encrypted `.sops.yaml` is the only on-disk pre-Bao
  artifact
- `git ls-files` in `dmf-env` returns no matches for `*.sops.yaml` or
  any path under `secrets/`; the bundle is not in any git tree
- no known default credentials in `dmf-infra`

Bootstrap checks:

- k3s token remains stable across reruns
- shared local admin credential is identical across enabled apps
- `seed-bao` fails rather than overwriting differing existing app-local admin
  paths
- local admin login works where supported
- OIDC admin login works for the seeded operator identity across all apps
- Bao paths contain expected keys after seed
- rerunning seed does not rotate values
- rerunning full bootstrap does not rotate stable values

Public-push checks:

- no plaintext secrets in public repos
- no fallback credentials in public role defaults
- no transcript or command output contains collected secrets
- gitleaks and scrub scripts remain clean

## Open Questions

1. ~~Should encrypted `secrets/bootstrap/<env>.sops.yaml` be committed to
   private `dmf-env`, or should it be gitignored but stored inside the repo
   directory?~~ **RE-RESOLVED 2026-05-08 (later same day)**: neither.
   `dmf-env` is a temporary, no-remote, operator-local clone; bundle
   persistence cannot depend on it. The bundle lives at
   `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml` outside any git tree
   (see Design Decision 1), with age public recipients in
   `dmf-env/.sops.yaml` and age private key in operator Keychain. This
   relocation also resolves the gitleaks/scrub-script interaction risk
   (encrypted ciphertext that may match secret regexes never enters a
   working tree).
2. ~~Should AWX control-node SSH private key be included in the encrypted
   bundle, or remain in a separate operator-bootstrap source until it is seeded
   to Bao?~~ **RESOLVED 2026-05-08**: keep it separate for the first
   implementation. Seed `secret/apps/awx/control_node_ssh` from a dedicated
   `dmf-env` operator-bootstrap step; `dmf-infra` consumes only Bao.
3. ~~Should provider tokens be copied into Bao forever, or only used from the
   encrypted bundle for future rebuilds?~~ **RESOLVED 2026-05-08**: seed
   provider tokens to Bao when the running cluster needs them, and keep the
   encrypted bundle as the day-zero authority for rebuilds.
4. ~~Which apps technically support identical local admin usernames?~~
   **RESOLVED 2026-05-08**: the target is identical username, email, and
   password for every app with a local admin surface. Any technical exception
   must be documented in the role README and surfaced by bootstrap verify.
5. How should the wizard reveal credentials to the operator when needed without
   creating transcript or browser-history leaks? This needs UI-specific design.

6. **Per-secret data classification.** The
   `dmf-infra/docs/security-compliance-framework-plan.md` Phase 1
   deliverables call for classifying each secret (Public / Internal /
   Confidential / Secret) so retention, rotation cadence, and
   breach-notification scope can be set per class. Today this design
   handles every bundle field uniformly. Open: do we add a
   `classification:` field to the Bundle Schema and a column to
   "Canonical OpenBao Paths" now, or defer to a follow-up classification
   doc owned by the framework-plan? Default if classified inline:
   provider tokens = Confidential, `k3s_token` = Confidential, shared
   bootstrap admin password = Confidential, `bootstrap_admin.email` =
   Internal. Recommend: defer; the bootstrap design should not absorb
   the classification framework. The follow-up doc should land before
   any rotation/retention SLA discussion.

7. **Bootstrap Verify ownership of the audit-policy gate.** Per the
   adjacent split plan's Specific Fix #19, the Kubernetes audit policy
   must filter the new `secret/platform/*` and `secret/apps/*/admin`
   paths at Metadata level (per
   `dmf-infra/docs/archive/SECURITY-REMEDIATION-N1-AUDIT-LEAK.md`).
   Open: should `bootstrap-verify.yml` assert the running policy
   contains the expected rule, or is this an operator-facing manual
   check at day zero? Recommend: both — verify-stage assertion plus a
   day-zero documentation check.

## Non-Goals

- Do not redesign OpenBao Shamir custody.
- Do not make `dmf-env` public.
- Do not put plaintext secrets in any repo.
- Do not introduce direct `ansible-playbook` live-run paths.
- Do not solve general secret rotation in the first implementation.
- Do not require the future wizard before the CLI flow works.
