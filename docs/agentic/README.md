# Agentic Harness

> **Mothballed 2026-06-04.** Preserved for provenance only; superseded by the
> GitHub Issues workflow. Do not treat `backlog.yaml`, `decisions-open.md`, or
> `issues.yaml` as live queues.

This directory contains the artifacts from the former agentic-harness system
(CONSTITUTION.md, loop-log, status files, etc.). They are no longer actively
used for task scheduling or agent coordination.

The canonical live-work system is now GitHub Issues + the umbrella repo's
Project board. See `docs/decisions/` for the decision that retired this
harness.

## What was removed / neutered (2026-07-13)

Mothballing on 2026-06-04 left two live edges that were closed on 2026-07-13:

- The invocable slash commands `.claude/commands/agentic-run.md` and
  `.claude/commands/agentic-tick.md` were **deleted**. They were still
  surfaced as runnable commands and could write handoffs, `backlog.yaml`,
  and `issues.yaml`. The narrative of how the loop worked survives in
  `docs/plans/DMF Agentic Harness Plan 2026-05-11.md` and the historical
  handoffs — this directory keeps the provenance without the trigger.
- Every retained script under `bin/agentic/` now **fails closed**: it exits
  non-zero with a `mothballed 2026-06-04` notice unless `DMF_AGENTIC_OVERRIDE=1`
  is set. This includes the former read-only helpers (`issue-list.sh`,
  `preflight.sh`), so nothing in the harness runs by accident. The scripts are
  kept for provenance, not use.
