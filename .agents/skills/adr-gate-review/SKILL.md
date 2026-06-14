---
name: adr-gate-review
description: Review ADRs that gate downstream implementation work — verify schema unambiguity, cross-links, and that downstream agents need zero further design input
source: auto-skill
extracted_at: '2026-06-04T09:30:00Z'
---

# ADR Gate Review

A read-only review of an Architecture Decision Record (ADR) that gates downstream implementation work. The goal is to ensure the ADR is unambiguous enough that agents implementing downstream work packages need **zero further design input** — architectural correctness alone is not sufficient.

## When to use

- An ADR has been committed and gates downstream work (e.g. WP0 gates WP1–WP11).
- Another agent asks for ADR review before downstream agents start coding.
- You want to verify that an ADR's schema/contract is precise enough for implementers.

**Read-only.** Do not edit the ADR. Produce a verdict + prioritized findings.

## Procedure

### 1. Ground yourself

Read these in order:
1. **The ADR under review** — read top-to-bottom.
2. **The plan/spec** the ADR implements — cross-check that all "DECIDED" items in the plan are reflected in the ADR.
3. **The INDEX.md** — verify the row is added, theme cluster updated if applicable.
4. **Referenced ADRs** — the ones in the Touches/Cross-references header. Check for reciprocal links.

### 2. Judge against the four minimum criteria

An ADR that gates downstream implementation work must specify these four elements at minimum (or flag as blocking):

| # | Criterion | Why it blocks | Example |
|---|---|---|---|
| 1 | **Timing/cadence** — If the ADR involves polling, caching, or refresh intervals, it must state actual values (e.g. `refresh_interval: 30s`, cache TTL `45s`) and worst-case latency. | Without this, implementers pick arbitrary values that may be wrong. | Adapter cache cadence: Prometheus polls at 30s, adapter cache refreshes at ~45s, worst-case churn ≈75s. |
| 2 | **Field types and choice sets** — Custom fields need types (integer, string, choice-set) and valid value enumerations. | Naming fields without types leaves WP1 agents guessing about NetBox API calls. | `metrics_port` = integer; `probe_module` = text constrained by `dmf_blackbox_probe_modules` choice set with values enumerated. |
| 3 | **Address composition** — For any SD/adapter that emits `__address__`, the source must be explicit per lane. | Without this, the adapter emits wrong addresses and Prometheus can't reach targets. | Scrape: `primary_ip4.address:metrics_port`; Probe: real target; SNMP: `device primary_ip4.address`. |
| 4 | **Relabeling contracts** — For probe/blackbox indirection, the relabeling pattern must be specified. | Without this, upstream adapters emit wrong labels and downstream wiring fails. | Probe: `__param_target ← __address__`, `__address__ ← blackbox service addr`, `instance ← original target`. |

If any of these four is missing, flag it as **P1 (blocking)** — downstream agents cannot proceed without design clarification.

### 3. Check additional dimensions

Beyond the four minimum criteria, evaluate:

| Dimension | What to check |
|---|---|
| **Fidelity to plan** | All "DECIDED" items from the plan are in the ADR. Rejected alternatives are named. Superseded approaches are explicitly superseded. |
| **Operator decisions** | All resolved operator decisions from the plan are captured (not just one of three). Scaling paths and upgrade triggers are recorded if the plan resolved them. |
| **Downstream permission notes** | If the plan resolved a permission question (e.g. "no catalog-svc extension expected"), the ADR should capture it so WP agents don't re-litigate. |
| **ADR format** | Status line, Deciders, Date, Context/Decision/Consequences/Alternatives sections present. |
| **Cross-links** | All ADRs referenced in the plan's "Canonical doctrine" are in the Touches header. Reciprocal back-links exist where appropriate (e.g. ADR-0013 should mention ADR-0038 if the monitoring contract extends the catalog model). |
| **IP/DNS hygiene** | No IPs, internal DNS names, or environment-specific values in the ADR. Only variable references and example domains. |
| **Schema completeness** | If the ADR defines a schema, every field in the schema has a type, default, and activation condition. Round-trip mapping (catalog → storage → output) is explicit. |

### 4. Prioritize findings

| Priority | Meaning | Example |
|---|---|---|
| **P1** | One of the four minimum criteria is missing, or a downstream agent will hit a design question before they can code. | Cache cadence absent; custom field types unspecified; __address__ composition missing. |
| **P2** | Significant gap that doesn't block the first downstream agent but will cause rework or ambiguity later. | exposure:* tag taxonomy undocumented; round-trip mapping implicit. |
| **P3** | Format/hygiene issue — helpful but not blocking. | Missing reciprocal cross-link; ADR-0010 not in cross-refs. |

### 5. Produce the review

Structure the reply as:

```
VERDICT: PASS / CHANGES-NEEDED

=== P1 (blocking) ===
GAP N — <criterion name> — <what's missing, which WP agent is blocked, what spec is needed>

=== P2 (significant, non-blocking) ===
...

=== P3 (format/hygiene) ===
...

=== Summary ===
Core architecture decisions [are/are not] faithfully captured. The [N] P1 gaps must be closed before WP1 starts. The rest can be resolved during implementation.
```

### 6. Re-review after amend

When the ADR is amended, re-read the full file (not just the diff) and verify each previously-flagged P1 gap is **actually closed** — not just mentioned, but specified with enough precision that the named downstream agent can code without guessing.

## Principles

- **Architectural correctness ≠ implementer readiness.** An ADR can be architecturally sound but underspecified for the agents who will implement it.
- **The four minimum criteria are non-negotiable.** If any is missing, the ADR is not ready for downstream work.
- **Verify, don't trust.** On re-review, read the full amended ADR — don't assume the diff closes the gap correctly.
- **Name the blocked agent.** Each P1 should say which WP (WP1, WP3, WP6, etc.) is blocked and what spec they're missing.
- **Read-only.** You are critiquing, not editing. The ADR owner folds the findings.
