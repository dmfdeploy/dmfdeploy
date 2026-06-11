# ADR-0010: `bin/run-playbook.sh` is the only sanctioned ansible entry point

**Status:** Accepted
**Date:** 2026-04-22 (formalized in rebuild session)
**Deciders:** @<handle>

## Context

Ansible playbook runs need consistent context: the right inventory, OpenBao
secrets exported as `vault_*` vars, an `ansible.cfg` resolved from the playbook's
directory, a runtime cap to prevent stuck runs, and a logged transcript for
post-mortem. Operators and agents alike historically invoked `ansible-playbook`
directly, missing one or more of these and producing unreproducible runs or
stuck processes that nobody knew about.

## Decision

`dmf-env/bin/run-playbook.sh` is the **only sanctioned** way to run an
ansible playbook against a DMF environment. Direct `ansible-playbook`
invocation is forbidden in scripts, skills, and agent workflows.

The wrapper:
- Resolves environment from arg 1 (default: `hetzner-arm`)
- Auto-discovers `ansible.cfg` walking up from the playbook path
- Authenticates to OpenBao via AppRole, fetches the kv-v2 vars document, and
  writes a temp file at `/tmp/openbao-vars-${ENV}.XXXXXX` (mktemp + cleanup trap)
- Injects the temp file with `-e @file`
- Logs every run to `/tmp/dmf-playbook-logs/<name>-<timestamp>.log`
- Enforces a runtime cap: 15 min (ordinary playbook), 30 min (`lifecycle-*.yml`),
  90 min (`site.yml`), overridable with `RUNBOOK_TIMEOUT=<seconds>`

A companion `bin/monitor-playbook.sh <log>` streams filtered output
(`PLAY/TASK/fatal/FAILED/PLAY RECAP`) for long runs.

## Consequences

- **Positive:** every playbook run has a known starting context, a log file,
  and a deadline. Stuck runs auto-terminate.
- **Positive:** secrets resolution is centralized — playbook authors don't
  worry about OpenBao auth, just reference `vault_<key>` after `-e @file` is
  injected.
- **Positive:** monitoring pattern is reusable across runs (run in terminal A,
  monitor in terminal B).
- **Negative:** wrapper is a load-bearing piece of infrastructure. When it
  breaks (heredoc quoting, BSD vs GNU mktemp, cleanup trap on signal),
  every run breaks.
- **Negative:** `/tmp/openbao-vars-*` files are sensitive while they exist —
  see ADR-0007 §5 for sweep procedure. Trap cleanup handles the happy path
  but not Ctrl-C in some edge cases.

## Alternatives considered

- **Bare `ansible-playbook` with operators remembering to set env vars.** This
  is what we had; it failed. Rejected.
- **Ansible vault for secrets instead of OpenBao.** Adds a second secret-management
  system; OpenBao is already the canonical runtime store (ADR-0008). Rejected.
- **Wrap in Make / Just.** Adds a tool dependency. Bash works fine and is
  already on every operator's box.

## Enforcement

`dmf-infra/CLAUDE.md` and `dmf-env/CLAUDE.md` both reference the
wrapper as the entry point. `dmf-cluster-access` skill §4.1 states the
"golden rule." The wrapper itself prints usage if mis-invoked. No automated
rejection of bare `ansible-playbook` calls — discipline + skill references
only.
