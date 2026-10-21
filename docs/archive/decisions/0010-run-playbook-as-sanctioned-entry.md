# ADR-0010 archive: `bin/run-playbook.sh` is the only sanctioned ansible entry point

This file holds material moved out of [ADR-0010](../../decisions/0010-run-playbook-as-sanctioned-entry.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Bare `ansible-playbook` with operators remembering to set env vars.** This
  is what we had; it failed. Rejected.
- **Ansible vault for secrets instead of OpenBao.** Adds a second secret-management
  system; OpenBao is already the canonical runtime store (ADR-0008). Rejected.
- **Wrap in Make / Just.** Adds a tool dependency. Bash works fine and is
  already on every operator's box.
