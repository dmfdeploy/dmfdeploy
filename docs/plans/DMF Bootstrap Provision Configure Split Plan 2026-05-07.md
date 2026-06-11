---
status: executed
date: 2026-05-07
---
# DMF Bootstrap Provision / Configure Split Plan

**Date:** 2026-05-07
**Status:** Draft implementation plan (revision 5)
**Scope:** `dmf-infra/k3s-lab-bootstrap`, with references to `dmf-env` and
`dmf-runbooks`
**Audience:** A freshly cleared implementation agent

**Revision 5 (2026-05-08, later same day):** Compliance review against
`dmf-infra/docs/security-compliance-framework-plan.md`,
`dmf-infra/docs/openbao-bootstrap-security-model.md`, and ADR-0011
relocated the encrypted bootstrap bundle **out of the `dmf-env` git tree**
to `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml` (operator-local secure
path, default sibling of OpenBao break-glass material). Rationale:
`dmf-env` is a temporary, no-remote, private operator-local clone;
bundle persistence must not depend on it, and encrypted ciphertext must
not enter any working tree where gitleaks/scrub-script regexes could
fire. Also added pointers in Required Context for the
security-compliance-framework-plan, the openbao-bootstrap-security-model,
and ADR-0011 (layered laptop-state risk acceptance).

**Revision 4 (2026-05-08):** Resolved the execution-model ambiguity with the
adjacent pre-Bao secrets design. A fresh bootstrap is now explicitly a
`dmf-env` orchestration sequence: run pre-seed provision through OpenBao/ESO,
run `bootstrap-secrets.sh seed-bao`, then run post-seed app install, configure,
and verify. `lifecycle-provision.yml` remains an Ansible compatibility wrapper,
not the canonical first-run secret-boundary crossing. Also clarified seed
collision behavior, Authentik `akadmin` migration posture, AWX SSH-key
ownership, Shamir threshold wording, and script subcommand inventory.

**Revision 3 (2026-05-08):** Aligned this plan with
`docs/plans/DMF Pre-Bao Bootstrap Secrets Design 2026-05-08.md`. The encrypted
pre-Bao bootstrap bundle is now the canonical day-zero source for provider
tokens, the k3s token, and the shared bootstrap admin identity. OpenBao seeding
from that bundle happens immediately after OpenBao is ready and before Layer 6
app install; it is not a Bootstrap Configure phase. App-local admin credentials
must all derive from the same `vault_bootstrap_admin_*` identity, with the same
OIDC identity mapped to admin/superadmin rights during Bootstrap Configure.
Grafana local-admin posture and the SOPS/age bundle question are resolved by
that design.

**Revision 2 (2026-05-07):** Corrected the pre-Bao secret-source description
after auditing the actual workflow. Added a "Pre-Bao vs Post-Bao Secret
Sources" section that replaces the prior "Secrets And Credential Ownership."
Added an "Initial App Credentials Audit" section documenting that **Forgejo,
NetBox, and Grafana currently boot with known default local credentials** if
`vault_*` env is unset — all three must be
fixed before public push. It also proposed putting pre-Bao secret seeding at
the start of Bootstrap Configure and resolved Open Question 5 (DMF Console is
OIDC-only — no local admin credential). **Revision 3 supersedes that placement:**
seeding now belongs immediately after OpenBao readiness and before Layer 6 app
install, not inside Bootstrap Configure.

## Goal

Refactor the platform bootstrap so it follows a clear two-pass model:

1. **Bootstrap Provision** installs platform capabilities in minimally viable,
   app-local form.
2. **Bootstrap Configure** wires those capabilities together into the DMF
   facility graph.

This bootstrap split must stay separate from the `dmf-runbooks` workload
lifecycle. Bootstrap Configure may publish AWX projects, credentials, and job
templates for media workloads, but it must not launch or finalise those
workloads. Runtime media-function actions remain operator-driven through
`dmf-runbooks` launch/finalise playbooks and AWX.

## Required Context

Before implementation, read these files from the umbrella workspace:

- `STATUS.md`
- `CLAUDE.md`
- `AGENTS.md`
- `docs/decisions/INDEX.md`
- `docs/decisions/0003-ebu-v2-taxonomy.md`
- `docs/decisions/0007-secrets-never-in-argv.md`
- `docs/decisions/0008-openbao-secrets-architecture.md`
- `docs/decisions/0009-shamir-dr-model.md`
- `docs/decisions/0010-run-playbook-as-sanctioned-entry.md`
- `docs/decisions/0011-auto-unseal-tradeoff.md` — laptop-state collapse
  acceptance during experiment phase; bootstrap bundle's age key extends
  this acceptance
- `docs/decisions/0012-configure-stage-distinct-from-provision.md`
- `docs/decisions/0013-media-function-catalog-model.md`
- `docs/decisions/0014-awx-project-layout.md`
- `docs/decisions/0016-awx-control-node-ssh-via-cloud-init-and-openbao.md`
- `docs/plans/DMF Secret Ownership and OpenBao Migration Plan.md`
- `docs/plans/DMF Pre-Bao Bootstrap Secrets Design 2026-05-08.md`
- `dmf-infra/docs/security-compliance-framework-plan.md` — control-register
  baseline (CIS, NIST CSF, ISO 27001, GDPR, NIS2, SOC 2)
- `dmf-infra/docs/openbao-bootstrap-security-model.md` — separation of
  duties (root-token disposal, ops-admin, ESO AppRole), break-glass
  posture
- the most recent handoff under `docs/handoffs/`

Before touching `dmf-infra`, also read:

- `dmf-infra/CLAUDE.md`
- `dmf-infra/AGENTS.md`
- `dmf-infra/k3s-lab-bootstrap/lifecycle-provision.yml`
- `dmf-infra/k3s-lab-bootstrap/lifecycle-configure.yml`
- `dmf-infra/k3s-lab-bootstrap/site.yml`
- `dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml` — target
  pre-seed provision wrapper to add.
- `dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml` — target
  post-seed app install wrapper to add.
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml`
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/tasks/main.yml`
- `dmf-infra/k3s-lab-bootstrap/roles/common/app-admin-facts/` — current helper
  pattern for app-local admin facts. In the target model it may materialize
  app-local paths, but it must not generate independent per-app passwords.

Before touching `dmf-env`, also read:

- `dmf-env/bin/bootstrap-secrets.sh` — target script from the pre-Bao secrets
  design. It owns `init`, `doctor`, `export-vars`, `seed-bao`, `status`, and
  optional `rotate`.
- `dmf-env/bin/export-openbao-vars.sh` — legacy wrapper that exports `vault_*`
  from operator-local files and self-seeds the rest. It should become a
  compatibility wrapper around `bootstrap-secrets.sh export-vars` or be retired.
- `dmf-env/.sops.yaml` — age public recipients for each environment; age
  private keys live in operator Keychain, never in any DMF repo.
- `dmf-env/inventories/hetzner-arm/group_vars/all/openbao.yml`
- `dmf-env/inventories/hetzner-arm/group_vars/all/openbao_secrets.yml`
- `dmf-env/inventories/hetzner-arm/group_vars/all/eso.yml`

**Note on `dmf-env` posture:** `dmf-env` is a private, no-remote,
operator-local working clone treated as temporary — it can be wiped and
recreated. The encrypted bootstrap bundle therefore lives **outside the
`dmf-env` git tree** at `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml`
(default: a directory adjacent to the OpenBao break-glass material under
the operator's secure JuiceFS mount). Bundle persistence does not depend
on `dmf-env` surviving, and encrypted ciphertext never enters any
working tree — so `gitleaks` and `bin/scrub-public-repos.sh` cannot
fire on it.

Check `git status` before editing. The workspace may contain in-flight public
publish prep work.

## Architectural Interpretation

The DMF platform already uses EBU vocabulary:

- horizontal layers: 1 through 6
- verticals: security, orchestration, monitoring, control
- lifecycle stages: Design, Plan, Provision, Configure, Operate, Finalise

ADR-0012 was written for catalog/media workloads, but the same conceptual split
is useful for bootstrap. The important distinction is scope:

- **Bootstrap Provision:** make the platform itself exist.
- **Bootstrap Configure:** bind the platform apps into one facility control
  plane.
- **Workload Provision/Configure/Finalise:** publish, launch, and tear down
  media functions such as `nmos-cpp`.

Do not collapse these scopes. A platform bootstrap wrapper is not the same thing
as a `dmf-runbooks` catalog launcher.

## Definition Of Vanilla

In this plan, "vanilla" does not mean chart defaults or random credentials.

Vanilla means the application is installed with only app-local durable runtime
inputs:

- admin username/password
- database password
- application secret key
- API pepper or session secret
- image tag
- storage class and PVC size
- hostname and ingress shape
- app-local bootstrap htpasswd where needed

**Today:** Those values come through the legacy `dmf-env` wrapper
(`bin/export-openbao-vars.sh`), which reads operator-local files
(`~/.config/hcloud/cli.toml`, `~/.config/cf/dns.txt`,
`~/.config/ts/authkey.txt`) and self-seeds the rest (`vault_k3s_token`,
`vault_zot_admin_password`, `vault_awx_admin_password`) fresh on every wrapper
invocation.

**Target (after this refactor):** those values come from the encrypted
pre-Bao bootstrap bundle defined in
`docs/plans/DMF Pre-Bao Bootstrap Secrets Design 2026-05-08.md`. The bundle
lives outside any git tree, at `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml`
(operator-local secure path, default sibling of OpenBao break-glass
material). It is initialized before Ansible changes state, exported through
`dmf-env/bin/bootstrap-secrets.sh export-vars`, and seeded into OpenBao as
soon as OpenBao is initialized, unsealed, and policy-ready. That seed step
runs before Layer 6 app install; it is not a Bootstrap Configure phase.
Future runs are Bao-first with the encrypted bundle as the day-zero
fallback. Stable values must never be generated silently during a playbook
run.

Concrete values must never live in the public `dmf-infra` repo, and never
as `default('changeme')` / `default('admin')`-style fallbacks in role
defaults — those are how known fallback credentials end up in production. A missing
`vault_*` variable must fail the play, not silently boot a known-default
credential.

Every enabled app with a local admin surface must receive the same bootstrap
admin identity at first install:

```text
vault_bootstrap_admin_username
vault_bootstrap_admin_email
vault_bootstrap_admin_password
```

App-local Bao paths may exist for compatibility, but their username, email,
and password must be identical to `secret/platform/bootstrap_admin` unless the
role documents a technical exception. Apps with no local admin surface, such as
DMF Console, still receive the same operator identity through OIDC during
Bootstrap Configure.

Vanilla excludes cross-app relationships:

- Authentik OIDC/SAML clients for other apps
- NetBox service users and tokens for AWX, LibreNMS, CMS, catalog jobs
- Forgejo service user, automation repos, mirror setup
- AWX SCM projects, inventories, job templates, Machine credentials
- CMS API tokens for Authentik, AWX, NetBox, Forgejo
- born-inventory registration
- media workload launch or finalise operations

## Current State Summary

`dmf-infra/k3s-lab-bootstrap/lifecycle-provision.yml` currently has 40
literal `import_playbook` lines (38 active, 2 commented/reserved) and
mixes install, integration, verification, and some credential rotation.

The file syntax-checks today, but it does not strictly follow a vanilla
provision then configure model.

Observed issues from the survey:

- `site.yml` says default bootstrap runs "Provision + Configure", but it only
  imports `lifecycle-provision.yml`.
- `lifecycle-configure.yml` points at stale `../dmf-media/...` content and does
  not match the current `dmf-runbooks` Path A model. (2026-05-19 update: the
  `dmf-runbooks` Path A model is itself being superseded for media catalog
  launchers by [ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md);
  reconcile against the converged 2026-05-19 plan when re-touching this
  area.)
- `219-host-verify.yml` is tagged Layer 2, but it is really provider and
  orchestration preflight. It also mutates local `known_hosts` despite claiming
  read-only behavior.
- `331-registry-zot.yml` installs Zot before Authentik, then
  `vertical-security/191-zot-oidc.yml` reruns the Zot role after Authentik.
  The model is valid, but the implementation is duplicated and should become
  an explicit base-install plus OIDC-overlay split.
- `190-breakglass-verify.yml` is imported as a gate, but it is still a stub.
- `694-born-inventory.yml` has `gather_facts: false` in the fact-gathering play
  even though the role later reads gathered facts.
- `awx-integration` still bootstraps the control-node private key from an
  operator-local file path. This is not a good generic bootstrap interface for a
  public repo.
- Some public repo code and comments still contain operator-local paths such as
  `<home>/...` or `/Volumes/...`.

**Actual secret flow today** (audited 2026-05-07 — contradicts the assumed
model in several places):

- **No `vault.yml` in `dmf-env`.** Pre-Bao secrets are exported by
  `dmf-env/bin/export-openbao-vars.sh` from operator-local files
  (`~/.config/hcloud/cli.toml`, `~/.config/cf/dns.txt`,
  `~/.config/ts/authkey.txt`, ntfy/healthchecks URLs) plus self-seeded
  random values for `vault_k3s_token`, `vault_zot_admin_password`, and
  `vault_awx_admin_password`.
- **Self-seeded values regenerate every wrapper run.** For values that
  should be stable across re-runs (especially `vault_k3s_token`, which is
  cluster identity) this is a latent footgun. The target fix is not another
  dynamic generation path; it is the encrypted pre-Bao bundle plus Bao-first
  lookup after Bao is seeded.
- **OpenBao starts empty.** The OpenBao install role initializes engines
  and AppRole/Kubernetes auth but seeds no application secrets. In the target
  sequence, `bootstrap-secrets.sh seed-bao` populates platform bootstrap paths
  immediately after Bao readiness and before Layer 6 app install. App roles
  may still create post-Bao runtime tokens after their owning app exists.
- **ESO uses AppRole**, with `role_id` and `secret_id` read from the
  break-glass JSON written at OpenBao init time
  (`<secure-store>/openbao-breakglass/hetzner-lab/openbao-keys-automation.json`).
- **AWX control-node SSH key is half-migrated.** `awx-integration`
  writes it to `secret/apps/awx/control_node_ssh` but reads only from
  the operator-local default `<secure-store>/awx-control-node.privkey`.
  No read-from-Bao plumbing exists on the consumer side.
- **Three apps boot with hardcoded default credentials** — Forgejo, NetBox,
  and Grafana all have known username/password fallbacks when `vault_*` is
  missing.
  See "Initial App Credentials Audit" for file:line evidence and required
  fixes.

## Target Entrypoints

Preferred end state:

```text
dmf-env/
  bin/bootstrap-platform.sh
  bin/bootstrap-secrets.sh

k3s-lab-bootstrap/
  site.yml
  lifecycle-provision.yml
  bootstrap-provision-pre-seed.yml
  bootstrap-provision-post-seed.yml
  bootstrap-configure.yml
  bootstrap-verify.yml
  lifecycle-configure.yml
  lifecycle-operate.yml
  lifecycle-finalise.yml
```

Entrypoint responsibilities:

- `dmf-env/bin/bootstrap-platform.sh`: canonical fresh-bootstrap orchestrator.
  It validates the encrypted bundle, runs pre-seed provision, invokes
  `bootstrap-secrets.sh seed-bao`, then runs post-seed provision, configure,
  and verify. This is the only entrypoint that crosses the local encrypted
  bundle to OpenBao seed boundary.
- `site.yml`: Ansible convenience entrypoint. It should import
  `lifecycle-provision.yml`, but it is not the canonical first-run path unless
  the encrypted bundle has already been seeded into OpenBao.
- `lifecycle-provision.yml`: Ansible compatibility wrapper for an already
  seeded cluster. It may import pre-seed provision, post-seed provision,
  configure, and verify, but it must fail before post-seed app install if
  `secret/platform/bootstrap_admin` or `secret/platform/k3s/cluster` is absent.
- `bootstrap-provision-pre-seed.yml`: installs host, container platform,
  OpenBao, ESO, and the readiness gates needed before seed.
- `bootstrap-provision-post-seed.yml`: installs monitoring base and Layer 6
  applications in vanilla form after OpenBao has been seeded.
- `bootstrap-configure.yml`: wires cross-app relationships between already
  installed platform apps.
- `bootstrap-verify.yml`: runs real readiness and integration gates.
- `lifecycle-configure.yml`: workload/catalog configure only. It must not be
  used for bootstrap wiring. If it stays in `dmf-infra`, it should either be
  repointed to current `dmf-runbooks` semantics or converted into a short
  documentation stub that tells operators to use AWX/job templates.
- `lifecycle-operate.yml`: read-only operate/monitor checks.
- `lifecycle-finalise.yml`: teardown/finalise, including post-teardown
  Headscale cleanup.

Do not remove `lifecycle-provision.yml` in the first refactor. Existing operator
muscle memory and docs rely on it. Do not present it as the fresh-bootstrap
entrypoint until the seed boundary is handled by a `dmf-env` orchestrator.

## Bootstrap Provision Target Scope

Bootstrap Provision should install only platform-local capabilities.

Fresh bootstrap has a mandatory local seed boundary. The target order is:

1. Pre-seed provision: Preflight
   - current `219-host-verify.yml`, but eventually retag or rename as
     bootstrap preflight rather than Layer 2 Host Platform.

2. Pre-seed provision: Layer 2 Host Platform
   - `200-baseline.yml`
   - `210-harden.yml`

3. Pre-seed provision: Layer 3 Container Platform
   - `300-k3s.yml`
   - immediate k3s readiness gate from `301-k3s-verify.yml`
   - `310-ingress-public.yml`
   - `311-ingress-private.yml`
   - `320-cert-manager.yml`
   - `321-tailscale.yml`
   - `330-longhorn.yml`
   - base `331-registry-zot.yml`, with htpasswd/bootstrap auth only
   - container-platform readiness gate from `339-container-platform-verify.yml`

4. Pre-seed provision: Security and Orchestration Base
   - `vertical-security/100-openbao.yml`
   - `vertical-orchestration/100-eso.yml`
   - OpenBao network policies, if they do not block ESO or app bootstrap

5. Local seed boundary owned by `dmf-env`
   - seed the encrypted pre-Bao bundle into OpenBao after OpenBao is
     initialized, unsealed, and policy-ready
   - materialize `secret/platform/bootstrap_admin`,
     `secret/platform/k3s/cluster`, provider paths, notification paths, and
     app-local admin compatibility paths with identical bootstrap admin values
   - this is implemented as `dmf-env/bin/bootstrap-secrets.sh seed-bao`; that
     script may invoke a small generic dmf-infra seed play, but `dmf-env` owns
     decryption and bundle handling
   - this step must complete before any Layer 6 app install consumes local
     admin credentials

6. Post-seed provision: Monitoring Base
   - Prometheus
   - Loki
   - Promtail
   - Grafana installed in local/minimal form, with OIDC later

7. Post-seed provision: Layer 6 Vanilla App Installs
   - landing page
   - Authentik base install
   - NetBox base install
   - Forgejo base install
   - AWX base install
   - DMF Console base install

Provision may include local health checks that are prerequisites for the next
component. End-to-end integration checks belong in Bootstrap Verify.

## Bootstrap Configure Target Scope

Bootstrap Configure should run only after OpenBao has been seeded from the
pre-Bao bundle and the app pods exist. It does not create day-zero bootstrap
secrets. Its job is to wire relationships between already-installed platform
apps.

1. OpenBao and ESO follow-up
   - policy reconciliation if still needed
   - AppRole or ops-admin rotation only if deliberately retained in bootstrap
   - otherwise move routine rotation into operate/maintenance docs

2. Authentik facility identity graph
   - baseline groups
   - passkey/bootstrap flow objects
   - the shared bootstrap operator identity from `vault_bootstrap_admin_*`
   - app providers and applications for Forgejo, NetBox, Grafana, AWX, Zot,
     and DMF Console
   - admin/superadmin group membership for the shared operator identity in
     every OIDC-backed app

3. App identity overlays
   - Zot OIDC overlay
   - Grafana OIDC
   - NetBox OIDC
   - Forgejo OIDC
   - AWX SAML/OIDC integration
   - DMF Console OIDC

4. Source of Truth and automation wiring
   - `691-netbox-sot.yml`: NetBox service users, permissions, tokens, catalog
     tag taxonomy
   - `692-forgejo-bootstrap.yml`: Forgejo service user, repos, mirror
     bootstrap
   - `693-awx-integration.yml`: AWX SCM projects, inventory source, job
     templates, Machine credential, roles path
   - `694-born-inventory.yml`: cluster registration in NetBox

5. CMS integration wiring
   - `696-cms-authentik-api.yml`
   - `697-cms-awx-token.yml`
   - `698-cms-netbox-forgejo-tokens.yml`

Bootstrap Configure may create AWX templates such as `media-launch-nmos-cpp`
and `media-finalise-nmos-cpp`. It must not run those templates.

## Bootstrap Verify Target Scope

Bootstrap Verify should contain actual gates, not TODO messages.

Target checks:

- k3s nodes are Ready
- CoreDNS works
- public and private Traefik are reachable according to configured lane
- cert-manager wildcard/default certificate is Ready
- Longhorn StorageClass is default and usable
- Zot `/v2/` responds with expected auth behavior
- OpenBao is initialized, unsealed, and reachable through intended paths
- ESO `ClusterSecretStore` is Ready
- Authentik break-glass login path works
- Prometheus, Loki, Grafana, and Promtail are deployed
- app-local admin credentials, where supported, all match the shared
  bootstrap admin identity
- the seeded Authentik/OIDC operator identity has admin or superadmin access
  in every app that supports OIDC
- NetBox API responds and expected DMF tags exist
- Forgejo API responds and expected repos exist
- AWX API responds, NetBox inventory source exists, catalog job templates exist
- AWX Machine credential is attached to catalog templates
- born-inventory registered the cluster in NetBox
- DMF Console `/healthz` passes
- DMF Console runtime Secret has expected integration tokens
- DMF Console can query AWX inventories with its token

If a verify playbook is still a stub, do not present it as a hard gate.

## Role Split Requirements

A wrapper-only split is not enough. Several current roles mix install and
cross-app configuration internally. Split those roles gradually.

Recommended pattern:

```text
roles/stack/operator/<app>/
  tasks/main.yml
  tasks/provision.yml
  tasks/configure.yml
  tasks/verify.yml
```

`tasks/main.yml` can dispatch by a role variable:

```yaml
- ansible.builtin.include_tasks: "{{ app_stage }}.yml"
```

where `app_stage` defaults to `provision` for app-install playbooks. Prefer a
role-specific variable name if the role already has a naming convention.

Mixed roles to split:

- `stack/operator/authentik`
  - Provision: namespace, runtime secrets, shared bootstrap admin identity,
    ExternalSecrets, Helm install, server/worker readiness.
  - Configure: blueprints, app providers, passkey invitation, break-glass user.

- `stack/operator/zot`
  - Provision: namespace, config Secret with htpasswd/bootstrap auth,
    StatefulSet, Service, Certificate, IngressRoute. The htpasswd/admin value
    comes from `vault_bootstrap_admin_*`.
  - Configure: Authentik OIDC client discovery, config rerender, persistent
    controlled rollout.

- `base/grafana`
  - Provision: namespace, chart, PVC, dashboards, shared local admin/runtime
    values.
  - Configure: Authentik OAuth client read and OAuth secret/update.

- `stack/operator/netbox`
  - Provision: runtime app secrets, wrapper chart, PVCs, Service/IngressRoute,
    shared local superuser, base API readiness.
  - Configure: Authentik OAuth wiring and any schema patch needed only for
    downstream integration.

- `stack/operator/forgejo`
  - Provision: namespace, chart, PVC, shared local admin path, Service/Ingress.
  - Configure: Authentik OAuth source and service account integration.

- `stack/operator/awx`
  - Provision: operator, AWX instance, shared admin Secret, Service/Ingress,
    base API.
  - Configure: Authentik SAML certificate discovery and SSO settings.

- `stack/operator/cms`
  - Provision: namespace, runtime Secret with app-local values, image/chart
    deploy, health endpoint.
  - Configure: OIDC client credentials and API tokens for Authentik, AWX,
    NetBox, and Forgejo.

Do not split everything in one risky commit. Preserve current behavior first,
then isolate one app at a time.

## Wrapper Migration Strategy

### Phase 0 - Safety Baseline

1. Record `git status` in umbrella and `dmf-infra`.
2. Run:

   ```bash
   cd dmf-infra/k3s-lab-bootstrap
   ANSIBLE_LOCAL_TEMP=/private/tmp/.ansible ansible-playbook --list-tasks lifecycle-provision.yml -i inventories/example/hosts.ini
   ANSIBLE_LOCAL_TEMP=/private/tmp/.ansible ansible-playbook --syntax-check lifecycle-provision.yml -i inventories/example/hosts.ini
   ```

3. Save the task order outside the repo if needed for comparison.

### Phase 1 - Entrypoint Scaffolding

Add:

- `bootstrap-provision-pre-seed.yml`
- `bootstrap-provision-post-seed.yml`
- `bootstrap-configure.yml`
- `bootstrap-verify.yml`

Change:

- `lifecycle-provision.yml` becomes an Ansible compatibility wrapper for
  already-seeded clusters and re-runs.
- `dmf-env` gains the canonical fresh-bootstrap orchestration entrypoint that
  runs the pre-seed playbook, seed command, post-seed playbook, configure, and
  verify.
- `site.yml` comment is corrected so it says exactly what happens.
- `lifecycle-configure.yml` is repointed or retired as workload-only.

Do not claim the split is complete in Phase 1 if mixed roles remain.

### Phase 2 - Move Existing Whole Playbooks

Move imports that are already semantically configure into
`bootstrap-configure.yml`:

- `vertical-security/191-zot-oidc.yml`
- `691-netbox-sot.yml`
- `692-forgejo-bootstrap.yml`
- `693-awx-integration.yml`
- `694-born-inventory.yml`
- `696-cms-authentik-api.yml`
- `697-cms-awx-token.yml`
- `698-cms-netbox-forgejo-tokens.yml`

Move smoke and end-to-end checks into `bootstrap-verify.yml`:

- `699-cms-smoke-test.yml`
- `339-container-platform-verify.yml`, if it is treated as an end-of-layer gate
  instead of an inline prerequisite
- real replacement for `190-breakglass-verify.yml`

Keep immediate dependency checks inline where they prevent confusing later
failures. Example: k3s network verification can remain directly after k3s until
the verify wrapper has richer dependency gating.

### Phase 3 - Split Mixed App Roles

For each mixed role:

1. Move app install tasks into `tasks/provision.yml`.
2. Move cross-app wiring tasks into `tasks/configure.yml`.
3. Update the app playbook or add new paired playbooks.
4. Run `--list-tasks` for both wrappers.
5. Run `--syntax-check`.
6. Only then proceed to the next role.

Do not change behavior and sequencing for multiple stateful apps in the same
commit unless there is no practical alternative.

### Phase 4 - Pre-Bao Bundle And Shared Admin Plumbing

Implement the target from
`docs/plans/DMF Pre-Bao Bootstrap Secrets Design 2026-05-08.md` before changing
Layer 6 role behavior:

- add `dmf-env/bin/bootstrap-secrets.sh` with `init`, `doctor`, `export-vars`,
  `seed-bao`, `status`, and optional `rotate`. The script must refuse to
  operate if `${DMF_BOOTSTRAP_BUNDLE_DIR}` resolves to a path inside any
  git working tree.
- create the operator-local secure bundle directory at
  `${DMF_BOOTSTRAP_BUNDLE_DIR}` (default sibling of OpenBao break-glass
  material under the operator's secure JuiceFS mount), permissions
  `0700`, **outside any git tree**
- add age public recipients to `dmf-env/.sops.yaml`; the age private key
  stays in operator Keychain or a strict-permissioned file outside any
  DMF repo
- add or document the `dmf-env` fresh-bootstrap orchestrator that sequences:
  pre-seed provision, seed-bao, post-seed provision, configure, verify
- make `run-playbook.sh` consume `bootstrap-secrets.sh export-vars` with
  a `0600` tmpfs-preferred temp file cleaned by `trap` on `EXIT ERR INT
  TERM` (per ADR-0007)
- keep `export-openbao-vars.sh` only as a temporary compatibility wrapper, if
  needed
- seed OpenBao immediately after OpenBao readiness and before Layer 6 app
  install
- materialize app-local admin paths from the shared
  `secret/platform/bootstrap_admin` value for compatibility
- update app roles to consume `vault_bootstrap_admin_*` and fail when missing

Phase mapping against
`docs/plans/DMF Pre-Bao Bootstrap Secrets Design 2026-05-08.md`:

| This plan | Pre-Bao design | Notes |
|---|---|---|
| Phase 0 | Required Context + Verification Checklist | establish baseline before edits |
| Phase 1 | Step 3 plus Bootstrap Sequence | add wrappers and dmf-env orchestrator |
| Phase 2 | Step 6 | move cross-app wiring into Bootstrap Configure |
| Phase 3 | Step 5 | split roles and remove known credential defaults |
| Phase 4 | Steps 1-4 | bundle, export-vars, run-playbook, seed-bao |
| Phase 5 | Step 7 plus public-push hygiene | cleanup and documentation alignment |

### Phase 5 - Clean Stale Paths And Secret Boundaries

Fix or document these before public push:

- `ansible.cfg` must not hardcode `<repos>/...`.
- OpenBao custody paths under `/Volumes/...` should be variables sourced from
  `dmf-env` or documented as example-only defaults outside generic code.
- `awx_control_node_ssh_privkey_path` must not default to an operator-local
  private path in public `dmf-infra`.
- AWX control-node private key should be preloaded by `dmf-env` or an operator
  bootstrap step, then read from OpenBao by `dmf-infra`.
- Do not write back to `vault.yml` from generic bootstrap. Day-zero stable
  bootstrap values live in the encrypted pre-Bao bundle and then OpenBao.
  Long-lived generated runtime credentials live in OpenBao.

## Initial Wrapper Sketch

This is a target sketch, not a patch.

`lifecycle-provision.yml`:

```yaml
---
# Compatibility wrapper for already-seeded clusters.
# Fresh first-run bootstrap must use the dmf-env orchestrator so the local
# encrypted bundle can be seeded into OpenBao between pre-seed and post-seed.
- import_playbook: bootstrap-provision-pre-seed.yml
  tags: [bootstrap, bootstrap-provision, bootstrap-pre-seed, lifecycle-provision]

- import_playbook: bootstrap-provision-post-seed.yml
  tags: [bootstrap, bootstrap-provision, bootstrap-post-seed, lifecycle-provision]

- import_playbook: bootstrap-configure.yml
  tags: [bootstrap, bootstrap-configure, lifecycle-provision]

- import_playbook: bootstrap-verify.yml
  tags: [bootstrap, bootstrap-verify, lifecycle-provision, verify]
```

The post-seed wrapper must include an early assertion that
`secret/platform/bootstrap_admin` and `secret/platform/k3s/cluster` exist in
OpenBao. That keeps accidental first-run use of `lifecycle-provision.yml` from
installing apps before their shared credentials exist.

Canonical fresh-bootstrap orchestration in `dmf-env`:

```bash
bin/bootstrap-secrets.sh doctor hetzner-arm
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-pre-seed.yml
bin/bootstrap-secrets.sh seed-bao hetzner-arm
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/bootstrap-provision-post-seed.yml
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/bootstrap-configure.yml
bin/run-playbook.sh hetzner-arm ../dmf-infra/k3s-lab-bootstrap/bootstrap-verify.yml
```

`bootstrap-provision-pre-seed.yml`:

```yaml
---
# Install platform capabilities needed before OpenBao can receive bundle data.

- import_playbook: playbooks/219-host-verify.yml
  tags: [bootstrap-preflight, verify]

- import_playbook: playbooks/200-baseline.yml
  tags: [layer2, host-platform, baseline]

- import_playbook: playbooks/210-harden.yml
  tags: [layer2, host-platform, security]

# Continue with Layer 3, Zot bootstrap auth if needed, OpenBao, ESO, and
# readiness checks. Stop before monitoring and Layer 6 app install.
```

`bootstrap-provision-post-seed.yml`:

```yaml
---
# Install platform applications after seed-bao has populated OpenBao.

# First assert that secret/platform/bootstrap_admin and
# secret/platform/k3s/cluster exist in OpenBao.

# Continue with monitoring base and vanilla Layer 6 app installs.
```

`bootstrap-configure.yml`:

```yaml
---
# Wire already-installed platform capabilities into the DMF facility graph.
# Assumes the pre-Bao bundle has already been seeded into OpenBao.

- import_playbook: playbooks/vertical-security/191-zot-oidc.yml
  tags: [bootstrap-configure, vertical-security, registry, identity, zot]

- import_playbook: playbooks/691-netbox-sot.yml
  tags: [bootstrap-configure, layer6, netbox, sot]

- import_playbook: playbooks/692-forgejo-bootstrap.yml
  tags: [bootstrap-configure, layer6, forgejo]

- import_playbook: playbooks/693-awx-integration.yml
  tags: [bootstrap-configure, layer6, awx, integration]

# Continue with born-inventory and CMS token wiring.
```

`bootstrap-verify.yml`:

```yaml
---
# Real bootstrap gates only. No workload launch.

- import_playbook: playbooks/339-container-platform-verify.yml
  tags: [bootstrap-verify, layer3, verify]

- import_playbook: playbooks/699-cms-smoke-test.yml
  tags: [bootstrap-verify, layer6, dmf-console, smoke-test]
```

## dmf-runbooks Boundary

`dmf-runbooks` owns media-function lifecycle execution.

Current examples:

- `dmf-runbooks/playbooks/launch-nmos-cpp.yml`
- `dmf-runbooks/playbooks/teardown-nmos-cpp.yml`
- `dmf-runbooks/roles/nmos-cpp/tasks/provision.yml`
- `dmf-runbooks/roles/nmos-cpp/tasks/configure.yml`
- `dmf-runbooks/roles/nmos-cpp/tasks/finalise.yml`

Bootstrap Configure may ensure AWX knows about these launchers. It must not
invoke them.

The expected state after bootstrap is:

- AWX project exists.
- AWX inventory source exists.
- AWX job templates exist.
- AWX Machine credential is attached.
- CMS can see or launch the templates through its API token.
- No NMOS workload has been launched solely by bootstrap.

Launching `media-launch-nmos-cpp` is a workload Configure action. Tearing it
down is a workload Finalise action.

## Pre-Bao vs Post-Bao Secret Sources

This section is aligned with
`docs/plans/DMF Pre-Bao Bootstrap Secrets Design 2026-05-08.md`, which is the
canonical design for gathering, storing, exporting, and migrating day-zero
bootstrap secrets. It replaces the 2026-05-07 assumption that the wrapper should
generate values locally and have Bootstrap Configure persist them later.

### The cutline

`vertical-security/100-openbao.yml` is the runtime-secret cutline. Plays before
OpenBao readiness cannot read from Bao, so they consume values exported from the
encrypted pre-Bao bundle. Immediately after OpenBao is initialized, unsealed,
and policy-ready, the bundle is seeded into Bao. Plays after that point read
Bao first, with the encrypted bundle retained as the day-zero fallback.

### Day-zero source before Bao

Target source is:

```text
${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml
```

managed by:

```text
dmf-env/bin/bootstrap-secrets.sh
```

`DMF_BOOTSTRAP_BUNDLE_DIR` defaults to a directory adjacent to the OpenBao
break-glass material under the operator's secure JuiceFS mount (per ADR-0009
custody). The bundle is SOPS/age encrypted and lives **outside any git
tree** — `dmf-env` is a temporary, no-remote, operator-local clone, so
bundle persistence cannot depend on it; and encrypted ciphertext that
might coincidentally match `gitleaks`/scrub-script regexes never enters a
working tree. Age public recipients are committed in `dmf-env/.sops.yaml`;
the age private key lives in operator Keychain. The bundle is initialized
before Ansible changes state. It contains or imports:

- `vault_bootstrap_admin_username`
- `vault_bootstrap_admin_email`
- `vault_bootstrap_admin_password`
- `vault_k3s_token`
- provider tokens such as Hetzner, Cloudflare, and Tailscale/Headscale
- notification endpoints/tokens

The AWX control-node SSH private key is not part of the generic encrypted
bootstrap bundle in the first implementation. It remains owned by the
ADR-0016/operator-bootstrap path and is seeded to
`secret/apps/awx/control_node_ssh` through a dedicated `dmf-env` step before
AWX integration consumes it. Revisit this only if reproducible rebuilds require
including that key in the SOPS bundle.

`bootstrap-secrets.sh export-vars <env> <output-json>` emits Ansible vars for
`run-playbook.sh`. During transition it may also emit legacy names such as
`vault_awx_admin_password`, `vault_zot_admin_password`,
`vault_forgejo_admin_password`, `vault_netbox_superuser_password`, and
`vault_grafana_admin_password`, but they must all map to the shared bootstrap
admin password. No wrapper or playbook may silently generate a new stable value
during a run.

### OpenBao seeding point

Run `bootstrap-secrets.sh seed-bao <env>` after OpenBao readiness and before
Layer 6 app install. The implementation may call a small generic dmf-infra
play, but `dmf-env` owns decryption and bundle handling.

Seed collision behavior must be explicit:

- if a target path is absent, write it from the encrypted bundle
- if a target path exists with the same value, do nothing
- if a platform path exists with a different value, fail and require an
  explicit rotate operation
- if an app-local admin path exists with a different value, fail and require an
  explicit app-account migration play that updates the app account and Bao
  together

Do not silently overwrite app-local admin paths. Updating Bao alone can create
drift if the app's internal user database still has the old password.

Canonical seed targets:

| Bao path | Source | Notes |
|---|---|---|
| `secret/platform/bootstrap_admin` | `vault_bootstrap_admin_*` | Canonical shared local admin identity |
| `secret/platform/k3s/cluster` | `vault_k3s_token` | Stable cluster identity and join token |
| `secret/platform/hetzner` | `vault_hcloud_token` | Imported provider token |
| `secret/platform/cloudflare` | `vault_cloudflare_dns_token` | Imported provider token |
| `secret/platform/tailscale` | `vault_tailscale_authkey` | Imported or generated through provider command |
| `secret/platform/notifications` | alertmanager/healthchecks vars | Optional if notifications disabled |
| `secret/apps/<app>/admin` | shared bootstrap admin identity | Compatibility copies only; values must match platform path |
| `secret/apps/awx/control_node_ssh` | dedicated operator-bootstrap source | Read-from-Bao consumer path still needs implementation |

### Off-limits (cannot live in Bao or `dmf-env`)

| What | Lives where | Why |
|---|---|---|
| OpenBao Shamir shares (5 shares, threshold 3 / 3-of-5) | JuiceFS `<secure-store>/openbao-breakglass/.../` + macOS Keychain + USB | Chicken-and-egg: needed to unseal Bao itself |
| ESO AppRole break-glass JSON | Same JuiceFS path | Needed to (re-)bootstrap ESO before Bao has its AppRole back |

### Post-Bao generated sources

After the owning app exists, app-specific runtime tokens are created by the
owning configure play and written to Bao. Examples:

- NetBox API/service/AWX tokens from `691-netbox-sot.yml`
- Forgejo service tokens from `692-forgejo-bootstrap.yml`
- AWX service token and Machine credential wiring from `693-awx-integration.yml`
- Authentik OIDC client secrets from Authentik provider configuration
- DMF Console integration tokens from the CMS configure plays

These are not pre-Bao inputs unless a specific app proves otherwise. If an app
or chart creates an unavoidable dynamic secret, the role must read it once with
`no_log`, write it to Bao, and switch future runs to Bao-first. Dynamic
pre-Bao generation is an exception path, not the architecture.

### Ownership table

| Credential type | Day-zero source | Steady-state source | Notes |
|---|---|---|---|
| Cloud provider tokens | Encrypted pre-Bao bundle | OpenBao at `secret/platform/<provider>` | Imported by `bootstrap-secrets.sh init`; seeded before app install |
| Platform-internal stable IDs such as k3s token | Encrypted pre-Bao bundle | OpenBao at `secret/platform/k3s/cluster` | Generated once, stable across reruns |
| Shared app-local bootstrap admin | Encrypted pre-Bao bundle | `secret/platform/bootstrap_admin`; app-local copies if needed | Same username/email/password for every local admin surface |
| App runtime secrets such as DB passwords, peppers, secret keys | Generated on first app install or configure | OpenBao at `secret/apps/<app>/runtime` | App-owned, post-Bao only unless proven otherwise |
| App service/API tokens | Owning app configure play | OpenBao app runtime paths | Created only after app exists |
| AWX control-node SSH key | Dedicated operator-bootstrap source | OpenBao at `secret/apps/awx/control_node_ssh` | Consumer side must read from Bao after seed; not in generic bundle initially |
| OpenBao unseal quorum + ESO AppRole JSON | JuiceFS + Keychain + USB | Same | Off-limits, never in dmf-env or dmf-infra |

### Hard rules

- **No `default('changeme')`, `default('admin')`, or any literal default
  credential in role defaults** — even if a wrapper masks the fallback
  in normal flow. A missing `vault_*` variable must fail the play, not
  silently boot a known-default credential.
- **No concrete secret values in `dmf-infra` ever.** Variables only.
- **No `vault_*` writeback to a `vault.yml` file in `dmf-env`.** The encrypted
  bootstrap bundle (at `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml`,
  outside any git tree) is the only pre-Bao durable secret file.
- **Pre-Bao values are generated or imported before Ansible changes state.**
  Do not create stable bootstrap secrets inside playbooks.
- **Writes to OpenBao always use stdin/no-log-safe transport** — never argv,
  never plaintext tempfiles, never printed env vars.
- **Subsequent bootstrap re-runs read from Bao first** for any value
  previously seeded — silent rotation of stable IDs is a bug.

## Initial App Credentials Audit

Audited 2026-05-07 and revised 2026-05-08 against
`docs/plans/DMF Pre-Bao Bootstrap Secrets Design 2026-05-08.md`. Every Layer 6
app's first-boot admin credential was checked. The user's flag about Forgejo's
known local fallback is confirmed and applies to NetBox and Grafana as well; AWX,
Zot, and `awx-integration` also carry `default('changeme')` in role defaults
but are masked in normal flow by the legacy wrapper auto-generating the var.

The target is no longer per-app generated admin passwords. Every enabled app
with a local admin surface uses the same shared bootstrap admin identity from
`vault_bootstrap_admin_*`, and the same human identity is granted
admin/superadmin rights through Authentik/OIDC during Bootstrap Configure.

### Per-app verdict

| App | Current username | Current password source | Required target | Evidence |
|---|---|---|---|---|
| Authentik | `akadmin` | `secret/apps/authentik/admin` | Use `vault_bootstrap_admin_*`; Authentik user becomes the seeded platform admin | `roles/stack/operator/authentik/tasks/main.yml` |
| Zot | `admin` | `secret/apps/zot/admin`; role default still has `default('changeme')` | Use shared bootstrap admin htpasswd/admin data; remove fallback | `roles/stack/operator/zot/defaults/main.yml:31` |
| DMF Console | N/A | N/A | No local admin surface; seeded OIDC identity must be platform admin | `roles/stack/operator/cms/defaults/main.yml` |
| AWX | `awx-local-admin` | `vault_awx_admin_password`, regenerated by legacy wrapper and only in K8s Secret | Use shared bootstrap admin; persist compatibility copy to `secret/apps/awx/admin` | `roles/stack/operator/awx/defaults/main.yml:9` |
| AWX integration | `awx-local-admin` | nested `default(vault_awx_admin_password \| default('changeme'))` | Read same shared bootstrap admin value; remove fallback | `roles/stack/operator/awx-integration/defaults/main.yml:58` |
| Forgejo | **`dev`** | `vault_forgejo_admin_password \| default('changeme')` | Use shared bootstrap admin username/password; remove `dev` and fallback | `roles/stack/operator/forgejo/defaults/main.yml:38-40` |
| NetBox | `admin` | `vault_netbox_superuser_password \| default('changeme')` | Use shared bootstrap admin as superuser; remove fallback | `roles/stack/operator/netbox/defaults/main.yml:5-6` |
| Grafana | `admin` | `vault_grafana_admin_password \| default('admin')` | Use shared bootstrap admin as local admin; OIDC admin is layered later | `roles/base/grafana/defaults/main.yml:5` |

Apps with no local admin login do not need a local credential fix: Prometheus,
Alertmanager, Loki, Longhorn. Where they have an Authentik-protected UI, the
seeded OIDC operator identity must still receive the intended admin/superadmin
access.

### Severity tiers

- **UNSAFE (P0 — must fix before public push):** Forgejo, NetBox,
  Grafana. These boot with literal default credentials if `vault_*` is
  unset; nothing in the current pipeline guarantees the var is set.
- **VIOLATES RULE (P1 — fix in same refactor):** Zot, AWX,
  awx-integration. The wrapper masks the default in normal flow, but the
  rule "no `default('changeme')` in role defaults" applies regardless of
  mitigation. A skipped wrapper invocation, a forgotten env var, or a
  partial re-run reaches the fallback.
- **ALIGNMENT REQUIRED (P1):** Authentik currently has a safer persisted
  path, but it still needs to become the same shared bootstrap admin identity
  used by the rest of the app stack.

### Required fixes

1. **Shared bootstrap admin plumbing**: implement
   `vault_bootstrap_admin_username`, `vault_bootstrap_admin_email`, and
   `vault_bootstrap_admin_password` in the encrypted pre-Bao bundle, export
   them through `bootstrap-secrets.sh export-vars`, and seed
   `secret/platform/bootstrap_admin` plus app-local compatibility paths before
   Layer 6 app install.

2. **Forgejo**: remove `dev` and `default('changeme')`; source local admin
   username/password from `vault_bootstrap_admin_*` or an app-local Bao copy
   that is identical to `secret/platform/bootstrap_admin`.

3. **NetBox**: remove `default('changeme')`; source the superuser username,
   email, and password from `vault_bootstrap_admin_*`. Runtime secrets
   (DB pass, peppers) stay in `secret/apps/netbox/runtime`.

4. **Grafana**: remove `default('admin')`; use the shared bootstrap admin as
   the local Grafana admin. Authentik/OIDC remains a Configure overlay, not a
   prerequisite for first login.

5. **AWX**: remove `default('changeme')` from both
   `roles/stack/operator/awx/defaults/main.yml:9` and
   `roles/stack/operator/awx-integration/defaults/main.yml:58`.
   Source the AWX operator admin Secret from `vault_bootstrap_admin_*` before
   the AWX CR reconciles. During transition, `vault_awx_admin_password` may be
   emitted as an alias for `vault_bootstrap_admin_password`.

6. **Zot**: remove `default('changeme')` from
   `roles/stack/operator/zot/defaults/main.yml:31`. Today
   `vertical-security/191-zot-oidc.yml` already calls `app-admin-facts`, so the
   path exists; the role default must require the shared bootstrap admin value
   instead of falling back.

7. **Authentik**: align the bootstrap superuser/admin path with
   `vault_bootstrap_admin_*`. Configure must create or verify the same human
   identity and map it into every app's admin/superadmin group. For existing
   clusters, do not silently rename or delete the legacy `akadmin` user. Create
   or verify the shared bootstrap user as an admin first; disabling or removing
   `akadmin` is a separate explicit hardening/migration step.

8. **DMF Console**: keep OIDC-only. Configure must ensure the seeded OIDC
   identity has platform-admin rights.

9. **Wrapper and bundle**: replace self-seeded behavior in
   `dmf-env/bin/export-openbao-vars.sh` with `bootstrap-secrets.sh export-vars`
   compatibility. Repeated exports must return the same k3s token and bootstrap
   admin password.

### Acceptance: hard requirement

After this refactor, **no Layer 6 app may boot with a literal default
credential.** A missing `vault_*` variable must fail the play. The
following grep must return zero credential-context hits across the
public `dmf-infra` repo:

```bash
grep -rnE "default\(\s*['\"](changeme|admin|password|dev)['\"]" \
  dmf-infra/k3s-lab-bootstrap/roles/ \
  | grep -vE 'acme_email|@example\.com'
```

Acceptable false-positive matches (non-credential): `cert_manager_acme_email`
defaults to `admin@example.com`, which is not a credential.

## Specific Fixes To Include

These fixes are tightly related to the split and should be addressed during or
immediately after the wrapper refactor.

1. Correct `site.yml` comments so they no longer claim implicit Configure unless
   the wrapper actually imports `bootstrap-configure.yml`.

2. Fix or retire `lifecycle-configure.yml`. It currently points at stale
   `dmf-media` paths and should not be confused with bootstrap configuration.

3. Retag or rename `219-host-verify.yml` as bootstrap preflight. It checks
   provider, DNS, local tools, and SSH, not only Layer 2 Host Platform.

4. Make `219-host-verify.yml` honest about `known_hosts` mutation, or move that
   task into a separate explicit cleanup/preflight step.

5. Replace `190-breakglass-verify.yml` with a real gate before it remains in a
   verify wrapper.

6. Fix `694-born-inventory.yml` fact gathering. The first play should gather
   facts if the role consumes `ansible_default_ipv4`, memory, mounts, distro,
   and kernel facts.

7. Remove duplicate Zot rollout in `vertical-security/191-zot-oidc.yml` after
   the Zot role has already restarted for OIDC.

8. Remove duplicate OpenBao read in `awx-integration` for the control-node SSH
   key.

9. Replace public default local paths for AWX private key and OpenBao custody
   paths with variables or documented private-repo inputs.

10. Decide whether routine ESO and ops-admin rotations belong in Bootstrap
    Configure or in Operate. Do not leave them hidden in a file named Provision
    without an explicit rationale.

11. Remove `dev` username + `default('changeme')` from Forgejo role defaults
    (`roles/stack/operator/forgejo/defaults/main.yml:38-40`). Source the
    local admin username/password from `vault_bootstrap_admin_*` or an
    app-local Bao copy identical to `secret/platform/bootstrap_admin`.

12. Remove `default('changeme')` from NetBox role defaults
    (`roles/stack/operator/netbox/defaults/main.yml:5-6`). Source the
    superuser username/email/password from `vault_bootstrap_admin_*`.

13. Remove `default('admin')` from Grafana role defaults
    (`roles/base/grafana/defaults/main.yml:5`). Use the shared bootstrap admin
    as Grafana's local admin; OIDC admin mapping remains a Configure overlay.

14. Remove `default('changeme')` from AWX role defaults
    (`roles/stack/operator/awx/defaults/main.yml:9`) and
    `awx-integration` (`roles/stack/operator/awx-integration/defaults/main.yml:58`).
    Source the AWX admin Secret from `vault_bootstrap_admin_*`. Ensure value
    lands in `awx-<instance>-admin-password` Secret before AWX CR reconciliation.

15. Remove `default('changeme')` from Zot role defaults
    (`roles/stack/operator/zot/defaults/main.yml:31`). The
    app-local path already exists via `191-zot-oidc.yml`; the role default
    just needs to require the shared bootstrap admin value.

16. Add `dmf-env/bin/bootstrap-secrets.sh` and wire `run-playbook.sh` to call
    `bootstrap-secrets.sh export-vars`. Repeated exports must return stable
    values for `vault_k3s_token` and `vault_bootstrap_admin_password`.

17. Add the OpenBao seed step immediately after OpenBao readiness and before
    Layer 6 app install. Seed `secret/platform/bootstrap_admin`,
    `secret/platform/k3s/cluster`, provider paths, notification paths, and
    app-local admin compatibility paths. This is a `dmf-env` local seed
    boundary between pre-seed and post-seed provision; it is not part of
    Bootstrap Configure.

18. Add read-from-Bao path for AWX control-node SSH key in
    `awx-integration` role. Today the role writes to
    `secret/apps/awx/control_node_ssh` but reads only from
    `awx_control_node_ssh_privkey_path` (operator-local file). The
    dedicated operator-bootstrap path becomes a day-zero seed source only; the
    generic encrypted bootstrap bundle does not carry this key in the first
    implementation.

19. **Verify the Kubernetes audit policy filters request bodies for the
    new `secret/platform/*` paths.** Per
    `dmf-infra/docs/archive/SECURITY-REMEDIATION-N1-AUDIT-LEAK.md`,
    OpenBao writes must log at Metadata level only — request bodies must
    not be captured. Bootstrap Secret Seed introduces new write targets
    (`secret/platform/bootstrap_admin`, `secret/platform/k3s/cluster`,
    `secret/platform/{hetzner,cloudflare,tailscale,notifications}`) plus
    app-local admin compatibility paths under `secret/apps/*/admin`. If
    the existing audit-policy rule (configured by
    `vertical-security/100-openbao.yml` or the cluster-level
    audit-policy YAML) uses a `secret/apps/*` prefix filter, extend it
    to `secret/platform/*` and `secret/apps/*/admin` before `seed-bao`
    runs against any environment.

## Verification Commands

**These commands are static-only.** `--syntax-check` and `--list-tasks`
do not connect to any host; they validate Ansible YAML and resolve task
graphs locally. Live runs (without those flags, against the real
cluster) must go through `dmf-env/bin/run-playbook.sh hetzner-arm
<playbook>` per ADR-0010 — never invoke `ansible-playbook` directly
against the live inventory.

Run from `dmf-infra/k3s-lab-bootstrap`:

```bash
ANSIBLE_LOCAL_TEMP=/private/tmp/.ansible ansible-playbook --syntax-check lifecycle-provision.yml -i inventories/example/hosts.ini
ANSIBLE_LOCAL_TEMP=/private/tmp/.ansible ansible-playbook --syntax-check bootstrap-provision-pre-seed.yml -i inventories/example/hosts.ini
ANSIBLE_LOCAL_TEMP=/private/tmp/.ansible ansible-playbook --syntax-check bootstrap-provision-post-seed.yml -i inventories/example/hosts.ini
ANSIBLE_LOCAL_TEMP=/private/tmp/.ansible ansible-playbook --syntax-check bootstrap-configure.yml -i inventories/example/hosts.ini
ANSIBLE_LOCAL_TEMP=/private/tmp/.ansible ansible-playbook --syntax-check bootstrap-verify.yml -i inventories/example/hosts.ini
```

Task graph checks:

```bash
ANSIBLE_LOCAL_TEMP=/private/tmp/.ansible ansible-playbook --list-tasks lifecycle-provision.yml -i inventories/example/hosts.ini
ANSIBLE_LOCAL_TEMP=/private/tmp/.ansible ansible-playbook --list-tasks bootstrap-provision-pre-seed.yml -i inventories/example/hosts.ini
ANSIBLE_LOCAL_TEMP=/private/tmp/.ansible ansible-playbook --list-tasks bootstrap-provision-post-seed.yml -i inventories/example/hosts.ini
ANSIBLE_LOCAL_TEMP=/private/tmp/.ansible ansible-playbook --list-tasks bootstrap-configure.yml -i inventories/example/hosts.ini
ANSIBLE_LOCAL_TEMP=/private/tmp/.ansible ansible-playbook --list-tasks bootstrap-verify.yml -i inventories/example/hosts.ini
```

Do not run live cluster bootstrap from this plan unless explicitly asked.

## Acceptance Criteria

The refactor is acceptable when:

- A fresh reader can answer "what installs apps?" and "what wires apps
  together?" from wrapper names alone.
- `dmf-env` has a canonical fresh-bootstrap orchestration path that runs
  pre-seed provision, `bootstrap-secrets.sh seed-bao`, post-seed provision,
  configure, and verify in that order.
- `lifecycle-provision.yml` remains a working compatibility entrypoint for
  already-seeded clusters and fails before app install if required Bao seed
  paths are absent.
- `bootstrap-provision-pre-seed.yml` and `bootstrap-provision-post-seed.yml`
  do not launch media catalog workloads.
- `bootstrap-configure.yml` does not launch media catalog workloads.
- `dmf-runbooks` remains the owner of workload launch/finalise playbooks.
- `lifecycle-configure.yml` is no longer stale or misleading.
- Syntax-check passes for all bootstrap wrappers.
- `--list-tasks` shows provision before configure before verify.
- **No Layer 6 app boots with a literal default credential**
  (`changeme`, default admin/admin pairs, `dev`, or similar). A missing `vault_*`
  variable fails the play. The grep gate from "Initial App Credentials
  Audit" returns zero credential-context hits.
- **All enabled apps with a local admin surface use the same shared
  bootstrap admin identity** from `vault_bootstrap_admin_*`. App-local Bao
  admin paths, if kept for compatibility, contain identical username, email,
  and password values.
- **The seeded OIDC operator identity has admin/superadmin rights** in
  Authentik, Forgejo, NetBox, Grafana, AWX, Zot where applicable, and DMF
  Console.
- **Pre-Bao secrets are sourced from the encrypted bundle** managed by
  `dmf-env/bin/bootstrap-secrets.sh`, not generated inside playbooks or
  regenerated by `export-openbao-vars.sh`.
- **The encrypted bundle lives outside any git tree** at
  `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml`. `git ls-files` in
  `dmf-env` returns no matches for `*.sops.yaml` or any `secrets/`
  path. The pre-commit hook + `bin/scrub-public-repos.sh` cannot fire
  on bundle ciphertext because it never enters a working tree.
- **Pre-Bao secrets are seeded into OpenBao before Layer 6 app install** at
  canonical `secret/platform/*` paths plus app-local admin compatibility paths,
  idempotent across re-runs.
- **Seed collision behavior is explicit**: same value is a no-op; missing path
  is written; differing platform paths require rotate; differing app-local
  admin paths require an app-account migration play.
- **Re-running bootstrap does not silently rotate** `vault_k3s_token`,
  provider tokens, or the shared bootstrap admin password.
- App-local credentials come from the encrypted bundle or OpenBao — concrete
  values never appear in `dmf-infra`.
- Existing behavior is preserved unless a change is explicitly called
  out in the commit message or implementation notes.

## Non-Goals

- Do not redesign the media catalog model.
- Do not move `nmos-cpp` back into `dmf-infra`.
- Do not launch `media-launch-nmos-cpp` during platform bootstrap.
- Do not make `dmf-env` public.
- Do not solve every public-publish hygiene item in the same patch unless it is
  directly blocking the wrapper split.
- Do not rename `k3s-lab-bootstrap` as part of this lifecycle split. That is a
  separate public-repo naming decision.

## Open Questions

1. Should `lifecycle-configure.yml` remain in `dmf-infra` as a workload
   convenience wrapper, or should workload Configure be exposed only through
   AWX and `dmf-runbooks`?

2. Should routine credential rotation run during every bootstrap configure pass,
   or should it move to `lifecycle-operate.yml` / maintenance runbooks?
   Specifically: ESO AppRole `secret_id` rotation per
   `dmf-infra/docs/SECURITY-REMEDIATION-GUIDE.md` Issue #6, ops-admin
   userpass rotation, and any post-seed Bao re-key. The existing
   `dmf-env/bin/rotate-approle-secret-id.sh` is the operational tool;
   the question is whether bootstrap should invoke it on every run, on a
   cadence, or never (operator-driven). Recommend: keep rotation out of
   bootstrap, document it in `lifecycle-operate.yml` and a maintenance
   runbook in `dmf-env/docs/`. Resolve before declaring Phase 4
   complete.

3. Should monitoring base move earlier than the full security vertical so the
   rest of bootstrap is observed from first app install onward?

4. Should `219-host-verify.yml` become `100-bootstrap-preflight.yml` or stay in
   place with corrected tags to minimize churn before public push?

5. ~~Should "vanilla" DMF Console run with auth disabled until Configure,
   or is OIDC a minimum app-local boot dependency for this app?~~
   **RESOLVED 2026-05-07**: DMF Console is OIDC-only (no local admin
   credential); see `roles/stack/operator/cms/defaults/main.yml`. It has
   no first-boot credential problem, but its OIDC client wiring must
   land in Configure before any human can log in — accept this as the
   known gating dependency.

6. ~~Grafana first-login posture: local admin or OIDC-only first login?~~
   **RESOLVED 2026-05-08**: Grafana gets the same shared local bootstrap admin
   credential as the other local-admin apps. Authentik/OIDC admin mapping is a
   Bootstrap Configure overlay.

7. ~~Migration timing for AWX control-node SSH key: manual procedure or
   Ansible play from the operator machine?~~
   **RESOLVED 2026-05-08**: keep the key outside the generic encrypted
   bootstrap bundle for the first implementation. A dedicated `dmf-env`
   operator-bootstrap step seeds `secret/apps/awx/control_node_ssh`; `dmf-infra`
   consumes only Bao. Document the step in `dmf-env` and revisit bundle storage
   only if reproducible rebuilds require it.

8. ~~Long-term: should pre-Bao secrets move from operator-local files into
   age-encrypted files committed to `dmf-env`?~~
   **RE-RESOLVED 2026-05-08 (later same day)**: yes to age-encrypted, but
   **outside the `dmf-env` git tree**. The bundle lives at
   `${DMF_BOOTSTRAP_BUNDLE_DIR}/<env>.sops.yaml` (operator-local secure
   path, default sibling of OpenBao break-glass material), not committed
   to any repo. `dmf-env` is a temporary, no-remote, operator-local clone;
   bundle persistence cannot depend on it, and encrypted ciphertext must
   not enter any working tree where gitleaks/scrub-script regexes could
   coincidentally fire. Canonical design:
   `docs/plans/DMF Pre-Bao Bootstrap Secrets Design 2026-05-08.md`.

9. **Authentik `akadmin` deprecation timing.** The design Phase D
   prohibits silently renaming or deleting the legacy `akadmin` user
   when an existing cluster is re-bootstrapped against the shared
   bootstrap admin identity. That keeps re-bootstrap safe but leaves a
   stale privileged account behind. Any access review (per
   `dmf-infra/docs/security-compliance-framework-plan.md` Phase 1
   deliverables) would flag it. Open: who removes it and when? Options:
   (a) a dedicated explicit hardening play in `lifecycle-operate.yml`
   that the operator runs once after verifying the new shared admin
   works; (b) Bootstrap Verify surfaces a warning until it is gone; (c)
   a manual `dmf-env`-side runbook step. Recommend (a) + (b) together —
   visible warning, deliberate cleanup. Resolve before Phase 3 role
   refactor lands the Authentik change.

10. **Per-secret data classification.** Today the bootstrap docs treat
    every secret uniformly. The `security-compliance-framework-plan.md`
    Phase 1 deliverables include data classification (Public / Internal /
    Confidential / Secret) for each value, which drives retention,
    rotation cadence, and breach-notification scope. Open: do we add a
    classification column to the Bundle Schema and the canonical OpenBao
    paths table now, or defer to a follow-up classification doc? Default
    if classified now: provider tokens = Confidential, k3s token =
    Confidential, shared bootstrap admin password = Confidential,
    operator email = Internal. Recommend: defer to a small follow-up
    doc owned by the framework-plan rather than expanding scope here.

11. **Audit-policy verification ownership.** Specific Fix #19 requires
    confirming the Kubernetes audit policy filters the new
    `secret/platform/*` and `secret/apps/*/admin` paths at Metadata
    level. Open: which role owns the verification — a Bootstrap Verify
    gate that asserts the running audit policy contains the expected
    rule, a manual operator check before first `seed-bao`, or both?
    Recommend: add the assertion to `bootstrap-verify.yml` so it is
    mechanical, with a manual operator check in the day-zero
    documentation as belt-and-braces. Resolve when implementing fix
    #19.
