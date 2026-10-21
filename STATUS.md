# dmfdeploy status

This file points to current state. It is not a log. A check keeps it under 30
lines, and git history keeps the old entries.

## Where current state lives

| You want | Go to |
|---|---|
| What ships next | [ROADMAP.md](ROADMAP.md) |
| Scheduled work and the backlog | [Milestones](https://github.com/dmfdeploy/dmfdeploy/milestones) and [issues](https://github.com/dmfdeploy/dmfdeploy/issues) |
| Operator notes | Pinned issue [#618](https://github.com/dmfdeploy/dmfdeploy/issues/618) |
| Live repo state | Run `bin/generate-status.sh`, then read `STATUS.digest.local.md` |
| Decisions | [docs/decisions/](docs/decisions/INDEX.md) |
| Open questions | [docs/OPEN-QUESTIONS.md](docs/OPEN-QUESTIONS.md) |
| Architecture | [Architecture plan](docs/architecture/DMF%20Platform%20Plan.md) |

The generator writes `STATUS.local.md` and `STATUS.digest.local.md`. Both are
local and gitignored, so don't commit them.

## Operator notes

<!-- HUMAN-START -->
Committed operator notes live in the pinned issue
[#618](https://github.com/dmfdeploy/dmfdeploy/issues/618). Post new notes there,
not in this file.
<!-- HUMAN-END -->
