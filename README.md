# dmfdeploy

**DMF Platform** — an open prototype of the [EBU](https://tech.ebu.ch/)
*Dynamic Media Facility* Reference Architecture V2.0 on commodity
infrastructure: k3s, Ansible, NetBox,
AWX, Authentik, OpenBao, and a React operator console. A blank ARM64 node
becomes a software-defined media facility — identity, secrets custody,
source-of-truth inventory, and a deployable media-function catalog — driven by a
Day-0 installer container. This repository is the **umbrella**: the consolidated
knowledge base, decision record, and cross-repo coordination point for the
eight component repos.

**Proven so far** (first-party, on the author's environments): NMOS IS-04/05
deploys and runs on commodity ARM k3s, driven end-to-end through the platform's
catalog control chain (console → AWX → Helm → NetBox lifecycle state) — closed
2026-06-04 as "Move 1", the NMOS spike
([learnings](docs/reviews/dmf-platform-move-1-learnings-2026-06-04.md)). The
larger claim — that a *stranger* can reproduce this — is exactly what v0.1 is
closing: see the [thesis one-pager](docs/THESIS.md).

## Start here — pick your path

| You are… | Read, in order |
|---|---|
| **Curious / evaluating** — "what is this and does it work?" | [docs/THESIS.md](docs/THESIS.md) → the [dmf-init quickstart](https://github.com/dmfdeploy/dmf-init) (Day-0 installer) |
| **A potential contributor** | [docs/JOURNEY.md](docs/JOURNEY.md) (how we got here) → [ADR reading guide](docs/decisions/READING-GUIDE.md) → [CONTRIBUTING.md](CONTRIBUTING.md) → [Issues](https://github.com/dmfdeploy/dmfdeploy/issues) + [project board](https://github.com/orgs/dmfdeploy/projects/1) |
| **An AI-agent operator** — working *on* the platform with agents | [CLAUDE.md](CLAUDE.md) / [AGENTS.md](AGENTS.md) boot ritual, then [STATUS.md](STATUS.md) |

The knowledge base is mapped in [docs/INDEX.md](docs/INDEX.md). What's
deliberately frozen, unproven, or undecided is curated honestly in
[docs/OPEN-QUESTIONS.md](docs/OPEN-QUESTIONS.md).

## Component repos

Each is an independent git repo under the [dmfdeploy org](https://github.com/dmfdeploy),
checked out as a sibling directory of this umbrella under a common parent:

| Repo | EBU layer / vertical | Stack | Status |
|---|---|---|---|
| [`dmf-infra`](https://github.com/dmfdeploy/dmf-infra) | Layers 1–3 + verticals (Security, Monitoring, Orchestration, Control) | Ansible + Helm | **Active** — generic playbooks/roles, the bootstrap engine |
| [`dmf-env`](https://github.com/dmfdeploy/dmf-env) | Layer 1 + generic env tooling | Terraform (OpenTofu) + Ansible vars | **Active** — generic; per-env state is operator-local (ADR-0035) |
| [`dmf-central`](https://github.com/dmfdeploy/dmf-central) | Deploy-once central services | Ansible (stub) | Scaffold — **frozen** for v0.1 (federation is a named non-goal) |
| [`dmf-media`](https://github.com/dmfdeploy/dmf-media) | Layers 4–5 (Media Exchange + Functions) | Ansible + Helm | **Active** — catalog metadata; v2 media roles frozen for v0.1 |
| [`dmf-runbooks`](https://github.com/dmfdeploy/dmf-runbooks) | Layers 4–5 execution | Ansible (AWX launchers) | **Active** — thin AWX launchers + authoritative `nmos-cpp` role |
| [`dmf-cms`](https://github.com/dmfdeploy/dmf-cms) | Layer 6 (Application & UI) | React + TypeScript / FastAPI / OIDC | **Active** — the operator console |
| [`dmf-init`](https://github.com/dmfdeploy/dmf-init) | Day-0 bootstrap | React + FastAPI container | **Active** — the installer: blank node → full platform |
| [`dmf-promsd`](https://github.com/dmfdeploy/dmf-promsd) | Monitoring vertical | Python | **Active** — NetBox-driven Prometheus service discovery (ADR-0038) |

Canonical architecture: [`docs/architecture/DMF Platform Plan.md`](docs/architecture/DMF%20Platform%20Plan.md).
Canonical vocabulary (layers/verticals/lifecycle): [`docs/architecture/DMF EBU Mapping (2026-04-25).md`](docs/architecture/DMF%20EBU%20Mapping%20%282026-04-25%29.md).

## Current phase: v0.1 committed

The experiment phase **closed on 2026-06-06** —
[architectural-commitments-v1](docs/decisions/architectural-commitments-v1.md)
froze the v0.1 architecture (single-node proof surface, AWX as catalog actuator,
NetBox tags as lifecycle state, dmf-init as installer, rebuild-only lifecycle)
and named the explicit non-goals. The work-selection rule is now: **make the
proven core runnable and legible to an outsider** — the active plan is the
[v0.1 commitment & focus-cut plan](docs/plans/DMF%20v0.1%20Commitment%20%26%2030-Day%20Focus-Cut%20Plan%202026-06-06.md).

Thesis scorecard from the experiment phase:

1. **NMOS IS-04/05 on commodity k3s** — ✅ confirmed (Move 1, 2026-06-04)
2. **Cross-cluster Authentik federation** — ❄️ frozen (never started; post-v0.1 spike)
3. **EBU taxonomy under a two-function hard case** — ⏸ paused (the MXL — Media eXchange Layer — spike; code-complete, live verification paused)

The full story — including the pivots and the mothballed machinery — is in
[docs/JOURNEY.md](docs/JOURNEY.md).

## Working model

- **The record lives in this repo** — ADRs ([docs/decisions/](docs/decisions/INDEX.md)),
  plans ([docs/plans/](docs/plans/INDEX.md)), reviews, handoffs.
- **Liveness lives on GitHub** — [Issues](https://github.com/dmfdeploy/dmfdeploy/issues)
  are the backlog, the [org project board](https://github.com/orgs/dmfdeploy/projects/1)
  carries scheduling, and [Discussions](https://github.com/dmfdeploy/dmfdeploy/discussions)
  host Q&A and the RFC-before-ADR pipeline (see [CONTRIBUTING.md](CONTRIBUTING.md)).
- Much of the platform is built by AI agents under operator orchestration — by
  design, and documented as method in
  [JOURNEY.md](docs/JOURNEY.md#working-with-agents-the-method).

## Provenance

The knowledge base was consolidated on 2026-05-03 from an operator-local note
store; document filenames are preserved verbatim because docs cross-reference
each other by display name. The repo is published with its full record —
pivots, superseded plans, and mothballed tooling included — because the record
is part of the method. Identity and topology details are placeholder-scrubbed
(`<control-node-public-ip>`, `dmf.example.com`, `<handle>`); concrete values
never lived in public repos.

## License

Apache License, Version 2.0 — see [LICENSE](LICENSE).
Third-party components are listed in [NOTICE](NOTICE).
