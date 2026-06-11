# DMF NetBox-Driven Dynamic Monitoring — Plan Handoff (2026-06-04)

**What:** a design conversation with the operator turned the legacy "Prometheus is
hardwired" issue into an approved, work-packaged plan for **NetBox-driven dynamic
monitoring** — monitoring that attaches/detaches automatically as a media facility's
devices, services, and media functions come and go. **This was a planning session
only — NO implementation has started.**

**Canonical plan:** [`docs/plans/DMF Dynamic NetBox-Driven Monitoring Plan 2026-06-04.md`](../plans/DMF%20Dynamic%20NetBox-Driven%20Monitoring%20Plan%202026-06-04.md)
— read it first; it has full context, conventions, reference patterns (file paths +
line hints), all 12 work packages, verification, and the resolved decisions. This
handoff is just the orientation layer on top.

---

## Why this exists (the legacy issue)

The Prometheus principle is proved, but target wiring is **hardwired/static** and
can't serve a dynamic facility:
- `dmf-infra/.../roles/base/prometheus/templates/scrape_configs.yml.j2` is a frozen,
  vendored copy of the chart-default scrape jobs (in-cluster k8s-SD only). NetBox
  plays **no part** in deciding what Prometheus monitors.
- `roles/modules/infra-monitoring/prometheus-snmp-exporter` is a `# TODO` stub
  ("targets generated from NetBox" — never built).
- **blackbox-exporter is not deployed at all**, yet the vendored config already
  references a `blackbox` host → dangling probe job (a real latent bug).
- The Day-0 plan's planned bridge roles (`netbox-register`, `dmf-app-register`,
  `dmf-monitoring-contract`, §13/§19) were never built. NOTE: `dmf-born-inventory`
  (playbook 694) **does** already register nodes + app-services into NetBox — the
  "born-inventoried" foundation exists; we're extending it, not starting cold.

## The goal (target architecture)

> NetBox is the single source of truth for what should be monitored. Prometheus +
> exporters **continuously** reconcile targets against live NetBox + Kubernetes
> state. Monitoring is born and dies with each device/service/function — no playbook
> re-run. This is the same SoT→scoped-reader→consumer relationship AWX already has
> via `nb_inventory`, applied to Prometheus.

## Decisions locked with the operator (do not relitigate)

1. **Two-lane discovery, one contract.** In-cluster pods → Prometheus **k8s-SD**
   (annotations; already self-healing). External/off-cluster (devices, NMOS nodes,
   FQDNs, SNMP) → live **NetBox http_sd**. Both fed by one catalog `monitoring:`
   contract via launcher tag/annotation stamping inside the lifecycle FSM.
2. **Standalone DMF PromSD adapter** (new repo `dmf-promsd`) is the http_sd bridge —
   NOT the `netbox-plugin-prometheus-sd` plugin. Rationale: air-gap (rides existing
   Zot image rail vs a custom NetBox image / missing PyPI mirror), version-compat
   (stable REST API decouples NetBox upgrades), and we own the target/label mapping.
3. **Cadence:** 30s Prometheus poll / ~45s adapter in-memory cache; NetBox webhooks
   deferred. Scaling path (poll → `last_updated` delta → webhooks+resync) recorded in
   the plan §Operator decisions #2 — the adapter's `/sd/*` contract stays stable
   across all three, so upgrades are non-breaking.
4. **Generic now, media exporters later** (NMOS/ST2110/PTP/flow telemetry deferred).
5. **dmf-catalog-svc** scoped writer needs **no permission bump** (WP1 pre-creates the
   tags/custom-fields; launcher only needs the `change` it already has).
6. **Branch discipline (ESSENTIAL — pre-release work):** every WP lands **directly on
   `main`** in every repo it touches — **no `feat/*` branches** for this effort,
   including the new `dmf-promsd` repo (default branch `main`). Verify `HEAD == main`
   before committing; reconcile any feature-branched sub-repo onto `main` first.

## Work-package roadmap (12 WPs; see plan for detail)

Dependency order: **WP0** → (WP1 ∥ WP2) → WP3 → WP4 → WP5 → (WP6 ∥ WP7) → WP8 →
(WP9 ∥ WP10) → WP11.

- **WP0** — ADR-0038 + monitoring contract schema (umbrella docs; unblocks all). *No code.*
- **WP1** — NetBox monitoring taxonomy + scoped `promsd-netbox` reader token (dmf-infra netbox-sot).
- **WP2** — blackbox-exporter role + `150-blackbox.yml` (dmf-infra) — fixes the dangling probe job.
- **WP3** — `dmf-promsd` FastAPI adapter (new repo): `/sd/{scrape,probe,snmp}` http_sd from live NetBox.
- **WP4** — adapter build/release + deploy role + ESO + playbook-630 Zot mirror entry.
- **WP5** — Prometheus http_sd jobs appended after the vendored blob (dmf-infra prometheus role).
- **WP6** — catalog `monitoring:` block + nmos-cpp launcher stamping (dmf-media + dmf-runbooks).
- **WP7** — born-inventory monitoring stamping (dmf-infra dmf-born-inventory).
- **WP8** — bootstrap wrappers + wizard wiring (profile-gated, after NetBox+token).
- **WP9** — snmp-exporter implementation (`full` profile; follow-on).
- **WP10** — logs relevance + alerts (follow-on).
- **WP11** — verification (190-monitoring-verify) + optional dmf-cms view + **live e2e**.

## Current state / next step

- **Status:** PLAN APPROVED, **zero implementation**. Operator instruction this
  session was explicitly "write plans only."
- **Task tracker:** 12 WP tasks created (all `pending`).
- **No sub-repos touched.** Umbrella has only the two new docs (this handoff + the
  plan) to commit.
- **Recommended next action when implementation resumes:** start **WP0** (ADR-0038 +
  schema, doc-only) — it makes the contract concrete so WP1/WP3/WP6 agents need no
  further design input. WP0 first commit should also create the `dmf-promsd` repo
  decision record.

## Open / watch items

- `dmf-promsd` repo creation is operator/ADR-worthy (like dmf-init was) — formalize in WP0.
- No live cluster is assumed; per-WP checks are lint/syntax/pytest. Live e2e (WP11)
  runs against the current `STATUS.md` env when a cluster is available (per memory,
  Hetzner env may be down — confirm before WP11).
- This plan **supersedes** the Day-0 plan §15 (bootstrap-time file_sd → live
  http_sd) — record the supersession in ADR-0038.
