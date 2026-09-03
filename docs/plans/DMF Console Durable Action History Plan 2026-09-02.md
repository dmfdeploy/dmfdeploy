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
(`main.py:952-1001`). The shape as this plan was written:

```
awx write: action=%s actor=%s role=%s real_role=%s request_id=%s
           target=%s reason=%r outcome=%s workload=%s capacity=%s
```

> **Superseded during implementation, 2026-09-03 — this shape is no longer what
> is emitted or accepted.** Every externally-influenced field is now quoted and
> the line carries an explicit format marker:
>
> ```
> awx write: fmt=2 action=%s actor=%r role=%s real_role=%s request_id=%s
>            target=%r reason=%r outcome=%s workload=%r capacity=%r
> ```
>
> `action`, `role`, `real_role`, `request_id` and `outcome` stay unquoted because
> each is code-generated with a constrained shape; `target`, `actor`, `workload`
> and `capacity` are externally sourced and are now boundary-proven rather than
> boundary-guessed. **A line without a well-formed `fmt=2` marker is not
> rendered.** See §4.1a for why.

## 4. The round

**Scope: read path, plus a producer change that implementation proved
unavoidable. Zero infra changes.**

> **Corrected 2026-09-03.** This section originally read *"read path only, zero
> producer changes"*, and that is no longer true — the record of what was built
> must say what was built. Seven forgery vectors were found against the
> read-path-only design, six by review and one by proof; the seventh
> demonstrated that **no reader-side check could exist**, because a forged line
> and a legitimate line can be byte-identical. See §4.1a.

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

### 4.1a Why the producer changed — the finding this plan did not anticipate

**Superseding §4.1's parsing guidance, 2026-09-03.** The instruction above is
what a reader must do when field boundaries are *inferred from content*. That
approach cannot be made safe on this format, and the implementation round proved
it rather than suspected it.

`target`, `workload` and `actor` are externally sourced. A value containing
marker-shaped text (` outcome=…`) shifted the parse of every field after it, so a
**refused** deploy could be made to render as **in flight** for an
attacker-chosen target — on well-formed input, on the normal path. Six such
vectors were found and individually closed; each fix was correct and the next
vector appeared anyway.

**The seventh ended the approach.** A forged line and a legitimate emission whose
real field values happen to match are **byte-identical**. There is therefore no
reader-side check that can separate them — not a stricter scanner, not a better
heuristic. The defect was never the parser; it was a format in which content and
syntax are indistinguishable.

So the fix moved to where the ambiguity is created:

- **The writer quotes** every externally-influenced field, making boundaries
  *proven* rather than guessed.
- **The line declares its grammar** (`fmt=2`), so the reader never infers which
  format it is reading — a second-order instance of the same disease, found
  immediately after the first was cured.
- **Records without a valid marker are not rendered.** Retained pre-change lines
  cannot be vouched for, and a durable action history must not display records it
  cannot vouch for. This deleted the legacy parser outright (**−1040 lines**).

> **The reusable finding, which outlives this lane and the transport under it:**
> *every place a reader infers structure that the writer could have stated is a
> defect waiting to be found.* It held for field boundaries, for which grammar a
> line uses, and for how the completeness guard located the code it guards — three
> instances in one round, each found only after the previous was fixed.

This does **not** pre-empt the structured envelope in §5. It is the same lesson
arriving early and cheaply, and it narrows what the envelope has left to do.

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
>   boundary-unaware match will select the rollback row *as its own parent*, whose
>   `workload` is blank — so the event still renders (it is covered by class) but
>   **silently loses its label, or worse carries one taken from the wrong record.**
>   Same family as `text-accent\b` also matching `text-accent-blue`.
>
> Both are covered by AC 3: if the implementation trips either, that criterion
> fails. Neither is a licence to reintroduce an unbounded read.
>
> *(Revised with the role-gate decision: this trap previously ended "so authorization
> then drops it". Under class membership nothing drops the row, which makes the trap
> **harder** to notice, not easier — a missing row is visible, a quietly wrong or
> absent label is not.)*

### 4.3 Authorization — and the target field is not uniform

**Decision (operator, 2026-09-02, REVISED after investigation): the lane carries the
same authorization as the actions it records — which is a gate PER RECORD CLASS, not
one gate for the lane.** A row is rendered only if the requesting user would pass the
gate that action's **own endpoint** applies. Applied **server-side after the parse**,
never by widening the selector. Any class whose live endpoint is tenant-scoped is
excluded, because the record does not carry what that scoping needs.

> **Per class, because the covered actions do not share a gate.** An earlier revision
> of this decision said "role-gated" and meant a single gate. That is wrong in both
> directions, and the source is unambiguous:
>
> | action | its endpoint's gate | source |
> |---|---|---|
> | `deploy` | `_require_min_role(request, "operator")` | `main.py:4653` |
> | `teardown` | `_require_min_role(request, "operator")` | `main.py:4949` |
> | `switch-source` | `_require_media_workloads_access(request)` | `main.py:5809` |
>
> `_require_media_workloads_access` grants on `role_at_least(user.role, "engineer")`
> **or** `MEDIA_ENGINEERS_GROUP in user.groups` (`main.py:277-295`), and its own
> docstring confirms *"a real viewer in media-engineers reaches the surface"*.
>
> So one gate for the lane either **leaks** `deploy`/`teardown` history to a
> group-only viewer, or **omits** `switch-source` history from an operator outside
> that group. Neither is acceptable, and no single gate avoids both. **Auto-rollback
> takes its parent's gate** — it responds to a `deploy`, so `operator`.
>
> The principle was right and its application was not: *"the same authorization as the
> actions it records"* is only meaningful action by action.

> **The decision this replaces, and why it could not be implemented.** It read: *"show
> events whose target the user is already authorized to read."* An investigation of the
> source found **no covered action has a target→tenant binding**, so there was nothing
> to be "already authorized to read" against:
>
> | class | `target=` | tenant-resolvable? |
> |---|---|---|
> | `deploy`, `teardown` | catalog key | **no** — `catalog.py` contains no tenant field; zero occurrences of `tenant` in the module |
> | `switch-source` | receiver instance | **no** — resolved by `entry.key` match against the same catalog (`switch_source.py:684-713`) |
> | auto-rollback | joined parent deploy | **no** — the chain terminates at the same catalog key |
> | `finalise-purge` | slug | **no binding** — see below |
>
> `main.py:5779-5782` states it outright: *"deploy/teardown/launch … are role-gated
> only, no tenant scoping — the catalog has no tenant concept at all."*
>
> **`finalise-purge` is the instructive case.** It *does* have a real, correctly
> fail-closed tenant check at request time — `tenants_for(user.groups)` threaded into
> `_fetch_services_complete`, requiring the caller's visible service set to equal the
> unscoped set before dispatch (`media_workloads.py:937-980`). But that is **a check,
> not a binding**: it answers "may this caller act now", never "which tenant did this
> row belong to". The NetBox `workload:<slug>` Tag carries no tenant field
> (`media_workloads.py:918-921`); `Operation.purge_tenant_scope` records the *caller's*
> permitted slugs rather than the target's tenant, is marked INTERNAL ONLY, is not
> serialized by `to_dict()`, and lives in a `ttl_seconds=3600` in-memory store
> (`operations.py:193-199`, `:242-244`, `main.py:1055`). **One hour is not history.**
>
> So `finalise-purge` is **excluded**: its live surface is tenant-scoped, and showing
> its rows under role-based gating would disclose purge activity for tenants a scoped
> operator cannot otherwise see. That is the one place where role-gating the lane would
> genuinely widen access, and it is the one place we exclude.

**Why role-gating is honest here rather than a shortcut.** For the four covered classes
the *live* surfaces are already role-gated with no tenant scoping. A history lane gated
the same way discloses nothing a user cannot already obtain from the catalog and the
existing endpoints — it matches the system's actual access model instead of implying a
finer one. **The lane must say so**: it is a record of actions on this facility, not a
per-tenant view, and it must not present as filtered-to-you.

> **This is a demo-profile decision, not a claim about production.** A production
> profile wanting tenant-scoped history needs a tenant concept on the catalog — a data
> model change, not a read-path change. Recorded here so nobody later cites this plan as
> evidence that per-tenant audit scoping was considered and rejected. It was found
> **unimplementable against today's schema**, which is a different statement.

> **`target` is not always a workload slug**, and assuming it is silently mislabels
> rows. **`rollback` and auto-rollback carry a run ID** (`main.py:5168`, `:5196`,
> `:2502`), not a workload. The two rollback kinds are **different classes** — the
> auto one covered, the operator-initiated one excluded — so they are separated at
> membership, by `actor=`, and never by whether a target happened to resolve.
>
> *(Revised with the role-gate decision: this previously said the assumption would
> "silently drop rows" and that the two rollback kinds "resolve differently". Under
> class membership `target=` decides no row's admission at all — it only supplies a
> label. The self-contradiction this callout was written to record still stands as
> history: an earlier draft excluded all unresolvable rows while also requiring
> auto-rollback rows to appear.)*

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

#### The projection is by class, and it is fail-closed

> **Replaced 2026-09-02.** This block previously specified a *tenant-scope* projection —
> resolve each record's target into the requesting user's scopes, exclude what does not
> resolve. That is superseded by the role-gate decision above, and leaving it would have
> made the plan unimplementable: following it drops `deploy`, `teardown` and
> `switch-source` outright, since none of them resolves to a tenant at all.

The projection admits a row on **class membership**, not on target resolution:

- **Default deny by class.** A row is rendered only if its `action=` (with `rollback`
  split by actor) is in the **covered** set of AC 5a's membership table. Everything else
  is excluded: the named excluded classes, an unrecognised `action=`, a row that fails
  to parse, and any row returned by a partial or failed Loki response. **An unrecognised
  action is never defaulted into covered** — a new emitter action must be assigned in
  the table before it can appear. `_fetch_services` sets the house pattern by failing
  closed to empty; match it.
- **The per-user axis is the row's own class gate, and there is no other.** There is no
  test against anything *on* the row, because a row carries nothing to test against —
  but which gate applies **depends on the class**, per the membership table. A user
  sees every covered row in the window whose class gate they pass, and no others. That
  is one rule, not one gate: `deploy`, `teardown` and auto-rollback answer to
  `operator`; `switch-source` answers to engineer-or-media-engineers.
- **Both directions are still defects.** Rendering an excluded class is a widening of
  access — `finalise-purge` most of all, since its live surface *is* scoped. Dropping a
  covered row is a silent omission in a feed whose whole purpose is to be trusted as
  complete. Neither may be traded for the other, and omissions must be disclosed.

**The auto-rollback join survives — as display, not authorization.** Under the
superseded model the `linked_request_id` → parent `request_id` join was load-bearing for
*admitting* the row. It is not any more: an auto-rollback is covered by class. The join
now only supplies the **workload label** for the row, so its two failure modes — a
parent outside the retention window, and a parent whose own `workload=` is blank
(26 of 28 `deploy` sites omit it) — **degrade the row rather than drop it.** The event
is still shown; it shows without a workload.

> That is a strictly better outcome than the model it replaces, and worth noticing: the
> old rules excluded an auto-rollback whose parent workload was blank, which meant an
> action the system took autonomously could vanish from the record for a reason having
> nothing to do with permission.

AC 5a and AC 5b below are the test for all of this.

> **Whatever is excluded, the lane's own description must say so.** A feed that
> silently omits whole action classes while presenting as complete is the untruth this
> work exists to remove — and under role-based gating the lane must additionally not present
> as filtered-to-you. Full run-ID → workload resolution, which would cover the
> operator-initiated rollback case, is deferred with §5.

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
| **`launch`** | **EXCLUDED from the lane this round** *(decision, 2026-09-02 — see §4.3)*. Its outcome is unresolved by the spec and its `target=` is an AWX job-template name, so the row would carry neither a verdict nor a workload | not rendered — **excluded and disclosed**, per AC 5 |

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
- This lane derives its stated window from deployed retention, never a
  hardcoded number — see the [Audit and Event-Log
  Spec](../design/DMF%20Console%20Audit%20and%20Event-Log%20Spec.md)'s Art. 1
  rule for the derivation, and §3 above for this environment's measured
  value. `dmfdeploy/dmfdeploy#530` corrected the spec to this rule.

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
   show as `failed`. **`launch` is excluded from the lane this round (§4.3), so this
   criterion no longer asserts anything about it** — its former clause required
   rendering a class the membership table excludes. A blanket rule in either direction
   fails this criterion. *(§4.4)*
2a. **No raw system error string appears at default level** — not
   `awx-error:<status>`, not `awx-not-configured`, not any `downstream_refs`. Each
   failure shows what happened, what it means for the facility, and what to do
   next; the raw class is reachable only at expert level, off the same record.
   *(§4.5)*
3. **An auto-rollback event appears in the lane, and carries its workload wherever the
   parent record supplies one.** Appearing is unconditional — it is covered by class
   (§4.3), so a missing or blank parent workload degrades the row's *label*, never its
   presence. The workload half is only possible if the query did not filter on the audit
   logger *(§4.1)*, the parent deploy was retrieved despite being older than the child,
   and the **parent** was selected rather than the child — the `linked_request_id`
   substring trap. **Test against a real auto-rollback, not a synthetic row.**

   > **Revised with the role-gate decision.** This read *"appears with its workload
   > resolved"*, and required surviving an authorization projection that no longer
   > exists. As written it was unsatisfiable in the common case: 26 of 28 `deploy` sites
   > omit `workload=`, so a real auto-rollback will frequently have a parent with
   > nothing to resolve to. **Assert presence unconditionally and the label
   > conditionally**; a criterion that fails on the ordinary case is not a gate, it is a
   > false alarm.

   Operator-initiated `rollback` is **not** expected to appear; it is excluded and
   disclosed.
4. The lane's stated window matches deployed retention. *(#530)*
5. **Rows of an excluded class never appear, and the lane says what is excluded.**
   *(Revised: this read "rows whose target cannot be resolved are excluded", which
   under the role-gate model would forbid the covered classes it also requires —
   `deploy`, `teardown` and `switch-source` resolve no target at all. Exclusion is by
   class, never by resolution.)*
   The disclosure names what is excluded: **`finalise-purge`, `launch`, `verify-drain`
   and operator-initiated `rollback`** this round. **The disclosure must not flatten the
   two reasons** (§4.3's membership table): `launch`, `verify-drain` and
   operator-initiated `rollback` are out because this lane cannot render them
   meaningfully — a scope decision. **`finalise-purge` is out because including it would
   widen access** — its live surface is tenant-scoped and this lane is not. A reader
   must be able to tell which omissions are a choice about detail and which are a
   boundary. *(§4.3)*
5a. **The rendered set equals the expected set, asserted as an equality, per class
   gate.** For each user in the fixture, the lane's response must equal **exactly** the
   set of fixture rows within the window whose class is *covered* **and whose class
   gate that user passes** — nothing else. Not "contains", not "excludes" — **equal**.
   The expected set is **enumerated in the fixture, never computed by calling the
   projection under test**; deriving expectation from the code under test is a
   tautology that passes for any implementation.

   **The fixture must contain the four discriminator users**, because a generic
   allowed/denied pair cannot tell a per-class implementation from a single-gate one:

   | user | expects |
   |---|---|
   | `operator`, **not** in media-engineers | `deploy`, `teardown`, auto-rollback — **not** `switch-source` |
   | `viewer` **in** media-engineers | `switch-source` — **not** `deploy`/`teardown`/auto-rollback |
   | qualifies for **both** | every covered row |
   | qualifies for **neither** | the empty set |

   > **The first two rows are the whole point.** They are the users a single gate gets
   > wrong, in opposite directions: one gate either shows the operator-only viewer
   > `deploy` history it must not see, or hides `switch-source` from an operator outside
   > the group. A fixture without both cannot distinguish the correct implementation
   > from either failure. The third and fourth rows alone would pass a single-gate
   > implementation.

   The fixture must carry rows of **every covered class and every excluded class**, so
   that the equality tests inclusion and exclusion in the same assertion. Include at
   least one `finalise-purge` row and one `launch` row: they must appear for **nobody**,
   and `finalise-purge` is the row whose wrongful inclusion would be an actual widening
   of access rather than a cosmetic defect.

   > **Scope fixtures are gone because scopes are not the axis.** Earlier drafts
   > required A-only/B-only tenant fixtures across multiple users. The investigation
   > found no covered class has a tenant binding at all, so those fixtures would have
   > asserted against a distinction the system does not make — testing an invented
   > model rather than the real one. **The axis that exists is role, plus the
   > covered/excluded partition**, and that is what the equality now ranges over.

   > **This is stated as an equality on purpose, and the reason is the more useful part
   > of this criterion.** Written as a list of polarity assertions, it was found too
   > weak four times running — each round adding the case the previous one missed, and
   > each fix admitting a differently-broken implementation. Enumeration does not
   > converge here: there is always another combination.
   >
   > A set equality closes the class by construction. Any omission fails it, any
   > admission fails it, and the cases found the expensive way — a zero-row response,
   > a deploy-only implementation, a dropped `launch`, a user granted only one of two
   > held scopes — are all just instances of set inequality, none needing its own
   > clause. **If a future gap is found here, prefer strengthening the predicate over
   > appending a case.**

   **Membership is fixed here, exhaustively. The implementation does not choose it.**
   A partition that named its two sets without populating them left "covered" as an
   implementation's own definition — so declaring `teardown`, `finalise-purge` and
   `switch-source` excluded, disclosing them, and rendering only `deploy` satisfied the
   equality. That is the deploy-only defect again, entering through the set definition
   instead of through the fixture. **These are closed sets:**

   | Record class | | Why |
   |---|---|---|
   | `deploy` | **covered** | gate: `_require_min_role("operator")` (`main.py:4653`) |
   | `teardown` | **covered** | gate: `_require_min_role("operator")` (`main.py:4949`) |
   | `switch-source` | **covered** | gate: `_require_media_workloads_access` — engineer+ **or** media-engineers group (`main.py:5809`, `:277-295`) |
   | **auto-rollback** (`actor=system:auto-rollback`) | **covered** | responds to a `deploy`, so it inherits `operator` |
   | `finalise-purge` | **excluded — access** | its live surface **is** tenant-scoped (`media_workloads.py:937-980`) and the record carries no binding, so role-gating it would widen access |
   | `launch` | **excluded — scope of this round** | §4.4 leaves its outcome *explicitly unresolved by the spec*, and `target=` is an AWX job-template name; a row with neither a verdict nor a workload is noise in a media-workload history |
   | `verify-drain` | **excluded — scope of this round** | §4.4 does not classify its outcomes at all; `target=run_id` |
   | **operator-initiated `rollback`** | **excluded — scope of this round** | `target=run_id`, with nothing correlating it to anything else the lane shows |

   > **The two exclusion reasons are not interchangeable, and the earlier one is now
   > void.** These three were previously excluded because their target *"does not
   > resolve to a scope"* — which stopped being a reason the moment the role-gate
   > decision established that **no** class resolves to a scope. Re-justified above on
   > what actually remains true: they cannot be rendered meaningfully or honestly in
   > this lane. **That is a scope decision, not a security one**, and it is therefore
   > cheaply reversible — classifying `verify-drain`'s outcomes in §4.4 would admit it.
   > `finalise-purge` is the opposite: excluded on access grounds, and reversing it
   > requires a tenant binding that does not exist.
   >
   > Left unfixed, this would have been a live section justifying a security-adjacent
   > decision with reasoning that no longer holds — the kind of residue that reads as
   > deliberate to the next person.

   `rollback` **splits by actor** and appears in both rows above — §4.3's resolution
   table already separates the two, and partitioning on the raw `action=` string would
   place it in both sets at once. `mapped_action` is a computed name resolving to one of
   the classes above, not a class of its own.

   **A record class absent from this table fails the criterion on its face** — an action
   added to the emitter must be assigned here, and until it is, the gate reports itself
   incomplete rather than silently omitting the new rows.

   > **`launch` is EXCLUDED** *(decision, 2026-09-02)*, and AC 2's launch clause is
   > withdrawn to match. Review correctly refused to let this stand as a future
   > decision: AC 2 required rendering it while default-deny forbade admitting it, and
   > **an active plan carrying a contradiction is unverifiable**, whoever eventually
   > resolves it.
   >
   > It is decided against the source rather than by preference. `target=` is the
   > `{workflow_name}` path parameter of `POST /api/workflows/{workflow_name}/launch`
   > (`main.py:3424`) — an **AWX job-template name**, carrying no workload association,
   > with `workload=` absent on all 8 sites. Combined with §4.4 leaving its outcome
   > explicitly unresolved, the row would carry neither a verdict nor a workload, which
   > is what puts it with operator-initiated `rollback` and `verify-drain`.
   >
   > *(The original justification — that it "does not resolve to a scope" — was voided
   > by the role-gate decision, which established that no class does. The exclusion
   > survives on the rewritten grounds above; see §4.3's membership table for why the
   > two exclusion reasons must stay distinct.)*
   >
   > *(Catalog lifecycle JTs reached through this route are refused and re-audited under
   > a computed action with `target=catalog_key` (`main.py:3459`, `:3476`), so they are
   > unaffected by this exclusion.)*
   >
   > **Reversible, and named as such:** §5's deferred run-ID → workload resolution is
   > what would make these rows scopeable. If it lands, revisit all three exclusions
   > together rather than this one alone.

   > **Five implementations that passed this criterion while being broken.** Kept
   > because the sequence is the lesson, not any one of them:
   >
   > | Passed anyway | Because the criterion was |
   > |---|---|
   > | returned **zero rows to everyone** | negative-only — every "does not see" clause held |
   > | handled **`deploy` only**, dropping the rest | action-blind — one A/B pair is a `deploy` pair |
   > | dropped **`launch`** | enumerated — the fix above *listed* covered actions and missed one |
   > | gave a user **one of two held scopes** | per-user polarity, which says nothing about completeness within a user |
   > | declared most classes **excluded** and rendered only `deploy` | a partition whose sets were named but never populated — "covered" was the implementation's to define |
   >
   > Each fix was correct and each admitted the next broken implementation. The first
   > four all **appended a case to an enumeration**; the fifth got in through the *set
   > definition* after the enumeration was replaced — proof that a stronger predicate
   > still fails if its terms are left open for the implementation to define.
   >
   > **And then the sixth finding made all five moot.** The criterion had been written
   > over an **undefined term**: every version of it asserted something about rows
   > "resolving into the user's scopes" while no covered class had a tenant binding at
   > all. The scope-based rows above are kept as history, but the distinction they
   > tested does not exist in this system — they were fixtures for an invented model.
   >
   > **The lesson that supersedes the others: check that a criterion's terms are
   > defined before making the criterion stricter.** Five rounds of sharpening went
   > into an assertion whose subject was undefined, and no amount of further
   > sharpening would have exposed that — only going to the source did. A reviewer
   > asked for the binding in round 1; the request was declined as over-specification,
   > and it was the one thing that would have ended this in one round.
   >
   > Still load-bearing for the criterion as it now stands: the **equality** makes cases
   > unnecessary, and the **closed membership table** denies its terms any freedom —
   > "equals the covered rows" is otherwise satisfiable by shrinking what counts as
   > covered. Neither half works alone. *(§4.3)*

5b. **Classification failure excludes; enrichment failure does not.** The two must be
   tested as opposites, because conflating them is what made the previous version of
   this criterion contradict AC 3.

   **Must EXCLUDE — the class cannot be established:**
   a row whose `action=` is unrecognised (absent from the membership table), a row whose
   fields fail to parse well enough to classify, and rows from a partial or failed Loki
   response. **An unrecognised action is excluded, never defaulted into covered.**

   **Must still RENDER — the class is covered, only the detail is missing:**
   an auto-rollback whose parent record is outside the window, and **an auto-rollback
   whose parent carries a blank `workload=`** (the ordinary case — 26 of 28 `deploy`
   sites omit it). These render **without** a workload label. Dropping them fails this
   criterion.

   > *(Revised: both auto-rollback cases were previously listed under "must exclude",
   > directly contradicting §4.3 and AC 3, which make the join label-only and presence
   > unconditional. The distinction the old list missed is that **an event the system
   > took must not disappear because a lookup that only decorates it came back
   > empty.**)*

   > **Every exclusion case must carry a valid covered-class control row in the same
   > response, and that row must still be rendered.** Otherwise "it excluded the bad
   > row" is indistinguishable from "it excluded everything", and each case would be
   > passed by the same broken endpoint AC 5a rules out. A default-deny claim verified
   > only on the happy path is not verified; one verified only on the sad path is not
   > verified either. *(§4.3)*
6. Loki is unreachable from the browser; the endpoint builds its own selector,
   accepts no caller LogQL or unbounded range, and bounds timeout/range/results.
   *(§4.2)*
7. A Loki outage renders **differently from** an empty history. *(§4.2)*
8. Retention and free disk unchanged from §3 at release. *(§3)*
