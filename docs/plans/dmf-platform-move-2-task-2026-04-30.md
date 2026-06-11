---
status: executed
date: 2026-04-30
executed: 2026-05-04
---
# Move 2 — DMF Console Vertical Slice + NetBox SoT Closure

> **2026-05-19 note — ADR-0016's "Move 2 deferred" work landing earlier.**
> ADR-0016 §Decision named EE-as-runtime as work deferred "to Move 2." It
> is now being executed earlier as **Lane A** of the
> [DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19](./DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md).
> This does **not** enlarge Move 2's scope (still Console + NetBox SoT);
> only redirects where the EE-as-runtime workstream's outputs land. ADR-0025
> codifies the move.

**Date:** 2026-04-30
**Repo scope:** `dmf-infra` + `dmf-cms`
**Reviewer that produced this task:** Claude Code (Opus 4.7), strategic review at `<repos>/dmf-platform-strategic-review-2026-04-30.md`, chain review at `<repos>/dmf-platform-chain-review-2026-04-30.md`
**Strategic context:** experiment phase, this is a falsifying test — the goal is to *learn whether the architecture survives contact with reality*, not to ship release-quality polish.
**Estimated effort:** 1–2 days realistic (was "half-day to full day" — bumped after spec audit revealed three pieces are heavier than first scoped).
**Blocker for the commit gate** in the strategic review.

> **Note on what this DOES NOT test:** Move 2 tests *single-cluster* identity composition (Authentik OIDC → dmf-cms → AWX → NetBox), not *cross-cluster federation* (which is dmf-central's thesis-killer, deferred until dmf-central exists). It also does not test the NMOS / Layer 4 thesis — that's Move 1. Three of the strategic review's four thesis-killers remain in their original priority; this exercise is sized for the SoT-and-data-flow question only.

---

## What this is and isn't

### This IS

A **falsifying spike**. One end-to-end vertical slice from the dmf-cms Workflows page through AWX to a real result, plus the NetBox SoT closure that the chain review identified as the load-bearing axiom. The whole point is to expose where the architecture is wrong *before* committing dmf-cms release-1 to a story that depends on it.

### This is NOT

- A polished release. The UI can be ugly. The error paths can be minimal. The code can have one TODO per shortcut.
- A multi-workflow build. Pick ONE workflow and wire it. The other three stay as static labels on the Workflows page.
- A full SoT taxonomy. Register apps as NetBox `ipam.Service` objects with the *minimum* fields needed; extend later when actual usage reveals what's missing.
- A multi-cluster federation exercise. Single cluster only.
- An observability/alerting/backup pass. Hardening waits for the commit gate.
- An auth-rebuild. Pick the simplest auth path that demonstrates the loop closes; rebuild later if needed.

---

## What this falsifies (or confirms)

Four architectural assumptions, in priority order:

1. **NetBox SoT is sufficient to drive AWX inventory the way you'd commit to.** If `nb_inventory` plugin can't represent the apps as the platform sees them, the SoT story breaks and you reshape NetBox custom fields before locking in.
2. **The dmf-cms `app-contract` model survives a live backend.** If the static YAML fixture's fields don't map cleanly to NetBox `ipam.Service` records, the contract changes shape — better discovered now than after release-1 ships.
3. **Runtime auth composition works.** Operator clicks "Run" in the console (Authentik OIDC session) → console calls AWX (some auth) → AWX uses NetBox token to read inventory → AWX runs the playbook → result returns to console. If any link is missing or twisted, find out now.
4. **`ipam.Service` is the right NetBox shape for the service catalog.** It's the obvious built-in (host-or-VM running app-on-port). If apps don't fit (e.g. SSO-federated apps need user/owner/lifecycle fields beyond what `ipam.Service` natively models), pivot to a different model or NetBox plugin.

---

## Decision points (need your input before execution)

### D1 — Which workflow to wire end-to-end first

`dmf-cms/src/dmf_cms/main.py:45-50` declares four workflow stubs:

```
WORKFLOWS = (
    ("stack-verify", ...),
    ("endpoint-certificate-verify", ...),
    ("eso-openbao-health-check", ...),
    ("netbox-registration-dry-run", ...),
)
```

**Recommendation: `eso-openbao-health-check`.** Read-only, low blast radius, exercises the inventory-pull + AWX run + structured-result loop without mutating anything. If something breaks, no cleanup needed.

Alternatives:
- `stack-verify` — broadest coverage, but it touches a lot; if it fails halfway you don't know which subsystem.
- `netbox-registration-dry-run` — meta-circular (using NetBox to verify NetBox); cute but harder to debug.
- `endpoint-certificate-verify` — also read-only and clean, but the cert path is mature so this falsifies less.

**Action:** confirm `eso-openbao-health-check` or pick another.

---

### D2 — NetBox `ipam.Service` field schema for apps

NetBox built-in `ipam.Service` model has: `name`, `protocol`, `ports[]`, `device | virtual_machine`, `description`, `comments`, `tags[]`, custom fields. Each app gets one Service object linked to the cluster's load-balancer Device.

**Minimal schema for the spike:**

| Field | Value | Source |
|---|---|---|
| `name` | app key (e.g. `forgejo`) | from inventory `*_app_name` or hostname stem |
| `protocol` | `tcp` | always |
| `ports` | `[443]` | always (Traefik front) |
| `device` | LB device (already created by 694) | reuse `dmf_born_inventory_load_balancer_id` |
| `description` | `<App display name> on <cluster>` | template |
| `comments` | hostname, OIDC client id, helm release name, exposure (public/private), owner-svc | template |
| `tags` | `dmf`, `app:<key>`, `exposure:<public|private>`, `lifecycle:active` | derived |

Custom fields **deferred** — the goal is "NetBox knows about the apps", not "NetBox holds the full app contract". When dmf-cms tries to read this and finds a field missing, that's the signal to add a CF.

**Action:** confirm minimal schema or extend before writing the role.

---

### D3 — Auth path from dmf-cms to AWX

**Important constraint discovered during spec audit:** AWX is currently wired to Authentik via **SAML**, not OIDC (`roles/stack/operator/authentik/templates/blueprints/20-app-providers.yaml.j2:84` provider id is `saml-awx`). That kills the original "OIDC pass-through / OIDC token-exchange" options — they would require either rebuilding the AWX↔Authentik integration as OIDC (~half-day on its own) or a more elaborate exchange. So the realistic options are now:

| Option | Mechanism | Pros | Cons |
|---|---|---|---|
| **A. AWX OAuth2 service-account token** (recommended for spike) | dmf-cms holds a `dmf-cms-svc` AWX OAuth2 token (NOTE: AWX uses OAuth2 applications + tokens, not opaque bearer tokens — the playbook must POST to `/api/v2/applications/` and `/api/v2/tokens/`). Token persists in OpenBao at `secret/apps/awx/runtime` and lands in `dmf-cms-runtime` K8s Secret. | Simplest. Independent of the SAML path. ~45 min to wire (was "30 min" — bumped because OAuth2 in AWX is heavier than a simple bearer-token POST). | The console acts as a single AWX identity; per-user RBAC is lost. Audit trail in AWX shows `dmf-cms-svc`, not the human. |
| B. Re-do AWX↔Authentik as OIDC, then pass-through | Tear down the SAML provider in Authentik, set up OIDC, configure AWX `SOCIAL_AUTH_OIDC_*`, then have dmf-cms forward the user's Authentik bearer to AWX. | Per-user identity preserved end-to-end. | The SAML rework is itself a half-day and risks breaking AWX login for everyone. Conflates two thesis tests. |

**Recommendation: A for the spike.** Per-user identity is a separate question; bundling it in conflates the thesis test. If A works and you decide per-user identity is required for release-1, B becomes a follow-up — and you'll know it's worth the SAML rework.

**Action:** confirm A. If A: a new playbook `697-cms-awx-token.yml` will create `dmf-cms-svc` user, an OAuth2 application owned by that user, an OAuth2 token, persist to OpenBao, patch the K8s Secret, and roll the dmf-cms Deployment.

---

### D4 — App-contract: keep static or pivot to NetBox-discovered

Currently `dmf-cms` loads its app catalog from a YAML fixture (`AppContract` in `contracts.py`). The strategic review flagged this as one of the things Move 2 should test.

Two choices:

- **Keep static, treat NetBox extension as "additionally registered".** The console reads from the fixture as today; NetBox holds a parallel record that AWX uses for inventory. Two stores of the same truth — explicit duplication, but contained.
- **Pivot to NetBox-discovered.** The console queries NetBox for apps at startup (or on each request, with cache) and builds the catalog dynamically.

**Recommendation: keep static for now.** The pivot is a separate concern; mixing it into Move 2 conflates two questions. Once Move 2 is done and the NetBox shape is validated, *then* pivot dmf-cms to read from NetBox in a follow-up. This also keeps the spike's blast radius small.

**Action:** confirm static (and queue the pivot as a TODO), or include the pivot now.

---

## Concrete work breakdown

Assuming D1=`eso-openbao-health-check`, D2=minimal schema, D3=service-account token, D4=keep static.

### Piece 1 — NetBox SoT extension (~1-2 hr)

**File scope:**
- `roles/common/dmf-born-inventory/tasks/main.yml` — extend with app-registration loop
- `roles/common/dmf-born-inventory/tasks/app-service.yml` — NEW — per-app `ipam.Service` upsert (factor out like `node.yml`)
- `roles/common/dmf-born-inventory/defaults/main.yml` — add `dmf_born_inventory_apps:` list with key/display-name/exposure/oidc-client-id per app
- `roles/stack/operator/netbox-sot/tasks/main.yml` — add forgejo-svc user creation block (mirror awx-svc pattern)
- `roles/stack/operator/netbox-sot/defaults/main.yml` — add forgejo-svc vars

**App list to register** (from existing `inventories/example/group_vars/all/main.yml`):
- `landing` (public, no OIDC)
- `authentik` (public, self-OIDC)
- `forgejo` (private, OIDC client `forgejo`)
- `awx` (private, OIDC client `awx`)
- `netbox` (private, OIDC client `netbox`)
- `grafana` (private, OIDC client `grafana`)
- `prometheus` (private, no OIDC — basic auth or open)
- `loki` (private, no OIDC)
- `zot` (private, OIDC client `zot` — added in 695)
- `dmf-cms` (public-or-private depending on env, OIDC client `dmf-cms`)

**Acceptance:** after `694-born-inventory.yml` runs, `curl https://netbox.<domain>/api/ipam/services/?tag=dmf` returns 10 records. Each record has `name`, `protocol`, `ports`, `device`, `description`, `comments`, `tags` populated per the schema. forgejo-svc exists as a NetBox user with API token (parallel to awx-svc).

---

### Piece 2 — AWX-side service-account for dmf-cms (~30 min)

**File scope:**
- `playbooks/697-cms-awx-token.yml` — NEW — mirrors `696-cms-authentik-api.yml` pattern
- `roles/stack/operator/cms-awx-token/` — NEW small role, OR keep tasks inline in the playbook
- `lifecycle-provision.yml` — add the new playbook after `696-cms-authentik-api.yml`

**What it does:**
1. Create `dmf-cms-svc` user in AWX (admin API)
2. Grant the user `Inventory > Read` on the NetBox-derived inventory + `Job Templates > Execute` on the chosen workflow's job template
3. Generate an OAuth2 application + token for dmf-cms-svc (AWX uses OAuth2 not bearer)
4. Persist token to OpenBao at `secret/apps/awx/runtime` → `cms_api_token`
5. Patch the `dmf-cms-runtime` K8s Secret to include `awxApiToken`
6. Roll the dmf-cms Deployment

**Acceptance:** `kubectl exec -n dmf-cms deploy/dmf-cms -- env | grep AWX_API_TOKEN` shows the token is mounted; `curl -H "Authorization: Bearer <token>" https://awx.<domain>/api/v2/me/` from inside the pod returns 200 with `username: dmf-cms-svc`.

---

### Piece 3 — AWX job template for the chosen workflow (~30 min)

**File scope:**
- The existing `roles/stack/operator/awx-integration/tasks/main.yml` already wires AWX to NetBox + Forgejo. Extend it to *also* create the job template.

**Choices:**
- The playbook source: needs to be either (a) committed to the Forgejo repo `forgejo-svc/dmf-runbooks` (or similar) so AWX SCM-clones it, or (b) referenced from `dmf-infra` with AWX configured to clone from the local forgejo. Pick (a) and check in `playbooks/runbooks/eso-openbao-health-check.yml` to the forgejo repo; AWX SCM-pulls it.
- Or: the playbook source can be a directly-typed string in AWX's "manual project" — fastest for the spike, but doesn't test the SCM loop.

**Recommendation:** put the playbook in the existing forgejo repo. Pre-existing `forgejo-bootstrap` creates `dmf-runbooks` repo (or whatever `forgejo_repos` lists). Just add the runbook file there.

**Inventory:** AWX already has the NetBox inventory source from `awx-integration`. Job template uses that.

**Acceptance:** From AWX UI, manually launch the job template. It pulls the playbook from forgejo, syncs inventory from NetBox (which now contains app records), and runs the openbao-health-check playbook against the cluster. Job completes successfully. A future-Claude can run this from the dmf-cms console (Piece 4).

---

### Piece 4 — dmf-cms Workflows page wires through to AWX (~1-2 hr)

**File scope:**
- `dmf-cms/src/dmf_cms/awx.py` — NEW — `awx_launch_job(template_name)`, `awx_get_job_status(job_id)` minimal client
- `dmf-cms/src/dmf_cms/settings.py` — add `awx_api_url`, `awx_api_token`, validation that they are configured
- `dmf-cms/src/dmf_cms/main.py` — add POST `/api/workflows/{key}/run` (kicks off AWX job, returns `{job_id, status_url}`); add GET `/api/workflows/{key}/status/{job_id}` (returns status). Add HTMX-ish "Run" button + result panel to `templates/page.html` for the workflows section.
- `dmf-cms/charts/dmf-cms/values.yaml` — surface AWX runtime config
- `dmf-cms/tests/test_awx.py` — NEW — unit tests for the AWX client with mocked responses (mocking is OK in unit tests; the integration test is the real loop)

**Behavior:**
- User clicks "Run" on the chosen workflow card
- Console POST to `/api/workflows/eso-openbao-health-check/run`
- Backend calls `POST {awx_api_url}/api/v2/job_templates/<id>/launch/` with bearer token
- Returns the AWX job id; UI polls `/api/workflows/.../status/<job_id>` every 2s
- When job completes: UI displays final status + tail of stdout (or link to AWX run)

**Acceptance:** Run the workflow from the UI as a logged-in user. Job runs in AWX. Result appears in the UI within 30 seconds. The full path is exercised: Authentik OIDC session → dmf-cms → AWX (svc-account auth) → NetBox inventory pull → playbook runs → result back.

---

### Piece 5 — Console integration smoke (~30 min)

**File scope:**
- `playbooks/698-cms-integration-smoke.yml` — NEW — appended to lifecycle-provision after `697-cms-awx-token.yml`

**What it does:**
- `kubectl exec -n dmf-cms deploy/dmf-cms -- curl -sf -o /dev/null -w '%{http_code}'` against:
  - `https://netbox.<domain>/api/` (expect 401, which proves reachable + cert OK)
  - `https://awx.<domain>/api/v2/ping/` (expect 200)
  - `https://prometheus.<domain>/-/healthy` (expect 200)
  - `https://auth.<domain>/application/o/dmf-cms/.well-known/openid-configuration` (expect 200)
- Assert all four return the expected status codes
- Optionally: with the `dmf-cms-svc` AWX token, hit `https://awx.<domain>/api/v2/me/` and assert `username == "dmf-cms-svc"`

**Acceptance:** lifecycle-provision exits green only if the console's outbound network and credentials work. The first failure here points at the broken backend, not "the deployment is unhealthy".

This is the gate for the strategic-review commit gate. When `698-cms-integration-smoke` is green AND a workflow run from the UI succeeds, you've closed Move 2.

---

## How to execute this — three options

### Option A — Codex autonomous, with human checkpoints

Hand this entire spec to codex with explicit STOP gates after each Piece. Codex builds, you review the diff after each Piece, you decide whether to proceed.

**Pros:** Fastest wall-clock. Pieces 1, 2, 3, 5 are mechanical enough.
**Cons:** Piece 4 (dmf-cms code changes) needs taste calls — error UX, polling cadence, status-rendering. Codex without human-in-loop on UI tends to over-engineer or under-handle errors.

**Recommended:** A but only for Pieces 1, 2, 3, 5 (the Ansible side). Piece 4 (dmf-cms Python + templates) is human-with-Claude territory.

### Option B — Claude with user, single session

You and Claude work through it sequentially in one session. Decisions get made inline. Codex stays out of it.

**Pros:** Highest quality on Piece 4. Architectural decisions get owned not auto-defaulted.
**Cons:** Slowest wall-clock. Eats a lot of session context.

### Option C — Mixed: codex on Ansible, Claude on dmf-cms

Codex executes Pieces 1, 2, 3, 5 autonomously (the Ansible scope, mechanical). Claude works with you on Piece 4 (Python + UI, taste-heavy). Final integration test runs end-to-end after both halves merge.

**Recommended.** Plays each tool to its strength.

**Sequencing under Option C:**
1. Codex: Piece 1 (NetBox SoT extension)
2. Codex: Piece 2 (AWX svc-token)
3. Codex: Piece 3 (AWX job template)
4. **Manual run:** Launch the job from AWX UI to confirm the loop works server-side, before involving dmf-cms
5. Claude+user: Piece 4 (dmf-cms Workflows wiring)
6. Codex: Piece 5 (integration smoke)
7. Final test: launch from dmf-cms UI

---

## Acceptance — falsification or confirmation

Move 2 is "complete" (gate-closed) when **all** of these are true:

- [ ] `694-born-inventory.yml` registers ≥10 apps as NetBox `ipam.Service` records, each tagged `dmf`
- [ ] forgejo-svc exists as a NetBox user (consistency with awx-svc, librenms-svc)
- [ ] `dmf-cms-svc` AWX user exists with a token persisted in OpenBao + dmf-cms-runtime Secret
- [ ] One workflow (e.g. `eso-openbao-health-check`) has an AWX job template that pulls inventory from NetBox and runs successfully when launched manually
- [ ] dmf-cms Workflows page has a working Run button that exercises the full loop and returns a result within 30s
- [ ] `698-cms-integration-smoke.yml` runs as part of lifecycle-provision and asserts all four console-backend reachability checks
- [ ] After lifecycle-provision passes, **a write-up captures what was learned** — schema fields that needed changing, auth path surprises, NetBox field gaps. This is the actual deliverable of Move 2; the working code is incidental.

If **any** of those breaks in a way that requires re-shaping NetBox or dmf-cms's data model, that breakage IS the deliverable. The strategic review's commit gate triggers when this loop runs end-to-end *or* when the breakage tells you to redraw the architecture before committing.

---

## Out of scope (do NOT include in Move 2)

- The other three workflows (`stack-verify`, `endpoint-certificate-verify`, `netbox-registration-dry-run`). Static labels stay.
- Polished error UX in the console. "Failed: see AWX run #123" is enough.
- SSE streaming of workflow output. Polling is fine.
- Per-user RBAC end-to-end. Service-account is fine for the spike (D3 option A).
- App-contract pivot to NetBox-discovered (D4 option B). Static fixture stays; queue as TODO.
- Multi-cluster federation. Single cluster.
- Token rotation, backups, alerts. Hardening waits for the commit gate.
- NMOS work (Move 1). Separate spike.
- Renumber/regroup playbooks (chain review #1). Wait for commit gate.
- Resource Profile manifest codegen (chain review #7). Release 5 work.

---

## Dependencies on prior cleanup (must be in place)

- ✅ Step 1 from chain-review cleanup (commit `9bdf758`) — fail-closed OpenBao mode
- ✅ Step 2 from chain-review cleanup (commit `d69935e`) — librenms gating
- ✅ Step 3 from chain-review cleanup (commit `19911bc`) — real L3 verify
- ✅ Strategic review committed and pushed
- ✅ DMF Platform Plan v0.1 committed and pushed

All in. Move 2 is unblocked.

---

## What to commit (suggested commit shape)

Five commits, one per Piece:

1. `feat(netbox-sot): register L6 apps as ipam.Service + add forgejo-svc user`
2. `feat(awx): provision dmf-cms-svc service account and OAuth2 token`
3. `feat(awx-integration): create job template for eso-openbao-health-check workflow`
4. `feat(dmf-cms): wire Workflows page to launch + poll AWX jobs`
5. `feat(verify): add 698-cms-integration-smoke for full backend reachability`

Each commit independently tests its own scope and can be reverted independently.

---

## Cross-reference

- Strategic review: `~/repos/dmf-platform-strategic-review-2026-04-30.md` (Move 2 framing)
- Chain review: `~/repos/dmf-platform-chain-review-2026-04-30.md` (findings #2, #3, #6 closed by this work)
- DMF Platform Plan: `~/repos/dmf-infra/k3s-lab-bootstrap/docs/dmf-platform-plan.md` (architectural reference)
- Cleanup task (already complete): `~/repos/dmf-platform-codex-cleanup-task-2026-04-30.md`
- Initial Data Gathering: `~/repos/dmf-env/docs/initial-data-gathering.md` (source of app list and OpenBao schema)
- Deployment Runbook: `~/repos/dmf-env/DEPLOYMENT.md`

---

## Single-line goal

**Close one workflow loop from console click to playbook result. Register the apps as NetBox `ipam.Service` so the SoT promise is kept. Capture what broke. That's the gate for committing the architecture.**
