# ADR-0036: dmf-init is a thin control-plane container — runtime-pull playbooks at a selected ref; nothing baked

**Status:** Accepted

## Context

`dmf-init` is the Day-0 bootstrap container (ADR/plan: *DMF Init Bootstrap
Container Plan 2026-06-02*). An early draft of the Phase-1 implementation plan had
the Docker image **bake the repo layer** — `dmf-env` + `dmf-infra` +
`dmf-runbooks` copied in at build time (the "image tag == platform release"
model). Building that surfaced two problems:

- **The private-repo bind.** `dmf-env` is private (Constitution Rule 13) and
  legitimately carries concrete IPs, functional CIDRs (k3s `10.42.0.0/15`,
  terraform nets), and residual legacy per-env artifacts. Baking it makes the
  image **operator-internal** (not publicly distributable) and tempted a build
  helper to *rewrite* private IPs in the staged copy — which would have
  **corrupted the baked playbooks** (those CIDRs are functional config, not
  secrets). No release tags or clean public repos exist yet, so the
  "clone-at-release-tag" target wasn't reachable either.
- **App images.** The DMF platform pulls app images (authentik, netbox, awx,
  forgejo, zot, grafana, dmf-cms, awx-ee, …) from **GHCR + upstream at bootstrap**
  and mirrors them into the cluster's Zot via `630-zot-seed-platform.yml`. The
  cluster is **not air-gapped**. So app images never need to live in the init
  container; baking them would be GB-scale, version-locked, and duplicate
  GHCR+Zot.

The init container is the **control plane** (runs `tofu`/`ansible` and SSHes into
the cluster), not the data plane — which reframes what it must contain.

## Decision

`dmf-init` is a **thin control-plane container**. The image bakes **only** the
**tool layer** (opentofu, ansible, sops, age, rclone, kubectl, jq,
openssh-client, git, python3) **+ the FastAPI/React app**. It bakes **no repos
and no app images**.

1. **Playbooks/scripts are `git clone`d at runtime, at an operator-selected ref**,
   into the tmpfs scratch — never baked. Source + credentials are supplied **at
   run time** (now: the private LAN Forgejo at a branch/SHA with operator-entered
   creds; later: the public repos at a **release tag**). Credentials live in
   tmpfs / process memory only — never baked into a layer, never logged. Each
   repo's **ref + resolved SHA is recorded in the backup `MANIFEST.json`**.
2. **App images are pulled from GHCR + upstream at bootstrap** (mirrored into the
   cluster Zot by `630`), exactly as today. The init container only drives the
   playbooks that do this.
3. **Version coupling lives in the runtime-selected ref**, not the image tag. The
   thin image is release-agnostic; the operator chooses which platform release to
   deploy at run, and the backup records exactly what was deployed. "Versioned to
   match releases" is satisfied by the ref, captured for provenance.
4. **Air-gap is out of scope.** If an offline/air-gapped deploy is ever needed,
   the right shape is a **portable image bundle** (a registry/`docker save`
   tarball alongside the backup) — a separate future profile, not baked into the
   control container.

## Consequences

- **The image is genuinely public-safe / publicly distributable from day 1** —
  it bakes no private content. The whole "operator-internal image / IP-scrub /
  build-time staging (`stage-repos.sh`) / repo-layer COPY / provenance LABEL"
  apparatus is **removed**. (The dmf-init *repo* remains public-safe on its own
  terms, incl. the `dmf-private-network-literal` gitleaks rule on tracked files.)
- The control plane needs **network at run** (it already does — bootstrap reaches
  GHCR/upstream to seed Zot) and the operator supplies the repo source + creds at
  run.
- The thin image is **not self-describing as "release X"** — you select the
  release when you run it (recorded in the backup).
- **Prerequisite for the fully-public *runtime* story** (not blocking): a clean
  generic **public `dmf-env`** + **release tags** on the public repos (ties into
  public-publish-readiness). Until then, runtime-clone targets the private LAN
  Forgejo with runtime creds — fine, since nothing private is ever baked.

## Alternatives considered

- **A — Bake the repo layer at a release tag (image tag == release).** Max
  reproducibility + offline control-plane, but binds the image to private
  `dmf-env` today (operator-internal), needs per-release image builds, and is
  blocked by the absence of tags + a clean public `dmf-env`. Rejected for Phase 1
  in favor of the thinner, public-safe, more flexible runtime-pull (B).
- **C — "Huge" container baking all app images.** Only pays off for a true
  air-gap; GB-scale, version-locked, duplicates GHCR+Zot. Rejected; air-gap is a
  separate future profile (portable bundle).
