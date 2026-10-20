# Roadmap

dmfdeploy is an open prototype of a Dynamic Media Facility. Work is scheduled
in three GitHub milestones. Each milestone is defined by an outcome, not a
list of features, and an issue belongs to a milestone only if the outcome
fails without it. Everything else carries the `platform-debt` label and no
milestone. There are no dates.

## v0.1-polish — the console tells the truth

An outsider completes the documented journey cold, nothing on the way tells
them something untrue, and the public repos are safe to read and clone.
Defects on that path, security and authorization fixes, and the UI
truthfulness work live here.

## v0.2 — a team shares one console

A usable workload of several media functions, switched by NMOS IS-05, operated
by a small team in one console, where a deploy never blocks the facility.
This means: role-based gating in the console, user management from the
console, per-workload operation scoping, a decided packaging format for media
functions with the existing charts conforming to it, and NMOS registration of
MXL flows so that switching is real.

Episode 001 declared the IS-05 gap on camera. The team scope is a maintainer
decision (2026-10-20) added beyond the declared limits.

## v0.3 — design and plan in the console

A team designs a workload and a facility in the console and plans them before
anything is provisioned. Episode 001 declared both stages as placeholders.
This milestone names where a design record lives, what Plan binds to, the
facility lifecycle, and self-enrolment.

## Not planned

Federation, high-availability and cloud claims, a hybrid GitOps actuator,
in-place upgrade, and media-v2 are explicit non-goals of the v0.1
architecture ([decisions/architectural-commitments-v1.md](docs/decisions/architectural-commitments-v1.md)).
Reopening one needs a dated amendment there first.

## Where to look

- Live backlog: [issues](https://github.com/dmfdeploy/dmfdeploy/issues), by milestone.
- Decisions: [docs/decisions](docs/decisions/INDEX.md).
- Open questions and frozen claims: [docs/OPEN-QUESTIONS.md](docs/OPEN-QUESTIONS.md).
- The demo: episode 001 on YouTube (linked from the README).
