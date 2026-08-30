---
status: active
date: 2026-08-30
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/480
---
# DMF Console Shell Round Plan (2026-08-30)

> **STATUS: ACTIVE — Phase 0 (docs) of the console shell round.** This plan is
> the design record for the console's **top-bar shell**: the message bus, the
> alarm LED, the top-bar layout, and the storage architecture underneath the
> bus. It tracks dmfdeploy/dmfdeploy#480 (top bar → message bus) — **#480
> itself lists the audit/event log as out of its scope; the storage-architecture
> content in §2a/§2b is tracked separately by umbrella issue #496, and the
> bus's own liveness/heartbeat (§2c) by umbrella issue #497.** Frontmatter
> `tracking_issue` stays #480 because the bus is this plan's primary subject.
> It touches
> dmfdeploy/dmfdeploy#481 only at the layout seam (the rail moving into its own
> band below the bar) — the rail's own visual system (colour, shape, icons) is
> specified separately in
> [DMF Console Lifecycle Rail Visual System](../design/DMF%20Console%20Lifecycle%20Rail%20Visual%20System.md),
> which governs #481/#482/#483. The lifecycle-stage model (peer views, not a
> gated sequence) is specified in the
> [Information Architecture](../design/DMF%20Console%20Information%20Architecture%202026-06-23.md)'s
> 2026-08-30 (#493) amendment. **Phase 1 (the throbber) is a companion arc**
> that runs in parallel in dmf-runbooks/dmf-cms — its primary, in-stage form
> (Placement 1, §3) depends on none of this plan's decisions; its secondary,
> bus-surfaced form (Placement 2, §3) is **not** independent — it depends on
> this plan's bus existing and on #436. §3 below cross-references the whole
> arc rather than duplicating its mechanism spec. Where this plan and the
> [Console UX Constitution](../design/DMF%20Console%20UX%20Constitution%202026-05-25.md)
> disagree, the Constitution wins.

## 0. Why

Operator design session, 2026-08-30, following an external walkthrough on
2026-08-25 (operator-local; not reproduced here beyond the two lines below).

Two quotable signals from that walkthrough:

- The tester, watching an in-flight provision: *"automation is running. You
  need a throbber."*
- Their reasoning, which matters more than the ask: waiting feels longer
  without an ETA; *something visibly working* immediately says "it's not
  stuck, it's still working."

The tester also **found and liked** the existing "N of N running" readout —
the model works; the in-flight moment is what's dead. The dead moment is
`AutomationInProgressNotice.tsx` — confirmed in the tree as exactly two `<p>`
tags with no motion, no elapsed clock, and no phase.

## 1. Three top-bar surfaces

The top bar — logo, alarm bell, avatar — is permanent screen real estate doing
essentially nothing today. It becomes three distinct surfaces:

| Surface | Carries | Shape |
|---|---|---|
| **Bus** | A stream of *what is happening* — machine-originated flow: job lifecycle + platform notices. | Newest visible in the bar + a count; older ages out of the bar but is retained in history. Filterable/scopable by user, expert level, and page context (goal — start with today's producers). |
| **Bell → Inbox** | Direct messages *from humans*, and requests *from automations with a human waiting* (approvals). | A work queue, not a feed. Items are addressed to you and expect an answer. |
| **Alarm LED** | Minimal indicator between bus and bell. Click → the relevant alarm messages render *into the bus area*, expanding it. | Later scope. Recorded now so the top bar is built with room for it. |

**Consequence that must not be missed.** The bell today reads workspace health
(`NotificationBell.tsx` — confirmed in the tree: *"the shell bell is a
MONITORING affordance, not a classified-condition inbox"*). Repurposing it into
a human/approval inbox means that monitoring signal **moves to the LED in the
same change**, and the inbox ships as a *defined empty state* — the platform
has no approval-gated automation and no human-to-human messaging today. A bell
that quietly still does the old thing while claiming to be an inbox is not an
acceptable interim state.

### 1a. LED semantics

- **One LED, not a panel.** Severity by shape + colour + count. A lamp per
  condition class turns the top bar into an annunciator and rebuilds the
  competing-indicator problem the rail repaint just got out from under.
- **The LED reads the same Prometheus workspace-health feed `NotificationBell`
  reads today** — confirmed in the tree: `useWorkspaceHealth` +
  `classifyWorkspaceHealth` (`lib/workspaceHealth.ts`), the same floored
  alert set and `isNominal` logic the bell already uses. §1's ruling that the
  monitoring signal *moves* from the bell to the LED means this, concretely:
  **the bell's existing implementation becomes the LED; the bell itself is
  rebuilt as the human/approval inbox.** A move, not a rewrite.
- **Not a projection of the ops store's `DIRTY_STATES`.** An earlier draft of
  this section had the LED read job-outcome dirty state
  (`FAILED_ROLLBACK_REQUIRED` / `ROLLBACK_INCOMPLETE` / `RUN_STATUS_UNKNOWN`)
  instead of monitoring. That was wrong and corrected before anything was
  built from it: alarms come from monitoring; dirty ops are job outcomes —
  different sources, and §1 already said the monitoring signal moves to the
  LED.
- **Self-clearing comes free from the real source.** A Prometheus alert
  clears when the condition stops firing. There is no TTL/self-clearing
  design question for the LED — that question only existed under the
  now-withdrawn `DIRTY_STATES` framing above.
- **The LED offers no actions this round.** Clicking it does exactly one
  thing: brings the relevant alarm message(s) into focus in the bus area —
  no ack button, no resolve, no dismiss, nothing else.
- **The LED does NOT discharge Art. 2.** Hard gate #2 is "close the loop *at
  the point of action*", and the Constitution's own §4 anti-pattern table
  records the exact failure being risked: *a failed teardown whose only
  surface was a different page*. The failure must still persist **at the
  acting stage**. dmfdeploy/dmfdeploy#408 (`ProvisionStage` keeps no record of
  how a deploy ended — confirmed open) is therefore a **prerequisite for this
  design being safe**, not an unrelated bug to fix later.
- **STILL OPEN — do not design around it.** With the LED now sourced from
  Prometheus, dirty-facility state (the ops store's `DIRTY_STATES`) has no
  standing top-bar surface any more, and `_facility_busy_check` still refuses
  dispatch while an op is dirty. Where an operator *sees* that today is an
  open question the operator is still deciding — this is left as a marked
  gap, not a guessed answer.

### 1b. LED visual spec (operator ruling, 2026-08-30 — spec only, later-round build)

**Form.** A narrow **vertical rectangle**, like a status LED on a device
front panel. Sits between the bus and the bell. The thin form is specifically
what lets it satisfy the "never dropped at any width" rule (§1a, §5) — a
narrow element survives narrowing better than a wide one.

**States — reuse the existing classifier, do not re-derive it.**
`lib/workspaceHealth.ts` already classifies workspace health in full:
`phase` (`loading` / `not-configured` / `unknown` / `live`), plus `stale`
(the query errored and the state is holding last-known data) and `verified`
(the Prometheus Watchdog deadman is firing — silence means healthy).
`isNominal` requires **all** of `phase==='live'` **and** `!stale` **and**
`verified` **and** `!hasProblems`; that file's own comment states every other
combination "is degraded/unknown and must be shown honestly." **The LED
renders this existing state — it does not invent a parallel
classification.** The LED and the bell (today) read the same classifier
output and must never be able to disagree. The real remaining design task is
collapsing that 5+-state classifier output onto a narrow bar **honestly**,
not designing a new "unreachable" state — that state already exists and is
already correctly designed; only its bar-scale presentation is undecided.

Collapsed to the bar's visual register, four treatments:

1. **Nominal** (`isNominal` true) — bar present, neutral/unlit-looking.
   **Present, never absent**: presence is what proves the indicator is
   alive. An absent bar and a dead bar would be indistinguishable from each
   other — an Art. 1 provenance failure if the bar could vanish.
2. **Unreachable / cannot-verify** (every `isNominal`-false case that is not
   itself a firing alert: `loading`, `not-configured`, `unknown`, `stale`, or
   `live`-but-`!verified`) — a **distinct treatment on the bar itself**, not
   a badge state. **Hard gate: zero alarms plus "we cannot tell" must never
   render as nominal.** A numeric badge can't express this (a count of zero
   reads as all-clear), so the bar's own look must carry it.
3. **Warning** — amber (the same floored warning+ alerts
   `classifyWorkspaceHealth` already surfaces).
4. **Critical** — red.

**Second cue (Art. 11 — colour is never the only signal): small numeric
badges**, familiar notification-badge form. Up to two — one red (critical
count), one amber (warning count). **Never render a badge at 0** — a badge
reading "0" is a redundant zero, not a signal. The digits are the
greyscale-surviving cue that carries the same information the colour does.

**Badge size — a legibility floor, not a shrink-to-fit exercise.** Numerals
need roughly **10–11px type in a ~14–16px badge** to stay readable — this is
also what Art. 11's "contrast and legibility suited to long shifts and
varied lighting" requires. At that size, **two tiny badges plus the 4px bar
total roughly 40px** — comfortably fits even a 360px viewport, so **both
badges are the default at every width**, not just the wide one.

**Collapse to a single highest-severity badge is a fallback, not the
default.** Use it only if a real measurement shows the two-badge form does
not fit — never as the first-choice narrow-width behaviour, and never
degrade to colour-only at any point (that still fails Art. 11 exactly where
the operator can least inspect the screen). Full degradation order across
the whole bar (fine-grained continuation of §5's order, not a competing
one):

1. Breadcrumb drops.
2. Bus message text drops (icon + count only).
3. **Only if measurement shows it's needed:** the second badge drops (down
   to one badge, highest severity only).
4. **The LED bar and at least one badge are never dropped** — the same rule
   §5/§1a already state, now spelled out at badge granularity.

**Blink.** 1 Hz for 5–10s on appearance. Well under WCAG 2.3.1's
3-flashes/second threshold; confines motion to the *transition* only (Art. 5
— "the screen is still unless the world moved").

- **Re-trigger rule, written down explicitly so it isn't left to guess:**
  fires on an **increase** in highest severity, or a **new** alarm arriving —
  never on every poll that re-observes an already-seen condition (otherwise
  it either never re-fires after the first paint, or blinks permanently
  forever).
- **No blink under `prefers-reduced-motion`.** Costs nothing: the badge
  appearing/changing is already the non-motion cue.

**Hit target.** The bar may be visually narrow, but the interactive target
must be padded to at least **24×24 CSS px** (WCAG 2.5.8) — invisible
padding, a real target.

**Accessibility.** It is clickable, so it is a `<button>` with a real
accessible name stating **severity and count**, e.g. *"2 critical alarms, 1
warning — show messages."* A bare coloured rectangle has no accessible name
at all.

**Colour budget — cross-reference, not a restatement.** Red and amber are
**reserved for this LED**, which is *why* the lifecycle rail's five identity
hues must avoid them
([Lifecycle Rail Visual System](../design/DMF%20Console%20Lifecycle%20Rail%20Visual%20System.md)
§4c). That doc carries the matching cross-reference back to here, so a
future round cannot loosen one side's colour reservation without seeing the
other.

**Unchanged from §1a/C2:** clicking still does exactly one thing — brings
the alarm message(s) into focus in the bus area. No ack, no dismiss, no
resolve — this spec doesn't change that.

**The LED's nominal reading is not proof the bus is alive.** The LED reads
workspace health via the Prometheus Watchdog (above); the message bus is a
*separate* pipeline with its own, independent liveness question — see §2c,
which this subsection does not substitute for.

**This entire subsection is spec only.** The LED remains later-round scope
(decisions-file §1, §8 below) — nothing here is built this round.

### 1c. Ack contract (recorded now, builds nothing this round)

**When Ack lands — not this round — it records "seen by `<actor>` at
`<time>`" and never dismisses** the underlying condition. This is presentation
only, never truth: it is ISA-18.2's actual meaning of "acknowledge" — telling
other operators someone is aware, not making the alarm go away. **The
condition clears only when the condition clears** (Art. 1: the console never
asserts an all-clear it has not observed).

**Standing operator preference: Ack ships only alongside the full alarm
taxonomy**, which remains a stub
([Alarm Philosophy](../design/DMF%20Console%20Alarm%20Philosophy.md)). This round
writes the rule down — here and in that doc — and builds nothing: there is
no ack UI, because the LED itself ships with no actions this round (§1a).

**Not a dangerous action.** A recorded ack — who saw it, and when — needs
none of Constitution Art. 7's heavier treatment (impact preview, typed
confirmation): it dismisses nothing and asserts nothing about the underlying
condition, so it carries none of Art. 7's consequence-class machinery.

**Ack does not require a C5 `reason` — explicit exception, stated now so
implementation cannot grow one.** ADR-0028 C5 requires actor, role, request
id, *and reason* for every DMF-initiated automated action
([0028-identity-and-authority-chain.md:63-66](../decisions/0028-identity-and-authority-chain.md)).
Ack's own shape above — actor + timestamp only, never a reason field — is
the exception to that general rule, not an oversight: an ack asserts nothing
about *why* (it dismisses nothing, per "Not a dangerous action" above), so
there is no "why" for a reason field to capture. Without this line, a
literal reading of C5 would require implementation to either add an
unnecessary reason prompt to what is supposed to be a single-click
acknowledgement, or reject a valid ack for lacking one it was never meant to
carry.

## 2. The bus is a projection, not a new store

The Audit/Event-Log Spec already says `/changes` should be *a projection of
the audit record*. The console today has **four partial, mutually
inconsistent answers to "what happened"**:

| Surface | Backing | Lifetime |
|---|---|---|
| `store/topbarMessage.ts` | in-memory, single slot | 6 seconds |
| `store/activity.ts` | localStorage | this browser only; never other operators |
| `/changes` | live AWX + Forgejo scrape | whatever those APIs return |
| `audit_logger` (`dmf_cms.audit`) | prose to stdout → Loki | 30d general — the 6mo security-relevant stream exists in Loki but nothing routes this logger into it today (gap, see §2a) |

**Ruling: collapse all four into projections of one record.** The bus is the
missing read side of Art. 10, not a fifth surface.

### 2a. Storage

**Recorded as operator rulings, 2026-08-30 — tracked by umbrella issue #496**
(`dmf-cms: the audit stream records dispatch but never outcome — the bus's
missing producer, and D7 retention is unmet`). The retention *numbers* below
are ADR-0028 D7, an existing, accepted ADR; the envelope, transport, and
rejected-alternatives choices are this round's own rulings, not independent
prior decisions — #496 is where their implementation and any revision is
tracked, not this plan alone.

- **Envelope: CloudEvents** (CNCF). `specversion`/`id`/`source`/`type`/`time`/
  `subject`/`data`; the Audit Spec's existing record schema drops into `data`.
  It is a *shape*, not a dependency. **Do not invent a bespoke JSON wrapper.**
  **`specversion` is REQUIRED** — CloudEvents 1.0 lists `id`, `source`,
  `specversion`, and `type` as its four required top-level attributes
  ([spec](https://github.com/cloudevents/spec/blob/main/cloudevents/spec.md));
  a `specversion`-less envelope is not CloudEvents, it is a bespoke wrapper
  that happens to share some field names — exactly the failure choosing
  CloudEvents was meant to avoid. Fixed value: `"1.0"`. **`id` is event
  identity only, never a correlation key** — it identifies *this event*, not
  a delivery attempt (a redelivery of the same event may reuse the same
  `id`; that is a dedup signal, not a new occurrence). `request_id` remains
  the **sole** cross-app correlation key (Audit Spec); consumers must not
  treat the CloudEvents `id` as a competing correlation identifier even
  though both fields sit on the same envelope.
- **Transport: structured JSON on the existing `dmf_cms.audit` child logger →
  stdout → Promtail → Loki.** The child logger, stdout, Promtail, and Loki all
  already exist — but the **structured JSON** part does not: today
  `audit_logger` emits printf-style prose, confirmed in the tree by its own
  declaring comment (`main.py`), which states it "stays printf-style ... not
  structured JSON" and that moving to structured logging is "a whole-codebase
  decision, not this fix's to make." That move is itself unbuilt work, tracked
  under #496.
- **Hot path in memory, cold path in Loki.** A bounded in-memory ring buffer
  serves the live bus instantly and keeps working when the monitoring vertical
  is down; click-to-expand history queries Loki.
- **Retention numbers are ADR-0028 D7** — hot 6 months (Loki) for
  security-relevant/identity-bearing streams, **streamed to WORM object-lock
  S3 in near-real-time, in parallel with the hot write** (12-month WORM
  window) — corrected: **not** a six-months-later handoff. D7's own rationale
  is closing the pre-export mutation window; a delayed export would leave
  that window open for the full 6 months, defeating the point. Loki is the
  hot cache of an append-only stream, not "our audit database".
  **The shipped default, verified against `dmf-infra`'s Loki role, is 30 days
  (720h) general retention plus a 4380h (6-month) security-relevant stream
  that already matches ADR-0028 D7's number** — the earlier 168h/7d figure was
  only ever a sandbox-monitoring-doc *plan target*, never what is actually
  deployed.
- **D7's 6-month hot retention is UNMET for `dmf_cms.audit` today — an
  explicit gap, not an assumed-solved detail.** Confirmed against
  `dmf-infra`: the security-relevant retention selectors are
  `{job="k3s-audit"}`, `{job="authentik-audit"}`, and `{job=~".+-security"}`
  (`roles/stack/operator/loki/templates/values.yml.j2`). Ordinary pod
  stdout — which is all `dmf_cms.audit` is today — is picked up by the
  generic Kubernetes-pods scrape job and carries none of those labels, so it
  falls through to the 30-day general default. **The exact Promtail rule and
  the acceptance check that actually proves survival past 30 days (not just
  a line's continued presence) are specified once, in full, in the
  [Audit and Event-Log Spec](../design/DMF%20Console%20Audit%20and%20Event-Log%20Spec.md)'s
  Storage architecture section** — summary: relabel matched `dmf_cms.audit`
  lines to `job=dmf-cms-security` (satisfies the existing `.+-security`
  selector with no Loki-role change), then a paired nonce + negative-control
  query proves both the label assignment and the >30-day survival, not one
  without the other. Tracked under #496.
- **The UI states its window honestly (Art. 1): "last 30 days," full stop —
  no future exception.** Until the routing gap above is closed and verified,
  no surface reads the security-relevant stream at all, so nothing can
  honestly claim a 6-month window yet either.
- **Rejected: NATS / a broker.** Wrong layer — one in-process producer, one
  consumer, single replica. It adds delivery semantics we don't need and still
  leaves the storage question open. Revisit only if multiple repos publish.
- **Rejected: a console-owned DB/PVC for now.** On this platform node loss
  means re-bootstrap either way, so a PVC buys control, not survivability.

### 2b. The frontend must not be a producer

`store/activity.ts` is written from **seven call sites**, confirmed against the
tree (a prior count of six was corrected by tree verification):

- `ProvisionStage.tsx:109-110` (`recordClear`) and `:260-268` (`recordAwxWrite`, deploy)
- `FinaliseStage.tsx:230-238` (`recordAwxWrite`, teardown) and `:272-280` (`recordAwxWrite`, finalise-purge)
- `JobsLane.tsx:40-48`
- `Catalog/index.tsx:64-72`
- `ConfigureStage.tsx:196-204`

The backend *already* records most of these events via `_audit_awx_write`
(`main.py:952-1001`) with better data — real `request_id`, server-side role —
**but not the actual outcome, and not uniformly for every action.**
Corrected: for the **watched actions** —
`deploy`/`teardown`/`rollback`/`finalise-purge`, exactly
`operations.py:89-96`'s `_WATCHED_ACTIONS` — `_audit_awx_write` records the
**dispatch result only**. The synchronous paths audit `outcome="launched"`
the moment AWX *accepts* the job (confirmed in the tree, e.g. `main.py`'s
sync deploy/teardown handlers); the asynchronous paths audit
`outcome="dispatched"`. Neither is the job's actual result. The real
terminal state (`RUN_COMPLETE` / `RUN_FAILED` / `FAILED_ROLLBACK_REQUIRED` /
`ROLLBACK_INCOMPLETE` / `RUN_STATUS_UNKNOWN`) is computed by
`_watch_job_operation`'s poll loop — confirmed in the tree to write only to
the in-memory `OperationStore` (`ops_store.update(...)`), with **no call to
`audit_logger` or `_audit_awx_write` anywhere in that function.** Terminal
truth exists only in memory today; it never reaches the audit log at all.

**This is scoped to the watched actions specifically — it is not true of
every `_audit_awx_write` call, in either direction.** `switch-source`
(`main.py:5728-5749`) has no watcher and needs none: it runs its own
actuator (reconnect / future `nmos-is05`) synchronously to completion
*before* its single `_audit_awx_write` call, so that call — unlike every
watched action's — already carries a genuinely terminal outcome
(`command.status.value`: `active` or `failed_rollback_required`). `launch`
(the generic AWX workflow launch) also has no watcher, but for a third,
distinct reason, and its own outcome values are **not** resolved by this
plan — see the
[Audit and Event-Log Spec](../design/DMF%20Console%20Audit%20and%20Event-Log%20Spec.md)'s
"`outcome` vs `outcome_detail`" section, which defines the full `outcome`
enum mapping (including the D2 ruling that dispatch acceptance maps to
`outcome: in-progress`, never a new enum member) and explicitly leaves
`launch`'s case open rather than guessing at it. Do not infer "no helper
call has a terminal outcome" (false — switch-source's does) or "every AWX
action has a watcher" (false — `launch` and `switch-source` don't, for two
different reasons) from the watched-action description above.

Separately, the CLEAR-FOR-DEPLOYMENT path (`recordClear`) is logged through
the plain module `logger`, not `audit_logger`/`_audit_awx_write` (confirmed at
`main.py:5463-5474`): it has no structured, correlatable server record to
become a read of yet. **Bringing the clear path onto `_audit_awx_write` is a
prerequisite for this section's plan, not an assumption that is already true
today.**

**A client-supplied audit record is not an audit record.** Once the clear path
is on the shared helper, all seven call sites can become
**reads/invalidations of the server's dispatch-level record**, never writers
of a second one. Whether the same surface can also show the *terminal*
outcome depends on the terminal audit-event producer below — a separate,
later dependency, not a blocker for this read migration itself.

**There is also no server audit-READ endpoint today, and building one is an
explicit deliverable of this work, not a buried clause.** Confirmed in the
tree: `/api/changes/jobs` and `/api/changes/pulls` (`main.py:4077-4153,
:4244-4248`) scrape AWX/Forgejo live on every request; `/api/operations/{id}`
(`main.py:3200-3209`) returns a single in-memory `Operation`, not a queryable
history. None of these read a durable, correlated audit record — that read
surface (over the ring buffer for "now" and Loki for history) has to be built,
not merely wired up.

**A terminal audit-event producer is a separate, explicit deliverable and
does not exist today (tracked by umbrella issue #496), with a scope split
worth stating precisely rather than collapsing.** A ring-buffer/Loki
projection of dispatch-only records (`launched`/`dispatched`) cannot close
the see/do/did loop (Constitution Art. 10) with real outcomes — dispatching a
job is not the same fact as the job succeeding or failing, and today only the
former reaches the audit logger. But **the bus's LIVE path may not need this
producer at all**: `OperationStore` already holds the real terminal state in
memory (above), so a live view can plausibly be served straight from that
store without waiting on an audit-log producer. It is the bus's **HISTORY**
path — anything meant to survive past the operation's in-memory lifetime,
correlated in Loki — that needs a durable audit record carrying the real
terminal outcome. Closing that gap means `_watch_job_operation` (or an
equivalent terminal-state observer) emitting a structured audit event at a
terminal `OperationState`, correlated by the same `request_id`/`run_id` the
dispatch record already carries. **This plan does not schedule that work
relative to the bus's live path** — whether the terminal producer must land
before the bus ships at all, or only before its history view does, is left
open here, not decided. See also §7's deliverables list.

### 2c. The bus's own liveness — not the same as workspace health

**The message bus is not equal to the Prometheus Watchdog.** The Watchdog
proves *monitoring* is alive — it proves nothing about whether the
console's own event stream is flowing. If the terminal audit-event producer
(§2b, #496) stops emitting, or Promtail stops shipping `dmf_cms.audit`
records, the Watchdog still fires happily, the LED still shows nominal
(§1b), and the bus goes silently empty. An empty bus would then read as
"nothing happened" when it actually means "we lost the stream" — the same
Art. 1 failure as an absent LED reading as all-clear.

**The bus needs its own liveness/provenance story**, with three sub-paths
that genuinely differ and must not be collapsed into one status:

- **LIVE path** (in-memory ring buffer, same process). Liveness here is just
  the console's own API liveness — cheap, and effectively always known.
- **HISTORY path** (a Loki query). Fails independently of the live path.
  Must render **"history unavailable"** on failure — never silently "no
  history," which reads as "nothing happened here" rather than "we could
  not ask."
- **PRODUCER path** (§2b's terminal-audit-event producer, tracked by #496).

**Operator ruling, 2026-08-30 — tracked by umbrella issue #497, design
record only, builds nothing this round:** the message bus **must monitor
its own liveness and report it to Prometheus**; the LED then surfaces that
through its ordinary path with no special-casing, because the LED already
reads Prometheus (§1a/§1b).

**The subtlety, written down explicitly so it isn't lost:** a quiet bus is
**legitimately** quiet — no operations running means no events, so "no
events in N minutes" is **not**, by itself, a fault signal. Alerting on
event-count staleness would fire constantly on an idle system and train
operators to ignore it (EEMUA 191's alarm-flood failure mode). The signal
has to be a **heartbeat that ticks regardless of activity**, separate from
the event count — the same pattern the Watchdog itself uses, applied to this
pipeline instead of to monitoring.

**Two tiers, kept distinguished — do not let one stand in for the other:**

- **Tier 1 — the emitter is alive.** `/metrics` exposition + a heartbeat
  counter + the standard `up{job="dmf-cms"}` scrape target existing at all.
- **Tier 2 — end-to-end.** A canary record emitted, then queried back out of
  Loki, proving the whole pipeline (emit → Promtail → Loki → read) actually
  works, not just that the emitter process is running.

**Tier 1 alone does not cover the bus.** It cannot see a Promtail
misconfiguration — which per §2a/#496 is a failure this platform **already
has today** (the security-relevant retention routing gap). Nothing in this
doc, or any implementation of it, should imply Tier 1 alone means the bus is
covered.

**Context worth recording here, bigger than the bus itself: `dmf-cms` is
currently unmonitored entirely.** Confirmed in the tree: `/api/monitoring/metrics`
(`main.py:3982`) is the console **reading** Prometheus, not exposing
anything to it; there is no `prometheus_client` dependency; there is no
`ServiceMonitor` under `charts/dmf-cms/templates/`; and nothing in
`dmf-infra`'s Prometheus role scrapes `dmf-cms`. The operator console is the
one platform component with no liveness monitoring at all today. **#497
carries this fact — this plan does not scope-creep the shell round into
fixing it**; it is recorded only so the bus-liveness ruling above is not
designed against a false assumption that `dmf-cms` already has baseline
monitoring to build on.

**Hard rule:** the bus must never render emptiness as "nothing happened"
without qualifying *which* of these possibilities it might instead be — a
genuinely quiet facility, a lost live connection, an unreachable history
query, or a stalled producer/heartbeat all look identical as a bare empty
list, and only the first is honest if presented as-is.

## 3. The throbber (cross-reference)

Full mechanism spec lives in the companion Phase 1 arc (dmf-runbooks +
dmf-cms), which runs in parallel with this doc round and depends on none of
its decisions. This section records only the shape, so the shell's layout
seams (the acting-stage box, and the bus's Placement 2) are built to receive
it.

- **Placement 1 — at the point of action (primary).** Replaces
  `AutomationInProgressNotice` in situ on Provision and Finalise: a spinner, the
  action in plain words, an elapsed clock counting up, and the current step in
  operator language. On terminal, the box stays put and becomes the result —
  it does not vanish. Three independent liveness proofs (spinner / clock /
  step text) that fail differently, so a stalled or uninstrumented run still
  reads honestly rather than as a blank throbber.
- **Placement 2 — the bus (secondary, survives navigation).**
  `◐ Provisioning Studio A · 2m 14s`, clickable, returns to the acting stage.
  **Needs dmfdeploy/dmfdeploy#436** (workload identity on the jobs wire) or it
  can only say "Provisioning" with no name — which is why #436 is pulled
  forward into this round's sequencing (§6).
- **Placement 3 — none.** No indicators on the lifecycle rail
  (dmfdeploy/dmfdeploy#481 ruling); this is what lets the chevrons centre.

**Marker contract, at plan level only.** The emit side reuses the existing
outcome-marker mechanism cleanly — dmf-runbooks already emits outcome markers
on named tasks and `awx.py` already reads them via `get_job_events_for_task`.
The console's existing *parse* side, however, is a **terminal-only** call
site: it runs once after a job reaches a terminal state and returns the last
matching event. Live milestone text during an in-flight run needs a genuinely
**new** during-run read path (a mid-run poll of job events for the milestone
task name, on the same cadence as the operation watcher's existing poll loop).
This is real, uncosted work, not a rewire of the existing parser — it is
**on hold pending an estimate and an operator ruling** before the companion
arc's corresponding work package is written. This plan does not re-derive that
estimate; it only records that the emit/parse split is uneven so neither this
doc nor the companion arc overclaims "the machinery is already gate-tested" for
the read side.

## 4. The lifecycle rail — out of scope here

The rail's visual grammar (channels, colour, shape, icon set) is specified in
the companion doc,
[DMF Console Lifecycle Rail Visual System](../design/DMF%20Console%20Lifecycle%20Rail%20Visual%20System.md).
This plan only owns the layout seam: the rail moves out of the top bar into
its own band (§5).

## 5. Top bar layout

One bar: **logo · breadcrumb · bus (right of centre) · alarm LED · bell ·
avatar.**

**Responsive degradation, explicit order (operator ruling):**

1. **The breadcrumb disappears first** as the bar narrows.
2. **The bus's message text is next** — it degrades to an icon + count,
   dropping the newest-message text.
3. **The alarm LED is never dropped, at any width.** It is the relocated
   always-visible monitoring signal (§1a); a facility alarm going invisible
   on a narrow viewport is exactly the failure this design exists to
   prevent.

The narrowest view therefore retains **logo · bus (icon + count) · alarm
LED · bell · avatar** — every step above drops something *before* the LED,
never the LED itself.

The rail moves out of the header into its **own band** below it
(dmfdeploy/dmfdeploy#481) — today it is header row 2 (`header-slot-row`),
rendered only on workload-detail routes.

## 6. Sequencing

- **Spec the model now, build visuals against it, behaviour lands after.**
  #493 is the doc amendment; `classifyWorkloadFlow` + the ~10 dependent tests
  (including the delete-permanently authorization suite) are a later round.
- **#436 pulled forward** into the bus work — the bus's Placement 2 is
  decorative without it.
- **Phase 1 (throbber) runs partly in parallel** with Phase 0 (docs): the
  primary in-stage throbber (Placement 1, §3) depends on none of the rail or
  bus decisions here, though its marker-contract read side (§3) needs its own
  estimate before it is built. Its secondary, bus-surfaced form (Placement 2)
  is **not** independent — it depends on this plan's bus existing and on #436
  (workload identity on the jobs wire).
- **Deferred, explicitly:** bell→inbox behaviour, mobile (#484), the grid
  canvas (frozen).

## 7. Explicit deliverables this round implies (not yet built)

Named here so they are not lost between "decided" and "built":

1. A server audit-READ endpoint over the ring buffer (hot) + Loki (cold) — does
   not exist today (§2b, tracked by umbrella issue #496).
2. `recordClear`'s CLEAR-FOR-DEPLOYMENT path moved onto `_audit_awx_write` so it
   has a structured server record to become a read of (§2b, tracked by
   umbrella issue #496).
3. **A terminal audit-event producer** (tracked by umbrella issue #496).
   `_watch_job_operation` (or an equivalent terminal-state observer) needs to
   emit a structured audit event when it reaches a terminal `OperationState`,
   correlated by the same `request_id`/`run_id` the dispatch record already
   carries. Today terminal truth reaches only the in-memory `OperationStore`;
   the audit log carries only dispatch outcomes (`launched`/`dispatched`),
   never success/failure (§2b). **Scope split, left open rather than decided
   here:** the bus's live view may be servable straight from `OperationStore`
   without this producer; it is the bus's *history* view (anything durable,
   correlated in Loki) that needs it to show real outcomes rather than only
   dispatch events.
4. The alarm LED as the new home for the existing Prometheus workspace-health
   feed (moved out of `NotificationBell`), landed **after** #408 — #408 is
   about `ProvisionStage` losing *deploy* outcomes on terminal, not about
   `FinaliseStage`/teardown, which does not have that gap. #408 matters here
   for the general point-of-action principle it establishes (Art. 2: a
   failed action's only record must not be a different page), not because
   teardown itself is the affected path (§1a) — **later-round scope, not
   this round's build** (decisions-file §1; see §1b for the visual spec and
   §1c for the ack contract, both recorded now precisely so this later build
   has no room to violate them).
   The open question of where dirty-facility state (`DIRTY_STATES`)
   surfaces once the LED moves to Prometheus is unresolved and explicitly
   not guessed at here (§1a).
5. The bus's Placement 2 throbber reference, gated on #436 (§3).
6. **The bus's own liveness signal** (tracked by umbrella issue #497): a
   Tier 1 emitter-alive heartbeat (`/metrics` + `up{job="dmf-cms"}`) and a
   Tier 2 end-to-end canary (§2c). `dmf-cms` has no `/metrics` exposition,
   no `prometheus_client` dependency, and no `ServiceMonitor` today — this
   is new baseline monitoring for the whole component, not just the bus.
7. **The D7 WORM/export producer** (tracked by umbrella issue #496 —
   previously named only as architecture text in §2a, not as a
   deliverable). §2a rules out "six months hot then export" and requires
   **streaming, near-real-time, parallel** delivery to object-lock S3
   (12-month window); nothing in this list built it. Needs: the producer
   itself (subscribes to the same append-only stream the ring buffer/Loki
   read side does, or tails Loki directly — implementer's choice, not
   pre-decided here); the object-lock/WORM bucket and its retention-lock
   configuration; and an acceptance check that proves, per write, (a) the
   S3 object landed **within the same request's window**, not on a later
   batch job (parallel, not delayed-export), (b) the bucket's object-lock
   mode actually rejects a delete/overwrite attempt against a written
   object (immutability, not just a retention *label*), and (c) the
   object's own retention-until metadata reflects the 12-month target.
   `dmf-infra`'s existing `audit-log-archival` role is a **precedent for
   the S3 object-lock plumbing only** (`audit_log_object_lock_mode:
   COMPLIANCE`, `audit_log_object_lock_days: 365`) — its own delivery is a
   **daily batch cron** against `k3s-audit`'s host-file log, not near-real-time
   streaming, so it does not itself satisfy D7's "parallel with the hot
   write" requirement and must not be reused as-is for timing, only for its
   bucket/object-lock configuration shape. If this producer belongs to a
   different owner/repo than dmf-cms (`dmf-infra`, most likely, given the
   precedent above), name that owner explicitly rather than leaving it to
   be inferred.

## 8. Non-goals this round

Bell→inbox interaction design, mobile placement (#484 — see the umbrella issue
for the one correction made this round), the rail's own visual system (owned
by the companion doc, §4), the throbber's implementation (companion Phase 1
arc, §3), **the bus's own liveness heartbeat** (§2c — recorded as an operator
ruling, tracked by #497, builds nothing this round), and **the alarm LED
itself plus its (not-this-round) ack UI**
(§1a/§1b/§1c — spec and contract recorded now, built in a later round, not
this one).
