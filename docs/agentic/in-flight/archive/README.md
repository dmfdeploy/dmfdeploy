# in-flight/archive: historical harness run-artifacts

These `*.json` files are **stale runtime task-state snapshots** from later
manual / agent-status use of the harness's `in-flight/` directory (the files are
dated **2026-05-24/25**, after the loop-log's last tick on 2026-05-12). The
harness is now mothballed. See [`../../CONSTITUTION.md`](../../CONSTITUTION.md)
and the "Agentic harness" section of the umbrella `CLAUDE.md`. On mothball (2026-06-04) they
were cleared here so the active `in-flight/` directory is empty.

They contain throwaway runtime detail (PIDs, `/tmp/dmf-playbook-logs/...` paths,
one stale `status: running`) and are **gitignored** (`*.json` here is excluded in
the umbrella `.gitignore`). Only this README is tracked. They are kept on disk
for local provenance and are not committed history. Safe to delete.
