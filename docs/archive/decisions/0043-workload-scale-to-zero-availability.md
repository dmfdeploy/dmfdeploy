# ADR-0043 archive: Workload scale-to-zero is an availability concern, scoped to AWX

This file holds material moved out of [ADR-0043](../../decisions/0043-workload-scale-to-zero-availability.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Name it a general "scale any workload to zero" primitive** (the plan's "reusable seam" read literally) — forward-looking, but an open invitation to build more bespoke wake/sleep helpers; rejected as sprawl-inviting and premature against the v0.1 freeze. The pattern is described, not generalized; reuse goes through a new ADR.
- **Build a general workload-elasticity actuator now** — over-engineering; conflates availability with elasticity; violates the freeze's non-goals.
- **Let AWX manage its own sleep** — circular: the controller must be running to act, so something out-of-band must own wake/sleep.
- **Node elasticity instead** — heavier and deferred; does not address the steady-state idle-RAM problem on a single node.
