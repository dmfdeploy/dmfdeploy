# DMF Agentic Harness — Decisions Open

> **⚠️ Status: HISTORICAL (mothballed 2026-06-04).** The harness loop that read
> this forward queue is retired. Live ADR-worthy decisions go to the operator
> directly; deferred work lives in [`TODOS.md`](../../TODOS.md). Preserved for
> provenance.

> **Audience**: Operator.
> **Authority**: Forward queue for ADR-worthy decisions surfaced by the
> agentic harness (worker `DECISION-NEEDED:` / `BLOCKED: needs-decision`
> tokens, or orchestrator self-classification per Constitution Rule 5).
>
> **How to answer**: Edit this file in-place. Replace the `Status: open`
> line with `Status: answered <YYYY-MM-DD> — <your-choice>`. Add a brief
> rationale under §"Operator note". The next `/agentic-tick` reads the
> answers and unblocks dependent backlog entries.
>
> **Distinct from**:
> - `autonomous-decisions.md` — retrospective log of non-ADR-worthy choices
>   the orchestrator already resolved. Operator does not need to act on
>   those — only audit.
> - `decisions-answered-history.md` — archive of past decisions that have
>   been answered **and** applied downstream. Moved out of this file once
>   their downstream work has landed, to keep the forward queue short. Full
>   audit trail preserved there.

---

## Current open queue

No current open decisions. The previous `grafana-local-admin-rename`
entry was answered and moved to
[`decisions-answered-history.md`](decisions-answered-history.md) on
2026-05-25.

The next `/agentic-tick`, worker `DECISION-NEEDED:` token, or orchestrator
self-classification will append further entries below.

---

## Future entries

The harness appends new entries here when:
- A worker emits `DECISION-NEEDED:` or `BLOCKED: needs-decision`, **or**
- The orchestrator self-classifies a choice as ADR-worthy per Constitution
  Rule 5 (a–e).

Entry shape (template): heading with kebab-case id, blockers list, question,
options with one marked **recommended default**, "Operator note" code block
with `Status: open`.

Once an entry is answered AND its downstream work has landed, move the full
entry (preserving all text + the `Applied` block) into
`decisions-answered-history.md`. The `/agentic-tick` reader skips anything
with `Status: answered`, so leaving it in place is also safe — moving is a
file-size hygiene step, not a correctness requirement.
