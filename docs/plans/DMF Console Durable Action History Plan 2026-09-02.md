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

> **The browser never talks to Loki.** It calls `dmf-cms` same-origin with its
> session cookie; `dmf-cms` reaches Loki over cluster DNS. Loki runs
> `auth_enabled: false` with no application auth, so anything exposing it would
> permit an unauthenticated read of every stream in that tenant. It is a ClusterIP
> today — keep it that way.

**Retrieval mechanism is the implementer's, not this plan's.** §7's acceptance
criteria state the properties the retrieval must satisfy; how it satisfies them —
one query or two, ordering, pre-filtering, parse strategy — is a coding decision
with a real feedback loop, and it belongs where it can be run and tested rather
than argued in prose.

> **Two known traps, recorded as hazards rather than prescriptions**, because
> they were found the expensive way and are cheap to hand over:
>
> - **A bounded result set and the §4.3 parent join are in tension.** The parent
>   deploy is by definition older than its auto-rollback child, so any retrieval
>   that caps by recency can return the child without the parent.
> - **`linked_request_id=<id>` contains the substring `request_id=<id>`.** A
>   boundary-unaware match will select the rollback row *as its own parent* — with
>   a blank `workload`, so authorization then drops it. Same family as
>   `text-accent\b` also matching `text-accent-blue`.
>
> Both are covered by AC 3: if the implementation trips either, that criterion
> fails. Neither is a licence to reintroduce an unbounded read.

### 4.3 Authorization — and the target field is not uniform

**Decision (operator, 2026-09-02): show events whose target the user is already
authorized to read.** No new permission model. Applied **server-side after the
parse**, never by widening the selector.

> **Corrected 2026-09-02: there is no existing per-workload read check to reuse.**
> This sentence previously said there was. What the source actually offers is
> `_require_min_role` (role tier), `_require_media_workloads_access` (surface
> role/group), `MediaTenancySettings.tenants_for` (group → tenant mapping), and the
> tenant-scoped service filtering in `media_workloads._fetch_services` — which fails
> closed to empty when nothing maps. None of these is a per-record read check keyed on
> an audit row's target. **The parent Audit and Event-Log Spec also leaves binding
> rendered authorization to records open.** So the operator's decision stands, and the
> projection from a record's target to a user's scope is **open work in this round**,
> not a lookup of something already built. Treat it as a security contract to settle,
> and say which surface you bound it to.

> **`target` is not always a workload slug**, and assuming it is would silently
> drop rows. **`rollback` and auto-rollback carry a run ID** (`main.py:5168`,
> `:5196`, `:2502`). The two rollback kinds resolve differently, and the
> difference is load-bearing — an earlier draft of this plan excluded *all*
> unresolvable rows while also requiring auto-rollback rows to appear, which is
> self-contradictory.

#### What the fields actually contain — enumerated, not assumed

**Corrected 2026-09-02 (orchestrator), after this section's original claim failed
against the emitter.** It read: *"Normal actions (deploy, teardown, switch, purge,
clear) — `workload=` is populated on dispatch (`main.py:4794`, `:4936`)."* **Of the 94
`_audit_awx_write` call sites, 7 pass `workload=` at all: 2 `deploy` sites — precisely
the two lines that claim was citing — and 5 `switch-source` sites, which pass a
*source*.** Every other site, including all 14 `teardown` and all 18 `finalise-purge`,
omits it. The emitter's own docstring says so directly: *"an optional trailing field,
blank when omitted, so existing callers (launch, teardown) need no changes."*

Every call site, by what it passes. **These are source-level argument counts — which
sites pass the argument, not whether the value arrives populated.** `workload` is
optional at runtime (`:384`), so a site in the "sets it" column can still emit a blank
field; that distinction matters for the auto-rollback join below.

| `action=` | sites | `target=` is | `workload=` is |
|---|---|---|---|
| `deploy` | 28 | catalog `key` | **absent on 26**; the requested workload on 2 (`:4794` dispatched, `:4936` launched) |
| `teardown` | 14 | catalog `key` | **absent on all 14** |
| `finalise-purge` | 18 | `slug` | **absent on all 18** |
| `switch-source` | 6 | the **receiver** `instance` | **`source_instance` on 5** — a *source*, not a workload — absent on 1 |
| `rollback` | 12 | `run_id` | absent on all 12 |
| `launch` | 8 | `workflow_name` | absent on all 8 |
| `verify-drain` | 7 | `run_id` | absent on all 7 |
| computed `mapped_action` | 1 | `catalog_key` | absent |

The counts come from an AST pass over `main.py`, independently reproduced by a second
tokenizer pass: 95 references, 1 definition, **94 direct calls**, no `**kwargs` spread,
no positional `workload`, and no **production** call site outside `main.py` — one test
(`tests/test_awx_write_gate.py:337`) calls the helper directly. Note the denominator's
qualifier — those are `_audit_awx_write` call sites. Counting **all** `awx write:`
producers gives **96**, because the two auto-rollback lines below emit the same prefix
directly on the module logger. The field shapes are corroborated by the emitter
docstring and by author-observed Loki rows on the sandbox (`action=teardown
target=<key> workload=` and `action=switch-source target=<receiver> workload=<source>`),
the latter recorded by observation rather than reproduced here.

**What follows from the table — stated as facts, not as a rule:**

- **`workload=` is not a uniform workload identifier across these call sites.**
  Precisely: `teardown` and `finalise-purge` **never** set it;
  `rollback`, `launch` and `verify-drain` never set it; `deploy` sets a genuine
  requested workload on **2 of 28** sites; and `switch-source` sets it on 5 of 6 — but
  to a **source**, not a workload. So it is neither absent enough to ignore nor present
  enough to key on, and the earlier absolute in this section ("four of them never set
  it") was itself wrong in both directions.
- **`clear` is audited, but not in this stream.** It emits no `awx write:` line and no
  `action=clear`; `main.py:5638` emits a separate **`media-workloads clear:`** line on
  the plain module logger, with a different envelope entirely — `instance=` instead of
  `target=`, no `action=`, no `workload=`, and `outcome` from `result.get("error", "ok")`,
  so a successful clear logs `outcome=ok`. It is therefore outside the §4.1 query, not
  unaudited. The superseded row named it as a normal action of this lane; it is not one.
- **`verify-drain` is real and unhandled.** Seven sites (`main.py:5351-5400`),
  `target=run_id`, `workload` absent. It is named nowhere else in this plan, and
  **§4.4 does not classify its outcomes** — so the lane must either classify it or
  state its exclusion, under the same honesty rule as §4.3's other exclusions.
- **A successful auto-rollback join can still yield nothing**, which the row below did
  not anticipate. It resolves by taking the parent deploy record's `workload=` — and
  **26 of 28 `deploy` sites omit that field.** Two parents can therefore join correctly
  and land on a blank workload:
  - **the `already-active` reattach** (`:4835`). It omits `workload=`, and it *is*
    watched — `_track_sync_reattach` at `:4829` creates the tracked operation — so it
    can reach the auto-rollback trigger like any other watched deploy.
  - **the two dispatch sites themselves** (`:4794`, `:4936`). They pass the argument,
    but the value is optional at runtime — `workload = body.get("workload") if body is
    not None else None` (`:384`) — so a request that omitted it renders blank.

  *(Corrected: an earlier draft of this bullet blamed refusal parents. That is
  impossible. `_maybe_auto_trigger_rollback` has exactly one call site, `:2324`, inside
  the `FAILED_ROLLBACK_REQUIRED` branch — the job started and then failed. A refusal
  never creates a watched deploy, so it can never have an auto-rollback child. The fact
  was right and the mechanism invented; the two causes above are the real ones.)*

  Retention is therefore **not** the only way that join fails, and neither §4.3 nor
  AC 3 may imply every auto-rollback is resolvable.

**Which field resolves which action is the implementer's call**, on the same
reasoning §4.2 gives for retrieval: it is a coding decision with a real feedback loop.
The table above is the input; AC 3 and AC 5 remain the test.

**Resolution rules, in order:**

| Record | Resolves how |
|---|---|
| Normal actions (deploy, teardown, switch-source, finalise-purge) | **The fields are not uniform across these four — see the table above, which is the input to this decision.** Resolve to a scope the authorization check built for this lane can accept, then apply it. **"The read check" below and here means that check — the one this round designs, not an existing primitive**; see the correction above. |
| **Auto-rollback** (`actor=system:auto-rollback`, 2 sites: `main.py:2501`, `:2510`) | `workload=` is **empty**, but both sites emit **`linked_request_id`** — documented at `main.py:2428-2432` as tying back to *"the failed deploy's own request_id for correlation."* **Join `linked_request_id` → the deploy record's `request_id`**, take that record's `workload=`, and apply the read check to it. Durable: the join is Loki-to-Loki, needing no in-memory store. |
| **Operator-initiated `rollback`** (`main.py:5168`, `:5196`) | Carries **neither** `workload=` **nor** `linked_request_id`. **Not resolvable this round** — exclude, and say so. |

> **The join's limits — two, not one.** *(Corrected 2026-09-02: this said "one".)*
> It only resolves while the linked deploy record is still inside the retention
> window, so a rollback near the 7-day boundary may have lost its parent — **and**,
> per the bullet above, a parent found inside the window may itself carry a blank
> `workload=`, because only 2 of 28 `deploy` sites populate it. Treat an unresolvable
> join, from either cause, exactly like an unresolvable target: exclude and disclose.
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
| **Any precondition/validation refusal**, any action (`capacity-denied`, `facility-busy`, `template-not-found`, `awx-not-configured`, `awx-error:<status>`) | **terminal.** The action did not happen, full stop | `failed` — **plain-language copy at default; the raw string is expert-only.** See §4.5 |
| **`launch`** | **explicitly unresolved by the spec** — its sync branch's `launched` may map to `succeeded` or `in-progress`, and the spec forbids answering by analogy to the watched actions | **do not claim either.** Show it without a verdict |

> **This is the good news in the round.** Switch-source already carries a true
> terminal outcome today, so the demo's key beat can honestly read *succeeded* —
> no producer change needed. Preserve the raw `SwitchStatus` value as the detail;
> it is spec-locked per `switch_source.py` §6.1 and **never renamed** to match the
> `outcome` enum.

**What genuinely has no outcome is the watched actions.** For those the watcher
updates `OperationStore` and emits no audit event, so the lane says **actions
taken**, not results — and must not imply completion.

### 4.5 Disclosure split — raw errors are expert-only

The spec resolves this (§ *Disclosure split — expert vs. default*), quoting
Constitution **Art. 8** verbatim: *"Raw/system errors never leak at default.
Every default error tells the operator three things: what happened, what it
means for the facility, and what to do next (or who to call). Raw detail is
available at expert level only."*

**This read path must not become the leak.** The parsed record carries exactly
the strings the split makes expert-only — `awx-error:<status>`, `awx-not-configured`,
`template-not-found`, and any `downstream_refs` — so rendering `outcome_detail`
straight into the lane would breach it by default.

| Level | Shows |
|---|---|
| **Default** | `action`, `target`, plain-language `outcome`, `reason` — plus, for a failure, **what happened, what it means for the facility, and what to do next** |
| **Expert** | the raw `outcome` error class/message, `downstream_refs`, AWX job-event text |

**One record backs both views** (Art. 1: *one truth, two resolutions, never two
records*) — expert detail is a transform layered on the same row, never a second
row or a second query. Design the default rendering first; the expert view is
the addition.

> **The mapping from raw class to operator-facing copy is required work in this
> round, not a follow-up.** Without it there are only two options at default —
> leak the raw string, or show a failure with no explanation — and both are
> defects. `facility-busy` is *"another operation is using this facility; wait
> for it to finish"*, not `facility-busy`.
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
   real terminal verdict (`succeeded`/`failed`); watched-action
   `launched`/`dispatched` shows as in flight and never as completion; refusals
   show as `failed`; `launch` shows no verdict. A blanket rule in either direction
   fails this criterion. *(§4.4)*
2a. **No raw system error string appears at default level** — not
   `awx-error:<status>`, not `awx-not-configured`, not any `downstream_refs`. Each
   failure shows what happened, what it means for the facility, and what to do
   next; the raw class is reachable only at expert level, off the same record.
   *(§4.5)*
3. **An auto-rollback event appears in the lane with its workload resolved** —
   which is only possible if the query did not filter on the audit logger *(§4.1)*,
   the parent deploy was retrieved despite being older than the child, the
   *parent* was selected rather than the child, and the row then survived the
   authorization projection *(§4.3)*. **Test this against a real auto-rollback,
   not a synthetic row** — it is one assertion covering four ways to get the
   retrieval wrong. Operator-initiated `rollback` is **not** expected to appear;
   it is excluded and disclosed.
4. The lane's stated window matches deployed retention. *(#530)*
5. Rows whose target cannot be resolved are excluded **and the lane says so**.
   *(§4.3)*
6. Loki is unreachable from the browser; the endpoint builds its own selector,
   accepts no caller LogQL or unbounded range, and bounds timeout/range/results.
   *(§4.2)*
7. A Loki outage renders **differently from** an empty history. *(§4.2)*
8. Retention and free disk unchanged from §3 at release. *(§3)*
