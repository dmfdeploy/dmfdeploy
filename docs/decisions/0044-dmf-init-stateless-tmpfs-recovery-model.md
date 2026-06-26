<!-- ADR doc convention: every ADR carries a top-of-doc **Rule:** line — the binding
constraint in one imperative sentence — directly under the metadata block. See
CONTRIBUTING.md → "ADR conventions". -->
# ADR-0044: dmf-init stays stateless — tmpfs-only env state, enforced; durable recovery is the encrypted bundle, not host persistence

**Status:** Proposed
**Date:** 2026-06-26
**Deciders:** @znerol2 (with Claude drafting the facet-(c) decision for the dmf-init long-run re-entry hardening plan, codex adversarial gate-review)
**Rule:** dmf-init persists **no** env state to host disk; `DMF_DATA_ROOT` **must** be tmpfs (enforced fail-closed at startup, not warn-only). The disk-backed resume cursor is tmpfs-only and is **not** durable across `docker rm`/recreate; cross-lifetime (crash / host-reboot) recovery is **rollback to the last checkpoint that has been exported off-tmpfs** (downloaded recovery bundle) — never a host-mounted durable store. Because that is a rollback (not same-step resume), the design **must make checkpoint export reliable before long unattended phases**.

Related: tightens the dmf-init runtime contract from [ADR-0036](0036-dmf-init-thin-control-container.md) (thin control container) and the bootstrap plan's tmpfs-only/safe-`docker rm` promise.

## Context

The dmf-init long-run re-entry hardening plan (issue #150, plan
*DMF Init Long-Run Re-Entry & Resume Hardening Plan 2026-06-26*) raised facet
(c): the v0.3.4 "disk-backed resume" promises a run survives a restart, but the
stated contract is **tmpfs-only runtime state + safe `docker rm`**
(`README.md:34-36`, bootstrap plan 2026-06-02 §15-17/§52-60). A `docker restart`
with the designed `--tmpfs` mount wipes tmpfs, so "survive a restart" and
"tmpfs-only" appear to contradict — tempting a host-mounted durable cursor, which
would break the stateless/disposable contract.

The real tension is narrower than it looks. The lockout incident's container was
**healthy and never restarted** — the restart was forced *only* to mint a new
launch token after the session expired (the missing facet (b)). So "must survive
a restart" was a **symptom of missing in-band re-entry**, not an inherent need
for durable persistence. Separately, the incident exposed a live contract
**violation**: `DMF_DATA_ROOT` was on the container's overlay layer (no `--tmpfs`
passed), and `_assert_data_root_tmpfs` only `logger.warning`s (`manage.py:116`) —
so the age key and `openbao-keys.json` actually touched disk, silently.

## Decision

dmf-init **stays strictly stateless**. All env state — including the disk-backed
resume cursor — lives in tmpfs; the only durable artifact is the
operator-held, passphrase-encrypted recovery bundle. We **reaffirm "`docker rm`
is safe"** and add enforcement:

1. **Enforce tmpfs fail-closed at startup.** `DMF_DATA_ROOT` must resolve to a
   `tmpfs`/`ramfs` mount; if not, dmf-init refuses to start (not a warning, not
   only at restore time). This closes the gap that let the incident's secrets
   land on the overlay layer.
2. **The resume cursor is a within-container-lifetime convenience.** It survives
   an in-process restart and an in-memory-run GC (v0.3.4) — it is **not** promised
   across `docker rm`/recreate, and we stop implying otherwise.
3. **Cross-lifetime / crash recovery = rollback to the last *exported* checkpoint.**
   The durable artifact is the downloaded recovery bundle (v0.3.4). Be honest
   about what this is: checkpoints exist only at **#2 (post-pre-seed)** and **#3
   (post-verify)** (`bootstrap_steps.py`), so a crash between them rolls back to
   #2 — replaying `post-seed → configure → workstation/passkey pauses → verify`,
   **not** a same-step resume. We **accept "rollback to the latest exported
   checkpoint" as the crash contract** (codex P1.1) — it is strictly weaker than
   the within-lifetime cursor, and that is the cost of staying stateless.
4. **The bundle only counts once it has left tmpfs.** The sealed backup lives
   under `DMF_DATA_ROOT/artifacts` (tmpfs) until the operator downloads it; a
   crash before download leaves **no** cross-lifetime artifact (codex P1.2). So
   the design **must make checkpoint export reliable before long unattended
   phases** — e.g. auto-trigger the browser download when a checkpoint seals,
   and/or gate unattended continuation past #2 on a *proven* download. This is a
   firm requirement of this decision, not a nicety.
5. **Reject a host-mounted durable cursor.** Durable resume across container
   recreation stays out of scope; the marginal gain over (forced) bundle-export
   does not justify breaking the stateless contract or adding a host volume.

This is safe **because** plan facets (a) long/sliding session + (b) in-band
launch-link re-mint remove the need to restart a *healthy* container — so the
only restart left is a genuine crash, which the (exported) bundle covers, at the
rollback granularity stated above.

## Consequences

- **Positive** — The stateless/`docker rm`-safe contract is preserved *and*
  enforced; the silent secrets-to-disk path (overlay `DMF_DATA_ROOT`) is closed.
  Facet (c) shrinks from "build durable persistence" to "reaffirm + enforce" —
  less code, no new host-volume surface, no new secret-handling risk.
- **Negative** — A genuine container crash/host-reboot mid-run is **not** a
  seamless in-place resume; it is a **rollback to the last exported checkpoint**
  (#2 or #3) and requires the operator to restore from the recovery bundle
  (passphrase needed). A crash before the operator has downloaded any checkpoint
  loses everything — which is why forced export (Decision 4) is mandatory, not
  optional. We accept the rollback granularity as the documented crash path.
- **Negative / sequencing** — Enforcing tmpfs fail-closed makes a `docker restart`
  destructive to in-flight tmpfs state. It must therefore land **with or after**
  facet (b) (in-band re-mint), or operators lose the accidental overlay-durability
  that this incident relied on for recovery. Enforce in that order.
- **Neutral** — The README run command must show the `--tmpfs` mount as
  mandatory; a run without it now fails fast instead of degrading silently.

## Alternatives considered

- **Host-mounted durable cursor (persist non-secret cursor + render meta to a
  volume; secrets stay tmpfs).** Gives seamless resume across `docker rm`. Rejected:
  breaks the "nothing durable on host disk / safe `docker rm`" contract, adds an
  operator-mounted volume and a new secret-scoping boundary to get wrong, for
  marginal benefit over the already-shipped bundle-restore path.
- **Status quo (warn-only tmpfs check, rely on accidental overlay durability).**
  Rejected: it is exactly what let secrets touch disk in the incident, and
  "durability by accident of a missing `--tmpfs` flag" is not a contract.

## Enforcement

- **CI / code:** a startup tmpfs check in dmf-init (`main.py` lifespan) that
  fail-closes on a non-tmpfs `DMF_DATA_ROOT`; promote `_assert_data_root_tmpfs`
  from warn-only to the shared fail-closed check. Unit test: non-tmpfs root →
  startup refusal.
- **Dev/test scope (codex P2.1):** the fail-closed check must **not** break CI /
  local iteration — today tests run `create_app` on a plain filesystem
  (`tests/test_resume.py`). Pick one and state it in the impl: appliance/entrypoint
  enforcement only (not the bare app), an explicit dev/test override env, or move
  tests to a tmpfs path (`/dev/shm`). Also define non-Linux behaviour (the helper
  is Linux-conditional today).
- **Forced checkpoint export (Decision 4):** the run flow must auto-export (or
  prove export of) a checkpoint before long unattended phases; without it the
  crash contract has no artifact.
- **Docs sequencing (codex P2.2):** the README run command currently **omits
  `--tmpfs`** — fail-closed enforcement must land **with** the README/runbook
  update making `--tmpfs /tmp/dmf-init-data` mandatory, or the documented
  invocation simply starts failing.
- **Plan linkage:** implements facet (c) of the long-run re-entry plan (#150);
  depends on facet (b) landing first (sequencing above). The plan's step 4 +
  verification are being realigned to bundle-only (they predated this ADR).
- This ADR is **Proposed** — ratify via the CONTRIBUTING RFC step (Discussions)
  before flipping to Accepted; codex adversarial gate-review (CHANGES-NEEDED →
  addressed) precedes ratification.
