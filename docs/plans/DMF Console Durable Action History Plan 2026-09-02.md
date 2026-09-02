---
status: active
date: 2026-09-02
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/496
---
# DMF Console Durable Action History Plan (2026-09-02)

> **STATUS: ACTIVE — the execution plan for the *demo history slice* of umbrella
> issue #496.** This is rounds 2–4 of the current console arc; round 1 (umbrella
> #444 plus the demo runbook walk, #379) is separate and lands first.
>
> **These rounds do not close #496.** They close the demo history slice. #496's
> original scope also names Promtail routing and ADR-0028 D7 retention as unmet,
> and §6 defers both — so the completing PR must **not** carry
> `Closes dmfdeploy/dmfdeploy#496`.
>
> This plan carries no new architectural decisions — the design is fixed by
> [DMF Console Audit and Event-Log Spec](../design/DMF%20Console%20Audit%20and%20Event-Log%20Spec.md)
> and ADR-0028 D7. It records *how the existing decision gets implemented*, what
> not to build, and **one open question** (§5.3) that needs an operator answer.

## 0. Why this exists

The console's action-history lane already renders, and shows an empty state.

**Be precise about what is missing, because a server-side record does partly
exist.** `dmf_cms.audit` already emits **dispatch** records to stdout as printf
prose (`main.py:952-1001`), and those lines already reach Loki — measured, §3. The
gap is not "nothing is recorded server-side." It is that there is **no
structured, queryable, complete** history:

- the records are **prose, not parseable JSON**;
- **terminal outcomes are never emitted at all** — the watcher updates
  `OperationStore` and stops, which is the issue title's *records dispatch but
  never outcome*;
- **`clear-for-deployment` bypasses the audit helper** entirely;
- and the lane reads none of it — it reads browser `localStorage`, which is **per
  origin**, holds only actions taken in that one browser, caps at ~50 rows, and
  is destroyed by every environment rebuild.

## 1. The bar this plan is built to

> **Perform an action in one browser. Open the console in a different browser (or
> a fresh incognito session, or another machine). The action is there.**

The originally-stated bar — *survive an environment rebuild* — was **relaxed by
operator decision, 2026-09-02**: short retention is acceptable; the record must be
persistent enough to show real recent changes.

**That relaxation is a dial, not a different architecture.** Operator ruling, same
day: *"Loki is of course not unnecessary, because we are not only building a demo,
we are demoing a system that might one day work in production."* A bespoke store
existing only to make the video work is the wrong answer, because the thing
demonstrated **is the real system**.

## 2. Already decided — do not re-open

The spec fixes the tiering, and the wording is load-bearing:

> *"Hot path in memory, cold path in Loki. A bounded in-memory ring buffer serves
> the console's live what-is-happening bus instantly …; **click-to-expand history
> queries Loki**."*

A ring **is** in the architecture — assigned to the **live bus** (#480).
**History is Loki's.** An adversarial review initially recommended serving history
from a ring and was reversed on this point: it substitutes the hot tier for the
cold tier, and is why a ring loses everything on a pod restart at `replicas: 1`.

**No new ADR is required.** The transport and tier split are already authorised;
ADR-0028 D7 is an **accepted** decision whose console-side producer and routing are
**unmet**. Freeze 1 names no durable-audit non-goal. Freeze 2 remains in force and
permits this as implementation of an existing decision.

**One tension to resolve explicitly.** `main.py`'s own comment says the audit
logger *"stays printf-style … a real move to structured logging is a whole-codebase
decision, not this fix's to make."* That was correct when written. The spec has
since named the structured-JSON move as unbuilt work **tracked under #496** — so
converting *this one logger* is now authorised, and the resulting format split
with the file's other printf calls is **deliberate**. Update that comment.

## 3. What is already true — measured 2026-09-02

Probed read-only against the live single-node sandbox. **This is why the plan has
no infrastructure round.** It is a **point-in-time observation, not a guarantee.**

| | Role default | Live sandbox |
|---|---|---|
| Loki general retention | 720h / 30d | **168h / 7d** — *measured* in the running ConfigMap, `retention_enabled: true` |
| Loki security retention | 4380h / 6mo | **168h / 7d** — *from committed source*, not measured; see note |
| Loki PVC | 50Gi | **5Gi** — measured |
| Loki actual usage | — | **~1008 MB after 17d uptime, 0 restarts** — measured |
| Node disk | — | 59G total, **26G free**, 54% used — measured |

**Distinguish measurement from configuration.** Only `retention_period: 168h` was
read from the live ConfigMap. The security-stream value comes from
`dmf-env/bin/init-wizard.sh:1810-1823`, which sets `loki_storage_size: 5Gi`,
`loki_retention: 168h`, `loki_security_retention: 168h`. Security selectors **may
still exist with the same 168h period** — the accurate statement is *no separate
longer security retention*, not *no security stream*.

These overrides are **committed and deliberate**, and are rendered into the
generated inventory *"so a STANDALONE re-run of a single monitoring play stays
sandbox-fit too."*

> **Re-run caveat.** `bin/run-playbook.sh:75` and `:195-200` select and pass the
> generated env inventory, and inventory beats role defaults — so a routine re-run
> through the wrapper preserves these values. A **direct `dmf-infra` invocation
> with a different or missing inventory, or explicit extra-vars, can restore
> 720h/50Gi/4380h** and silently remove this safety. Verify rendered values as a
> preflight; do not run the bare role against this env.

**Collection is not the gap.** A live query returned **958 lines in one hour** for
`{namespace="dmf-cms"}` with labels `namespace`, `job`, `app`, `container`, `pod`,
`node_name`, `level`, `stream`. Generic stdout collection is proven. The
**audit-specific JSON parse and retention routing remain gaps.**

**Consequences.** Umbrella #289 is **not an active accumulation failure on this
env** — retention enforced, steady state, large headroom. Umbrella #282 **does not
bite** because this plan releases only `dmf-cms` and queries the already-running
Loki: no Loki or Promtail release means no gateway rollout. Neither is a gate
**for this work** — conditionally: verify disk and retention before release, do
not introduce a high-volume producer, and if any later Helm change touches the
gateway, render the diff first and use soft/preferred anti-affinity or `Recreate`.

**Residual risk.** The 1MB/s per-stream cap and Promtail's line limiter are
*protection, not a disk budget* — 1MB/s sustained would exceed free space in about
a day. Audit events are low-volume by nature; keep them so.

## 4. The four gaps

All in `dmf-cms`, all located:

1. **`dmf_cms.audit` emits printf prose, not structured JSON** (`main.py:952-1001`).
2. **Terminal outcomes emit no audit event at all** — the watcher updates
   `OperationStore` and stops.
3. **`clear-for-deployment` bypasses the audit helper** (`main.py:5635-5646`).
4. **No read side** — no Loki client, no endpoint, no consumer; `HistoryLane`
   still reads `localStorage`.

## 5. The rounds

### Round 2 — the event contract and the read endpoint (`dmf-cms`)

**5.1 The event contract.** This is the weakest part of any under-specified
version of this plan; specify it before writing code.

Emit **one CloudEvents 1.0 JSON event per lifecycle record** — *not* one per
action. A watched action produces **two** events: dispatch, then terminal.

- Envelope: `specversion`, **unique `id` per event**, `source`, `type`, `time`,
  `subject`, `data`.
- **`id` is event identity; `request_id` is correlation.** The two events of one
  action share `request_id` and have **different `id`s**.
- `data` carries `request_id`, actor, role snapshot, reason, action, target,
  `outcome`, **`outcome_detail`**, and downstream refs.
- **Include a top-level `logger` field.** `logger` is *not* a CloudEvents envelope
  field, and the query in §5.2 has nothing stable to match without it.

**The concrete envelope values, recorded here so the implementer does not invent
them:**

| Field | Value | Why |
|---|---|---|
| `specversion` | `"1.0"` — **fixed, required** | The spec is explicit: an envelope missing it *"is not CloudEvents, it is a bespoke wrapper that happens to reuse some field names."* |
| `type` | `dmf.cms.audit.action` — **one shared value for dispatch *and* terminal** | See below. Not domain-qualified, deliberately: `type` is a free-form string, and asserting a real hostname in a public repo is avoidable. |
| `source` | `/dmf-cms` | The producing application, **not** environment-specific — environment identity already arrives as Loki labels, and env ids must not be baked into event bodies. |
| `subject` | the action's target identifier (workload slug) | Lets a consumer filter without parsing `data`. |
| `id` | unique per event | **Never a correlation key** — see below. |
| `time` | RFC 3339 | CloudEvents default. |

> **The single shared `type` is mandated, not a style choice.** The spec
> *considered and rejected* distinct types (`…audit.dispatch` vs
> `…audit.outcome`): it would *"make every consumer branch on `type` before it
> can read `outcome` at all, for a distinction the `outcome` enum already
> expresses on its own."* Dispatch and terminal are told apart by
> `outcome`/`outcome_detail` — **never by `type`**. Emitting two types would
> contradict a resolved decision.

> **`id` is event identity only, never correlation.** The spec is emphatic:
> `request_id` remains the **sole** cross-app correlation key, and consumers must
> not treat the envelope's `id` as a competing correlation identifier even though
> both sit on the same message. `id` answers *which event is this* (a redelivery
> may reuse it — useful for dedup); `request_id` answers *which human action
> produced this and everything correlated with it*.

The exact `type`/`source` strings above are a naming choice recorded for
consistency; change them only by amending this plan, since they are a stable
contract once events are in Loki.

**`outcome_detail` is spec-locked and must not be skipped.** Per the D2 decision
(Audit Spec §`outcome` vs `outcome_detail`), `outcome` stays the closed 5-value
enum and **every producer supplies `outcome_detail`** for the specific string it
actually has. The spec's mapping table is authoritative — including watched-action
dispatch being `outcome: in-progress` with `outcome_detail: launched | dispatched`,
and switch-source terminals mapping to `active` / `failed_rollback_required` with
their **raw `SwitchStatus` values, never renamed**.

**The terminal mapping — this plan's own design work, and it must not be skipped.**
The spec's mapping table covers dispatch acceptance and switch-source terminals,
and then says explicitly of the terminal producer: *"it does not exist yet; its
`OperationState → outcome` mapping is **that producer's own design work, not
pre-committed here**."* That producer is this plan. So the mapping is defined
here, over `_WATCHED_TERMINAL_STATES` (`operations.py:99-106`), against the closed
enum `{ in-progress | succeeded | failed | partial | cancelled }`:

| `OperationState` | `outcome` | `outcome_detail` | Note |
|---|---|---|---|
| `RUN_COMPLETE` | `succeeded` | `run_complete` | |
| `RUN_FAILED` | `failed` | `run_failed` | |
| `FAILED_ROLLBACK_REQUIRED` | `failed` | `failed_rollback_required` | In `DIRTY_STATES` — surfaces need to say the facility may be inconsistent |
| `ROLLBACK_INCOMPLETE` | `partial` | `rollback_incomplete` | In `DIRTY_STATES`. **`partial`, not `failed`** — the rollback ran and did not finish; calling it `failed` implies nothing moved |
| `RUN_STATUS_UNKNOWN` | `partial` | `run_status_unknown` | **See below — the one worth challenging** |
| `ERROR` | `failed` | the specific error string | Console-side fault (e.g. AWX wake failed), not a run verdict |

> **`RUN_STATUS_UNKNOWN` is the uncomfortable one, and it is deliberate.** The
> closed enum has no *unknown* member, so every choice is imperfect. `succeeded`
> is plainly untrue. `failed` asserts a verdict nobody reached and would send an
> operator to undo work that may have completed. `in-progress` is a different lie
> — the state is terminal, nothing will move it further. **`partial` is the
> least-wrong bucket** — "not cleanly either" — and `outcome_detail:
> run_status_unknown` carries the actual truth. **The UI must render the detail
> for this row, not just the bucket**, or it will state something the system does
> not know. If any mapping here deserves a second look, it is this one.

**`launch`'s sync-branch `"launched"` is explicitly OUT of scope.** The spec flags
it as unresolved and warns it *"must not answer by analogy to the watched actions
— they are not the same mechanism,"* to be resolved when #496 touches that call
site. This slice does not touch it: `launch` is not in `_WATCHED_ACTIONS` and is
not a demo beat. **Do not map it by analogy while passing.** It stays open.

**The read endpoint collapses the pair into one lane row**, joining on
`request_id` and preferring the terminal event where present. A row with only a
dispatch renders as still in flight; a row with both renders the terminal
`outcome` plus `outcome_detail`.

**5.2 The endpoint.** Add a backend Loki client and an authenticated
`GET /api/audit/events` (or equivalent) querying `query_range`.

```
{namespace="dmf-cms", job="dmf-cms/dmf-cms"} | json | logger="dmf_cms.audit" | __error__=""
```

Loki selects all `dmf-cms` streams first, then parses and filters each line — less
efficient than a dedicated stream, but modest at ~958 lines/hour over 7 days.
**Do not add `actor` or `request_id` as labels** — unbounded cardinality.

> **The browser never talks to Loki.** It calls `dmf-cms` same-origin with its
> signed session cookie; `dmf-cms` reaches Loki over cluster DNS. Loki runs
> `auth_enabled: false` and has no application auth, so anything that exposed it
> — a proxy or ingress — would permit an unauthenticated read of **every stream in
> that Loki tenant**. It is a ClusterIP today and not browser-reachable; keep it
> that way.

**Hard requirements on the endpoint:**

- **The backend constructs the selector.** Never accept arbitrary LogQL, a
  caller-supplied selector, or an unbounded `start`/`end` from the browser.
- **Bound everything:** explicit query timeout, maximum time range, maximum result
  count.
- **Loki-unavailable must be distinguishable from empty history** at the API and
  in the UI. "Nothing happened" and "we could not ask" are different statements,
  and conflating them is exactly the untruth this work exists to remove.

**5.3 The authorization projection — RESOLVED (operator decision, 2026-09-02).**
"`_require_user` plus effective scope" was not an implementable contract, and #419
(security-scoped Recent Changes over global audit history) is out of scope (§6), so
this needed deciding rather than inheriting.

**Decision: the lane shows events whose *target the user is already authorized to
read*** — reusing the existing per-workload read check. **No new permission
model.** An event whose target cannot be resolved, or which the user cannot open,
is excluded.

Rejected: *only the acting user's own events* — trivially safe and it would pass
§1, but in a multi-operator facility a lane that silently hides a colleague's
Deploy is misleading, and gives no indication anything is hidden. Rejected:
*unfiltered* — leaks activity across authorization boundaries.

The projection is applied **server-side, after the Loki parse and before the
response** — never by the client, and never by widening the LogQL selector.

### Round 3 — consumer (frontend)

Types plus a TanStack query hook; replace the `localStorage` source in
`HistoryLane`. Keep the empty state honest, and render the Loki-unavailable state
distinctly from it.

> **The lane must state its window as "last 7 days."** The spec's UI honesty rule
> currently mandates *"last 30 days, full stop — never 7"*, which is **false on
> this environment**. Tracked as dmfdeploy/dmfdeploy#530 and **must be resolved
> before this round ships**. Derive the window from deployed retention; hardcoding
> either number guarantees one profile lies.

### Round 4 — tests, release, verification

**Migrate the caplog tests. This is not optional and is larger than it looks.**
`main.py`'s comment records that **15+ existing tests parse the exact
`"awx write: action=… actor=…"` prose shape via `caplog`**; at least ten test
files touch it (`test_finalise_purge_endpoint.py`, `test_awx_write_gate.py`,
`test_audit_log_stdout.py`, `test_switch_source_endpoint.py`,
`test_media_workloads.py`, `test_capacity_gate.py`, `test_view_as.py`,
`test_topology_seam.py`, `test_autoscale_operations.py`,
`test_drain_verification.py`). Converting the emitter to JSON **breaks every one
of them**. Re-point them at the structured record; do not delete, skip or weaken
any assertion.

Then release and verify **by the bar in §1** — action in browser A, read in a
**fresh** browser B.

- **Hard-reload before measuring.** A tab open across a deploy serves the old
  bundle and yields a false negative even when the pod digest verifies.
- **Verify the deploy by image label, not cross-registry digest equality** —
  skopeo re-manifests on copy, so Zot and GHCR digests legitimately differ.
- **`/api/version` and `/version` both return 200 with `index.html`** (SPA
  catch-all) — any HTTP version check against them is a false green.
- Confirm retention and free disk unchanged from §3.

## 6. Explicitly not in scope

- **A dedicated stream label.** Needs a Promtail relabel rule, so an infra
  release, which re-introduces #282. **Because this is deferred, #496 does not
  close on these rounds.**

  > **Two different labels, and conflating them is the trap.** The shipped
  > security-relevant selector is `{job=~".+-security"}`, so **`dmf-cms-audit`
  > does not match it** — a stream labelled that way falls through to the general
  > default and gets **no** D7 retention. The D7-correct label would be
  > **`dmf-cms-security`**, which *does* match — and which is precisely why it
  > must **not** be used on this sandbox, where it would attach the six-month
  > selector to a 7-day-retention profile. So: `dmf-cms-audit` is the
  > **demo-safe** label, not the D7 one; adopting `dmf-cms-security` is a
  > production-profile change and carries its own selector work. Neither is in
  > scope here — this slice adds no label at all and queries by namespace.
- **Full ADR-0028 D7 compliance** — six-month hot security retention plus
  near-real-time 12-month WORM object-lock. The 7-day sandbox profile is an
  environment tuning override on the same architecture; **the UI must not claim
  otherwise.**
- **dmfdeploy/dmfdeploy#419** — security-scoped Recent Changes over global audit
  history. Related in intent, materially larger, must not be silently absorbed.
- **A bespoke persistence layer.** See §1.
- **dmfdeploy/dmfdeploy#523** (`.btn-secondary` hover darkens). Real, not this plan's.

## 7. Acceptance

1. An action performed in browser A is visible in a fresh browser B. *(§1)*
2. A **terminal** outcome — succeeded or failed — is recorded and displayed
   truthfully, carrying both `outcome` and `outcome_detail` per the spec's mapping;
   dispatch and terminal are **distinct events sharing a `request_id`**, collapsed
   to one lane row by the endpoint. *(§5.1)*
3. `clear-for-deployment` appears in the lane. *(§4.3)*
4. The lane's stated window matches deployed retention. *(#530)*
5. Loki is unreachable from the browser; the endpoint builds its own selector,
   accepts no caller LogQL or unbounded range, and bounds timeout/range/results.
   *(§5.2)*
6. A Loki outage renders **differently from** an empty history. *(§5.2)*
7. Every migrated `caplog` test passes with no assertion deleted, skipped or
   weakened. *(§5 Round 4)*
8. Retention and free disk unchanged from §3 at release. *(§3)*
