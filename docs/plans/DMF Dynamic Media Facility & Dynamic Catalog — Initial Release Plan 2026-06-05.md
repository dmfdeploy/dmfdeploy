---
status: historical
date: 2026-06-05
---
# DMF Dynamic Media Facility & Dynamic Catalog — Initial Release Plan

**Date:** 2026-06-05
**Status:** Plan (approved scope: *full generic reconcile*). **No formal ADR yet** — formalize once the controller-shaped reconcile is proven on the two-function demo (operator instruction).
**Authoring:** Claude + a deep-dive adversarial review by codex (gpt-5.x, 2026-06-05).
**Expands:** `DMF Dynamic Catalog & Deployable-Workflow Mechanism — Discussion Notes 2026-06-05.md` (the originating thread; coupling-map + live evidence).
**Governed by / pressure-tests:** [ADR-0037](../decisions/0037-media-workloads-netbox-instance-inventory.md) (amends [ADR-0027](../decisions/0027-catalog-instance-vs-definition-separation.md)), [ADR-0013](../decisions/0013-media-function-catalog-model.md), [ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md), [ADR-0028](../decisions/0028-identity-and-authority-chain.md), [ADR-0032](../decisions/0032-catalog-launcher-scoped-netbox-writer.md). Canonical model: [`DMF Function Catalog Model`](../architecture/DMF%20Function%20Catalog%20Model.md).
**Target lane:** the single-node `sandbox` (`dmf-sandbox` Lima Debian-12 ARM64). Genericity comes from a *second function*, not a second node.

---

## 0. Goal & what "demonstrate the concept" means

DMF aims to be a **Dynamic Media Facility**: an operator **adds / deploys / removes** media functions from a **dynamic catalog of media workloads**, sees what's deployed and where, with the deploy *workflow itself* dynamically updatable — **without hand-running playbooks**.

The acceptance bar for the initial release (the demo): a reviewer watching the console sees —

> commit a catalog YAML + chart → click **Sync Catalog** → the entry appears **without a dmf-cms redeploy** → **Deploy** → **Media Workloads** shows active count + where → **Teardown** → count → 0 → **remove the entry + Sync** → it disappears and its job templates are no longer launchable by API.

**No laptop `630/693/697` anywhere in that loop.** If the operator still hand-runs bootstrap playbooks, it is a manually-patched catalog UI, not a Dynamic Media Facility.

## 1. Why now — the live evidence

The `mxl-hello` live verify (env `u1u3-c7rz`, 2026-06-05) proved the catalog→AWX→helm→pod→live-MXL-flow path **and exposed three gaps**, each fixed by hand on the cluster, each the same root: *the catalog-launcher infra was hardwired to the first function (nmos-cpp) and never generalized* — exactly the [ADR-0027](../decisions/0027-catalog-instance-vs-definition-separation.md) "bootstrap-RBAC conflation":

1. **Console Deploy 404** — `dmf-cms-svc` had no role on the new JTs; `697`'s grant (`cms_awx_catalog_job_templates`) is a *separate hardcoded list*. (`lookup_job_template_by_name` → None → 404 before AWX is invoked.)
2. **AWX job 403** — launcher SA `nmos:nmos-cpp-launcher` Role is scoped to the `nmos` namespace only; it can't operate in `mxl`.
3. **No catalog status** — the simplified launch playbook omitted the NetBox lifecycle-flip that nmos-cpp's *role* does (provision = create NetBox Service; configure = flip `lifecycle:active`; finalise = flip back) → no NetBox instance → console shows nothing deployed.

Those hand-fixes are the per-function toil a dynamic catalog must eliminate. See [[project_catalog_jt_rbac_two_list_gap]].

## 2. The v1 contract (stated up front)

- **First-party catalog only.** A catalog entry names a playbook/chart/image — that is *code execution*, not harmless metadata. 3rd-party deferred (it needs schema validation, allowed repo/registry prefixes, signed commits/artifacts, chart lint/scan, quotas, an approval gate).
- **Git YAML is the canonical *definition* store** (`dmf-media/catalog/<key>.yaml`). **NetBox is read-model + instance store + approval state only** — never the definition source. (Moving definitions into NetBox creates an unaudited "write arbitrary AWX playbook reference" path — codex.)
- **Secrets are *references*, never values.** A catalog entry may declare OpenBao paths / an ESO `ExternalSecret` spec; the reconcile/launcher ensures the `ExternalSecret` exists in the target namespace and ESO syncs it from OpenBao at runtime. **No secret material in git** (ADR-0007/0008). A catalog entry must not be able to reference arbitrary OpenBao paths — restrict to an allowed prefix per function (3rd-party hardening; first-party trusted in v1).
- **k3s is runtime/scheduler.** NetBox *scopes* eligibility (tenant/site/cluster); k3s *schedules* placement; born-inventory records *where it landed*.
- **One instance per function** for v1. Multi-instance needs a real instance identity — `ipam.Service` name alone won't survive count>1.
- **Deferred:** flow graph / composition canvas / cross-host fabrics / per-user NetBox tokens / continuous watch loop / auto-destructive removal of active workloads.
- **Declared lifecycle ≠ observed health.** The console must distinguish NetBox's `lifecycle:*` tag from runtime health — tags lie if Helm dies.

## 3. Architecture — AWX reconcile built like a controller

The spine stays ADR-0037 (NetBox instances + AWX reconcile; **not** a CRD/operator). But **AWX must be a *controller*, not a pile of rerunnable bootstrap fragments.** A `catalog-reconcile` job MUST:

- **read desired state** = git catalog (definitions) + NetBox (cleared/desired instance set);
- **compute a desired resource set** and **owner-label** everything it manages (`dmf.io/managed-by=catalog-reconcile`, `dmf.io/catalog-key=<key>`);
- **dry-run → diff → apply → PRUNE.** Prune of stale resources is the load-bearing difference between a Dynamic Media Facility and a manually-patched UI. If reconcile only *appends* JTs/RBAC/charts, it recreates today's footgun at scale.
- **write a status object keyed by `catalog git-rev + computed desired-set hash`** (not a timestamp) → the console can answer *"which exact catalog did AWX converge?"* and surface stale/partial sync;
- run **idempotent phases** — it is **not** transactional (it can mirror a chart then fail before JT prune). Each phase is re-runnable; the status records the last-successful phase.

**Three stores, clean ownership** (ADR-0037): git catalog = *definitions* (immutable, reviewed); NetBox = *instances + placement + approval/lifecycle* (no flows, no graph object); k3s = *actual runtime*.

**CRD/operator stays the end-state** (ADR-0027), promoted when N grows / 3rd-party is real / convergence must be continuous. Deferring it until the controller-shaped reconcile proves itself is the right sequencing.

## 3a. The actuator fork — hand-built AWX reconcile vs **Argo CD** (open decision)

Everything §3 says the AWX reconcile must do *for the Kubernetes side* — desired-set from Git, diff, apply, **prune**, **health + status keyed by the synced git-rev**, self-heal/drift — **is exactly what Argo CD does natively**, and **ApplicationSet's git-directory generator maps almost literally onto "a dynamic catalog"** (a git dir of app definitions → one auto-managed `Application` each, **pruned on removal**, with sync/health/last-synced-revision in its API + UI). Hand-rolling that controller in Ansible/AWX is rebuilding — worse — what Argo already is. So the honest model is a **hybrid by responsibility**, and *which actuator owns the k8s reconcile is a real fork to decide*:

| Responsibility | More natural owner |
|---|---|
| K8s declarative reconcile (namespace, RBAC, Helm release, `ExternalSecret`, workload) + **prune + health + drift + synced-revision status** | **Argo CD** (ApplicationSet git generator) — it *is* the controller |
| Imperative glue not expressible as k8s objects: **NetBox** instance/lifecycle + born-inventory placement; **approval / "clear-for-deployment"** + C5 audit; **Zot** GHCR→Zot mirror | **AWX** (NetBox/approval/audit) + **CI** (mirror); the NetBox write can be an Argo **PostSync hook** Job |
| AWX **JT Org-Execute RBAC** (gap #1's structural fix) | **may shrink or disappear** if Argo (not AWX) deploys the workload — the console triggers an Argo sync / writes a desired `Application` instead of launching a JT |

- **Where Argo is genuinely better:** prune/health/status/self-heal/drift are *free* (the load-bearing controller semantics we'd otherwise hand-build); ApplicationSet ≈ the dynamic catalog; synced-revision *is* the git-rev status the console needs; mature desired-vs-observed model + UI.
- **Where Argo doesn't reach (AWX/CI/hooks fill):** NetBox is not a k8s object (PostSync hook or AWX writes the instance record); GHCR→Zot mirror (CI / pre-sync); approval workflow + audit identity (console + AWX, or Argo manual-sync policy as the gate); multi-step imperative orchestration (AWX).
- **Costs / tensions:** Argo CD is **a new platform component not in the stack** — **ADR-0025 §9 explicitly deferred GitOps**; adopting it reframes ADR-0025's "in-cluster Helm via AWX EE" toward "Argo applies the chart," must pull charts/images from in-cluster **Zot** (fine — k8s-native), needs its own RBAC/SSO, and risks **two reconcilers** if AWX-deploy also stays (pick one deployer for the k8s side to avoid split-brain). Counter: Argo **reduces** build vs hand-rolling a controller, and ADR-0027 §"Alternatives" already noted "if GitOps lands, the reconciler can be that GitOps controller."
### Recommendation (codex re-review, 2026-06-05): adopt the hybrid — **gated on a viability spike**

Codex reconsidered and **endorses (ii) Argo-for-k8s + AWX/console-glue** — hand-rolling prune/health/status/self-heal in Ansible is "controller cosplay," and the hybrid "demonstrates DMF better because the dynamic catalog becomes visible as *controller state*, not Ansible emulating a controller." Adopt it for v1, subject to these **hard conditions**:

1. **Exactly one Helm owner = Argo.** AWX stops `kubernetes.core.helm` for media workloads — *full stop*, no dual path ever. The `media-launch-*` JTs become **legacy/break-glass with NO console path**; if they stay launchable via normal RBAC/API, split-brain is already back (worse than the original nmos hardcoding).
2. **Repo shape:** Argo's **Git *file* generator over the catalog YAML**, or a **catalog-hydrator** emitting `Application` manifests/values — **not** "catalog dir as manifest" (`dmf-media/catalog/*.yaml` is not a deployable manifest tree).
3. **Argo consumes *approved desired-instance* state, not raw catalog definitions.** Catalog entry exists = *deployable option*; **approved instance** exists = Argo `Application` exists/syncable. Removing a catalog definition marks it **unavailable/deprecated + blocks new deploys** — it does **not** prune active instances until the explicit teardown path removes the approved instance (preserves §7; Argo's default ApplicationSet lifecycle *would* delete the Application + resources).
4. **Approval gate (v1):** console **records C5** then **calls Argo Sync** via a tightly-scoped Argo token; **auto-sync disabled** for deploy → *Sync* is the consequential action. (Manual-sync alone ≠ C5 audit; console patches only narrow annotations/params, never arbitrary spec; a NetBox-flag custom generator = overbuild.)
5. **Audit split:** DMF/AWX owns *who/why* (C5); Argo owns *sync/revision/health* (deployment evidence); NetBox owns lifecycle/placement; correlate via a `dmf.io/request-id` label on the Application + resources.
6. **ADR amendment** (not just a plan note): ADR-0025 **Lane B is superseded ONLY for media-workload k8s deploys** — AWX EE stays valid for bootstrap/glue/imperative ops; **Argo becomes the Helm owner for catalog workload runtime.** Write it if the spike is green.
7. **AppProject is security-critical** — admin-owned, narrow destination namespaces, allowed repos, allowed source namespaces, allowed cluster-scoped resources. **Never template project names/fields from contributor-controlled catalog YAML** (the ApplicationSet privilege-escalation footgun).
8. **v1 Argo = internal-only, non-HA, no SSO/UI/ingress blocker.** Don't make Argo polish a release gate.
9. **START with a sandbox viability spike as a real KILL-SWITCH** (not a ritual) — see sequence step 0.

**Why it wins for v1:** Argo *reduces* engineering scope + conceptual risk vs hand-building a controller; the honest two-function demo is *faster* on the hybrid **iff** Argo stays internal-only. If the operator insists Argo be fully first-class before the demo, AWX-incremental may be faster — but that's self-inflicted scope.

**Net effect on §3–§4:** §3's "controller-shaped AWX reconcile" and §4 concerns **(a)(c)** collapse into **Argo** (it owns namespace/RBAC/ExternalSecret/Helm/workload + prune/health/status); **(b)** JT Org-Execute **largely disappears** (no JT to grant); **(e)(f)** NetBox/console + **(d)** Zot mirror + the **approval workflow** stay with **AWX/console/CI**. The AWX-reconcile path stays documented as the **fallback if the spike is red.**

## 4. The reconcile concerns — ownership

> **Cross-checked** against an independently-drawn deployment pipeline (Forgejo catalog → CI validate → mirror chart/image into Zot → AWX instantiate → Helm apply → **ESO pulls runtime secrets from OpenBao** → **Prometheus/Loki/Grafana discover by labels** → post-deploy AWX writes service records into NetBox). It matches this plan's spine and surfaced two concerns this plan now folds in: **(g) runtime secrets** and **(h) observability discovery**. The pipeline is the happy-path *forward* flow; this plan adds the **controller** semantics around it (desired-set / prune / status / deletion) that make removal and drift honest — a forward "apply" pipeline that never prunes is the manually-patched-UI trap.

| # | Concern | Owner in v1 | Notes / which gap it kills |
|---|---|---|---|
| a | **JT lifecycle** | `catalog-reconcile` | create/update desired launch+finalise JTs in a **catalog AWX Org**; **disable** stale (deprecate if active instances), hard-delete only when no runtime state. |
| b | **JT Execute authz** | structural — **AWX Org-scoped Execute** | a dedicated **catalog Org**; grant `dmf-cms-svc` **Org Execute once**; infra/`693`-class JTs stay in Default. Reconcile *asserts* the grant exists; it does **not** maintain per-JT lists. **(Gap #1.)** |
| c | **Launcher namespace + RBAC** | `catalog-reconcile` | reconcile **pre-creates** each catalog `provision.namespace` (+ labels; quotas/limits later) + the launcher-SA RoleBinding into it + the AWX pod-manager RoleBinding (ADR-0025 EE pods). **Launchers ASSUME namespace/RBAC exists and fail clear if not — they never create namespaces.** **(Gap #2.)** |
| d | **Chart + image → Zot** | **CI** publishes/validates; **reconcile** mirrors declared **chart AND images** GHCR→Zot | don't half-mirror — chart in Zot but image from public GHCR leaves it only half self-contained (ADR-0025). Fail visibly on private/missing artifact or digest mismatch. |
| e | **NetBox instance + lifecycle** | **shared generic lifecycle helper** | one `dmf-runbooks` NetBox-lifecycle helper used by nmos-cpp **and** mxl-hello — no function-specific tag-flip code. Reconcile may pre-register `lifecycle:bootstrapped`; launchers flip `active`/`bootstrapped` **after a real health check**; born-inventory records placement. **(Gap #3.)** |
| f | **Console visibility** | dmf-cms reads a **NetBox-backed catalog read-model** (generated from git by reconcile) + NetBox runtime | **remove the baked-ConfigMap dependency** for the dynamic path → entries appear without a dmf-cms redeploy. |
| g | **Runtime secrets** | reconcile/launcher ensures the **ESO `ExternalSecret`** in the target namespace; ESO syncs from OpenBao | catalog declares secret *references* (OpenBao path / ExternalSecret spec), never values. Restrict each function to an allowed OpenBao prefix. The deployed workload reads the synced k8s Secret — no secret ever in catalog git or the reconcile transcript (ADR-0007/0008). |
| h | **Observability discovery** | **label-based**, via the existing ADR-0038 / `dmf-promsd` NetBox-driven monitoring | the chart stamps standard labels + NetBox monitoring tags; Prometheus/Loki/Grafana discover the workload by label **automatically** — no per-function monitoring wiring. This is the **source of the Media Workloads page's observed-health** (the declared-vs-observed truth), and is already built. |

## 5. RBAC / namespace model for v1 (least-priv + reproducible)

- **One shared catalog-launcher ServiceAccount** in a fixed namespace; **reconcile-managed RoleBindings** into each target namespace (Role limited to what Helm-deployed media workloads need) + an AWX pod-manager RoleBinding per target namespace. AWX Container Group uses the shared SA; target namespaces bind it.
- **Not** a cluster-scoped launcher (destroys least-priv; makes every catalog entry cluster-admin-adjacent).
- **Not** per-function SAs yet (precise but adds CG/JT/token churn — save for untrusted 3rd-party).
- This **replaces today's hand-applied** `dmf-catalog-launcher-ns-read` ClusterRole + bespoke `mxl` Role (applied live on `u1u3-c7rz`) with a reconcile-generated, reproducible set.

## 6. Console — Media Workloads page + Sync Catalog

- **New page** `dmf-cms/frontend/src/pages/MediaWorkloads/` (+ `Sidebar.tsx` nav, gated to a **media-engineers** group). Backend `GET /api/media-workloads` (pattern: the existing `api_catalog_list` in `dmf-cms/src/dmf_cms/main.py`); instance/placement helpers in `catalog.py`. **Server-side tenant/site scope is a hard authz boundary** (ADR-0028), test-covered — a single service-token scope is fragile, a backend bug exposes every tenant.
- **Content:** Media Function instance inventory — count + placement (namespace/node/site) + `lifecycle:*` **and** observed runtime health / drift warning. **Observed-health is sourced from label-based discovery (concern (h): ADR-0038 / `dmf-promsd`), not the NetBox tag** — that is the declared-vs-observed distinction made concrete. **Honest copy:** title "Media Workloads", subtitle "Media Function instances — flow graph deferred" (avoid the assembly/composition vocabulary trap; the page is an inventory before it is a true Workload/assembly view).
- **Triggers (console-first, so the dynamism is legible):** a **"Sync Catalog"** button → fires `catalog-reconcile` (definition/workflow reconcile; shows AWX job id/status inline); **"Clear for Deployment" / Deploy** → instance reconcile. **Scheduled poll** as a safety net (not the demo path). **Webhooks deferred** (Forgejo/NetBox webhooks add auth/retry/idempotency/replay — after the core is correct).

## 7. Deletion / prune semantics (authoritative but safe)

- Removing a catalog entry while instances are **active** → **mark deprecated/disabled, block new launches**; **require teardown before** deleting JTs/RBAC/charts. **Never silently uninstall a running workload because a git branch changed.**
- Prune of *inactive* stale resources (JTs, RBAC, mirrored charts) **is** authoritative — else Org-Execute keeps stale JTs launchable by API even when the console hides them.

## 8. Adversarial risks → guardrails (carry into the build)

- **NetBox tags can lie.** Show declared-vs-observed; the Media Workloads page must overlay runtime health, not trust the tag.
- **`ipam.Service` is weak for multiple instances.** v1 one-per-function; record the instance-identity debt.
- **Single service-token tenant scope is fragile.** Hard backend authz + tests → route through `Security & Secrets`.
- **Dynamic deploy = code execution.** First-party only for v1; enumerate the 3rd-party trust gate as explicit future work.
- **Reconcile is not transactional.** Status object + idempotent phases + last-successful-sync; the console shows partial-sync.
- **Function #2/#3 is the real test of genericity.** If nmos keeps a special role and mxl keeps bespoke playbooks, we have two handcrafted demos, not a dynamic catalog — hence the two-function acceptance bar.

## 9. Sequence (the build order)

> **Actuator-dependent:** this is the **Argo-green** path (§3a recommendation). If the spike (step 0) is **red**, fall back to the hand-built AWX reconcile-controller and steps 4/5/7 below apply as written; if **green**, those collapse into Argo per §3a's "net effect."

0. **Argo viability spike — a real KILL-SWITCH, not a ritual** (do this *first*; do not commit the actuator before it). Install minimal internal-only Argo on the sandbox; wire a Forgejo repo credential (+ internal CA/cert) and one admin-owned AppProject; create **one static `mxl-hello` Application** pulling its **chart from in-cluster Zot**. **Pass criteria (all must hold):** Argo reports **Synced + Healthy at the expected git revision**; chart **and image** pull from Zot; a **dmf-cms/Argo-token Sync call** succeeds; namespace/RBAC creation works without Argo holding excessive cluster perms; total stays **within an explicit node-memory budget** on the 10 GiB node. **If any of repo-auth/certs / Zot OCI access / RBAC / footprint is ugly → STOP and revert to the AWX reconcile path. Never run both.**
1. **State the v1 contract** (§2) at the top of the implementation.
2. **Generic catalog validation + reconcile data-model** — read `dmf-media/catalog/`, validate schema, compute the desired set, owner-label, produce a dry-run diff + the status object (git-rev + desired-set hash).
3. **Generic NetBox lifecycle helper** in `dmf-runbooks` — used by both nmos-cpp and mxl-hello; retire the nmos-only role path. (Gap #3, generalized.)
4. **Catalog AWX Org + Org-Execute** grant to `dmf-cms-svc`; move/create catalog JTs there; keep infra/health-check JTs in Default. (Gap #1, structural.)
5. **Namespace/RBAC reconcile** — shared launcher SA + target-ns RoleBindings + pod-manager; launchers stop creating namespaces. (Gap #2, generalized.) **+ ESO `ExternalSecret` reconcile** in the target namespace from the entry's secret references (concern (g)).
6. **Artifact reconcile** — mirror declared charts + images GHCR→Zot; fail visibly on missing/private/digest-mismatch.
7. **JT reconcile** — create/update desired launch/finalise JTs from the catalog; disable/delete stale; safe active-instance handling.
8. **dmf-cms dynamic** — backend reads the live catalog read-model + NetBox runtime; add the "Sync Catalog" trigger → AWX; show job status; **drop the baked-ConfigMap dependency** for the demo path.
9. **Media Workloads page** — backend-enforced scope; count + placement + lifecycle + observed health/drift (observed-health from label discovery, concern (h)); honest copy.
10. **Prove with two functions** — nmos-cpp (baseline) + mxl-hello (newly added/updated) through the **same** reconcile path with **no per-function infra edits**; then remove/disable mxl-hello and verify the console hides/disables it and `dmf-cms-svc` cannot launch the stale JTs by API.

## 10. Verification (end-to-end, single-node sandbox)

Run the §0 acceptance loop, plus: (1) `catalog-reconcile` status object reflects the committed git-rev + desired-set hash; (2) an out-of-scope user does **not** see the Media Workloads entries (backend-enforced); (3) the two-function proof passes with zero function-specific infra edits after the reconcile mechanism exists; (4) deleting an entry with an active instance is *refused* (deprecate + require teardown), not a silent uninstall.

## 11. Critical files (representative)

- **Reconcile:** new `dmf-infra/k3s-lab-bootstrap/playbooks/lifecycle/catalog-reconcile.yml` (+ `tasks/`), evolving from `operate-catalog-drift.yml` / `catalog-drift-check.yml`.
- **Org / RBAC:** `dmf-infra/.../roles/stack/operator/awx-integration/` — catalog Org + Org-Execute + namespace/RBAC reconcile; supersedes the per-JT `697 cms_awx_catalog_job_templates` list and the per-function `nmos-cpp-launcher` Role.
- **Lifecycle helper:** new shared role under `dmf-runbooks/roles/`; launchers `dmf-runbooks/playbooks/launch|teardown-<key>.yml` assume namespace/RBAC.
- **Console:** `dmf-cms/src/dmf_cms/{main.py,catalog.py,settings.py}` + `frontend/src/pages/MediaWorkloads/` + `Sidebar.tsx`.
- **Catalog defs:** `dmf-media/catalog/*.yaml`, `dmf-media/charts/*`.

## 12. Out of scope (deferred, named)

Flow/composition graph + canvas; cross-host fabrics multi-node; 3rd-party contribution + its trust gate; per-user NetBox tokens; multi-instance instance-identity; webhook triggers; continuous watch loop; the CRD/operator end-state (with ADR-0027's promotion criteria). The formal **ADR** for this model is written once the two-function demo proves it.
