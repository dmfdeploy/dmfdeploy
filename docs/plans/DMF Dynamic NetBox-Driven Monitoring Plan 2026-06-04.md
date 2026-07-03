---
status: executed
date: 2026-06-04
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/5
---
# DMF Dynamic NetBox-Driven Monitoring Plan (2026-06-04)
> Supersedes: [DMF Day-0 Inventory and Monitoring Plan.md](DMF%20Day-0%20Inventory%20and%20Monitoring%20Plan.md)

> **Executed (2026-07-03).** The core pipeline (ADR-0038 incl. Amendment A,
> the `dmf-promsd` adapter, netbox-sot seeding, born-inventory stamping)
> shipped 2026-06-04/05 and was validated live. The two remaining items
> closed via the
> [Monitoring Close-Out Work Packages 2026-07-02](DMF%20Monitoring%20Close-Out%20Work%20Packages%202026-07-02.md):
> **WP6 catalog-launcher stamping** (nmos-cpp stamps the Amendment-A cluster
> coordinates; the full deploy→finalise lifecycle proven live on the NetBox
> side) and **WP2/WP11 probe tuning** (ADR-0038 Amendment B `probe_path`
> field + `http_2xx_302` module; grafana and loki `probe_success 1`
> in-cluster; Loki's public-ingress probe workaround removed). **WP9
> (snmp-exporter) and WP10 (log-relevance alerts) remain deferred** —
> post-v0.1 scope alongside
> [#166](https://github.com/dmfdeploy/dmfdeploy/issues/166).

> **Status:** PLAN (2026-06-04). Design forks resolved with the operator in a
> plan-mode design conversation (see §Operator decisions). Broken into single-session
> work packages a freshly-cleared agent can pick up. **No implementation has started.**
> No live cluster is assumed mid-stream; live e2e is the final WP, run against the env
> in `STATUS.local.md` after running `bin/generate-status.sh` when a cluster is available.

---

## Context — why this work

We proved the Prometheus principle (a monitoring stack deploys and works). But the
current target wiring is **hardwired/static** and cannot serve a *dynamic media
facility* where devices, services, and media functions come and go:

- `roles/base/prometheus/templates/scrape_configs.yml.j2` is a **vendored, frozen
  copy** of the chart-default scrape jobs (pure in-cluster Kubernetes-SD + a static
  self-scrape). Helm replaces the list wholesale, so it's an opaque blob.
- **NetBox plays no part in deciding what Prometheus monitors.** The one lane that
  was meant to be NetBox-driven — `roles/modules/infra-monitoring/prometheus-snmp-exporter`
  — is an empty `# TODO: implement … targets generated from NetBox` stub.
- **blackbox-exporter is not deployed at all**, yet the vendored scrape config
  already references a `blackbox` target host → the `kubernetes-services` probe job
  is dangling.
- The planned bridge roles (`netbox-register`, `dmf-app-register`,
  `dmf-monitoring-contract`) from the Day-0 plan §13/§19 were never built.

Doctrine (already settled) says NetBox is the operational source of truth and
Prometheus derives its targets from it — exactly the relationship AWX already has
via the `nb_inventory` plugin. This plan realizes that relationship for Prometheus,
**continuously**, so monitoring attaches/detaches automatically as the facility
changes — with no playbook re-run.

**Canonical doctrine to (re)read:**
- `docs/architecture/DMF Platform Plan.md` §7a "Discovery architecture — three lanes"
- `docs/plans/DMF Day-0 Inventory and Monitoring Plan.md` (this plan supersedes its
  §15 *bootstrap-time file_sd* choice with a *live http_sd* adapter — record in ADR)
- ADRs: **0013** (catalog model), **0032** (scoped NetBox writer), **0037** (NetBox
  instance inventory), **0028** (identity/authority), **0034** (air-gap collections),
  **0010** (run-playbook.sh entry), **0003** (EBU vocabulary).

---

## Goal (target architecture)

> **NetBox is the single source of truth for what exists and what should be
> monitored. Monitoring (metrics, endpoint probes, log relevance) attaches and
> detaches automatically as devices, services, and media functions appear and
> disappear — no human action, no playbook re-run. Prometheus and its exporters
> continuously reconcile their target sets against live NetBox + Kubernetes state.**

### Two-lane discovery, one contract (DECIDED)

| Population | Lives in | Churn driver | Discovery lane |
|---|---|---|---|
| **In-cluster workloads** — platform apps, media-function *pods* | k3s | catalog launchers (AWX) deploy/teardown; k3s schedules | **Prometheus Kubernetes-SD** via pod/service `prometheus.io/*` annotations (already self-healing; keep) |
| **External / off-cluster** — physical media devices, NMOS nodes, SNMP gear, service FQDNs/ingress, appliances | **NetBox** (registered by nmos-cpp IS-04 discovery, `dmf-born-inventory`, catalog) | gear patched in/out; discovery registers/deregisters | **Prometheus continuous NetBox-SD (`http_sd`)** via the **DMF PromSD adapter** + blackbox + snmp |

Both lanes are fed by **one declarative monitoring contract**: a `monitoring:` block
in the catalog/app contract → the launcher stamps (a) `prometheus.io/*` annotations
+ standard labels on k8s objects, and (b) `monitoring:*` tags / custom-fields on the
NetBox objects, inside the existing lifecycle FSM
(`lifecycle:bootstrapped → active → bootstrapped`). Monitoring is thus *born and
dies with the function*, using the same tag-flip machinery as ADR-0032/0037.

Logs (Loki/Promtail) stay on **k8s-SD** (Promtail already follows pod churn); NetBox
tags drive log *relevance / ownership / retention class*, not discovery.

### The bridge: standalone DMF PromSD adapter (DECIDED)

A small **own-built FastAPI service** (`dmf-promsd`) in the `monitoring` namespace:
- holds a **scoped least-privilege NetBox read token** (ESO from OpenBao; mirrors the
  `awx-netbox` reader pattern), queries NetBox's **REST API** live;
- exposes Prometheus `http_sd` endpoints (`/sd/scrape`, `/sd/probe`, `/sd/snmp`)
  returning targets + labels derived from `monitoring:*` tags / custom-fields;
- ships as a **DMF image on the existing Zot rail** (built like dmf-cms/dmf-init).

Rationale vs the `netbox-plugin-prometheus-sd` alternative (rejected):
- **Air-gap:** adapter rides the existing GHCR→Zot image rail; a NetBox plugin would
  require a custom NetBox image *or* a Python-package mirror we don't have (ADR-0034).
- **Version-compat:** adapter uses the stable REST API, decoupling NetBox upgrades; a
  plugin couples our SoT's patch cadence to a third-party plugin's NetBox support.
- **Mapping:** we own the NetBox→target/label mapping to match our taxonomy (as
  `awx-integration` owns its `group_by`/`compose`).

---

## Conventions a fresh agent must follow

- **Boot ritual** (CLAUDE.md): `git fetch && pull` umbrella → `bin/generate-status.sh`
  → read `STATUS.local.md` → read newest `docs/handoffs/` → skim `docs/decisions/INDEX.md` → `git status` each
  sub-repo before touching; **ask before modifying a dirty sub-repo**. Land work on
  `main` (no feature branches — `feedback_converge_on_main_no_feat_branches`); verify
  HEAD==main first (`feedback_verify_main_branch_before_work`).
- **Branch discipline (ESSENTIAL — this is pre-release work):** every WP lands
  **directly on `main`** in every repo it touches — **no `feat/*` branches** for this
  effort. This includes the **new `dmf-promsd` repo** (init it with `main` as default).
  Verify `HEAD == main` before each commit; if a sub-repo is on a feature branch,
  stop and reconcile onto `main` first.
- **Playbook entry (ADR-0010):** only via `dmf-env/bin/run-playbook.sh <env> <playbook>`
  — it resolves inventory + injects OpenBao secrets at runtime. Never invoke
  `ansible-playbook` directly for live runs.
- **App-role anatomy** (`dmf-infra/k3s-lab-bootstrap/roles/{base,stack/operator}/<app>/`):
  `tasks/main.yml` (create ns → Helm repo → template values to `/tmp` →
  `kubernetes.core.helm` → wait → cleanup), `defaults/main.yml` (all vars,
  documented), `templates/*.j2`. kubeconfig is always `/etc/rancher/k3s/k3s.yaml`;
  plays run `hosts: k3s_control[0]`, `become: true`, `gather_facts: false`, with
  `roles: [base/cluster-ready, …]`.
- **Cross-app URLs** are cluster-internal svc DNS over plain HTTP server-side
  (ADR-0023): e.g. `http://prometheus-server.monitoring.svc.cluster.local/prometheus`,
  `http://loki-gateway.monitoring.svc.cluster.local`. PromSD adapter target:
  `http://dmf-promsd.monitoring.svc.cluster.local:<port>/sd/*`.
- **Identity (ADR-0028/0032/0033):** machine identities are **scoped, named,
  OpenBao-stored**; token ownership binds to the *authenticating principal* — set the
  service-account password, then auth **as** that account to mint a self-owned token
  (never admin-owned). Reader token path convention: `secret/apps/netbox/runtime`.
- **Air-gap (ADR-0034 / 0030 / 0031):** no public internet at runtime. Collections
  from internal Forgejo git mirrors (`ee/requirements.yml`, `netbox.netbox` present);
  images pulled at bootstrap and **mirrored to Zot via playbook 630**.
- **No IPs/DNS in public repos** — use vars + `dmf.example.com`. gitleaks + scrub run
  on commit.
- **Local checks** (no live cluster needed): `ansible-playbook --syntax-check`,
  `yamllint`, `ansible-lint`, shellcheck via `uvx --from shellcheck-py shellcheck`
  (`reference_shellcheck_via_uvx`); adapter `pytest`.

---

## Reference patterns (study before coding)

| Pattern | Where | Use as template for |
|---|---|---|
| **AWX↔NetBox contract** — `nb_inventory` scoped read | `roles/stack/operator/awx-integration/tasks/main.yml` (~L504–530): `plugin: netbox.netbox.nb_inventory`, `token`, `group_by: [sites, device_roles]`, `compose: {ansible_host: primary_ip4.address}` | The whole "NetBox SoT → scoped reader → consumer derives config" model the adapter realizes |
| **Scoped NetBox token + groups + tags + custom fields** | `roles/stack/operator/netbox-sot/{tasks/main.yml,defaults/main.yml}` (awx-netbox/awx-readonly; dmf-catalog-svc/dmf-catalog-writer; lifecycle/exposure tags; `dmf_*` custom fields + choice sets) | WP1 reader token + monitoring taxonomy |
| **Token mint inside NetBox pod (Django) → OpenBao** | `playbooks/698-cms-netbox-forgejo-tokens.yml` (`Token.objects.create`, store `secret/apps/netbox/runtime`) | WP1 token mint+persist |
| **Born-inventory: NetBox auth + REST registration** | `roles/common/dmf-born-inventory/{tasks/main.yml,app-service.yml,node.yml}` (OpenBao break-glass AppRole OR admin token; `ansible.builtin.uri` to NetBox API) | WP7 stamping; adapter NetBox query shape |
| **Catalog contract YAML** | `dmf-media/catalog/nmos-cpp.yaml` (`netbox_service.{ports,tags}`, `health_probe`) | WP6 `monitoring:` block |
| **Catalog launcher lifecycle FSM (tag flips)** | `dmf-runbooks/roles/nmos-cpp/tasks/{provision,configure,finalise}.yml` | WP6 tag/annotation stamping |
| **Build/release a DMF service image** | `dmf-cms` + `bin/publish-to-ghcr.sh`, playbook 630 (Zot mirror), playbook 650 (deploy), skill `dmf-cms-build-and-release`, `dmf-cms/docs/DEVELOPMENT-AND-BUILD-RULES.md` | WP3/WP4 adapter build+deploy |
| **FastAPI service + NetBox read token via ESO** | `dmf-cms/src/dmf_cms/` (backend), `contracts.py`, `config/app-contracts.yaml` | WP3 adapter scaffold |
| **Prometheus chart values + scrape include** | `roles/base/prometheus/templates/values.yml.j2` (`serverFiles.prometheus.yml.scrape_configs: {% include 'scrape_configs.yml.j2' %}`; `server.extraArgs`; `kube-state-metrics`/`node-exporter` enabled) | WP5 http_sd jobs + ConfigMap mounts |
| **Monitoring vertical order + profile gate** | `bootstrap-sandbox-provision-post-seed.yml` (100-prom→110-loki→130-promtail→120-grafana, each `when: dmf_monitoring_profile in ['minimal','full']`); `bootstrap-sandbox-profile.yml` | WP2/WP8 wiring |

---

## Work packages (each = one fresh-agent session)

> Dependency order: **WP0** → (**WP1**, **WP2** parallel) → **WP3** → **WP4** → **WP5**
> → (**WP6**, **WP7**) → **WP8** → (**WP9**, **WP10**) → **WP11**.
> Each WP: commit on `main` in the relevant repo(s); run the local checks listed in
> Conventions; report DONE/BLOCKED.

### WP0 — ADR + monitoring contract schema (umbrella docs only)
**Repo:** dmfdeploy umbrella. **No code.**
- New ADR `docs/decisions/0038-netbox-driven-dynamic-monitoring.md`: goal statement,
  two-lane model, the **monitoring contract** (catalog `monitoring:` block schema;
  NetBox tag taxonomy `monitoring:scrape|probe|snmp`; custom fields `metrics_port`,
  `metrics_path`, `probe_module`, `snmp_module`; k8s annotation/label conventions),
  the **standalone PromSD adapter** decision + rationale (air-gap/version/mapping),
  and the supersession of Day-0 plan §15 (file_sd-at-bootstrap → live http_sd).
  Reciprocal links to ADR-0013/0027/0032/0037/0034/0023.
- Update `docs/decisions/INDEX.md` (row + catalog/execution cluster note).
- Record the `dmf-promsd` new-repo decision (see §Operator decisions).
**Done:** ADR committed, INDEX updated, schema unambiguous enough that WP1/WP3/WP6
agents need no further design input.

### WP1 — NetBox monitoring taxonomy + scoped reader token (dmf-infra)
**Files:** `roles/stack/operator/netbox-sot/{tasks/main.yml,defaults/main.yml}`,
playbook `playbooks/691-netbox-sot.yml`.
- Create monitoring **tags** + **custom fields** (+ choice sets for module/severity),
  mirroring the existing lifecycle-tag and `dmf_*` custom-field creation blocks
  (idempotent; warn-on-type-drift, no PATCH — copy that pattern).
- Add service account **`promsd-netbox`** + group **`monitoring-readonly`** with
  *view* on `ipam.service`, `ipam.ipaddress`, `dcim.device`, `dcim.interface`,
  `virtualization.virtual-machine`, `extras.tag` — mirror the `awx-netbox`/
  `awx-readonly` block. Mint a **self-owned** token (auth as the account) and persist
  to OpenBao `secret/apps/netbox/runtime` field `promsd_api_token` (698 pattern).
**Checks:** `--syntax-check`, ansible-lint, yamllint.

### WP2 — blackbox-exporter role + playbook (dmf-infra)
**Files:** new `roles/base/blackbox-exporter/{tasks/main.yml,defaults/main.yml,templates/values.yml.j2}`;
new `playbooks/vertical-monitoring/150-blackbox.yml`.
- Helm `prometheus-community/prometheus-blackbox-exporter` → **service `blackbox`** in
  `monitoring` ns (this is the host the vendored scrape config already targets).
- Modules: `http_2xx`, `http_2xx_insecure` (local-CA lane — see grafana CA notes),
  `tcp_connect`, `icmp`. Sandbox-sized resources (follow prometheus/loki sizing
  precedent in their defaults).
**Checks:** `--syntax-check`, lint; template-render the values.

### WP3 — dmf-promsd adapter service (scaffold + endpoints)
**Repo:** `dmf-promsd` (new — see Operator decisions).
- FastAPI app mirroring dmf-cms backend layout; `VERSION`, `Dockerfile`, `pyproject`,
  tests. Config: `NETBOX_URL`, `NETBOX_TOKEN` (from env/secret), `validate_certs`.
- Endpoints returning **Prometheus http_sd JSON**:
  - `/sd/scrape` — services/devices tagged `monitoring:scrape`; `__address__` +
    `__metrics_path__` from custom fields; labels from `app:*`/`exposure:*`/site.
  - `/sd/probe` — `monitoring:probe` objects → blackbox targets; `__param_module`
    from `probe_module`; relabel for the blackbox `/probe` indirection.
  - `/sd/snmp` — `monitoring:snmp` devices → snmp targets; `__param_module` from
    `snmp_module`.
- Read-only NetBox REST queries (tag-filtered); in-memory cache refreshed ~45s
  (see §Operator decisions #2). Unit tests against a NetBox fixture/mock (no live
  cluster needed). Health endpoint.
**Checks:** `pytest`, `ruff`/lint, `docker build` (local), shellcheck any scripts.

### WP4 — adapter build/release + deploy role + ESO (dmf-infra + dmf-promsd)
**Files:** dmf-promsd `bin/publish-to-ghcr.sh` (model on dmf-cms); dmf-infra
`roles/stack/operator/dmf-promsd/` deploy role + `playbooks/…-promsd.yml`; add the
image to the **playbook 630** GHCR→Zot mirror set; ESO `ExternalSecret` mapping
`secret/apps/netbox/runtime#promsd_api_token` → k8s Secret in `monitoring`.
**Checks:** lint; `--syntax-check`; verify 630 mirror list includes the image.

### WP5 — Prometheus http_sd wiring (dmf-infra prometheus role)
**Files:** `roles/base/prometheus/templates/scrape_configs.yml.j2` (append **after**
the vendored blob — do not edit the vendored jobs), `templates/values.yml.j2`.
- Add three jobs with `http_sd_configs: [{ url: http://dmf-promsd.monitoring.svc…/sd/<lane>, refresh_interval: 30s }]`:
  `netbox-scrape`, `netbox-probe` (blackbox indirection relabel → `__address__: blackbox…`),
  `netbox-snmp` (snmp-exporter indirection). Honor labels from the adapter.
- Keep the self-scrape `metrics_path` fix and all chart-default jobs intact.
**Checks:** render values, validate YAML, `promtool check config` if available locally.

### WP6 — Catalog `monitoring:` block + launcher stamping (dmf-media + dmf-runbooks)
**Files:** `dmf-media/catalog/nmos-cpp.yaml` (+ schema doc/README);
`dmf-runbooks/roles/nmos-cpp/tasks/{provision,configure,finalise}.yml`.
- Add `monitoring:` block (scrape? probe module? snmp? metrics path/port; per WP0
  schema). On **provision/configure**: stamp `monitoring:*` tags + custom fields on
  the `ipam.service` (via the `dmf-catalog-svc` scoped writer — extend its perms if a
  new object/field write is needed, per ADR-0032) **and** `prometheus.io/*`
  annotations + labels on the k8s workload. On **finalise**: remove them — inside the
  existing lifecycle tag-flip.
**Checks:** lint; `--syntax-check`; dry catalog-schema validation.

### WP7 — born-inventory monitoring stamping (dmf-infra)
**Files:** `roles/common/dmf-born-inventory/tasks/app-service.yml` (+ defaults).
- When registering platform-app services, stamp `monitoring:probe` (+ `probe_module`,
  `exposure:*`) so every born-inventoried app is probed by blackbox via the adapter.
**Checks:** `--syntax-check`, lint.

### WP8 — bootstrap wiring + wizard sizing (dmf-infra wrappers + dmf-env)
**Files:** `bootstrap-sandbox-provision-post-seed.yml`,
`bootstrap-provision-post-seed.yml`; dmf-env wizard sandbox inventory block if sizing
vars are needed.
- Import `150-blackbox` + the promsd deploy after monitoring core and after NetBox is
  live, `when: dmf_monitoring_profile in ['minimal','full']`. Adapter needs NetBox
  (610) + the WP1 token (691) before it can serve.
**Checks:** `--syntax-check` the wrappers; confirm import order.

### WP9 — snmp-exporter implementation (dmf-infra; `full` profile) — follow-on
**Files:** `roles/modules/infra-monitoring/prometheus-snmp-exporter/tasks/main.yml`
(replace TODO stub); a `vertical-monitoring/1NN-snmp-exporter.yml`.
- Deploy snmp-exporter; consume adapter `/sd/snmp`. Gated to `full` (no SNMP gear in
  current envs). **Checks:** lint, syntax-check.

### WP10 — logs relevance + alerts (dmf-infra loki/promtail) — follow-on
**Files:** `roles/base/promtail/*`, `roles/stack/operator/loki/*`,
`roles/base/prometheus` alert rules.
- Verify Promtail k8s-SD covers all pod logs (not just k3s-audit); add NetBox-tag-
  driven ownership/retention-class labels; a minimal set of metric/log alerts per
  registered service. **Checks:** lint, syntax-check.

### WP11 — verification + console surfacing + live e2e (dmf-infra + optional dmf-cms)
**Files:** `playbooks/vertical-monitoring/190-monitoring-verify.yml`; optional dmf-cms
monitored-inventory view.
- Extend 190 to assert NetBox-derived targets are **present and `up`** in Prometheus
  (scrape + probe lanes), and that a catalog deploy/teardown adds/removes targets.
- **Live e2e** against the current `STATUS.local.md` env when a cluster exists: deploy a
  catalog media function → confirm metrics + probe appear automatically → teardown →
  confirm they disappear, with no playbook re-run. See §Verification.

---

## Verification (end-to-end, WP11)

1. `bin/generate-status.sh`; pick the live env id from `STATUS.local.md`.
2. `dmf-env/bin/run-playbook.sh <env> …/playbooks/vertical-monitoring/<…>` to deploy
   blackbox + promsd; confirm pods Running in `monitoring`, ESO secret populated.
3. Prometheus **Targets** page (via Grafana datasource proxy): `netbox-scrape`,
   `netbox-probe`, `netbox-snmp` jobs present; born-inventoried apps show as `up`
   probes.
4. **Dynamic test:** deploy a catalog function (AWX `media-launch-nmos-cpp`) → within
   one `refresh_interval` its metrics scrape + endpoint probe appear **without** any
   playbook run; run `media-finalise-nmos-cpp` → targets disappear.
5. Logs: the function's pod logs are queryable in Grafana/Loki and carry the
   ownership label.
6. `promtool check config` clean; no `CERTIFICATE_VERIFY_FAILED` in adapter/blackbox
   logs on the local-CA lane.

---

## Operator decisions (resolved)

1. **`dmf-promsd` repo home — RESOLVED: new component repo `dmf-promsd`** (mirrors
   `dmf-cms`/`dmf-init` as an independent service repo with its own build/release
   rails). Treat repo creation as operator/ADR-worthy (record in WP0 ADR).
2. **Adapter refresh cadence / NetBox load — RESOLVED: cache-decoupled poll.**
   Prometheus `http_sd refresh_interval: 30s`; the adapter serves from an in-memory
   cache refreshed on its own ~45s timer, so NetBox is queried at a fixed low rate
   regardless of how many Prometheus replicas poll (same idea as `nb_inventory`'s
   `cache`/`cache_timeout: 3600` in `awx-integration`). NetBox webhook → cache
   invalidation deferred (poll is sufficient for v1). Worst-case churn-detection
   latency ≈ refresh_interval + cache TTL (~75s) — fine for discovery (scrape
   interval is separate).

   **Scaling path (record for future agents).** The full-snapshot poll's cost
   scales with *total monitored-object count N* (⌈N/1000⌉ paged, tag-filtered NetBox
   list reqs/sweep), **not** with change rate — comfortable to ~tens of thousands of
   objects (well beyond experiment-phase facility sizes), but wasteful at very large
   N because it re-serializes a mostly-unchanged set every sweep. The adapter's
   external `/sd/*` http_sd contract never changes, so each upgrade is internal +
   non-breaking:
   - **v1 (this plan):** full-snapshot poll + in-memory cache.
   - **v1.5 (cheap, pull-only):** delta sweeps via `?last_updated__gte=<since>` with
     an occasional full sweep to catch deletes — ~80% of the webhook benefit, no new
     infrastructure (no inbound endpoint/HMAC/lossy events). First lever if poll cost
     climbs.
   - **v2 (webhooks + slow resync):** NetBox webhooks (object-type + condition
     filtered) → HMAC-verified adapter ingest applies deltas; **keep** a slow
     (5–15 min) full resync for correctness (webhooks are lossy under adapter
     downtime; a missed *delete* would orphan a target). Cost then scales with change
     rate; latency sub-second. Add when metrics demand it.
   - **Upgrade triggers:** NetBox list-query p95 rising, adapter sweep duration
     nearing the refresh interval, payload into tens of MB, or a need for sub-10s
     churn detection.
3. **`dmf-catalog-svc` permission extension — RESOLVED: no extension expected.**
   WP1 pre-creates the monitoring **tags + custom-field definitions** at bootstrap
   (netbox-sot). The launcher then only *references* them, which is a `change` on
   `ipam.service` (already granted) + `extras.tag: view` (already granted). A grant
   bump is needed **only** if monitoring metadata is stamped on `dcim.device`
   objects via the catalog writer (currently device = view-only) — but external
   devices are stamped by nmos-cpp/born-inventory under different writers, not the
   catalog launcher. Confirm at WP6; bump ADR-0032 only if that case arises.

## Out of scope (explicit, deferred)
- Media-specific exporters: NMOS-node health, ST2110/PTP telemetry, flow metrics
  (operator chose "generic now, media exporters later").
- Migration to Prometheus Operator / ServiceMonitor CRDs (stack uses the community
  `prometheus` chart; http_sd is the chosen mechanism).
- `netbox-plugin-prometheus-sd` (rejected — see §bridge).
- Live NetBox webhook → adapter push (poll is sufficient for v1).
