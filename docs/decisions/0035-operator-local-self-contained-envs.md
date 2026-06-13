# ADR-0035: Envs are fully operator-local and self-contained; dmf-env is generic tooling + modules

**Status:** Accepted
**Rule:** Every env (cloud + sandbox) is fully operator-local and self-contained under `~/.dmfdeploy/envs/<env>/`, with nothing per-env committed; dmf-env is generic — scripts, `terraform/modules/`, one per-provider root, neutral tasks/templates.

## Context

The cloud-env lane scattered each env's artifacts across **dmf-env** (committed
`inventories/<env>/`, `manifests/<env>.yaml`, `terraform/<env>/`, and per-env
`.sops.yaml` creation rules) **and** operator-local dirs (the SOPS bundle,
`<provider>.tfvars`, Terraform state). This had three recurring costs, all hit
while standing up a fresh Hetzner env (2026-06-01):

- **Removal is manual git surgery + scattered `rm`s** across the repo and
  `~/secure`; failed/aborted wizard runs left orphaned committed dirs and dangling
  `.sops.yaml` rules.
- **dmf-env carries env identity** (IPs, domains, opaque slugs, SOPS age
  recipients, operator pubkeys), so it can never be anything but a private repo
  and churns on every env.
- A **shared, `prevent_destroy`'d** SSH key (`k3s-hetzner`) plus the wizard's
  reuse-by-fingerprint logic produced cross-env key-name contamination and a
  `prevent_destroy` replace-deadlock, requiring `state rm` / `import` dances on
  every teardown/build.

The **sandbox lane already** solved this (ADR-0031 / the 2026-05-28 consolidation):
every sandbox env lives entirely under `~/.dmfdeploy/envs/<env>/`, is committed to
no repo, and is removed with a single `rm -rf`. The path resolver
`dmf-env/bin/lib/_resolve_env_paths.sh` already models a **"new"** (operator-local)
vs **"legacy"** (in-repo) layout.

## Decision

Extend the **operator-local "new" layout to all envs** (cloud + sandbox). Every
env is fully self-contained under `~/.dmfdeploy/envs/<env>/` — inventory,
manifest, SOPS bundle + co-located `.sops.yaml`, `<provider>.tfvars`, Terraform
state, and the per-env SSH keypair. **dmf-env becomes a generic repo**: `bin/`
scripts, `terraform/modules/`, **one generic per-provider Terraform root**
(`terraform/<provider>/`, parameterized by operator-local manifest/tfvars/state
paths), and neutral `tasks/`/`templates/`. No per-env artifacts are ever
committed.

Consequences for keys and lifecycle:

- **SSH keys are per-env.** The wizard generates an `ed25519` keypair per env
  (skippable bring-your-own override); the Hetzner key is always
  `${env_id}-operator`, created from the per-env pubkey. The reuse-by-fingerprint
  path and the shared `prevent_destroy` key are removed.
- **The private key lives in the per-env SOPS bundle** (encrypted at rest;
  portable via age/sops; no reliance on filesystem `0600` semantics, which DrvFS
  breaks on WSL2). The public key is a non-secret per-env file. The privkey is
  materialized to an ephemeral `0600` temp at runtime (mirroring how
  `run-playbook.sh` already materializes the vars file).
- **The wizard does everything up to — but not including — resource creation.**
  It renders, validates (`doctor`), `tofu init`, and `tofu plan` (saving the
  plan), then stops. `tofu apply` (cost / blast radius) stays a deliberate
  operator action. A first-class `bin/remove-env.sh` does teardown + removal in
  one command (`tofu destroy` → delete the per-env key → `rm -rf` the env dir).

This **changes dmf-env's documented role** from "private inventory + Terraform
Layer-1" to "generic env tooling + modules." Legacy in-repo cloud envs
(`aliyun*`, `hetzner-arm`, `wobe-9n0c`) are all defunct and are deleted
wholesale; the resolver's legacy branch is retired.

## Consequences

- **Positive** — Removing an env is `rm -rf` + `tofu destroy`, no git surgery; no
  cross-env contamination; teardown/build have no `prevent_destroy`/`import`
  dances; dmf-env stops carrying env identity and stops churning; cloud and
  sandbox share one model + one resolver; per-env keys die with their env.
- **Negative** — One-time refactor across the resolver, `tf-apply`/`tf-destroy`,
  the wizard, `run-playbook`, and the Terraform layout; the generic root must take
  manifest/output paths as input variables; privkey-in-bundle adds a runtime
  materialization step.
- **Neutral** — Terraform state was already operator-local
  (`TERRAFORM_STATE_ROOT`); this just moves it into the per-env dir. The
  co-located per-env `.sops.yaml` also resolves the cloud-lane
  `bundle_sops_config_file` issue hardened earlier.

## Alternatives considered

- **Keep per-env artifacts in dmf-env, just fix the key mismatch.** Rejected —
  leaves the removal friction, the identity-in-repo problem, and the shared-key
  dances intact.
- **Per-env keypair stored as files in a `0600` dir** (not the bundle). Rejected
  — less aligned with the "secrets sops-encrypted at rest" policy and fragile on
  WSL2/DrvFS, where `0600` is not preserved.
- **Wizard runs `tofu apply` itself.** Rejected — resource creation / cost must
  stay a deliberate, separate operator action.

## Enforcement

- Verification gate (per the refactor plan): `git -C dmf-env status` stays clean
  through create → apply → bootstrap → teardown.
- `docs/plans/DMF Env Lifecycle Refactor Plan 2026-06-01.md` is the implementation
  plan; honors ADR-0031 (self-contained gate) + the secrets-discipline conventions.
