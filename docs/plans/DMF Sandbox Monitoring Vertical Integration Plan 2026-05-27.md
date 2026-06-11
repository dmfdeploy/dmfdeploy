---
status: executed
date: 2026-05-27
---
# DMF Sandbox Monitoring Vertical Integration Plan (2026-05-27)

**Status:** IMPLEMENTING (2026-05-28). Driven by `claude-bottom` (pane 4) per
operator dispatch; `claude` (pane 2) orchestrates + verifies. See §9 for the
2026-05-28 scope-lock addendum (supersedes any earlier conflicting choices).

**Scope (operator-set):** integrate **Grafana + Prometheus + Loki only** into the
WP1S sandbox lane so `grafana.deploy.dmf.test` is reachable and OIDC login works,
and so a clean rebuild brings monitoring up automatically. **Out of scope:**
LibreNMS, snmp-exporter, netdisco. **Flagged:** Promtail (see Open Question 1).

---

## 1. Why it's broken today (diagnosis, 9y6o-zn0t)

- Hitting `grafana.deploy.dmf.test` returns the **landing page**, because **no
  monitoring stack is deployed** — there is no `monitoring` namespace; Prometheus,
  Loki, Grafana, Promtail are all absent. The landing page is the catch-all
  default route, so any host with no backend lands there.
- Root cause: the sandbox bootstrap wrappers
  (`bootstrap-sandbox-{profile,provision-pre-seed,provision-post-seed,configure,verify}.yml`)
  deploy only the core apps. The `playbooks/vertical-monitoring/*` playbooks
  (`100-prometheus`, `110-loki`, `120-grafana`, `130-promtail`, `140-librenms`,
  `190-monitoring-verify`) are **not wired into the sandbox lane at all**.
- `dmf_monitoring_profile: minimal` (set in `bootstrap-sandbox-profile.yml`) is
  currently **inert** — defined as a default, consumed nowhere.

## 2. What's already in our favour

- **Playbooks exist and are sandbox-runnable:** `100-prometheus` → `base/prometheus`;
  `110-loki` → `stack/operator/loki`; `120-grafana` → `base/grafana`. All run
  `hosts: k3s_control` + `base/cluster-ready` first.
- **Authentik "Grafana" OAuth2 provider already exists** (confirmed live alongside
  Forgejo/NetBox/LibreNMS/DMF Console/Zot — created by `110-authentik`).
- **Grafana role is already wired correctly for host mode:** `root_url:
  https://{{ grafana_host }}/`, Host-based IngressRoute on `grafana_ingress_class`
  (inventory overrides to `traefik`), datasources pre-provisioned to
  `http://prometheus-server.<ns>.svc.cluster.local/prometheus` and
  `http://loki-gateway.<ns>.svc.cluster.local`.
- **Node already maps** `grafana.deploy.dmf.test` (321-local-ca-trust /etc/hosts).
- **Inventory already overrides** `grafana_ingress_class: traefik` and
  `dmf_storage_class: local-path`.

## 3. The four gaps to close

### Gap A — Grafana server-side OIDC trust on the local-CA lane (3rd WP1S gate-2)
Grafana's generic-OAuth points `AUTH_URL`/`TOKEN_URL`/`API_URL` at
`https://auth.deploy.dmf.test/...` and does **server-side token + userinfo**
exchange. On the local-CA lane its Go HTTP client won't trust the cert →
login fails (same class as the NetBox 500 we just fixed, and the Zot fix before
it). **Fix:** mirror the **zot** pattern in `roles/base/grafana` — publish
`dmf-local-ca` (cert-manager) into the monitoring ns as a ConfigMap and mount
`ca.crt` into the Grafana pod at `/etc/ssl/certs/dmf-local-ca.crt`, gated on
`dmf_tls_mode == 'local-ca'`. Grafana is Go (like Zot), so the directory mount
should suffice without env vars — **verify at impl** (Go reads `/etc/ssl/certs`
dir and adds certs; Zot proved this). Fallback if not: initContainer
`update-ca-certificates`, or `SSL_CERT_FILE`/`GF_*` CA env.
> **claude-bottom heads-up:** confirm the Grafana image base before assuming the
> Zot dir-mount transfers — official `grafana/grafana` is **Alpine**, whose
> `/etc/ssl/certs` layout + Go cert-dir scan differ from Zot's. `SSL_CERT_FILE`
> pointed at the mounted `ca.crt` is the most image-agnostic fallback if the bare
> dir-mount doesn't take.
*This is NOT the netbox case* — Grafana's OAuth URLs are explicit env (not
discovery-derived), but moving them to internal svc DNS would break the browser
authorize redirect (auto_login + disable_login_form), so keep them public and
trust the CA in-pod. (See `[[project_cms_authentik_backchannel_split]]` — CA-mount
is the right tool for discovery/explicit-URL Go/Python clients.)

### Gap B — Sandbox storage + resource fit (single 60GiB Lima VM, 4CPU/10GiB)
Role defaults are **cloud-sized and will not fit**:
- `prometheus_storage_size: 50Gi`, `prometheus_retention: 30d` / `40GB`
- `loki_storage_size: 50Gi`, `loki_retention: 720h` (+ 6-month security stream)
- 100Gi requested on a 60GiB disk; plus Prometheus memory pressure on a 10GiB node.

**Fix:** sandbox-scaled values (exact numbers TBD at impl, suggested starting point):
- Prometheus: `storage_size 8Gi`, `retention 3d` / `retention_size 6GB`,
  alertmanager 256Mi; modest scrape set; resource requests/limits capped.
- Loki: `storage_size 8Gi`, `retention 168h` (7d), security stream off or short;
  single-binary/monolithic mode for a single node.
- Grafana: dashboards are config-provisioned; confirm whether it requests a PVC
  (keep small/ephemeral if so).
- **Access mode:** local-path is RWO-only. Confirm none of the three PVCs default
  to `ReadWriteMany` (the NetBox-media trap — `[[reference_sandbox_standalone_playbook_profile_gap]]`).
  Prometheus/Loki single-replica should be RWO already; verify.
- **Total disk budget (claude-bottom):** 8Gi+8Gi=16Gi of monitoring PVCs land on
  the SAME 60GiB disk as k3s + all core apps + container images. Before locking
  sizes, check real headroom (`df -h` / `kubectl df`-equivalent on the node after
  the existing stack binds). If tight, start smaller (Prom 6Gi/2d, Loki 6Gi/3-7d)
  and grow — easier than recovering a wedged disk. Disk is the §5 top risk.

### Gap C — Make `dmf_monitoring_profile` real (express "these only")
Turn the inert var into an actual gate so the sandbox deploys exactly the minimal
set and skips librenms/snmp/netdisco:
- `minimal` → prometheus + loki + **promtail** + grafana (sandbox default)
- `full` → + librenms + snmp-exporter + netdisco (cloud/lab)
- `none` → skip monitoring entirely (escape hatch)

> **claude-bottom:** I moved **promtail into `minimal`** to match Open Q1's
> recommendation — Loki is decorative without a shipper, and gate shape is
> unchanged. If the operator defers promtail, drop just that one line.
>
> **Mechanism:** gate at the sandbox wrapper's `import_playbook` `when:` — each
> monitoring play imported with `when: dmf_monitoring_profile in ['minimal','full']`
> (librenms/snmp/netdisco additionally `== 'full'`). Declarative, one place, no
> per-role edits. The var already resolves from the wizard-rendered inventory +
> the profile prelude, so the gate reads a real value on every lane.
>
> **Open Q3 recommendation: make it real now.** The var exists; incremental cost
> over hardcoding is ~one `when:` per play; and it's what lets the cloud lane stay
> `full` without forking the wrapper.

### Gap D — Persistence: wire monitoring into the sandbox bootstrap (rebuild-safe)
> **claude-bottom decision: fold into `bootstrap-sandbox-provision-post-seed.yml`**,
> not a separate wrapper. Monitoring is an app-layer concern (post-seed, after
> OpenBao + the core apps + `110-authentik`, which provisions the Grafana OAuth
> provider); a separate wrapper is one more step the operator must remember on
> every rebuild. Append in dependency order — `100-prometheus` → `110-loki` →
> `130-promtail` → `120-grafana` (grafana last so its datasources resolve) — each
> `when: dmf_monitoring_profile in ['minimal','full']`. Mirror into the cloud
> post-seed wrapper later for parity (out of scope tonight).
>
> **Wizard / inventory (dmf-env):**
> - `dmf_monitoring_profile: minimal` is **already rendered** into the sandbox
>   group_vars (init-wizard.sh sandbox capabilities block — same block as the
>   `netbox_media_access_mode` fix). No change needed for the profile var.
> - **What's missing:** the Gap-B sandbox-scaled sizing vars (prometheus/loki
>   `*_storage_size` + `*_retention` + resource caps). Land them in that same
>   wizard block (rebuild-persistent) **and** the sandbox profile prelude as
>   `| default(...)` (wrapped-flow), exactly like `netbox_media_access_mode`
>   (`[[reference_sandbox_standalone_playbook_profile_gap]]`). Values from Gap B
>   (claude drafts → claude-bottom lands).

## 4. Proposed division of labour (for 2026-05-28)

| WS | Work | Owner |
|---|---|---|
| **A** | `base/grafana` local-CA OIDC trust (CA-mount, gate on local-ca); live-deploy + verify Grafana login on 9y6o-zn0t | **claude** (owns the gate-2 pattern; did netbox+zot) |
| **B** | Sandbox-scaled storage/retention/resource values for prometheus + loki (+ grafana PVC check); RWO access-mode audit | **claude** drafts values ↔ **claude-bottom** lands them in the wizard/profile |
| **C** | Make `dmf_monitoring_profile` a real gate (minimal vs full) in the monitoring vertical | **claude-bottom** (sandbox-lane/profile area) |
| **D** | Wire monitoring into the sandbox bootstrap wrappers + wizard sandbox inventory template (rebuild persistence) | **claude-bottom** (owns sandbox bootstrap + dmf-env wizard) |
| **V** | End-to-end verification (see §6) | **claude** drives live, **claude-bottom** confirms rebuild path |

Sequencing: A + B values first (so a live deploy proves the stack), then C + D to
make it durable, then a clean-rebuild verification of D.

## 5. Risks / footguns
- **Disk:** 100Gi default PVCs on a 60GiB VM → must shrink before any deploy (Gap B). Highest-risk item.
- **RWO immutable-PVC trap** if any monitoring PVC defaults RWM (cf. netbox-media). Audit first.
- **Grafana CA mount:** verify Go picks up `/etc/ssl/certs/dmf-local-ca.crt` without `update-ca-certificates` (Zot proved yes; confirm for the grafana image).
- **Authentik Grafana redirect URI:** confirm the provider's redirect URI is the sandbox callback `https://grafana.deploy.dmf.test/login/generic_oauth` (110-authentik ran with the sandbox host, so likely correct — verify).
- **Prometheus memory** on a 10GiB node shared with all other apps; cap requests/limits + trim scrape targets.
- **Loki without Promtail = empty** (Open Question 1).

## 6. Verification (definition of done)
1. `monitoring` ns: prometheus-server, loki, grafana pods all Running; PVCs Bound (small sizes).
2. `grafana.deploy.dmf.test` serves **Grafana** (not the landing page).
3. OIDC: hitting Grafana 302s to Authentik authorize; full round-trip logs in as
   `ops-admin` → GrafanaAdmin (no `CERTIFICATE_VERIFY_FAILED` in grafana logs).
4. Datasources: Prometheus + Loki both **green** in Grafana (Prometheus has data;
   Loki green even if empty pending Promtail).
5. Disk headroom on the VM remains sane after PVCs bind.
6. (Gap D) A clean rebuild via the sandbox wrappers brings monitoring up unattended.

## 7. Open questions for the operator
1. **Promtail:** "Loki only" gives a Loki datasource with **no logs ingested**
   (Promtail is the shipper). Include Promtail now (lightweight DaemonSet, makes
   Loki useful) or accept empty Loki for now? *Recommendation: include Promtail —
   it's the standard pairing and trivial; otherwise Loki is decorative.*
2. **Sizing/retention:** OK with the suggested sandbox sizes (Prom 8Gi/3d, Loki
   8Gi/7d) or different?
3. Make `dmf_monitoring_profile` real now (Gap C), or just hardcode the sandbox
   set for speed and generalise later? *Recommendation (claude-bottom): make it
   real now — see Gap C; the var exists, cost is ~one `when:` per play, and it
   keeps the cloud lane `full` without forking the wrapper.*

---

## 8. claude-bottom review (2026-05-27)
Reviewed + amended in place. **Split as proposed is right** — A is the gate-2/CA-mount
pattern claude owns (zot→netbox→grafana); C+D + landing B's values is my
sandbox-bootstrap/wizard area (same as the `netbox_media_access_mode` fix). Taking
**C + D + B-landing + the rebuild-path leg of V**. Substantive amendments:
1. **Promtail folded into `minimal`** (Gap C) — resolves the §3-vs-§7 inconsistency
   (Loki needs a shipper). Contingent on Open Q1; one-line drop if deferred.
2. **Gap D: fold into post-seed**, not a new wrapper; ordered prom→loki→promtail→grafana,
   profile-gated. And `dmf_monitoring_profile: minimal` is *already* in the wizard
   inventory — only B's sizing vars need landing there.
3. **Gap B: total-disk-budget check** (`df -h` before locking; 16Gi must coexist with
   the whole stack on 60GiB) + start-smaller option.
4. **Gap A heads-up:** verify Grafana image base (Alpine vs Zot's) before assuming the
   dir-mount transfers; `SSL_CERT_FILE` is the image-agnostic fallback.

No code tonight — locked for 2026-05-28 execution.

Related: `[[project_dmf_sandbox_local_vm]]`, `[[project_cms_authentik_backchannel_split]]`,
`[[reference_sandbox_standalone_playbook_profile_gap]]`, `[[feedback_cluster_internal_urls]]`.

---

## 9. 2026-05-28 scope-lock addendum (operator brief)

Operator brief 2026-05-28: "implement the monitoring stack in the sandbox env,
sized to fit. Reference g2r6-foa9 (outdated but has full stack running). Decide
9y6o-zn0t modify/delete freely. Make sure complete stack incl. host (Lima VM
cpu/ram/disk). Don't overcomplicate. claude-bottom is freshly cleared — instruct
them to implement. Commit regularly."

**Scope (locked, supersedes Open Questions 1–3):**
- **Complete stack = 4 helm-deployed components** (matches g2r6-foa9 live):
  Prometheus + Loki + Grafana + Promtail. **Promtail IN** (resolves Open Q1).
  LibreNMS / snmp-exporter / netdisco **OUT** (g2r6-foa9 doesn't run them either).
- **Host metrics covered by the Prometheus chart's bundled DaemonSets** —
  `node-exporter` (host CPU/RAM/disk/network/filesystem) + `kube-state-metrics`.
  Both are sub-charts of the `prometheus` 25.x chart; no extra play needed.
- **`dmf_monitoring_profile`: `minimal` = {prometheus, loki, grafana, promtail}**;
  `full` adds librenms/snmp/netdisco (later, not now); `none` skips all. Sandbox
  default `minimal`; cloud lane `full`.

**Target env: 9y6o-zn0t (MODIFY in place, do NOT delete).** Yesterday's catalog-token
+ NetBox CA fixes are live there; clean install of monitoring on top works fine.

**Sandbox sizing (mirror g2r6-foa9 reference; fits the 60GiB / 4CPU / 10GiB Lima VM):**
- Prometheus PVC `5Gi`, retention `7d` (cluster fact STATUS §3.5 uses 6h on the
  reference — too aggressive; 7d is operator-friendly given headroom). Reduce
  scrape interval if memory pressures.
- Loki PVC `5Gi`, retention `168h` (7d). Security stream off / matched to default.
- Grafana PVC `1Gi`.
- Promtail no PVC (DaemonSet, single pod on the single node).
- Total monitoring PVCs ≈ 11Gi (vs ~30Gi free on the 60GiB VM after the core
  stack). Comfortable. **Verify with `df -h` on the node before locking** (claude-bottom).
- Resource requests/limits: capped low (server-side budget; see ref values).

**Reference (g2r6-foa9 live, 2026-05-28 inventory):**
```
HELM RELEASES (ns monitoring)
  prometheus  chart=prometheus-25.8.0  app=v2.48.0  PVC=5Gi (RWO, longhorn)
  loki        chart=loki-6.6.2         app=3.0.0    PVC=5Gi (RWO, longhorn)
  grafana     chart=grafana-8.0.0      app=11.0.0   PVC=1Gi (RWO, longhorn)
  promtail    chart=promtail-6.16.4    app=3.0.0    DaemonSet, no PVC
PODS additionally: prometheus-kube-state-metrics, prometheus-prometheus-node-exporter (DS),
                   loki-canary (DS), loki-gateway, all running.
```
On the sandbox: same charts, same components, **storageClass=local-path** (RWO),
single-replica everywhere (single node), Loki single-binary mode.

**Locked workstream (single owner: claude-bottom; claude orchestrates+verifies):**
- **W1 — Grafana local-CA OIDC trust** (Gap A): publish `dmf-local-ca` ConfigMap
  into the `monitoring` ns + mount `ca.crt` into the Grafana pod. **Verify image
  base first** — `grafana/grafana` is Alpine (Go cert-dir scan differs from
  Debian/Zot). Set `SSL_CERT_FILE=/etc/ssl/certs/dmf-local-ca.crt` on the Grafana
  container as the image-agnostic primary (don't rely on dir-mount alone).
  Gate on `dmf_tls_mode=='local-ca'`. Mirror the pattern in `roles/base/grafana`.
- **W2 — Make `dmf_monitoring_profile` real** (Gap C): one place (the post-seed
  wrapper, see W3), each monitoring play imported with
  `when: dmf_monitoring_profile in ['minimal','full']` (and additionally
  `== 'full'` for librenms/snmp/netdisco if/when added).
- **W3 — Wire monitoring into the sandbox bootstrap** (Gap D): fold into
  `bootstrap-sandbox-provision-post-seed.yml` in order
  `100-prometheus → 110-loki → 130-promtail → 120-grafana` (grafana last so
  datasources resolve), each profile-gated.
- **W4 — Sandbox-fit sizing** (Gap B): land sandbox-scaled values in the dmf-env
  wizard sandbox inventory template (same block as `netbox_media_access_mode`)
  AND/OR via `dmf_monitoring_profile`-aware overrides in the monitoring roles'
  defaults. Either is fine; the wizard block is most consistent with prior fixes.
- **W5 — Live deploy on 9y6o-zn0t**: re-run the post-seed (or the individual
  monitoring plays via `run-playbook.sh`); verify (§6).

**Verification (§6 from above) still applies**, plus: node-exporter scrapes the
host's CPU/RAM/disk (visible in Prometheus' `node_*` metrics), and the Grafana
"Node Exporter Full" / k8s-views dashboards already shipped in
`roles/base/grafana/files/` render data.

**Commit cadence:** claude-bottom commits regularly per the operator's brief.
Suggested boundaries: (1) grafana-CA-mount role change, (2) profile gating +
post-seed wiring, (3) wizard sizing values, (4) any per-role default tweaks.
Push to LAN Forgejo after each.

**Coordination:** claude-bottom drives all implementation. Reports progress /
DONE / BLOCKED back to `claude` (pane 2) via
`~/.claude/skills/agent-bridge/bin/agent-bridge send claude "<status>"` so the
loop closes as notifications, not poll-and-read. `claude` (pane 2) verifies live
on 9y6o-zn0t after each milestone.
