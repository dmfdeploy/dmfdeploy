# ADR-0004: Experiment phase, not hardening

> **⚠️ Canonical truth for this topic is consolidated in the
> [Deployment scope and release digest](digests/deployment-scope-and-release.md).** This ADR's status: stance superseded for the committed core by `architectural-commitments-v1` (2026-06-04).
> Full text preserved below for decision history — do not act on it without
> reading the digest + the named successor.

**Status:** Accepted — **stance superseded for the committed core by
[architectural-commitments-v1](architectural-commitments-v1.md)** (2026-06-06). The
commit gate this ADR implied fired on 2026-06-04 (Move 1 + Move 2 closed); the project
has committed v0.1. This ADR remains accurate history + still describes the *reserved*
post-v0.1 experiments (federation, taxonomy-v2).
**Date:** 2026-04-30 (strategic review)
**Deciders:** @<handle>

## Context

The platform has a working lab cluster, deployable apps, monitoring, secrets,
and an emerging operator console. The natural pull from there is "harden it" —
add alerts, backups, token rotation, polish the UI. That pull is wrong for
where the project actually is. Several architectural assumptions remain
**untested**: NMOS IS-04/05 + EBU LIST 2110 on commodity k3s (Layer 4–5),
Authentik cross-cluster federation, and whether the EBU V2.0 taxonomy survives
a hard case. Hardening before testing those locks in commitments to a design
that may not survive contact with reality.

## Decision

The platform is in **experiment phase**. The right metric is *"what
irreversible architectural decisions am I de-risking before I commit?"* — not
*"is the system hardened?"* Three thesis-killer risks dominate, in priority
order:

1. **NMOS IS-04/05 + EBU LIST 2110 on commodity k3s** — `dmf-media/` is empty.
2. **Authentik cross-cluster federation with passkey enrollment** — single-cluster
   works; federation untested. Hinges on `dmf-central/` standing up.
3. **EBU V2.0 layer/vertical/lifecycle taxonomy survives a hard case** — every
   existing playbook fits because it was written with the taxonomy in mind.

Hardening work (alerts, backups, token rotation, polish) is **deferred** until
at least one thesis-killer is resolved.

## Consequences

- **Positive:** clear filter on incoming work. "Does this de-risk an irreversible
  decision?" If no, defer. Spends limited time on the right experiments.
- **Positive:** explicit permission to ship rough demos for thesis-killer tests.
  Move 2 (`docs/plans/dmf-platform-move-2-task-2026-04-30.md`) is the active
  example — it tests the SoT data model with one ugly UI and one workflow
  wired end-to-end, no polish.
- **Negative:** soft lock-in still accumulates (dashboards, runbooks, scripts).
  Each hardening-adjacent thing built creates pressure to keep it, even when
  the underlying architecture changes. Continuous vigilance required.
- **Negative:** an outsider visiting the repo today sees gaps that look like
  oversights but are deliberate. Strategic review and this ADR are the
  explanation; new agents/collaborators must read them.

## Alternatives considered

- **Mode A (harden now, experiment later).** Was the implicit default until the
  2026-04-30 strategic review. Reframed: hardening adds soft lock-in and
  doesn't test the thesis. Retracted.
- **Mode B (parallel hardening + experimentation).** Half-effort on each, neither
  ships. Solo-developer constraint makes serial focus the better bet.

## Enforcement

`dmfdeploy/docs/reviews/dmf-platform-strategic-review-2026-04-30.md` is the
authoritative reframe. New work proposed by agents should reference whether
it advances a thesis-killer or is hardening. STATUS.md (auto-generated) lists
in-flight work; agents flag hardening work that isn't supporting an active
thesis-killer experiment.
