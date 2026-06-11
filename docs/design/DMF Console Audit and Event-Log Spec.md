# DMF Console — Audit / Event-Log Spec

**Status:** 🚧 Stub — to be written. Owns the procedural detail behind **[UX Constitution](DMF%20Console%20UX%20Constitution%202026-05-25.md) Art. 2** (close every loop) and **Art. 10** (one identity chain — see / do / did).
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
  - `outcome` — { in-progress | succeeded | failed | partial | cancelled } + final error class/message
  - `attestation_kind` — { `dmf-cms-attested` | `crypto-bound` }; **today is `dmf-cms-attested` (experiment-phase, NOT cryptographic non-repudiation)** — crypto-binding gated on ADR-0020 Mode B / first safety-critical path
  - `posture` — { `bootstrap-window` | `steady-state` } (D2 — bootstrap-window actions carry concentrated authority)
  - `downstream_refs` — structured, hung off `request_id`: { `awx_job_id`, `netbox_change_id`, `forgejo_commit_sha`, `k8s_object_uid`/`k8s_audit_id`, `openbao_audit_ref` } — so the "did" view can hyperlink into the system that ran the work
- **See / do / did linkage** — how a rendered action, its authorization, and its recorded outcome share identifiers so an incident can be reconstructed end-to-end.
- **`/changes` as a read of this log** — the operator-facing "what changed" view is a projection of the audit record, not a separate ad-hoc feed (today `/changes` is a direct AWX/Forgejo scrape — constitution §4).
- **Immutability, retention & export** — append-only. Per ADR-0028 **D7**: identity-bearing audit streams → **streaming export to WORM object-lock S3 (12-month)** as the *destination architecture* (not optional polish, not a cron dump); hot logs 6-month (Loki); general operational 30-day. Mark each stream's WORM target; define who may read.
- **Relationship to AWX/job records** — how platform job IDs (e.g. `media-finalise-nmos-cpp #168`) attach to the operator action that triggered them.

## Resolved by review (claude umbrella pane + Codex, 2026-05-25)
- **There is no "two-identity bridge."** ADR-0028 is one *human* identity (Authentik, D4) + many *machine* identities (per-app native, D5); the "bridge" is the dmf-cms request log binding *human-who-asked* to *service-account-who-did* — captured by the `actor` / `executed_as` split.
- **`request_id` is the correlation key** — no competing top-level `correlation_id` unless it has a distinct purpose (distributed trace/span id).
- **Break-glass is classified, not collapsed:** sanctioned break-glass (emergency/bootstrap, audited C4/D8) ≠ unsanctioned shadow/local account (security finding) ≠ service account (executor, never the human actor).

## Open questions
- Storage/source of truth for the log (platform DB vs. existing AWX/Forgejo history vs. a new event stream).
- Reconciling expert-level raw detail (job id, exit code) with default-level plain outcome (Arts. 3, 8).
