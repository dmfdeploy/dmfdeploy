# DMF Workspace Alarm Surface Research (EEMUA 191) — 2026-07-06

> **STATUS: RESEARCH ACCEPTED — the operator accepted it on 2026-11-08.** This is
> WP-G of the v0.2 round
> (`docs/archive/plans/DMF v0.2 Media-Native Console Demo Plan 2026-07-06.md`,
> tracking [#187](https://github.com/dmfdeploy/dmfdeploy/issues/187)). 15
> claims are adversarially verified 3-0 (§3); the synthesis + HealthCore
> mapping (§4-§6) is authored from those. The one thin spot is visual-design
> specifics (§3c) — flagged where it matters. WP-H applies §5/§6; WP-H is
> **not** a 0.14.0 release gate.
>
> **Checked against:** EEMUA 191, 2024 edition (Publication 191, Edition 4),
> checked 2026-11-08. The copy used for the check holds the front matter and
> pages 1 to 34 (Sections 1 to 2.7.2). It confirms the alarm definition, the
> alert, prompt and event classes, alarm classification, the lifecycle, and the
> operator-workload reasoning. These carry EEMUA 191 section numbers below. The
> priority distribution, alarm-rate bands, flood tolerance, standing-alarm
> benchmark, KPIs, shelving and suppression sit in Chapters 5 to 7, which the
> copy does not include. Those statements keep their original sources, which are
> other alarm-management guidance. This document did not check that guidance
> against its source. The statements are marked "not checked against EEMUA 191". One conclusion is qualified: see
> §4, point 2.

## 1. Why this research exists (context for a cold agent)

Operator feedback on the Workspace "are we OK?" core shipped in #174
(dmf-cms 0.13.0): good start, but wants a human-friendly at-a-glance surface
with a **clear priority structure** and **no non-required info on the front
page**. WP-G researches what the alarm-management and high-performance-HMI
standards actually prescribe; WP-H (gated on this doc + operator review)
applies it to the console.

The surface being judged: **HealthCore** — firing Prometheus alerts rendered
as severity tiles + a "Current Problems" list + a single verdict line
(Watchdog-verified green, degraded-as-content, no Ack). See dmf-cms
`pages/Workspace/` and the Console UX Constitution
(`docs/design/dmf-console-ux-constitution.md`, esp. Art. 4 alarm
pointer + Art. 6 "one deliberate step away").

Ground rules (from the plan): EEMUA 191 is paywalled — use reputable
secondary sources, cite only what was actually read, **never fabricate clause
numbers**. Every clause number and figure below is quoted from a source that
was actually fetched and read; where a number lives beyond a preview boundary
it is attributed to the secondary source that reproduced it, not to the
primary standard. The 2024 edition of EEMUA 191 was read later for the
sections named in the "Checked against" note. Every EEMUA 191 section number
in this document comes from that read or from the edition's contents pages.

## 2. Method + run provenance

- Harness: `deep-research` workflow, run id `wf_3568056d-fd7`, 2026-07-06.
  Phases Scope → Search (5 parallel angles) → Fetch (22 sources, 109 claims
  extracted) → Verify (top 25, 3-vote adversarial) → Synthesize.
- Verification ran in three passes because the first two hit model/session
  token limits mid-flight (Fable 5 limit, then a session limit); the run was
  resumed with cached search/fetch results, and the verify fleet finished on
  Opus 4.8. **Final: 15 of 25 prioritized claims confirmed 3-0; 10 abstained
  0-0** (verifier died on the limit before voting — NOT refuted). The
  abstained 10 are near-duplicates of confirmed claims sourced from a
  different document (exida "Journey", Inductive Automation/PAS mirror,
  Yokogawa rate table), so their substance is independently corroborated by
  the confirmed set. The harness's own `synthesize` step never ran (limit);
  §4-§6 below are authored by the orchestrator from the confirmed claims.
- Raw run output (session-scoped tmp; may not survive reboot):
  `…/tasks/w5px4wy2r.output` (final pass), `…/wc4z2c066.output` +
  `…/wat9stinm.output` (earlier passes) under
  `/private/tmp/<session-scoped harness tmp>/…/tasks/`.
  Workflow script: `…/workflows/scripts/deep-research-wf_3568056d-fd7.js`.
- The 5 search angles: (1) Standards KPIs + priority distribution, (2) Alarm
  lifecycle + suppression semantics (IEC 62682 / ISA-18.2), (3) ISA-101 HMI
  hierarchy + L1 overview design, (4) Visual design: grey-scale, colour
  reserved for abnormal, (5) Alarm floods, rationalization failures,
  IT-monitoring crossover (deliberately includes Google SRE for the
  Prometheus-world mapping).

## 3. Verified findings (adversarial 3-0, quotes from the actually-read source)

### (a) Priority structure, distribution targets, alarm rates

- **Priority distribution target ~80% low / 15% medium / 5% high** for a
  3-priority scheme (or 80/15/5 + <1% "highest" for 4 priorities),
  special-purpose priorities excluded. — ProcessVue (author is an ISA-18.2
  committee voting member), quoting ISA-18.2 / IEC 62682:
  *"3 priorities: ~80% Low, ~15% Medium, ~5% High or 4 priorities: ~80% Low,
  ~15% Medium, ~5% High, ~<1% 'highest'."*
  <https://www.processvue.com/downloads/Alarm_system_performance_KPIs_V1_0.pdf>
  EEMUA 191 (2024) has, by title, a priority-distribution table (Table 15,
  Section 7.3.2) and a priority-distribution section in Appendix 3 (A3.3),
  seen in the contents only. Neither is in the copy checked, so the 80/15/5 figures are other
  alarm-management guidance, and this document did not check them against
  their source. EEMUA 191's own table may differ.
- **Steady-state alarm-rate bands per operator (EEMUA 191 3rd ed., p.96):**
  <1 alarm/10 min very likely acceptable; 1/5 min manageable; 1/2 min
  over-demanding; >1/min very likely unacceptable. — ProcessVue (quoting
  EEMUA 191 p.96 verbatim). The page number belongs to the 3rd edition. In the
  2024 edition the table with the closest title is Table 16, "Long term
  average alarm rate" (Chapter 7, page 107; seen in the contents only). The 2024 edition says the criteria in earlier
  editions have not changed ("Revised Fourth Edition, 2024"), but Table 16 is
  not in the copy checked, so the bands are not checked against EEMUA 191. The
  2024 edition does explain why the rate matters: if each alarm takes about
  five minutes to handle, six alarms an hour occupy half of the operator's
  time (Section 2.1.4).
- **Flood tolerance after a major upset (EEMUA 191 3rd ed., p.97):** <10
  alarms/operator in the first 10 min manageable; 20-100 hard to cope with;
  >100 excessive and likely to make the operator abandon the alarm system.
  — ProcessVue. In the 2024 edition the related tables are, by title, Table 17,
  "Major process upset alarm", and Table 18, "Target maximum occurrence rates
  of alarms of different priorities" (Chapter 7, page 108; seen in the
  contents only). Neither is in the copy checked, so these figures are not checked against EEMUA 191. The principle
  holds: EEMUA 191 says floods during upsets overload operators so that they
  cannot diagnose the problem (Section 1.3).
- **ISA-18.2-2016 flood/hygiene KPIs (Table 7):** <~1% of 10-min periods with
  >10 alarms; ≤10 alarms in any 10-min period; system in flood <~1% of the
  time; zero chattering/fleeting alarms; <5 stale alarms/day. **Averages must
  not be extrapolated** — *"One alarm per ten minutes cannot be converted to
  six alarms per hour and certainly not extrapolated to 144 alarms per day…
  the 144 alarms of a day can all occur in (less than) an hour"* (clustering
  is what overwhelms). — ProcessVue. These KPIs come from ISA-18.2 and do not appear in
  the EEMUA 191 text checked. EEMUA 191 has its own standing-alarm benchmark (Section 7.4.4,
  Table 19) and KPI set (Section 7.4.5, Tables 20 and 21), seen in the
  contents only and not checked. The clustering point matches EEMUA 191 Section 2.1.4: a scenario
  that creates many alarms at once overloads the operator even when each alarm
  is useful.
- **Targets are approximate and non-mandatory; rate alone is not
  acceptability:** *"The target metrics … are approximate and depend upon
  many factors … Alarm rate alone is not an indicator of acceptability."*
  — PAS "Understanding ISA-18.2" (Hollifield), hosted by ISA. This is an
  ISA-18.2 statement. It is not checked against EEMUA 191.
  <https://www.isa.org/getmedia/55b4210e-6cb2-4de4-89f8-2b5b6b46d954/PAS-Understanding-ISA-18-2.pdf>

### (b) What is an alarm / what belongs on the surface

- **An alarm requires an operator response** — *"an audible and/or visible
  means of indicating to the operator an equipment malfunction, process
  deviation, or abnormal condition requiring a response."* Non-actionable
  indications are not alarms. — PAS (ISA-18.2 definition) and independently
  Yokogawa/Control-Engineering
  (<https://www.yokogawa.com/us/library/resources/media-publications/implementing-alarm-management-per-the-ansi-isa-182-standard-control-engineering/>).
  EEMUA 191 (2024) agrees, with one difference. Its definition (Section 1.1)
  says the condition requires a *timely* response. It also says that if you
  cannot define a response, the signal should not be an alarm (Section 1.4),
  and it lists signals that are not alarms (Section 2.3.4).
- **EEMUA 191 separates alarms from alerts, prompts and events (Section 2.3,
  Figures 7 and 9).** An alarm is an unexpected event that needs timely
  operator action. An alert is an unexpected event that needs no response. An
  alert is not time critical, always ranks below an alarm, should not be
  audible, and can be suppressed during upsets (Sections 2.3.1 and 2.3.3). A
  prompt is an expected event that may need action but is not time critical
  (Section 2.3.3). Most events need no alarm (Section 2.3.2). Section 2.4 adds
  that an alarm class groups alarms that share management requirements, such as
  testing, training or shelving. A class is different from a priority.
- **Prioritization + suppression are lifecycle work-products, not UI
  features.** IEC 62682:2022 defines a full alarm-management life cycle
  (Clause 5.2, Fig. 2): philosophy (6) → identification (8) →
  rationalization (9, incl. 9.5 Prioritization) → detailed HMI design (11) →
  operation incl. shelving (14.3) → maintenance incl. out-of-service (15.3) →
  monitoring (16) → MOC (17) → audit (18). Philosophy (Clause 6) must define
  the prioritization method, alarm-class definitions, and HMI design
  principles. — IEC 62682:2022 preview PDF
  (<https://cdn.standards.iteh.ai/samples/103485/6f7b44e368fc4f4d93216f716a51771a/IEC-62682-2022.pdf>).
  EEMUA 191 reproduces the same lifecycle in Figure 4 and Table 2
  (Section 1.5.5). The stages are philosophy, identification, rationalisation,
  detailed design, implementation, operation, maintenance, monitoring and
  assessment, management of change, and audit. The chain above leaves out the
  implementation stage. EEMUA 191 also says the philosophy identifies alarm
  classes and the method of classifying alarms (Section 2.4), and defines the
  use of alerts, events, prompts, alarms and highly managed alarms
  (Section 2.6). Its example philosophy has headings for prioritisation methods and HMI
  design principles (Appendix 4, A4.5 and A4.11, seen in the contents only);
  the content was not checked. The IEC clause numbers were not re-checked.
- **Per-operator-console KPIs are normative content (IEC 62682 Clause 16):**
  average alarm rate (16.3.3), peak rate (16.3.4), floods (16.3.5),
  chattering/fleeting (16.3.7), stale (16.3.8), annunciated priority
  distribution (16.3.9), with numeric Table 5 (average rates) + Table 6
  (example priority distribution). — IEC 62682:2022 preview. EEMUA 191 lists
  KPIs in Section 7.4.5 and Tables 20 and 21 (seen in the contents only);
  that content was not checked.
- **IT-monitoring crossover (Google SRE Workbook)** — the natural bridge to a
  Prometheus-native console: a **two-tier** page-vs-ticket split chosen by
  required response speed (*"If an issue will exhaust the error budget within
  hours or a few days, sending an active notification is appropriate.
  Otherwise, a ticket-based notification … the next working day is more
  appropriate"*), with concrete burn-rate thresholds (**2%/1h or 5%/6h →
  page; 10%/3d → ticket**). — <https://sre.google/workbook/alerting-on-slos/>

### (c) Visual design (thin — see gap note)

The confirmed set does not include a quote-level visual-design rule (the
grey-scale / colour-reserved-for-abnormal claims fell below the verify cut).
What IS anchored: IEC 62682 Clause 11 formalizes an **alarm summary display**
as a distinct display type and requires priority to be visually
distinguishable. The grey-scale / high-performance-HMI colour discipline
(neutral background, saturated colour reserved for abnormal, ~90%-neutral L1
screen) is well-attested across the fetched practitioner sources (Rockwell
Process HMI Style Guide WP023, PAS High-Performance HMI overview, ISA-101
summaries) but was **not independently vote-verified in this run**. Treat
§3c as directional; if WP-H makes colour-token changes, verify against
Rockwell WP023 + the PAS overview first (both fetched, listed in §7).

### (d) Shelving / out-of-service / suppression — the "don't half-implement" set

- **Three distinct, separately-specified silencing mechanisms, each with its
  own functional-requirements subclause AND its own mandatory display
  subclause:** IEC 62682:2022 **11.7 Alarm shelving** (incl. 11.7.4 Shelved
  alarm displays), **11.8 Out-of-service alarms** (incl. 11.8.3 displays),
  **11.9 Alarms suppressed by design** (incl. 11.9.4 displays). *A surface
  that offers any of these states must also display them — not merely hide
  alarms.* — IEC 62682:2022 preview. EEMUA 191 has sections with matching titles:
  5.7 (shelved and suppressed alarms), 6.3 (suppression, including 6.3.4,
  authorisation and control) and 6.5 (shelving). They were seen in the
  contents only and not checked, so this bullet rests on IEC 62682. EEMUA 191 does say that an alarm system needs a mechanism for
  suppression, shelving, overrides and inhibits (Section 2.2.2), and that
  highly managed alarms need stricter control of shelving, out-of-service
  handling and change (Section 2.5.3).
- **Shelved = operator-initiated, temporary, tracked** — *"temporarily
  suppressed, usually via a manual initiation by the operator, using a method
  meeting a variety of administrative requirements to ensure the shelved
  status is known and tracked."* Not a bare mute. — PAS.
- **Out of Service = distinct state, tracked like shelving** — *"also tracked
  via similar administrative requirements to a shelved alarm."* — PAS.
- **Unauthorized suppression is a monitored condition** — *"It is possible,
  and unfortunately common, to suppress an alarm outside of the proper work
  practices, and the detection of such undesirable situations is part of the
  Monitoring life cycle stage"* (IEC 62682 16.4 Unauthorized alarm
  suppression). A suppression feature without detection/audit violates the
  standard's intent. — PAS + IEC 62682 preview.

## 4. What this means for HealthCore (synthesis)

HealthCore today renders **every firing Prometheus alert** as a severity tile
+ a Current Problems row, under one verdict line. Mapped against the verified
findings, four things follow:

1. **"Firing alert" ≠ "alarm".** The standards' load-bearing definition is
   that an alarm *requires an operator response* (§3b). A raw Prometheus feed
   mixes actionable conditions with informational/expected-noise series. The
   central WP-H move is a **rationalization split**: each surfaced alert is
   either an *alarm* (needs response → front page) or an *alert/info* (no
   response → segregated, one click away). This is the operator's "no
   non-required info on the front page" restated in standards terms. EEMUA 191
   supports the split (Sections 1.1, 1.4 and 2.3.4, and Figures 7 and 9). It
   calls the no-response class an *alert*. This document says "info" for that
   class, to avoid confusion with a Prometheus alert.

2. **Collapse severity to a small priority set with a sane distribution.**
   The secondary-sourced ISA/IEC target is **3-4 priorities, skewed ~80/15/5**
   (§3a, via ProcessVue — not checked against EEMUA 191; see Section 7.3.2,
   not checked here). A Prometheus-native console
   maps cleanly onto the Google SRE **two-tier page-vs-ticket** urgency model
   (§3b, verified), which this doc extends with a **separate
   non-actionable/info class** (a synthesis from the alarm definition in §3b,
   not something Google itself prescribes) — giving a practical page-now /
   attend-soon / info split rather than mirroring raw Prometheus `severity`
   labels. The ~80/15/5 target doubles as a **KPI / design smell**: if most
   tiles are "high", the surface communicates no priority. EEMUA 191 names
   inconsistent prioritisation as a problem, because operators then cannot
   tell which alarm to handle first (Section 1.3). The distribution figures
   themselves are not checked against EEMUA 191.

   **Qualification from EEMUA 191.** The three-bucket split stands, but the
   rule for the middle bucket changes. An alarm needs a *timely* response. A
   condition that can wait, such as one the Google model sends to a ticket for
   the next working day, is an alert under EEMUA 191 and never an
   alarm (Sections 1.4 and 2.3.1, Figure 9). An "attend-soon" item belongs in the
   alarm buckets only when it needs a timely response, which EEMUA 191 describes
   as "look at this soon" (Section 1.4). Ticket-class conditions belong in the
   info class. Apply this rule to the Attention bucket in §5.

3. **The verdict line + counts are the legitimate L1; everything else is one
   click away.** Per-operator-console KPIs are standardized (§3b, IEC 62682 Clause 16),
   and the "at-a-glance" overview should carry only the required-at-a-glance
   content. Concretely for HealthCore L1: **the single verdict + a
   priority-bucketed count of open alarms + the top N problems**. Rates,
   full lists, history, per-instance detail, and info-class alerts move to a
   deliberate second step (Console UX Constitution Art. 6).

4. **Do NOT add Ack/shelve/mute/OOS in v0.2.** This is the strongest verified
   result (§3d, 3-0): shelving, out-of-service, and designed suppression are
   three separate mechanisms, each requiring functional rules, tracking, a
   dedicated display, and unauthorized-suppression detection (IEC 62682; the
   matching EEMUA 191 sections are not checked). A half-built
   "mute" would be actively non-conformant. The v0.2 HealthCore must stay a
   **raw, honest, un-silenceable surface** — which is exactly the current
   #174 stance (no Ack). Silencing/lifecycle graduates only via the future
   **Alarm Philosophy** spec (Constitution Art. 4 detail pointer), which this
   doc feeds.

## 5. Concrete deltas for WP-H (proposed; operator to confirm)

Front page (L1), keep only:
- the single **verdict line** (unchanged);
- **priority-bucketed counts** over a collapsed 3-bucket scheme
  (e.g. Urgent / Attention / Info-segregated), Info excluded from the "are we
  OK?" verdict. Attention holds only alarms that need a timely response (§4,
  point 2);
- **top N current problems** (alarms only, i.e. actionable), deterministically
  ordered by priority then firing time.

Move one click away (a "Details"/"All signals" step):
- the full Current Problems list, the info/non-actionable alerts (visually
  segregated as a separate class, never mixed into the alarm list),
  per-instance detail, and any rate/history KPI panel.

Add (small, honest):
- a **priority-distribution / count sanity indicator** (optional, L2): if the
  live distribution is far from ~80/15/5, that itself is a rationalization
  smell worth surfacing to an admin — not to the front page. The 80/15/5 figure
  is not checked against EEMUA 191; confirm it against Table 15 in
  Section 7.3.2 before you build this indicator.

Explicitly do NOT add: Ack, shelve, mute, snooze, out-of-service, or any
per-alert hide. Those are blocked on the Alarm Philosophy spec.

Visual (only if in scope, and verify first): keep the neutral/low-chroma
background with saturated colour reserved for abnormal tiles (high-performance
HMI discipline) — but re-verify §3c sources before touching colour tokens.

## 6. Feeds the Alarm Philosophy spec (not v0.2 UI)

The following are out of v0.2 scope but are the spec's future backlog. The
**clause structure** each maps to is verified in §3d/§3a (IEC 62682
11.7/11.8/11.9 + 16.4, Clause 6/9/16); the **operational specifics** in
parentheses marked "(secondary)" come from ISA-18.2 secondary sources that
were fetched but not vote-verified in this run, so the spec must re-verify
them before treating them as standard-derived: a documented **prioritization
method** + **alarm-class definitions** (rationalization, IEC 62682 Clause
6/9); **shelving** — tracked state + dedicated display (11.7), with
operator-initiated auto-return *(secondary)*; **out-of-service** — distinct
tracked state + display (11.8), with a permit/renewal process *(secondary)*;
**suppressed-by-design** (11.9); **unauthorized-suppression detection** as a
monitoring lane (16.4); and a **KPI panel** (rates, flood %, stale, priority
distribution — Clause 16). None of these should appear, even partially, in the
v0.2 raw-alert surface. EEMUA 191 (2024) has sections with matching titles:
6.3 (suppression), 6.5 (shelving, including release) and 7.4 (performance
metrics and KPIs). They were seen in the contents only and not checked. Read
them before the spec adopts any figure.

## 7. Source inventory (22 fetched; quality as rated by the harness)

Checked directly: EEMUA 191, 2024 edition (primary; contents pages and
Sections 1 to 2.7.2, read 2026-11-08).

Verified-source subset (carried a 3-0 confirmed claim): IEC 62682:2022 preview
(primary), Google SRE Workbook (primary), ProcessVue KPI paper (secondary,
ISA-18.2 committee author), PAS "Understanding ISA-18.2" via isa.org
(secondary), Yokogawa/Control-Engineering ISA-18.2 (secondary).

Other fetched (available for the §3c visual-design second pass + WP-H):
Rockwell Process HMI Style Guide WP023 + WP014; PAS High-Performance HMI
overview (isa.org); ISA-101 summaries (hmilibrary.com, yokogawa.com,
malisko.com); Corso Systems HP-HMI Handbook parts 1-2; RealPars HMI colours;
AutomationWorld "going gray"; exida "Journey Not a Destination", "When Good
Alarms Go Bad", Alarm Philosophy sample, alarm-shelving eBook; Inductive
Automation/PAS ISA-18.2 mirror; symestic MES alarm-management; aeSolutions
urgent-alarm-reduction whitepaper.

Full URLs are in the run output (§2). The two primary sources:
- IEC 62682:2022 preview — <https://cdn.standards.iteh.ai/samples/103485/6f7b44e368fc4f4d93216f716a51771a/IEC-62682-2022.pdf>
- Google SRE Workbook, Alerting on SLOs — <https://sre.google/workbook/alerting-on-slos/>

## 8. Honest limitations

- **The original run did not read EEMUA 191 directly** (paywalled). The
  2026-11-08 check read the 2024 edition for the contents pages and
  Sections 1 to 2.7.2 only. The rate bands, flood tolerance and priority
  distribution are still quoted via ProcessVue, whose author is an ISA-18.2
  committee voting member — reputable, but a secondary. The p.96 and p.97 page
  numbers belong to the 3rd edition and do not apply to the 2024 edition. Cite
  the 2024 edition by section for the statements listed in the "Checked
  against" note. For the rest, cite the secondaries, and keep the unchecked
  figures out of UI copy and ADRs until someone checks them against Chapter 7.
- The specific IEC 62682 Table 5/Table 6 **numbers** sit beyond the preview
  boundary (pp. 83-85); only the *table titles + clause structure* are
  primary-verified. The numeric targets come from the ISA-18.2 secondaries.
- §3c (visual design) is under-verified — see the gap note.
- 10 claims abstained on token limits (not refuted); they duplicate confirmed
  content. If a future round wants belt-and-suspenders, resume the workflow
  after 19:20 Europe/Berlin (2026-07-06) to clear them.
