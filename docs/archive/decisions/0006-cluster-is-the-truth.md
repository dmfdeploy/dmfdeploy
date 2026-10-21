# ADR-0006 archive: The cluster is the truth, not local kubectl

This file holds material moved out of [ADR-0006](../../decisions/0006-cluster-is-the-truth.md) when the ADRs were cut to a short shape. The text is unchanged apart from headings and relative link paths. The ADR is the binding record; this file is history and is not maintained.

## Alternatives considered

- **Trust local kubectl but verify before each session.** Adds a verification
  step that's easy to skip. The mistakes happen on routine operations, not on
  ceremonial ones.
- **Distribute the kubeconfig to each operator's machine.** Each copy is a
  full cluster-admin cert; each is an attack surface. Centralizing on the
  control node minimizes copies of high-value credentials.
