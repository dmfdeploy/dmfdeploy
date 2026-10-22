# docs/ — knowledge-base map

The tree has three kinds of content. **Canonical** docs state current truth and
are maintained. **Synthesis** docs are curated entry points written for
newcomers. **Record** docs are the append-only lab notebook — point-in-time,
never rewritten, superseded in place with banners. Filenames are preserved
verbatim (docs cross-reference each other by display name).

## Synthesis — start here

| File | What it answers |
|---|---|
| [THESIS.md](THESIS.md) | What is this, who is it for, what can a stranger validate in an hour? |
| [JOURNEY.md](JOURNEY.md) | How did it get here — phases, pivots, and the method? |
| [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md) | What is frozen, unproven, broken, or undecided — honestly? |
| [decisions/INDEX.md](decisions/INDEX.md#start-here) | Which core ADRs to read, in what order? (★ Start here) |
| [CORRECTIONS.md](CORRECTIONS.md) | What has the project said in public that was wrong, and what is right? |
| [WORKING-MODEL.md](WORKING-MODEL.md) | How work is tracked — Issues/milestones/board/Discussions + documentation rules (canonical, enforced) |
| [STYLE.md](STYLE.md) | How should project prose read, and which Vale rules check it? |

## Directories

| Directory | Kind | One line |
|---|---|---|
| [architecture/](architecture/) | **Canonical** | Long-lived design docs — the [Platform Plan](architecture/DMF%20Platform%20Plan.md) and the [EBU vocabulary mapping](architecture/DMF%20EBU%20Mapping%20%282026-04-25%29.md) everything else uses. |
| [decisions/](decisions/INDEX.md) | **Canonical** | ADRs + [architectural-commitments-v1](decisions/architectural-commitments-v1.md); the [theme clusters](decisions/INDEX.md#theme-clusters--canonical-pointer) name the canonical ADR per topic. |
| [plans/](plans/INDEX.md) | Record (frontmatter-tracked) | Work plans and task specs; the generated [INDEX](plans/INDEX.md) groups them Active / Draft / Executed / Superseded / Historical. |
| [reviews/](reviews/) | Record | Point-in-time strategic and technical reviews; current assessment is the [2026-06-06 technical evaluation](reviews/dmf-platform-technical-evaluation.md). |
| [handoffs/](handoffs/) | Record | Append-only session handoffs — newest wins; never required reading to contribute. |
| [sessions/](sessions/) | Record | Operational session logs (rebuild notes, DR drill). |
| [references/](references/README.md) | Record | Third-party reference documents (with licence) plus a DMF summary-and-relevance note for each — inputs to parked topics, not decisions. |
| [questions/](archive/questions/) | Record | Raw open-question ledgers; the curated view is [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md). |
| [design/](design/) | **Canonical** | Operator-console UX constitution + alarm/danger/audit/glossary specs. |
| [runbooks/](runbooks/) | **Canonical** | Copy-pasteable operator runbooks. |
| [processes/](processes/) | **Canonical** | BPMN 2.0 process models. |
| [releases/](releases/) | Record | Release notes and publish artifacts. |
| [audits/](archive/audits/), [baselines/](archive/baselines/), [inventory/](archive/inventory/) | Record | Point-in-time audits, diffable baselines, inventory/boundary plans. |
| [archive/](archive/README.md) | Record (archived) | Executed, historical and superseded plans, audits, baselines, inventories, reviews, sessions and question ledgers, each at its original sub-path. |
| [agentic/](agentic/README.md) | Record (mothballed) | The retired agentic-harness state, preserved for provenance. |

## Generated indexes

- [plans/INDEX.md](plans/INDEX.md) — by `bin/generate-plans-index.sh` (frontmatter-driven)
- [SCRIPTS.md](SCRIPTS.md) — by `bin/generate-scripts-catalog.sh`
- `../STATUS.local.md` — by `bin/generate-status.sh` (local operator/agent dashboard, gitignored)
- [../STATUS.md](../STATUS.md) — pointer file; operator notes live in the pinned issue [#618](https://github.com/dmfdeploy/dmfdeploy/issues/618)

Live backlog: [GitHub Issues](https://github.com/dmfdeploy/dmfdeploy/issues) ·
[project board](https://github.com/orgs/dmfdeploy/projects/1) ·
[Discussions](https://github.com/dmfdeploy/dmfdeploy/discussions).
