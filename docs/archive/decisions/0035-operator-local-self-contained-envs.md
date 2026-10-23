# ADR-0035 archive: Envs are fully operator-local and self-contained; dmf-env is generic tooling + modules

This file holds material moved out of [ADR-0035](../../decisions/0035-operator-local-self-contained-envs.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Keep per-env artifacts in dmf-env, just fix the key mismatch.** Rejected —
  leaves the removal friction, the identity-in-repo problem, and the shared-key
  dances intact.
- **Per-env keypair stored as files in a `0600` dir** (not the bundle). Rejected
  — less aligned with the "secrets sops-encrypted at rest" policy and fragile on
  WSL2/DrvFS, where `0600` is not preserved.
- **Wizard runs `tofu apply` itself.** Rejected — resource creation / cost must
  stay a deliberate, separate operator action.

## Moved from the ADR on 2026-10-23

### Context (original)

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


### Neutral consequence (original)

- **Neutral** — Terraform state was already operator-local
  (`TERRAFORM_STATE_ROOT`); this just moves it into the per-env dir. The
  co-located per-env `.sops.yaml` also resolves the cloud-lane
  `bundle_sops_config_file` issue hardened earlier.

### Enforcement lines (original)

- Verification gate (per the refactor plan): `git -C dmf-env status` stays clean
  through create → apply → bootstrap → teardown.
- `docs/plans/dmf-env-lifecycle-refactor-plan.md` is the implementation
  plan; honors ADR-0031 (self-contained gate) + the secrets-discipline conventions.
