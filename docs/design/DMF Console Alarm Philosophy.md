# DMF Console — Alarm Philosophy

**Status:** 🚧 Stub — to be written. Owns the procedural detail behind **[UX Constitution](DMF%20Console%20UX%20Constitution%202026-05-25.md) Art. 4** ("Alarms are classified, and have a lifecycle").
**Basis:** ISA-18.2 / EEMUA 191 / IEC 62682. (ISA-18.2 explicitly mandates an alarm philosophy document; this is it.)

## Why this doc exists
The constitution states the *principle* — conditions are classified by severity and required response, each with a lifecycle — and deliberately does **not** inline the taxonomy. That taxonomy lives here so the constitution stays principled.

## To define
- **Alarm classes / severity** — e.g. alarm · warning · advisory · notice · activity-outcome. Definition and threshold for each.
- **Required response per class** — not just "fixable": escalate, acknowledge, suppress-during-maintenance, watch-degradation, call-engineering.
- **Priority assignment** — how urgency × consequence maps to class.
- **Lifecycle states** — unacked → acked → shelved → suppressed-by-design → out-of-service → expiry; transitions and who may make them.
- **Presentation / annunciation** — colour + shape + text + position (ties Art. 11); placement; sound (if any); the "calm by default" budget.
- **Rationalisation criteria** — every alarm must be necessary, unique, actionable (EEMUA 191). Process for adding/removing one.
- **Suppression during maintenance** — how planned work silences expected conditions without blinding the operator to real ones.

## Open questions
- Source of truth for conditions (Prometheus/Alertmanager vs. platform events vs. job outcomes) and how they map to classes.
- Relationship between the current "Notifications" bell (Prometheus alerts) and operator-action outcomes — today they're conflated (see constitution §4 anti-patterns).
