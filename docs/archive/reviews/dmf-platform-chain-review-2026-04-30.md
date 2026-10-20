# Critical Review — `site.yml` Chain & DMF Layer Model

**Date:** 2026-04-30
**Scope:** `~/repos/dmf-infra/k3s-lab-bootstrap/site.yml` → `lifecycle-provision.yml` and the L6 app/integration/console chain
**Reviewer mode:** plan-eng-review (architectural & sequencing review)
**User-flagged concern:** "I see forgejo-svc user repos on Forgejo but nothing in NetBox yet"
**Goal:** absolute clarity on (i) vanilla infra/host/container rollout, (ii) born-inventory phase, (iii) dmf-cms phase, (iv) completeness

---

## Phase Diagram (what site.yml → lifecycle-provision.yml actually does)

```
PHASE 1: VANILLA INFRASTRUCTURE                  [order = layer-numeric]
─────────────────────────────────────
  L2 Host Platform
    219-host-verify     ★★★ pre-flight (real, 234 lines)
    200-baseline        ★★★ OS baseline
    210-harden          ★★★ host hardening

  L3 Container Platform
    300-k3s + 301-verify
    310-ingress-public + 311-ingress-private
    320-cert-manager + 321-tailscale
    330-longhorn
    331-registry-zot          (htpasswd-only, no OIDC yet)
    339-verify                ★    STUB — debug-only

  Vertical: Security
    vs/100-openbao
    vo/100-eso                (orchestration, but lives between security plays)
    vs/110-authentik
    vs/190-breakglass-verify  ★    STUB — debug-only

  Vertical: Monitoring
    100-prom → 110-loki → 120-grafana → 130-promtail
    140-librenms              (DISABLED in chain, commented out)
    190-monitoring-verify     ★★★ real, 188 lines

PHASE 2: BORN-INVENTORY (apps + integration)     [order != layer-numeric]
─────────────────────────────────────
  600-landing-page
  610-netbox
  620-forgejo
  640-awx
  691-netbox-sot         creates awx-svc, librenms-svc users in NetBox
  692-forgejo-bootstrap  creates forgejo-svc + repos in FORGEJO
  693-awx-integration    wires AWX → NetBox inv plugin, Forgejo SCM
  694-born-inventory     registers cluster NODES + LB into NetBox

PHASE 3: DMF CONSOLE                             [logical apex consumer]
─────────────────────────────────────
  650-dmf-cms            position 9 of 11 in L6, despite numeric prefix 650 < 691
  695-zot-oidc           tagged [layer3] but runs after L6 work
  696-cms-authentik-api  post-hoc API token wiring → console reload
```

---

## Critical Findings

### 1. The numbering lies about the actual order in Phase 2/3 *(confidence: 9/10)*

`lifecycle-provision.yml:78-99` imports L6 in this real order:

```
600 → 610 → 620 → 640 → 691 → 692 → 693 → 694 → 650 → 695 → 696
```

But `650-dmf-cms.yml` has number prefix 650, which sorts before 691/692/693/694. The numeric order says "console at position 5"; the actual import order says "console at position 9 of 11". Anyone reading by file numbers will guess wrong.

Also: `695-zot-oidc.yml:96` carries `tags: [layer3, container-platform, ...]` but is sequenced inside the L6 block. `--tags layer3` would skip it on a normal full run; `--tags layer6` would skip it on a re-run. Tag mismatch.

**Why it matters:** The numbering scheme is the documented mental model (DEPLOYMENT.md §5). When the model and reality diverge, every operator who follows the table picks the wrong rerun set during incidents.

**Fix options:**
- (A) Renumber to match reality: 650 → 695 (after 694), and rename the existing 695/696 layer-on plays to e.g. 696-zot-oidc, 697-cms-authentik-api.
- (B) Keep numbers, encode order in lifecycle-provision.yml only, and add a note "import order ≠ numeric order; see lifecycle-provision.yml".
- (C) Split the layer-on plays out into a `lifecycle-finalize-identity.yml` stage so the L6 block stays clean.

(A) is cleanest but renumber-churn. (C) is structurally most honest — they're a different lifecycle phase.

---

### 2. forgejo-svc exists in Forgejo, missing from NetBox *(confidence: 10/10 — verified)*

You flagged this. Confirmed:
- `roles/stack/operator/netbox-sot/tasks/main.yml:336-415` creates **awx-svc** and **librenms-svc** users in NetBox + tokens.
- `roles/stack/operator/forgejo-bootstrap/tasks/main.yml:128-160` creates **forgejo-svc** user in Forgejo only.
- No NetBox entry is ever created for forgejo-svc, even though the AWX integration depends on the Forgejo token.

But the deeper problem is **the service catalog is fragmented across four systems**:

| Knowledge | Lives in | Authoritative? |
|---|---|---|
| Hostnames / FQDNs | Ansible group_vars/all/main.yml | yes-ish |
| forgejo-svc account + token | Forgejo + vault.yml or OpenBao | yes |
| awx-svc, librenms-svc accounts | NetBox + Forgejo (no) + OpenBao | partial |
| Cluster nodes + LB | NetBox (via 694) | yes |
| The apps themselves (Forgejo, AWX, NetBox, Authentik, Grafana, Zot, Prometheus, Loki, dmf-cms run here) | **nowhere structured** | NO |
| App ingress routes / TLS | Traefik IngressRoute CRDs in cluster | yes (runtime) |
| App-contract for dmf-cms | static YAML fixture in dmf-cms repo | NO (snapshot) |

**The "DMF SoT" claim is currently false.** NetBox holds nodes, LB, and three svc users. It does not hold the apps that run on the cluster, their owners, their endpoints, or their dependencies. dmf-cms's app-contract is the closest thing to a service catalog but it's a static fixture, not a discovery output.

**Why it matters:** Move 2 from the strategic review (dmf-cms vertical slice → real AWX) will fail or produce hollow output if NetBox doesn't know about the AWX service to drive inventory from. You'll end up reshaping NetBox custom fields painfully later — exactly the interface-commitment risk flagged.

**Fix options:**
- (A) Extend `netbox-sot` to also create forgejo-svc as a NetBox user. Cheap consistency fix. Doesn't solve the catalog gap.
- (B) Extend `694-born-inventory` to register apps as NetBox `Service` objects (built-in NetBox `ipam.Service` model exists for this exact purpose), each linked to the cluster Device + tagged with owner/lifecycle/exposure. Closes the catalog gap. ~1-2 hr work in the same role.
- (C) Defer until after Move 2 reveals what the dmf-cms app-contract actually needs. Pragmatic — you're in experiment phase. Risk: AWX integration runs against an incomplete SoT.

Recommendation: **(B) inside Move 2's vertical slice**, not before. Closing the slice will reveal exactly what fields are needed; building the catalog blind right now is premature taxonomy.

---

### 3. "born-inventory" is misnamed — it's "born-cluster-inventory" *(confidence: 9/10)*

`694-born-inventory.yml` (and `roles/common/dmf-born-inventory/`) registers:
- DMF tag, tenant, site
- k3s cluster type, k3s cluster
- Platform (Debian)
- Device roles (control-plane, worker, load-balancer)
- Each k3s node as a NetBox VM
- Hetzner LB as a NetBox Device + interface + IP

It does **not** register:
- Any of the platform's L6 apps (NetBox, Forgejo, AWX, Authentik, Grafana, Prometheus, Loki, Zot, dmf-cms)
- Tailscale interfaces (only IPs, in node comments)
- Any Service / endpoint object
- Any cert / TLS state
- Any IngressRoute → backing service mapping

The DEPLOYMENT.md §1 design rule says **"Born inventoried — Deployment registers what it creates into NetBox."** That promise is half-kept.

**Why it matters:** This is the same root cause as #2. The "deployment registers what it creates" claim is the load-bearing axiom for Move 2 (dmf-cms reads NetBox SoT to understand the platform).

---

### 4. Verify gates are stubs at L3 and breakglass *(confidence: 10/10 — verified)*

- `playbooks/339-container-platform-verify.yml`: 21 lines, only a `debug:` task with intended-checks comment. Phase 1 closes without confirming wildcard cert is Ready, registry reachable, Longhorn StorageClass default, or LB healthy.
- `playbooks/vertical-security/190-breakglass-verify.yml`: 18 lines, debug-only. Vertical-security closes without confirming Authentik break-glass admin works.
- ESO has no verify play at all (no `vertical-orchestration/190-*-verify.yml`). Whether `ClusterSecretStore` is Valid is never asserted in the chain.

**Why it matters:** A green lifecycle-provision exit means "every play returned 0", not "the cluster works". The fix recipe in DEPLOYMENT.md §12 lists 11 manual checks because the verify chain doesn't cover them. That's a gap that will quietly ship broken state to dmf-cms.

**Fix:** Make the L3 verify real. ~1-2 hr. The check list is already inline in the stub. ESO + breakglass verify can wait until commit phase; L3 verify is in the critical path because dmf-cms depends on cert state and registry reachability.

---

### 5. The mode-toggle in *-bootstrap roles fails open *(confidence: 7/10)*

`forgejo-bootstrap`, `netbox-sot`, `awx-integration` all have:

```yaml
*_persist_to_openbao: >-
  {{ (openbao_url | default('') | length > 0)
     and (openbao_role_id | default('') | length > 0)
     and (openbao_secret_path | default('') | length > 0)
     and (openbao_keychain_service | default('') | length > 0)
     and (openbao_keychain_account | default('') | length > 0) }}
```

If any of those five vars is missing/empty, the role silently falls through to vault.yml + ansible-vault password file — the legacy path. There is no assert that **at least one** of the two paths is complete and consistent. Risk: env partially configured, role takes the wrong path, secrets land in the wrong store and create the "two long-lived stores for the same value" bug your `initial-data-gathering.md` §"Boundary rules" §3 explicitly forbids.

**Fix:** Add an assert at top: "exactly one of {OpenBao mode complete, vault mode complete} must be true; partial-OpenBao config is a misconfiguration." 5 min.

---

### 6. dmf-cms (the apex consumer) has no integration verify *(confidence: 8/10)*

650-dmf-cms.yml deploys the console. 696-cms-authentik-api.yml waits for the Deployment to be Ready (`readyReplicas >= 1`). Neither verifies that:
- The pod can reach NetBox at `https://netbox.<cluster-domain>`
- The pod can reach AWX at `https://awx.<cluster-domain>`
- The pod can reach Prometheus
- OIDC discovery succeeds against Authentik

**Why it matters:** Move 2 hinges on the console actually composing across three+ backends. Right now, "deployment Ready" is the only gate, which only confirms the container started and serves `/healthz`. The first user click reveals the integration breakage.

**Fix:** Add a post-deploy `kubectl exec` smoke that the pod can `curl -s` each backend's health endpoint and OIDC discovery URL. ~30 min. This becomes the gate for Move 2's commit gate.

---

### 7. Resource Profile manifest is documented but not runtime-consumed *(confidence: 8/10)*

Per `initial-data-gathering.md` §3, the workflow is:
1. Author `manifests/hetzner-arm.yaml` (Resource Profile, the EBU "Design" stage output)
2. Hand-render `inventories/hetzner-arm/...` to match
3. Ansible reads **inventory only**

There's no codegen (the doc admits "Codegen open — `manifests → inventories/` rendering is not yet automated"). There's no preflight that asserts manifest matches inventory. `219-host-verify.yml` reads the inventory, never the manifest.

So the Resource Profile is a *documented aspiration*, not a *load-bearing artifact*. The "initially collected variables" you asked about flow through `inventories/.../group_vars/all/main.yml` directly. The manifest is a forward-compat stub for the future wizard (Release 5 of dmf-cms).

**Why it matters:** Drift between manifest and inventory is silent. Any operator who edits one without the other introduces inconsistency. Worse, the chain claims "EBU Design stage output" provenance it doesn't actually honor.

**Fix options:**
- (A) Add a manifest-vs-inventory diff check to 219-host-verify (2-3 hr — needs YAML→Ansible-vars schema map). Clean, but premature if the manifest schema is still fluid.
- (B) Remove manifest references until codegen lands. Honest about current state.
- (C) Keep references but add a banner in `initial-data-gathering.md` §3 that the manifest is documentation-only until codegen lands, and the inventory is authoritative today.

Recommendation: **(C)** for now, **(A)** as part of the wizard work (Release 5).

---

### 8. librenms-svc is created in NetBox but LibreNMS is disabled in the chain *(confidence: 10/10 — verified)*

`lifecycle-provision.yml:64-67` comments out the LibreNMS playbook. But `roles/stack/operator/netbox-sot/tasks/main.yml:417-482` creates the `librenms-svc` user in NetBox with API token, and the `LibreNMS discovery sync` token is generated regardless.

Orphan service account. Not security-critical (the user has no LibreNMS to log into) but:
- Creates a NetBox user that is never used (audit noise)
- Generates and stores an unused token (lifecycle gap — when does it rotate? It doesn't.)
- Reveals that `netbox-sot` doesn't ask "is this app actually deployed?" before provisioning its identity

**Fix:** Gate librenms-svc creation on `librenms_enabled | default(false)` (or whatever lane-toggle exists). Same pattern should apply to awx-svc and forgejo-svc. 15 min.

---

## Sequencing Recommendation — Cleaner Phase Boundaries

Right now lifecycle-provision.yml has phases mashed together. A cleaner split that matches your actual mental model:

```
lifecycle-provision.yml (vanilla — bring the platform up)
  L2 host
  L3 container (incl 339-verify made real)
  vertical-security (openbao, eso, authentik, breakglass-verify)
  vertical-monitoring

lifecycle-bootstrap-apps.yml (NEW — born-inventory phase)
  L6 app deploys (600, 610, 620, 640)
  L6 integration (691, 692, 693)
  L6 inventory registration (694)

lifecycle-bootstrap-console.yml (NEW — apex consumer + identity layer-ons)
  650-dmf-cms
  695-zot-oidc
  696-cms-authentik-api
  + console-integration-verify (NEW — 30-min smoke)

site.yml (calls all three in order)
```

This makes your question — "vanilla / born-inventory / console" — visible in the directory structure, not just in someone's head.

**Effort:** 1-2 hr to split. Two new wrapper playbooks; site.yml grows from 1 import to 3.

**Why I'd recommend this only after Move 2 lands:** The phase boundaries become permanent commitments. Doing the split before validating Move 2 risks locking in boundaries you'll want to redraw (e.g., maybe identity layer-ons belong in vertical-security, not in console phase).

---

## Completeness Score

```
PHASE 1 (Vanilla):              7/10  — works, but L3+breakglass+ESO verify stubs
PHASE 2 (Born-inventory):       4/10  — registers nodes only; misses apps, services, mixed svc-user provisioning
PHASE 3 (DMF Console):          5/10  — deploys + auth wired, but no integration verify
Cross-cutting consistency:      4/10  — manifest aspirational; numbering vs ordering mismatch; mode toggle fails open
Service-catalog SoT integrity:  3/10  — fragmented across Forgejo + NetBox + AWX + dmf-cms-fixture; "born inventoried" claim half-kept
```

---

## Recommended Action Order (cheapest → most leveraged)

1. **5 min:** Add fail-closed assert to the OpenBao mode toggle in 3 roles. (#5)
2. **15 min:** Gate librenms-svc creation on `librenms_enabled`. (#8)
3. **30 min:** Add console-integration smoke (curl backends from inside dmf-cms pod). (#6) — gates Move 2.
4. **1-2 hr:** Make 339-container-platform-verify real. (#4) — gates Phase 1 trust.
5. **As part of Move 2 (per strategic review):** Extend 694-born-inventory to register L6 apps as NetBox `ipam.Service`, fix forgejo-svc gap. (#2, #3) — closes the SoT promise.
6. **Defer to commit phase:** Renumber/regroup playbooks (#1) and split lifecycle-provision into three wrappers. Premature now; locks in boundaries that Move 2 might still reshape.

---

## What's NOT in scope of this review

- The dmf-media playbooks (4xx/5xx). They're scaffolds; reviewing them is Move 1 territory.
- Helm chart contents for individual apps. The chain is the question, not the charts.
- The Terraform Layer-1 (Hetzner provisioning). Lives in dmf-env; out of the bootstrap chain proper.
- OpenBao Shamir/break-glass procedures. Reviewed in Secret Ownership plan separately.
- Whether the EBU V2.0 layer model itself is correct (Move 1's NMOS work will surface that).

---

## Single-line Verdict

**The chain works in the happy path. The four real problems are: (a) NetBox is not the SoT it claims to be — apps and one svc-user are missing; (b) two L3-area verify gates are stubs; (c) numbering ≠ ordering in Phase 2/3 confuses operators; (d) the apex consumer (dmf-cms) ships without an integration smoke.** Items (a) and (d) are blockers for Move 2; (b) and (c) are cleanup. Don't restructure until Move 2 has run — premature taxonomy locks in boundaries you'll want to redraw.

---

## Cross-reference

- Strategic review: `~/repos/dmf-platform-strategic-review-2026-04-30.md` (experiment-phase three-move recommendation)
- DMF Platform Plan: `~/repos/dmf-infra/k3s-lab-bootstrap/docs/dmf-platform-plan.md` (canonical architecture reference)
- Initial Data Gathering: `~/repos/dmf-env/docs/initial-data-gathering.md` (variable provenance, Resource Profile manifest)
- Deployment Runbook: `~/repos/dmf-env/DEPLOYMENT.md` (operator entry point)
