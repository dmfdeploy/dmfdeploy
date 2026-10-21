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
