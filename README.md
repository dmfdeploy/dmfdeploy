# dmfdeploy

[![CI](https://github.com/dmfdeploy/dmfdeploy/actions/workflows/ci.yml/badge.svg)](https://github.com/dmfdeploy/dmfdeploy/actions/workflows/ci.yml)

dmfdeploy is an open prototype of the [EBU](https://tech.ebu.ch/) *Dynamic
Media Facility* (DMF) architecture on commodity infrastructure: k3s, Ansible,
NetBox, AWX, Authentik, OpenBao, and a React operator console. A Day-0
installer container turns a blank ARM64 node into a software-defined media
facility with identity, secrets custody, a source-of-truth inventory, and a
catalog of media functions to deploy. This repository is the **umbrella**: the
knowledge base, the decision record, and the coordination point for the eight
component repos.

<!-- Goal statement (short, mid and long term): dmfdeploy/dmfdeploy#675 -->

**Proven so far** (first-party, on the author's environments): the NMOS IS-04 and IS-05
services deploy and run on commodity ARM k3s, driven end to end through the platform's catalog
chain: console, AWX, Helm, and NetBox lifecycle state ([learnings, 2026-06-04](docs/reviews/dmf-platform-move-1-learnings.md)).
Whether an outsider can repeat that cold is the test of the current
[`v0.1-polish` milestone](https://github.com/dmfdeploy/dmfdeploy/milestone/1).
A workload switched by NMOS IS-05 from the console is [`v0.2`](https://github.com/dmfdeploy/dmfdeploy/milestone/2) work.
An 81-second recording of one workload being provisioned, with a plain account
of what it shows, is on the [organization page](https://github.com/dmfdeploy).

## Purpose

dmfdeploy stays an independent, open prototype of a Dynamic Media Facility.
It earns trust by proving its claims with conformance checks against
published specifications and by sharing what it learns upstream as evidence.
It does not call itself a reference; only a standards body can name one.
Any change of direction goes through a
[Discussions RFC](docs/decisions/README.md) first.

## Start here

| You are | Read, in order |
|---|---|
| **Evaluating** the platform | [docs/THESIS.md](docs/THESIS.md), then the [dmf-init quickstart](https://github.com/dmfdeploy/dmf-init) (Day-0 installer) |
| **A potential contributor** | [CONTRIBUTING.md](CONTRIBUTING.md), the [core ADRs](docs/decisions/INDEX.md#start-here), then the [issues](https://github.com/dmfdeploy/dmfdeploy/issues) |
| **An AI-agent operator** working on the platform | [AGENTS.md](AGENTS.md) and its boot steps |

The [docs landing page](docs/README.md) maps the knowledge base, and
[OPEN-QUESTIONS](docs/OPEN-QUESTIONS.md) lists what is frozen or unproven.

## Component repos

Each is an independent git repo under the [dmfdeploy org](https://github.com/dmfdeploy),
checked out as a sibling directory of this umbrella under a common parent:

| Repo | EBU layer / vertical | Stack | Status |
|---|---|---|---|
| [`dmf-infra`](https://github.com/dmfdeploy/dmf-infra) | Layers 1–3 + verticals (Security, Monitoring, Orchestration, Control) | Ansible + Helm | **Active**: generic playbooks/roles, the bootstrap engine |
| [`dmf-env`](https://github.com/dmfdeploy/dmf-env) | Layer 1 + generic env tooling | Terraform (OpenTofu) + Ansible vars | **Active**: generic; per-env state is operator-local (ADR-0035) |
| [`dmf-central`](https://github.com/dmfdeploy/dmf-central) | Deploy-once central services | Ansible (stub) | Scaffold: **frozen** for v0.1 (federation is a named non-goal) |
| [`dmf-media`](https://github.com/dmfdeploy/dmf-media) | Layers 4–5 (Media Exchange + Functions) | Ansible + Helm | **Active**: catalog metadata; v2 media roles frozen for v0.1 |
| [`dmf-runbooks`](https://github.com/dmfdeploy/dmf-runbooks) | Layers 4–5 execution | Ansible (AWX launchers) | **Active**: thin AWX launchers + authoritative `nmos-cpp` role |
| [`dmf-cms`](https://github.com/dmfdeploy/dmf-cms) | Layer 6 (Application & UI) | React + TypeScript / FastAPI / OIDC | **Active**: the operator console |
| [`dmf-init`](https://github.com/dmfdeploy/dmf-init) | Day-0 bootstrap | React + FastAPI container | **Active**: the installer: blank node → full platform |
| [`dmf-promsd`](https://github.com/dmfdeploy/dmf-promsd) | Monitoring vertical | Python | **Active**: NetBox-driven Prometheus service discovery (ADR-0038) |

Canonical architecture: [`docs/architecture/dmfdeploy-platform-plan.md`](docs/architecture/dmfdeploy-platform-plan.md).
Canonical vocabulary (layers/verticals/lifecycle): [`docs/architecture/DMF EBU Mapping (2026-04-25).md`](docs/architecture/DMF%20EBU%20Mapping%20%282026-04-25%29.md).

## Where it is going

[ROADMAP.md](ROADMAP.md) describes three milestones, each defined by an outcome:

- [`v0.1-polish`](https://github.com/dmfdeploy/dmfdeploy/milestone/1): the
  console tells the truth. An outsider completes the documented journey cold.
- [`v0.2`](https://github.com/dmfdeploy/dmfdeploy/milestone/2): a team shares
  one console to run a multi-function workload switched by NMOS IS-05.
- [`v0.3`](https://github.com/dmfdeploy/dmfdeploy/milestone/4): a team designs
  and plans a workload and a facility in the console.

[architectural-commitments-v1](docs/decisions/architectural-commitments-v1.md)
fixes the v0.1 architecture and its non-goals; [JOURNEY](docs/JOURNEY.md) tells the history.

## Working model

The record lives in this repo: ADRs in [docs/decisions/](docs/decisions/INDEX.md)
and plans in [docs/plans/](docs/plans/INDEX.md). Liveness lives on GitHub:
[issues](https://github.com/dmfdeploy/dmfdeploy/issues) are the backlog,
milestones schedule them, and
[Discussions](https://github.com/dmfdeploy/dmfdeploy/discussions) hold
questions and RFCs. The rules are in [docs/WORKING-MODEL.md](docs/WORKING-MODEL.md).
AI agents under operator orchestration build much of the platform, by design
([the method](docs/JOURNEY.md#working-with-agents-the-method)).

## Provenance

The knowledge base moved here from an operator-local note store on 2026-05-03,
with filenames kept verbatim because docs cite each other by name. It is
published with its full record, pivots and mothballed tooling included,
because the record is part of the method. Identity and topology details use
placeholders such as `dmf.example.com`.

## License

Apache License, Version 2.0. See [LICENSE](LICENSE).
Third-party components are listed in [NOTICE](NOTICE).
