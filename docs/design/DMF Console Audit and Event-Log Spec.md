# DMF Console — Audit / Event-Log Spec

**Status:** **Design spec.** Record schema (below), and — as of 2026-08-30 —
the storage architecture and the expert/default disclosure split are resolved
(§ Storage architecture, § Disclosure split below). **See/do/did linkage
remains open** — it is still headed "To define" below and the doc has not
actually defined when IDs are minted, how a rendered authorization decision
is bound to a record, or how terminal events update/append without
overwriting history; do not read the record-schema/storage/disclosure
resolutions as covering it too. Implementation is also open: the ring-buffer +
Loki read endpoint, the terminal audit-event producer, the `/changes`
projection, the Promtail routing for the security-relevant stream, and export
tooling do not exist yet (see
[DMF Console Shell Round Plan 2026-08-30](../plans/DMF%20Console%20Shell%20Round%20Plan%202026-08-30.md)
§2a/§2b/§7 and umbrella issue #496 for the concrete build gaps). Owns the
procedural detail behind
**[UX Constitution](DMF%20Console%20UX%20Constitution%202026-05-25.md) Art. 2**
(close every loop) and **Art. 10** (one identity chain — see / do / did).
**Aligned with:** ADR-0028 (identity/authority chain).

## Why this doc exists
Art. 10 asserts that *what you see, what you can do, and what you did* derive from one identity chain. The durable record that makes "did" real — and that the console's "what changed" view reads from — is specified here.

## To define
- **Record schema** — `request_id` is the **primary cross-app correlation key** (ADR-0028 standardises it; do *not* add a competing top-level `correlation_id` unless it carries a distinct purpose such as a distributed trace/span id). Core + ADR-0028-mandated fields:
  - `request_id`, `session_id` (D6 quartet propagates actor / session / request_id / reason), `started_at`, `completed_at`
  - **actor (structured human requester):** `actor_subject` (stable Authentik/OIDC `sub` — survives renames), `actor_username` / `preferred_username`, `actor_email?` — a display name alone is insufficient for incident review
  - `actor_type` / `authority_path` — { `human_oidc` | `break_glass` (sanctioned, audited under C4/D8) | `service_account` | `system` }. An *unsanctioned* local/shadow account is a **drift/security finding, not a valid actor class** (e.g. the remediated AWX shadow superuser — never modelled as a normal or sanctioned actor)
  - `role_snapshot` — role/group claims **copied at action time** (plural; never re-resolved from *current* membership during later review)
  - `reason` — the human-supplied why, where warranted
  - **`executed_as`** — the downstream service account that actually ran it, **distinct from the human `actor`** (D5: machine identities are per-app; D6: record the human even when a service account executes — the `actor`/`executed_as` split is what makes "the human who requested it" testable)
  - `action`, `target` (structured: type / id / name / namespace-or-app)
  - `consequence_class` — keep **both** the requested classification and the observed impact when they differ
  - `outcome` — coarse, closed lifecycle state: { in-progress | succeeded |
    failed | partial | cancelled }. Paired with `outcome_detail` — a
    free-form string carrying the specific acceptance mode, error class, or
    actuator status that produced that bucket. `outcome` alone answers "is
    this action still open, and if not, how did it end"; `outcome_detail`
    answers "which of the many concrete things that map to that bucket
    actually happened," and is never itself validated against a closed set.
    **See "`outcome` vs `outcome_detail`" below for the definitive mapping —
    this is a decision, not left to inference.**
  - `attestation_kind` — { `dmf-cms-attested` | `crypto-bound` }; **today is `dmf-cms-attested` (the current v0.1-committed posture, NOT cryptographic non-repudiation)** — crypto-binding gated on ADR-0020 Mode B / first safety-critical path
  - `posture` — { `bootstrap-window` | `steady-state` } (D2 — bootstrap-window actions carry concentrated authority)
  - `downstream_refs` — structured, hung off `request_id`: { `awx_job_id`, `netbox_change_id`, `forgejo_commit_sha`, `k8s_object_uid`/`k8s_audit_id`, `openbao_audit_ref` } — so the "did" view can hyperlink into the system that ran the work
- **See / do / did linkage — still open, not resolved by this round.** `request_id` and `downstream_refs` (above) define the correlation *vocabulary*, but not the mechanics: when in the request lifecycle an `id`/`request_id` pair is minted, how a rendered *authorization* decision (what the operator was shown as permitted, at what moment) binds to the same identifiers as the resulting action, and how a **terminal** audit event (see the Shell Round Plan's terminal-audit-event-producer gap) updates or appends onto an already-emitted dispatch record without overwriting or orphaning it in an append-only stream. None of these three questions has an answer yet.
- **`/changes` as a read of this log** — the operator-facing "what changed" view is a projection of the audit record, not a separate ad-hoc feed (today `/changes` is a direct AWX/Forgejo scrape — constitution §4).
- **Immutability, retention & export** — append-only. Per ADR-0028 **D7**: identity-bearing audit streams → **streaming export to WORM object-lock S3 (12-month)** as the *destination architecture* (not optional polish, not a cron dump); hot logs 6-month (Loki) for security-relevant streams; general operational 30-day. Mark each stream's WORM target; define who may read. See **§ Storage architecture** below for the full envelope/transport/retention resolution, including the shipped-vs-planned retention numbers.
- **Relationship to AWX/job records** — how platform job IDs (e.g. `media-finalise-nmos-cpp #168`) attach to the operator action that triggered them.

## Resolved by review (claude umbrella pane + Codex, 2026-05-25)
- **There is no "two-identity bridge."** ADR-0028 is one *human* identity (Authentik, D4) + many *machine* identities (per-app native, D5); the "bridge" is the dmf-cms request log binding *human-who-asked* to *service-account-who-did* — captured by the `actor` / `executed_as` split.
- **`request_id` is the correlation key** — no competing top-level `correlation_id` unless it has a distinct purpose (distributed trace/span id).
- **Break-glass is classified, not collapsed:** sanctioned break-glass (emergency/bootstrap, audited C4/D8) ≠ unsanctioned shadow/local account (security finding) ≠ service account (executor, never the human actor).

## Storage architecture (recorded 2026-08-30)

Resolves the former "storage/source of truth" open question, as far as it
goes. **Recorded as operator rulings, 2026-08-30 — tracked by umbrella issue
#496** (`dmf-cms: the audit stream records dispatch but never outcome — the
bus's missing producer, and D7 retention is unmet`), not an independent
decision this doc invented on its own; also recorded at plan level in
[DMF Console Shell Round Plan 2026-08-30](../plans/DMF%20Console%20Shell%20Round%20Plan%202026-08-30.md)
§2a. The retention *numbers* below are ADR-0028 D7, an existing accepted ADR;
the envelope, transport, and rejected-alternatives choices are this round's
own rulings.

- **Envelope: CloudEvents** (CNCF). `specversion` / `id` / `source` / `type` /
  `time` / `subject` / `data`; the record schema above (`request_id`, `actor`,
  `executed_as`, `outcome`, …) drops into `data` unchanged. It is a *shape*
  applied on top of the existing schema, not a new dependency and not a
  redesign of the fields above. **Do not invent a bespoke JSON wrapper.**
  **`specversion` is REQUIRED**, fixed value `"1.0"` — CloudEvents 1.0's four
  required top-level attributes are `id`, `source`, `specversion`, and `type`
  ([spec](https://github.com/cloudevents/spec/blob/main/cloudevents/spec.md));
  an envelope missing it is not CloudEvents, it is a bespoke wrapper that
  happens to reuse some field names, which is exactly what choosing
  CloudEvents was meant to avoid. **`id` is event identity only — never a
  correlation key.** CloudEvents mandates a top-level `id`, but `request_id`
  (above) remains the **sole** cross-app correlation key per this doc's own
  record-schema rule; consumers must not treat the envelope's `id` as a
  competing correlation identifier even though both fields sit on the same
  message. `id` answers "which *event* is this" (a redelivery of the same
  event may reuse it — useful for dedup, not "which delivery attempt");
  `request_id` answers "which human action produced this and everything
  correlated with it."
- **Transport: structured JSON on the existing `dmf_cms.audit` child logger →
  stdout → Promtail → Loki.** The child logger, stdout, Promtail, and Loki all
  already exist — the **structured JSON** part does not: today `audit_logger`
  emits printf-style prose (confirmed in the tree — its own declaring comment
  says it "stays printf-style ... not structured JSON" and that moving to
  structured logging is "a whole-codebase decision, not this fix's to make").
  That move is unbuilt work, tracked under #496.
- **Hot path in memory, cold path in Loki.** A bounded in-memory ring buffer
  serves the console's live "what's happening" bus instantly and keeps
  working when the monitoring vertical itself is down; click-to-expand
  history queries Loki.
- **Retention — architecture vs. shipped reality vs. actual routing, stated
  separately so the UI never overclaims:**
  - **Destination architecture (ADR-0028 D7):** identity-bearing/security-relevant
    streams get 6 months hot in Loki, **streamed to WORM object-lock S3 in
    near-real-time, in parallel with the hot write** (12-month WORM window) —
    **not** a six-months-later handoff; D7's own rationale is closing the
    pre-export mutation window, which a delayed export would leave open for
    the full 6 months. General operational logs get 30 days hot, no
    archival.
  - **Shipped default, verified against `dmf-infra`'s Loki role config:** 720h
    (30 days) general retention, plus a 4380h (6-month) security-relevant
    *stream selector* that already matches the D7 number. An earlier 168h/7d
    figure was only ever a sandbox-monitoring-doc *plan target* — it was never
    deployed and must not be repeated as current behaviour.
  - **D7's 6-month hot retention is UNMET for `dmf_cms.audit` today — a gap,
    not an assumed-solved detail.** The shipped security-relevant selectors
    are `{job="k3s-audit"}`, `{job="authentik-audit"}`, and
    `{job=~".+-security"}` (`dmf-infra`
    `roles/stack/operator/loki/templates/values.yml.j2`). `dmf_cms.audit`
    exits as ordinary pod stdout, picked up by the generic Kubernetes-pods
    scrape job, and carries none of those labels — so today it falls through
    to the 30-day general default regardless of what this doc calls it.
    `k3s-audit`'s own dedicated scrape config is not a template for this
    fix — it tails a host file (`__path__: /var/log/kubernetes/audit*.log`
    via a static Promtail scrape target), not pod stdout, so its exact shape
    does not transfer.
    **The rule (still #496 build work, but no longer an unspecified shape):**
    a Promtail pipeline stage on the dmf-cms pod's stdout scrape that matches
    lines from the `dmf_cms.audit` logger — once the structured-JSON move
    above lands, matched on the JSON `logger` field; until then, on the
    stable printf prefixes `audit_logger` already emits (e.g. `"awx write: "`,
    `"media-workloads clear: "`) — and overrides `job` to **`dmf-cms-security`**
    for just those matched lines. That value is deliberately chosen to
    already satisfy the existing `{job=~".+-security"}` selector, so
    shipping it requires **no change to the Loki role**, only the new
    Promtail pipeline stage.
    **Acceptance — proving D7, not just one line's survival:**
    1. Emit two lines sharing one nonce at the same instant: a real
       `dmf_cms.audit` line (routed by the rule above) and a control line
       through the plain module `logger` (general stream, unrelabelled).
    2. Immediately query `{job="dmf-cms-security"} |= "<nonce>"` — it must
       return the audit line and **not** the control line, proving Promtail
       assigned the intended label at ingest, not merely that some `job`
       value happens to still be readable.
    3. Re-run the same query **more than 30 days later**: the audit line
       must still be present — proving Loki actually retained it via the
       4380h security stream, not the 720h general default.
    4. **Negative control, same nonce:** query the control line's own
       (general/default) `job` value for that nonce — it must return
       **nothing** past 30 days. Without this, an audit line that simply
       hadn't been compacted away yet (Loki compaction lag, or a query too
       loosely scoped to actually exclude the general stream) could be
       mistaken for proof the routing worked; the negative control shows an
       *ordinary* 30-day line, planted the same way, does not survive — so
       the positive result in step 3 isn't a false positive.
    Tracked under #496.
  - **UI honesty rule (Art. 1), unconditional:** any user-facing surface
    reading this log states its window as **"last 30 days," full stop** —
    never 7, and never a future "last 6 months" claim either, because until
    the routing gap above is closed and verified, no surface reads the
    security-relevant stream at all.
- **Rejected: NATS / a broker.** Wrong layer for one in-process producer and
  one consumer at single-replica scale — it adds delivery semantics the
  console doesn't need and still leaves the storage question open. Revisit
  only if multiple repos start publishing to the same bus.
- **Rejected: a console-owned DB/PVC, for now.** On this platform, node loss
  means re-bootstrap either way, so a PVC buys control over the data, not
  survivability of it.

### `outcome` vs `outcome_detail` — the D2 decision (resolved 2026-08-30)

**Decision: a distinct field, not a bigger enum, not a distinct event
type.** `outcome` stays the closed 5-value enum above; every producer of
this record — today's and the not-yet-built terminal producer alike —
supplies a second field, `outcome_detail`, for whatever specific string it
actually has. Rejected alternatives, and why:

- **A distinct event type** (e.g. CloudEvents `type` of `...audit.dispatch`
  vs `...audit.outcome`) was considered. Rejected: it would make every
  consumer branch on `type` before it can read `outcome` at all, for a
  distinction (`in-progress` vs terminal) the `outcome` enum already
  expresses on its own.
- **Expanding the enum** (adding `launched`, `dispatched`, and every
  actuator's own vocabulary as new peer members) was considered. Rejected:
  it fragments "not done yet" across N near-duplicate spellings and commits
  every terminal-state consumer to keep enumerating all of them, forever,
  as new actuators are added — the opposite of a closed contract.
- **Excluding/migrating dispatch records** (don't audit acceptance at all,
  only terminal outcome) was considered. Rejected: it throws away the one
  signal that exists *before* the terminal producer is built — the bus's
  live view (§2b/§7 deliverable #1 above) has nothing else to show today.

**The mapping — resolved where the evidence is unambiguous, left explicitly
open where it isn't:**

| Producer | `outcome` | `outcome_detail` |
|---|---|---|
| deploy / teardown / rollback / finalise-purge dispatch acceptance — the **watched actions** (`operations.py:89-96`'s `_WATCHED_ACTIONS`); AWX accepted the job, a watcher is attached, nothing about the run is known yet (`main.py`'s `outcome="launched"`/`outcome="dispatched"` call sites for these four actions) | `in-progress` | `launched` \| `dispatched` (unchanged) |
| Any precondition/validation refusal recorded before an actuator ever ran, for any action (e.g. `capacity-denied`, `facility-busy`, `template-not-found`, `awx-not-configured`, `awx-error:<status>`) — the action did not happen, full stop | `failed` | the existing string, unchanged |
| switch-source terminal success (`SwitchStatus.ACTIVE`, `main.py:5747-5749`) | `succeeded` | `active` (the raw `SwitchStatus` value — spec-locked per `switch_source.py` §6.1, never renamed to match this enum) |
| switch-source terminal rollback failure (`SwitchStatus.FAILED_ROLLBACK_REQUIRED`, same call site) | `failed` | `failed_rollback_required` |
| switch-source pre-command validation error (`SwitchSourceError.code`, e.g. `receiver-not-found`, `main.py:5666-5668`/`:5728-5730`) | `failed` | the raw error code, unchanged |

**Explicitly left open, not guessed at:**

- **The plain `launch` action's own `outcome` values.** Unlike the four
  watched actions, `launch` has no watcher *by design* —
  `operations.py:89-96`'s own comment states its `OperationState.LAUNCHED`
  is genuinely terminal for this action ("nothing will ever move it
  further"). But its **synchronous** branch (`main.py:3362`,
  `outcome="launched"`) creates no `Operation`/`OperationStore` entry at
  all, while its **async/autoscale** branch's background task
  (`_run_launch_operation`, `main.py:1092-1146`) reaches
  `OperationState.LAUNCHED` in the store *without ever calling
  `_audit_awx_write` again* — so the store's own terminal state for that
  branch is never audited; only its earlier `outcome="dispatched"`
  acceptance call is. Whether `launch`'s sync-branch `"launched"` should
  therefore map to `succeeded` (matching the store's stated terminal
  semantics) or `in-progress` (matching every other action's use of that
  word) is a real question this round did not examine and must not answer
  by analogy to the watched actions above — they are not the same
  mechanism. Resolve explicitly when #496 touches this call site.
- **The terminal-audit-event producer's own future `OperationState` values**
  (§2b/§7 deliverable #3) — it does not exist yet; its
  `OperationState → outcome` mapping is that producer's own design work,
  not pre-committed here.

Every resolved row above is already-shipped code; mapping it is a
documentation fix, not new engineering, and is binding now — a future
structured-JSON migration of `_audit_awx_write` (§ Storage architecture
above) applies it as written. The two open items are not silently dropped:
an implementer hitting either must resolve it explicitly, not infer it from
this table.

**This also resolves the "helper records dispatch only" overbreadth** in
the paragraph below and in the
[Shell Round Plan](../plans/DMF%20Console%20Shell%20Round%20Plan%202026-08-30.md)
§2b: the switch-source path is not a dispatch record at all. It runs its
own synchronous actuator (reconnect / future `nmos-is05`) to completion
*before* ever calling `_audit_awx_write`, so its single call per request is
genuinely terminal — unlike deploy/teardown/rollback/finalise-purge, which
call it once, at accept time, well before the job finishes. "Today's log
carries dispatch outcomes only" describes those four **watched** AWX
actions specifically (`operations.py:89-96`'s `_WATCHED_ACTIONS`); it was
never true of switch-source. `launch` is a third, distinct case — see
"Explicitly left open" above; do not assume it behaves like either of the
other two without checking.

**What this resolves and what it doesn't.** This section fixes the envelope
and transport *shape*, and the retention *numbers*. It does not build: the
ring-buffer + Loki read endpoint `/changes` needs to become a real
projection of this log; the terminal audit-event producer for the four
watched actions (today their log entries carry dispatch outcomes only —
`launched`/`dispatched` — never success/failure); or the Promtail routing
that would actually put
`dmf_cms.audit` in the 6-month security stream. All three are named
explicitly (not left implicit) in the Shell Round Plan §2a/§2b/§7 and tracked
by umbrella issue #496.

## Disclosure split — expert vs. default (resolved 2026-08-30)

Resolves the former "reconciling expert-level raw detail with default-level
plain outcome" open question, per **Constitution Art. 3** and **Art. 8**
(quoted verbatim so this doc does not silently drift from its parent):

> **Art. 3 — Speak the operator's language, and teach the facility's.** Split
> vocabulary in three, not two: **System / infrastructure jargon** (`k8s`,
> `Ansible`, `AWX job #168`, exit codes, tracebacks) → **hidden at default,
> revealed at expert.** This is *our* implementation leaking. **Industry-standard
> domain vocabulary** (`NMOS`, `IS-04/05`, `PTP`, `ST 2110`) → **kept and
> explained in place.** This is the operator's actual profession; hiding it is
> condescending. **DMF-internal architecture ontology** (the EBU layer /
> vertical / lifecycle taxonomy) → **treated as suspect.** It must **earn**
> operator-native status by appearing in a real operator workflow; until then
> it is expert/internal, not default vocabulary.

> **Art. 8 — Errors are content, not exceptions.** Raw/system errors never leak
> at default. Every default error tells the operator three things: **what
> happened, what it means for the facility, and what to do next** (or who to
> call). Raw detail is available at expert level only.

Applied to this record: `downstream_refs` (`awx_job_id`, `netbox_change_id`,
`forgejo_commit_sha`, `k8s_object_uid`/`k8s_audit_id`, `openbao_audit_ref`),
raw `outcome` error classes/messages, and any AWX job-event text are **expert-only**
fields on the same record — never surfaced in the bus or `/changes` at default
level. Default disclosure shows `action`, `target`, plain-language `outcome`,
and `reason`; the same record backs both views (Art. 1: one truth, two
resolutions, never two records). This is the same default-first discipline
the Constitution states in §1: *every state is designed at default first*;
expert detail is a transform layered on top of one record, not a second,
separately-maintained one.
