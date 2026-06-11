# DMF NetBox-Driven Monitoring — Build + Live e2e Handoff (2026-06-04)

**What:** built the entire NetBox-driven dynamic monitoring feature (WP0–WP8),
deployed it **live** on a fresh `montest` sandbox via the **dmf-init** prefilled
bootstrap, and **closed the loop end-to-end** — Prometheus is probing 10 platform
apps discovered from NetBox tags, all `up`. Eight deploy-time issues surfaced
(static review can't catch these); seven fixed, the eighth resolved by **ADR-0038
Amendment A**. Orchestrated: Claude drove + verified; codex + qwen-right lifted;
qwen-left reviewed.

## Headline result (validated live)

`/sd/probe` emits **10** target groups; Prometheus `netbox-probe` job shows **10
targets, all `up`** — e.g. `grafana.monitoring.svc.cluster.local:80`,
`netbox.netbox.svc.cluster.local:80`, `awx-service.awx.svc.cluster.local:80`, …
The full chain works: NetBox `monitoring:probe` tag + `cluster_*`/`probe_module`
custom fields → `dmf-promsd` adapter composes `<svc>.<ns>.svc.cluster.local:<port>`
→ Prometheus `http_sd` → blackbox-exporter → health.

## What shipped (all on `main`, reviewed)

- **ADR-0038** + Amendment A (umbrella `d8afc38` … `f75ba0d`): two-lane discovery,
  the monitoring contract, the standalone PromSD adapter, and (Amendment A)
  **cluster-svc-DNS probe/scrape targets**.
- **dmf-promsd** (NEW repo `git@<lan-forgejo>:<operator>/dmf-promsd.git`): FastAPI `http_sd`
  adapter, v**0.1.3**. Key commits: `51cf946` scaffold → `db71065` tag-slug →
  `c916dcf` cache per-tag union → `1b33486` svc-DNS composition.
- **dmf-infra**: WP1 taxonomy+token `978d08b`, WP2 blackbox `9b71e32`, WP4 deploy+ESO+630
  `68807cb`/`0ad0706`, WP5 http_sd jobs `8f780d1`, WP7 born-inventory `4de6f6f`/`23c3767`,
  WP8 wiring `9cee756`/`a458b75`; live-fixes: blackbox chart `8c459b7`, role_path
  `1ad7ce9`, token capture `6322343`, Amendment A fields+stamping `18d3e95`.
- **dmf-runbooks** WP6 nmos-cpp stamping `c634ac5`; **dmf-media** catalog `monitoring:`
  block `2bc417a`; **dmf-init** fetch dmf-promsd `bfd21c9`.

## The 8 live-deploy findings

1. dmf-init didn't fetch dmf-promsd (630 VERSION lookup) → **FIXED** `bfd21c9`.
2. dmf-promsd image never published → workaround: built + `k3s ctr images import`.
   **Open:** GHCR publish (operator will, GHCR token in the operator's keychain).
3. blackbox chart `8.16.1` nonexistent + `blackboxConfig:` key → **FIXED** `8c459b7`
   (11.11.0 + `config:`).
4. promsd VERSION lookup `playbook_dir`-relative → **FIXED** `1ad7ce9` (role_path).
5. WP1 promsd token mint `| tail -n 1` captured empty → **FIXED** `6322343`
   (sentinel). **But not validated live — see Loose ends.**
6. adapter queried by tag name not slug → **FIXED** `db71065`.
7. cache ANDed all tags in one query → **FIXED** `c916dcf` (union).
8. probe target address gap (services have no IP/FQDN) → **ADR-0038 Amendment A**
   (cluster-svc-DNS), implemented + reviewed + **validated live**.

## Live env state (montest)

- env **`8f2y-sgg7`**, node `<operator>@<sandbox-node-ip>` (Lima `dmf-sandbox`), `*.montest.dmf.test` (live IP in STATUS.md).
- Driven by **dmf-init** app on `127.0.0.1:8091`, `DMF_DATA_ROOT=/tmp/dmf-init-montest`,
  repos `file:///tmp/dmf-init-reposrc`. Backups: local `/tmp/dmf-backups-{a,b}`.
- **Workaround state (not production-clean):**
  - dmf-promsd image is **node-local** (`k3s ctr images import`), NOT on GHCR/Zot.
  - adapter `NETBOX_TOKEN` is **injected via `kubectl set env`**, NOT from the ESO
    secret (ESO secret was empty — finding #5 not validated live).
  - fetched `repos/dmf-media` keeps the **MXL catalog entries stripped** (#9, so
    configure's AWX catalog JT passes); fetched `repos/dmf-infra/630` has the
    dmf-promsd seed entry removed (image not on GHCR).
- VM is **up** at session end (10 GiB). Stop with `limactl stop dmf-sandbox` to free RAM.

## Loose ends / next steps (priority order)

1. **Validate finding-#5 ESO path:** re-running 691 (FIX5) didn't populate
   `secret/apps/netbox/runtime#promsd_api_token` → ESO secret stayed empty → token
   had to be injected. Investigate the 691 reuse/idempotency gate (it may skip the
   re-mint when an empty token already exists) + force an ESO resync. Goal: adapter
   gets its token from ESO, not `set env`.
2. **GHCR publish** dmf-promsd (#1/#2 proper path) so 630 mirrors it normally; then
   the canonical (unstripped) 630 works. Operator flips the package public after.
3. **WP6 catalog launcher** must stamp `cluster_service/namespace/port` too (born-inventory
   done in `18d3e95`; the dynamic-catalog path — nmos-cpp launcher — is NOT yet wired
   for Amendment A). Needed for the "deploy a media function → monitoring attaches"
   dynamic e2e.
4. **4-mint sentinel hardening** (operator-confirmed deferred): apply the FIX5 pattern
   to admin/awx/librenms/catalog mints in `netbox-sot/tasks/main.yml`
   (L30/L47/L64/L82). qwen-right offered.
5. **Amendment A optional second probe** for `exposure:public` (external ingress URL)
   — deferred; internal svc-DNS is the baseline.
6. Minor: loki probe uses `loki:3100` (resolves; `loki-gateway:80` is the alt entry if
   the http_2xx root probe ever 404s); dmf-promsd Dockerfile `/app` is benign scaffold
   (could tidy the `--create-home` warning).

## Pointers

- Findings detail: memory `project_dmf_promsd_bootstrap_integration_gaps`.
- Plan: `docs/plans/DMF Dynamic NetBox-Driven Monitoring Plan 2026-06-04.md`.
- Contract: `docs/decisions/0038-netbox-driven-dynamic-monitoring.md` (+ Amendment A).
