<!-- ADR doc convention: every ADR carries a top-of-doc **Rule:** line — the binding
constraint in one imperative sentence — directly under the metadata block. See
docs/decisions/README.md → "ADR conventions". -->
# ADR-0044: dmf-init stays stateless: tmpfs-only env state, enforced; durable recovery is the encrypted bundle and never host persistence

**Status:** Accepted (2026-07-02; implementation landed in dmf-init v0.3.5; fail-closed `assert_data_root_tmpfs` startup guard, forced checkpoint-export gate before long unattended phases, launcher `--tmpfs :exec` noexec guard; #150 and #162 closed)
**Date:** 2026-06-26.
**Deciders:** @znerol2 (with Claude drafting the facet-(c) decision for the dmf-init long-run re-entry hardening plan, codex adversarial gate-review)
**Rule:** dmf-init persists **no** env state to host disk; `DMF_DATA_ROOT` **must** be tmpfs (enforced fail-closed at startup; a warning alone does not satisfy the Rule). The disk-backed resume cursor is tmpfs-only and is **not** durable across `docker rm`/recreate. Cross-lifetime (crash / host-reboot) recovery is **rollback to the last checkpoint that has been exported off-tmpfs** (downloaded recovery bundle). A host-mounted durable store is never used. Because that is a rollback (not same-step resume), the design **must make checkpoint export reliable before long unattended phases**.

Related: tightens the dmf-init runtime contract from [ADR-0036](0036-dmf-init-thin-control-container.md) (thin control container) and the bootstrap plan's tmpfs-only/safe-`docker rm` promise.

## Context

The v0.3.4 "disk-backed resume" promises a run survives a restart, but the stated contract is **tmpfs-only runtime state + safe `docker rm`**. A `docker restart` with the designed `--tmpfs` mount wipes tmpfs, so the two appear to contradict. That tempts a host-mounted durable cursor, which would break the stateless/disposable contract (issue #150, facet (c) of the long-run re-entry plan).

Problem statement and evidence: see the [archive record](../archive/decisions/0044-dmf-init-stateless-tmpfs-recovery-model.md).

## Decision

dmf-init **stays strictly stateless**. All env state, including the disk-backed resume cursor, lives in tmpfs. The only durable artifact is the operator-held, passphrase-encrypted recovery bundle. We **reaffirm "`docker rm` is safe"** and add enforcement:

1. **Enforce tmpfs fail-closed at startup.** `DMF_DATA_ROOT` must resolve to a `tmpfs`/`ramfs` mount. If it does not, dmf-init refuses to start. A warning is not enough, and a check at restore time alone is not enough. This closes the gap that let the incident's secrets land on the overlay layer.
2. **The resume cursor is a within-container-lifetime convenience.** It survives an in-process restart and an in-memory-run GC (v0.3.4). It is **not** promised across `docker rm`/recreate, and we stop implying otherwise.
3. **Cross-lifetime / crash recovery = rollback to the last *exported* checkpoint.** The durable artifact is the downloaded recovery bundle (v0.3.4). Checkpoints exist only at **#2 (post-pre-seed)** and **#3 (post-verify)** (`bootstrap_steps.py`). A crash between them rolls back to #2 and replays `post-seed → configure → workstation/passkey pauses → verify`. It does not resume the same step. We **accept "rollback to the latest exported checkpoint" as the crash contract** (codex P1.1). It is strictly weaker than the within-lifetime cursor, and that is the cost of staying stateless.
4. **The bundle only counts once it has left tmpfs.** The sealed backup lives under `DMF_DATA_ROOT/artifacts` (tmpfs) until the operator downloads it. A crash before download leaves **no** cross-lifetime artifact (codex P1.2). So the design **must make checkpoint export reliable before long unattended phases**, for example by auto-triggering the browser download when a checkpoint seals, and/or by gating unattended continuation past #2 on a *proven* download. This is a firm requirement of this decision.
5. **Reject a host-mounted durable cursor.** Durable resume across container recreation stays out of scope. The marginal gain over (forced) bundle-export does not justify breaking the stateless contract or adding a host volume.

This is safe **because** plan facets (a) long/sliding session and (b) in-band launch-link re-mint remove the need to restart a *healthy* container. The only restart left is a genuine crash, which the (exported) bundle covers at the rollback granularity stated above.

### Amendment (2026-07-01): the tmpfs data root must be **exec**-mounted (#162)

**Invariant (refines the Rule):** `DMF_DATA_ROOT` must be tmpfs **and** exec-mounted: `docker: --tmpfs /tmp/dmf-init-data:exec`. This does **not** relax this ADR's Rule. The mount stays tmpfs (RAM-only secrets, `docker rm`-safe) and retains `nosuid`/`nodev`. The `exec` option is orthogonal to the secrets-on-disk concern. A `noexec` mount gave no real protection here: the directory exists to run the toolchain, and interpreters bypass `noexec` trivially. Splitting into an exec repos-mount and a noexec secrets/artifacts-mount is deferred and tracked separately.

**Enforcement (extends the fail-closed check):** `assert_data_root_tmpfs` also rejects a tmpfs-but-`noexec` data root at startup, with an actionable message pointing at `:exec`. The README / `build-bundle.sh` run commands and the `bin/dmf-init` launcher use `--tmpfs /tmp/dmf-init-data:exec`.

## Consequences

- **Positive:** the stateless/`docker rm`-safe contract is preserved and enforced, and the silent secrets-to-disk path (overlay `DMF_DATA_ROOT`) is closed. No new host-volume surface and no new secret-handling risk.
- **Negative:** a genuine container crash or host reboot mid-run is **not** a seamless in-place resume. It is a **rollback to the last exported checkpoint** (#2 or #3) and requires the operator to restore from the recovery bundle (passphrase needed). A crash before the operator has downloaded any checkpoint loses everything, which is why forced export (Decision 4) is mandatory. We accept the rollback granularity as the documented crash path.
- **Negative / sequencing:** enforcing tmpfs fail-closed makes a `docker restart` destructive to in-flight tmpfs state. It must therefore land **with or after** facet (b) (in-band re-mint), or operators lose the accidental overlay-durability that this incident relied on for recovery. Enforce in that order.
- **Neutral:** the README run command must show the `--tmpfs` mount as mandatory. A run without it now fails fast instead of degrading silently.
- **Docs sequencing (codex P2.2):** fail-closed enforcement must land **with** the README/runbook update making `--tmpfs /tmp/dmf-init-data` mandatory.

## Enforcement

- `dmf-init/src/dmf_init/manage.py` (`assert_data_root_tmpfs`) fail-closes on a non-tmpfs or `noexec` data root. `dmf-init/src/dmf_init/main.py` calls it at startup unless `DMF_ALLOW_NON_TMPFS_DATA_ROOT` is set, the dev/test override (codex P2.1). On non-Linux the check allows, because mounts cannot be read.
- `dmf-init/tests/test_tmpfs.py` covers startup refusal on a non-tmpfs root, the `noexec` case and the override.
- Forced checkpoint export (Decision 4): `dmf-init/tests/test_bootstrap_steps.py` asserts the `checkpoint-2-export-gate` step.

## Status

Accepted (2026-07-02; implementation landed in dmf-init v0.3.5; fail-closed `assert_data_root_tmpfs` startup guard, forced checkpoint-export gate before long unattended phases, launcher `--tmpfs :exec` noexec guard; #150 and #162 closed)

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0044-dmf-init-stateless-tmpfs-recovery-model.md).
