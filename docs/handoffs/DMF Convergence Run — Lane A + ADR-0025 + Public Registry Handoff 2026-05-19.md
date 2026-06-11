# DMF Convergence Run — Lane A + ADR-0025 + Public Registry Handoff

**Date:** 2026-05-19
**Session type:** Architecture + implementation + first public image publish
**Outcome:** The 2026-05-19 catalog Helm + EE-as-runtime + GHCR pivot
landed end-to-end across the umbrella + five public component repos.
Lane A's shared AWX EE image is **live and publicly pullable** at
`ghcr.io/dmfdeploy/awx-ee:0.1.0`. NMOS-cpp registry + node images
rebuilt with a pinned upstream SHA and ready to publish. dmf-cms
publish pending operator-side push. The lab cluster was torn down
mid-session — a fresh rebuild is the next user-facing milestone.

---

## 1. Headline

In one session the project went from "an architectural question raised
by an aliyun-123 NMOS launcher failure" to "first canonical DMF-built
image on the public internet plus the build pipeline that produced it,
plus the playbooks and role defaults that will pick it up on the next
cluster bootstrap." Three workstreams converged: the NMOS catalog
launcher pivot, the in-cluster Ansible runner pod work
(2026-05-14 Phase 1), and the public container registry plan. ADR-0025
codifies the result.

The session also resolved a documentation-mass concern by collapsing
the three duplicated `publish-to-ghcr.sh` scripts into one umbrella
helper with thin per-repo wrappers (NMOS, AWX EE, dmf-cms).

---

## 2. What shipped — per repo

### `dmfdeploy` (umbrella)

Commits landed on `main` and pushed to `local`:

| Commit | Topic |
|---|---|
| `c534595` | docs(plans+adr+status): converged Catalog Helm + EE-runtime + GHCR pivot (ADR-0025) — primary convergence landing |
| `bba538f` | docs(status): scrub operator-identity from §8.5 operator-notes entry |
| `1ae68ea` | docs(plans): init wizard env_id / provider / architecture / label disambiguation plan (parallel workstream) |
| `918599e` | chore(gitleaks+scrub): promote operator's custom hostname stem + TLD to operator-identity (BLOCKING) |
| `ed9615f` | docs(status): record Lane A milestone — awx-ee:0.1.0 public on GHCR |
| `b9ea1de` | feat(bin): generic GHCR publish helper (consolidates 3 wrapper scripts) |
| `8ca388a` | docs(plan+architecture): env_id schema §8c + Codex-review implementation note (parallel) |

New artifacts:
- `docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md` — canonical convergence plan
- `docs/plans/DMF Public Container Registry Publishing Plan 2026-05-19.md` — GHCR as canonical, Zot as runtime mirror
- `docs/decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md` — ADR placeholder (Proposed until Lane A Zot mirror verified)
- `bin/publish-image-to-ghcr.sh` — generic GHCR push helper

Amendments / banners on 9 existing plans + 3 ADRs (0012, 0016, 0023) + INDEX.md per the convergence plan's §10 doc-update register.

### `dmf-infra`

```
7117b2f feat(born-inventory): selection custom fields + inventory-name fallback   (parallel)
6d0fb45 refactor(ee): collapse publish-to-ghcr.sh into thin wrapper
e72da5f docs(ee): document known build constraints + first-build artifact size
424a795 fix(ee): drop ansible-core pin — base image Python 3.9 incompatible
88cb81f feat(born-inventory): surface env_id/provider/architecture as NetBox fields  (parallel)
f4c3197 chore(defaults): point ansible-runner + awx-integration at Zot-hosted EE
af26ebc feat(ee): GHCR publish script + playbook 630 (Stage 4b first instance)
20df98b build(ee): add shared AWX EE build context (Lane A of ADR-0025)
4819375 chore(gitleaks): extend dmf-operator-identity to include <custom-stem> + <custom-TLD>
3135498 docs(adr-0025): note incoming EE build pipeline at k3s-lab-bootstrap/ee/
```

New artifacts:
- `k3s-lab-bootstrap/ee/` — ansible-builder v3 build context
  - `execution-environment.yml`, `requirements.yml`, `requirements.txt`, `bindep.txt`
  - `scripts/build.sh` — Colima docker-build wrapper
  - `scripts/publish-to-ghcr.sh` — thin wrapper around the umbrella helper
  - `README.md` — operator workflow + known build constraints
- `k3s-lab-bootstrap/playbooks/630-awx-ee.yml` — Stage 4b mirror from GHCR digest to cluster-internal Zot

Default flips:
- `roles/stack/operator/ansible-runner/defaults/main.yml` → `ansible_runner_image: registry.dmf.example.com/dmf/awx-ee:{{ ansible_runner_image_tag }}`
- `roles/stack/operator/awx-integration/defaults/main.yml` → new `awx_ee_catalog_image` / `awx_ee_catalog_tag` vars for Lane B consumers

### `dmf-runbooks`

```
1cdc58e refactor(nmos): collapse publish-to-ghcr.sh into thin wrapper
8a1ebdc chore(gitleaks): extend dmf-operator-identity to include <custom-stem> + <custom-TLD>
ada0c75 feat(nmos): harden Dockerfiles + add GHCR publish script per public registry plan
36605c9 docs(adr-0025): catalog Helm + EE-runtime pivot — repo-level cross-refs
```

Dockerfile hardening: both `Dockerfile.registry` and `Dockerfile.node`
require `ARG NMOS_CPP_REF` (no default) so the build fails loud on
master-only builds (plan §5.1). OCI labels added per §6.

### `dmf-media`

```
03a27e2 chore(gitleaks): extend dmf-operator-identity to include <custom-stem> + <custom-TLD>
16e07a9 docs(adr-0025): catalog Helm pivot — note charts/ home + role/chart split
```

`charts/nmos-cpp/` is reserved as the canonical home for the NMOS Helm
chart (Lane B work; not authored this session).

### `dmf-cms`

```
9ad8190 feat(scripts): add publish-to-ghcr.sh
8c4ce6b chore(gitleaks): extend dmf-operator-identity to include <custom-stem> + <custom-TLD>
```

`scripts/publish-to-ghcr.sh` is the third thin wrapper; reads VERSION,
asserts IMAGE_TAG match (ADR-0005 / plan §5.3), delegates to the
umbrella helper.

### `dmf-central`

```
b4ab734 chore(gitleaks): extend dmf-operator-identity to include <custom-stem> + <custom-TLD>
```

No other touches.

### `dmf-env`

```
2bfd49d feat(init-wizard): auto-generate env_id; split provider/architecture  (parallel)
```

Operator's parallel workstream from the init-wizard plan. Not touched
by the convergence work this session.

---

## 3. Lane A milestone — `ghcr.io/dmfdeploy/awx-ee:0.1.0`

**First canonical DMF-built image on the public internet:**

```
ghcr.io/dmfdeploy/awx-ee:0.1.0
  digest: sha256:bdd802bb598df46714abdfa919e9b07491bfc85bfd3443111aee372bca93e63d
  arch:   arm64/linux
  size:   ~535 MB content
  base:   quay.io/ansible/awx-ee:24.6.1
  source: github.com/dmfdeploy/dmf-infra (commit 88cb81f at build time)
```

Anonymous pull verified from an empty `DOCKER_CONFIG`. Build pipeline
end-to-end exercised: operator workstation → ansible-builder → Colima
docker-build → `ghcr.io/dmfdeploy/awx-ee`.

NMOS-cpp registry + node images also built this session with a pinned
upstream Sony SHA (`8e2e17f`, Apr 7 2026, "Fix service name generation
to enforce RFC 6763 length limit"), but **not yet pushed** to GHCR —
see §4.

---

## 4. Walls debugged

### 4.1 ansible-core 2.16+ requires Python ≥ 3.10; awx-ee:24.6.1 ships Python 3.9

First EE build failed with:

```
ERROR: Could not find a version that satisfies the requirement
ansible-core<2.18,>=2.16
```

My initial `execution-environment.yml` pinned `ansible-core>=2.16` in
the `dependencies.ansible_core.package_pip` section, which asks pip to
upgrade the in-image ansible-core. The base image's Python 3.9 doesn't
satisfy the 2.16+ requirement.

Fix (`424a795`): drop the explicit `ansible_core` / `ansible_runner`
declarations. Trust the base image. The collections we ship
(kubernetes.core 5.x, community.general 9.x, ansible.posix 1.x,
community.docker 3.x) are all compatible with ansible-core 2.15.x. To
upgrade ansible-core later, bump the awx-ee base tag first to a build
shipping Python ≥ 3.11.

Documented in `dmf-infra/k3s-lab-bootstrap/ee/README.md ## Known
constraints` (`e72da5f`).

### 4.2 Three gitleaks operator-identity trips

The `dmf-operator-identity` rule (extended `918599e` to also catch the
operator's custom hostname stem + TLD) fired three times during the
session:

1. `dmf-runbooks/roles/nmos-cpp/README.md` + `scripts/publish-to-ghcr.sh`
   — contained operator-local registry paths embedding the custom
   stem + TLD. Scrubbed to `registry.dmf.example.com/dmf/...`
   placeholders.
2. `docs/agentic/decisions-open.md` §8.5 + `autonomous-decisions.md`
   — same path leaked into the operator-notes entries. Scrubbed.
3. `STATUS.md` §8.5 operator-notes entry — leaked the same path past
   the first commit. Caught by codex review, fixed in `bba538f`.

After the operator promoted the custom hostname stem and TLD to
identity (BLOCKING) status, the gitleaks rule +
`bin/scrub-public-repos.sh` patterns were extended in lock-step across
the umbrella + all 5 public sub-repos. Pattern names left implicit
here to keep the handoff itself clean of the literal strings (which
is exactly what the new rule catches).

Historical leak counts (informational, pre-commit not affected):
~1,500 total references across all repos in committed history. Public
mirrors are shielded by the orphan-rebase-to-v0.1.0 procedure
(2026-05-07 handoff).

### 4.3 ADR-0024 slot conflict

The Aliyun-123 follow-ups plan §B.1/§C.3 had informally reserved
`ADR-0024` for "Live-state read pattern for app admin identities" (App
Admin drift). The convergence work initially claimed `ADR-0024` for
the catalog Helm pivot. Conflict surfaced via cross-reference scan;
renumbered to **ADR-0025** to respect prior reservation. INDEX.md
records both ADR-0024 (reserved) and ADR-0025 (placeholder) rows;
plan §10 doc-update register tracks the rename across all touched
files. Recorded in `docs/agentic/autonomous-decisions.md`.

### 4.4 dmf-runbooks origin remote not workstation-reachable

`dmf-runbooks` origin points at the in-cluster Forgejo (lab domain),
which isn't DNS-resolvable from the operator workstation. After the
operator's "only push to local" instruction, all repos are pushed to
the LAN Forgejo (`http://<lan-ip>/<user>/<repo>.git`) instead of
origin. No content lost; just a different remote.

---

## 5. Pending work (forward queue)

### 5.1 dmf-cms publish to GHCR — **operator action**

Local image `registry.dmf.example.com/dmf-cms:0.8.0` exists. Script
ready at `dmf-cms/scripts/publish-to-ghcr.sh`. Operator runs:

```bash
security find-generic-password -s "ghcr.io" -a "<github-username>" -w \
  | GHCR_USER="<github-username>" \
    ~/repos/dmfdeploy/dmf-cms/scripts/publish-to-ghcr.sh
```

After push: link package to source repo + set visibility (private until
public publish of dmf-cms repo lands per 2026-05-07 readiness handoff).

### 5.2 NMOS-cpp canonical publish to GHCR — **operator action**

Both images built this session with `NMOS_CPP_REF=8e2e17f`:

```
registry.dmf.example.com/dmf/nmos-cpp-registry:0.1.0  (image ID da25271)
registry.dmf.example.com/dmf/nmos-cpp-node:0.1.0      (image ID 21c2a44)
```

Operator runs:

```bash
security find-generic-password -s "ghcr.io" -a "<github-username>" -w \
  | GHCR_USER="<github-username>" IMAGE_TAG=0.1.0 \
    ~/repos/dmfdeploy/dmf-runbooks/roles/nmos-cpp/scripts/publish-to-ghcr.sh
```

Override `IMAGE_TAG=0.1.0` because the wrapper's default is `0.1.0-dev`
(originally chosen for the master-built images that no longer exist
on this Colima profile). With the canonical pin, the `:0.1.0` tag is
appropriate. The wrapper will prompt for confirmation when overriding
to a non-prerelease tag; respond `y`.

After both pushes: 4 GHCR packages (`awx-ee`, `dmf-cms`,
`nmos-cpp-registry`, `nmos-cpp-node`) under `dmfdeploy`. Make all
public.

### 5.3 Cluster rebuild

Lab cluster was torn down mid-session. Operator is preparing for a
fresh rebuild. All Lane A artifacts are forward-ready: role defaults
already reference `registry.dmf.example.com/dmf/awx-ee:0.1.0` (cluster-
internal Zot path).

Verification flow on the new cluster (§7 below).

### 5.4 Lane B + Lane C — not in scope this session

Lane B (NMOS Helm chart, AWX EE registration, Container Group / pod
spec wiring) and Lane C (runner-pod Phases 2–4) are unchanged from
the convergence plan §5. Both inherit the EE image automatically via
the default flip; both wait for the new cluster.

### 5.5 ADR-0025 promotion

ADR-0025 stays `Proposed (placeholder)` until:
1. Lane A Stage 4b mirror via playbook 630 succeeds on the new cluster
2. A test pod in `dmf-bootstrap` ns pulls
   `registry.dmf.example.com/dmf/awx-ee:0.1.0` and runs
   `ansible --version` successfully

Then operator promotes to `Accepted` (one-line edit + INDEX.md row update).

---

## 6. Open decisions — all answered with defaults this session

Per `docs/agentic/decisions-open.md` (2026-05-19 batch ratification —
see `autonomous-decisions.md`):

| Item | Default | Status |
|---|---|---|
| §8.1 Stage 4b seed mechanism | (a) workstation Ansible play | Answered |
| §8.2 dmf-media build-and-release skill | (b) defer | Answered |
| §8.3 ADR-0025 scope | (a) keep broad | Answered |
| §8.4 EE build host | (a) operator workstation | Answered |
| §8.5 NMOS arm64 images | Confirmed | Answered |
| §8.6 Zot pull policy | (a) anonymous on `dmf/*` | Answered |
| §8.7 AWX pod placement | (b) SA in target ns + Container Group | Answered |

App Admin drift (Aliyun-123 follow-ups §B.1/§C.3 — ADR-0024 candidate)
remains open. Orthogonal to convergence; not blocked on rebuild.

---

## 7. Cluster rebuild runbook (for the next session)

When the new cluster is up and Layer 4a apps (OpenBao, ESO, Authentik,
Zot) are deployed, but BEFORE Forgejo/NetBox/AWX:

```bash
# 1. Seed Zot with the AWX EE image via Stage 4b mirror playbook.
cd ~/repos/dmfdeploy/dmf-env
bin/run-playbook.sh <env> ../dmf-infra/k3s-lab-bootstrap/playbooks/630-awx-ee.yml

# 2. Verify the EE pulled into Zot. From the control node:
ssh <env-control-ip> "sudo k3s kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  run zot-pull-test -n dmf-bootstrap \
  --image=registry.dmf.example.com/dmf/awx-ee:0.1.0 \
  --restart=Never --command -- ansible --version"

# 3. Confirm output. Should report ansible-core 2.15.x.

# 4. Promote ADR-0025: edit docs/decisions/0025-... — Status to Accepted,
#    update INDEX.md row, commit.
```

The ansible-runner Phase 1 install play (`050-ansible-runner.yml`) will
also now reference the Zot path correctly via the default flip in
`ansible-runner/defaults/main.yml`. No further code changes needed.

When NMOS + dmf-cms canonical GHCR pushes land (§5.1, §5.2), follow-on
Stage 4b seeding plays for those images can land using the same
playbook 630 pattern (or a single combined `600-zot-seed-images.yml`
that handles all of them — minor refactor when needed).

---

## 8. Boot ritual for the next agent

```bash
cd "$DMFDEPLOY_UMBRELLA"
git fetch && git pull
bin/generate-status.sh --no-fetch
# Read in this order:
#   STATUS.md (operator notes — has the Lane A milestone)
#   This handoff
#   docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md
#   docs/plans/DMF Public Container Registry Publishing Plan 2026-05-19.md
#   ADR-0025 (proposed placeholder)
```

Skills to read §0 before any cluster-touching work (when cluster
exists again):
- `.claude/skills/dmf-cluster-access/SKILL.md`
- `.claude/skills/dmf-openbao-unseal/SKILL.md`
- `.claude/skills/dmf-cms-build-and-release/SKILL.md` (for the next dmf-cms release)

ADRs touched this session, worth re-reading if work overlaps:
- ADR-0012 (new §Terminology — two configure-stage usages)
- ADR-0016 (new §Amendments — partial supersession for media JTs)
- ADR-0023 (§Future direction update — Lane C realisation in flight)
- ADR-0025 (Proposed placeholder)

---

## 9. References

- Plan (canonical):
  [`docs/plans/DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19.md`](../plans/DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md)
- Public registry plan:
  [`docs/plans/DMF Public Container Registry Publishing Plan 2026-05-19.md`](../plans/DMF%20Public%20Container%20Registry%20Publishing%20Plan%202026-05-19.md)
- ADR placeholder:
  [`docs/decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md`](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md)
- Trigger (preceding session):
  AWX job 44 on `aliyun-123` (2026-05-17), `media-launch-nmos-cpp`,
  `UNREACHABLE!` at `Fetch existing NetBox tags`
- Open decisions queue:
  [`docs/agentic/decisions-open.md`](../agentic/decisions-open.md)
- Autonomous decisions log (convergence call + renumbering record + batch ratification):
  [`docs/agentic/autonomous-decisions.md`](../agentic/autonomous-decisions.md)

---

## 10. Quick-reference: GHCR publish commands

```bash
# AWX EE (already pushed; here for reference)
security find-generic-password -s "ghcr.io" -a "<user>" -w \
  | GHCR_USER="<user>" \
    ~/repos/dmfdeploy/dmf-infra/k3s-lab-bootstrap/ee/scripts/publish-to-ghcr.sh

# dmf-cms (operator action — pending §5.1)
security find-generic-password -s "ghcr.io" -a "<user>" -w \
  | GHCR_USER="<user>" \
    ~/repos/dmfdeploy/dmf-cms/scripts/publish-to-ghcr.sh

# NMOS-cpp registry + node (operator action — pending §5.2)
security find-generic-password -s "ghcr.io" -a "<user>" -w \
  | GHCR_USER="<user>" IMAGE_TAG=0.1.0 \
    ~/repos/dmfdeploy/dmf-runbooks/roles/nmos-cpp/scripts/publish-to-ghcr.sh
```

After each push: link package to source repo (GHCR Settings) and set
visibility (Public after verification; Private until then).
