# ADR-0007 archive: Secrets never in argv, env, /tmp, or AI transcripts

This file holds material moved out of [ADR-0007](../../decisions/0007-secrets-never-in-argv.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **"Use OpenBao for everything."** Necessary but not sufficient — once the
  secret is fetched, it still has to flow through some channel to where it's
  used; the rules are about *that* channel.
- **"Trust the operator."** Solo developer discipline is reliable; multi-agent
  collaboration is not, especially when one agent's transcript may be visible
  to humans/services the operator hasn't audited.
