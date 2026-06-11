# DMF Architectural Commitments — v1 (2026-06-06)

**Status:** Accepted — closes the [ADR-0004](0004-experiment-phase-stance.md)
experiment-phase commit gate.
**Supersedes (stance, for the committed core):** ADR-0004 "experiment, not hardening"
— see §"Relationship to ADR-0004".
**Source:** the 2026-04-30 strategic review's commit gate fired; confirmed by the
2026-06-06 technical evaluation + CEO/eng review (dual-voice: Claude subagent + codex,
both CONFIRMED). Operator decisions D1 (commit now) and D2 (credibility-signal first).

---

## Why this exists

The [2026-04-30 strategic review](../reviews/dmf-platform-strategic-review-2026-04-30.md)
set an explicit commit gate:

> When dmf-cms release-1's first vertical slice runs end-to-end against real backends
> **AND** one NMOS registry is deployed in dmf-media, write
> `architectural-commitments-v1.md` and **stop reshaping the foundations.**

Per [TODOS.md](../../TODOS.md): **Move 2** (vertical slice → AWX → NetBox) closed
2026-05-04; **Move 1** (NMOS registry) closed 2026-06-04, runtime-verified. **Both
halves are met.** The gate fired ~5 weeks before this doc was written, and the project
kept choosing work under the experiment-phase doctrine — including a foundation-reshaping
move (the Argo+AWX actuator hybrid, last umbrella commit) that *reverses an existing ADR*,
which is exactly what the gate said to stop doing.

This document closes that gate. From here, **new work follows the committed layout
instead of reshaping it.**

---

## The v0.1 commitments (frozen architecture)

These are the load-bearing decisions for v0.1. They are **committed** — changing one is
a deliberate amendment to this doc, not a casual refactor.

1. **Single-node / Flypack is the proof surface.** The validated, demonstrable profile
   is single-node (Lima sandbox today; Flypack/OB-truck is its production sibling).
   Multi-node HA and cloud are **non-goals for v0.1** (see below).
2. **AWX is the catalog actuator.** The catalog control chain (catalog YAML → Provision
   → AWX JT → launcher playbook → Helm → health_probe → Finalise → NetBox tag) is the
   committed mechanism. It is proven end-to-end (NMOS + the vertical slice).
   ([ADR-0013](0013-media-function-catalog-model.md), [ADR-0014](0014-awx-project-layout.md),
   [ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md).)
3. **NetBox tags are the lifecycle state.** Lifecycle status lives as NetBox tags written
   by a scoped service account ([ADR-0032](0032-catalog-launcher-scoped-netbox-writer.md)).
   Flows stay runtime-only ([ADR-0037](0037-media-workloads-netbox-instance-inventory.md)).
4. **dmf-init is the installer.** A thin control container that clones playbooks at a
   selected ref and pulls images from GHCR ([ADR-0036](0036-dmf-init-thin-control-container.md)).
   It is the canonical Day-0 install path.
5. **Public-safe repo split stays as-is.** The 9-repo topology
   ([ADR-0001](0001-umbrella-as-docs-home.md), [ADR-0035](0035-operator-local-self-contained-envs.md))
   is frozen. **Do not** merge repos or move to submodules now — that's churn. Legibility
   is solved with a front door (public README + quickstart), not restructuring.
6. **Rebuild-only is the lifecycle model.** dmf-init rebuilds a blank node → full
   platform → restores a verified backup. **In-place upgrade (`main~N → main` skew
   convergence) is a non-goal for v0.1.** The keystone is not "prove in-place upgrade";
   it is **"cold bootstrap is deterministic and re-bootstrap is unblocked."**

## Explicit non-goals for v0.1

Naming these stops them from re-entering as "experiments":

- **Cross-cluster Authentik federation** (dmf-central). Reserved; a future ≤1-day spike,
  not a v0.1 lane. dmf-central stays scaffold + **frozen**.
- **Multi-node HA + cloud (Hetzner) as a release claim.** The lab env is reference, not
  a release target ([ADR-0031](0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md)).
- **Argo-for-k8s + AWX-glue hybrid actuator.** Do **not** build a hybrid framework to
  avoid choosing. AWX is the v0.1 actuator. Argo is a future spike, not a dependency.
  (This explicitly holds [ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md) §9
  and shelves the 2026-06-05 reversal plan.)
- **In-place upgrade mechanism.** Rebuild-only (see commitment 6).
- **dmf-media catalog-v2 roles** (ebu-list, flow-exporters, ptp-monitor,
  netbox-media-plugin). Frozen scaffold until v0.1 ships.
- **The drift-prevention meta-harness** (beyond the minimal safety net below).

## What v0.1 *adds* (the only in-scope work)

The credibility goal (D2) requires a **stranger-runnable artifact**. The minimal slice
that makes that real — and nothing more:

1. **Deterministic cold bootstrap** + a single **cold-bootstrap smoke gate** (the recurring
   first-boot-bug class is the #1 reproducibility risk).
2. **Fix the re-bootstrap blocker** — `seed-bao` `bundle_set` (root cause still unproven;
   it breaks re-bootstrap, so it breaks the quickstart).
3. **Catalog per-entry cross-action lock** — the double-launch TOCTOU + deploy↔finalise
   race are bugs a stranger driving the console *will* hit (needs one dmf-cms image build).
4. **Public-tag install path** — dmf-init quickstart resolves repos from public GitHub
   tags, not the LAN Forgejo `file://` path.
5. **Minimal CI only** — dmf-cms CI (the placeholder), a doc-link check, the cold-boot
   smoke gate. Stop there.
6. **The public front door** — one-page product thesis (who it's for, what a stranger
   validates in <1 hour) + quickstart, then publish the coherent v0.1 proof.

## The work-selection rule (changed)

Old rule (ADR-0004): *"choose work that produces falsifying evidence."*
New rule: **"choose work that makes the proven core runnable and legible to an outsider."**
If a task does not move v0.1 toward "a stranger clones, runs one command, gets DMF on a
blank node, deploys NMOS/MXL from the console, and inspects the receipts," it is out of
scope until v0.1 ships.

## Relationship to ADR-0004

ADR-0004 ("experiment phase, not hardening") was correct *until its own gate fired*. It is
now **superseded as the operating stance for the committed core** by this document. It
remains accurate history for how the experiment phase was run, and the thesis-killer frame
it introduced still describes the *reserved* experiments (federation, taxonomy-v2) that are
now explicit post-v0.1 non-goals. The April P0s ADR-0004 deferred (alerts, backups, token
rotation) become eligible work *after* v0.1 ships — they harden committed architecture, not
fluid experiments.

## Amending this document

Add a dated amendment block below. Reversing a commitment or promoting a non-goal into
scope is a deliberate decision with a one-line rationale — not a drift.
