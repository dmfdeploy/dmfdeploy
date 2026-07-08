# DMF EBU Reference-Architecture Mapping (2026-04-25)

Single-page lookup that aligns the homelab DMF rollout with the EBU
*Dynamic Media Facility Reference Architecture* White Paper V2.0
(EBU TC, 2026-04-15). All other DMF docs defer to this one for
vocabulary, layer/vertical/lifecycle naming, and old↔new playbook
identity.

White paper: `~/Downloads/EBU_White_Paper_The_Dynamic_Media_Facility_Reference_Architecture.pdf`

---

## EBU model (canonical, V2.0)

### 6 horizontal layers (white paper Figure 2, p.5)

| # | Layer              | EBU scope (white paper section)                                |
|---|--------------------|----------------------------------------------------------------|
| 1 | Infrastructure     | Compute, network, storage, timing reference (PTP/NTP/SyncE) — §Infrastructure p.7 |
| 2 | Host Platform      | OS, hardening, kernel-bypass; **Cluster** of **Hosts** — §Host Platform p.9 |
| 3 | Container Platform | Container engine, networking, orchestration (k8s/k3s) — §Container Platform p.11 |
| 4 | Media Exchange     | High-perf shared-memory/RDMA exchange between Media Functions; MXL SDK — §Media Exchange p.14 |
| 5 | Media Functions    | Containerised media processing units — §Media Functions p.18 |
| 6 | Application & UI   | User-facing apps, control surfaces — §Application & UI p.21 |

Generic (blue) = layers 1–3, vendor-agnostic IT.
Industry-specific (green) = layers 4–6, broadcast/media.

### 4 verticals (white paper Figure 3, p.6) — cross-cutting, apply to every layer

- **Orchestration** — IaC; create/destroy/configure resources at each layer
- **Control** — operate-time control surfaces
- **Monitoring** — telemetry, alerts, analysis
- **Security** — zero-trust: AAA, least-privilege, segmentation, continuous monitoring (EBU R 160)

### 6-stage Media Workload lifecycle (white paper Figure 1, p.3)

Design → Plan → Provision → Configure → Operate → Finalise & Review
(+ continuous **Monitor & Update**)

---

## Homelab repo → EBU scope

| Repo | EBU scope owned |
|---|---|
| `~/repos/dmf-infra/k3s-lab-bootstrap/` | Layers 2 (Host Platform), 3 (Container Platform), 6 (Application & UI) + verticals (Security, Monitoring, Orchestration, Control) |
| `~/repos/dmf-env/` | Inventories + Resource Profile manifests (EBU "Design" lifecycle output) at `manifests/<env>.yaml`. First manifest: `manifests/hetzner-arm.yaml` (2026-04-26). Inventory under `inventories/<env>/` is currently maintained by hand alongside the manifest; codegen TBD per Open Questions §EBU-3. No playbooks/roles. |
| `~/repos/dmf-central/` | vertical-security artifacts deployed to a federated central Cluster (Authentik, OpenBao, Harbor/Zot) |
| `~/repos/dmf-media/` | Layers 4 (Media Exchange), 5 (Media Functions) — currently reserved skeleton |
| `~/repos/dmf-cms/` | Layer 6 artifact (operator UI) — consumed by `dmf-infra/playbooks/650-dmf-cms.yml` |

---

## Vocabulary canon

Active homelab docs adopt EBU terms verbatim. Old terms retained only as
historical artifacts in the operator note store archive.

| EBU term (canonical) | Old homelab term | Notes |
|---|---|---|
| Layer (1–6) | Phase (0–9) | "Phase" survives only as informal rollout-order ordinal in chat |
| Vertical (Orchestration, Control, Monitoring, Security) | (was conflated into Phase 4/5) | Cross-cutting; not a numbered layer |
| Lifecycle stage (Design / Plan / Provision / Configure / Operate / Finalise & Review) | (was conflated into Phase 8/9) | Time axis, runs across layers |
| Cluster | k3s cluster, lab cluster | EBU §Host Platform §Cluster |
| Host | node | EBU treats Kubernetes "Node" as a Host |
| Container | pod content | EBU treats Kubernetes "Pod" as a group of Containers |
| Media Workload | (was "stack" loosely) | Assembly of Media Functions for a production (EBU Fig B1). **NB:** the console's "Media Workloads" page currently lists Media *Function* instances (ADR-0037 modelled the inventory and deferred the assembly); a first-class Media Workload entity — membership by NetBox tag `workload:<name>`, first example `videotest` = `mxl-videotestsrc` + `mxl-videotest-view` — is tracked in the Media Workload RFC. |
| Media Function | media app, media service | Containerised processing unit. Layer-5; classified by Layer + a media-function type/role — **not** by one of the four control-plane verticals (Orchestration/Control/Monitoring/Security). |
| Resource Profile | (no equivalent) | EBU "Design" stage output: compute/network/storage/licence requirements |
| Facility Orchestration | site.yml + run-playbook.sh | The whole control envelope |
| Flow / Flow Domain | (no equivalent yet) | EBU §Media Exchange concept; deferred until layer 4 work |

Homelab-specific terms with no EBU equivalent (kept):
- **Lane** — ingress topology choice (public / private / airgapped). Deployment-shape, orthogonal to EBU model.
- **Profile** — facility footprint (Flypack / Site / Cloud). Compatible with EBU; refers to scale, not architecture.
- **Manifest** — non-secret deployment intent doc; matches EBU "Design" lifecycle output.

---

## Playbook old→new mapping (dmf-infra)

### Layer 2xx — Host Platform
| Old | New |
|---|---|
| `playbooks/00-verify-environment.yml` | `playbooks/219-host-verify.yml` |
| `playbooks/01-baseline.yml`            | `playbooks/200-baseline.yml` |
| `playbooks/02-harden.yml`              | `playbooks/210-harden.yml` |

### Layer 3xx — Container Platform
| Old | New |
|---|---|
| `playbooks/10-k3s.yml`             | `playbooks/300-k3s.yml` |
| `playbooks/11-k3s-verify.yml`      | `playbooks/301-k3s-verify.yml` |
| `playbooks/20-ingress-public.yml`  | `playbooks/310-ingress-public.yml` |
| `playbooks/21-ingress-private.yml` | `playbooks/311-ingress-private.yml` |
| `playbooks/22-cert-manager.yml`    | `playbooks/320-cert-manager.yml` |
| `playbooks/23-tailscale.yml`       | `playbooks/321-tailscale.yml` |
| `playbooks/30-longhorn.yml`        | `playbooks/330-longhorn.yml` |
| `playbooks/31-registry-zot.yml`    | `playbooks/331-registry-zot.yml` |
| `playbooks/29-network-verify.yml`  | `playbooks/339-container-platform-verify.yml` |

### Layer 6xx — Application & UI
| Old | New |
|---|---|
| `playbooks/32-landing-page.yml`      | `playbooks/600-landing-page.yml` |
| `playbooks/60-netbox.yml`            | `playbooks/610-netbox.yml` |
| `playbooks/61-forgejo.yml`           | `playbooks/620-forgejo.yml` |
| `playbooks/63-awx.yml`               | `playbooks/640-awx.yml` |
| (new) `playbooks/650-dmf-cms.yml`    | `playbooks/650-dmf-cms.yml` (placeholder for dmf-cms chart) |
| `playbooks/70-netbox-sot.yml`        | `playbooks/691-netbox-sot.yml` |
| `playbooks/71-forgejo-bootstrap.yml` | `playbooks/692-forgejo-bootstrap.yml` |
| `playbooks/72-awx-integration.yml`   | `playbooks/693-awx-integration.yml` |

### Vertical: Security
| Old | New |
|---|---|
| `playbooks/40-openbao.yml`                     | `playbooks/vertical-security/100-openbao.yml` |
| `playbooks/50-authentik.yml`                   | `playbooks/vertical-security/110-authentik.yml` |
| `playbooks/51-authentik-breakglass-verify.yml` | `playbooks/vertical-security/190-breakglass-verify.yml` |

### Vertical: Monitoring
| Old | New |
|---|---|
| `playbooks/45-prometheus.yml`        | `playbooks/vertical-monitoring/100-prometheus.yml` |
| `playbooks/46-loki.yml`              | `playbooks/vertical-monitoring/110-loki.yml` |
| `playbooks/47-grafana.yml`           | `playbooks/vertical-monitoring/120-grafana.yml` |
| `playbooks/48-promtail.yml`          | `playbooks/vertical-monitoring/130-promtail.yml` |
| `playbooks/62-librenms.yml`          | `playbooks/vertical-monitoring/140-librenms.yml` |
| `playbooks/49-monitoring-verify.yml` | `playbooks/vertical-monitoring/190-monitoring-verify.yml` |

### Vertical: Orchestration
| Old | New |
|---|---|
| `playbooks/41-eso.yml` | `playbooks/vertical-orchestration/100-eso.yml` |

### Vertical: Control
*(Documentation-only; runbooks for operate-time. No playbooks initially.)*

### Lifecycle wrappers (orchestrator entrypoints, repo root)
| Old | New | Calls |
|---|---|---|
| `phase0-host.yml` … `phase8-verify.yml` | *(deleted)* | superseded |
| (new) | `lifecycle-provision.yml` | imports layer 1xx → 2xx → 3xx → vertical-security + vertical-monitoring + vertical-orchestration → 4xx → 5xx → 6xx |
| `playbooks/80-stack-verify.yml` (top-level wrapper) | `lifecycle-operate.yml` | full-stack verify, DR drill, day-0 inventory |
| `playbooks/90-teardown.yml` | `lifecycle-finalise.yml` | teardown sequence (reverse order) |
| `site.yml` | `site.yml` (rewritten) | calls `lifecycle-provision.yml` |

### Tag scheme (replaces `phase{N}`)
- Layer tags: `layer1` … `layer6`
- Vertical tags: `vertical-security`, `vertical-monitoring`, `vertical-orchestration`, `vertical-control`
- Lifecycle tags: `lifecycle-provision`, `lifecycle-operate`, `lifecycle-finalise`
- Existing functional tags (`k3s`, `ingress`, `tls`, `monitoring`, `eso`, etc.) retained.

---

## Playbook new layout (dmf-central)

| Old | New |
|---|---|
| `playbooks/00-central-base.yml` | `playbooks/300-central-base.yml` |
| `playbooks/10-authentik.yml`    | `playbooks/vertical-security/110-authentik.yml` |
| `playbooks/20-openbao.yml`      | `playbooks/vertical-security/100-openbao.yml` |
| `playbooks/30-registry.yml`     | `playbooks/vertical-security/130-registry.yml` |

Central cluster bootstrap (300-central-base) walks layers 1–3 of an
isolated central Cluster; vertical-security playbooks then deploy the
shared services that all federated Clusters consume.

---

## Playbook new layout (dmf-media) — reserved skeleton

| New | Notes |
|---|---|
| `playbooks/400-mxl-prereq.yml`            | Layer 4 stub |
| `playbooks/410-libfabric.yml`             | Layer 4 stub |
| `playbooks/499-media-exchange-verify.yml` | Layer 4 stub |
| `playbooks/500-nmos-cpp.yml`              | Layer 5 — role exists |
| `playbooks/510-ebu-list.yml`              | Layer 5 stub |
| `playbooks/520-flow-exporters.yml`        | Layer 5 stub |
| `playbooks/530-ptp-monitor.yml`           | Layer 5 stub |
| `playbooks/540-netbox-media-plugin.yml`   | Layer 5 stub |
| `playbooks/599-media-functions-verify.yml`| Layer 5 stub |

Existing `playbooks/30-media-base.yml` retired in favour of the per-layer split.

---

## Role-directory mapping (no rename, just clarity)

`dmf-infra/k3s-lab-bootstrap/roles/`:
- `roles/base/*` → Layer 2 (k3s host prep, harden) + Layer 3 (k3s, ingress, cert-manager, longhorn, prometheus base) + verticals where applicable
- `roles/stack/operator/*` → Layer 6 (NetBox, Forgejo, AWX, CMS) + verticals (OpenBao, Authentik, Loki, oauth2-proxy)
- `roles/stack/standalone/*` → Layer 6 alternate (lighter app subset for Flypack)
- `roles/modules/infra-monitoring/*` → vertical-monitoring extension (LibreNMS et al.)
- `roles/modules/advanced/*` → vertical-orchestration extension (ArgoCD, federation)
- `roles/common/*` → utilities used across layers

`dmf-media/roles/`: all → Layer 4 or 5.

`dmf-central/roles/`: all → vertical-security (or its central-cluster Layer 3 base).

---

## Open items deferred to later work

- **Flow Domains** (EBU §Media Exchange) — modeling in NetBox + manifest schema.
- **Multi-cluster Container Orchestration** (EBU "subject to further study") — homelab has central + sites; revisit when ArgoCD lands.
- **Resource Profile schema** — concrete field list for the manifest; tracked in Open Questions doc.
- **MXL SDK integration** — github.com/dmf-mxl/mxl; deferred behind 4xx skeleton.
- **Joint Task Force on DMF (JT-DMF)** — referenced in white paper; track for industry alignment.
