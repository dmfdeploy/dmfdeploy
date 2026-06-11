---
status: executed
date: 2026-05-19
---
# DMF Public Container Registry Publishing Plan

**Date:** 2026-05-19
**Status:** Draft implementation plan for operator ratification
**Scope:** public publication of DMF-built container images and OCI artifacts.
Primary public registry: **GitHub Container Registry (GHCR)**. Cluster runtime
registry remains **in-cluster Zot**.

This plan is written for a fresh agent picking up the work cold. It assumes the
operator wants DMF custom images publicly pullable while keeping the cluster's
runtime path internal and reproducible.

---

## 1. Decision Summary

Use **GHCR** as the public image registry:

```text
ghcr.io/dmfdeploy/<image>:<tag>
```

Use **Zot** as the cluster-local runtime mirror:

```text
zot.zot.svc.cluster.local:5000/dmf/<image>:<tag>
```

The public registry is the durable publication point. Stage 4b of the
cluster bootstrap mirrors the exact public image digests into Zot so pods
pull from inside the cluster. Helm/chart values and Ansible defaults should
eventually prefer digest-pinned references, not floating tags.

## 2. Required Reading

Read these before changing files:

1. [STATUS.md](../../STATUS.md) — current cross-repo state and active work.
2. [CLAUDE.md](../../CLAUDE.md) and [AGENTS.md](../../AGENTS.md) — boot ritual,
   repo topology, secrets discipline, and dirty-subrepo rule.
3. [DMF Cluster-Internal Ansible Execution and Catalog Helm Pivot Plan 2026-05-19](./DMF%20Cluster-Internal%20Ansible%20Execution%20and%20Catalog%20Helm%20Pivot%20Plan%202026-05-19.md)
   — Stage 4b, Lane A shared EE image, Lane B catalog Helm path.
4. [ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md)
   — proposed decision tying in-cluster Ansible pods to Zot-hosted EE images.
5. [ADR-0007](../decisions/0007-secrets-never-in-argv.md) — secrets never in
   argv/env/tmp/transcripts.
6. [ADR-0010](../decisions/0010-run-playbook-as-sanctioned-entry.md) —
   `bin/run-playbook.sh` remains the sanctioned Ansible entry point.
7. [ADR-0005](../decisions/0005-version-as-single-source-of-truth.md) —
   `VERSION` files are release sources of truth where present.
8. [DMF Release and Contribution Model](../architecture/DMF%20Release%20and%20Contribution%20Model.md)
   — public repo posture, release conventions, and GitHub org assumption.
9. [DMF Public Publish Readiness Handoff 2026-05-07](../handoffs/DMF%20Public%20Publish%20Readiness%20Handoff%202026-05-07.md)
   if this work touches public GitHub mirrors or first public pushes.

For component repos, also read local `CLAUDE.md` / `AGENTS.md` before edits.
Run `git status` in each component repo and ask the operator before modifying
dirty subrepo state.

## 3. Images and Artifacts in Scope

Initial images:

| Image | Source repo | Build source | Public name |
|---|---|---|---|
| DMF Console | `dmf-cms` | existing Dockerfile | `ghcr.io/dmfdeploy/dmf-cms` |
| Shared AWX EE | `dmf-infra` | `k3s-lab-bootstrap/ee/` | `ghcr.io/dmfdeploy/awx-ee` |
| NMOS registry | `dmf-runbooks` | `roles/nmos-cpp/files/Dockerfile.registry` | `ghcr.io/dmfdeploy/nmos-cpp-registry` |
| NMOS node | `dmf-runbooks` | `roles/nmos-cpp/files/Dockerfile.node` | `ghcr.io/dmfdeploy/nmos-cpp-node` |

Later / optional:

| Artifact | Source repo | Public name |
|---|---|---|
| MXL example images | `dmf-media` or `dmf-infra` depending final ownership | `ghcr.io/dmfdeploy/mxl-*` |
| Catalog Helm charts as OCI artifacts | `dmf-media/charts/<key>/` | `ghcr.io/dmfdeploy/charts/<key>` |

Out of scope:

- Publishing third-party base images as DMF-owned images unless DMF rebuilds
  or materially patches them.
- Publishing secrets, env-specific config, kubeconfigs, generated inventories,
  or private `dmf-env` artifacts.
- Replacing Zot as the in-cluster registry. Zot stays in the runtime path.

## 4. Registry and Naming Policy

### 4.1 Public Registry

Use GHCR under the public GitHub org:

```text
ghcr.io/dmfdeploy/<image>
```

Expected package visibility: **public** after the first push. GHCR packages may
need operator-side visibility confirmation in GitHub UI after first creation.

### 4.2 Runtime Mirror

Stage 4b mirrors public images into Zot:

```text
ghcr.io/dmfdeploy/nmos-cpp-registry@sha256:<digest>
  -> zot.zot.svc.cluster.local:5000/dmf/nmos-cpp-registry:<tag>
```

Mirroring must copy by digest where possible. Tags are for human readability;
digests are the deployment identity.

### 4.3 Tags

Every published image gets:

```text
<semver>
<semver>-<shortsha>
sha-<shortsha>
```

Example:

```text
ghcr.io/dmfdeploy/nmos-cpp-registry:0.1.0
ghcr.io/dmfdeploy/nmos-cpp-registry:0.1.0-2cb41aa
ghcr.io/dmfdeploy/nmos-cpp-registry:sha-2cb41aa
```

Do not use `latest` in Helm values, Ansible defaults, or bootstrap plans.
If `latest` is published for humans, it is informational only.

## 5. Source Pinning Requirements

Before public publication, remove moving upstream refs from image builds.

### 5.1 NMOS-cpp

Current Dockerfiles clone Sony upstream from `master`. Change both
Dockerfiles to accept an immutable ref:

```dockerfile
ARG NMOS_CPP_REF=<full-upstream-commit-sha>
RUN git clone https://github.com/sony/nmos-cpp.git . \
    && git checkout "$NMOS_CPP_REF"
```

Do not publish a public DMF image built from upstream `master`.

Record the upstream SHA in:

- `dmf-runbooks/roles/nmos-cpp/README.md`
- image labels
- release notes / changelog
- optional `NOTICE` entry if attribution wording changes

### 5.2 AWX EE

Pin base image:

```text
quay.io/ansible/awx-ee:24.6.1
```

When feasible, resolve and record the base digest. The first implementation may
build from the tag if the digest-resolved workflow is not yet available, but
the promotion gate should capture the resulting GHCR digest.

### 5.3 DMF-cms

Use the repo `VERSION` as the semver tag. The workflow must fail if the tag or
manual release version disagrees with `VERSION`.

## 6. OCI Labels

Every Dockerfile should include OCI labels. Prefer workflow-generated labels
where possible, but source Dockerfiles should at least support them.

Minimum labels:

```text
org.opencontainers.image.title
org.opencontainers.image.description
org.opencontainers.image.source
org.opencontainers.image.revision
org.opencontainers.image.version
org.opencontainers.image.licenses
```

Example for NMOS:

```dockerfile
ARG IMAGE_VERSION=0.1.0
ARG VCS_REF=unknown
ARG NMOS_CPP_REF=unknown

LABEL org.opencontainers.image.title="DMF nmos-cpp registry" \
      org.opencontainers.image.description="Sony nmos-cpp registry packaged for DMF" \
      org.opencontainers.image.source="https://github.com/dmfdeploy/dmf-runbooks" \
      org.opencontainers.image.revision="$VCS_REF" \
      org.opencontainers.image.version="$IMAGE_VERSION" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.dmfdeploy.upstream.nmos_cpp_ref="$NMOS_CPP_REF"
```

## 7. Authentication and Secrets

### 7.1 CI Path

Use GitHub Actions with `GITHUB_TOKEN`:

```yaml
permissions:
  contents: read
  packages: write
  id-token: write
```

Use `id-token: write` for keyless signing with Sigstore/cosign.

No PAT should be committed, printed, passed through AI transcripts, stored in
repo defaults, or placed in `dmf-env`.

### 7.2 Manual Emergency Path

If the operator must publish manually, use an operator terminal and a short-lived
token with the minimum `write:packages` scope. Do not ask an AI agent to handle
the token.

Manual login shape:

```bash
export DOCKER_CONFIG="$(mktemp -d)"
trap 'rm -rf "$DOCKER_CONFIG"; unset DOCKER_CONFIG' EXIT

printf '%s\n' '<token-from-operator-password-manager>' \
  | docker login ghcr.io -u '<github-user>' --password-stdin
```

This command is for the operator, not for an agent to run.

## 8. Implementation Phases

### Phase 0 — Ratify Plan and Open Decisions

1. Operator ratifies GHCR as public registry.
2. Operator confirms GitHub org is `dmfdeploy`.
3. Operator confirms whether Helm charts should also publish publicly as OCI
   artifacts in GHCR in the first pass or remain Zot-only until Lane B.
4. Record the decision in either:
   - a new ADR, if public registry choice is considered cross-cutting enough; or
   - an amendment to the 2026-05-19 convergence plan, if treated as execution
     detail of Stage 4b.

Recommended: create a small ADR after the first successful publication, because
the public registry policy will bind every component repo.

### Phase 1 — Inventory Current Build Sources

Run read-only checks:

```bash
git status --short
find dmf-runbooks/roles/nmos-cpp -maxdepth 3 -type f | sort
docker --host unix://$HOME/.colima/docker-build/docker.sock images
```

Known current state as of 2026-05-19:

- `docker-build` Colima profile is running on `aarch64`.
- No local `nmos`, `sony`, or `cpp` images are present.
- NMOS Dockerfile work is preserved in git:
  - `dmf-media@7916269` — working build from Sony upstream master
  - `dmf-media@6c22653` — Ubuntu runtime for glibc compatibility
  - `dmf-runbooks@d009ee2` — role consolidated into `dmf-runbooks`
  - `dmf-runbooks@2cb41aa` — CMD fix

This means the NMOS images need rebuilding, but the build recipe is not lost.

### Phase 2 — Harden NMOS Dockerfiles for Public Builds

Repo: `dmf-runbooks`

Files:

- `roles/nmos-cpp/files/Dockerfile.registry`
- `roles/nmos-cpp/files/Dockerfile.node`
- `roles/nmos-cpp/README.md`
- `roles/nmos-cpp/scripts/push-nmos-images.sh` or replacement build script

Tasks:

1. Add `ARG NMOS_CPP_REF`.
2. Replace shallow `git clone --depth 1 ... .` from moving `master` with a
   clone + checkout of the exact SHA.
3. Add OCI labels.
4. Add `ARG IMAGE_VERSION` and `ARG VCS_REF`.
5. Ensure both images build on `linux/arm64`.
6. Keep runtime base Ubuntu until a successful Alpine/static route is proven.

Local verification:

```bash
export DOCKER_HOST=unix://$HOME/.colima/docker-build/docker.sock
cd dmf-runbooks/roles/nmos-cpp/files

docker build \
  --build-arg NMOS_CPP_REF=<full-upstream-sha> \
  --build-arg IMAGE_VERSION=0.1.0 \
  --build-arg VCS_REF="$(git -C ../../../ rev-parse --short HEAD)" \
  -t ghcr.io/dmfdeploy/nmos-cpp-registry:0.1.0-local \
  -f Dockerfile.registry .

docker build \
  --build-arg NMOS_CPP_REF=<full-upstream-sha> \
  --build-arg IMAGE_VERSION=0.1.0 \
  --build-arg VCS_REF="$(git -C ../../../ rev-parse --short HEAD)" \
  -t ghcr.io/dmfdeploy/nmos-cpp-node:0.1.0-local \
  -f Dockerfile.node .

docker image inspect ghcr.io/dmfdeploy/nmos-cpp-registry:0.1.0-local \
  --format '{{.Architecture}} {{.Os}}'
docker image inspect ghcr.io/dmfdeploy/nmos-cpp-node:0.1.0-local \
  --format '{{.Architecture}} {{.Os}}'
```

Expected: `arm64 linux`.

### Phase 3 — Add GHCR CI Workflows

Implement one workflow per source repo rather than one umbrella workflow.
Component repos own their image builds.

#### 3.1 `dmf-runbooks`

New file:

```text
dmf-runbooks/.github/workflows/publish-nmos-images.yml
```

Trigger:

```yaml
on:
  workflow_dispatch:
    inputs:
      version:
        required: true
      nmos_cpp_ref:
        required: true
  push:
    tags:
      - 'nmos-cpp-v*'
```

Core steps:

1. Checkout.
2. Set up QEMU only if multi-arch is enabled.
3. Set up Buildx.
4. Login to GHCR using `GITHUB_TOKEN`.
5. Generate metadata/tags.
6. Build and push registry image.
7. Build and push node image.
8. Install cosign.
9. Keyless-sign both pushed digests.
10. Generate SBOMs.
11. Attach SBOMs as OCI artifacts or upload as workflow artifacts.

Recommended first platform:

```text
linux/arm64
```

Add `linux/amd64` later when a real consumer needs it.

#### 3.2 `dmf-infra`

New files:

```text
dmf-infra/k3s-lab-bootstrap/ee/execution-environment.yml
dmf-infra/k3s-lab-bootstrap/ee/requirements.yml
dmf-infra/k3s-lab-bootstrap/ee/requirements.txt
dmf-infra/k3s-lab-bootstrap/ee/bindep.txt
dmf-infra/.github/workflows/publish-awx-ee.yml
```

The workflow builds:

```text
ghcr.io/dmfdeploy/awx-ee:<version>
```

It should use the same tag policy and signing/SBOM pattern as NMOS.

#### 3.3 `dmf-cms`

Add or update workflow:

```text
dmf-cms/.github/workflows/publish-image.yml
```

The workflow builds:

```text
ghcr.io/dmfdeploy/dmf-cms:<VERSION>
```

It should fail if the release tag and `VERSION` disagree.

### Phase 4 — Add Signing, SBOM, and Provenance

For every image:

1. Sign with cosign keyless from GitHub Actions.
2. Generate SBOM with Syft.
3. Prefer SPDX JSON or CycloneDX JSON; pick one and use it consistently.
4. Record the image digest and SBOM artifact in release notes.
5. Optional follow-up: SLSA provenance once the basic publish path is stable.

Verification examples:

```bash
cosign verify ghcr.io/dmfdeploy/nmos-cpp-registry:<tag> \
  --certificate-identity-regexp 'https://github.com/dmfdeploy/dmf-runbooks/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

cosign verify ghcr.io/dmfdeploy/nmos-cpp-node:<tag> \
  --certificate-identity-regexp 'https://github.com/dmfdeploy/dmf-runbooks/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

### Phase 5 — Make GHCR Packages Public

After first push, the operator verifies package visibility in GitHub:

```text
https://github.com/orgs/dmfdeploy/packages
```

For each package:

1. Confirm package exists.
2. Confirm visibility is public.
3. Confirm README/description/source link render acceptably.
4. Confirm anonymous pull works from a clean Docker config.

Anonymous pull verification:

```bash
export DOCKER_CONFIG="$(mktemp -d)"
trap 'rm -rf "$DOCKER_CONFIG"; unset DOCKER_CONFIG' EXIT

docker pull ghcr.io/dmfdeploy/nmos-cpp-registry:<tag>
docker pull ghcr.io/dmfdeploy/nmos-cpp-node:<tag>
```

### Phase 6 — Wire Stage 4b Mirror to Zot

Repo: `dmf-infra` for generic playbook logic; `dmf-env` for env-specific
registry auth and target variables.

Preferred mechanism, if operator confirms the current recommendation:

```text
dmf-infra/k3s-lab-bootstrap/playbooks/600-zot-seed.yml
```

Responsibilities:

1. Authenticate to Zot using existing OpenBao-backed admin credential flow.
2. Pull/copy from GHCR by digest.
3. Push into Zot under `zot.zot.svc.cluster.local:5000/dmf/*`.
4. Push Helm charts if chart OCI publication is included.
5. Emit a digest map artifact for later verification.

Tool options:

- `skopeo copy docker://... docker://...`
- `crane copy ... ...`
- Docker pull/tag/push as fallback

Recommendation: use `skopeo` or `crane` for digest-preserving registry copy
rather than Docker daemon retagging, if available.

Example conceptual mapping:

```yaml
zot_seed_images:
  - name: awx-ee
    public_ref: ghcr.io/dmfdeploy/awx-ee@sha256:<digest>
    zot_ref: zot.zot.svc.cluster.local:5000/dmf/awx-ee:0.1.0
  - name: nmos-cpp-registry
    public_ref: ghcr.io/dmfdeploy/nmos-cpp-registry@sha256:<digest>
    zot_ref: zot.zot.svc.cluster.local:5000/dmf/nmos-cpp-registry:0.1.0
  - name: nmos-cpp-node
    public_ref: ghcr.io/dmfdeploy/nmos-cpp-node@sha256:<digest>
    zot_ref: zot.zot.svc.cluster.local:5000/dmf/nmos-cpp-node:0.1.0
```

Acceptance:

```bash
docker pull ghcr.io/dmfdeploy/nmos-cpp-registry:<tag>
docker pull registry.dmf.example.com/dmf/nmos-cpp-registry:<tag>
```

Cluster-side acceptance:

```bash
kubectl -n dmf-bootstrap run zot-pull-test \
  --image=zot.zot.svc.cluster.local:5000/dmf/awx-ee:<tag> \
  --restart=Never --command -- ansible --version
```

Use the sanctioned cluster-access procedure; do not run raw local kubectl unless
that context is explicitly configured and verified.

### Phase 7 — Update Consumers to Use Zot Mirror

Do not point runtime pods directly at GHCR unless the operator explicitly
chooses an external-pull mode. Runtime defaults should point at Zot.

Files likely touched:

- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/ansible-runner/defaults/main.yml`
- `dmf-infra/k3s-lab-bootstrap/roles/stack/operator/awx-integration/defaults/main.yml`
- `dmf-media/charts/nmos-cpp/values.yaml` once the chart exists
- `dmf-runbooks/roles/nmos-cpp/defaults/main.yml` until chart migration removes
  workload image refs from the role

Expected defaults:

```text
zot.zot.svc.cluster.local:5000/dmf/awx-ee:<tag>
zot.zot.svc.cluster.local:5000/dmf/nmos-cpp-registry:<tag>
zot.zot.svc.cluster.local:5000/dmf/nmos-cpp-node:<tag>
```

### Phase 8 — Documentation Updates

Update:

1. `STATUS.md` operator notes if shared state changes.
2. `docs/decisions/INDEX.md` if a new ADR is added.
3. `docs/SCRIPTS.md` for new scripts.
4. Component `README.md` / `CLAUDE.md` only where workflow changes affect agents.
5. `dmf-runbooks/roles/nmos-cpp/README.md` with public image names, upstream SHA,
   and rebuild procedure.
6. Convergence plan §4 / §5 if Stage 4b implementation details change.

## 9. Verification Matrix

| Check | Command / proof | Expected |
|---|---|---|
| GHCR package exists | GitHub Packages UI | package visible under `dmfdeploy` |
| Anonymous public pull | clean `DOCKER_CONFIG`; `docker pull ghcr.io/...:<tag>` | succeeds without login |
| Image arch | `docker image inspect --format '{{.Architecture}} {{.Os}}'` | `arm64 linux` |
| OCI labels | `docker image inspect --format '{{json .Config.Labels}}'` | source, revision, version, license present |
| Signature | `cosign verify ghcr.io/...:<tag>` | succeeds with GitHub Actions OIDC identity |
| SBOM | `syft ghcr.io/...:<tag>` or attached artifact | readable and current |
| Zot mirror | `skopeo inspect docker://registry.dmf.example.com/dmf/...:<tag>` | digest matches expected or is recorded |
| In-cluster pull | test pod from Zot image | pulls and starts |
| Catalog deploy | Lane B verification in convergence plan §7 | `media-launch-nmos-cpp` succeeds |

## 10. Failure Modes and Guardrails

| Risk | Guardrail |
|---|---|
| Image built from moving upstream `master` | Require `NMOS_CPP_REF` SHA |
| Token leak | CI `GITHUB_TOKEN`; manual token only in operator terminal |
| Public package accidentally private | Explicit package visibility check |
| Runtime depends on internet GHCR | Stage 4b mirrors to Zot; charts point at Zot |
| Tag overwritten | Treat semver tags immutable; republish with new patch version |
| Wrong architecture | inspect `Architecture`; run on arm64 Colima first |
| Unsigned image | release gate requires cosign verify |
| Missing attribution | NOTICE + OCI labels + SBOM |

## 11. Suggested Commit Sequence

Keep commits/reviews small:

1. `docs(registry): add public container registry publishing plan`
   - this plan, optional ADR placeholder if operator wants one now.
2. `build(nmos): pin upstream source and add OCI labels`
   - `dmf-runbooks` Dockerfiles + README.
3. `ci(nmos): publish nmos-cpp images to GHCR`
   - `dmf-runbooks` GitHub Actions workflow.
4. `build(ee): add shared AWX EE build context`
   - `dmf-infra` `ee/` files.
5. `ci(ee): publish AWX EE image to GHCR`
   - `dmf-infra` workflow.
6. `ci(cms): publish dmf-cms image to GHCR`
   - `dmf-cms` workflow update.
7. `feat(zot): seed Stage 4b from GHCR digests`
   - `dmf-infra` playbook + docs.
8. `docs: record published digests and update runtime defaults`
   - umbrella + component docs.

## 12. Handoff Checklist for the Implementing Agent

Before editing:

- [ ] `git fetch && git pull --ff-only` in umbrella.
- [ ] `bin/generate-status.sh --no-fetch`; read `STATUS.md`.
- [ ] Read latest handoff.
- [ ] Read ADRs listed in §2.
- [ ] Check `git status` in every component repo to be touched.
- [ ] Ask operator before editing dirty component repos.

Implementation:

- [ ] Confirm operator ratified GHCR and `dmfdeploy` org.
- [ ] Decide whether to add ADR now or after first successful publish.
- [ ] Pin NMOS upstream SHA.
- [ ] Add OCI labels.
- [ ] Build NMOS images locally on `docker-build`.
- [ ] Add GHCR workflows.
- [ ] Publish first images from CI.
- [ ] Make packages public.
- [ ] Verify anonymous pulls.
- [ ] Sign and verify images.
- [ ] Generate/attach SBOMs.
- [ ] Mirror into Zot via Stage 4b.
- [ ] Update runtime refs to Zot.
- [ ] Run convergence-plan verification gates that are in scope.

End:

- [ ] Update `STATUS.md` if shared state changed.
- [ ] Record exact image digests in docs or release notes.
- [ ] Leave clear follow-up notes for any image not yet published.

## 13. Open Questions

1. Should public Helm chart OCI artifacts publish to GHCR in the first pass, or
   only after the NMOS Helm chart exists?
2. Should this registry choice become a dedicated ADR immediately, or be
   folded into ADR-0025 until the first successful publication?
3. Should public images be single-arch arm64 at first, or should GHCR publish a
   multi-arch manifest even before an amd64 deployment target exists?
4. Should CI enforce Trivy/Grype vulnerability gates now, or start with SBOM +
   non-blocking scan during experiment phase?

Recommended defaults:

1. Defer public chart publication until the first chart exists.
2. Add a dedicated ADR after first successful GHCR publish.
3. Publish arm64 first; add amd64 when needed.
4. Start with SBOM + non-blocking vuln report; enforce gates after the image
   pipeline stabilizes.
