---
status: executed
date: 2026-05-14
---
# DMF Internal Service DNS Migration Survey

**Date:** 2026-05-14
**Author:** session-collaborative (Claude + operator)
**Status:** Plan + survey template — execution pending
**Related:** ADR-0023 (decision), `dmf-infra@3457513` (first application)

---

## 1. Context

ADR-0023 (2026-05-14) decided: **cross-app HTTP wiring uses cluster-internal
service DNS, not public URLs.** Today's `dmf-infra@3457513` applied this to
`698-cms-netbox-forgejo-tokens.yml` (8 defaults migrated). The decision is
sealed; this doc is the **migration plan** — survey the rest of the codebase,
classify each public-URL reference, and migrate the cross-app ones.

The principle in one line: *if a URL is consumed by another cluster pod,
it should default to `http://<svc>.<ns>.svc.cluster.local:<port>`. If a
URL is consumed by a browser or external system, it stays public.*

---

## 2. Method

Two passes:

### 2.1 Discovery (grep)

Find every URL default in `dmf-infra/k3s-lab-bootstrap/` that might be
cross-app wiring. The signal patterns:

```bash
# Placeholder domain references — almost certainly cross-app (or stale)
grep -rEn "https?://[^ ]*\.dmf\.example\.com" \
  dmf-infra/k3s-lab-bootstrap/{playbooks,roles}/

# Defaulted *_host or *_api_url references in `uri:` task contexts
grep -rEn "default\('https?://" \
  dmf-infra/k3s-lab-bootstrap/{playbooks,roles}/

# Cross-app pattern: role X talks to app Y
grep -rEn "url:.*\{\{.*(authentik|awx|netbox|forgejo|grafana|librenms|zot|cms)_(host|api|url)" \
  dmf-infra/k3s-lab-bootstrap/{playbooks,roles}/
```

### 2.2 Classification

Classify each hit on **two axes**: WHAT is being called, and WHERE the
caller runs.

**Axis 1 — what is being called (workload type):**

| Bin | Meaning | Action |
|---|---|---|
| **A — cross-app, migrate** | A pod calls another pod's API. Examples: dmf-cms → NetBox runtime API; NetBox worker → Forgejo for datasource sync. | Change default to internal service DNS (after Axis 2 check) |
| **B — user-facing, keep public** | URL rendered to a human or used as OIDC redirect/webhook callback. Examples: ingress URLs in landing page, OIDC `redirect_uris`. | Leave as-is |
| **C — env-supplied, OK** | Already derives from an env-defined `*_host` variable and works on this env. Example: `_cms_awx_api_base` in 697 uses `awx_host \| default(...)`. | If Axis 2 = control-node caller, this is already correct; leave alone. If Axis 2 = pod caller, optionally tighten to internal DNS for defense-in-depth (lower priority). |
| **D — unrelated** | Not a cross-app HTTP call (e.g. `external_base_url` for ingress configuration, OpenBao URLs, OIDC discovery endpoints). | Skip |

**Axis 2 — where the caller runs (added 2026-05-14 after run-11):**

| Caller location | Meaning | Constraint |
|---|---|---|
| **P — pod (in-cluster)** | The HTTP call originates from inside a pod at runtime — e.g. dmf-cms making API calls to NetBox; NetBox worker syncing from Forgejo; AWX inventory plugin querying NetBox at job time. | Internal service DNS is reachable. ADR-0023 fully applies. |
| **C — control-node ansible** | The HTTP call originates from `bin/run-playbook.sh` invoking an `ansible.builtin.uri:` task on the ansible target host (`k3s_control[0]`). DNS goes through the node's `/etc/resolv.conf`, NOT CoreDNS. | Internal `*.svc.cluster.local` is **unreachable** from here. Use public URL via `*_host` env var pattern (697's `awx_host \| default(...)` model). |
| **O — operator workstation** | Direct curl from the operator's machine. Off-cluster by definition. | Public URL. |

**Decision matrix** — given (workload type, caller location):

| (Axis 1, Axis 2) | Action |
|---|---|
| (A — cross-app, P — pod) | Migrate default to internal service DNS. ADR-0023 applies. |
| (A — cross-app, C — control-node ansible) | Use `*_host`-derivation pattern (public URL with env var). ADR-0023 future-direction applies once in-cluster runner pod lands. |
| (B — user-facing, any) | Keep public. |
| (C — env-supplied, any) | Already correct; leave alone. |
| (D — unrelated, any) | Skip. |

**Worked examples from session 2026-05-13/14:**

| Reference | Workload | Caller | Bin | Default chosen |
|---|---|---|---|---|
| `forgejo_internal_host` in netbox-sot role (sync URL stored on NetBox DataSource) | A — cross-app | P — consumed by NetBox worker pod at sync time | (A, P) | Internal DNS — `forgejo-http.forgejo.svc.cluster.local:3000` (`dmf-infra@07d0e00`) |
| `cms_netbox_api_url` in 698 `uri:` tasks | A — cross-app | C — control-node ansible | (A, C) | `https://<netbox_host>` derived from env var (`dmf-infra@37dbb56`, amending the earlier mis-step `3457513`) |
| `_cms_awx_api_base` in 697 | A — cross-app | C — control-node ansible | (A, C) | `https://<awx_host>` derived from env var (already correct) |
| Landing page app links | B — user-facing | O — operator browser | (B, O) | Public URL — unchanged |

---

## 3. Known scope (initial pass)

From session 2026-05-13/14 grep work, the following files have cross-app
URL defaults pointing at `dmf.example.com` or other public hosts. Each
needs classification per §2.2.

| File | Lines | Likely bin | Notes |
|---|---|---|---|
| `playbooks/698-cms-netbox-forgejo-tokens.yml` | 217, 397, 412, 436, 455, 470, +2 more | (A, C) | **DONE (corrected)** — `dmf-infra@3457513` migrated to internal DNS, `dmf-infra@37dbb56` corrected to `*_host`-derivation (control-node caller, needs public URL until in-cluster runner pod lands) |
| `playbooks/697-cms-awx-token.yml` | 36–41 (`_cms_awx_api_base`) | C → could be A | Already derives via `awx_host`; works on aliyun-123. Could be migrated to internal-service default for defense-in-depth |
| `playbooks/696-cms-authentik-api.yml` | none (uses `kubectl exec ak shell`) | — | No HTTP — uses in-pod Python |
| `playbooks/691-netbox-sot.yml` | references `forgejo_internal_host` (already internal via `dmf-infra@07d0e00`) | A — already done | `forgejo-http.forgejo.svc.cluster.local:3000` |
| `playbooks/692-forgejo-bootstrap.yml` | TBD — survey | — | Forgejo API for user/repo provisioning. If calling Forgejo via localhost from inside its own pod, fine. If cross-pod, classify A |
| `playbooks/693-awx-integration.yml` | TBD — `awx_integration_api_base` | TBD | Where this resolves matters; survey needed |
| `playbooks/694-born-inventory.yml` | TBD | — | Constructs NetBox URLs; verify already internal |
| `playbooks/699-cms-smoke-test.yml` | TBD | — | If smoke-test from a pod, internal; if from operator workstation, public is correct |
| `roles/stack/operator/cms/...` | `dmf_cms_*_url` defaults | mixed | Runtime config injected into CMS pod. App-to-app calls = A. Frontend redirect URLs = B (stay public) |
| `roles/stack/operator/awx-integration/...` | inventory `*_url` for AWX inventory plugin | A | AWX talks to NetBox via API — internal is fine |
| `roles/stack/operator/forgejo-bootstrap/...` | OAuth client redirect URIs | B | Authentik OIDC callback URLs — stay public |
| `roles/stack/operator/landing-page/...` | discovered app URLs | B | These are rendered to the user — stay public |

This table is incomplete; the survey will fill it in.

---

## 4. Service-name + port reference (verified 2026-05-14 on aliyun-123)

When migrating, use these exact internal endpoints:

| App | Service | Namespace | Port | Internal URL |
|---|---|---|---|---|
| Authentik | `authentik-server` | `authentik` | 80 | `http://authentik-server.authentik.svc.cluster.local:80` |
| AWX | `awx-service` | `awx` | 80 | `http://awx-service.awx.svc.cluster.local:80` |
| Forgejo (HTTP) | `forgejo-http` | `forgejo` | 3000 | `http://forgejo-http.forgejo.svc.cluster.local:3000` |
| Forgejo (SSH) | `forgejo-ssh` | `forgejo` | 22 | (SSH not in scope for HTTP-wiring migration) |
| NetBox | `netbox` | `netbox` | 80 | `http://netbox.netbox.svc.cluster.local:80` |
| Zot | TBD — survey | `zot` (?) | 5000 | TBD |
| Grafana | TBD — survey | `monitoring` (?) | 3000 | TBD |
| LibreNMS | not deployed on aliyun-123 | — | — | survey on hetzner-arm |
| OpenBao | `openbao` | `openbao` | 8200 | already used via `kubectl exec` pattern, not HTTP-default |

The list is verified for aliyun-123. Names may vary on hetzner-arm (e.g.
if a Helm chart's `fullnameOverride` differs); migration must check both
envs and use the canonical name (most Helm charts produce stable service
names per chart version, so a single internal URL default usually
covers all envs).

---

## 5. Acceptance criteria

Migration is "done" when:

1. The survey table in §3 is fully classified — every cross-app URL
   default is bin-A or bin-C; nothing left unclassified.
2. All bin-A defaults have been migrated to internal service DNS, each
   in a focused commit citing ADR-0023.
3. `bootstrap-configure.yml` runs end-to-end on a fresh-cluster baseline
   with **zero** `cms_*_api_url`-style overrides on the command line.
   (Drift-related `-e` overrides per the App Admin Drift audit doc are
   a separate concern and out of scope here.)
4. (Optional) `bin/scrub-public-repos.sh` or pre-commit grows a check
   that flags new `https?://.*dmf\.example\.com` defaults in `uri:`
   contexts — discipline gate against regression.

---

## 6. Out of scope (explicit)

- **User-facing URLs.** Anything rendered to a human or used by an external
  IdP/webhook source stays public. Examples: landing page links, OIDC
  redirect_uri lists, CMS frontend asset URLs.
- **`external_base_url` and ingress configuration.** These are *about*
  public URLs by definition; they configure the public surface.
- **OpenBao addressing.** Already uses `kubectl exec` patterns in the
  playbooks (no HTTP defaults to migrate). The OpenBao public URL exists
  for operator break-glass only.
- **OIDC discovery endpoints.** Authentik's OIDC issuer URL is part of
  its public identity — clients (NetBox, AWX, Forgejo, dmf-cms) need
  the issuer URL to match what's in the token's `iss` claim. Out of
  scope for this migration.
- **Drift-related admin user/password overrides.** Covered by the App
  Admin Drift Audit (`DMF App Admin Account Drift Audit and
  Realignment Plan 2026-05-14.md`). Different concern from URL routing.
- **dmf-cms runtime config (`dmf-cms-runtime` Secret).** The CMS app
  itself needs the right URLs depending on whether it's calling NetBox
  (internal) or rendering a link to NetBox in the UI (public). The CMS
  consumer side is in scope; the values *injected* into the runtime
  Secret are part of this migration only for the app-to-app calls,
  not for the UI render URLs.

---

## 7. Risks

1. **Hostname leak into user-facing render.** A migrated default that
   gets accidentally exposed to the user (e.g. error page shows
   "could not reach http://netbox.netbox.svc.cluster.local"). Mitigate
   by reviewing each app's error-rendering surface; render-time URLs
   should still come from the public `*_host` var.

2. **Off-cluster validator regression.** If anyone runs a validator on
   their workstation pointing at the role's default, switching to
   internal DNS breaks that flow. Mitigate by **keeping the per-env
   override knob fully functional**; off-cluster usage explicitly sets
   `cms_*_api_url` to the public URL via `-e` or env override.

3. **Service-name divergence across envs.** A Helm chart with different
   `fullnameOverride` between envs produces different service names.
   Mitigate by verifying internal URL on every env before merging the
   migration — single-env testing is insufficient.

4. **OIDC token audience.** If an app's OIDC tokens are bound to an
   issuer's public URL, and the app does internal-URL discovery, there
   can be `aud` mismatches. Not yet observed; flag if it surfaces.

---

## 8. Critical files

Survey targets — read-only for §3 classification:

- `dmf-infra/k3s-lab-bootstrap/playbooks/*.yml` (all playbooks)
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/*/{defaults,tasks,templates}/`
- `dmf-infra/k3s-lab-bootstrap/roles/common/*/`
- `dmf-cms/` — runtime config consumers (separate workstream)

Migration targets — to be patched in focused commits:

- One commit per playbook/role file with cross-app default changes
- Each commit cites ADR-0023 in the message
- Verify with `ansible-playbook --syntax-check` before committing
- For each migrated default, do an in-pod probe on at least one env to
  confirm 200/401/302 response (not a host-header rejection)
