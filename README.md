# dmfdeploy

[![CI](https://github.com/dmfdeploy/dmfdeploy/actions/workflows/ci.yml/badge.svg)](https://github.com/dmfdeploy/dmfdeploy/actions/workflows/ci.yml)

## What it is

dmfdeploy is an open prototype of a software-defined media facility. You
install it on one computer or virtual machine, and it gives you identity,
secrets custody, an inventory, monitoring, and an operator console. From the
console you deploy media functions, such as an NMOS registry, from a catalog.

It is for broadcast and media-tech engineers who want to learn how an IP-media
facility can be installed and operated, and for anyone who wants to study a
working prototype with its decisions on the record. It is not a production
facility. [docs/THESIS.md](docs/THESIS.md) says what has been shown, and a
recording of one deployment is on the [organization page](https://github.com/dmfdeploy).

The platform implements part of the [EBU](https://tech.ebu.ch/) *Dynamic Media
Facility* (DMF) reference architecture: layers 2, 3 and 6 (host platform,
container platform, and the operator console) and the Orchestration, Security
and Monitoring verticals. Layers 4 and 5 are thin so far: an NMOS registry and
a media-exchange demo. You provide the node, which is layer 1. See the
[EBU mapping](docs/architecture/DMF%20EBU%20Mapping%20%282026-04-25%29.md) and
the [glossary](docs/GLOSSARY.md).

<!-- Goal statement (short, mid and long term): dmfdeploy/dmfdeploy#675 -->

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

The [docs landing page](docs/README.md) maps the knowledge base,
[ROADMAP](ROADMAP.md) lists the milestones, and
[OPEN-QUESTIONS](docs/OPEN-QUESTIONS.md) lists what is frozen or unproven.

## How the parts fit together

This repository is the **umbrella**: the knowledge base, the decision record,
and the coordination point for the eight component repos. In the diagram,
boxes are component repos, rounded shapes are services they install, and an
arrow points from the caller to the part it calls.

```mermaid
flowchart LR
  init["dmf-init<br/>Day-0 installer"] -->|"runs playbooks through"| env["dmf-env<br/>env tooling"] -->|"runs"| infra["dmf-infra<br/>Ansible roles and playbooks"]
  infra -->|"installs"| cms["dmf-cms<br/>operator console"] & promsd["dmf-promsd<br/>service discovery"] & awx(["AWX"]) & netbox(["NetBox"]) & prom(["Prometheus"])
  infra -->|"copies the catalog from"| media["dmf-media<br/>catalog and charts"]
  infra -->|"registers projects in"| awx
  cms -->|"launches job templates"| awx
  cms -->|"reads workloads"| netbox
  awx -->|"runs playbooks from"| runbooks["dmf-runbooks<br/>workload playbooks"]
  runbooks -->|"deploys charts from"| media
  runbooks -->|"writes state to"| netbox
  promsd -->|"reads targets from"| netbox
  prom -->|"scrapes targets from"| promsd
  central["dmf-central<br/>scaffold, frozen for v0.1"]
```

`dmf-central` has no arrows because it is a scaffold, frozen for v0.1.

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

## Working model

ADRs ([docs/decisions/](docs/decisions/INDEX.md)) and plans
([docs/plans/](docs/plans/INDEX.md)) live in this repo. The
[issues](https://github.com/dmfdeploy/dmfdeploy/issues) are the backlog, and
[Discussions](https://github.com/dmfdeploy/dmfdeploy/discussions) hold RFCs.
The rules are in [docs/WORKING-MODEL.md](docs/WORKING-MODEL.md). AI agents
build much of the platform, by design ([the method](docs/JOURNEY.md#working-with-agents-the-method)).

## License

Apache License, Version 2.0. See [LICENSE](LICENSE).
Third-party components are listed in [NOTICE](NOTICE).
