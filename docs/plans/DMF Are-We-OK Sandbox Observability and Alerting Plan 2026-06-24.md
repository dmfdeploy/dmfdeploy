---
status: executed
date: 2026-06-24
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/166
---
# DMF "Are We OK?" Sandbox Observability & Alerting Plan (2026-06-24)

> **STATUS: EXECUTED (2026-07-04).** Implemented in `dmf-infra` PRs
> [#36](https://github.com/dmfdeploy/dmf-infra/pull/36) (WP-A..D + WP-F: rules-as-code,
> alert suite, static probe lanes, AWX monitoring-apply lane, `195-are-we-ok-verify`)
> and [#38](https://github.com/dmfdeploy/dmf-infra/pull/38) (WP-E + WP-G: verdict +
> Platform-services dashboards, DMF/System provider split; re-land of #37, which
> auto-merged into its stacked base). Live-verified on the `aoka-9dat` cloud sandbox
> (fail-soft path: full rule suite with Alertmanager disabled). Open follow-ups are
> tracked on issue #166: `dmf-runbooks/docs/alerts.md` runbook targets, AM inhibition
> for warn/crit duplicate names, OQ-5 threshold baselining.
>
> Prior status note (adoption, 2026-07-03): adopted with **Amendment A** adding WP-G —
> Grafana dashboard alignment (demote the lab-era k8s-views set, add the NetBox-driven
> "Platform services" dashboard). Original proposal preamble follows.
>
> **STATUS AT AUTHORING: PROPOSED — for adversarial cross-check before any code lands.**
> This is a design/spec doc only. No `dmf-infra` edits have been made. It captures the
> full context, the live evidence it is grounded in, the decisions taken (and who/what
> drove them), ADR conformance, the proposed work packages, the alternatives rejected,
> the resource budget for a saturated node, and an explicit open-questions list for the
> reviewer. Per [WORKING-MODEL](../WORKING-MODEL.md) a tracking issue must be opened and
> referenced in frontmatter before the implementing PR.

**Component:** `dmf-infra` (prometheus / grafana / blackbox-exporter roles), delivered via the
committed **Forgejo → AWX → Ansible/Helm** chain. Doc lives in the umbrella per convention.
**Trigger:** Operator request — author detailed Prometheus/Grafana alerts capturing *all*
relevant metrics from the live sandbox (dmf-sandbox host + the NetBox-driven SD pipeline),
including RPi metrics (temperature, fan, network latency/jitter), to back one definitive,
reliable **"Are we OK?"** dashboard pane.
**Reframing from the operator (load-bearing):** *"this env is a sandbox and ridiculously
under-sized; it's more like worst-case-scenario — will it still run and break gracefully."*
The deliverable is therefore a **graceful-degradation observability slice**, not capacity
planning.

---

## 1. Context & motivation

The target is the current single-node k3s sandbox env (id `<sandbox-env-id>` at time of survey) on a
**Raspberry Pi 4, 4-core / 8 GB** at `<lan-ip>`. It runs a full DMF stack (authentik, netbox,
awx, forgejo, zot, dmf-cms, nmos, openbao, cert-manager, external-secrets, and the monitoring
namespace).

This is a **deliberately undersized worst-case rig.** Its value is exactly that it sits on the
edge of resource exhaustion, so it surfaces *how the platform behaves when starved*. The
"Are we OK?" pane must answer one question for an operator at a glance: **is the platform up
and degrading gracefully, or is it failing — and if so, where?**

This work is the natural sequel to the **`DMF Constrained-Node k3s Control-Plane Stability
Plan 2026-06-21`** (dmfdeploy#106), which *diagnosed and mitigated* the dominant failure mode
on this exact node: AWX staying awake through configure → RAM exhaustion → `kswapd` thrash →
load 28–35 → k3s `Restart=always` cycling → transient 6443/Forgejo/SSH refusals. That plan
**fixed** the trigger; **this plan instruments it** so the next regression is *seen* (and
alarmed) instead of rediscovered by hand. The alert thresholds below are chosen to light up on
precisely that chain (memory pressure, swap thrash, high load, k3s/api flaps).

### Design constraints that fall out of "worst-case + graceful"
1. **Featherweight.** Additions must not themselves tip the node over. No heavy controllers;
   conservative scrape/probe intervals; recording rules to keep the dashboard cheap.
2. **Fail-soft & loud.** Monitoring must *self-monitor* — if Prometheus/Alertmanager/scrapes
   break, that must be visible, not silent. The verdict pane must still render a meaningful
   answer when a dependency is degraded.
3. **Warn-before-crit.** On a node that is *normally* near the edge, alerts need hysteresis and
   generous `for:` debounce or they flap. "Graceful" means amber before red.

---

## 2. Live survey evidence (verified 2026-06-24)

All facts below were captured by read-only SSH + `k3s kubectl` against `<lan-ip>`. They are the
ground truth the design is built on; a cross-checker should be able to re-run and reproduce.

### 2a. Node is on the edge — and memory/IO-bound, not CPU-bound
- `uptime`: load average **~24 on 4 cores**; `free -h`: **63 MiB free**, 2.4 GiB available,
  swap 246 MiB used of 2 GiB.
- `kubectl top node`: **CPU ~47%**, **MEM ~76%** — i.e. load ≫ CPU%, confirming the bottleneck
  is **memory reclaim / swap / IO wait**, not compute. (This matches dmfdeploy#106's kswapd
  finding; it tells us the *primary* alert signals must be memory/swap/iowait, not CPU.)
- Several pods are **already silently restarting**: authentik-server 9× / authentik-worker 17×,
  netbox-worker 8×, `dmf-promsd` 7×, `zot-0` 6× — the "does it break gracefully" story is
  **live right now and currently unobserved**.

### 2b. RPi thermal/fan signals are present via node-exporter
- `node_hwmon_temp_celsius{chip="thermal_thermal_zone0"}` ≈ **56 °C**.
- `node_cooling_device_cur_state{type="pwm-fan"}` = **4**, `..._max_state` = **4** → **fan
  pinned at max** (corroborates sustained thermal/work load).
- `vcgencmd` is **unavailable** in this image (`/dev/vcio_gencmd` missing) → Pi-specific
  under-voltage/throttle flags cannot be read. **Decision:** rely on node-exporter
  thermal/cooling only; do *not* add a vcgencmd-based rpi-exporter (it would not function here).
- **Cross-env caveat (verified on the `<lima-vm-lan-ip>` Lima VM sandbox, env `<lima-env-id>`, 2026-06-24):**
  the thermal/fan series are **bare-metal-Pi-only**. On the Lima VM, node-exporter exposes **no
  `node_hwmon_temp_celsius` / `node_thermal_zone_temp`**, and `node_cooling_device_*` is 6
  virtual `type="Processor"` entries at state 0 (not a `pwm-fan`). → the thermal recording rules
  (`rpi:node_temp_celsius:max`, `rpi:fan_saturation`), the `HostThermalHot`/`HostFanMaxed`
  alerts, and the verdict pane's temp clause **must tolerate the series being absent** (guard
  with `absent()` / treat missing as "n/a", not "bad") so the dashboard verdict doesn't go null
  on VM envs. Everything else (rules empty, no Alertmanager, config-reloader sidecar, Grafana 11
  no-sidecar, born-inventory-not-a-service, dmf-promsd present) is **identical across `<pi-lan-ip>` and
  `<lima-vm-lan-ip>`** — the plan is env-portable.

### 2c. Monitoring stack already deployed (prometheus community chart)
| Component | Observed state |
|---|---|
| `prometheus-server` | chart image `v2.48.0`; **2/2** = server + `prometheus-config-reloader v0.67.0` sidecar (hot-reloads on ConfigMap change) |
| Rule source | single Helm-managed ConfigMap `prometheus-server`, mounted at `/etc/config`; keys include `alerting_rules.yml`, `recording_rules.yml`, `prometheus.yml` |
| **Alert rules** | `alerting_rules.yml` **and** `recording_rules.yml` are **empty `{}`** — zero alerts exist today |
| Alertmanager | **NOT deployed** (no deploy/sts/svc) |
| Exporters | node-exporter, kube-state-metrics, cAdvisor (via kubelet), blackbox-exporter all present |
| Grafana | `11.0.0`, **no dashboard sidecar** → dashboards come only from ConfigMap `grafana-custom-dashboards` (currently 4 k8s-views dashboards) |
| `dmf-promsd` | running; NetBox-driven `http_sd`; health at `/healthz` + `/readyz`; **exposes no `/metrics`** of its own |
| `dmf-cms` | exposes `:8000` but **no native `/metrics`** (its `prometheus.py` is a *client* that queries Prometheus) |
| GitOps controllers | **none** (no Argo / Flux / git-sync / reloader-operator) |
| Forgejo Actions runner | **none deployed** |
| Forgejo repos (anon-visible) | includes `forgejo-svc/dmf-runbooks` |

### 2d. Scrape mechanism
Standard community-chart jobs: `kubernetes-service-endpoints` (annotation-driven:
`prometheus.io/scrape|port|path`), `kubernetes-nodes` + `kubernetes-nodes-cadvisor`, blackbox
via `kubernetes-services` (`prometheus.io/probe`), plus the **NetBox SD jobs** (`netbox-scrape`,
`netbox-probe`, `netbox-snmp`) that consume `dmf-promsd`'s `http_sd` endpoints (ADR-0038).

---

## 3. Decisions taken (interactive, with rationale)

These were settled with the operator during planning. Recorded here so the cross-checker can
challenge them directly.

| # | Decision | Operator choice | Rationale / consequence |
|---|---|---|---|
| D1 | **Where alert rules live** | As code in **in-cluster Forgejo** | Rules-as-code, reviewable, versioned. Combined with D2 below this rides the committed SCM lane. |
| D2 | **Delivery engine (GitOps)** | **Forgejo → AWX → Ansible** (not ArgoCD, not Forgejo Actions, not git-sync) | ArgoCD is an explicit v0.1 non-goal (§4). AWX is the committed v0.1 actuator and Forgejo is its SCM source. **Zero new runtime components** — lightest possible on a saturated node. Operator initially picked "Forgejo Actions CI" but reversed to the AWX lane after the ADR context surfaced (no runner is even deployed). |
| D3 | **Alerting depth** | **Alertmanager + notify *and* the dashboard pane** | Real notifications via the *existing* (currently disabled) Alertmanager + `ntfy` bridge, plus a pane that reads alert state. The pane reads `ALERTS` directly so it survives Alertmanager being down. |
| D4 | **"born-inventory"** | **Monitor the SD pipeline** | born-inventory is a *one-shot NetBox-seeding Ansible job* (role `common/dmf-born-inventory`, playbook `694`), **not** a running service. "Monitoring it" = watching the NetBox → `dmf-promsd` → Prometheus discovery pipeline (promsd health, NetBox reachability, discovered-target freshness). Consistent with monitoring-plan WP7/WP10. |
| D5 | **Latency/jitter targets** | **All four lanes** | LAN gateway (`<lan-gateway>`), public internet anchor (1.1.1.1 / 8.8.8.8), cluster ingress (Traefik), and inter-pod/DNS (CoreDNS + a representative ClusterIP). |
| D6 | **Scope / version** | **"Forgejo only for now, v0.1 target"** | First minimal increment of *this* observability feature. ArgoCD deferred to v0.2. Framed as a **v0.1 observability-hardening slice that is non-blocking to the v0.1 release gates** (see §4). |

---

## 4. ADR / roadmap conformance

Direct citations the design must not violate (a reviewer should verify each):

- **ArgoCD is a v0.1 non-goal.** `architectural-commitments-v1.md`: *"Argo-for-k8s + AWX-glue
  hybrid actuator. Do not build a hybrid framework to avoid choosing. AWX is the v0.1 actuator.
  **Argo is a future spike, not a dependency.**"* → D2 conforms; ArgoCD is deferred to v0.2.
- **Committed control chain is Forgejo → AWX → Ansible.** ADR-0041 (release & contribution
  model) + commitments §C5: *in-cluster Forgejo is the AWX SCM source*; *"AWX is the catalog
  actuator."* → D1/D2 ride this lane; no Forgejo Actions runner (which is *not* part of the
  committed chain and is not deployed).
- **Monitoring is NetBox-driven.** `0038-netbox-driven-dynamic-monitoring.md`: *"NetBox is the
  single source of truth for monitoring intent … in-cluster workloads are discovered by
  Prometheus k8s SD; external/off-cluster objects via a live `http_sd` bridge … the bridge is a
  standalone DMF PromSD service."* → D4 (SD-pipeline health) and the static-probe approach for
  *non-NetBox* anchors in §5/WP-D are designed around this, not against it.
- **Alerting is formally deferred to post-v0.1 ("April P0s").** Hence D6's framing: this is a
  **hardening slice that stress-validates the committed architecture**, explicitly *not* new
  release-claim scope. It does not touch any v0.1 release gate. The full alarm
  classification/lifecycle is owned by the (stub) `DMF Console Alarm Philosophy` doc and is out
  of scope here — these are raw Prometheus alerts, not console-classified alarms.
- **Existing (disabled) notify infra.** The prometheus role already ships
  `templates/ntfy_bridge.py.j2` and `prometheus_alertmanager_{enabled,ntfy_url,watchdog_url}`
  defaults → D3 is *enable + configure*, not net-new build.
- **Public-repo hygiene.** This doc uses placeholders (`<lan-ip>`, `<lan-gateway>`,
  `<base-domain>`) per the umbrella IP/DNS convention; concrete values live only in `dmf-env`.

---

## 5. Proposed design — work packages

> All rule/dashboard content is authored as **discrete, diffable files** under the `dmf-infra`
> roles (not inline jinja), so "rules-as-code" is reviewable. The prometheus
> `templates/values.yml.j2` is refactored to **slurp** `files/rules/*.yaml` into the
> `serverFiles.{alerting_rules,recording_rules}.yml` keys.

### WP-A — Enable resource-capped Alertmanager + ntfy notify
- `roles/base/prometheus/defaults/main.yml`: `prometheus_alertmanager_enabled: true`; set
  `prometheus_alertmanager_ntfy_url` (in-cluster `ntfy.<base-domain>`) and
  `prometheus_alertmanager_watchdog_url` (healthchecks.io dead-man's-switch). Env-specific URLs
  live in `dmf-env`.
- `roles/base/prometheus/templates/values.yml.j2` (alertmanager block): **replicas=1**, tight
  requests/limits (target ~`32–64Mi` mem / `25m` cpu), short retention (~2h), `emptyDir` or a
  tiny PVC. Reuse `ntfy_bridge.py.j2` as the receiver.
- **Fail-soft:** verdict pane reads `ALERTS` from Prometheus directly; an `AlertmanagerDown`
  self-alert (WP-C group 3) covers the notify path itself.

### WP-B — Recording rules (cheap pane + stable alerts)
New `roles/base/prometheus/files/rules/recording.yaml`:
- `instance:node_load_per_core`, `instance:node_mem_avail_ratio`, `instance:node_swap_used_ratio`,
  `instance:node_iowait_ratio` (the real saturation signal here).
- `rpi:node_temp_celsius:max` (max across thermal zones), `rpi:fan_saturation` (cur/max state).
- `probe:latency_avg`, `probe:latency_jitter` = `stddev_over_time(probe_duration_seconds[10m])`,
  `probe:loss_ratio` = `1 - avg_over_time(probe_success[10m])`.
- `dmf:targets_up_ratio` (per job), `dmf:promsd_discovered_targets` (count of NetBox-SD targets).

### WP-C — Alert suite: "graceful degradation" (`files/rules/alerts.yaml`)
Generous `for:`, warn-before-crit, `severity` label (`critical|warning|info`), `runbook_url`
annotation into `dmf-runbooks`. Groups:
1. **node-saturation** — `HostMemoryPressure` (avail <10% 5m warn / <5% crit), `HostSwapThrashing`
   (si+so rate high), `HostHighLoad` (load_per_core >4 for 10m), `HostIOWaitHigh`,
   `HostThermalHot` (>70 warn / >80 crit), `HostFanMaxed` (saturated 15m, info),
   `DiskNearFull` (>85%, reuses `prometheus_alert_pv_full_threshold`).
2. **workload-health** — `PodCrashLooping`, `PodOOMKilled`
   (`kube_pod_container_status_last_terminated_reason="OOMKilled"`), `KubeNodeNotReady`,
   `PodNotReady`, `ContainerCPUThrottling`. *(These would already be firing on the live node.)*
3. **monitoring-self** — `TargetDown` (critical jobs), `AlertmanagerDown`,
   `PrometheusTSDBReloadFailed`, `PrometheusRuleEvalFailures`. *(So monitoring breaks loudly.)*
4. **sd-pipeline / born-inventory** — `PromsdDown` (blackbox `/healthz`, since promsd has no
   `/metrics`), `NetBoxUnreachable` (blackbox), `DiscoveredTargetsZeroOrStale`
   (`dmf:promsd_discovered_targets` → 0 or drops vs baseline).
5. **connectivity** — `GatewayUnreachable`/`GatewayHighJitter` (LAN), `InternetUnreachable`/
   `InternetHighLatency`, `IngressDown` (Traefik), `DNSSlowOrDown` (CoreDNS).

### WP-D — Blackbox probe targets (4 lanes) + `dns` module
- In-cluster targets (ingress, CoreDNS, representative ClusterIP) → prefer NetBox/promsd
  discovery (ADR-0038) where a NetBox object exists.
- **Non-NetBox external anchors** (LAN gw `<lan-gateway>`, `1.1.1.1`, `8.8.8.8`) → a **static
  blackbox probe job** via `extraScrapeConfigs` in `scrape_configs.yml.j2`. Add a `dns` module
  to `roles/base/blackbox-exporter/defaults/main.yml` (`icmp`/`http_2xx_insecure`/`tcp_connect`
  already exist). Probe `interval` **~60s** to bound load; jitter derived in WP-B.

### WP-E — "Are we OK?" Grafana dashboard
- New `roles/base/grafana/files/dmf-are-we-ok.json`; register in
  `roles/base/grafana/templates/configmap-dashboards.yml.j2` (the `grafana-custom-dashboards`
  ConfigMap). No sidecar exists, so this is the only delivery path.
- **Top verdict pane** (single stat, green/amber/red): GREEN iff
  `count(ALERTS{alertstate="firing",severity="critical"}) == 0` **and** key probes up **and**
  `instance:node_mem_avail_ratio > 0.05` **and** the temp clause holds *where it exists*
  (`rpi:node_temp_celsius:max < 80 OR absent(rpi:node_temp_celsius:max)` — so VM envs without
  thermal sensors stay GREEN rather than null; see §2b cross-env caveat).
- Supporting rows, recording-rule-backed, long min-interval, few panels (stays legible under
  load): node saturation, workload health, connectivity (latency/jitter/loss per lane),
  SD-pipeline health, monitoring self-health.

### WP-F — Delivery wiring (Forgejo → AWX → Ansible)
- Author files in `dmf-infra` (GitHub `main` canonical per ADR-0041); they reach the cluster via
  the in-cluster **Forgejo mirror** that AWX uses as SCM source.
- **Verified (OQ-1 resolved — live AWX, 2026-06-24):** the `dmf-infra` AWX project exists and
  **SCM-syncs successfully** from the Forgejo mirror (live ORM check: 5 projects — `dmf-infra`,
  `dmf-media`, `dmf-runbooks`, `awx-automation`, Demo — all `status: successful`). Of 12 job
  templates (Demo + `eso-openbao-health-check` on project `awx-automation` + 10 `media-*` on
  `dmf-runbooks`), **none is a monitoring JT**. So a **"monitoring-apply"** JT must be **added**
  to `awx_catalog_job_templates` (role `defaults/main.yml`): `project_name: dmf-infra`,
  `playbook: k3s-lab-bootstrap/playbooks/vertical-monitoring/100-prometheus.yml` (plus siblings
  for `120-grafana.yml` / `150-blackbox.yml`). **Path note:** the `dmf-infra` AWX project root is
  the *repo* root (its `roles_path` is `.../dmf-infra/k3s-lab-bootstrap/roles`), so JT playbook
  paths are prefixed `k3s-lab-bootstrap/playbooks/...` — unlike the `dmf-runbooks` JTs whose repo
  root holds `playbooks/` directly. Small, GitOps-aligned addition — no new mechanism.
- **Wake-cost caveat (links OQ-2):** AWX runs **scale-to-zero** here (`awx-web`/`awx-task` at
  `replicas=0`, `awx-autoscale` present). Waking AWX is the *exact* RAM-exhaustion trigger from
  dmfdeploy#106 on this node. So on this sandbox the cheaper apply path is the operator-run
  `bin/run-playbook.sh <env> playbooks/vertical-monitoring/100-prometheus.yml` (still from the
  Forgejo-mirrored `dmf-infra`, no AWX wake). Recommendation: **author the monitoring-apply JT
  for GitOps correctness, but default to `run-playbook.sh` for sandbox iteration** to avoid the
  wake cost; reserve the AWX path for non-constrained envs.

### WP-G — Grafana dashboard alignment (added by Amendment A, 2026-07-03)
See **Amendment A** below for the full problem statement and decision. Summary: demote the
four lab-era dotdc "Kubernetes / Views" dashboards (keep Global + Nodes in an expert
**System** folder, delete Namespaces + Pods), and add a NetBox-driven **"Platform
services"** dashboard consuming the `netbox-*` jobs (`probe_success`/`up` per discovered
instance + a dmf-promsd adapter-health row: target counts via WP-B rules, cache
freshness as a boolean blackbox probe of `/readyz`). Dashboard titles use operator
vocabulary per UX-Constitution Art. 3. Same delivery mechanism as WP-E (ConfigMap
sideload; two provider/ConfigMap pairs — see Amendment A).

---

## 6. Alternatives considered & rejected

| Option | Why rejected |
|---|---|
| **ArgoCD** as GitOps engine | Explicit v0.1 non-goal (§4). Heavy (repo-server + app-controller + redis + server) for a node at 76% mem / swap-thrashing — the opposite of featherweight. Deferred to v0.2 as a documented seam. |
| **Forgejo Actions CI** (act_runner applies ConfigMap) | Not part of the committed chain; **no runner is deployed** (would be a new always-on pod on a saturated node); bypasses AWX audit. Operator initially leaned here, then reversed. |
| **git-sync sidecar** on prometheus-server | Lightest runtime, but outside the committed chain and bypasses AWX; adds a container to the already-large prometheus pod. |
| **Patch the Helm-owned `prometheus-server` ConfigMap directly** | Would be clobbered on the next Helm/Ansible run. Hence WP-F authors rules *in the role* so Helm owns them; the config-reloader still hot-reloads. |
| **vcgencmd-based rpi-exporter** for throttle flags | `/dev/vcio_gencmd` is absent on this image (§2b) — it would not function. node-exporter thermal/cooling is the working source. |
| **Instrument dmf-cms with `prometheus_client`** now | dmf-cms has no `/metrics` (§2c); adding app instrumentation is a code change in a component repo, out of this slice's scope. Covered by blackbox + k8s pod metrics for now; deferred to v0.2. |

---

## 7. Resource budget & fail-soft analysis (the crux for this node)

The node currently sits at ~76% mem with swap in use. Net new steady-state cost of this plan:
- **Alertmanager**: one capped pod (~32–64 MiB). The only net-new *always-on* workload. A
  reviewer should sanity-check that even this is acceptable, or whether notify should be
  **routed off-node** (e.g. directly to healthchecks.io + ntfy without a co-located AM) — see
  OQ-2.
- **Blackbox probes**: a handful of targets at ~60s — negligible CPU, tiny memory.
- **Recording rules**: *reduce* steady query cost for the dashboard and stabilize alerts; they
  add minor TSDB write volume (small rule set).
- **No new controllers** (the entire point of D2).

**Fail-soft guarantees baked in:** verdict reads `ALERTS` (works without AM); `monitoring-self`
group makes scrape/AM/TSDB failure *loud*; the watchdog (dead-man's-switch) detects total
Prometheus death from off-node; dashboard uses long min-intervals + recording rules so it
renders even when the node is thrashing.

---

## 8. Open questions for the cross-check

These are the points most likely to be wrong or under-specified. **Reviewer: please attack
these first.**

- **OQ-1 — RESOLVED (2026-06-24, repo + live AWX ORM).** `dmf-infra` AWX project exists and
  SCM-syncs successfully from Forgejo; of 12 job templates, **none is a monitoring JT** (all are
  `media-*` on `dmf-runbooks` + `eso-openbao-health-check` on `awx-automation`). → Add a
  `monitoring-apply` JT on project `dmf-infra` (playbook path prefixed `k3s-lab-bootstrap/...`).
  Note AWX is **scale-to-zero** (`awx-autoscale` present); the API rejects basic auth (SSO-only),
  so this was confirmed via `awx-manage shell` ORM. See WP-F (resolution + `run-playbook.sh`
  fallback to avoid the AWX-wake cost).
- **OQ-2:** Is a co-located Alertmanager (even capped) justified on this node, or should notify
  be off-node only (healthchecks.io watchdog + direct ntfy webhook) to keep the rig pure
  worst-case? Trade-off: routing/grouping/silencing vs. memory footprint.
- **OQ-3:** For the non-NetBox external anchors (gateway, 1.1.1.1), is a **static**
  `extraScrapeConfigs` probe job acceptable, or should even these be modeled as NetBox objects
  to keep *all* monitoring intent in NetBox per ADR-0038's spirit? (Static is simpler; NetBox is
  more "pure".)
- **OQ-4:** `dmf-promsd` exposes no `/metrics`; we propose blackbox `/healthz`. Should
  `dmf-promsd` instead gain a real `/metrics` (discovered-target gauge) in its component repo so
  `DiscoveredTargetsZeroOrStale` is a true metric, not an inference? (Relates to umbrella #5.)
- **OQ-5:** Thresholds. Given the node is *normally* near the edge, are warn/crit cutoffs
  (mem 10%/5%, load/core >4, temp 70/80, swap-rate) tuned so the pane is GREEN in steady state
  but trips on the dmfdeploy#106 chain? These need a live baselining pass before they're trusted.
- **OQ-6:** Does enabling Alertmanager via the role change behavior on the *Hetzner* env too
  (the role is generic)? Confirm the change is env-gated or safe cluster-wide.

---

## 9. Verification plan

1. **Static:** `promtool check rules files/rules/*.yaml`; render the monitoring playbook
   (check/render) and confirm the rendered `prometheus-server` ConfigMap carries populated
   `alerting_rules.yml` / `recording_rules.yml`.
2. **Apply via the real lane:** run the AWX "monitoring-apply" job (Forgejo SCM → AWX → Ansible).
   Confirm hot-reload: `kubectl -n monitoring get cm prometheus-server -o jsonpath=...` shows the
   rules; `curl .../prometheus/api/v1/rules` lists the groups; Alertmanager pod `Running` within
   caps.
3. **Graceful-degradation drill:** induce memory pressure (small `stress-ng --vm`) → `HostMemory
   Pressure` fires → Alertmanager → **ntfy** notification; verdict pane flips RED then returns
   GREEN on recovery. Confirm the *currently-restarting* pods (authentik/netbox/promsd/zot) now
   surface as `PodCrashLooping`/`PodOOMKilled`.
4. **Footprint check:** capture `kubectl top node` + load avg before/after; confirm probes
   (~60s) + capped Alertmanager don't materially worsen mem/swap. If they do, verify the verdict
   + self-alerts still degrade gracefully (and reconsider OQ-2).

---

## 10. Delivery & commit plan

- **Issue first** (WORKING-MODEL): open a tracking issue (`component:dmf-infra`,
  `workstream:observability`, milestone `v0.2` or `v0.1-polish` per maintainer call) and put its
  URL in this doc's `tracking_issue` frontmatter.
- **Code edits in `dmf-infra`** (sibling repo); this **doc** in the umbrella. The completing PR
  flips this frontmatter `status: proposed → executed` in the same change.
- **Commit format** (commitlint + DCO): `feat(monitoring): add are-we-ok alerts + dashboard
  (Closes dmfdeploy/dmfdeploy#N)`; for the umbrella doc:
  `docs(plans): add are-we-ok sandbox observability plan (refs #N)`. Sign every commit `-s`.
- **Public-repo hygiene:** keep placeholders only; gitleaks + `bin/scrub-public-repos.sh` run on
  commit. Concrete IPs/URLs go to `dmf-env`.
- **PR per repo** (`dmf-infra` code PR + umbrella doc PR), cross-referenced; reference umbrella
  issues fully-qualified (`Closes dmfdeploy/dmfdeploy#N`).

---

## 11. Deferred to v0.2 (documented, not built)
- **ArgoCD** migration of the same rules repo (the GitOps seam) — explicit v0.1 non-goal.
- `snmp-exporter` (monitoring-plan WP9); Loki/Promtail **log-relevance alerts** (WP10).
- `dmf-cms` app instrumentation (`prometheus_client`) to replace blackbox-only coverage.
- A real `dmf-promsd` `/metrics` endpoint (OQ-4; the former umbrella-#5 self-metrics
  note — #5 itself closed 2026-07-03 with self-metrics deferred here).
- Console-classified **alarms** (lifecycle/severity) per `DMF Console Alarm Philosophy` — these
  raw alerts are the upstream feed, not the classified surface.
- **Per-app deep-dive dashboards** (per-service Grafana boards beyond WP-G's "Platform
  services" roll-up) — add only when a real operator workflow demands one (Art. 3 rule:
  vocabulary/surfaces must earn their place).

---

## 12. References
- `../decisions/0038-netbox-driven-dynamic-monitoring.md` — NetBox-driven dynamic monitoring + PromSD.
- `../decisions/0041-release-and-contribution-model.md` — Forgejo-as-AWX-SCM; GitHub `main` canonical.
- `../decisions/architectural-commitments-v1.md` — ArgoCD non-goal; AWX is the v0.1 actuator.
- `DMF Dynamic NetBox-Driven Monitoring Plan 2026-06-04.md` — WP7 (born-inventory stamping), WP10 (alerts) follow-ons.
- `DMF Constrained-Node k3s Control-Plane Stability Plan 2026-06-21.md` (dmfdeploy#106) — the failure mode this plan instruments.
- `../design/DMF Console Alarm Philosophy.md` (stub) — downstream alarm classification (out of scope here).
- `DMF Monitoring Close-Out Work Packages 2026-07-02.md` (dmfdeploy#5, **executed
  2026-07-03**) — delivered the probe-lane prerequisites (`probe_path`,
  `http_2xx_302`, launcher stamping); the remaining `dmf-promsd` self-metrics idea
  lives in OQ-4, not in #5.

---

## Amendment A (2026-07-03): Grafana dashboard alignment (WP-G)

**Status:** Adopted with the plan's flip to `active` (2026-07-03). Adds WP-G to §5.
Motivated by the 2026-07-03 dashboard survey run after the monitoring close-out
(dmfdeploy#5) landed the probe lane end-to-end.

### Problem

The Grafana dashboard layer predates ADR-0038 entirely. The only provisioned
dashboards are the four vendored dotdc **"Kubernetes / Views"** JSONs
(`roles/base/grafana/files/k8s-views-{global,nodes,namespaces,pods}.json`), sideloaded
via the `grafana-custom-dashboards` ConfigMap into a folder literally named
**"Kubernetes"** — a leftover from the early lab days. Meanwhile Prometheus runs the
NetBox-driven jobs (`netbox-scrape`, `netbox-probe`, `netbox-snmp`) against dmf-promsd,
and the probe lane (ADR-0038 Amendment B, `probe_path`, `http_2xx_302`) emits
`probe_success` per platform app — **and no dashboard consumes any of it.** Two
consequences:

1. The operator's default Grafana surface visualizes raw Kubernetes state — **system-tier
   vocabulary** per the Console UX Constitution Art. 3 — instead of the platform's own
   monitoring model.
2. The NetBox source-of-truth investment is invisible: per-instance health, discovery
   freshness, and probe verdicts exist as metrics but have no visual consumer.

### Decision (WP-G)

1. **Demote, don't delete wholesale.** Keep `k8s-views-global.json` and
   `k8s-views-nodes.json`, moved to a folder named **"System"** (expert tier, Art. 3);
   **delete** `k8s-views-namespaces.json` and `k8s-views-pods.json` (drill-down views
   duplicated by `kubectl` for the expert audience, never operator-relevant).
   **Mechanism (explicit):** the pinned Grafana chart (8.0.0) keys external-ConfigMap
   dashboards **per provider** (`dashboardsConfigMaps.<provider>` mounted at
   `/var/lib/grafana/dashboards/<provider>`), and the current role defines a single
   provider `custom` hard-coding folder "Kubernetes"
   (`roles/base/grafana/templates/values.yml.j2`). The executing WP replaces this with
   **two provider/ConfigMap pairs** — `dmf` (folder "DMF", the default surface) and
   `system` (folder "System") — with matching mount paths and two ConfigMaps rendered
   from `templates/configmap-dashboards.yml.j2`. `foldersFromFilesStructure` is **not**
   usable here (it is a sidecar-provider knob, and direct ConfigMap mounts don't
   materialize subdirectories).
2. **New "Platform services" dashboard** (`roles/base/grafana/files/dmf-platform-services.json`,
   registered in the `dmf` ConfigMap): per-instance health from the NetBox lanes —
   `probe_success{job="netbox-probe"}` and `up{job=~"netbox-.*"}` rows with labels
   derived from the NetBox-stamped target labels — plus a **dmf-promsd adapter-health
   row** consisting of (a) discovered-target counts (`dmf:promsd_discovered_targets`,
   WP-B) and (b) **cache freshness as a boolean blackbox probe of `/readyz`** — the
   endpoint that goes non-2xx when the adapter's NetBox snapshot exceeds its staleness
   threshold (`/healthz` is liveness-only and always 200-ok, so it cannot carry
   freshness; and snapshot age is JSON, not a Prometheus metric). A real quantitative
   freshness/age series requires the OQ-4 `/metrics` endpoint — until then the row is
   counts + boolean-fresh, and says so on the panel (Art. 1: no false precision).
3. **The WP-E verdict pane is the front item of the "DMF" folder.** Mechanically:
   Grafana orders dashboards alphabetically within a folder, and "Are we OK?" sorts
   before "Platform services" — the executing WP keeps titles in that order and MAY
   additionally provision it as the org default home dashboard
   (`grafana.ini` `[dashboards] default_home_dashboard_path` on the mounted provider
   path); that choice is left to the executing WP. All dashboard titles use operator
   vocabulary (Art. 3) — "Are we OK?", "Platform services" — never raw k8s/EBU-layer
   jargon.
4. **No mechanism change:** ConfigMap sideload stays the only delivery path (no
   sidecar), files stay discrete/diffable under the role, delivered via WP-F.

**Resource note:** net dashboard count stays at 4 (2 demoted + verdict + platform
services); recording rules (WP-B) keep the new panels cheap. No new runtime components —
consistent with §7.

### Cross-env note (2026-07-03)

At amendment time the live env is a **single cloud node** (bring-your-own-node
sandbox profile, `<node-public-ip>`), not the RPi this plan was surveyed on. §2b's
env-portability caveat covers it: the thermal/fan clauses are absent-tolerant and
everything else is identical. Grafana on the live env confirmed at `11.0.0`, no
dashboard sidecar, the four k8s-views dashboards as described.
