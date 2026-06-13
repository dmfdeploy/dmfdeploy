# DMF-Aligned Operations Prototype — Platform Plan

> **Vocabulary aligned 2026-04-25** with the EBU *Dynamic Media Facility Reference
> Architecture* White Paper V2.0. See `DMF EBU Mapping (2026-04-25).md` for the
> canonical layer / vertical / lifecycle map.

**Status:** Draft for discussion
**Date:** 2026-04-17 (updated 2026-04-20: live-state inspection + doc consolidation; reconciliation note 2026-04-24; vocabulary aligned 2026-04-25)
**Repos in scope:** `~/repos/dmf-infra`, `~/repos/dmf-env`

## Status snapshot — 2026-04-24

This plan is the long-term architecture blueprint. Several sections have been
overtaken by in-tree implementation. Treat the repo as source of truth for:

- **Playbook numbering** — EBU layer/vertical/lifecycle scheme is live
  (Layer 2xx Host Platform, Layer 3xx Container Platform, vertical-security,
  vertical-monitoring, vertical-orchestration, Layer 6xx Application & UI,
  lifecycle-{provision,operate,finalise}). `site.yml` plus the lifecycle
  wrappers (`lifecycle-provision.yml`, `lifecycle-operate.yml`,
  `lifecycle-finalise.yml`) are the canonical entry points. `run-playbook.sh`
  wraps with timeout + logging. See `DMF Orchestrator and Renumbering Plan
  2026-04-22.md` (now DONE, infra `d21dde6`) and the EBU Mapping doc for the
  old phase-number → new layer/vertical translation table.
- **Private lane** — shipped as Tailscale + socat (L4) + a secondary
  Traefik on NodePort 30443, not the WireGuard-wg3 design this plan
  proposed. Intent preserved; mechanism diverged.
- **App exposure** — all 6 apps (`auth`, `awx`, `forgejo`, `grafana`,
  `netbox`, `registry`) are on host-root
  `*.dmf.example.com` with DNS-01 wildcard issuance. Apex path routing
  is retired. Public `apps.json` advertises host cards only. LibreNMS
  remains available as a module but is excluded from the initial rollout.
- **OpenBao custody** — 5-location Shamir model live: JuiceFS shares 1+2
  (`<secure-store>/openbao-breakglass/<env>/`), macOS Keychain
  share 3 (via `osascript`), USB `OPENBAO_A` shares 4+5, plus a 3-share
  quorum automation file on JuiceFS. Supersedes the "connected flypack"
  draft in §7b.
- **Flypack profile** — canonical spec is `dmf-infra/k3s-lab-bootstrap/docs/flypack-offline-lane.md`
  (airgapped-primary, ship-once-never-reconnects). Supersedes §254–257,
  §270–274, §276–279, §298–300 here.
- **Alertmanager** — ntfy formatter bridge shipped (`roles/base/prometheus/templates/ntfy_bridge.py.j2`,
  infra `048e8bb`, 2026-04-23) plus healthchecks.io watchdog.

No §-by-§ rewrite yet; this block lets a reader know which parts of the
body are overtaken by the rebuild. Items still open: reorg branch merge,
Hetzner leakage audit cleanup, OpenBao root token disposal, Longhorn
BackupTarget.

**Document role:** Canonical DMF architecture and phased work plan.

**Related active docs:**
- `STATUS.local.md` (umbrella root, gitignored) — live cross-repo state, refreshed by `bin/generate-status.sh`; committed `STATUS.md` keeps operator notes
- `docs/handoffs/` — most recent file is the canonical "what just happened / what's next"
- `docs/plans/dmf-platform-move-1-task-2026-05-04.md` — current active task spec
- `docs/decisions/INDEX.md` — ADRs (especially 0012/0013/0014/0016 for the catalog model)
- `dmf-infra/k3s-lab-bootstrap/docs/flypack-offline-lane.md` — **canonical spec for the flypack profile**

**Archived (moved to `Archive/` 2026-04-20):**
- ~~`DMF Repo Reorg Plan.md`~~ — structural work executed; branch resolution is a git issue
- ~~`DMF Multi-Environment Ingress Strategy.md`~~ — merged into §7e
- ~~`DMF Hetzner CCM vs MetalLB.md`~~ — superseded by §7e

---

## 1. Goal

> Exploratory work on a cloud-native microservices platform for IP media operations across the full lifecycle: discovery and validation, source-of-truth modelling, automated commissioning, monitoring, and structured feedback into a custom client/operator-facing CMS built for a single-pane-of-glass workflow. Built on widely used open software projects, it also serves as a practical, hands-on exercise in AI-assisted coding to prototype faster with clear change control and traceability.

## 2. Deployment profiles (the flexibility requirement)

The platform must deploy across a wide range of environments:

| Profile | Nodes | Network | Example |
|---|---|---|---|
| **Flypack** | 1 | Local-only, often disconnected | Production truck, single box, connected to local media infra |
| **Site / facility** | 3+ HA | LAN, semi-isolated | Studio, OB base, permanent venue |
| **Cloud** | 3+ HA | WAN-accessible | Hetzner/AWS/Azure, managed or self-hosted k3s |

Same codebase, profile-driven deploy.

## 3. Current state (evaluated 2026-04-17, updated 2026-04-20 live inspection)

### `dmf-infra` (public, generic)
- Ansible-driven k3s bootstrap, 14 roles, 18+ numbered playbooks
- **Working on Hetzner hub cluster (live, 3 days old):**
  - k3s v1.30.6+k3s1, 3-node HA (ARM CAX21, private network on `enp7s0`)
  - Hetzner CCM + Hetzner LoadBalancer (cloud-native ingress, `dmf.example.com → <lb-public-ip>`)
  - Traefik with Let's Encrypt TLS (cert-manager v1.16.1, HTTP-01, 3 SANs, auto-renewal)
  - Longhorn v1.10.1 (2 replicas, PVC provisioning verified, NFS backup configured, daily etcd snapshots)
- **Roles layered into `base/` + `stack/operator/` + `modules/` + `charts/`** (branch `reorg/layered-structure`, diverged from `main` — operational work landed on `main` after branch point)
- **Provider-specific logic moved to `dmf-env`** — Hetzner CCM lives in `tasks/hetzner_ccm.yml`, not in the generic repo

### Live workloads (2026-04-20 verified, 60+ pods across 13 namespaces)

| Workload | Namespace | Status | Routing |
|---|---|---|---|
| Authentik | `authentik` | 3 pods (server, worker, postgres) | Host: `auth.dmf.example.com` |
| Forgejo | `forgejo` | 1 pod | Host: `forgejo.dmf.example.com` (Ingress) |
| NetBox | `netbox` | 4 pods (+ postgres, valkey, housekeeping) | Path: `/netbox` (IngressRoute) |
| AWX | `awx` | 4 pods (+ postgres, operator, migration) | Path: `/awx` (IngressRoute) |
| Grafana | `monitoring` | 1 pod | Path: `/grafana` (IngressRoute) |
| Prometheus | `monitoring` | 2 pods (+ node-exporter ×3, kube-state) | Path: `/prometheus` (IngressRoute) |
| Loki | `monitoring` | 5 pods (+ canary ×3, gateway, promtail ×3) | Path: `/loki` (IngressRoute) |
| OpenBao | `openbao` | 1 pod | In-cluster only |
| External Secrets | `external-secrets` | 3 pods | N/A |
| Landing page | `default` | 1 pod | Path: `/` (IngressRoute) |

### `dmf-env` (private, Hetzner-specific)
- Site-specific inventory for Hetzner ARM environment
- OpenBao AppRole secrets model (role_id in git, secret_id in macOS keychain)
- Provider task files: `tasks/hetzner_ccm.yml`, `tasks/hetzner_firewall.yml`
- Domain: `dmf.example.com`, ACME email configured in the private inventory

### New repos (scaffolded, pushed to Forgejo — all scaffold-only)
- `dmf-media` — 6 stub media roles
- `dmf-central` — 6 stub roles
- `dmf-cms` — placeholder Dockerfile, Helm chart skeleton

### DMF alignment today
- ✅ Source of truth (NetBox), monitoring (Prometheus + Grafana + Loki), cloud-native runtime
- ✅ In-cluster DNS, cross-node pod/Service traffic, external ingress verified
- ✅ Let's Encrypt TLS cert issued and serving (auto-renewal at ~day 60)
- ✅ Longhorn storage verified (PVC bound, 2 replicas on separate nodes, NFS backup + etcd snapshots)
- ✅ Authentik baseline: 4 OIDC providers (Forgejo/AWX/NetBox/Grafana), break-glass, userpass operator path
- ✅ OpenBao operator retrieval path (ops-admin user, app-admin-reader policy, helper script)
- ✅ AWX deployed with operator (commissioning loop wiring still pending — AWX ↔ NetBox ↔ Forgejo integration not yet functional)
- ⚠️ All admin UIs reachable from the public internet through single Traefik (no private lane, no wg3)
- ❌ Zero media-domain code (NMOS, 2110, PTP, flows)
- ❌ No CMS — the landing page is a link portal, not a CMS

## 4. Structural issues to resolve BEFORE next cluster deploy

Three gaps compound if more clusters are built on top of them:

1. **AWX commissioning loop non-functional.** Commissioning is a DMF pillar. Fix before adding media workloads so bugs are not ambiguous.
2. **No stateful backup/DR** for NetBox + Grafana. Cheap now, expensive once real device data is in NetBox.
3. **No CI on either repo.** Two-repo model + Ansible + Helm + OpenBao = drift is inevitable without lint/syntax/dry-run on PRs. The goal explicitly requires "clear change control and traceability."

Plus one architectural decision: **where does media-domain logic live?** (See §8.)

### Resolved since original assessment

| Issue | Status |
|---|---|
| In-cluster DNS broken | ✅ Fixed — flannel bound to private NIC (`enp7s0`), CoreDNS resolving correctly |
| MetalLB + floating IP ingress | ✅ Replaced with Hetzner CCM + LoadBalancer (cloud-native profile) |
| `community.hashi_vault` crash on macOS ARM64 | ✅ Worked around — secrets fetched via curl + `bin/export-openbao-vars.sh` |
| Hetzner vendor code in generic repo | ✅ Moved to `dmf-env/tasks/`; generic repo uses `cluster_ingress_provider_tasks` delegation |
| No TLS / self-signed certs | ✅ Let's Encrypt via cert-manager + TLSStore, auto-renewal, HTTPS serving |

## 5. What "media-domain logic" means

Five layers of broadcast-specific work that must land somewhere:

1. **Data model extensions (NetBox)** — senders, receivers, flows, essences (SMPTE ST 2110-20/30/40), PTP domains, multicast pools, SDP parameters, sync islands, media profiles. Custom fields or a plugin.
2. **Discovery & validation** — NMOS IS-04/05/07/08/09, AMWA BCP compliance tests, PTP topology (ST 2059), EBU LIST for 2110-21 timing.
3. **Commissioning workflows** — route sender→receiver via IS-05 PATCH, allocate multicast + write SoT + push to device, bring-online sequence, bulk route changes for shows.
4. **Flow-level monitoring** — RTP sequence gaps, per-flow packet loss, PTP lock/offset, CRC errors, 2110-21 compliance. Needs media-specific exporters, not just node_exporter.
5. **Operator-facing CMS** — routing matrix (virtual X-Y), flow browser, tally, incidents correlated to flows not hosts.

## 6. Critique of naive "all in base" approach

Four honest pushbacks:

### 6.1 The CMS is the project, not a component
Every other app (Forgejo, AWX, ArgoCD, Prometheus, NMOS) is plumbing beneath the CMS. The landing page today is not a CMS. The CMS is custom software that doesn't exist yet and has to speak NetBox + Forgejo + AWX + ArgoCD + Prometheus + NMOS. Current repos don't acknowledge this scope.

### 6.2 AWX *and* ArgoCD is architectural overload
- AWX = imperative, hits non-K8s targets (NMOS IS-05, SNMP, IPAM writes). Wins for media ops.
- ArgoCD = declarative K8s reconciliation. Wins for platform drift.
- Both have value, but a small team will underuse one.
- ArgoCD is promise-ware until cluster state is actually Git-modeled as Helm charts / manifests. Today it isn't.
- **Decision:** defer ArgoCD to a module. AWX carries the operator flow first.

### 6.3 "Approval pipeline for every change" is a process choice, not a default
- PR-gated GitOps is right for **configuration** changes (deploy service, change VLAN).
- It is wrong for **runtime** operations (route camera 3 to PGM, arm tally).
- Forcing routing through Forgejo PRs = friction operators will bypass.
- Platform needs **two lanes**:
  - **Config-change lane:** PR → review → merge → sync (Forgejo + CI + AWX/ArgoCD)
  - **Operations lane:** CMS action → AWX job → audit log, no PR
- Design both up front or one gets bolted on badly.

### 6.4 "All in base" breaks the flypack story
Resource floor for AWX (Postgres) + ArgoCD + Forgejo (DB) + LibreNMS (MySQL+RRDtool) + Prom stack + NetBox stack + CMS on a single node ≈ **14–18 GB RAM** before any media workload. That kills "small flypack on a mini-PC." Fix with a **standalone profile** where operator IS the approver — same codebase, different stack manifest.

### 6.5 Missing from operator-stack list (non-negotiable additions)
- **Central IdP / OIDC** (Keycloak or Authentik) — single operator identity across all tools. Today each has its own auth.
- **CI runners** (Forgejo Actions) — PR validation, policy checks, dry-runs.
- **Event bus / webhook glue** — Forgejo merge → AWX job → CMS status update. This integration does not exist yet and is the thing that makes the "pipeline" a pipeline.

## 6.6. Deployment topology — hub-cluster-first (scoping decision 2026-04-17)

The platform supports federated multi-cluster deployments by design, but the **initial build is explicitly a single self-contained cluster** that also acts as the hub for any future federation. Federation is deferred until the self-contained cluster is proven end-to-end.

**What "hub-cluster-first" means in practice:**
- `dmf-central` playbooks and `dmf-infra` stack playbooks both deploy to the **same physical cluster** for Stages 0–3 of the rollout (Layers 2 → 3 → verticals → Layer 6)
- Central services (Authentik, OpenBao, Harbor) run alongside the operator stack on the same nodes
- Central services are addressed by **external-looking URLs** from day 1: `auth.<cluster-domain>`, `vault.<cluster-domain>`, `registry.<cluster-domain>` — not k8s internal `*.svc.cluster.local` shortcuts
- All stack apps reference those URLs as if central services were external
- A later rollout stage (the "flypack profile" stage) adds a second cluster (flypack or remote site) pointing at the same URLs — no migration needed

**Why this framing, not "deploy without central services":**
If Authentik/OpenBao/Harbor were embedded as inner-cluster-only Ansible roles in `dmf-infra`, splitting them out later would be a painful migration. Deploying them as hub services from day 1 — with proper URLs, their own playbooks in `dmf-central`, and external-looking wiring — makes adding a second cluster a deployment act, not a refactor.

**Explicitly deferred until after the self-contained cluster works:**
- WireGuard tunnels between clusters
- Harbor replication to edge registries (Zot)
- NetBox federation (central ↔ flypack)
- oauth2-proxy session caching for offline use (mechanism installed, but default-short-TTL; single-cluster LAN means refresh is always available)
- Flypack pull-through image cache (Zot sync)
- Push-from-flypack reconnect sync jobs
- Central-managed OIDC clients across multiple Authentik realms (one realm for now)

**Prepared but not active (groundwork only):**
- oauth2-proxy deployed and wired, but TTL tuned for single-cluster usage
- Harbor has replication endpoints *configurable* but no actual replicas exist yet
- OpenBao PKI issues certs only to same-cluster workloads; roles for future multi-cluster issuance stay as stubs
- `dmf-central/roles/openbao/` implements **relocation** of the currently external OpenBao into the hub cluster — deferred until we're confident the hub cluster can host stateful services reliably

**Rollout-stage gating:**
- Stages 0–3 of the rollout (cleanup, commissioning loop, CMS, media domain) all happen on **one cluster** acting as both stack and hub
- The flypack stage is the **first** introduction of a second cluster and activates the federation work listed above
- Do not build federation plumbing during Stages 0–3

## 7. Layer model (EBU canonical) and homelab translation

This section adopts the EBU *Dynamic Media Facility Reference Architecture*
V2.0 layer / vertical / lifecycle vocabulary as the canonical structure for
the platform. Earlier drafts of this section described a homelab-specific
`base/` + `stack/` + `central-services/` + `modules/` layout; that layout
still exists in-tree as the role-directory shape, but it is now mapped onto
the EBU model rather than being the model itself.

### 7.0 EBU canonical model (recap)

**6 horizontal layers** (white paper Figure 2):

| # | Layer              | EBU scope |
|---|--------------------|-----------|
| 1 | Infrastructure     | Compute, network, storage, timing reference (PTP/NTP/SyncE) |
| 2 | Host Platform      | OS, hardening, kernel-bypass; Cluster of Hosts |
| 3 | Container Platform | Container engine, networking, orchestration (k8s/k3s) |
| 4 | Media Exchange     | High-perf shared-memory/RDMA exchange between Media Functions; MXL SDK |
| 5 | Media Functions    | Containerised media processing units (NMOS, EBU LIST, flow exporters, PTP) |
| 6 | Application & UI   | User-facing apps, control surfaces (NetBox, Forgejo, AWX, CMS, landing page) |

Layers 1–3 are generic (vendor-agnostic IT). Layers 4–6 are industry-specific
(broadcast/media).

**4 verticals** — cross-cutting, apply to every layer:
- **Orchestration** — IaC; create/destroy/configure resources at each layer (ESO, future ArgoCD)
- **Control** — operate-time control surfaces (runbooks; no playbooks initially)
- **Monitoring** — telemetry, alerts, analysis (Prometheus, Loki, Grafana, Promtail, LibreNMS)
- **Security** — zero-trust: AAA, least-privilege, segmentation (OpenBao, Authentik)

**6-stage Media Workload lifecycle** — Design → Plan → Provision → Configure
→ Operate → Finalise & Review (+ continuous Monitor & Update). Implemented
as `lifecycle-provision.yml`, `lifecycle-operate.yml`, `lifecycle-finalise.yml`
wrappers at the repo root, plus inventory/manifest artifacts in `dmf-env/`
that act as the Design/Plan output.

### 7.1 Homelab profile and manifest terms (still in use)

EBU has no equivalent for these; they are kept as homelab-specific concepts:

- **Lane** — ingress topology choice (public / private / airgapped). Deployment-shape, orthogonal to EBU model.
- **Profile** — facility footprint (Flypack / Site / Cloud). Compatible with EBU; refers to scale, not architecture.
- **Manifest** — non-secret deployment intent doc; matches EBU "Design" lifecycle output.

### 7.2 Homelab role-directory layout mapped to EBU

The on-disk layout in `dmf-infra/k3s-lab-bootstrap/` is unchanged; only
the labels are EBU-aligned now:

```
roles/base/*                           Layer 2 (host prep, harden) +
                                       Layer 3 (k3s, ingress, cert-manager,
                                       longhorn, prometheus base)

roles/stack/operator/*                 Layer 6 (NetBox, Forgejo, AWX, CMS) +
                                       verticals: vertical-security
                                       (OpenBao, Authentik, oauth2-proxy),
                                       vertical-monitoring (Loki)

roles/stack/standalone/*               Layer 6 alternate (lighter app subset
                                       for the Flypack profile)

roles/modules/infra-monitoring/*       vertical-monitoring extension
                                       (LibreNMS, SNMP exporter, Netdisco)

roles/modules/media/*                  Layers 4 + 5 (lives in dmf-media)

roles/modules/advanced/*               vertical-orchestration extension
                                       (ArgoCD, federation)

roles/common/*                         Utilities used across layers
```

### 7.3 Per-component placement in the EBU model

| Component | EBU placement |
|---|---|
| k3s, traefik, cert-manager, longhorn, kube-prometheus-stack base | Layer 3 — Container Platform |
| storage-slot (local-path / longhorn / cloud CSI) | Layer 3 |
| lb-slot (cloud-native / metallb-bgp / metallb-l2 / nodeport-only) | Layer 3 |
| external-secrets-operator | vertical-orchestration |
| OpenBao | vertical-security |
| Authentik | vertical-security |
| oauth2-proxy | vertical-security |
| Prometheus, Loki, Grafana, Promtail, Alertmanager rules | vertical-monitoring |
| LibreNMS, SNMP exporter, Netdisco | vertical-monitoring (infra-monitoring extension) |
| NetBox, Forgejo + runners, AWX, landing page, CMS, event-glue | Layer 6 — Application & UI |
| Container registry (Harbor / Zot) | Layer 3 (runtime) + vertical-security (signing/scan policy) |
| nmos-cpp, EBU LIST, flow exporters, PTP monitor, NetBox media plugin | Layers 4–5 (dmf-media) |
| ArgoCD (deferred), netbox-federation (deferred) | vertical-orchestration (advanced) |

### 7.4 Profile composition

`base/` = pure platform = **Layer 2 + Layer 3 + cross-cutting verticals**.
`stack/operator` and `stack/standalone` are profile-specific selections of
**Layer 6** components. `modules/*` are EBU-aligned extensions:
`modules/infra-monitoring` extends vertical-monitoring,
`modules/media` provides Layers 4–5, `modules/advanced` extends
vertical-orchestration.

**Key composition rules (preserved from earlier draft):**
- **LibreNMS is not in Layer 3 base nor in Layer 6 stack** → it lives under vertical-monitoring (`modules/infra-monitoring/`).
- **Authentik is in vertical-security at the central Cluster**, not per-cluster (one instance, everyone federates).
- **OpenBao is in vertical-security at the central Cluster**, expanded scope (see §7b); not a Layer 3 "slot".
- **`cert-manager` (Layer 3) integrates with OpenBao PKI (vertical-security)** where WAN reachable; falls back to ACME or self-signed for airgap.
- **Storage slot clarified**: `local-path` = ephemeral flypack only; `longhorn @ replica 1` = scalable flypack (default).

## 7a. Discovery architecture — three lanes

SoT discipline: NetBox is authoritative. Discovery tools **propose** into NetBox staging; operators (or policy-gated AWX jobs) promote to active. Discovery never writes authoritatively.

| Lane | Tool | Protocol | Writes to |
|---|---|---|---|
| **L2/L3 infra topology** | LibreNMS or Netdisco | LLDP/CDP/ARP/SNMP | NetBox *staging* status |
| **Infra metrics** | Prometheus SNMP Exporter | SNMP v3 | Prometheus (targets generated from NetBox) |
| **Media devices** | nmos-cpp registry | NMOS IS-04 (mDNS + HTTP) | NetBox via *media plugin* |

Rationale: single TSDB (Prometheus), single SoT (NetBox), media-aware discovery (NMOS) alongside infra-aware discovery (SNMP/LLDP). No tool maintains its own device inventory.

## 7b. OpenBao scope (per-cluster embedded secrets backend)

> **Updated 2026-04-27.** DMF does **not** involve the operator-side
> wg2/Aliyun OpenBao at `<wg-mesh-ip>` (memory:
> `project_dmf_no_wg2_openbao.md`). The earlier "one central OpenBao for
> all clusters" model is retired. wg2-OpenBao remains as the operator's
> personal cross-site secrets infra, but it is not part of any DMF
> profile.

Each DMF cluster runs its **own** OpenBao instance, embedded in-cluster
and exposed only on the cluster service network
(`http://openbao.openbao.svc:8200`). There is no shared central runtime
endpoint — secret coordination across clusters happens through bootstrap
artefacts (the Resource Profile manifest + breakglass shares on JuiceFS),
not a runtime network path.

This generalises the flypack-lane pattern (canonical:
`dmf-infra/k3s-lab-bootstrap/docs/flypack-offline-lane.md`) to **all**
DMF profiles — cloud, site, flypack.

Scope per cluster expands beyond KV-only use:

| Engine | Use |
|---|---|
| **KV v2** | Static creds — device admin passwords, API tokens, SNMPv3, TACACS shared secrets, cluster bootstrap secrets |
| **PKI** | Internal CA — issues short-lived certs for NMOS IS-10 TLS, media control-plane mTLS, service-to-service mTLS, operator browser certs |
| **SSH** | Signed SSH certs for operator access to switches/routers — replaces static authorized_keys on devices |
| **Kubernetes auth method** | Pod-level secret injection via external-secrets-operator (in-cluster) |
| **OIDC auth method** | Operators authenticate to OpenBao *via Authentik* — single login flow per cluster |
| **AppRole** | Machine-to-machine (Ansible, AWX, CI runners) inside the cluster |

**Operator-side token resolution** for pre-cluster work (`tofu apply`,
`bin/run-playbook.sh` from the Mac mini before a cluster exists) reads
from local config shims (`~/.config/hcloud/cli.toml`,
`~/.config/cf/dns.txt`). After provisioning, ESO inside the cluster takes
over all in-cluster secret resolution.

**Disconnected operation** is intrinsic to the design — every profile is
offline-capable by construction:

- ESO caches resolved secrets in k8s Secrets at deploy; no runtime dependency on the operator host
- Sealed-secrets remains an option as a long-term airgap fallback (controller + SealedSecret objects committed to local git)

## 7c. Authentik topology — central, not per-cluster

One Authentik instance lives in `central-services/` at the main site or cloud. All clusters (flypack, remote site, cloud) configure their OIDC clients against this single instance.

**Why central, not per-cluster:**
- Consistent operator identity across every deployment
- Single revocation point
- One audit trail for authn events
- Authentik's ~1 GB platform tax paid once, not N times
- Group/role mapping defined once (broadcast roles: `studio-op`, `net-eng`, `media-admin`, etc.)

**Flypack offline pattern:**

> **Superseded (2026-04-18) for the flypack lane.** The flypack now runs its **own
> embedded Authentik** (blueprint-seeded at factory); there is no oauth2-proxy
> dock-login model. Canonical: `dmf-infra/k3s-lab-bootstrap/docs/flypack-offline-lane.md`.
> Central Authentik remains correct for **site** and **cloud** profiles.

- `oauth2-proxy` in front of each app with extended session TTL (7–30 days)
- Operator logs in once at dock (WAN available) → session cookie valid for field duration
- On reconnect, session refreshes normally
- Covers 95% of field cases (day-to-week shoots)

**When central Authentik is wrong (rare):**

> **Superseded (2026-04-18) for the flypack lane.** What was framed here as the
> rare exception ("slim Authentik per flypack" / "air-gapped indefinitely = different
> product") is now the **default and canonical model** for flypack. See the
> canonical spec.

- Flypacks isolated for weeks: deploy a slim Authentik per flypack with realm exported from central, accept drift + reconcile on return
- Production air-gapped indefinitely: central model doesn't apply; treat as a different product

**Reconciliation note:** `central-auth-proposal.md` proposed **Keycloak**. This plan supersedes that with **Authentik** — lighter footprint, sufficient features (OIDC + SAML + LDAP + flow builder), better UX. pocket-id tests in progress confirmed too narrow (OIDC + passkeys only, no group claims flexibility needed for broadcast role mapping).

## 7d. Scalability matrix — what can change without redeploy

| Change | Cost | Notes |
|---|---|---|
| Add/remove nodes | Cheap | k3s native; Longhorn rebalances automatically |
| Add modules (media, infra-monitoring) | Cheap | Independent Helm releases, playbook per module |
| Remove modules | Medium | Export state first (NetBox data, AWX history, Grafana dashboards) before uninstall |
| Swap IdP target | Medium | Re-create OIDC clients, re-map groups; avoid — pick Authentik once |
| **Storage slot change** (local-path → Longhorn) | **Expensive** | Per-PVC data migration; choose for target shape at install |
| LB slot change (MetalLB → cloud LB) | Medium | Service annotations + DNS changes |
| Profile upgrade (standalone → operator) | Medium | Documented runbook, not automatic; adds Forgejo + AWX data stores |
| Profile downgrade (operator → standalone) | Expensive | State eviction + migration out of removed services |
| OpenBao engine enablement (PKI, SSH) | Cheap | Just enable the engine on existing instance |

**Design rule from this matrix:** pick storage slot for *target shape*, not current node count. Scalable flypack = Longhorn @ replica 1 from day 1 (accept the ~500 MB RAM tax). Ephemeral flypack (throwaway after event) = local-path OK.

**Flypack sub-profiles:**

> **Superseded (2026-04-18).** The flypack lane is now a **single tier** with
> composable role toggles (`storage`, `nodes`, `ingress_mode`, `tls_mode`, per-role
> on/off). Sub-profiles are deferred until a second client demands a distinct shape.
> Canonical: `dmf-infra/k3s-lab-bootstrap/docs/flypack-offline-lane.md`.

- `standalone-ephemeral` — local-path, throwaway, fastest deploy, cannot scale without redeploy
- `standalone-scalable` — Longhorn @ replica 1, can grow to HA by adding nodes and bumping replica count

## 7e. Multi-environment ingress strategy

This section supersedes the narrower ingress comparison notes. The portability target for DMF is
**not** one universal external-IP mechanism. The portability target is a stable Kubernetes ingress
contract with an environment-specific `lb-slot` behind it.

**Portable contract:**
- applications publish traffic through the normal Kubernetes primitives (`Ingress` / Gateway, `Service`, DNS names, TLS policy)
- Traefik remains the default ingress layer unless a profile explicitly overrides it
- platform services use stable hostnames such as `auth.<domain>`, `vault.<domain>`, `registry.<domain>`, `netbox.<domain>`, `grafana.<domain>`, `cms.<domain>`
- applications do **not** hard-code provider-specific ingress annotations; those come from environment values

**Supported `lb-slot` modes:**
- `cloud-native` — provider-managed Kubernetes load balancer
- `metallb-bgp` — MetalLB with BGP peering to upstream routers
- `metallb-l2` — MetalLB L2 announcement mode
- `nodeport-only` — no cluster-managed VIP; external path is local or separately fronted

**Default mode by profile:**
- **Cloud** → `cloud-native`
  - Hetzner CCM + Hetzner Load Balancer
  - AWS Load Balancer Controller / NLB / ALB
  - GKE / AKS provider-native load balancer path
- **Site / facility** → `metallb-bgp`
  - preferred on-prem mode when router ownership and BGP are available
- **Small site / lab** → `metallb-l2`
  - acceptable fallback when BGP is unavailable but a local VIP is still useful
- **Flypack local-only** → `nodeport-only`
  - lowest-complexity option for disconnected and 1-node deployments
  - `metallb-l2` remains optional where a stable LAN VIP is genuinely needed

**Why this boundary matters:**
- `cloud-native` is the cleanest scaling story for cloud environments because the public IP belongs
  to a real cloud LB resource and target-node reconciliation is provider-managed
- `metallb-bgp` is the best long-term on-prem story where DMF owns the network and can peer with routers
- `metallb-l2` is useful but should be understood as a simple failover/VIP mechanism, not a universal HA abstraction
- `nodeport-only` is the right minimum for many flypack and local-only deployments

**Explicit anti-patterns:**
- do not standardize on `MetalLB + floating IP` as the universal DMF ingress model
- do not chain cloud LB and MetalLB for the same ingress path unless there is a very unusual, explicit reason
- do not treat a public-cloud floating IP as a universal HA primitive
- do not mark ingress healthy just because Deployments show `Ready`

**Environment-facing values shape:**

```yaml
cluster_ingress:
  mode: cloud-native | metallb-bgp | metallb-l2 | nodeport-only
  domain: lab.example.net
  public: true
  ingress_class: traefik
  service_type: LoadBalancer
  external_traffic_policy: Cluster
  node_selector: ""
  service_annotations: {}
  metallb:
    address_pool: ""
    advertisement_mode: l2 | bgp
```

**Verification gates for every new environment:**
- **Gate A — node network:** nodes reach each other on the intended cluster interface and the private NIC is explicit
- **Gate B — pod network:** pod-to-pod traffic and DNS work cross-node
- **Gate C — service network:** ClusterIP, NodePort, and admission webhooks work cross-node
- **Gate D — ingress path:** the chosen `lb-slot` actually reaches Traefik correctly from outside the cluster
- **Gate E — hostname contract:** required DNS names and TLS behavior match the platform expectation

**Consequence for the current Hetzner lab:**
- validating Hetzner with CCM + cloud LB does **not** make DMF Hetzner-specific
- it validates the **cloud** profile only
- later site/facility and flypack work should validate the MetalLB- and NodePort-based profiles independently

## 7f. Flypack lane supersession (2026-04-18)

> **Pointer section.** The flypack profile was redefined on 2026-04-18 after a
> product-requirement review. It is now treated as a **permanently airgapped**
> appliance — factory build, ship once, live indefinitely without any reconnect.
> The canonical spec is:
>
> **`dmf-infra/k3s-lab-bootstrap/docs/flypack-offline-lane.md`**
>
> The following blocks elsewhere in this plan are now superseded **for the
> flypack lane specifically** (site and cloud profiles are unaffected):
>
> - §7b "Flypack offline strategy for secrets" — replaced by embedded OpenBao inside each truck
> - §7c "Flypack offline pattern" — replaced by embedded Authentik inside each truck (no oauth2-proxy dock-login model)
> - §7c "When central Authentik is wrong (rare)" — what was framed as a rare exception is now the default
> - §7d "Flypack sub-profiles" — collapsed to a single `flypack` tier with composable role toggles; sub-profiles deferred
>
> Supersession rationale, full architecture, Shamir unseal custody, both TLS
> modes (`factory-acme` and `customer-provided`), signed update packs, and the
> `truckctl` operator CLI all live in the canonical doc. Do not re-derive them
> here.

## 7g. Break-glass local admin doctrine (2026-04-19)

Every SSO-federated app keeps exactly **one permanent local admin account** forever. OIDC integration adds a second login path; it never replaces the first. This is the break-glass lane.

**Why this exists:**
- Authentik is the SPOF for the identity plane. When it is down, misconfigured mid-migration, or its OIDC client for an app is broken, the only way back in is a local admin.
- Initial deploy needs a usable admin *before* Authentik's OIDC provider and per-app client exist — bootstrap ordering forbids SSO-only from day 1.
- Some apps (Forgejo git protocol, AWX CLI with `awx-manage`) have operational paths that expect a local identity regardless of SSO.

**The rule (one-liner):** every app playbook seeds one local admin, keeps it enabled, and never deletes it. OIDC integration playbooks (under `playbooks/vertical-security/` for Authentik-integration steps) must not disable local login.

**Credential flow (deploy-time):**

1. Deploy playbook's `pre_tasks` check OpenBao at path `secret/apps/<app>/admin` (keys: `username`, `password`, optional `email`).
2. If the secret exists → use it. Idempotent re-deploy reuses the same credentials.
3. If missing:
   - **Interactive run (TTY):** `vars_prompt` asks the operator for username + password (confirm, no_log). Playbook writes the result back to `secret/apps/<app>/admin` before proceeding.
   - **Non-interactive run (CI/AWX):** generate a 32-char random password, fixed username (`admin`), write to OpenBao, continue. Operator retrieves afterward.
4. Deploy playbook creates an `ExternalSecret` that materializes the OpenBao entry into a K8s Secret in the app's namespace. The app's Helm values / init job reads from that Secret to seed the local admin.
5. Rotation is a write to OpenBao + re-sync (ESO `refreshInterval`, or force re-reconcile).

**Retrieval path (human operator):**

- Operator authenticates to OpenBao via **userpass** identity (one per operator human, seeded during `playbooks/vertical-security/100-openbao.yml` post-init). Policy grants `read` on `secret/data/apps/*/admin`.
- CLI: `bao login -method=userpass username=<op>` then `bao kv get -field=password secret/apps/<app>/admin`.
- Optional wrapper: `bin/get-admin-cred.sh <app>` in the bootstrap repo — prints username+password or opens the app URL with credentials on clipboard.
- After Authentik is live, the same operator has an OIDC auth method against OpenBao (§7b) for a single login flow; userpass remains as a break-glass for the break-glass.

**Playbook conventions:**

- Pre-deploy fact-gathering pattern lives in a shared role `roles/common/app-admin-facts` — takes `app_admin_app_name` (e.g. `forgejo`), exposes `app_admin_username` / `app_admin_password` as no_log facts, handles the check/prompt/generate/write logic.
- Every app role consumes that role as a dependency; no app role prompts directly.
- A separate per-app `ExternalSecret` template materializes the K8s Secret; the app's local-admin seed task reads from the Secret, never from OpenBao directly.

**What this is NOT:**

- Not a replacement for Authentik — 99% of daily logins go through SSO. The local admin is dormant.
- Not a shared credential — one local admin per app, distinct passwords, all stored separately in OpenBao.
- Not exposed to the public ingress unless the app requires it for git/CLI protocols (e.g. Forgejo ssh). Where possible, local-admin web login is restricted to the internal network / VPN.

**Flypack parity:** embedded OpenBao + embedded Authentik inside the truck follow the same rule. The factory seed creates one local admin per app in the embedded OpenBao; the unseal/root custody model in the canonical flypack doc governs how that credential is retrieved in the field.

**Scope of this doctrine right now:** Authentik itself (superadmin + one break-glass local user), Forgejo, AWX, NetBox, Grafana. Extended to every future SSO-federated app added to the platform.

## 8. Repo split decision

**Four repos.** The splits map to real boundaries (topology, tech stack, env, build artifact) — all decided 2026-04-17.

```
dmf-infra         (public) — base/ + stack/operator + stack/standalone + modules/*
dmf-media         (public) — modules/media only; depends on dmf-infra
dmf-central           (public) — central-services/: Authentik, OpenBao, Harbor, central NetBox (opt), central Forgejo (opt)
dmf-env           (private) — multi-env inventories + per-env secrets references
dmf-cms               (public) — the operator-facing CMS as a standalone web app (its own language stack, CI, release cycle)
```

Five repos total including the CMS. Dependency direction is clean: `dmf-cms` → `dmf-media` → `dmf-infra`; `dmf-central` is consumed by all; `dmf-env` parameterises any of them.

### 8a. Decision A — `dmf-central` as separate repo (not a profile)

Central services have a different deployment topology (deployed once, everyone federates in), different release cadence, and different failure domain from stack clusters. Keeping them inside `dmf-infra` would conflate "how to deploy a cluster" with "what's deployed at the centre." Moving later would fracture history, break inventory paths, and force a secrets migration.

### 8b. Decision B — `dmf-cms` as separate repo (not a `dmf-media` module)

The CMS is a web app (JS/TS/Python), not IaC. Different CI surface (unit + e2e + visual regression), different tests, different contributors likely, different release cycle. It *consumes* the platform; it isn't part of it. It also speaks to NetBox + AWX + Prometheus + NMOS — it's not exclusively media. Putting it inside `dmf-media` forces the media repo to absorb frontend tooling.

### 8c. Decision C — `dmf-env` becomes multi-env (not N repos)

```
dmf-env/
  inventories/
    hetzner-arm/       (current Hetzner env)
    flypack-01/        (future)
    site-bern/         (future)
    cloud-dev/         (future)
  tasks/               (env-specific tasks like hetzner_firewall.yml)
  templates/
  bin/run-playbook.sh  (wrapper already exists)
```

One private repo, one secrets backend reference, easy cross-env diff. Splitting N repos later is always possible; merging N repos is painful. Each env maps to its own OpenBao AppRole — secrets isolation maintained at the OpenBao layer, not the repo layer.

#### 8c.1 Four-field env schema (init-wizard 2026-05-19)

The original schema used a single freeform string per environment for the
identifier, the directory name, the cluster name in NetBox, and to imply
provider + architecture (`hetzner-arm`, `aliyun-123`). That conflation
broke filtering ("which envs run on AWS?"), made arch undetectable from
inventory, and made the path-shaped identifier hostile to a future
operator portal. The init wizard now writes four orthogonal fields:

| Field | Shape | Generated? | Used as path? | Surfaces in NetBox? |
|---|---|---|---|---|
| `env_id`       | `[a-z0-9]{4}-[a-z0-9]{4}` (e.g. `nb1k-7q3m`) | wizard auto | **yes** — the only path identifier | yes (cluster name + custom field `dmf_env_id`) |
| `env_label`    | free text, optional (e.g. `production-lab`)  | operator    | no — never in a path                | yes (site display name + custom field `dmf_env_label`) |
| `provider`     | enum `hetzner` \| `aliyun` \| `aws`           | operator    | no                                  | yes (custom field `dmf_provider`, selection set; drives `manufacturer`) |
| `architecture` | enum `arm64` \| `amd64`                       | operator    | no                                  | yes (custom field `dmf_architecture`, selection set) |

The identifier (`env_id`) drives every path-shaped artifact —
`inventories/<env_id>/`, `bundles/<env_id>.sops.yaml`,
`terraform/<env_id>/`, `manifests/<env_id>.yaml`, B2 bucket suffixes,
OpenBao break-glass dirs, keychain service names, the `.sops.yaml`
recipient rule, and the NetBox cluster name. It is intentionally opaque
so renaming a deployment ("production-lab" → "prod-eu") only touches the
human-facing `env_label`, never the underlying state.

`env_label`, `provider`, and `architecture` flow into structured fields
on the bundle (`metadata.*`), the resource-profile manifest
(`metadata.*` and `spec.*`), the inventory (`dmf_env_label`,
`dmf_provider`, `dmf_architecture`), and NetBox custom fields on both
`dcim.site` and `virtualization.cluster`. `base_domain` continues to be
a separate concern (`spec.ingress.external_base_url`) — it has always
been distinct from the env identifier and is not coupled to this schema.

Pre-schema environments (`hetzner-arm`, `aliyun-123`) keep their
freeform names as the path identifier. `dmf-env/bin/run-playbook.sh`
injects `dmf_inventory_env_name` as an extra-var so the legacy
fallback in `dmf-born-inventory` resolves to the inventory directory
name rather than a literal `hetzner-arm` default. The wizard's
collision check refuses to overwrite any of those legacy directories.

### 8d. Decision D — Helm charts extracted into `charts/` (not embedded in Ansible roles)

```
dmf-infra/
  charts/              (source-of-truth Helm charts per component)
    netbox/
    awx/
    librenms/
    ...
  roles/               (Ansible roles reference the chart, pass values)
    netbox/tasks/main.yml  → helm_install ../../charts/netbox
```

Helm values stay passed via Ansible (so env-specific config still flows through `dmf-env`), but the chart itself is versioned as a chart, not as a role template. This makes:
- Chart versioning real (semver, independent of Ansible role version)
- ArgoCD adoption a redirect (point Application at `charts/netbox` instead of swapping Ansible for Argo)
- Chart reuse possible across repos without copy-paste

No separate `k3s-charts` repo yet — defer until an OCI chart registry is actually needed.

### 8e. Alternatives rejected

- **Everything in one monorepo.** Easy to start, but couples release cycles of infra, media, CMS, central services. Rejected.
- **`dmf-media/modules/media/` inside `dmf-infra`.** Bloats the "generic reusable" claim; makes swapping NMOS implementations churn the base. Rejected.
- **CMS inside `dmf-media`.** Forces media repo to carry frontend CI. Rejected.
- **One repo per env (many `k3s-env-*` private repos).** More moving parts, harder to share secrets patterns. Rejected.
- **Embedded Helm values forever.** Precludes ArgoCD and chart versioning. Rejected.

## 8f. Container image registry — supply chain and airgap story

Production broadcast cannot depend on `docker.io` during a show. Registry is a non-negotiable platform concern.

**Requirements:**
1. **Reproducibility** — images pinned by digest, not floating tags
2. **Availability** — flypack pulls must succeed without WAN
3. **Supply chain integrity** — custom images signed (cosign), SBOM generated, CVE scanning
4. **Custom artifact hosting** — CMS builds, media controllers, NetBox plugin images

**Architecture:**

```
Upstream registries (docker.io, quay.io, ghcr.io, lscr.io)
            │
            │  proxy-cache pulls
            ▼
┌──────────────────────────────────────┐
│  Central registry (in dmf-central)   │
│  - Harbor or Zot                     │
│  - Proxy cache for all upstreams     │
│  - Hosts custom images (CMS, media)  │
│  - cosign signing + verification     │
│  - Trivy CVE scanning                │
│  - Replication endpoints defined     │
└──────────────────────────────────────┘
            │
      ┌─────┴──────┐
      │            │
      ▼            ▼
  Site pull     Flypack local
  (WAN-backed)  Zot cache (seeded at dock)
                containerd mirror → localhost
```

**Policies:**
- All Helm values pin images by **digest**, not tag (`image: netbox@sha256:...`)
- Custom images signed with **cosign** at build
- Admission webhook (**kyverno** or **cosign policy-controller**) enforces signed-only on production clusters
- SBOMs attached to images at build (syft → OCI referrers)
- Pull secrets sourced from **OpenBao** via external-secrets-operator (same pattern as every other secret)

**Flypack pattern:**
- Small Zot instance runs on the flypack node (~50 MB)
- Before dock departure: `zot sync` pulls required images from central (pinned list from the stack manifest)
- containerd `registry.mirrors` config rewrites all pulls to `localhost:5000`
- Show runs fully offline; no WAN dependency for image pulls

**Central registry choice — Harbor vs Zot — deferred:**
- **Harbor:** full UI, project RBAC, Trivy built-in, replication UI, SAML/OIDC, robot accounts. ~1–2 GB RAM + Postgres + Redis.
- **Zot:** OCI-native, cosign/SBOM-first, lightweight (~50 MB), CLI-driven, simpler but less UI.
- Picking one is low-cost to change — digest pins and admission policy are the invariants.

**Repo implications of registry decision:**
- **Dockerfiles live next to source**: `dmf-cms/Dockerfile`, `dmf-media/charts/<component>/Dockerfile` where we build custom images
- **CI (Forgejo Actions) builds + signs + pushes** on tag → digest referenced in chart values
- **Chart `values.yaml` pins digests**; chart version bumps when digest changes
- **Admission policies** live in `dmf-infra/base/` (platform-wide security invariant)
- **Pre-flight sync manifest** (list of images a flypack needs) lives in `dmf-infra/stack/standalone/`

**Deferred decisions (not blocking repo layout):**
- Harbor vs Zot for central
- CVE policy (block on high? medium? informational only?)
- Retention policy (how many image versions kept)
- Whether to also mirror Helm charts through the same registry (OCI artifacts)

## 9. Change-control model (the "two lanes")

### Config lane (PR-gated)
```
Operator edits in CMS → CMS commits to Forgejo PR
  → CI runs (ansible-lint, helm lint, dry-run, policy)
  → Reviewer approves → merge
  → Webhook → AWX job template executes → status back to CMS
  → Prometheus confirms outcome, CMS shows green/red
```

### Operations lane (runtime, no PR)
```
Operator triggers action in CMS (e.g., route sender→receiver)
  → CMS calls AWX job template directly (IS-05 PATCH)
  → AWX writes audit event to Loki (structured JSON)
  → CMS shows result + flow monitoring correlates
```

Both lanes emit to the same audit store (Loki structured logs or a dedicated events index). Traceability = query audit store by operator, flow, or time window.

## 10. Ordered work plan (proposed)

This plan is sequenced as rollout stages, not EBU lifecycle stages. Each
stage exercises one or more EBU layers/verticals and culminates in a
`lifecycle-operate` verify pass.

**Stage 0 — Structural cleanup + hub cluster bring-up (current stage):**

All of Stage 0 targets a **single self-contained cluster** acting as both the operator stack host and the central-services hub. No federation yet. Touches Layers 2–3, vertical-security (OpenBao, Authentik baseline), vertical-monitoring (Prom/Loki/Grafana), vertical-orchestration (ESO), and Layer 6 (Application & UI baseline).

1. **Repo creation & reorg** — ✅ completed 2026-04-17 (see `Archive/DMF Repo Reorg Plan.md`):
   - `dmf-infra` layered into `base/` + `stack/*` + `modules/*` (branch `reorg/layered-structure`, diverged from `main`)
   - `dmf-central`, `dmf-media`, `dmf-cms` scaffolded and pushed to Forgejo
   - `dmf-env` multi-env pattern (branch `reorg/multi-env-docs`, diverged from `main`)
   - **Completed live:** NetBox reference chart extraction deferred (not blocking), CI in dmf-infra (`.forgejo/workflows/ci.yml` scaffolded), live Hetzner bootstrap verified end-to-end
2. **Live Hetzner hub cluster bootstrap** — ✅ completed 2026-04-17:
   - `playbooks/210-harden.yml` → nftables, fail2ban, SSH hardening, unattended-upgrades (Layer 2)
   - `playbooks/200-baseline.yml` → Python kubernetes lib, helm binary, kernel modules, sysctl, chrony (Layer 2)
   - `playbooks/300-k3s.yml` → 3-node HA etcd on private network (`10.0.0.x`), flannel on `enp7s0` (Layer 3)
   - `playbooks/310-ingress-public.yml` → Hetzner CCM + LoadBalancer, `dmf.example.com` DNS, HTTP→HTTPS redirect at the Traefik `web` entrypoint via `HelmChartConfig` (Layer 3)
   - `playbooks/320-cert-manager.yml` → cert-manager v1.16.1, Let's Encrypt ClusterIssuer (HTTP-01), TLS certificate issued and serving (Layer 3)
   - `playbooks/339-container-platform-verify.yml` → DNS, cross-node pod/Service, ingress path all verified (Layer 3 verify)
   - `playbooks/330-longhorn.yml` → Longhorn v1.10.1, 2 replicas, PVC provisioning verified (Layer 3)
3. **Remaining Stage 0 work:** deploy platform playbooks (`playbooks/600-landing-page.yml` → `playbooks/vertical-monitoring/100-prometheus.yml` → `playbooks/vertical-monitoring/120-grafana.yml` → `playbooks/610-netbox.yml` → `playbooks/691-netbox-sot.yml` → `playbooks/692-forgejo-bootstrap.yml` → `playbooks/693-awx-integration.yml`), then merge reorg branches. LibreNMS (`playbooks/vertical-monitoring/140-librenms.yml`) is available as a module but excluded from the initial rollout.
   - Immediate follow-up from the first live platform slice: keep path-based roles on the same
     Traefik pattern now proven on the Hetzner hub cluster:
     entrypoint-level HTTP→HTTPS redirect, `tls: {}` default-`TLSStore` inheritance, and only
     namespace-local middleware for real app-path behavior

**Stage 1 — Close the commissioning loop (on existing cluster):** Layer 6 + vertical-security integration work.
6. **Registry adoption:** pin all Helm chart images by digest, route pulls through central registry, enable cosign signing for any custom images
7. **Authentik federation:** wire NetBox + AWX + Forgejo + Grafana + OpenBao OIDC clients
8. **AWX Job Templates:** first end-to-end template ("sync NetBox device → apply config"), Machine credentials from OpenBao
9. **Forgejo runners + PR validation:** `.forgejo/workflows/` in every repo
10. **Event glue prototype:** Forgejo merge webhook → AWX launch → status callback + Loki audit event
11. **OpenBao PKI enablement:** internal CA, cert-manager ClusterIssuer pointing at PKI, migrate existing self-signed certs

**Stage 2 — CMS skeleton (`dmf-cms` repo):** Layer 6 — Application & UI extension.
12. Decide CMS tech stack (web framework, auth flow, deploy model) — blocks start
13. **Minimum viable CMS:** read NetBox, list AWX jobs, show Prometheus alerts, trigger one Job Template
14. **Both lanes wired:** config (PR lane) + operations (direct call lane), both emit structured audit events to Loki
15. CMS image built via CI, signed, pinned in chart

**Stage 3 — Media domain (`dmf-media` repo):** Layers 4–5 — Media Exchange + Media Functions.
16. **NetBox media plugin:** sender/receiver/flow schema, published as NetBox plugin image
17. **nmos-cpp registry** deploy + IS-04 discovery → writes to NetBox media plugin
18. **EBU LIST** deploy for 2110 packet analysis
19. **Flow exporters** → Prometheus (per-flow RTP/PTP metrics)
20. **First media Job Template:** "route sender X to receiver Y via IS-05 PATCH"
21. **CMS media views:** routing matrix, flow browser, tally

**Stage 4 — Flypack profile + federation activation (`stack/standalone/`):**

This is where the federation work that was deferred during Stages 0–3 lands. Second physical cluster (Layers 2–3 again, on a flypack-shaped Host Platform) appears for the first time.

22. Build standalone stack manifest, validate on single mini-PC
23. **Federation plumbing** (new at this stage):
    - WireGuard tunnel between flypack and hub cluster
    - Harbor replication endpoint to flypack-local Zot
    - OpenBao secret materialisation strategy for offline operation
    - NetBox federation per §6 hybrid model (pull device inventory, push flow state)
24. **Registry sync tooling:** pre-dock `zot sync` command; containerd mirror config
25. **oauth2-proxy session caching** tuned for multi-day offline (TTL 14–30 days)
26. Flypack deploy runbook
27. First end-to-end flypack deploy + reconnect cycle

**Stage 5 — Hardening (parallel with Stage 4):** vertical-security across all layers.
27. Admission webhook (kyverno / policy-controller) — signed-images-only policy
28. CVE scanning policy tuned in registry (block criticals, warn highs)
29. SBOM generation for all custom images
30. Disaster recovery drill (`lifecycle-operate` + `lifecycle-finalise`): restore central services from backup to a fresh cluster

## 11. Open questions for discussion

**Resolved** (moved to §12 decision log):
- ~~Central-services deployment — separate repo or profile?~~ → Decision A
- ~~CMS repo placement?~~ → Decision B
- ~~Multi-env model?~~ → Decision C
- ~~Helm chart extraction?~~ → Decision D
- ~~IdP choice — Keycloak vs Authentik vs pocket-id?~~ → Authentik, central
- ~~LibreNMS role?~~ → module, staging-writes only
- ~~Container registry pattern?~~ → central Harbor/Zot + flypack pull-through

**Resolved 2026-04-17 (moved to §12):**
- ~~Flypack offline duration + reusability~~ → days-offline, field-reusable default; `standalone-scalable` profile
- ~~CMS tech stack~~ → FastAPI + HTMX + WebSockets (Python)
- ~~Harbor vs Zot~~ → Harbor at hub, Zot on flypack
- ~~cert-manager issuer policy~~ → openbao-pki default, letsencrypt-prod for public, selfsigned bootstrap only
- ~~Admission policy strictness~~ → enforce custom, warn upstream, block direct pulls
- ~~Flypack federation model~~ → hybrid by data type
- ~~Deployment topology~~ → hub-cluster-first, federation deferred to Stage 4 (flypack)

**Still open:**
1. **Operations-lane audit store** — Loki or dedicated event index (OpenSearch/Meilisearch)? Loki is already present; default to it unless query ergonomics force a change. Decide when building the CMS audit view.
2. **ArgoCD activation timing** — chart extraction (decided) makes ArgoCD a flip-of-a-switch. Keep deferred unless a specific need forces it.
3. **Non-media deployment profile** — do we actively model one (generic IT ops), or is "media-first, generic-possible-by-subtraction" sufficient? Probably the latter; confirm.
4. ~~**Reorg branch merge**~~ → **Resolved 2026-04-20:** Branches diverge from `main` (operational work landed after branch point). Need rebase before merge. See `DMF Open Questions 2026-04-20.md`.
5. **Private lane / security hardening** — All admin UIs currently public via single Traefik. The two-lane ingress plan (wg3 + private Traefik) from the Session Handoff is still the target, but sequencing needs revision since the apps it was waiting on already exist.

## 12. Decision log

| Date | Decision | Rationale |
|---|---|---|
| 2026-04-17 | **NetBox is authoritative SoT**; discovery tools write to NetBox *staging* only, never active | Prevents dual-source-of-truth drift; matches existing ZTP proposal pattern |
| 2026-04-17 | **LibreNMS moved out of base** to `modules/infra-monitoring/` | Too heavy for flypack; duplicates Prometheus TSDB; not needed for media device discovery |
| 2026-04-17 | **Three-lane discovery** — LibreNMS/Netdisco (infra topology), Prometheus SNMP Exporter (infra metrics), nmos-cpp (media) | Eliminates TSDB duplication; gives media devices their own discovery path |
| 2026-04-17 | **Authentik as single IdP**, deployed once in `central-services/`; all clusters federate | Consistent operator identity; single revocation; ~1 GB tax paid once; supersedes earlier Keycloak proposal and pocket-id experiments |
| 2026-04-17 | **OpenBao scope expanded** — KV + PKI + SSH + K8s auth + OIDC auth + AppRole | PKI and SSH engines are production-grade and currently idle; needed for NMOS IS-10, mTLS, and operator device access |
| 2026-04-17 | **oauth2-proxy with long session TTL** for flypack offline authn | Covers 95% of field cases (days-offline); avoids per-flypack Authentik |
| 2026-04-17 | **external-secrets-operator** is base-fixed (not a slot) | One secrets-injection mechanism; reads from OpenBao central; cached k8s Secrets survive offline |
| 2026-04-17 | **Two flypack sub-profiles** — `standalone-ephemeral` (local-path) and `standalone-scalable` (Longhorn @ replica 1) | Separates throwaway-after-event from field-scalable use cases |
| 2026-04-17 | **ArgoCD deferred to `modules/advanced/`** | Promise-ware until cluster state is Git-modeled as Helm charts; AWX carries commissioning first |
| 2026-04-17 | **Two change-control lanes** — config (PR-gated) and operations (direct, audited) | PR gating is wrong for runtime routing; operators will bypass if forced |
| 2026-04-17 | **Five repos** — `dmf-infra`, `dmf-media`, `dmf-central`, `dmf-env`, `dmf-cms` | Splits map to real boundaries (topology, tech stack, env, build artifact); retrofitting repo splits later is expensive |
| 2026-04-17 | **Decision A — `dmf-central` separate repo** (not a profile inside `dmf-infra`) | Different topology, cadence, failure domain; avoid conflating "deploy a cluster" with "deploy central" |
| 2026-04-17 | **Decision B — `dmf-cms` separate repo** (not a `dmf-media` module) | Web app, not IaC; different CI, different tests, orchestrates more than media |
| 2026-04-17 | **Decision C — `dmf-env` multi-env** (not N repos) | Simpler, matches existing `inventories/` pattern; secrets isolation at OpenBao layer |
| 2026-04-17 | **Decision D — Helm charts extracted to `charts/`** (not embedded in Ansible roles) | Enables chart versioning and ArgoCD adoption without rewrite |
| 2026-04-17 | **Container registry in `central-services/`** (Harbor or Zot, choice deferred) | Non-negotiable for broadcast; pattern (pinned digests, signed, proxy-cache, flypack-local pull-through) is the invariant |
| 2026-04-17 | **Images pinned by digest, not tag**; custom images **cosign-signed**; admission webhook enforces | Reproducibility and supply-chain integrity required for production broadcast |
| 2026-04-17 | **Hub-cluster-first deployment topology** — initial build is one self-contained cluster acting as both stack host and central-services hub; federation deferred until Stage 4 (flypack) | De-risks the stack; federation introduces problems best solved against a proven base; a self-contained cluster *is* the flypack pattern, so this doubles as flypack proof-of-concept |
| 2026-04-17 | **Central services addressed by external-looking URLs from day 1** (`auth.<cluster>`, `vault.<cluster>`, `registry.<cluster>`) even when same-cluster | Adding a second cluster later becomes a deployment act, not a refactor; no app code changes when federation activates |
| 2026-04-17 | **Flypack default sub-profile = `standalone-scalable`** (Longhorn @ replica 1, days-offline, field-reusable) | Covers OB trucks, venue kits, remote deployments; `standalone-ephemeral` (local-path) is opt-in only |
| 2026-04-17 | **CMS tech stack = FastAPI + HTMX + WebSockets** (Python) | Strongest client-library ecosystem (pynetbox, awxkit, NMOS, Prometheus); single-process deploy; strongest AI-coding support |
| 2026-04-17 | **Registry: Harbor at hub, Zot on flypack** | Harbor's RBAC/scanning maturity at ingest; Zot's 50 MB footprint at edge; use each where it fits |
| 2026-04-17 | **cert-manager issuers** — `openbao-pki` default for internal; `letsencrypt-prod` for public endpoints; `selfsigned-fallback` for bootstrap only | OpenBao PKI root distributed to operator devices makes `.dmf.local` trusted; Let's Encrypt only for genuinely external URLs |
| 2026-04-17 | **Admission policy** — enforce signed-only for custom images day 1; warn-only for proxy-cached upstream; block direct-internet pulls on prod | Strict where cheap to enforce; pragmatic where upstream reality requires |
| 2026-04-17 | **Ingress dispatch abstracted** — `cluster_ingress_provider_tasks` in env group_vars, no vendor code in generic repo | Keeps `dmf-infra` cloud-agnostic; Hetzner CCM lives in `dmf-env/tasks/hetzner_ccm.yml` |
| 2026-04-17 | **Let's Encrypt for `dmf.example.com`** — HTTP-01 challenge, cert-manager TLSStore default, auto-renewal | Public domain with DNS A record to Hetzner LB; Traefik serves valid cert via TLSv1.3 |
| 2026-04-17 | **cert-manager CRDs installed from upstream manifest** before Helm install | Helm post-install hook fails on first install (webhook-CRD chicken-and-egg); direct manifest apply is reliable |
| 2026-04-17 | **Longhorn replica count = 2** on 3-node cluster | Survives one node loss; leaves one node free for maintenance |
| 2026-04-17 | **Federation model = hybrid by data type** — device inventory pulls from central; routing/flow/audit pushes to central | Device adds happen at base, routing actions happen in field; clear per-type boundary keeps conflict resolution simple |
| 2026-04-17 | **Stage 0 repo reorg — structural work complete on branches** (commits `03157d7`, `0d20f03`, `b1fdf24`, `4227ac1`) | 13 roles relayered, 14 stubs created, multi-env pattern live, 3 new repos scaffolded and pushed; vendor code removed from generic repo; Let's Encrypt TLS live on Hetzner; remaining: platform playbooks, merge reorg branches |
| 2026-04-20 | **Operator stack live on Hetzner** — NetBox, AWX, Grafana, Prometheus, Loki, OpenBao, ESO, Authentik, Forgejo, landing page all running (60+ pods, 13 namespaces) | Apps deployed via IngressRoute `PathPrefix()` routing (except Authentik/Forgejo on `Host()`); HTTP-01 cert with 3 SANs; no private lane, no wg3 |
| 2026-04-20 | **Planning doc consolidation** — 8 superseded docs archived into `Projects/Archive/`; 5 active docs remain | Reduces triangulation cost for future sessions; Archive/INDEX.md preserves lineage |
| 2026-04-20 | **Reorg branches diverge from `main`** — operational work (TLS SANs, Forgejo host-root, Authentik blueprints, OpenBao vertical-security rollout, app deployments) landed on `main` after branch point | Branches need rebasing before merge; merging as-is would undo live work |
