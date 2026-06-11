---
status: executed
date: 2026-04-26
---
# DMF Console Initial Implementation Plan — 2026-04-26

> **Vocabulary aligned with EBU DMF Reference Architecture V2.0.** The console
> is a Layer 6 — Application & UI component, but it is also the operator-facing
> control surface for the Orchestration, Control, Monitoring, and Security
> verticals.

## 1. Purpose

This document defines the first implementation plan for the DMF single pane of
glass. It replaces the current link-portal landing page with a real product
surface where facility control, monitoring, workflow execution, and change
management converge.

Working product name: **DMF Console**.

Repository/deploy artifact name can remain `dmf-cms`, but the user-facing
product should not be framed as a generic CMS. It is the visible DMF product.

## 2. Product Thesis

The DMF Console is not an iframe aggregator for NetBox, AWX, Grafana, Forgejo,
and Authentik.

It is the operator's operational model of the facility:

- NetBox provides inventory and topology truth.
- Prometheus and Alertmanager provide health, telemetry, and alert state.
- AWX executes controlled workflows.
- Forgejo carries reviewable configuration changes.
- Authentik provides identity.
- OpenBao protects secret values.
- Kubernetes provides live workload state.

The console correlates those systems into operator-native answers:

- Is the facility healthy?
- What is broken or at risk?
- What changed?
- What workflows are running?
- What needs approval?
- What can I safely do now?
- Did the last action complete correctly?
- Which backend system should I deep-inspect only if needed?

## 3. Non-Negotiable Design Rules

1. **The console replaces the landing page.** The first viewport must be the
   operational product, not a link directory.
2. **Do not duplicate sources of truth.** NetBox, Prometheus, AWX, Forgejo,
   Authentik, OpenBao, and Kubernetes keep their existing ownership boundaries.
3. **Do not store raw secrets in the console database.** Store secret reference
   names and credential health metadata only.
4. **Prefer APIs over iframes.** Deep links are useful; embedded admin tools are
   not the product.
5. **Every operator action is audited.** Runtime actions and config changes both
   emit structured records.
6. **Config and operations are separate lanes.** PR-gated config changes and
   direct runtime operations are different workflows with different latency and
   approval needs.
7. **The initial product must work before media-specific Layer 4/5 features
   exist.** Media flow views come later; the first console controls the platform
   that will host them.
8. **Backend failures must degrade explicitly.** If NetBox is unavailable, show
   "inventory unavailable", not an empty facility.

## 4. Current Starting Point

`~/repos/dmf-cms` is scaffold-only:

- `README.md` describes the intended single-pane-of-glass product.
- `CLAUDE.md` says no production code should be written until the tech stack is
  recorded.
- Helm chart values are placeholders.
- `playbooks/650-dmf-cms.yml` is reserved in the EBU mapping as the Layer 6
  deployment slot.

The current `dmf-infra` landing page advertises app cards through
`apps.json`. The console should eventually own that user-facing entry point,
while preserving deep links to backend tools.

## 5. Recommended Initial Stack

Record this as the initial implementation decision:

- **Backend:** FastAPI
- **Frontend:** server-rendered HTML with Jinja templates + HTMX
- **Live updates:** Server-Sent Events first; WebSockets only when bidirectional
  interaction is required
- **Database:** PostgreSQL
- **Background jobs:** lightweight internal worker loop at first; Celery/RQ only
  when job volume requires it
- **Packaging:** existing Dockerfile + Helm chart in `dmf-cms`
- **Auth:** Authentik OIDC
- **Styling:** restrained operational UI; dense, scan-friendly, no marketing
  layout

Rationale: FastAPI gives strong API-integration ergonomics. HTMX avoids an
early full-SPA commitment while still supporting live workflow pages and rich
forms. React/Svelte islands can be added later for views that genuinely need
high-frequency interaction, such as topology maps or routing matrices.

## 6. User Roles

Initial roles should be simple and map from Authentik groups:

| Role | Scope |
|---|---|
| Viewer | Read facility status, inventory summaries, alerts, and workflow history |
| Operator | Launch approved runtime workflows and acknowledge operational items |
| Engineer | Draft config changes, run reconciliation workflows, inspect integrations |
| Admin | Configure integrations, role mappings, and deployment settings |

Do not create a complex permission model in release 0. Start with role-gated
actions and keep all write actions server-side.

## 7. Core Information Architecture

### 7.1 Overview

The default page after login.

Shows:

- facility health summary
- active incidents and critical alerts
- app/service status
- public/private lane status
- running workflows
- recent workflow failures
- pending changes
- credential and certificate risk notices

This page answers: "What needs my attention right now?"

### 7.2 Facility

Inventory and topology view backed primarily by NetBox and Kubernetes.

Initial scope:

- environments
- cluster nodes
- namespaces
- applications
- endpoints/FQDNs
- ingress lane assignment
- storage summary
- certificate status

Later scope:

- media devices
- Flow Domains
- NMOS senders/receivers
- PTP domains
- timing islands

### 7.3 Workflows

Human-friendly forms and live status around AWX job templates.

Initial workflows:

- stack verify
- endpoint/certificate verify
- ESO/OpenBao health check
- NetBox registration dry-run

Each run gets:

- requested by
- parameters
- AWX job id
- start/end time
- status
- live event stream
- summary result
- linked audit record

### 7.4 Monitoring

Operator-facing health, not a Grafana replacement.

Initial scope:

- Alertmanager alert list
- grouped active alerts
- app endpoint probe state
- Prometheus target health
- certificate expiry summary
- node and PVC risk summary

Deep charts link to Grafana.

### 7.5 Changes

Config-change lane.

Initial scope:

- show open Forgejo PRs relevant to DMF repos
- show CI status
- show deploy/reconcile job status after merge
- create guided change drafts later

Long-term flow:

`draft in console -> Forgejo PR -> CI -> approve -> AWX apply -> verify -> audit`

### 7.6 Operations

Direct runtime lane.

Initial scope:

- safe verification and reconciliation operations
- acknowledgement and annotation actions
- console-local alert acknowledgements with operator notes

Later scope:

- route sender to receiver
- run show checklist
- arm/disarm tally
- validate source
- trigger flow diagnostics

### 7.7 Admin

Integration and platform configuration.

Initial scope:

- backend integration status
- configured API endpoints
- OIDC identity status
- service account credential health
- feature flags
- app contract registry status

## 8. Architecture

### 8.1 High-Level Shape

```text
Browser
  -> DMF Console UI
      -> DMF Console API / BFF
          -> NetBox API
          -> Prometheus API
          -> Alertmanager API
          -> AWX API
          -> Forgejo API
          -> Authentik OIDC/userinfo
          -> Kubernetes API
          -> OpenBao metadata/health only
```

The console API is a backend-for-frontend. It owns correlation, caching,
normalisation, RBAC enforcement, and audit emission.

### 8.2 Console-Owned Database

The database stores only console-owned state:

- users seen from OIDC, group snapshot, and preferences
- saved views and pinned facilities
- workflow run records and local summaries
- audit records emitted by console actions
- alert acknowledgements and operator notes
- integration health snapshots
- Resource Profile draft metadata
- app contract cache

It must not store:

- NetBox inventory as authoritative truth
- Prometheus metrics as a TSDB
- secret values
- Git repository content as truth
- AWX job output as the only source of execution truth

### 8.3 Integration Adapters

Implement each backend behind a small adapter interface:

| Adapter | Reads | Writes / Actions |
|---|---|---|
| NetBox | sites, clusters, devices, services, IPs, tags | later: registration/reconcile through controlled service account |
| Prometheus | targets, rules, query results | none initially |
| Alertmanager | active alerts, silences | acknowledge/silence later |
| AWX | templates, inventories, jobs, events | launch approved jobs |
| Forgejo | repos, PRs, checks, commits | create draft PRs later |
| Kubernetes | workloads, pods, PVCs, certificates, ingress | none initially; actions via AWX where possible |
| Authentik | OIDC login, user/group claims | none initially |
| OpenBao | seal/health/metadata and secret-reference validation | no raw secret read in normal UI paths |

Adapters should have explicit timeouts and return typed degraded states.

## 9. Domain Model

Initial internal objects:

| Object | Meaning |
|---|---|
| Facility | A deployed DMF environment or site |
| App | A DMF-managed application such as NetBox, Grafana, AWX, Forgejo |
| Endpoint | FQDN or internal URL plus lane, TLS, and probe state |
| HealthSignal | Normalised health input from Kubernetes, Prometheus, or HTTP probes |
| WorkflowTemplate | Console-approved wrapper around an AWX job template |
| WorkflowRun | One execution, linked to AWX and audit events |
| Change | Forgejo PR or future console-authored config draft |
| AlertSummary | Alertmanager alert grouped into operator-facing meaning |
| IntegrationStatus | Backend connectivity and credential health |
| ResourceProfileDraft | Future deployment wizard draft, not required for release 0 |

The `dmf_app_contract` concept from the Day-0 Inventory and Monitoring Plan
should become the bridge between app deployment roles and the console:

```yaml
dmf_app_contract:
  app: grafana
  display_name: Grafana
  fqdns:
    - grafana.dmf.example.com
  lane: private
  deep_links:
    primary: https://grafana.dmf.example.com/
  monitoring:
    probes:
      - grafana-ui
    prometheus_targets:
      - grafana
  workflows:
    - grafana-health-check
```

## 10. Initial Release Scope

### Release 0: Product Skeleton

Goal: replace the landing page with a real authenticated console shell.

Deliverables:

- FastAPI app scaffold
- Authentik OIDC login/logout
- base layout and navigation
- app shell for Overview, Facility, Workflows, Monitoring, Changes, Admin
- static app catalog loaded from config or app-contract fixture
- Helm chart updated enough to deploy
- health endpoint for Kubernetes probes

Acceptance:

- console deploys in cluster through `650-dmf-cms.yml`
- apex or chosen console hostname opens the console, not the old landing page
- unauthenticated users are redirected to Authentik
- authenticated users see the operational shell

### Release 1: Live App Catalog and Health

Goal: make the console more useful than the landing page.

Deliverables:

- app cards backed by live endpoint checks
- Kubernetes workload state for each app
- certificate expiry summary
- public/private lane label per app
- backend deep links
- integration status page

Acceptance:

- each app shows reachable/degraded/unavailable
- failures distinguish DNS, TLS, HTTP, Kubernetes, and unknown backend errors
- deep links remain available but are secondary

### Release 2: Workflow Launcher

Goal: prove the console can operate the platform.

Deliverables:

- AWX adapter
- approved workflow registry
- launch form for safe jobs
- live job status/events
- workflow run history
- audit record for every launch

Initial approved jobs:

- stack verify
- endpoint/certificate verify
- NetBox registration dry-run
- ESO/OpenBao health check

Acceptance:

- an Operator can launch a safe workflow without opening AWX
- status updates live until completion
- failure summary links to AWX for deep inspection

### Release 3: Alert and Monitoring Center

Goal: make active health actionable in the console.

Deliverables:

- Alertmanager adapter
- active alert list grouped by app/facility/severity
- Prometheus target health summary
- blackbox probe summary once probes exist
- acknowledgement notes in console DB

Acceptance:

- critical alerts appear on Overview
- app pages show relevant alerts
- stale/unavailable monitoring backend is visible as its own degraded state

### Release 4: Change-Control Lane

Goal: expose the config lane without replacing Forgejo.

Deliverables:

- Forgejo adapter
- open PR list for DMF repos
- CI/check status
- merged-change activity feed
- link workflow runs to commits or PRs where applicable

Acceptance:

- an Engineer can see pending DMF changes and their deployment/verification
  state from the console

### Release 5: Deployment Wizard Foundation

Goal: begin Resource Profile authoring without turning the console into a
second deployment engine.

Deliverables:

- Resource Profile draft model
- schema validation
- manifest preview
- secret-reference validation
- render/diff handoff design to `dmf-env`

Acceptance:

- the console can draft and validate a non-secret Resource Profile
- no playbook logic is embedded in the UI

## 11. Replacing The Landing Page

Recommended exposure:

- `https://console.<domain>` is the canonical public URL for DMF Console.
- `https://dmf.example.com/console` remains a supported fallback for
  environments without DNS control.
- `https://dmf.example.com/` may redirect to the console or serve the same app
  if the deployment wants a single apex entry point.
- Existing app hosts remain host-root subdomains:
  `auth`, `awx`, `forgejo`, `grafana`, `librenms`, `netbox`, `registry`.
- Preserve `/apps.json` temporarily for compatibility, but treat it as a
  console data source or legacy endpoint, not the primary UI.

Implementation note:

- The console must be path-aware from the start so `/console` can work cleanly
  without DNS changes. That means base-path configuration, path-safe assets,
  and OIDC redirect URIs for both host-based and path-based deployments.

## 12. Security Model

### 12.1 Authentication

Use Authentik OIDC from release 0.

Required claims:

- subject
- email or username
- display name
- groups

Map Authentik groups to the four initial console roles.

### 12.2 Authorization

All write actions are server-side and role-checked.

Examples:

- Viewer: no writes
- Operator: launch approved runtime workflows
- Engineer: create change drafts and launch reconcile workflows
- Admin: configure integrations and role mappings

### 12.3 Secrets

The console may validate that a secret reference exists and may show rotation
metadata where available. It must not display secret values in normal UI paths.

OpenBao interaction should be limited to:

- health/seal status
- metadata
- capability checks
- secret-reference validation

Break-glass credential retrieval remains outside the console unless explicitly
designed as a separate, audited ceremony.

### 12.4 Audit

Every write action records:

- actor
- role
- action
- target
- parameters hash or redacted parameters
- backend request id where available
- result
- timestamp

Audit records should later emit to Loki as structured events.

## 13. Implementation Order

### Phase A: Product and Contract Lock

- Record this plan as the initial product contract.
- Update `dmf-cms/README.md` and `CLAUDE.md` later to retire "tech stack TBD".
- Define app-contract fixture format.
- Decide apex vs `console.<domain>` exposure.

### Phase B: Repository Bootstrap

- Create FastAPI project layout.
- Add dependency management.
- Add lint/test workflow.
- Add Dockerfile for real app.
- Update Helm chart for environment variables, probes, service, ingress.
- Add local dev instructions.

### Phase C: Authenticated Console Shell

- Implement Authentik OIDC.
- Implement session handling.
- Implement role mapping.
- Build layout and navigation.
- Add placeholder pages with real backend health checks.

### Phase D: App Catalog and Health

- Implement app-contract loader.
- Implement endpoint checker.
- Implement Kubernetes adapter.
- Implement certificate summary.
- Replace landing page with Overview/App Catalog.

### Phase E: Workflows

- Implement AWX adapter.
- Define approved workflow registry.
- Add launch forms and run detail page.
- Add live status stream.
- Persist workflow run records.

### Phase F: Monitoring

- Implement Alertmanager adapter.
- Implement Prometheus target/probe summaries.
- Add Overview alert rollups.
- Add acknowledgement notes.

### Phase G: Change Lane

- Implement Forgejo adapter.
- Show PR and CI state.
- Link changes to workflow runs.

### Phase H: Resource Profile Wizard Foundation

- Add Resource Profile draft model and validation.
- Generate manifest preview.
- Validate secret references.
- Hand off rendering/execution to existing repos.

## 14. Verification Strategy

Each release needs evidence, not just a deployed pod.

Release 0:

- unit tests for config loading and OIDC role mapping
- container builds locally
- Helm template renders
- Kubernetes readiness/liveness pass
- Authentik redirect flow works

Release 1:

- app health tests with mocked reachable/degraded/unreachable backends
- live check against current DMF apps
- certificate expiry parsing test
- failure mode screenshots or captured responses

Release 2:

- AWX adapter tests with mocked API
- launch an approved no-op/safe job in live AWX
- prove audit record creation
- prove live status reaches terminal state

Release 3:

- Alertmanager adapter tests
- Prometheus target summary tests
- synthetic alert appears on Overview

Release 4:

- Forgejo adapter tests
- open PR and check status readback

## 15. Risks

| Risk | Mitigation |
|---|---|
| Console becomes a second source of truth | Enforce adapter boundaries and store only console-owned state |
| UI becomes a link portal again | Start with operator questions and health/workflow correlation |
| Full SPA complexity arrives too early | Use HTMX first; add frontend islands only for high-interaction views |
| Backend outages make the UI misleading | Typed degraded states and explicit stale timestamps |
| Overbroad credentials | One service account per backend with least privilege; read-only first |
| Workflow launches become unsafe | Approved workflow registry, role gates, parameter validation, audit |
| Media features distract release 0 | Keep Layer 4/5 views out of MVP until platform console works |

## 16. Decision Log

1. Product label: **DMF Console**.
2. Exposure: canonical `console.<domain>` plus supported `/console` fallback
   for environments without DNS control.
3. Console database: use a dedicated Postgres instance owned by the console
   deployment unless the platform already provides a hardened external Postgres
   service. Do not share the database with other apps.
4. Live updates: keep SSE for releases 0-2 unless a concrete WebSocket need
   appears.
5. App contract source: use a versioned YAML contract in `dmf-cms` as the
   source of truth, then generate runtime `apps.json` / ConfigMap artifacts
   from it.
6. First AWX workflows: `stack-verify`, `endpoint-certificate-verify`,
   `eso-openbao-health-check`, and `netbox-registration-dry-run`.
7. Alert acknowledgements: start console-local with notes and audit only;
   introduce Alertmanager silences later as a separate explicit action.

## 17. Definition of Done For Initial Implementation

The initial implementation is complete when:

- the current landing page has been replaced by an authenticated DMF Console
- the console shows live health for all current DMF apps
- operators can launch at least one safe verification workflow from the console
- workflow status is visible without opening AWX
- active alerts or monitoring degradation appear on the Overview
- every console action has an audit record
- backend failures degrade visibly and do not produce false-green states
- docs explain where the console owns state and where it only reads/correlates

At that point, the visible product exists. Media-specific workflow and routing
features can then land on top of a real operational surface instead of a link
portal.
