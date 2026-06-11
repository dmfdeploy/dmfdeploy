# DMF Open Questions — 2026-04-20

> **Vocabulary aligned 2026-04-25** with the EBU *Dynamic Media Facility Reference
> Architecture* White Paper V2.0. See `DMF EBU Mapping (2026-04-25).md` for the
> canonical layer / vertical / lifecycle map.

> **Status:** All 7 questions answered + 2 new findings documented. 2026-04-20.

## Post-rebuild reconciliation — 2026-04-24

The 2026-04-22 rebuild + Wave 2+ cutover invalidated most of the 2026-04-20
live-state findings below. Current state:

- **Finding 2 (apex-plus-path routing)** — **CLOSED.** All 7 apps
  (`auth`, `awx`, `forgejo`, `grafana`, `librenms`, `netbox`,
  `registry`) are host-root on `*.dmf.example.com`. Verified via
  `https://dmf.example.com/apps.json` on 2026-04-24.
- **Finding 3 (no private lane)** — **CLOSED.** Tailscale + socat +
  secondary Traefik on NodePort 30443 shipped. Node-01 on tailnet.
- **Finding 4 (HTTP-01, 3 SANs)** — **CLOSED.** DNS-01 wildcard issuer
  with Cloudflare now issues `*.dmf.example.com`.
- **Orchestrator / numbering (action items #10, #12)** — **CLOSED
  2026-04-25** by EBU realignment. Old `site.yml` + 9-phase wrappers
  (commit `d21dde6`) are superseded by `lifecycle-provision.yml` /
  `lifecycle-operate.yml` / `lifecycle-finalise.yml` plus the
  layer/vertical playbook tree. See `DMF EBU Mapping (2026-04-25).md`
  for old↔new identity table.
- **Alertmanager raw JSON to ntfy** — **CLOSED.** Formatter bridge
  `ntfy_bridge.py.j2` shipped (infra `048e8bb`, 2026-04-23).

### Still OPEN (carried forward)

- **Reorg branches** (`reorg/layered-structure`, `reorg/multi-env-docs`)
  need rebase onto `main` or per-commit reapplication. Both still exist
  locally and on origin.
- **Hetzner Leakage Audit** (below, items 1–10) — no commits address.
- **OpenBao AppRole `secret_id` TTL=0** — flagged in Pre-Rebuild
  Critical Review §2.2. Rotation still pending.
- **Longhorn BackupTarget** — missing; DR drill flagged as deferred debt.

### Finding 1 ("operator stack is much further along")

Still true, and even more so after the rebuild — full integration wave
(Authentik OIDC for Forgejo/AWX/NetBox/Grafana/LibreNMS, shared admin
group, WebAuthn ops user) landed on 2026-04-23. See Todo.md Review for
`2026-04-23 DMF Authentik Integration Wave + Alerting Repair`.

---

## Repo & Merge Status
1. ~~**Repo merge delay:** The reorg branches (`reorg/layered-structure` in `dmf-infra`, `reorg/multi-env-docs` in `dmf-env`) are ready but not merged. Is there a reason for the delay, or should these be merged now?~~
   **RESOLVED:** Both branches diverge from `main`. Operational work (TLS SANs, Forgejo host-root, Authentik blueprints, OpenBao under vertical-security, and — critically — the deployment of NetBox, AWX, Grafana, Prometheus, Loki) landed on `main` *after* the reorg branches were cut. Merging as-is would undo live work. Branches need rebasing onto `main` before merge, or the structural moves should be reapplied as small commits on `main` and the branches deleted.

## Private Lane Foundation
2. ~~**wg3 WireGuard tunnel:** The session handoff mentions wg3 as the private access mechanism. Is the wg3 role already implemented in the repo, or is that still pending?~~
   **RESOLVED: NOT IMPLEMENTED.** No `wireguard-peer` role, no `wg3` references in any repo file, no WG interfaces on any node (verified live: `ip link show | grep wg` returns nothing). wg3 is purely a planned feature from the Session Handoff Layer 3 (Container Platform) ingress work.

3. ~~**Private Traefik instance:** Is the `traefik-private` deployment in `traefik-private` namespace already set up, or is that part of the pending Layer 3 (Container Platform) ingress work?~~
   **RESOLVED: NOT DEPLOYED.** No `traefik-private` namespace, no second Traefik instance. Only one Traefik runs in `kube-system` (LoadBalancer, <lb-public-ip>). This is pure Layer 3 ingress pending work.

4. ~~**DNS-01 wildcard cert:** The plan mentions `cert-manager-webhook-hetzner` for `*.dmf.example.com`. Is this deployed, or is it part of the foundation work?~~
   **RESOLVED: NOT DEPLOYED.** Current issuer is `letsencrypt-http` (HTTP-01 only). Certificate `cluster-tls` (secret `lab-<lan-host>-tls`) covers 3 SANs: `dmf.example.com`, `auth.dmf.example.com`, `forgejo.dmf.example.com`. No DNS-01 infrastructure, no `cert-manager-webhook-hetzner`, no Hetzner DNS API token in OpenBao. Wildcard cert is Layer 3 (Container Platform) TLS pending work.

## App-Specific Decisions
5. ~~**LibreNMS status:** The docs mention LibreNMS required complex nginx rewrite proxies for path-based routing. Is the plan still to decommission it or move it to the private lane?~~
   **RESOLVED: NOT DEPLOYED ON LIVE CLUSTER.** LibreNMS pods do not exist in any namespace. It was deployed during earlier bootstrap attempts but is not currently running. The Platform Plan already classifies it under vertical-monitoring (`modules/infra-monitoring/`, optional). No active decision needed — it simply isn't here.

6. ~~**dmf-cms spec:** The CMS is mentioned as "FastAPI + HTMX + WebSockets" but the Layer 6 CMS skeleton hasn't started. Is there a separate spec for this, or should it be designed from scratch?~~
   **RESOLVED: SCAFFOLD ONLY.** `~/repos/dmf-cms` contains only placeholder Dockerfile, empty Helm chart skeleton, and `src/.gitkeep`. No tech stack chosen, no spec written. This is a Layer 6 (Application & UI) item to be picked up after the core operator stack stabilises.

## Operational Access
7. ~~**Current cluster access:** Can you currently access the Hetzner Cluster (via kubectl, SSH to Hosts), or do credentials/endpoint info need to be located first?~~
   **RESOLVED: FULLY ACCESSIBLE.** SSH via `k3s-admin@<control-node-public-ip>` works. `kubectl` works from node-01. OpenBao AppRole credentials functional (macOS keychain stores secret_id). Break-glass JSON at `<secure-store>/openbao-breakglass/hetzner-lab/openbao-keys.json`. Helper script `dmf-env/bin/get-admin-cred.sh` works.

---

## NEW FINDINGS (from live system inspection 2026-04-20)

### Finding 1: The operator stack is much further along than docs claim

The Session Handoff and Platform Plan describe NetBox, AWX, Grafana, Prometheus, and Loki as **"not deployed"** or pending. **They are all live and healthy:**

| Workload | Namespace | Status | Routing |
|---|---|---|---|
| Authentik | `authentik` | 3 pods (server, worker, postgres) | Host: `auth.dmf.example.com` |
| Forgejo | `forgejo` | 1 pod | Host: `forgejo.dmf.example.com` (Ingress) |
| NetBox | `netbox` | 4 pods (+ postgres, valkey, housekeeping) | Path: `/netbox` (IngressRoute) |
| AWX | `awx` | 4 pods (+ postgres, operator, migration) | Path: `/awx` (IngressRoute) |
| Grafana | `monitoring` | 1 pod | Path: `/grafana` (IngressRoute) |
| Prometheus | `monitoring` | 2 pods (+ node-exporter ×3, kube-state) | Path: `/prometheus` (IngressRoute) |
| Loki | `monitoring` | 5 pods (+ canary ×3, gateway, promtail ×3) | Path: `/loki` (IngressRoute) |
| OpenBao | `openbao` | 1 pod | In-cluster only (not exposed) |
| External Secrets | `external-secrets` | 3 pods | N/A |
| Landing page | `default` | 1 pod | Path: `/` (IngressRoute) |

**This means the "hub-cluster-first" self-contained operator stack is largely
built** — well ahead of the Layer 2 → Layer 3 → Layer 6 rollout timeline the
docs describe.

### Finding 2: All routing is still apex-plus-path (except Authentik and Forgejo)

Every IngressRoute on the live cluster uses `PathPrefix()`:
- `PathPrefix(\`/netbox\`)` (+ `/netbox/static` with StripPrefix middleware)
- `PathPrefix(\`/awx\`)` (+ redirect + strip-prefix middleware)
- `PathPrefix(\`/grafana\`)`
- `PathPrefix(\`/prometheus\`)`
- `PathPrefix(\`/loki\`)` (+ `/loki/ready` priority route)
- Landing page: `Path(\`/\`)` etc. on `dmf.example.com`

Only two apps use `Host()` routing:
- Authentik: `Host(\`auth.dmf.example.com\`)`
- Forgejo: standard Ingress with host `forgejo.dmf.example.com`

### Finding 3: No private lane exists at all

- Zero WireGuard interfaces on any Host
- Zero private Traefik instances
- All apps reachable from the public internet through one Traefik (<lb-public-ip>)
- The Session Handoff's entire two-lane ingress cutover (Layer 3 Container
  Platform work) is still pending

### Finding 4: Certificate is still HTTP-01, 3 SANs

Current cert (`lab-<lan-host>-tls`):
- Issuer: `letsencrypt-http` (HTTP-01)
- SANs: `dmf.example.com`, `auth.dmf.example.com`, `forgejo.dmf.example.com`
- No wildcard, no DNS-01, no per-app certs for NetBox/AWX/Grafana/etc.

## Hetzner Leakage Audit — dmf-infra (2026-04-20)

### Verdict: **LEAKS FOUND — requires cleanup before public release**

The `dmf-infra` repo on `main` is mostly clean in code (roles, playbooks, defaults), but **docs and example inventory contain significant Hetzner-specific content** that violates the "no cloud-provider coupling" doctrine.

### Classification by Severity

#### LEAK (must fix before public)

| # | File | Issue | Fix |
|---|------|-------|-----|
| 1 | `docs/repo-strategy.md` | Entire document is Hetzner-centric — Hetzner ARM64 provisioning, `hcloud` CLI commands, floating IPs, CAX21 node specs, `hetzner-arm` inventory name | Rewrite as generic cloud-agnostic guide, or move to `dmf-env` |
| 2 | `docs/hardening.md` | Layer 1 (Infrastructure) table says "Hetzner Cloud Firewall (`k3s-nodes`)", includes `--tags hetzner_firewall` instructions | Replace with generic "cloud firewall" concept; provider-specific doc belongs in `dmf-env` |
| 3 | `docs/netbox-deployment-notes.md` | "Hetzner rollout notes" section, "against the Hetzner LB IP" references | Keep as historical log but replace "Hetzner LB IP" with `<load-balancer-IP>` |
| 4 | `inventories/example/group_vars/all/main.yml` | Comment: "For Hetzner private networks this is usually `enp7s0`" | Change to "For cloud private networks the interface varies by provider" |
| 5 | `inventories/example/hosts.ini` | Comment: "For Hetzner/cloud VPS: ansible_host = public IP" | Rephrase generically: "For cloud/VPS: ..." |

#### QUESTIONABLE (should review)

| # | File | Issue | Assessment |
|---|------|-------|------------|
| 6 | `README.md` | "Tested on Hetzner CAX21 (ARM64 / Ampere Altra)" | Acceptable as a test matrix note, but could be generalized to "ARM64 (e.g. Hetzner CAX21)" |
| 7 | `roles/base/ingress/defaults/main.yml` | Comment: "Example: `.../tasks/hetzner_ccm.yml`" | Example-only, but should use generic name like `cloud_ccm.yml` |
| 8 | `roles/base/ingress/README.md` | Same `hetzner_ccm.yml` example | Same fix — change example to generic name |
| 9 | `playbooks/vertical-orchestration/100-eso.yml` | Comment: "For Hetzner lab this is set in inventories/hetzner-arm/group_vars/all/eso.yml" | Change to "For your environment, set this in the inventory group_vars" |
| 10 | `playbooks/210-harden.yml` | Comment mentions `hetzner_firewall.yml` as example | Change to `cloud_firewall.yml` |

#### CLEAN (acceptable generic reference)

| # | File | Issue | Assessment |
|---|------|-------|------------|
| 11 | `roles/stack/operator/openbao/tasks/main.yml` | Comment: "Save all keys to a local file (Hetzner validation mode)" | Minor comment, functionally generic — the code itself has no Hetzner dependency |
| 12 | `docs/awx-integration-plan.md` | References "DMF Hetzner cluster" as historical context | Historical doc, acceptable |
| 13 | `docs/netbox-token-journey.md` | References "live DMF Hetzner deployment" | Historical doc, acceptable |

### Correct Placement (in dmf-env)

The following files in `dmf-env` are **correctly placed** — this is where Hetzner-specific config belongs:

- `inventories/hetzner-arm/hosts.ini` — real Host IPs ✓
- `inventories/hetzner-arm/group_vars/all/main.yml` — Hetzner-specific VIPs, interfaces ✓
- `inventories/hetzner-arm/group_vars/all/eso.yml` — Hetzner-specific ESO config ✓
- `tasks/hetzner_ccm.yml` — Hetzner CCM installation task ✓
- `tasks/hetzner_firewall.yml` — Hetzner cloud firewall task ✓
- `templates/hcloud_firewall_rules.json.j2` — Hetzner firewall rules template ✓
- `docs/hetzner-provisioning.md` — Hetzner provisioning guide ✓

### Summary of Required Fixes in dmf-infra

1. **`docs/repo-strategy.md`** — Heaviest offender (~140 lines of Hetzner-specific content). Should be rewritten as a generic cloud-agnostic document. All `hcloud` CLI commands, CAX21 specs, floating IP instructions, and `hetzner-arm` references should either be generalized or moved to `dmf-env/docs/`.

2. **`docs/hardening.md`** — Replace "Hetzner Cloud Firewall" with generic "Cloud firewall (provider-specific)". Remove the `--tags hetzner_firewall` example. The hardening doc should describe the concept, not the implementation.

3. **`docs/netbox-deployment-notes.md`** — Replace "Hetzner LB IP" and "Hetzner ARM cluster" with generic equivalents. This is a deployment log, so historical context is fine but vendor names should be abstracted.

4. **`playbooks/` comments** — 3 playbooks have "Hetzner lab" comments. Replace with generic "your environment" language.

5. **`roles/base/ingress/` comments** — Change `hetzner_ccm.yml` example to `cloud_ccm.yml`.

6. **`inventories/example/` comments** — Remove Hetzner-specific interface name guidance.

7. **`README.md`** — Optional: soften "Hetzner CAX21" to "tested on Hetzner CAX21 and x86_64 VMs" → "tested on ARM64 (e.g. Hetzner CAX21) and x86_64 VMs".

### Reorg Branch Note

The `reorg/layered-structure` branch **deletes 3,374 lines** (removing Authentik, OpenBao, ESO, Zot, and standalone roles) while keeping only 144 lines of additions. This is consistent with the Platform Plan's doctrine that central vertical-security services (Authentik, OpenBao, ESO) should move to `dmf-central`, and Layer 6 app-specific roles (Zot) should move to `dmf-media`. The reorg branch should also apply the Hetzner cleanup above.

---

## NEW Open Items — EBU Realignment 2026-04-25

The 2026-04-25 vocabulary alignment with the EBU *Dynamic Media Facility
Reference Architecture* White Paper V2.0 surfaces several concepts that have
no concrete homelab implementation yet. See
`DMF EBU Mapping (2026-04-25).md` for the canonical layer / vertical /
lifecycle map.

### EBU-1: Flow Domains modelling (Layer 4 — Media Exchange)

EBU §Media Exchange introduces **Flow Domains** as the unit grouping
high-performance media flows between Media Functions (MXL SDK / RDMA /
shared-memory). The homelab has no Flow Domain model in NetBox, no schema in
the Resource Profile manifest, and no playbook coverage. Open until Layer 4
work begins (`dmf-media/playbooks/4xx-*.yml` skeleton exists but is
empty).

**Decisions needed:**
- NetBox custom field / object type for Flow Domains
- Resource Profile manifest fields (peer Hosts, transport, MXL params)
- Discovery vs declarative provisioning policy

### EBU-2: Multi-cluster Container Orchestration

EBU flags multi-cluster Container Platform orchestration as "subject to
further study". The homelab plan calls for a central Cluster (`dmf-central`)
federating site Clusters (`dmf-infra` deployments) but no concrete
multi-cluster orchestration tool is chosen. ArgoCD is the leading candidate
under `roles/modules/advanced/` (vertical-orchestration extension).

**Decisions needed:**
- ArgoCD vs Fleet vs alternative
- Bootstrap order: central first, then sites pull, or push from central?
- How federated identity (Authentik upstream OIDC) interacts with cluster
  federation

### EBU-3: Resource Profile manifest schema

The Deployment Workflow doc describes the manifest as the EBU "Design"
lifecycle output — a **Resource Profile**.

**Partial progress 2026-04-26:** First concrete manifest landed at
`dmf-env/manifests/hetzner-arm.yaml` (dmf-env commit pending).
Schema spans 13 spec sub-sections (resource_profile, topology, provider,
domain, network, secrets, apps, monitoring, orchestration, control,
storage, media_exchange, media_functions). YAML validates. Companion
`manifests/README.md` documents schema → EBU mapping and the secret-ref
URL convention `openbao:<path>#<field>`. Status: manifest is the source
of truth for environment intent; `inventories/<env>/` is currently
hand-maintained alongside it.

**Still open:**

- Which compute / network / storage / licence axes are mandatory vs optional
  (current schema is descriptive, not enforced)
- How verticals are declared once more facilities exist (the hetzner-arm
  manifest uses per-layer enable flags + cross-cutting vertical sections;
  consistency across future Profiles needs a stronger pattern)
- How Layer 4 / Layer 5 fields slot in once `dmf-media` activates
  (placeholders `media_exchange` / `media_functions` exist with
  `enabled: false`)
- Versioning / migration strategy as the schema evolves
  (`apiVersion: dmf.<lan-host>/v1alpha1` is provisional, not a CRD)
- Codegen from manifest into `inventories/<env>/` — currently manual,
  drift risk grows as more environments land

### EBU-4: JT-DMF tracking

The white paper references the **Joint Task Force on DMF (JT-DMF)** for
industry alignment. The homelab has no formal mechanism to track JT-DMF
publications, conformance markers, or test-suite alignment. Open items:

- Subscription / monitoring channel for JT-DMF outputs
- Resource Profile compliance markers field
- Mapping between JT-DMF published profiles and homelab Profiles
  (Flypack / Site / Cloud)

### EBU-5: Lifecycle wrapper structure

**CLOSED 2026-04-25.** Implemented by dmf-infra commits `5c970c4`
(rename + new lifecycle wrappers) and `5595a46` (site.yml rewrite +
internal-comment fixes + roles/README.md). Old `phase[0-8]-*.yml`
wrappers deleted; replaced by `lifecycle-provision.yml`,
`lifecycle-operate.yml`, `lifecycle-finalise.yml`. Tag scheme rewritten:
`phase{N}` → `layer{N}` / `vertical-*` / `lifecycle-*`. Verified with
`ansible-playbook --syntax-check`. Companion commits: `ec0b95c`
(dmf-central), `86c8a89` (dmf-media Layer 4/5 skeleton), `1c5a899`
(dmf-env DEPLOYMENT.md + run-playbook.sh timeout case).
