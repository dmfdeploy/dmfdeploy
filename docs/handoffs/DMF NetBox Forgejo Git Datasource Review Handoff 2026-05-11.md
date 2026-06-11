# DMF — NetBox ↔ Forgejo Git Datasource Review Handoff (2026-05-11)

## Purpose

A coding agent committed —
**`feat(netbox): add git-backed external datasource from Forgejo`**.
A follow-up commit addressed all 6 review issues from §3. After both commits
landed, `git filter-branch` rewrote author identity across all post-`v0.1.0`
commits on `dmf-infra`, so SHAs changed; the table below lists the
operator-facing **current** SHA and the **pre-rebase** SHA for cross-reference
with earlier session notes.

| Role | Current SHA (on `main`) | Pre-rebase SHA (in reflog only) |
|---|---|---|
| Original feature | `660f0d2` | `5afcb7e` |
| Review-fix follow-up | `3b0db13` | `c162301` |
| Identity scrub | `fe6767c` | `7723af5` |

State: **all 6 review issues resolved**, scrub passes, ready for cluster
validation. Branch is `ahead 21 / behind 17` of `origin/main` — publish path
is the orphan-rebase to `v0.1.0` (see the 2026-05-07 Public Publish Readiness
Handoff), not a fast-forward push.

Read this end-to-end before touching the two roles
(`forgejo-bootstrap`, `netbox-sot`) or running the bootstrap on the cluster.

---

## 0. Boot ritual (do not skip)

This is a multi-repo change. Before editing anything:

```bash
cd dmfdeploy/
git fetch && git pull
bin/generate-status.sh --no-fetch        # refresh STATUS.md
```

Then read in order:

1. [`STATUS.md`](../../STATUS.md) — current state across all six repos.
2. [`CLAUDE.md`](../../CLAUDE.md) — the umbrella boot ritual and workspace map.
3. [`docs/decisions/INDEX.md`](../decisions/INDEX.md) — note ADR-0014, ADR-0016
   (Path A for catalog launchers, AWX project layout) and ADR-0019 (SLB
   backend registration). None of them block this work, but several constrain
   adjacent moves.
4. The most recent file in [`docs/handoffs/`](.) — typically the entry just
   before this one.
5. If you are about to **run** the playbook against the cluster, also read
   §0 of:
   - skill `dmf-cluster-access` (kubectl context discipline)
   - skill `dmf-openbao-unseal` (OpenBao must be unsealed before
     `netbox-sot` can read the Forgejo svc token)

Verify cluster context **before** any cluster operation:

```bash
kubectl config current-context        # must be hetzner-arm
```

The local RPi homelab at `<lan-ip>` is **not** the DMF cluster — never use it.

---

## 1. What shipped in `dmf-infra@660f0d2` (orig: `5afcb7e`)

Commit:
[`660f0d2`](../../dmf-infra) — `feat(netbox): add git-backed external datasource from Forgejo`

Eight files, 523 insertions:

```
k3s-lab-bootstrap/roles/stack/operator/
├── forgejo-bootstrap/
│   ├── defaults/main.yml                                 # +1  (netbox-data repo)
│   ├── tasks/main.yml                                    # +168 (seed 5 example files)
│   └── templates/netbox-data/
│       ├── config-contexts/sites.yaml.j2
│       ├── export-templates/cable-list.csv.j2.j2
│       ├── policy/conventions.yaml.j2
│       └── templates/device-cisco-base.j2.j2
└── netbox-sot/
    ├── defaults/main.yml                                 # +15 (datasource vars)
    └── tasks/main.yml                                    # +194 (create/sync DS)
```

### Behaviour

1. **`forgejo-bootstrap`** now creates one more private repo — `netbox-data` —
   under the `forgejo-svc` user, and seeds it with five example files
   (`config-contexts/sites.yaml`, `templates/device-cisco-base.j2`,
   `export-templates/cable-list.csv.j2`, `policy/conventions.yaml`,
   `generated-inputs/README.md`) plus a top-level README. Each seed task is
   GET→404→POST, so operator edits made later via PR are preserved on rerun.

2. **`netbox-sot`** now wires up a **NetBox core Data Source** of type `git`
   pointing at that Forgejo repo. The role:
   - Reads `forgejo_svc_token` from OpenBao at
     `secret/apps/forgejo/runtime`.
   - Assembles a git URL of the form
     `https://forgejo-svc:<token>@<forgejo-host>/forgejo-svc/netbox-data.git`.
   - POSTs `/api/core/data-sources/` with branch `main`, sync interval
     1440 min (24 h), ignore rules `*.md` + `.gitkeep`.
   - Triggers an initial sync (`POST .../sync/`) and waits up to ~5 min for
     completion before asserting `status == "completed"`.

3. **Five use cases** for the synced repo (per commit message):
   - `config-contexts/` — site/role/platform/tenant variables
   - `templates/` — device config (Cisco/Arista/Juniper), ZTP
   - `export-templates/` — CSV/Markdown reports, cable lists
   - `policy/` — NTP, DNS, VLAN conventions, PTP, SNMP profiles
   - `generated-inputs/` — machine-generated YAML from discovery scripts

### Review verdict

- **Public-repo hygiene** — passes `bin/scrub-public-repos.sh dmf-infra`
  (clean across secret / topology / identity / context layers).
- **Convention compliance** — no real cluster IPs, hostnames, or operator
  identity in tracked content. One style nit (see §3).
- **Idempotency** — repo creation and file seeding are correctly guarded;
  unchanged reruns are no-ops.
- **Authoritative behaviour** — the cluster is the source of truth, but the
  role only creates the data source if a row with the same name does **not**
  already exist (see §3 issue 1).

---

## 2. Architecture context

```
                     ┌────────────────────────┐
                     │  operator PRs          │
                     │  (Forgejo UI)          │
                     └──────────┬─────────────┘
                                ▼
   ┌────────────────────────────────────────────────────────┐
   │  Forgejo: forgejo-svc/netbox-data (private)            │
   │  seeded by forgejo-bootstrap on every run, GET→404→POST│
   └──────────────────────┬─────────────────────────────────┘
                          │  https + token (read:repository)
                          ▼
   ┌────────────────────────────────────────────────────────┐
   │  NetBox core Data Source "forgejo-netbox-data"         │
   │  type: git, branch: main, sync_interval: 24h           │
   │  creates DataFile rows in the NetBox DB                │
   └──────────────────────┬─────────────────────────────────┘
                          ▼
   Config contexts · Export templates · Jinja2 device templates ·
   Policy YAML consumed by automation pipelines
```

Layer/vertical placement (per
[`DMF EBU Mapping (2026-04-25).md`](../architecture/DMF%20EBU%20Mapping%20%282026-04-25%29.md)):
both roles sit in the **Operator** stack, Layer 5 (control plane), Lifecycle
**Operate**. The data source feeds the Catalog / Provisioning verticals
downstream.

---

## 3. Original review findings (all resolved by `3b0db13`)

These six items were raised during the first review of `660f0d2`. The
follow-up commit `3b0db13` (originally `c162301` pre-filter-branch)
addresses each one — diff verified line-by-line against the diagnoses
below. Line numbers cited are **pre-fix, historical**; the fix
restructured the netbox-sot tasks file (+70 lines, new section comments
added), so live line numbers no longer match.

### Issue 1 — **RESOLVED in `3b0db13`** — token embedded in `source_url`, no rotation path

**Where (pre-fix):**
`dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox-sot/tasks/main.yml:918-930`
(`Assemble NetBox datasource URL after token resolution`).

**Symptom:** The Forgejo svc token is embedded directly in
`source_url` as `https://forgejo-svc:<token>@host/...`. NetBox stores
`source_url` in its database and renders it in the admin UI. Two
consequences:

1. Anyone with NetBox read access to the Data Source row can read the
   Forgejo svc token in plaintext. The token is `read:repository` +
   `write:repository` scope on `forgejo-svc` — not catastrophic but it
   defeats OpenBao’s point.
2. When `forgejo_svc_token` is rotated (e.g. by re-running
   `692-forgejo-bootstrap.yml` with no existing token), `netbox-sot`
   re-runs but the **create-datasource task is gated on
   `netbox_sot_datasource_name not in existing names`**. It is skipped.
   No PATCH path exists. Sync starts returning `failed` silently.

**Recommended fix:** Use the NetBox v4 Data Source `parameters` field for
credentials (`{"branch": "...", "username": "...", "password": "..."}`)
instead of embedding them in `source_url`. Add a separate PATCH task that
runs unconditionally to keep parameters in sync with the current OpenBao
token. Doc:
<https://docs.netbox.dev/en/stable/models/core/datasource/>.

**How it was fixed:** `parameters.username` + `parameters.password`
populated on both POST (create) and a new unconditional PATCH task that
runs every play; `source_url` no longer carries credentials.

### Issue 2 — **RESOLVED in `3b0db13`** — vault-only fallback gap

**Where (pre-fix):** same file, lines 885-941.

**Symptom:** If `netbox_sot_persist_to_openbao` is false (i.e. the
operator is running with classic ansible-vault, not the OpenBao
break-glass file), the **Read Forgejo datasource token from OpenBao**
task is skipped (`when: netbox_sot_persist_to_openbao | bool`), so
`netbox_sot_forgejo_datasource_token` is never set, and the assert at
line 932 fires.

**Recommended fix:** Add a fallback before the assert:

```yaml
- name: Fall back to ansible-vault for Forgejo datasource token
  ansible.builtin.set_fact:
    netbox_sot_forgejo_datasource_token: "{{ vault_forgejo_svc_token | default('') }}"
  when:
    - netbox_sot_datasource_enabled | bool
    - not netbox_sot_persist_to_openbao | bool
    - netbox_sot_forgejo_datasource_token | length == 0
```

The rest of the role already uses this pattern for its own tokens —
this one task is the exception.

**How it was fixed:** the recommended fallback task was added verbatim,
and the assert fail-message now reads "OpenBao or vault" instead of
"OpenBao or defaults".

### Issue 3 — **RESOLVED in `3b0db13`** — `openbao-0` literal fallback

**Where (pre-fix):** same file, line 891: `_netbox_sot_openbao_pod | default('openbao-0')`.

**Symptom:** Harmless today because the surrounding task is gated on
`netbox_sot_persist_to_openbao | bool` and the pod-discovery block sets
`_netbox_sot_openbao_pod` whenever that gate is true. But the literal
`openbao-0` will be wrong the moment OpenBao is rescheduled with a new
ordinal or moved to a different StatefulSet name. Recommend removing the
default entirely so the task fails loudly if the discovery step was
skipped.

### Issue 4 — **RESOLVED in `3b0db13`** — style nit: `dmf.internal` vs `dmf.example.com`

**Where (pre-fix):**
`forgejo-bootstrap/templates/netbox-data/config-contexts/sites.yaml.j2:14-21`
and `templates/device-cisco-base.j2.j2:8`.

The platform-wide convention in
[`CLAUDE.md`](../../CLAUDE.md) is the fictitious domain
`dmf.example.com` (RFC 2606). The original template used `dmf.internal`
for its NTP/DNS examples. Not a leak — `dmf.internal` is also
fictitious — but inconsistent with the rest of the docs.

**How it was fixed:** three hits in `sites.yaml.j2` and one in
`device-cisco-base.j2.j2` rewritten to `dmf.example.com`.

### Issue 5 — **RESOLVED (cosmetic, no change needed)** — mirror loop runs on empty dict

**Where:** `forgejo-bootstrap/tasks/main.yml:258-272`.

`forgejo_mirror_repos` was emptied to `{}` in the identity-scrub commit
(`fe6767c`, originally `7723af5` — public publish prep). The PATCH-mirror
loop now runs zero iterations on every play. Cosmetic only; safe to leave.

### Issue 6 — **RESOLVED in `3b0db13`** — `generated-inputs/README.md` is intentionally ignored

The seeded ignore rules are:

```
*.md
.gitkeep
```

So the only file under `/generated-inputs/` will be skipped by NetBox
sync. That is the *intent* — the dir is reserved for machine-generated
YAML. Worth a one-line comment in the seeded README so the convention
sticks.

**How it was fixed:** the README body now includes
"NOTE: \*.md files are ignored by the datasource ignore_rules. Use
.yaml or .yml extension for files that should be synced."

---

## 4. How to validate end-to-end

Run from `dmf-env` (the private inventory wrapper):

```bash
cd dmf-env/
bin/run-playbook.sh hetzner-arm \
  ../dmf-infra/k3s-lab-bootstrap/playbooks/692-forgejo-bootstrap.yml
bin/run-playbook.sh hetzner-arm \
  ../dmf-infra/k3s-lab-bootstrap/playbooks/691-netbox-sot.yml
```

Then check:

```bash
# 1. Forgejo repo exists and is seeded
ssh k3s-admin@<control-node-public-ip> \
  'sudo k3s kubectl -n forgejo exec deploy/forgejo -- \
     curl -s -u forgejo-svc:<token> \
     http://localhost:3000/api/v1/repos/forgejo-svc/netbox-data/contents'

# 2. NetBox Data Source row exists, status == completed
kubectl -n netbox exec deploy/netbox -- \
  /opt/netbox/venv/bin/python /opt/netbox/netbox/manage.py shell -c \
  "from core.models import DataSource; \
   ds = DataSource.objects.get(name='forgejo-netbox-data'); \
   print(ds.status, ds.last_synced, ds.datafiles.count())"
```

Expected:
- Forgejo `/api/v1/repos/forgejo-svc/netbox-data/contents` returns the
  five seed files.
- NetBox prints `completed <timestamp> 4` (the four non-`.md` files; READMEs
  are ignored by rule).

Failure modes (post-fix mechanics):
- `401 Unauthorized` from Forgejo during sync → either the unconditional
  PATCH task failed to run (check play output for
  "PATCH NetBox data source parameters with current Forgejo token"), or
  the token stored in `secret/apps/forgejo/runtime` is stale relative
  to what Forgejo currently accepts. The PATCH itself is idempotent and
  runs every play; persistent 401 means the OpenBao secret is the
  ground-truth that's wrong.
- `Assert Forgejo datasource token is available` failure → both paths
  are empty: OpenBao has no `forgejo_svc_token` at
  `secret/apps/forgejo/runtime`, AND `vault_forgejo_svc_token` is unset
  in the inventory (post-fix vault fallback). Re-run
  `692-forgejo-bootstrap.yml` to mint a token.
- NetBox sync stuck in `syncing` past 5 min → check NetBox `RQ` workers
  (`kubectl -n netbox logs deploy/netbox-worker`).
- `Assert data source sync succeeded` failure with `status: failed` →
  inspect the Data Source's `last_sync_message` in NetBox UI
  (Core → Data Sources → `forgejo-netbox-data`) for the underlying
  git error.

---

## 5. Release-model context (what the next agent must respect)

The DMF Release and Contribution Model — `docs/architecture/DMF Release and
Contribution Model.md` (Draft for ratification, will become ADR-0018) —
binds any further work on this thread. The implementation plan
`docs/plans/DMF Release and Contribution Model Implementation Plan
2026-05-11.md` audits current state and orders the work in six phases.

Rules **in force today** (discipline; not yet script-enforced):

- **Conventional Commits prefix on every commit to `main`**
  (`feat`, `fix`, `docs`, `chore`, `refactor`, `test`, `build`, `ci`).
  Both `660f0d2` (`feat(netbox):`) and `3b0db13` (`fix(netbox-datasource):`)
  comply. Any follow-up commits must too.
- **No `*.<lan-host>` hostnames, cluster IPs, plaintext creds in
  URLs, kubeconfigs, tfstate, OpenBao share material, or AWX tokens**
  in tracked content of any public repo (the six listed in the spec §1
  table). `bin/scrub-public-repos.sh` enforces a subset of this and
  must pass before any further commit on this thread is pushed.
- **Sub-repo dirty state requires operator approval** before any agent
  modifies that sub-repo.
- **Agents must never** use `--no-verify`, `--force`, `--no-gpg-sign`,
  run `kubectl apply|patch|delete` / `helm upgrade` directly (use
  `bin/run-playbook.sh`), push to `main` (commits stage there during
  experiment phase but the operator decides when they're published),
  or modify `.github/workflows/` without operator review.

Rules **not yet active** but coming soon (relevant when planning
follow-ups):

- **Phase 0** (Implementation Plan §2) adds `LICENSE`, `NOTICE`,
  `VERSION` (=`0.1.0`), `CHANGELOG.md`, `CONTRIBUTING.md`, and the
  baseline `.gitignore` block to `dmf-infra`. Until that lands, fix-up
  commits don't bump a `VERSION` (there is no `VERSION` file yet on
  this repo).
- **Phase 1** installs `.githooks/pre-commit` (gitleaks) in
  `dmf-infra`, generalizes `bin/install-hooks.sh` to work from any
  repo, and rotates the `local` / `forgejo-lab` remote credentials.
- **Phase 1 of the LLM-Restricted Git Pipeline** (separate plan,
  `docs/plans/LLM-Restricted Git Pipeline — Dev-Testing-Production
  Isolation Plan 2026-05-09.md`) protects `main` on Forgejo and
  introduces a `dev` branch + scoped `llm-agent-svc` token. After it
  lands, agents push only to `dev` and operator merges PRs to `main`.
- **Phase 2.5 ✋** is the first-real-push gate to the future
  `github.com/dmfdeploy/*` mirror — irrelevant for landing this work,
  but if the next agent finds itself near `bin/sync-to-github.sh`,
  that gate has not yet been crossed for *any* repo and must not be
  pre-empted.

Practical implication for this thread: any follow-up commit on the
Forgejo↔NetBox work should (a) keep the Conventional Commits prefix,
(b) re-run `bin/scrub-public-repos.sh dmf-infra` before commit, (c)
not push to `origin/main` without explicit operator say-so.

**Branch state on `dmf-infra` is `ahead 21 / behind 17` of `origin/main`**
because `git filter-branch` rewrote author identity across every
post-`v0.1.0` commit (the operator-identity scrub for publish readiness).
The two commits this handoff documents — `660f0d2` and `3b0db13` — sit
inside that 21-commit lineage. Publish is **not** a fast-forward push;
it is the orphan-rebase-to-`v0.1.0` flow per the 2026-05-07 Public Publish
Readiness Handoff. Do not `git push` to `origin/main` without running
that flow first.

## 6. Reference index

| Topic | Path |
|---|---|
| Feature commit | `dmf-infra@660f0d2` (orig `5afcb7e`) |
| Review-fix commit | `dmf-infra@3b0db13` (orig `c162301`) |
| Forgejo role tasks | `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/tasks/main.yml` |
| Forgejo role defaults | `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/defaults/main.yml` |
| Forgejo seed templates | `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/forgejo-bootstrap/templates/netbox-data/` |
| NetBox SoT role tasks | `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox-sot/tasks/main.yml` |
| NetBox SoT defaults | `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/netbox-sot/defaults/main.yml` |
| Playbook entry points | `dmf-infra/k3s-lab-bootstrap/playbooks/{691-netbox-sot,692-forgejo-bootstrap}.yml` |
| Architecture map | `dmfdeploy/docs/architecture/DMF EBU Mapping (2026-04-25).md` |
| Public-repo scrub | `dmfdeploy/bin/scrub-public-repos.sh` |
| Strategic frame | `dmfdeploy/docs/reviews/dmf-platform-strategic-review-2026-04-30.md` |

External:

- NetBox Data Sources (core model):
  <https://docs.netbox.dev/en/stable/models/core/datasource/>
- NetBox Synchronized Data (config contexts, export templates):
  <https://docs.netbox.dev/en/stable/features/synchronized-data/>
- Forgejo API (token + contents):
  <https://forgejo.org/docs/latest/user/api-usage/>

---

## 7. Prompt for the next agent

Copy the block below verbatim into a fresh session if you want a single
self-contained brief:

> You are picking up the NetBox ↔ Forgejo git-datasource thread on `dmf-infra`.
> The feature commit (`660f0d2`, originally `5afcb7e`) added a NetBox core
> Data Source of type `git` that syncs from `forgejo-svc/netbox-data` in the
> in-cluster Forgejo. A follow-up commit (`3b0db13`, originally `c162301`)
> resolved all 6 findings from the first review — token now lives in
> `parameters.username`/`password` with an unconditional PATCH task for
> rotation, ansible-vault fallback added for the non-OpenBao path,
> `openbao-0` literal default removed, `dmf.internal` swept to
> `dmf.example.com`, and the generated-inputs README now documents the
> `*.md` ignore rule. Your job is to **validate the resolved state against
> the live `hetzner-arm` cluster** by re-running
> `692-forgejo-bootstrap.yml` then `691-netbox-sot.yml`, then verifying the
> Data Source row is `status == completed` with 4 DataFiles. Before
> touching anything, run the boot ritual in the umbrella `CLAUDE.md` and
> read this handoff end-to-end — especially §4 (validation steps + post-fix
> failure modes) and §5 "Release-model context" (rules in force: Conventional
> Commits, scrub must pass, no agent push to `main`; `dmf-infra` is now
> `ahead 21 / behind 17` after a `git filter-branch` identity scrub, so any
> publish must use the orphan-rebase-to-`v0.1.0` flow, not a fast-forward).
> Cluster target is `hetzner-arm`; verify `kubectl config current-context`
> before any cluster command. The local `<lan-ip>` RPi cluster is unrelated
> and must never be used.

End of handoff.
