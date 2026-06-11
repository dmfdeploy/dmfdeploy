# bin/agentic/

> **Mothballed 2026-06-04.** Preserved for provenance only; superseded by the
> GitHub Issues workflow.

This directory contains the former agentic-harness scripts. All **mutating**
scripts (those that write repo files or call Forgejo/GitHub mutation APIs)
**fail closed** unless `DMF_AGENTIC_OVERRIDE=1` is set in the environment.

```bash
# To run a mothballed script (only if you know what you're doing):
DMF_AGENTIC_OVERRIDE=1 bin/agentic/issue-open.sh ...
```

Read-only scripts (`agent-status.sh`, `issue-list.sh`, `preflight.sh`) remain
usable without the override — they only gather and display information.

The `forgejo.env` file is an environment configuration file, not a script.
The `templates/` directory contains git hook templates that were installed
by `install-agentic-hooks.sh`.
