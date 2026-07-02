---
status: active
date: 2026-07-02
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/5
---
# DMF Monitoring Close-Out Work Packages (2026-07-02)

> **Purpose:** operationalize the two remaining items of
> [DMF Dynamic NetBox-Driven Monitoring Plan 2026-06-04](DMF%20Dynamic%20NetBox-Driven%20Monitoring%20Plan%202026-06-04.md)
> (tracking issue [#5](https://github.com/dmfdeploy/dmfdeploy/issues/5)) as
> discrete work packages a **fresh agent can execute cold**. Design was
> adversarially cross-checked (codex) on 2026-07-02: first pass FAIL (P1:
> `probe_path` is a contract change → WP0 added; five P2s folded in), re-gate
> **PASS**. Do not re-litigate the design decisions below without new evidence —
> execute them.
>
> **Completion rule:** the WP5 umbrella PR closes #5 and flips **both** the
> 2026-06-04 plan **and this doc** to `executed` in the same change.

## 0. Rules for the executing agent (read first)

1. **Boot ritual** per umbrella `CLAUDE.md` (fetch/pull, `bin/generate-status.sh`,
   read latest handoff, skim ADR INDEX). Component repos are **siblings** of the
   umbrella (`../dmf-runbooks`, `../dmf-promsd`, `../dmf-infra`).
2. **Commits:** conventional format + DCO — `git commit -s -m "type(scope): …"`
   (see the `dmf-deploy-commit-workflow` skill). No agent co-author trailers.
3. **Issue references:** component-repo commits/PRs use the fully qualified
   `refs dmfdeploy/dmfdeploy#5` (cross-repo `Closes` does **not** auto-close the
   umbrella issue). Only the WP5 umbrella PR carries `Closes #5`.
4. **PR auto-merge arms at open** — open a PR only when it is final, or apply
   the `hold` label.
5. **Codex cross-check** every WP diff via the `agent-bridge` skill before
   opening its PR (send the diff summary to the `codex` pane; require
   `GATE: PASS`).
6. **Ordering (hard):** WP0 (ADR-0038 Amendment B) must be **merged in the
   umbrella before WP2/WP3 are accepted as complete** — no cross-repo "lands
   together" atomicity. WP1 is independent and may land first.
7. **Public hygiene:** no env ids, node IPs/hostnames, SSH usernames, or
   operator-local paths in commits, PR bodies, or docs. The live sandbox env id
   rotates — resolve it via `bin/generate-status.sh` → `STATUS.local.md`.
8. **Secrets discipline:** §0 of the `dmf-cluster-access` skill applies to all
   live-env work. The env restore passphrase is entered by the operator in the
   dmf-init UI — never through an agent.

## 1. Context

Issue [#5](https://github.com/dmfdeploy/dmfdeploy/issues/5) is the last
engineering item gating the `v0.1-polish` milestone (after it, only tracker
[#36](https://github.com/dmfdeploy/dmfdeploy/issues/36) remains). The
NetBox-driven monitoring pipeline
([ADR-0038](../decisions/0038-netbox-driven-dynamic-monitoring.md): NetBox is
the address book of monitoring intent; the `dmf-promsd` adapter feeds Prometheus
via `http_sd`) is validated and green on the live sandbox. Two loose ends:

- **(a) Launcher stamping.** The nmos-cpp AWX launcher does not stamp the
  ADR-0038 **Amendment A** cluster coordinates (`cluster_service` /
  `cluster_namespace` / `cluster_port`) onto its NetBox `ipam.Service`, so the
  adapter cannot compose a stable in-cluster probe target and monitoring
  **silently drops the workload**. The nmos-crosspoint launcher already stamps
  them (`dmf-runbooks/roles/nmos-crosspoint/defaults/main.yml:28-41` is the
  reference); nmos-cpp is the straggler.
- **(b) Grafana/Loki probe tuning.** Both are born-inventory probe targets with
  the strict `http_2xx` module against their service root. **Live-verified
  (2026-07-02, current sandbox, local-CA lane):** Grafana answers `/` with
  `302 Location: /login`; following redirects chains through OAuth auto-login to
  the external `https://auth.<base-domain>` URL signed by the **DMF Local CA**,
  so the probe dies with `CERTIFICATE_VERIFY_FAILED` — exactly the failure class
  the 2026-06-04 plan's verification step 6 gates on. Loki's root returns
  non-2xx; its health contract is `GET /ready` on `:3100`, and the promsd probe
  lane has **no URL-path support** (`metrics_path` is scrape-lane-only,
  `dmf-promsd/src/dmf_promsd/sd.py:232`).

**Operator scope decisions (fixed — do not expand):**
- Amendment-A parity only. **No** new catalog-instance label/field.
- Plumbing only. **No** dmf-cms changes (console per-instance health is future
  work; see §6).
- **All monitoring handled in-cluster; publicly exposed monitoring endpoints
  removed where sensible.** Consequence: Loki's public IngressRoute
  (`<base-domain>/loki/ready` + PathPrefix to `loki-gateway`, unauthenticated)
  exists only as a workaround for external `/ready` probing; once the probe lane
  can hit `/ready` in-cluster it is redundant — remove it. Prometheus already
  has no ingress; Grafana's stays (operator UI, passkey/OIDC-gated per
  [ADR-0015](../decisions/0015-dmf-console-passkey-only.md)/[ADR-0028](../decisions/0028-identity-and-authority-chain.md)).

## 2. Design decisions (codex-gated; execute as specified)

1. **nmos-cpp stamping is a defaults-only change.** The role tasks already pass
   `netbox_service_monitoring_custom_fields` / `..._clear` generically
   (`provision.yml:111,137`, `configure.yml:44`, `finalise.yml:44`). Stamp
   `cluster_service: nmos-cpp-registry`, `cluster_namespace` (the role's nmos
   namespace var), `cluster_port: 80` — matching the chart's registry Service
   and `nmosConfig.httpPort` default — and null all four fields in the `_clear`
   map so finalise leaves no stale coordinates.
2. **Grafana → new blackbox module `http_2xx_302`** with
   `follow_redirects: false` and `valid_status_codes: [200,301,302,303,307,308]`.
   The probe never dereferences `Location`, so it **structurally cannot** reach
   the external local-CA URL — the "no CERTIFICATE_VERIFY_FAILED" gate holds by
   construction. `http_2xx_insecure` was rejected: it couples the health lane to
   the ingress path and normalizes disabling TLS verification.
3. **Loki → new `probe_path` custom field consumed by the promsd probe lane**
   (mirrors the scrape-lane `metrics_path` precedent). The adapter appends the
   normalized path to the composed target
   (`loki.monitoring.svc.cluster.local:3100/ready`). The `netbox-probe`
   Prometheus job already relabels `__address__` → `__param_target`
   (`dmf-infra/k3s-lab-bootstrap/roles/base/prometheus/templates/scrape_configs.yml.j2:322-335`),
   and blackbox's http prober accepts schemeless full-URL targets — **no
   Prometheus template change**. `tcp_connect` was rejected (port-open ≠ ready);
   a Loki-specific blackbox module is non-viable (modules cannot set a URL
   path — the path comes from the target).
4. **Remove Loki's public IngressRoute and its `loki-ready-path` middleware.**
   Both real consumers are in-cluster service DNS (promtail push →
   `loki-gateway.monitoring.svc…`, Grafana datasource → same), honoring
   [ADR-0023](../decisions/0023-internal-service-dns-for-cross-app-wiring.md).

## 3. Work packages

Dependency order: **WP0 → (WP1 ∥ WP2 ∥ WP3) → WP4 → WP5**, where WP2/WP3 must
not be *accepted* before WP0 is merged (rule 6). Each WP reports DONE/BLOCKED
with evidence.

### WP0 — umbrella: ADR-0038 **Amendment B** (`probe_path`) — gates WP2/WP3

`probe_path` extends the monitoring contract (the ADR defines `metrics_port`,
`metrics_path`, `probe_module`, `snmp_module`; Amendment A added only the three
`cluster_*` fields), and the ADR's enforcement clause requires schema changes to
be reviewed against it. Amend
[`docs/decisions/0038-netbox-driven-dynamic-monitoring.md`](../decisions/0038-netbox-driven-dynamic-monitoring.md)
in place (Amendment-A precedent), defining:

- **`probe_path`** — text custom field, default empty; object types
  `ipam.service`, `dcim.device`, `virtualization.virtualmachine`.
- **Semantics:** probe-lane only; appended to the composed target **only for
  http-prober modules** (`probe_module` starting `http_`); normalized to a
  single leading `/`; empty/absent = no-op; applies to both the svc-DNS
  composition and the `primary_ip4` fallback.

Commit: `docs(adr): ADR-0038 amendment B — probe_path probe-lane field (refs #5)`.
Update the ADR's row in `docs/decisions/INDEX.md` if its summary changes.

### WP1 — dmf-runbooks: nmos-cpp Amendment-A stamping (independent; can land first)

- **File (only):** `roles/nmos-cpp/defaults/main.yml` — extend
  `netbox_service_monitoring_custom_fields` with `cluster_service:
  "nmos-cpp-registry"`, `cluster_namespace` (nmos namespace var), `cluster_port:
  80`; extend `netbox_service_monitoring_custom_fields_clear` with nulls for all
  three. Mirror the crosspoint comment style (its `defaults/main.yml:28-41`).
- **Checks:** `ansible-playbook --syntax-check` on the launch/teardown
  playbooks; `ansible-lint roles/nmos-cpp`.
- **Acceptance:** live finalise must be proven on the **NetBox side** — the
  service loses `monitoring:probe` and all three `cluster_*` fields read null —
  not merely "the Prometheus target disappeared".
- **PR:** `feat(nmos-cpp): stamp cluster coords for in-cluster probe (refs dmfdeploy/dmfdeploy#5)`.

### WP2 — dmf-promsd: `probe_path` support + release (needs WP0 merged)

- **Files:**
  - `src/dmf_promsd/sd.py` — probe lane: append normalized `probe_path` per
    Amendment-B semantics (**only when `probe_module` starts `http_`**) to the
    composed target, on both the svc-DNS path and the `primary_ip4` fallback.
  - `tests/test_sd.py` — five discriminating cases: cluster-coords +
    `/ready` composition; `ready` → `/ready` normalization; absent/empty field
    regression (target unchanged); fallback address + path; **non-http module
    gets NO path appended**.
  - `VERSION` — bump. ⚠️ `origin/main` reads `0.1.3`; an earlier survey said
    `0.1.4`. **First** check the deployed image tag on the env and the GHCR
    tags, then pick the next free patch version.
- **Checks:** full `pytest`; repo lint/CI.
- **Release gate (explicit):** merge → `git fetch` → assert
  `git show origin/main:VERSION` equals the intended tag →
  `scripts/publish-to-ghcr.sh --push` (CI does **not** push images) → verify the
  tag exists on GHCR **before** WP4 runs `630-zot-seed-platform.yml` (dmf-infra
  resolves the tag from the sibling checkout's `origin/main:VERSION`; see
  [#135](https://github.com/dmfdeploy/dmfdeploy/issues/135)).
- **PR:** `feat(sd): probe-lane probe_path custom field (refs dmfdeploy/dmfdeploy#5)`.

### WP3 — dmf-infra: module + schema + stamping + Loki ingress removal (one PR, lock-step; needs WP0 merged)

All paths are under `k3s-lab-bootstrap/` — the roles do **not** live at repo
root (verified fresh-agent footgun):

1. `k3s-lab-bootstrap/roles/base/blackbox-exporter/defaults/main.yml` — add the
   `http_2xx_302` module (`prober: http`, `timeout: 5s`,
   `valid_status_codes: [200,301,302,303,307,308]`, `follow_redirects: false`,
   `preferred_ip_protocol: ip4`) with a rationale comment (Grafana
   root_url/local-CA redirect).
2. `k3s-lab-bootstrap/roles/stack/operator/netbox-sot/defaults/main.yml` — add
   `http_2xx_302` to the `dmf_blackbox_probe_modules` choice set (~line 226 —
   **must stay lock-step with the blackbox module list**; playbook 691
   reconciles `extra_choices` on live envs), and add the `probe_path` text
   custom field to the monitoring custom-fields schema (~line 245, same three
   object types, per Amendment B).
3. `k3s-lab-bootstrap/roles/common/dmf-born-inventory/defaults/main.yml` —
   populate `dmf_born_inventory_app_monitoring_overrides`: `grafana →
   probe_module: http_2xx_302`; `loki → probe_path: /ready`. Document
   `probe_path` in the hook's comment (~lines 166-172).
4. `k3s-lab-bootstrap/roles/common/dmf-born-inventory/tasks/app-service.yml` —
   resolve and stamp `probe_path` as a **separate** PATCH task modeled on the
   probe_module task (:152-166), gated on `monitoring:probe` + non-empty path.
5. `k3s-lab-bootstrap/roles/stack/operator/loki/tasks/main.yml` — drop the
   "Create Loki HTTPS IngressRoute" task; fold `loki` into the IngressRoute
   removal loop (`state: absent`); **add an explicit `state: absent` for
   `Middleware/loki-ready-path`** (an IngressRoute removal loop does not delete
   Middlewares) and drop its creation task.

- **Checks:** `ansible-lint` on the touched roles; `--syntax-check` on
  `691-netbox-sot.yml`, `694-born-inventory.yml`,
  `vertical-monitoring/150-blackbox.yml`, and the loki playbook (`110-loki.yml`).
- **PR:** `feat(monitoring): http_2xx_302 module, probe_path field+stamp, drop Loki public ingress (refs dmfdeploy/dmfdeploy#5)`.
  May land in parallel with WP2 (the adapter ignores unknown fields; a missing
  field is a no-op).

### WP4 — live verification on the current sandbox env (no code)

**Access:** via the **dmf-init Manage lane** — the operator holds the env's
dmf-init recovery package (encrypted bundle + local-CA cert). Launch dmf-init
locally (`dmf-init up`), restore the bundle (**operator enters the passphrase in
the UI**), then follow the `dmf-init-manage-playbook` skill
(restore → lock → rerun-playbook → stream) — mind its **repo-checkout-advance
gotcha** so the env's fetched dmf-infra/dmf-promsd checkouts include the new
commits. Node SSH (operator user from the restored env state) is for read-only
checks only; playbook runs stay on the Manage API / `run-playbook.sh` lane
([ADR-0010](../decisions/0010-run-playbook-as-sanctioned-entry.md)).

**Rollout order (matters):**
1. `691-netbox-sot.yml` — additive schema (choice + `probe_path` field).
2. `vertical-monitoring/150-blackbox.yml` — the module **must precede** any
   NetBox record referencing it (else "unknown module" probe failures).
3. `694-born-inventory.yml` — **mandatory re-stamp** of grafana/loki; nothing
   else re-stamps them.
4. `git fetch` in the env's dmf-promsd checkout; assert VERSION/GHCR tag
   (WP2 release gate); `630-zot-seed-platform.yml` (tag lands in Zot **before**
   the deployment rolls); `vertical-monitoring/160-promsd.yml`.
5. `110-loki.yml` — ingress + middleware removal.

**Acceptance gates:**
- **Pre-check on record (before step 2):** capture the "before" Grafana failure
  **against the exact target string `/sd/probe` currently emits** (not a
  hand-composed URL) via an in-cluster blackbox `debug=true` probe — the
  evidence must prove the NetBox-discovery lane, not the old ingress/OAuth path.
  If Grafana already passes, the module change is still the right hardening —
  record it either way in the PR body.
- **After step 4:** wait out **both cadences** (promsd cache ~45s + Prometheus
  `http_sd` refresh 30s ≈ 75s worst-case), then check `/sd/probe` **first**
  (grafana carries `__param_module: http_2xx_302`; loki target ends
  `:3100/ready`), **then** Prometheus target state — a stale cache otherwise
  mimics a failed fix.
- `probe_success == 1` for grafana and loki; `promtool check config` clean; no
  `CERTIFICATE_VERIFY_FAILED` in blackbox/adapter logs.
- **nmos-cpp lifecycle:** deploy via console/AWX → within ~75s
  `nmos-cpp-registry.<nmos-ns>.svc.cluster.local:80` appears and is up;
  finalise → target disappears **and** the NetBox service shows the
  `monitoring:probe` tag gone + all `cluster_*` fields null.
- **Post-removal:** no `IngressRoute/loki` **and** no
  `Middleware/loki-ready-path` in the namespace; the public `/loki/…` path no
  longer routes; promtail still shipping; the Grafana Loki datasource still
  healthy.

### WP5 — umbrella close-out PR (lands last, after WP4 gates pass)

- **Precondition:** WP0 (Amendment B) is merged — never flip the plan to
  executed while component repos carry a schema field absent from ADR-0038.
- Flip frontmatter `active → executed` on **both**
  [DMF Dynamic NetBox-Driven Monitoring Plan 2026-06-04](DMF%20Dynamic%20NetBox-Driven%20Monitoring%20Plan%202026-06-04.md)
  (+ short executed postscript naming what landed) **and this doc**; regenerate
  `docs/plans/INDEX.md` via `bin/generate-plans-index.sh` (pre-commit/CI
  `check-docs` hard-fails on a stale index).
- **PR:** `docs(plans): monitoring close-out executed — launcher stamping + probe tuning (Closes #5)`
  (bare `Closes #5` is correct here — the PR lands in dmfdeploy/dmfdeploy).

## 4. Risks

- **Lock-step window:** module / choice-set / override must land in one
  dmf-infra PR and roll out in the WP4 order, else NetBox select-validation
  errors or "unknown module" probe failures.
- **Born-inventory re-run is mandatory** (WP4 step 3) — without it all code is
  "correct" but the gates fail.
- **VERSION discrepancy** (0.1.3 vs 0.1.4 sightings) — resolve against GHCR +
  the deployed tag before bumping.
- **`cluster_port: 80` literal** couples to the chart's `httpPort` default —
  the same accepted trade-off as crosspoint's literal.
- **Loki ingress removal:** confirm no external consumer (e.g. an off-cluster
  uptime check) relies on the public `/loki/ready` before WP4 step 5. The
  are-we-ok plan ([#166](https://github.com/dmfdeploy/dmfdeploy/issues/166))
  probes in-cluster, so none is expected.

## 5. References

- [ADR-0038 — NetBox-driven dynamic monitoring](../decisions/0038-netbox-driven-dynamic-monitoring.md) (incl. Amendment A; WP0 adds Amendment B)
- [ADR-0037 — Media Workloads instance inventory](../decisions/0037-media-workloads-netbox-instance-inventory.md)
- [ADR-0032 — scoped catalog NetBox writer](../decisions/0032-catalog-launcher-scoped-netbox-writer.md)
- [ADR-0023 — internal service DNS](../decisions/0023-internal-service-dns-for-cross-app-wiring.md)
- [ADR-0010 — run-playbook.sh as sanctioned entry](../decisions/0010-run-playbook-as-sanctioned-entry.md)
- [DMF Dynamic NetBox-Driven Monitoring Plan 2026-06-04](DMF%20Dynamic%20NetBox-Driven%20Monitoring%20Plan%202026-06-04.md) — parent plan (WP6/WP2/WP11 map to these items)
- [DMF Constrained-Node k3s Control-Plane Stability Plan 2026-06-21](DMF%20Constrained-Node%20k3s%20Control-Plane%20Stability%20Plan%202026-06-21.md) — the sandbox's failure-mode context
- [DMF Are-We-OK Sandbox Observability and Alerting Plan 2026-06-24](DMF%20Are-We-OK%20Sandbox%20Observability%20and%20Alerting%20Plan%202026-06-24.md) — downstream consumer of these probes ([#166](https://github.com/dmfdeploy/dmfdeploy/issues/166))
- Skills: `dmf-init-manage-playbook`, `dmf-cluster-access`, `agent-bridge`, `dmf-deploy-commit-workflow`, `cold-agent-wp-execution`

## 6. Future work (explicitly out of scope)

- **Console per-instance health join** (catalog card ↔ Prometheus target) —
  needs a shared instance label; candidate v0.2 issue alongside
  [#29](https://github.com/dmfdeploy/dmfdeploy/issues/29) /
  [#166](https://github.com/dmfdeploy/dmfdeploy/issues/166). The dmf-cms side
  today consumes Prometheus opaquely (`src/dmf_cms/prometheus.py`; cluster-wide
  Monitoring page only) and joins NetBox solely via the `lifecycle:*` tag.
- **snmp-exporter** (parent-plan WP9) and **Loki log-relevance alerts**
  (parent-plan WP10) remain deferred.
