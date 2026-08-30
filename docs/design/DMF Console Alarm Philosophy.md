# DMF Console — Alarm Philosophy

**Status:** 🚧 Stub — to be written, except the Ack semantics and the bus self-monitoring cross-reference recorded below (2026-08-30). Owns the procedural detail behind **[UX Constitution](DMF%20Console%20UX%20Constitution%202026-05-25.md) Art. 4** ("Alarms are classified, and have a lifecycle").
**Basis:** ISA-18.2 / EEMUA 191 / IEC 62682. (ISA-18.2 explicitly mandates an alarm philosophy document; this is it.)

## Why this doc exists
The constitution states the *principle* — conditions are classified by severity and required response, each with a lifecycle — and deliberately does **not** inline the taxonomy. That taxonomy lives here so the constitution stays principled.

## Recorded so far (2026-08-30 — console shell round, top-bar alarm LED companion decision)

**Ack records "seen," it never dismisses.** An acknowledgment records **"seen
by `<actor>` at `<time>`"** and **never dismisses** the underlying condition —
presentation only, never truth. This is ISA-18.2's actual meaning of the word
"acknowledge": it tells other operators someone is aware, it does not make
the alarm go away. **The condition clears only when the condition clears**
(Constitution Art. 1 — the console never asserts an all-clear it has not
observed).

**Standing operator preference: Ack ships only alongside the full alarm
taxonomy above**, which remains an open stub. This round (the top-bar shell,
dmfdeploy/dmfdeploy#480) writes the rule down here and in the
[Shell Round Plan](../plans/DMF%20Console%20Shell%20Round%20Plan%202026-08-30.md)
§1c; it builds no ack UI and no lifecycle machinery. The new alarm LED itself
ships with **no actions this round** — clicking it only brings the relevant
alarm message(s) into focus in the message bus; there is no ack/resolve/
dismiss control to wire this rule into yet. The LED's own visual spec (form,
states, badges) is recorded separately at that plan's §1b.

**Not a dangerous action.** A recorded ack — who saw it, and when — needs
none of Constitution Art. 7's heavier consequence-class / impact-preview
treatment: it dismisses nothing and asserts nothing about the underlying
condition.

## Bus self-monitoring — cross-reference only (2026-08-30, #497)

The message bus's own liveness (whether the console's event pipeline — emit
→ Promtail → Loki → read — is actually flowing) is a **condition distinct
from workspace health**, and must never be inferred from the Prometheus
Watchdog, which proves only that *monitoring* is alive, not that the bus's
own pipeline is. A dead terminal-audit-event producer or a Promtail
misconfiguration leaves the Watchdog firing and the LED nominal while the
bus goes silently empty — the same "condition looks fine but isn't verified"
failure Art. 1 already forbids elsewhere.

Full design record — the two-tier (emitter-alive / end-to-end) heartbeat
model, the "a quiet bus is legitimately quiet" alarm-flood caution (EEMUA
191), and the fact that `dmf-cms` currently has **no monitoring exposition
at all** to build this on — lives in the
[Shell Round Plan](../plans/DMF%20Console%20Shell%20Round%20Plan%202026-08-30.md)
§2c, tracked by umbrella issue #497. Recorded here only as a pointer, so a
reader who lands on this doc's own "source of truth for conditions" open
question (below) does not miss that a whole new condition class is coming
that this doc will eventually need to classify.

## To define
- **Alarm classes / severity** — e.g. alarm · warning · advisory · notice · activity-outcome. Definition and threshold for each.
- **Required response per class** — not just "fixable": escalate, acknowledge, suppress-during-maintenance, watch-degradation, call-engineering.
- **Priority assignment** — how urgency × consequence maps to class.
- **Lifecycle states** — unacked → acked → shelved → suppressed-by-design → out-of-service → expiry; transitions and who may make them. (The "acked" transition's own semantics are recorded above; the rest of the lifecycle is still open.)
- **Presentation / annunciation** — colour + shape + text + position (ties Art. 11); placement; sound (if any); the "calm by default" budget.
- **Rationalisation criteria** — every alarm must be necessary, unique, actionable (EEMUA 191). Process for adding/removing one.
- **Suppression during maintenance** — how planned work silences expected conditions without blinding the operator to real ones.

## Open questions
- Source of truth for conditions (Prometheus/Alertmanager vs. platform events vs. job outcomes) and how they map to classes.
- Relationship between the current "Notifications" bell (Prometheus alerts) and operator-action outcomes — today they're conflated (see constitution §4 anti-patterns). **Partially addressed 2026-08-30:** the console shell round moves the Prometheus alert feed from the bell to a new alarm LED and rebuilds the bell as a human/approval inbox — see the [Shell Round Plan](../plans/DMF%20Console%20Shell%20Round%20Plan%202026-08-30.md) §1/§1a (semantics), §1b (visual spec), §1c (ack contract). Job/operation-outcome conflation (where dirty-facility state surfaces) remains unresolved — see that plan's "still open" note in §1a.
