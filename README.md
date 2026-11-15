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
It aims to earn trust by checking its claims against published specifications
with conformance tests, and by sharing what is learned upstream as evidence. It
also aims to be an independent implementation that others can compare against
those specifications. Any change of direction goes through a
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

Each repo is independent and sits beside this one under a common parent. Pick the repo by the kind of task. Each linked CONTRIBUTING.md has the exact versions, the test command and the checks that need a live environment.

| Repo | Work here when you change | Needs installed |
|---|---|---|
| [`dmfdeploy`](CONTRIBUTING.md) (this repo) | Docs, decisions, plans, agent skills and the repo-wide checks | Python 3, ShellCheck, `jq`, `ruby`, Vale |
| [`dmf-infra`](https://github.com/dmfdeploy/dmf-infra/blob/main/CONTRIBUTING.md) | Ansible roles and playbooks for layers 1–3 and the verticals | Ansible and the Python packages in its `requirements.txt` |
| [`dmf-env`](https://github.com/dmfdeploy/dmf-env/blob/main/CONTRIBUTING.md) | Environment tooling (wizard, wrappers, OpenTofu); env state stays operator-local (ADR-0035) | bash, Python 3, `jq`, `sops`, `age`, Go `yq` v4, OpenSSH, ShellCheck, OpenTofu |
| [`dmf-central`](https://github.com/dmfdeploy/dmf-central/blob/main/CONTRIBUTING.md) | Central services: a scaffold, **frozen** for v0.1 | Python 3, Ansible, `ansible-lint`, `yamllint` |
| [`dmf-media`](https://github.com/dmfdeploy/dmf-media/blob/main/CONTRIBUTING.md) | Media function catalog and charts for layers 4–5 (v2 roles frozen for v0.1) | Python 3, Helm, Ansible |
| [`dmf-runbooks`](https://github.com/dmfdeploy/dmf-runbooks/blob/main/CONTRIBUTING.md) | Playbooks that AWX launches to start, switch, and tear down workloads | Python 3, `ansible-core`; no cluster for the tests |
| [`dmf-cms`](https://github.com/dmfdeploy/dmf-cms/blob/main/CONTRIBUTING.md) | The operator console, with a React frontend and a FastAPI backend (layer 6) | Python 3, Node.js 22 |
| [`dmf-init`](https://github.com/dmfdeploy/dmf-init/blob/main/CONTRIBUTING.md) | The Day-0 installer container: blank node to full platform | Python 3, Node.js 22, `age`, `rclone`; Docker for the image |
| [`dmf-promsd`](https://github.com/dmfdeploy/dmf-promsd/blob/main/CONTRIBUTING.md) | NetBox-driven Prometheus service discovery (ADR-0038) | Python 3 |

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
