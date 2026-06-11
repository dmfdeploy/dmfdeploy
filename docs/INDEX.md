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
| [decisions/READING-GUIDE.md](decisions/READING-GUIDE.md) | Which ~8 ADRs to read, in what order? |
| [WORKING-MODEL.md](WORKING-MODEL.md) | How work is tracked — Issues/milestones/board/Discussions + documentation rules (canonical, enforced) |

## Directories

| Directory | Kind | One line |
|---|---|---|
| [architecture/](architecture/) | **Canonical** | Long-lived design docs — the [Platform Plan](architecture/DMF%20Platform%20Plan.md) and the [EBU vocabulary mapping](architecture/DMF%20EBU%20Mapping%20%282026-04-25%29.md) everything else uses. |
| [decisions/](decisions/INDEX.md) | **Canonical** | ADRs + [architectural-commitments-v1](decisions/architectural-commitments-v1.md); [digests/](decisions/digests/) consolidate current truth per topic cluster. |
| [plans/](plans/INDEX.md) | Record (frontmatter-tracked) | Work plans and task specs; the generated [INDEX](plans/INDEX.md) groups them Active / Draft / Executed / Superseded / Historical. |
| [reviews/](reviews/) | Record | Point-in-time strategic and technical reviews; current assessment is the [2026-06-06 technical evaluation](reviews/dmf-platform-technical-evaluation-2026-06-06.md). |
| [handoffs/](handoffs/) | Record | Append-only session handoffs — newest wins; never required reading to contribute. |
| [sessions/](sessions/) | Record | Operational session logs (rebuild notes, DR drill). |
| [questions/](questions/) | Record | Raw open-question ledgers; the curated view is [OPEN-QUESTIONS.md](OPEN-QUESTIONS.md). |
| [design/](design/) | **Canonical** | Operator-console UX constitution + alarm/danger/audit/glossary specs. |
| [runbooks/](runbooks/) | **Canonical** | Copy-pasteable operator runbooks. |
| [processes/](processes/) | **Canonical** | BPMN 2.0 process models. |
| [releases/](releases/) | Record | Release notes and publish artifacts. |
| [audits/](audits/), [baselines/](baselines/), [inventory/](inventory/) | Record | Point-in-time audits, diffable baselines, inventory/boundary plans. |
| [agentic/](agentic/README.md) | Record (mothballed) | The retired agentic-harness state, preserved for provenance. |

## Generated indexes

- [plans/INDEX.md](plans/INDEX.md) — by `bin/generate-plans-index.sh` (frontmatter-driven)
- [SCRIPTS.md](SCRIPTS.md) — by `bin/generate-scripts-catalog.sh`
- [../STATUS.md](../STATUS.md) — by `bin/generate-status.sh` (operator/agent dashboard)

Live backlog: [GitHub Issues](https://github.com/dmfdeploy/dmfdeploy/issues) ·
[project board](https://github.com/orgs/dmfdeploy/projects/1) ·
[Discussions](https://github.com/dmfdeploy/dmfdeploy/discussions).
