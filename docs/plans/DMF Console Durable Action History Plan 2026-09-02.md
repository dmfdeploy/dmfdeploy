---
status: active
date: 2026-09-02
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/496
---
# DMF Console Durable Action History Plan (2026-09-02)

> **STATUS: ACTIVE — one read-only round that demonstrates the mechanism.**
> **Rescoped by operator decision, 2026-09-02**, after the original three-round
> spec: *"for the demo I would be fine to just have a timeline of the sentences,
> who did what when. Later we can investigate a proper solution … just to
> demonstrate the mechanism."*
>
> **This does not close #496.** It closes a demo slice. The terminal-outcome
> producer, the structured envelope, and D7 retention all stay open — §5 keeps
> them as one coherent deferred piece rather than deleting them.

## 1. The bar

> **Perform an action in one browser. Open the console in a different browser (or
> a fresh incognito session, or another machine). The action is there.**

Env-rebuild survival is **not** required (operator, 2026-09-02) — short retention
is fine. What must change is that the record is **server-side, not per-browser**.

## 2. Why this is not a shortcut architecture

The operator's standing rule is that the demo shows a system meant to run in
production, so a store existing only to make the video work is the wrong answer.
That rule was already applied once this round: an in-memory ring serving the
history lane was proposed and rejected, because the spec assigns the ring to the
**live bus** and history to **Loki** — a ring would substitute the hot tier for the
cold tier and lose everything on a pod restart at `replicas: 1`.

**Reading the existing Loki records is a different case, and it passes.** The
architecture is the production one, end to end: audit line → stdout → Promtail →
Loki → console queries it back, server-side, behind the console's own auth. What
is interim is **only the payload format**.

| Survives the proper solution | Thrown away |
|---|---|
| Transport, storage, retention, the read path, the auth boundary, the lane itself | One parser |

Compare the cost of the alternative — converting the emitter to structured JSON
would break **15+ existing `caplog` tests across ten files**, which `main.py`'s own
comment records as the reason it stayed printf. This route is both cheaper *and*
less disruptive, and it is the same shape as what replaces it.

## 3. What already exists — measured, not assumed

Re-verified read-only against the live sandbox twice on 2026-09-02, hours apart:

| | Reading 1 | Reading 2 |
|---|---|---|
| Retention | 168h (7d), `retention_enabled: true` | **unchanged** |
| Loki disk | 1008 MB | **1007 MB** |
| Node free | 26 G of 59 G | **unchanged** |
| Restarts | 0 (17d uptime) | **0** |

It went **down** 1 MB between readings — genuine steady state, deletion keeping
pace, not slow growth. Sandbox values come from `dmf-env/bin/init-wizard.sh`
(5Gi, 168h general, 168h security) and are rendered into the generated inventory
so a standalone monitoring re-run stays sandbox-fit.

> **Point-in-time, not a guarantee.** A direct `dmf-infra` invocation with a
> different or missing inventory can restore the 720h/50Gi role defaults. Verify
> rendered values as a preflight; do not run the bare role against this env.

**The console's lines already reach Loki** — 958 lines/hour for
`{namespace="dmf-cms"}`, labelled `namespace`, `job`, `app`, `container`, `pod`,
`node_name`, `level`, `stream`. Collection is not the gap. **No producer change is
needed for this round.**

**And the records are already field-structured**, not free prose
(`main.py:952-1001`):

```
awx write: action=%s actor=%s role=%s real_role=%s request_id=%s
           target=%s reason=%r outcome=%s workload=%s capacity=%s
```

## 4. The round

**Scope: read path only. Zero producer changes. Zero infra changes.**

### 4.1 The query — match on content, not on logger

```
{namespace="dmf-cms", job="dmf-cms/dmf-cms"} |= "awx write:"
```

> **Do not filter on `logger="dmf_cms.audit"`.** The **auto-rollback** dispatch at
> `main.py:2499-2503` emits the identical `awx write:` shape on the **module
> logger**, not the audit child logger. A logger-field filter silently hides it —
> an action the system took and did not show. Content matching catches both
> producers. This is the one place where the cheaper filter is also the more
> correct one.

Parse the `key=value` fields for the lane. Nine split trivially; **`reason=%r` is
a Python repr** — quoted, may contain spaces and escapes — so parse it last and
tolerantly, and never let a malformed `reason` drop the whole row.

### 4.2 The endpoint

An authenticated `GET /api/audit/events` (or equivalent) over Loki `query_range`.

- **The backend builds the selector.** Never accept caller-supplied LogQL, a
  caller selector, or an unbounded `start`/`end`.
- **Bound everything** — query timeout, maximum range, maximum results.
- **A Loki outage must render differently from an empty history.** "Nothing
  happened" and "we could not ask" are different statements.

**Retrieval is two queries, not one — and that is forced by the join.** A single
bounded result set will routinely contain a recent auto-rollback whose parent
deploy is *older than the cap*. The join in §4.3 would then fail, authorization
would exclude the row, and **AC 3 could not pass** — a bounded query and a
parent join cannot both be satisfied by one retrieval.

1. **Primary query** — bounded, **newest-first**, over the requested window.
2. **Collect the distinct `linked_request_id` values** from any auto-rollback rows
   in that result. Deduplicate; this set is small (one per auto-rollback).
3. **Targeted parent lookup** — a second query filtered to those specific ids
   (`|= "request_id=<id>"`), scoped to the **full retention window**, not the
   display window. It is bounded by the number of distinct parents, not by stream
   volume, so it does not reintroduce an unbounded read.
4. Cap the parent-lookup count too, and if a parent is still not found — genuinely
   aged out of retention — **exclude and disclose**, per §4.3's stated limit.

> **Do not solve this by paginating the primary query.** Walking back through the
> stream until every parent is found is unbounded in the volume dimension, which
> is the thing the cap exists to prevent. The targeted lookup is bounded by a
> count the result set already tells you.

> **The browser never talks to Loki.** It calls `dmf-cms` same-origin with its
> session cookie; `dmf-cms` reaches Loki over cluster DNS. Loki runs
> `auth_enabled: false` with no application auth, so anything exposing it would
> permit an unauthenticated read of every stream in that tenant. It is a ClusterIP
> today — keep it that way.

### 4.3 Authorization — and the target field is not uniform

**Decision (operator, 2026-09-02): show events whose target the user is already
authorized to read**, reusing the existing per-workload read check. No new
permission model. Applied **server-side after the parse**, never by widening the
selector.

> **`target` is not always a workload slug**, and assuming it is would silently
> drop rows. **`rollback` and auto-rollback carry a run ID** (`main.py:5168`,
> `:5196`, `:2502`). The two rollback kinds resolve differently, and the
> difference is load-bearing — an earlier draft of this plan excluded *all*
> unresolvable rows while also requiring auto-rollback rows to appear, which is
> self-contradictory.

**Resolution rules, in order:**

| Record | Resolves how |
|---|---|
| Normal actions (deploy, teardown, switch, purge, clear) | `workload=` is populated on dispatch (`main.py:4794`, `:4936`); early refusals carry a workload key in `target=`. Apply the read check directly. |
| **Auto-rollback** (`actor=system:auto-rollback`, 2 sites: `main.py:2501`, `:2510`) | `workload=` is **empty**, but both sites emit **`linked_request_id`** — documented at `main.py:2428-2432` as tying back to *"the failed deploy's own request_id for correlation."* **Join `linked_request_id` → the deploy record's `request_id`**, take that record's `workload=`, and apply the read check to it. Durable: the join is Loki-to-Loki, needing no in-memory store. |
| **Operator-initiated `rollback`** (`main.py:5168`, `:5196`) | Carries **neither** `workload=` **nor** `linked_request_id`. **Not resolvable this round** — exclude, and say so. |

> **The join's one limit, stated rather than discovered.** It only resolves while
> the linked deploy record is still inside the retention window — a rollback near
> the 7-day boundary may have lost its parent. Treat an unresolvable join exactly
> like an unresolvable target: exclude and disclose.
>
> **Whatever is excluded, the lane's own description must say so.** A feed that
> silently omits rollbacks while presenting as complete is the untruth this work
> exists to remove. Full run-ID → workload resolution, which would cover the
> operator-initiated case, is deferred with §5.

### 4.4 Honest labelling — the load-bearing requirement

**`outcome=` semantics are PER ACTION, not uniform.** An earlier draft of this
plan said the field is *always* an acceptance mode and never a terminal verdict.
That is wrong, and wrong in the worst place — it would have mislabelled
**switch-source, the north-star demo beat**, as perpetually in flight when it had
in fact succeeded. The spec's own mapping table governs:

| Record | `outcome` is | Render as |
|---|---|---|
| **Watched actions** — deploy, teardown, rollback, finalise-purge (`_WATCHED_ACTIONS`) — at `outcome=launched`/`dispatched` | **acceptance only.** AWX took the job, a watcher attached, *nothing about the run is known yet* | in flight — **never** a verdict |
| **switch-source** — runs **synchronously** before the audit line is written | **terminal.** `active` → `succeeded`; `failed_rollback_required` → `failed`; a `SwitchSourceError.code` → `failed` | a real outcome |
| **Any precondition/validation refusal**, any action (`capacity-denied`, `facility-busy`, `template-not-found`, `awx-not-configured`, `awx-error:<status>`) | **terminal.** The action did not happen, full stop | `failed`, with the raw string as detail |
| **`launch`** | **explicitly unresolved by the spec** — its sync branch's `launched` may map to `succeeded` or `in-progress`, and the spec forbids answering by analogy to the watched actions | **do not claim either.** Show it without a verdict |

> **This is the good news in the round.** Switch-source already carries a true
> terminal outcome today, so the demo's key beat can honestly read *succeeded* —
> no producer change needed. Preserve the raw `SwitchStatus` value as the detail;
> it is spec-locked per `switch_source.py` §6.1 and **never renamed** to match the
> `outcome` enum.

**What genuinely has no outcome is the watched actions.** For those the watcher
updates `OperationStore` and emits no audit event, so the lane says **actions
taken**, not results — and must not imply completion.
- The window is **7 days** — not the 30 the spec currently mandates
  (dmfdeploy/dmfdeploy#530, must be resolved before this ships). Derive it from
  deployed retention rather than hardcoding.

## 5. Deferred as one coherent piece — the proper solution

Not dropped, not reconsidered — **not this round**:

- **The terminal-outcome producer.** The actual heart of #496: *records dispatch
  but never outcome*. Needs the immutable context/correlation handoff into the
  async watcher — including reattachment — defined so the pair cannot misjoin or
  lose metadata.
- **The structured CloudEvents envelope**, and with it the `caplog` migration.
- **`OperationState → outcome`/`outcome_detail` mapping**, including
  `RUN_STATUS_UNKNOWN` and the rollback states.
- **A dedicated stream label.** `dmf-cms-audit` does **not** match the shipped
  `{job=~".+-security"}` selector, so it grants no D7 retention; `dmf-cms-security`
  does match — which is exactly why it must not go on a 7-day profile. Either
  needs a Promtail rule, so an infra release, which re-introduces #282.
- **Proper run-ID → workload resolution** (§4.3).
- **Full ADR-0028 D7** — six-month hot security retention plus near-real-time
  12-month WORM object-lock.

  > **Deferred, not dropped.** Operator ruling, 2026-09-02: rigorous WORM and
  > audit-retention constraints are **out of scope for this sandbox demo**, and
  > are **valid and not off the table**. D7 remains an accepted decision a
  > production profile must meet. A later reader must not cite this plan as
  > evidence D7 was reconsidered or softened — it was scoped out of one
  > environment — and no surface may present this slice as an audit trail
  > carrying a guarantee it does not have.

**No new ADR is required** for this round or for the deferred work: the transport
and hot/cold tiering are already authorised by the Audit and Event-Log Spec, and
ADR-0028 D7 is an accepted decision whose console-side implementation is unmet.
Freeze 1 names no durable-audit non-goal.

## 6. Also out of scope

- **dmfdeploy/dmfdeploy#419** — security-scoped Recent Changes over global audit
  history. Related in intent, materially larger; must not be silently absorbed.
- **A bespoke persistence layer.** See §2.
- **dmfdeploy/dmfdeploy#523** (`.btn-secondary` hover darkens). Real, not this plan's.

## 7. Acceptance

1. An action performed in browser A is visible in a fresh browser B. *(§1)*
2. **`outcome=` is rendered per action, per §4.4's table** — switch-source shows a
   real terminal verdict (`succeeded`/`failed`) with its raw `SwitchStatus` as
   detail; watched-action `launched`/`dispatched` shows as in flight and never as
   completion; refusals show as `failed`; `launch` shows no verdict. A blanket
   rule in either direction fails this criterion. *(§4.4)*
3. **Auto-rollback events appear**, resolved via the `linked_request_id` join —
   proving both that the query did not filter on the audit logger *(§4.1)* and
   that the join survives the authorization projection *(§4.3)*. Operator-initiated
   `rollback` is **not** expected to appear; it is excluded and disclosed.
4. The lane's stated window matches deployed retention. *(#530)*
5. Rows whose target cannot be resolved are excluded **and the lane says so**.
   *(§4.3)*
6. Loki is unreachable from the browser; the endpoint builds its own selector,
   accepts no caller LogQL or unbounded range, and bounds timeout/range/results.
   *(§4.2)*
7. A Loki outage renders **differently from** an empty history. *(§4.2)*
8. Retention and free disk unchanged from §3 at release. *(§3)*
