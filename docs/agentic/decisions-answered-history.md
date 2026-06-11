# DMF Agentic Harness — Decisions Answered (audit trail)

> **Audience**: Anyone auditing why the harness or operator chose option X
> for an ADR-worthy decision. This file is append-only history.
>
> **Authority**: Read-only archive of `decisions-open.md` entries that
> have been **answered and applied**. Entries are moved here once
> `Status: answered` is set AND any "Applied" downstream work has landed,
> so `decisions-open.md` reflects only the forward queue.
>
> **Workflow**:
> 1. Operator answers an entry in `decisions-open.md` (`Status: answered …`).
> 2. Backlog or downstream work consumes the answer and ships.
> 3. The next harness session (or a human convergence pass) moves the
>    answered entry from `decisions-open.md` into this file, preserving
>    the full text. The audit trail stays intact; the forward queue stays
>    short.
>
> **Distinct from**: `autonomous-decisions.md` (orchestrator-resolved
> choices that never required operator input).

---

## Seed gates (pre-existing from source plans)

Six decisions that existed independently of the harness — already
pending operator action in the source plans before kickoff 2026-05-12.
Surfaced in `decisions-open.md` as the operator's first-glance inbox.

---

### `adr-0020-promote`

**Surfaced**: 2026-05-12 (seeded at kickoff).
**Blocks**: Tier A.1, Group B Phase 0 (LICENSE/NOTICE attribution rests on
the deployment-mode framing), Group D enumeration.

**Question**: Promote [ADR-0020](../decisions/) from `Proposed` to `Accepted`
with mode declaration?

**Options**:
- **A. Mode A only** (OSS self-host) — *recommended default*. Smallest
  surface; minimum compliance burden; matches current operational reality.
  Tier B (managed) and Tier C (flypack) become future ADRs.
- **B. Mode A + Mode B** — declare managed-service intent now. Adds Tier B
  compliance commitments (HA OpenBao, customer-side quorum, SLA-bearing
  audit retention). Heavier today, faster path to commercial offering later.
- **C. All three** — A + B + C. Most ambitious; commits to flypack
  hardware-bundled distribution. High coordination cost; defer unless a
  flypack partner is imminent.

**Operator note**:

```
Status: answered 2026-05-12 — A. Mode A only. Experiment phase; no managed-service or flypack partner yet. B and C become future ADRs when there's a concrete driver.
```

**Applied** 2026-05-23: ADR-0020 amended in place — status becomes
"Accepted (Mode A); Proposed (Mode B, Mode C)" with an Amendment 2026-05-23
section spelling out what flips on Mode-A promotion and what does not.
ADR-0027 cross-ref to ADR-0020 clarified to specify Mode B (not generic
"Accepted") as the trigger.

---

### `github-org-name`

**Surfaced**: 2026-05-12 (seeded at kickoff).
**Blocks**: Release Phase 2 (`bin/sync-to-github.sh` push gate setup; GitHub
remote configuration on each public repo).

**Question**: What is the GitHub org name for the first public push?

**Options**:
- **A. `dmfdeploy`** — *recommended default*. Matches the umbrella repo
  name; consistent with current Forgejo posture.
- **B. Personal namespace** (e.g. `github.com/<operator-handle>/dmf-*`) —
  fast to set up; less professional appearance; harder to migrate to an
  org later because of fork-history quirks.
- **C. New org name** — operator picks something else; this issue captures
  the choice.

**Operator note**:

```
Status: answered 2026-05-12 — A. `dmfdeploy`. Matches umbrella and Forgejo namespace.
```

**Applied** 2026-05-22: `github.com/dmfdeploy/dmf-runbooks` is the first
public DMF repo. Pipeline live (LAN Forgejo push-mirror → GitHub → per-env
pull-mirror). Same org will host the remaining 5 public-target repos as
Move 7 lands.

---

### `move1-d1` — NMOS registry implementation

**Surfaced**: 2026-05-04 (in source task plan); re-surfaced 2026-05-12 at
harness kickoff.
**Source**:
[`docs/plans/dmf-platform-move-1-task-2026-05-04.md`](../plans/dmf-platform-move-1-task-2026-05-04.md)
§"Decision gates".
**Blocks**: Move 1 Piece 4 (NMOS provision-side work).

**Question**: Which NMOS registry implementation for the v1 spike?

**Options**:
- **A. Sony nmos-cpp built from source via Conan** — *recommended default*.
  Reference implementation; well-documented; ARM64-clean. ~1 day build cost
  the first time, cached after.
- **B. Pre-built nmos-cpp container from a third-party registry** — faster
  start; introduces an external dependency on an image we don't control.

**Operator note**:

```
Status: answered 2026-05-12 — A. Sony nmos-cpp from source. Gate 2 already proved it works; build cost already paid.
```

**Applied** 2026-05-19 onward: arm64 NMOS-cpp registry + node images
built from Sony upstream (commit `8e2e17f`); published to GHCR; mirrored
to in-cluster Zot via Stage 4b. Lane B (ADR-0025) deploys them as the
NMOS Helm chart.

---

### `move1-d2` — `lifecycle-configure.yml` first implementation

**Surfaced**: 2026-05-04; re-surfaced 2026-05-12 at harness kickoff.
**Source**:
[`docs/plans/dmf-platform-move-1-task-2026-05-04.md`](../plans/dmf-platform-move-1-task-2026-05-04.md)
§"Decision gates".
**Blocks**: Move 1 Piece 2, Piece 5.

**Question**: Shape of the configure-side lifecycle wrapper for catalog
entries?

**Options**:
- **A. Tag-driven, single import per entry** — *recommended default*.
  Mirrors the existing `lifecycle-operate.yml` pattern; minimum cognitive
  load; one playbook per catalog entry tagged for selective invocation.
- **B. Catalog-driven dynamic discovery** — wrapper iterates the catalog at
  runtime; more flexible; harder to debug when a single entry fails.

**Operator note**:

```
Status: answered 2026-05-12 — A. Tag-driven, single import per entry. Mirrors lifecycle-operate.yml pattern; simpler debugging.
```

**Applied** 2026-05-17 (`dmf-infra@a891ecb`): `lifecycle-configure.yml`
shipped tag-driven; verified end-to-end on `aliyun-123` and again on
`g2r6-foa9`.

---

### `move1-d3` — AWX launcher pattern

**Surfaced**: 2026-05-04; re-surfaced 2026-05-12 at harness kickoff.
**Source**:
[`docs/plans/dmf-platform-move-1-task-2026-05-04.md`](../plans/dmf-platform-move-1-task-2026-05-04.md)
§"Decision gates".
**Blocks**: Move 1 Piece 3, Piece 6.

**Question**: Launcher playbook shape in `dmf-runbooks`?

**Options**:
- **A. `import_role:` per launcher** — concise; uses Ansible's import
  semantics; less explicit about `roles_path`.
- **B. `hosts:` + `roles:` with explicit `roles_path` config** —
  *recommended default*. Matches ADR-0014/0016 Path A pivot; explicit about
  where roles resolve from; AWX-friendly.

**Operator note**:

```
Status: answered 2026-05-12 — B. hosts: + roles: with explicit roles_path config. Matches ADR-0014/0016 Path A; AWX-friendly; explicit role resolution.
```

**Applied** 2026-05-06+ in `dmf-runbooks/playbooks/launch-nmos-cpp.yml`
and `finalise-nmos-cpp.yml`. ADR-0025 Lane B (2026-05-23) re-targets the
launcher into the in-cluster AWX EE pod but keeps the `hosts:` + `roles:`
shape.

---

### `move1-d4` — dmf-cms catalog source

**Surfaced**: 2026-05-04; re-surfaced 2026-05-12 at harness kickoff.
**Source**:
[`docs/plans/dmf-platform-move-1-task-2026-05-04.md`](../plans/dmf-platform-move-1-task-2026-05-04.md)
§"Decision gates".
**Blocks**: Move 1 Piece 7 (dmf-cms catalog page).

**Question**: Where does the dmf-cms catalog page read its data?

**Options**:
- **A. HTTP fetch from raw catalog file** in Forgejo — single source of
  truth at HTTP request time; introduces runtime dependency on Forgejo
  reachability from dmf-cms.
- **B. ConfigMap mounted at pod start** — *recommended default*. No runtime
  Forgejo dependency; standard k8s pattern; updates require pod restart
  (acceptable for catalog-class data).

**Operator note**:

```
Status: answered 2026-05-12 — B. ConfigMap mounted at pod start. No runtime Forgejo dependency; standard k8s pattern; pod restart acceptable for catalog-class data.
```

**Applied** 2026-05-12 (`dmf-cms@1b4c259` + `0addc19`) and live in v0.9.0
(`dmf-cms@8f9ba75`, deployed to `g2r6-foa9` 2026-05-23).

---

## Orchestrator-surfaced decisions

### `catalog-namespace-source-of-truth`

**Surfaced**: 2026-05-12 (orchestrator self-classification — Rule 5(a) public
surface change to catalog schema).
**Blocks**: Drift detector correctness (move1-p8 lands with a known gap;
will report false positives for any entry whose k8s namespace ≠
`entry.key | regex_replace('-', '_')`); future P8-style integration logic.

**Question**: Where should the catalog YAML's k8s namespace field live?

**Background**: P8 drift detector needs to know which k8s namespace to
query Helm releases in. Today:
- The catalog YAML (`dmf-media/catalog/nmos-cpp.yaml`) has NO namespace field
- The role (`dmf-runbooks/roles/nmos-cpp/defaults/main.yml`) defines
  `nmos_namespace: nmos`
- The drift detector qwen wrote derives namespace as
  `entry.key | regex_replace('-', '_')` → `nmos_cpp` (wrong; actual is `nmos`)

**Options**:
- **A. Add `provision.namespace` to catalog schema** — *recommended default*.
  Future-proof; one source of truth; tiny extension to schema doc + ADR-0013;
  one-field addition to nmos-cpp.yaml; one-line patch to
  catalog-drift-check.yml. Future catalog entries declare their namespace
  alongside chart name etc.
- **B. Add `nmos_namespace`-style default per role; drift check looks up
  via lookup('vars')** — keeps catalog schema lean; couples drift check
  to per-role variable conventions (brittle as roles evolve).
- **C. Use `kubernetes.core.k8s_info` to list workloads cluster-wide,
  match by chart-name label** — no schema change; depends on every chart
  setting `app.kubernetes.io/name=<chart-name>` consistently (fragile).
- **D. Defer; mark P8 as draft; revisit at write-up time (P9)** — cheapest
  for now; drift detector ships with known false-positive on nmos-cpp;
  P9 write-up captures the gap as a learning.

**Operator note**:

```
Status: answered 2026-05-12 — A. Add `provision.namespace` to catalog schema. Future-proof, one source of truth. Tiny schema change (one field in YAML, one line in drift check, one paragraph in ADR-0013).
```

**Applied** 2026-05-12 shift 8 tick 16 (claude):
- `docs/architecture/DMF Function Catalog Model.md` — schema example updated
- `docs/decisions/0013-media-function-catalog-model.md` — amendments §
- `dmf-media/catalog/README.md` — schema table row added
- `dmf-media/catalog/nmos-cpp.yaml` — `provision.namespace: nmos`
- `dmf-infra/k3s-lab-bootstrap/playbooks/lifecycle/tasks/catalog-drift-check.yml`
  — reads `entry.provision.namespace`, asserts presence before helm_info

---

## 2026-05-19 — Catalog Helm + EE-as-runtime pivot

Surfaced by the
[DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19](../plans/DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md)
§8. Six decisions, all answered 2026-05-19 with the recommended defaults
and ratified by the plan adoption. Applied across Lane A (2026-05-19) and
Lane B (2026-05-22 → 2026-05-23).

### `stage-4b-seed-mechanism`

**Surfaced**: 2026-05-19 (orchestrator self-classification, Rule 5(a/c) —
new bootstrap stage, multi-repo touch).
**Blocks**: Lane A of the converged plan; both Lane B and Lane C depend on
images being in Zot.

**Question**: How does the workstation push the AWX EE image, NMOS-cpp
images, and Helm charts into cluster-internal Zot during bootstrap Stage 4b?

**Options**:
- **A. Workstation Ansible playbook (`600-zot-seed.yml`)** — *recommended
  default*. Uses `community.docker` or `skopeo` to push from operator
  workstation. Mirrors playbook 650 (`dmf-cms-build-and-release`). Operator
  needs `docker`/`skopeo`/`helm` locally.
- **B. Dedicated `bin/seed-zot.sh`** — bash wrapper, no Ansible indirection.
  Less consistent with the rest of the bootstrap (Ansible-driven). Same
  workstation prerequisites.
- **C. In-cluster Job seeded by `kubectl cp`** — workstation cp's a tarball
  of `docker save` outputs + chart `.tgz` files into a Job pod; Job does the
  push from inside. No `docker` required on workstation. Most moving parts.

**Operator note**:

```
Status: answered 2026-05-19 — A. Workstation Ansible playbook (600-zot-seed.yml). Mirrors 650 (dmf-cms-build-and-release); Ansible-driven consistency with bootstrap.
```

**Applied** 2026-05-19+: `playbooks/630-zot-seed-platform.yml` is the Stage 4b
seeder. Skopeo-driven mirror from GHCR → in-cluster Zot.

---

### `dmf-media-build-and-release-skill`

**Surfaced**: 2026-05-19.
**Blocks**: Codifies how arm64 NMOS-cpp (and future media-function) images
get built and pushed to Zot. Plan can ship without it; skill timing only.

**Question**: Author a `dmf-media-build-and-release` skill now (mirroring
`dmf-cms-build-and-release`), or defer until a second media function lands?

**Options**:
- **A. Author now** — codify the NMOS arm64 build + push as a sanctioned
  skill. Sets pattern for future functions; future-proof.
- **B. Defer** — *recommended default* per "no premature abstraction".
  Document the NMOS build informally in the plan; promote to skill when a
  second media function (e.g. MXL) needs the same flow.

**Operator note**:

```
Status: answered 2026-05-19 — B. Defer. No premature abstraction; promote to skill when MXL (or other second function) needs the same flow.
```

**Applied** — no skill authored. Promote when MXL (or other second
function) needs the same flow.

---

### `adr-0025-scope`

**Surfaced**: 2026-05-19.
**Blocks**: Whether the placeholder ADR-0025 evolves into one broad
decision record or splits into two.

**Question**: ADR-0025 scope — broad converged (NMOS Helm + EE-as-runtime
+ Stage 4b seeding + runner-pod-image alignment) or narrow (NMOS Helm only)
with a separate ADR-0026 for the runner-pod side?

**Options**:
- **A. Broad ADR-0025** — *recommended default*. One decision record
  captures the whole architectural shift. Larger ADR but the convergence
  story stays together.
- **B. ADR-0025 + ADR-0026** — split by lane. Each ADR is smaller; the
  convergence story spans both.

**Operator note**:

```
Status: answered 2026-05-19 — A. Broad ADR-0025. Convergence story stays together; matches the plan's §2 shape. Promote from Proposed to Accepted when Lane A ships with the EE image in Zot.
```

**Applied** 2026-05-23: ADR-0025 (broad scope) promoted from Proposed to
Accepted after Lane B's end-to-end success on `g2r6-foa9`. ADR-0026 ended
up being authored on 2026-05-20 for an unrelated topic (Provider Descriptors).

---

### `ee-build-host`

**Surfaced**: 2026-05-19.
**Blocks**: Lane A implementation — where the AWX EE image is built before
push to Zot.

**Question**: Where does the AWX EE image get built — operator workstation
or in-cluster Kaniko Job?

**Options**:
- **A. Operator workstation** — *recommended default* (operator has
  buildkit / podman set up already for dmf-cms; symmetric pattern).
- **B. In-cluster Kaniko Job** — no operator-side build prerequisites; one
  more moving piece during bootstrap.

**Operator note**:

```
Status: answered 2026-05-19 — A. Operator workstation (Colima docker-build). Symmetric with dmf-cms; no new cluster machinery; ansible-builder runs locally then push to GHCR / Zot.
```

**Applied** 2026-05-19: `dmf-infra/k3s-lab-bootstrap/ee/` builds locally
in operator's Colima `docker-build` profile; published to GHCR
(`ghcr.io/dmfdeploy/awx-ee:0.1.0`); Stage 4b mirrors to in-cluster Zot.

---

### `nmos-cpp-arm64-availability`

**Surfaced**: 2026-05-19 (operator note during plan discussion).
**Blocks**: Lane B execution sequencing (image build vs image push).

**Question**: Operator stated locally-built arm64 NMOS-cpp images already
exist. Confirm before plan execution. If yes, Lane B's "build" step
collapses to "push." If not, factor build time + tooling.

**Options**:
- **A. Confirm locally-built arm64 images exist and identify path** —
  *expected default* per operator's note.
- **B. Build from source on workstation arm64 builder** — if (A) is false.

**Operator note**:

```
Status: answered 2026-05-19 — A. Images present in Colima `docker-build` profile under the
operator's local registry namespace (path on operator workstation only — not in this doc per
the dmf-operator-identity gitleaks rule). Both built 2026-05-19 14:26, arm64/linux,
tag :0.1.0. Caveat: current Dockerfiles clone Sony upstream from `master` without SHA pin
(plan §5.1 violation for public publish). First publish path: tag as `0.1.0-dev` to GHCR
(package private); canonical `:0.1.0` public push happens after Dockerfile hardening +
rebuild in this session.
```

**Applied** 2026-05-19: hardened Dockerfiles pin Sony upstream at commit
`8e2e17f`; `:0.1.0` public canonical images at `ghcr.io/dmfdeploy/nmos-cpp-{registry,node}`.

---

### `zot-anonymous-read`

**Surfaced**: 2026-05-19.
**Blocks**: How in-cluster pods (runner pod, AWX EE pod) pull from Zot.

**Question**: Pull-secret strategy for in-cluster pulls from Zot's `dmf/*`
repos?

**Options**:
- **A. Anonymous read on `dmf/*` in Zot** — *recommended default*. Simplest;
  Zot config allows in-cluster pulls without auth on the `dmf/*` namespace.
  Push still requires auth. Zot ClusterIP is not exposed externally.
- **B. Per-namespace pull-secret injection** — every catalog namespace
  gets a pull-secret synced from a master secret. More moving parts; more
  secure in principle.

**Operator note**:

```
Status: answered 2026-05-19 — A. Anonymous read on dmf/* in Zot. Zot ClusterIP not externally exposed; push retains auth. Verify Zot config supports per-repo anonymous policy at Lane A implementation.
```

**Applied** 2026-05-22+: Zot config grants anonymous read on `dmf/*` and
`charts/*`; in-cluster pulls work without pull-secret injection. Push
retains auth.

---

### `awx-pod-placement`

**Surfaced**: 2026-05-19 post-codex-review.
**Blocks**: Lane B implementation — without this, the JT pod runs in
`ns: awx` under SA `default`. The May-6 SA-mount churn
(`f669415`..`e8bc0f4` in dmf-runbooks) was exactly this gap. **Lane B's
verification check `spec.serviceAccountName == <expected>` depends on the
answer here.**

**Question**: Which AWX mechanism routes `media-*` JT pods into the
catalog function's namespace with the right ServiceAccount?

**Options**:
- **A. SA in `awx` ns + cross-namespace RoleBinding** — JT pod stays in
  `awx` ns. RoleBinding subject `ns: awx, sa: nmos-cpp-launcher`; role lives
  in `ns: nmos`. EE pod runs in awx ns under awx-ns SA, acts on nmos ns
  resources. Still needs an AWX Container Group with
  `pod_spec_override.spec.serviceAccountName` to bind the JT to that SA.
  Simpler RBAC topology; less namespace boundary clarity.
- **B. SA in `nmos` ns + AWX Container Group with namespace override** —
  *recommended default*. Container Group's `pod_spec_override` sets
  `metadata.namespace: nmos` and `spec.serviceAccountName: nmos-cpp-launcher`.
  JT pod runs in the same namespace as the workload it manages. Cleaner
  boundary; more AWX-operator config; EE pod must be schedulable in `nmos`
  ns (image pull, network policies).

**Operator note**:

```
Status: answered 2026-05-19 — B. SA in target ns + AWX Container Group with namespace override. Cleaner namespace semantics; each function owns its namespace; matches the chart's RBAC home. Validation spike (60 min) recommended at Lane B start to confirm AWX-operator schedules EE pod into `nmos` ns correctly with image pull from Zot.
```

**Applied** 2026-05-22 → 2026-05-23: Container Group `pod_spec_override`
places `media-*` JT pods in `ns: nmos` under SA `nmos-cpp-launcher`.
Verified by ADR-0025 Lane B job 131 success.

---

### `grafana-local-admin-rename`

**Surfaced**: 2026-05-24 by Claude (pane 2), ADR-0028 follow-on step 3
(`adr0028-local-admin-sweep`).

**Blockers**:
- ADR-0028 §"Sanctioned exceptions" lists three pre-cleared carve-outs:
  Authentik `akadmin`, Zot `admin`, **Grafana `admin`**. Touching
  Grafana's local admin name interacts with the binding text of an
  Accepted ADR.

**Context**:
ADR-0028 follow-on step 2 (AWX) landed `dmf-infra@c426dc0`. Step 3
renamed NetBox + Forgejo to dedicated break-glass identities
(`netbox-break-glass`, `forgejo-break-glass`). The per-app feasibility
survey §5 item 2 named Grafana alongside NetBox + Forgejo for the rename
sweep:

> "NetBox, Forgejo, Grafana: rename local admin to non-colliding
> break-glass identity (mirror of #1). Lower-risk than AWX because no
> shadow exists today; the rename is a cleanup that crystallises the
> slogan."

But ADR-0028 §"Sanctioned exceptions" pre-clears Grafana `admin` as a
permanent carve-out with the rationale "Helm chart default; login form
disabled; OIDC is the day-to-day path; local admin is dormant unless
OIDC is broken." Survey §3.6 echoes the same Helm-chart-default
rationale.

The contradiction between survey §5 item 2 (rename) and ADR-0028
§"Sanctioned exceptions" (Grafana `admin` is pre-cleared) had to be
resolved by the operator before any Grafana edit landed.

**Current Grafana posture** (from `roles/base/grafana/defaults/main.yml`
+ survey §3.6):
- `grafana_admin_password` is set via OpenBao; no `grafana_admin_user`
  override is present, so the chart default `admin` flows through.
- `grafana_oidc_enabled: true`, `grafana_oidc_disable_login_form: true`,
  `grafana_oidc_auto_login: true`, `grafana_oidc_admin_group: ops-admin`.
- C4 ("no routine break-glass") is already satisfied in this posture:
  human access lands on `/login`, which immediately redirects to
  Authentik. Local `admin` is not reachable through the UI in steady
  state.

**Question**: Should Grafana's local admin username be renamed to
`grafana-break-glass` (mirroring AWX/NetBox/Forgejo), and if so does
the sanctioned exception list in ADR-0028 require amendment?

**Options**:

1. **Keep ADR-0028 exception list unchanged; no Grafana rename.**
   *(Recommended default — minimum-change, preserves Accepted ADR text.)*
   Rationale: C4 is already satisfied because the login form is disabled
   and OIDC auto-redirect means `admin` is dormant in steady state. The
   sanctioned exception list pre-cleared Grafana `admin` specifically
   because the Helm chart default is operationally inert. Renaming would
   add no security benefit, would require either chart override or
   `grafana_admin_user` injection (chart accepts it via `adminUser:`
   value), and would touch ADR-0028's binding text.
2. **Rename Grafana local admin to `grafana-break-glass`; amend
   ADR-0028 to drop Grafana from the sanctioned exception list.**
   Rationale: structural consistency with AWX/NetBox/Forgejo.
3. **Rename Grafana but record it as a survey-recommended architectural
   rename WITHOUT removing the carve-out.**
   Rationale: belt-and-suspenders; risk: exception list becomes muddier.

**Operator note**:

```
Status: answered 2026-05-25 — Option 1. Keep ADR-0028's Grafana `admin`
exception and do not rename. Grafana already satisfies C4 because the
login form is disabled and OIDC auto-login redirects routine humans to
Authentik. The local `admin` account is dormant break-glass only; a rename
would add chart override surface without a meaningful security gain.
```

**Applied** 2026-05-25: no Grafana code change. ADR-0028 and the
feasibility survey were amended to record that Grafana was evaluated and
intentionally retained as a sanctioned exception while AWX, NetBox, and
Forgejo use dedicated break-glass local-admin names.
