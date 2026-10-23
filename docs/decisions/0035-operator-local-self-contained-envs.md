# ADR-0035: Envs are fully operator-local and self-contained; dmf-env is generic tooling + modules

**Status:** Accepted
**Date:** 2026-06-01
**Deciders:** @<handle>
**Rule:** Every env (cloud + sandbox) is fully operator-local and self-contained under `~/.dmfdeploy/envs/<env>/`, with nothing per-env committed; dmf-env is generic: scripts, `terraform/modules/`, one per-provider root, neutral tasks/templates.

## Context

The cloud-env lane scattered each env's artifacts across dmf-env (committed
inventories, manifests, Terraform roots and per-env `.sops.yaml` rules) and
operator-local directories (the SOPS bundle, tfvars, Terraform state). This made
env removal manual, put env identity in a repo, and caused SSH key contamination
across envs. The sandbox lane already keeps every env under
`~/.dmfdeploy/envs/<env>/` (ADR-0031). The full cost list is in the archive record.

## Decision

Extend the **operator-local "new" layout to all envs** (cloud + sandbox). Every
env is fully self-contained under `~/.dmfdeploy/envs/<env>/`. It holds the inventory,
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
- **The wizard does everything before resource creation.**
  It renders, validates (`doctor`), `tofu init`, and `tofu plan` (saving the
  plan), then stops. The wizard does not run `tofu apply`. Creating resources
  (cost and blast radius) stays a deliberate operator action. A first-class `bin/remove-env.sh` does teardown + removal in
  one command (`tofu destroy` → delete the per-env key → `rm -rf` the env dir).

This **changes dmf-env's documented role** from "private inventory + Terraform
Layer-1" to "generic env tooling + modules." Legacy in-repo cloud envs
(`aliyun*`, `hetzner-arm`, `<env>`) are all defunct and are deleted
wholesale; the resolver's legacy branch is retired.

## Consequences

- **Positive:** Removing an env is `rm -rf` + `tofu destroy`, no git surgery; no
  cross-env contamination; teardown/build have no `prevent_destroy`/`import`
  dances; dmf-env stops carrying env identity and stops churning; cloud and
  sandbox share one model + one resolver; per-env keys die with their env.
- **Negative:** One-time refactor across the resolver, `tf-apply`/`tf-destroy`,
  the wizard, `run-playbook`, and the Terraform layout; the generic root must take
  manifest/output paths as input variables; privkey-in-bundle adds a runtime
  materialization step.

### Rejected alternatives

- Keep per-env artifacts in dmf-env and only fix the key mismatch: rejected, it leaves the removal friction, the identity-in-repo problem and the shared-key dances intact.
- Store the per-env keypair as files in a `0600` directory, outside the bundle: rejected, it is less aligned with the "secrets sops-encrypted at rest" policy and fragile on WSL2/DrvFS, where `0600` is not preserved.
- Let the wizard run `tofu apply`: rejected, resource creation and cost must stay a deliberate, separate operator action.

### Enforcement

- `dmf-env/.github/workflows/ci.yml` runs `tofu validate` on the generic
  `terraform/hetzner` root and the `dmf-env/tests/remove-env-data-root.sh` and
  `dmf-env/tests/remove-env-sandbox-noop.sh` tests for the single-command removal.
- Discipline only: no check rejects a per-env artifact committed to dmf-env. The
  operator confirms `git -C dmf-env status` stays clean through the env lifecycle.
- `docs/plans/dmf-env-lifecycle-refactor-plan.md` is the implementation plan.

## Status

Accepted

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0035-operator-local-self-contained-envs.md).
