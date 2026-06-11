---
status: historical
date: 2026-06-05
---
# DMF Dynamic Catalog & Deployable-Workflow Mechanism — Discussion Notes

**Date:** 2026-06-05
**Status:** DISCUSSION NOTES (not a plan yet) — "discuss further" per operator. Captures the
problem, the live evidence, the candidate mechanisms, and open questions.
**Trigger:** the single-node `mxl-hello` live verify (env `u1u3-c7rz`) exposed that adding a
deployable media function to the catalog is **bootstrap-coupled** — it needs laptop playbook
re-runs and hits a chain of "hardwired to nmos-cpp" gaps.
**Inputs:** Claude + codex cross-check (AWX RBAC / org-scoping); ADR-0025 (in-cluster Helm /
EE-as-runtime), ADR-0027 (Catalog Operator + MediaFunctionInstance, deferred), ADR-0028
(svc-token least-priv), ADR-0037 (instances in NetBox).
**Related:** `DMF MXL-Hello Single-Node Catalog Control-Chain Validation Plan 2026-06-05.md`,
[[project_catalog_jt_rbac_two_list_gap]].

---

## 1. The question

How do we **dynamically add / update / remove a deployable media function** (a catalog item
+ its deploy workflow) **at runtime** — visible and deployable from the console — **without
re-running bootstrap playbooks from a laptop**? And critically: how is the *deploy workflow
itself* dynamically defined/updatable, not just the catalog metadata?

## 2. Why it's static today (the coupling map)

Adding one media function today touches **six** things, all git-defined + laptop-applied:

| # | Artifact | Where / playbook | Coupling |
|---|---|---|---|
| 1 | Chart → cluster Zot | 630 (skopeo GHCR→Zot) | chart must be mirrored before deploy |
| 2 | AWX Job Templates (launch/finalise) | 693 from `awx_catalog_job_templates` | the deploy "workflow" |
| 3 | JT **Execute grant** to `dmf-cms-svc` | 697 `cms_awx_catalog_job_templates` (separate list) | console can launch the JT |
| 4 | **Launcher SA namespace RBAC** | awx-integration `nmos-cpp-launcher` Role (ns `nmos` only) | the EE pod can deploy into the function's namespace |
| 5 | Catalog entry → NetBox | 691 netbox-sot | lifecycle status |
| 6 | Catalog definition → console | 650 (baked ConfigMap) | console reads a *baked* file, not live |

## 3. Live evidence — the failure chain (mxl-hello, 2026-06-05)

Two real bugs surfaced, **same root pattern: the catalog launcher infra was hardwired to the
first catalog item (nmos-cpp) and never generalized.**

1. **Console Deploy → 404** (coupling #3). The mxl-hello JTs existed (693 created them), the
   catalog had the entry, the chart was in Zot — but `dmf-cms-svc` had **no role** on the new
   JTs, because the 697 grant list is a *separate hardcoded list* that only named nmos-cpp.
   AWX hid the JTs from the svc token → `lookup_job_template_by_name` → None → 404, **before
   AWX was even invoked.** Live fix: additive `execute_role.members.add` on the 2 JTs. Code
   fix: dmf-infra `fd597b4` (added MXL JTs to the 697 list). **Gotcha:** re-running 697 does
   NOT self-heal a live env — it skips RBAC when the AWX token already exists.
2. **AWX job → 403** (coupling #4). The deploy then launched and failed at "Ensure MXL
   namespace exists": `serviceaccount nmos:nmos-cpp-launcher cannot get namespaces "mxl"`. The
   launcher SA has a **Role scoped to `nmos` only** and no namespace-level permission, so it
   can't operate in `mxl`. Live fix (least-priv, operator-approved): pre-create `mxl`, a
   namespace-scoped workload Role/RoleBinding for the SA in `mxl`, and a read-only namespaces
   ClusterRole. **No code change to the launcher yet.**

**Lesson:** each new catalog item silently needs *creation + 3 separate authorizations*
(JT create, JT Execute grant, launcher namespace RBAC) + chart-mirror + NetBox + console. A
"dynamic catalog" is really a **reconcile problem across all six**, not just metadata.

## 4. Candidate mechanism (three moves)

**Move 1 — catalog as a live registry (NetBox = SoT).** Console reads catalog *definitions*
from NetBox at runtime, not a baked ConfigMap (650). Add/remove a NetBox catalog entry →
console reflects it immediately. Kills couplings #5/#6. (Extends ADR-0037's instances-in-NetBox
to definitions.)

**Move 2 — reconcile in-cluster, triggered not laptop-run.** The provisioning (chart→Zot, JT
create, JT grant, launcher RBAC) becomes an in-cluster reconcile:
- **Now (pragmatic):** an AWX **"catalog-reconcile" Workflow** — a slimmed, idempotent,
  **always-run** version of 630/693/697/launcher-RBAC. Trigger via Forgejo webhook on
  catalog-repo change (GitOps), a console "Sync catalog" button, or an AWX schedule. AWX is
  the in-cluster engine — "automate the playbooks in-cluster," no laptop.
- **Later (proper):** the **ADR-0027 Catalog Operator** — a controller that watches catalog
  entries (NetBox/CRDs) and continuously converges JTs + charts + RBAC + console. End-state.

**Move 3 — org-scoped RBAC (codex option D).** Put catalog-launcher JTs in a dedicated AWX
**Organization**; grant `dmf-cms-svc` **Org Execute once**. Any JT added to that org is
auto-executable; coupling #3 drops out of the reconcile loop. AWX 24.6 supports org-scoped
JobTemplate Execute (DAB role assignments). Infra/693-class JTs stay in the Default org →
ADR-0028 least-priv preserved.

## 5. What "dynamically updatable deployable workflow" specifically requires

Beyond adding *metadata*, the **deploy workflow itself** must be dynamically definable. Each
catalog entry already declares its workflow surface (`configure.playbook` +
`configure.awx_job_template`, `finalise.*`, `provision.chart/image`, `provision.namespace`).
The reconcile must, **idempotently and authoritatively** (i.e. also *remove/disable* on
delete — codex's guardrail, else org-Execute keeps stale launchability alive), converge:

- (a) **JT lifecycle** — create/update/**delete** the launch+finalise JTs from the catalog set.
- (b) **JT authorization** — solved structurally by Move 3 (org membership), not per-JT grants.
- (c) **Launcher namespace RBAC** — per catalog `provision.namespace`, ensure the launcher SA
  has a Role there (the #4 gap, generalized). Either the reconcile creates a Role per catalog
  namespace, or a namespace-scoped launcher SA per function.
- (d) **Chart availability** — mirror `provision.chart` GHCR→Zot (the 630 step) on add; prune
  on remove.
- (e) **NetBox entry + console** — Move 1 (live read) makes this automatic.

The **deploy workflow as data**: the catalog YAML *is* the workflow definition; the reconcile
turns it into live AWX JTs + RBAC + chart. Updating a catalog entry (e.g. new chart version,
changed playbook) → reconcile re-converges the JT/chart. This is the "dynamically updatable
deployable workflow mechanic" — the catalog repo (or NetBox) is the single source, the
in-cluster reconcile is the actuator, and nothing is hand-applied.

## 6. Open questions (for the discussion)

1. **Catalog SoT:** NetBox vs a Git repo (GitOps) vs CRDs? ADR-0037 leans NetBox; GitOps gives
   change-history + webhooks for free. Possibly NetBox-as-read-model fed by Git.
2. **Reconcile actuator:** AWX workflow (reuse playbooks, fastest) vs a real operator
   (ADR-0027, cleanest, more build). Stage AWX-workflow → operator?
3. **Trigger:** Forgejo webhook (GitOps) vs console button vs schedule vs operator-watch.
4. **Authoritative reduction:** how aggressively to delete/disable removed JTs/charts/RBAC
   (codex: org-Execute preserves API launchability of stale JTs unless reconciled away).
5. **Launcher RBAC model:** one shared launcher SA with reconcile-managed per-namespace Roles,
   vs a per-function namespace-scoped launcher SA. Least-priv vs simplicity.
6. **Namespace ownership:** should the launch playbook create its namespace (needs cluster
   perms) or should the reconcile pre-create per-catalog namespaces (cleaner, narrower SA)?
   The mxl-hello 403 argues for reconcile-pre-created namespaces.
7. **The two-list / always-run lesson:** any reconcile must put RBAC in an always-run path
   (697 skipping RBAC when the token exists is exactly the trap to avoid).

## 7. Immediate vs durable (what's done now)

- **Done now (live unblock only):** JT Execute grant (live + 697 code fix `fd597b4`) and
  launcher `mxl` RBAC (live, least-priv, **no code change**). These get mxl-hello deployable
  on `u1u3-c7rz`; they are NOT the durable mechanism.
- **Durable:** Moves 1–3 above. To be designed in the follow-up discussion and likely captured
  as an ADR superseding the static catalog model (and folding in ADR-0027).
