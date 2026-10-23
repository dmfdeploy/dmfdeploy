# DMF Console: Audit / Event-Log Spec

**Status:** **Design spec.** The record schema (below) is defined. As of
2026-08-30, the storage architecture and the expert/default disclosure split
are also resolved (§ Storage architecture, § Disclosure split below). **See/do/did
linkage remains open.** It is still headed "To define" below. The doc has
not defined when IDs are minted, how a rendered authorization decision is
bound to a record, or how terminal events update or append without
overwriting history. Do not read the record-schema, storage, and disclosure
resolutions as covering it too.

Implementation is also open. These pieces do not exist yet: the ring-buffer
and Loki read endpoint, the terminal audit-event producer, the `/changes`
projection, the Promtail routing for the security-relevant stream, and export
tooling. For the concrete build gaps, see
[DMF Console Shell Round Plan 2026-08-30](../plans/dmf-console-shell-round-plan.md)
§2a/§2b/§7 and umbrella issue #496.

This doc owns the procedural detail behind
**[UX Constitution](dmf-console-ux-constitution.md) Art. 2**
(close every loop) and **Art. 10** (one identity chain: see / do / did).
**Aligned with:** ADR-0028 (identity/authority chain).

## Why this doc exists
Art. 10 asserts that *what you see, what you can do, and what you did* derive from one identity chain. This doc specifies the durable record that makes "did" real. The console's "what changed" view reads from that record.

## To define
- **Record schema:** `request_id` is the **primary cross-app correlation key** (ADR-0028 standardises it). Do *not* add a competing top-level `correlation_id` unless it carries a distinct purpose such as a distributed trace/span id. Core and ADR-0028-mandated fields:
  - `request_id`, `session_id` (D6 quartet propagates actor / session / request_id / reason), `started_at`, `completed_at`
  - **actor (structured human requester):** `actor_subject` (stable Authentik/OIDC `sub`, which survives renames), `actor_username` / `preferred_username`, `actor_email?`. A display name alone is insufficient for incident review.
  - `actor_type` / `authority_path`: { `human_oidc` | `break_glass` (sanctioned, audited under C4/D8) | `service_account` | `system` }. An *unsanctioned* local/shadow account is a **drift/security finding and is not a valid actor class** (for example the remediated AWX shadow superuser). Never model it as a normal or sanctioned actor.
  - `role_snapshot`: role/group claims **copied at action time** (plural). Never re-resolve them from *current* membership during later review.
  - `reason`: the human-supplied why, where warranted
  - **`executed_as`:** the downstream service account that actually ran it, **distinct from the human `actor`**. D5: machine identities are per-app. D6: record the human even when a service account executes. The `actor`/`executed_as` split is what makes "the human who requested it" testable.
  - `action`, `target` (structured: type / id / name / namespace-or-app)
  - `consequence_class`: keep **both** the requested classification and the observed impact when they differ
  - `outcome`: a coarse, closed lifecycle state: { in-progress | succeeded |
    failed | partial | cancelled }. It pairs with `outcome_detail`, a
    free-form string carrying the specific acceptance mode, error class, or
    actuator status that produced that bucket. `outcome` alone answers "is
    this action still open, and if not, how did it end." `outcome_detail`
    answers "which of the many concrete things that map to that bucket
    actually happened," and the doc never validates it against a closed set.
    **See "`outcome` vs `outcome_detail`" below for the definitive mapping.
    This is a decision that the doc does not leave to inference.**
  - `attestation_kind`: { `dmf-cms-attested` | `crypto-bound` }. **Today it is `dmf-cms-attested` (the current v0.1-committed posture, which is NOT cryptographic non-repudiation).** Crypto-binding is gated on ADR-0020 Mode B or the first safety-critical path.
  - `posture`: { `bootstrap-window` | `steady-state` } (D2: bootstrap-window actions carry concentrated authority)
  - `downstream_refs`: structured, hung off `request_id`: { `awx_job_id`, `netbox_change_id`, `forgejo_commit_sha`, `k8s_object_uid`/`k8s_audit_id`, `openbao_audit_ref` }. This way the "did" view can hyperlink into the system that ran the work.
- **See / do / did linkage: still open, and this round does not resolve it.** `request_id` and `downstream_refs` (above) define the correlation *vocabulary* but leave the mechanics undefined. Three questions remain. First, when in the request lifecycle is an `id`/`request_id` pair minted? Second, how does a rendered *authorization* decision (what the operator was shown as permitted, at what moment) bind to the same identifiers as the resulting action? Third, how does a **terminal** audit event (see the Shell Round Plan's terminal-audit-event-producer gap) update or append onto an already-emitted dispatch record without overwriting or orphaning it in an append-only stream? None of these three questions has an answer yet.
- **`/changes` as a read of this log:** the operator-facing "what changed" view is a projection of the audit record. It is not a separate ad-hoc feed (today `/changes` is a direct AWX/Forgejo scrape; see constitution §4).
- **Immutability, retention & export:** the log is append-only. Per ADR-0028 **D7**, identity-bearing audit streams use **streaming export to WORM object-lock S3 (12-month)** as the *destination architecture*. It is neither optional polish nor a cron dump. Security-relevant streams keep 6 months of hot logs (Loki), and general operational logs keep 30 days. Mark each stream's WORM target and define who may read. See **§ Storage architecture** below for the full envelope/transport/retention resolution, including the shipped-vs-planned retention numbers.
- **Relationship to AWX/job records:** how platform job IDs (for example `media-finalise-nmos-cpp #168`) attach to the operator action that triggered them.

## Resolved by review (claude umbrella pane + Codex, 2026-05-25)
- **There is no "two-identity bridge."** ADR-0028 defines one *human* identity (Authentik, D4) plus many *machine* identities (per-app native, D5). The "bridge" is the dmf-cms request log binding *human-who-asked* to *service-account-who-did*. The `actor` / `executed_as` split captures it.
- **`request_id` is the correlation key.** There is no competing top-level `correlation_id` unless it has a distinct purpose (distributed trace/span id).
- **Break-glass is classified and not collapsed.** Sanctioned break-glass (emergency/bootstrap, audited C4/D8) differs from an unsanctioned shadow/local account (a security finding). Both differ from a service account (the executor, never the human actor).

## Storage architecture (recorded 2026-08-30)

This section resolves the former "storage/source of truth" open question, as far as it
goes. **Recorded as operator rulings, 2026-08-30, and tracked by umbrella issue
#496** (`dmf-cms: the audit stream records dispatch but never outcome — the
bus's missing producer, and D7 retention is unmet`). They are not an
independent decision this doc invented on its own. The rulings are also recorded at plan level in
[DMF Console Shell Round Plan 2026-08-30](../plans/dmf-console-shell-round-plan.md)
§2a. The retention *numbers* below are ADR-0028 D7, an existing accepted ADR.
The envelope, transport, and rejected-alternatives choices are this round's
own rulings.

- **Envelope: CloudEvents** (CNCF). `specversion` / `id` / `source` / `type` /
  `time` / `subject` / `data`. The record schema above (`request_id`, `actor`,
  `executed_as`, `outcome`, …) drops into `data` unchanged. The envelope is a
  *shape* applied on top of the existing schema. It adds no new dependency
  and does not redesign the fields above. **Do not invent a bespoke JSON wrapper.**
  **`specversion` is REQUIRED**, with the fixed value `"1.0"`. CloudEvents 1.0's four
  required top-level attributes are `id`, `source`, `specversion`, and `type`
  ([spec](https://github.com/cloudevents/spec/blob/main/cloudevents/spec.md)).
  An envelope missing `specversion` is a bespoke wrapper that
  happens to reuse some field names. It is not CloudEvents, and that outcome is exactly what choosing
  CloudEvents was meant to avoid. **`id` is event identity only and never a
  correlation key.** CloudEvents mandates a top-level `id`, but `request_id`
  (above) remains the **sole** cross-app correlation key per this doc's own
  record-schema rule. Consumers must not treat the envelope's `id` as a
  competing correlation identifier even though both fields sit on the same
  message. `id` answers "which *event* is this." A redelivery of the same
  event may reuse it, which is useful for dedup but does not identify a delivery attempt.
  `request_id` answers "which human action produced this and everything
  correlated with it."
- **Transport: structured JSON on the existing `dmf_cms.audit` child logger →
  stdout → Promtail → Loki.** The child logger, stdout, Promtail, and Loki all
  already exist. The **structured JSON** part does not. Today `audit_logger`
  emits printf-style prose (confirmed in the tree). Its own declaring comment
  says it "stays printf-style ... not structured JSON" and that moving to
  structured logging is "a whole-codebase decision" that the fix does not make.
  That move is unbuilt work, tracked under #496.
- **Hot path in memory, cold path in Loki.** A bounded in-memory ring buffer
  serves the console's live "what's happening" bus instantly and keeps
  working when the monitoring vertical itself is down. Click-to-expand
  history queries Loki.
- **Retention: architecture, shipped reality, and actual routing, stated
  separately so the UI never overclaims:**
  - **Destination architecture (ADR-0028 D7):** identity-bearing/security-relevant
    streams get 6 months hot in Loki. They are **streamed to WORM object-lock S3 in
    near-real-time, in parallel with the hot write** (12-month WORM window).
    This is **not** a handoff six months later. D7's own rationale is closing the
    pre-export mutation window, which a delayed export would leave open for
    the full 6 months. General operational logs get 30 days hot, with no
    archival.
  - **Role default, `dmf-infra`'s Loki role (`k3s-lab-bootstrap/roles/stack/operator/loki/defaults/main.yml`):**
    `720h` (30 days) general retention, plus a `4380h` (6-month) security-relevant
    *stream selector* that already matches the D7 number. **This is a global
    default that a deploying profile overrides. It is not a figure every environment
    runs.** The sandbox profile deployed here overrides both to `168h` (7 days):
    `dmf-env/bin/init-wizard.sh:1822-1823` renders `loki_retention: 168h` and
    `loki_security_retention: 168h` into the per-env inventory. This is
    the profile's committed, deployed *intent*. It is not a plan target that someone might
    revert to. Rendered inventory proves intent and does not prove what Loki is actually
    running or enforcing. The [Durable Action History
    Plan](../plans/dmf-console-durable-action-history-plan.md)'s
    §3 records a point-in-time confirmation of that intent, re-verified live
    twice. Neither is a substitute for Art. 1's runtime discovery below. A
    surface derives the window from the running value and never from this
    paragraph.
  - **D7's 6-month hot retention is UNMET for `dmf_cms.audit` today. This is a gap
    and the doc does not assume it is solved.** The shipped security-relevant selectors
    are `{job="k3s-audit"}`, `{job="authentik-audit"}`, and
    `{job=~".+-security"}` (`dmf-infra`
    `k3s-lab-bootstrap/roles/stack/operator/loki/templates/values.yml.j2`).
    `dmf_cms.audit` exits as ordinary pod stdout, which the generic
    Kubernetes-pods scrape job picks up. It carries none of those labels, so today
    it falls through to the general default, whatever that is on the
    deploying profile (`168h` here, `720h` at role default), regardless of what
    this doc calls it.
    `k3s-audit`'s own dedicated scrape config is not a template for this
    fix. It tails a host file (`__path__: /var/log/kubernetes/audit*.log`
    via a static Promtail scrape target) and does not read pod stdout, so its exact shape
    does not transfer.
    **The rule (still #496 build work, but no longer an unspecified shape):**
    add a Promtail pipeline stage on the dmf-cms pod's stdout scrape. The stage matches
    lines from the `dmf_cms.audit` logger. Once the structured-JSON move
    above lands, it matches on the JSON `logger` field. Until then, it matches on the
    stable printf prefixes `audit_logger` already emits (for example `"awx write: "`,
    `"media-workloads clear: "`). The stage overrides `job` to **`dmf-cms-security`**
    for only those matched lines. That value is deliberately chosen to
    already satisfy the existing `{job=~".+-security"}` selector, so
    shipping it requires **no change to the Loki role** and needs only the new
    Promtail pipeline stage.
    **Acceptance: prove D7 for the whole stream and not for one line's survival:**
    1. Emit two lines sharing one nonce at the same instant: a real
       `dmf_cms.audit` line (routed by the rule above) and a control line
       through the plain module `logger` (general stream, unrelabelled).
    2. Immediately query `{job="dmf-cms-security"} |= "<nonce>"`. It must
       return the audit line and **must not** return the control line. This proves Promtail
       assigned the intended label at ingest. A readable `job`
       value alone does not prove that.
    3. Re-run the same query **more than 30 days later**. The audit line
       must still be present. This proves Loki actually retained it via the
       `4380h` security stream, and that the `720h` general default did not apply.
    4. **Negative control, same nonce:** query the control line's own
       (general/default) `job` value for that nonce. It must return
       **nothing** past 30 days. Without this control, an audit line that
       had not yet been compacted away (Loki compaction lag, or a query too
       loosely scoped to exclude the general stream) could be
       mistaken for proof the routing worked. The negative control shows that an
       *ordinary* 30-day line, planted the same way, does not survive. So
       the positive result in step 3 is not a false positive.

    Tracked under #496.
  - **UI honesty rule (Art. 1), derived not hardcoded.** A surface reading
    this log derives its stated window from the deployed retention
    *applicable to the stream it actually queries*. It never uses a hardcoded
    number, and it never uses the global default when the surface queries a
    security-relevant stream that overrides it. Read that value from the
    running Loki instance over the cluster-DNS path. Never read it from rendered
    inventory intent or role defaults, since a direct `dmf-infra` invocation
    with a different or missing inventory can silently restore the role
    defaults. That read must also establish that retention is actually
    **enforced** and is more than configured. A `retention_period` value with
    `retention_enabled` false, or with enforcement otherwise unhealthy, is
    an invalid ceiling. Treat it as unknown, the same as an unreadable
    policy value below (`dmf-infra`
    `k3s-lab-bootstrap/roles/stack/operator/loki/templates/values.yml.j2:19-26`:
    `retention_period` is policy-but-not-enforced without the compactor
    running). State the window as a **ceiling with an as-of sense**
    ("searches up to `X` ago"). Never state it as a
    claim that a complete `X`-day history is present. Retention is a
    ceiling and gives no coverage guarantee. A policy change is not retroactive; a young
    environment has less than the ceiling, a filled volume has less, and the
    compactor's delete delay makes the cutoff eventual and inexact. Keep
    these states distinct and never collapse them into one:
    - Loki unavailable: the query itself failed.
    - Query succeeded, no rows: nothing found inside the window.
    - Partial or truncated: some rows returned, and more may exist.
    - **Retention/policy read failed but data returned:** a real state that
      is no edge case. Render the data *with* "window unavailable" rather than
      guessing. **No hardcoded fallback, anywhere.** An unreadable policy
      value stays unknown. A fallback here reintroduces the defect this
      rule exists to close.

    **Hazard, latent today:** per-stream `retention_stream` selectors
    (`dmf-infra`
    `k3s-lab-bootstrap/roles/stack/operator/loki/templates/values.yml.j2:28-47`)
    take precedence over the global `retention_period`. That global value is only the
    **fallback for streams matching no selector**. It is not a minimum every
    stream receives. On the sandbox profile both values happen to be `168h`,
    so a surface that reads only the global figure looks correct **today**
    and passes every test available today. It becomes wrong the moment a
    profile's two values diverge (the role default already does: `720h` vs
    `4380h`), and again the day #496's Promtail rule moves `dmf_cms.audit`
    onto the `dmf-cms-security` job. Bind the derived value to the labels
    the surface actually queries. Do not bind it to whichever retention figure is
    easiest to read.
- **Rejected: NATS / a broker.** It is the wrong layer for one in-process producer and
  one consumer at single-replica scale. It adds delivery semantics the
  console doesn't need and still leaves the storage question open. Revisit
  only if multiple repos start publishing to the same bus.
- **Rejected: a console-owned DB/PVC, for now.** On this platform, node loss
  means re-bootstrap either way. A PVC would buy control over the data and would give no
  survivability of it.

### `outcome` vs `outcome_detail`: the D2 decision (resolved 2026-08-30)

**Decision: a distinct field. It is neither a bigger enum nor a distinct event
type.** `outcome` stays the closed 5-value enum above. Every producer of
this record, today's and the not-yet-built terminal producer alike,
supplies a second field, `outcome_detail`, for whatever specific string it
actually has. Rejected alternatives, and why:

- **A distinct event type** (for example CloudEvents `type` of `...audit.dispatch`
  vs `...audit.outcome`) was considered. Rejected: it would make every
  consumer branch on `type` before it can read `outcome` at all, for a
  distinction (`in-progress` vs terminal) the `outcome` enum already
  expresses on its own.
- **Expanding the enum** (adding `launched`, `dispatched`, and every
  actuator's own vocabulary as new peer members) was considered. Rejected:
  it fragments "not done yet" across N near-duplicate spellings and commits
  every terminal-state consumer to keep enumerating all of them, forever,
  as new actuators are added. That is the opposite of a closed contract.
- **Excluding or migrating dispatch records** (do not audit acceptance at all,
  and audit only terminal outcome) was considered. Rejected: it throws away the one
  signal that exists *before* the terminal producer is built. The bus's
  live view (§2b/§7 deliverable #1 above) has nothing else to show today.

**The mapping is resolved where the evidence is unambiguous and left explicitly
open where it isn't:**

| Producer | `outcome` | `outcome_detail` |
|---|---|---|
| deploy / teardown / rollback / finalise-purge dispatch acceptance (the **watched actions**, `operations.py:89-96`'s `_WATCHED_ACTIONS`); AWX accepted the job, a watcher is attached, nothing about the run is known yet (`main.py`'s `outcome="launched"`/`outcome="dispatched"` call sites for these four actions) | `in-progress` | `launched` \| `dispatched` (unchanged) |
| Any precondition/validation refusal recorded before an actuator ever ran, for any action (for example `capacity-denied`, `facility-busy`, `template-not-found`, `awx-not-configured`, `awx-error:<status>`). The action did not happen, full stop. | `failed` | the existing string, unchanged |
| switch-source terminal success (`SwitchStatus.ACTIVE`, `main.py:5747-5749`) | `succeeded` | `active` (the raw `SwitchStatus` value, spec-locked per `switch_source.py` §6.1 and never renamed to match this enum) |
| switch-source terminal rollback failure (`SwitchStatus.FAILED_ROLLBACK_REQUIRED`, same call site) | `failed` | `failed_rollback_required` |
| switch-source pre-command validation error (`SwitchSourceError.code`, for example `receiver-not-found`, `main.py:5666-5668`/`:5728-5730`) | `failed` | the raw error code, unchanged |

**Explicitly left open. The doc does not guess:**

- **The plain `launch` action's own `outcome` values.** Unlike the four
  watched actions, `launch` has no watcher *by design*.
  `operations.py:89-96`'s own comment states its `OperationState.LAUNCHED`
  is genuinely terminal for this action ("nothing will ever move it
  further"). But its **synchronous** branch (`main.py:3362`,
  `outcome="launched"`) creates no `Operation`/`OperationStore` entry at
  all. Its **async/autoscale** branch's background task
  (`_run_launch_operation`, `main.py:1092-1146`) reaches
  `OperationState.LAUNCHED` in the store *without ever calling
  `_audit_awx_write` again*. So the store's own terminal state for that
  branch is never audited, and only its earlier `outcome="dispatched"`
  acceptance call is. Should `launch`'s sync-branch `"launched"`
  map to `succeeded` (matching the store's stated terminal
  semantics) or to `in-progress` (matching every other action's use of that
  word)? This is a real question that this round did not examine. Do not answer it
  by analogy to the watched actions above, because they use a different
  mechanism. Resolve explicitly when #496 touches this call site.
- **The terminal-audit-event producer's own future `OperationState` values**
  (§2b/§7 deliverable #3). The producer does not exist yet. Its
  `OperationState → outcome` mapping is that producer's own design work,
  and this doc does not pre-commit it.

Every resolved row above is already-shipped code. Mapping it is a
documentation fix and needs no new engineering. The mapping is binding now: a future
structured-JSON migration of `_audit_awx_write` (§ Storage architecture
above) applies it as written. The doc does not silently drop the two open items.
An implementer hitting either must resolve it explicitly and must not infer it from
this table.

**This also resolves the "helper records dispatch only" overbreadth** in
the paragraph below and in the
[Shell Round Plan](../plans/dmf-console-shell-round-plan.md)
§2b. The switch-source path is not a dispatch record at all. It runs its
own synchronous actuator (reconnect / future `nmos-is05`) to completion
*before* ever calling `_audit_awx_write`, so its single call per request is
genuinely terminal. The deploy/teardown/rollback/finalise-purge actions differ: they
call it once, at accept time, well before the job finishes. "Today's log
carries dispatch outcomes only" describes those four **watched** AWX
actions specifically (`operations.py:89-96`'s `_WATCHED_ACTIONS`). It was
never true of switch-source. `launch` is a third, distinct case (see
"Explicitly left open" above). Do not assume it behaves like either of the
other two without checking.

**What this resolves and what it doesn't.** This section fixes the envelope
and transport *shape*, and the retention *numbers*. It does not build three things.
The first is the ring-buffer and Loki read endpoint that `/changes` needs to become a real
projection of this log. The second is the terminal audit-event producer for the four
watched actions (today their log entries carry dispatch outcomes only,
`launched`/`dispatched`, and never success or failure). The third is the Promtail routing
that would actually put
`dmf_cms.audit` in the 6-month security stream. The Shell Round Plan §2a/§2b/§7 names all three
explicitly and leaves none implicit, and umbrella issue #496 tracks them.

## Disclosure split: expert vs. default (resolved 2026-08-30)

This section resolves the former "reconciling expert-level raw detail with default-level
plain outcome" open question, per **Constitution Art. 3** and **Art. 8**
(quoted verbatim so this doc does not silently drift from its parent):

> **Art. 3: Speak the operator's language, and teach the facility's.** Split
> vocabulary in three and not two: **System / infrastructure jargon** (`k8s`,
> `Ansible`, `AWX job #168`, exit codes, tracebacks) → **hidden at default,
> revealed at expert.** This is *our* implementation leaking. **Industry-standard
> domain vocabulary** (`NMOS`, `IS-04/05`, `PTP`, `ST 2110`) → **kept and
> explained in place.** This is the operator's actual profession, and hiding it is
> condescending. **DMF-internal architecture ontology** (the EBU layer /
> vertical / lifecycle taxonomy) → **treated as suspect.** It must **earn**
> operator-native status by appearing in a real operator workflow. Until then
> it is expert/internal and is not default vocabulary.

> **Art. 8: Errors are content and not exceptions.** Raw/system errors never leak
> at default. Every default error tells the operator three things: **what
> happened, what it means for the facility, and what to do next** (or who to
> call). Raw detail is available at expert level only.

Applied to this record: `downstream_refs` (`awx_job_id`, `netbox_change_id`,
`forgejo_commit_sha`, `k8s_object_uid`/`k8s_audit_id`, `openbao_audit_ref`),
raw `outcome` error classes/messages, and any AWX job-event text are **expert-only**
fields on the same record. The bus and `/changes` never surface them at default
level. Default disclosure shows `action`, `target`, plain-language `outcome`,
and `reason`. The same record backs both views (Art. 1: one truth, two
resolutions, and never two records). This is the same default-first discipline
the Constitution states in §1: *every state is designed at default first*.
Expert detail is a transform layered on top of one record. It is not a second
record that someone maintains separately.
