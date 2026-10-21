# ADR-0044 archive: dmf-init stays stateless — tmpfs-only env state, enforced; durable recovery is the encrypted bundle, not host persistence

This file holds material moved out of [ADR-0044](../../decisions/0044-dmf-init-stateless-tmpfs-recovery-model.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Host-mounted durable cursor (persist non-secret cursor + render meta to a
  volume; secrets stay tmpfs).** Gives seamless resume across `docker rm`. Rejected:
  breaks the "nothing durable on host disk / safe `docker rm`" contract, adds an
  operator-mounted volume and a new secret-scoping boundary to get wrong, for
  marginal benefit over the already-shipped bundle-restore path.
- **Status quo (warn-only tmpfs check, rely on accidental overlay durability).**
  Rejected: it is exactly what let secrets touch disk in the incident, and
  "durability by accident of a missing `--tmpfs` flag" is not a contract.

## Context — the narrower tension and the incident evidence (moved from the ADR)

The real tension is narrower than it looks. The lockout incident's container was
**healthy and never restarted** — the restart was forced *only* to mint a new
launch token after the session expired (the missing facet (b)). So "must survive
a restart" was a **symptom of missing in-band re-entry**, not an inherent need
for durable persistence. Separately, the incident exposed a live contract
**violation**: `DMF_DATA_ROOT` was on the container's overlay layer (no `--tmpfs`
passed), and `_assert_data_root_tmpfs` only `logger.warning`s (`manage.py:116`) —
so the age key and `openbao-keys.json` actually touched disk, silently.

## Amendment (2026-07-01) — problem and evidence (moved from the ADR)

The tmpfs mandate above says nothing about the mount's `exec` flag, and Docker's
`--tmpfs` default is **`noexec`**. But `DMF_DATA_ROOT` is an **execution root**:
the render step execs `init-wizard.sh` directly (`createnew.py`), which in turn
directly execs ~40 dmf-env `bin/` tools. On a `noexec` mount every render fails
with `PermissionError: [Errno 13] … init-wizard.sh` (a direct exec returns 126;
only interpreter-wrapped `bash script.sh` would work, which is infeasible across
the whole toolchain). Found via the published `curl … | bash -s -- up` launcher.

## Enforcement — plan linkage bullet (moved from the ADR)

- **Plan linkage:** implements facet (c) of the long-run re-entry plan (#150);
  depends on facet (b) landing first (sequencing above). The plan's step 4 +
  verification are being realigned to bundle-only (they predated this ADR).
