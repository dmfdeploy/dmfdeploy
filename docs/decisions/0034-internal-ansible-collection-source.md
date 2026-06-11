# ADR-0034: No public Ansible Galaxy at runtime; internal collection source

**Status:** **Accepted (2026-05-29)** — mechanism locked to Forgejo-git
(operator delegated the Zot-vs-Forgejo choice). The no-public-galaxy posture is
binding now and partially proven: the v0.1 EE-bake interim is live and verified
offline on `imc1-cyh4` (FIX 2). The permanent Forgejo-git internal source is
tracked for implementation by the WP below; this ADR records the decision, not
its completion.
**Deciders:** @<handle>, Claude (orchestrator), Claude (implementer, imc1-cyh4 diagnosis)
**Touches:** [ADR-0030](0030-console-i18n-and-airgap-posture.md) (air-gap/offline posture),
[ADR-0031](0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md) (self-contained sandbox release gate),
[ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md) (in-cluster EE),
[ADR-0014](0014-awx-project-layout.md) (AWX project layout)

## Context

On a fresh `sandbox-single-node` rollout (`imc1-cyh4`, 2026-05-29) the
DMF Console catalog deploy failed. Root-cause chain: the Console launch
depended on a NetBox inventory sync, which depended on an AWX
`project_update` of the `awx-automation` project. The project update ran
`ansible-galaxy collection install -r collections/requirements.yml`,
which reached out to **`https://galaxy.ansible.com`** to download
`netbox.netbox` and timed out.

This is not a sandbox quirk. ADR-0030 commits the platform to an
air-gap / China-region / offline-capable posture, and ADR-0031 makes the
sandbox profile's self-containment a v0.1 **release gate**. A runtime
that reaches public Ansible Galaxy at project-sync time is therefore a
latent failure on every air-gapped, egress-restricted, or
China-region install — and a supply-chain exposure (unpinned tarballs
pulled from the public internet into the automation control plane on
every sync).

The expedient v0.1 unblock (bake the collection into the execution
environment image + point the AWX Organization Galaxy Credentials at
internal/none) closes the gate, but it is not the complete permanent
answer: it makes the EE an opaque blob and does not give a reusable,
declarative, internal resolution path for *all* collections.

## Decision

DMF resolves Ansible collections (and roles) **exclusively from an
internal, self-hosted source** at runtime. Public `galaxy.ansible.com`
is never contacted by any DMF runtime in any profile.

The contract has four layers:

1. **AWX Organization Galaxy Credentials** point at the internal
   collection source (or are empty), so `project_update` can never reach
   public Galaxy. This is the authoritative AWX-native control, not a
   per-project `requirements.yml` edit.
2. **Internal collection source — Forgejo git mirror (locked
   2026-05-29).** Collections are git-mirrored in internal **Forgejo**
   and referenced as git sources in `requirements.yml`
   (`name: https://forgejo.<domain>/mirrors/<collection>.git`,
   `type: git`, `version: <tag-or-sha>`). `ansible-galaxy`'s git-source
   install is a first-class, long-stable path that works on every
   ansible version in use and contacts **no galaxy server at all** —
   `project_update` clones directly from internal Forgejo. This reuses
   the SCM that AWX already mirrors from (ADR-0014) and is pinnable by
   tag/sha. **Zot-OCI is deferred, not chosen:** `ansible-galaxy`'s OCI
   client support is not mature enough to anchor the air-gap guarantee
   today; revisit if/when it becomes first-class (collections-alongside-
   images in one registry is the attractive end-state). Full self-hosted
   Galaxy NG / Automation Hub is rejected as overkill for this scale.
3. **Collections baked into the hermetic EE.** Collections live in the
   execution-environment image (AWX best practice) — this is the runtime
   layer and is genuinely correct, not throwaway. The EE digest is
   pinned on the catalog Job Templates.
4. **`collections/requirements.yml` stays declarative and
   version/digest-pinned** — it is the dependency manifest and
   supply-chain record. It is not deleted; it resolves internally.

Project `scm_update_on_launch` is reconsidered so a self-contained
platform does not re-resolve dependencies from SCM+Galaxy on every job
launch (the exact mechanism that surfaced this bug).

## Consequences

- **Positive** — No DMF runtime depends on public Galaxy; air-gap /
  China / offline installs work; supply chain is internal and pinnable.
- **Positive** — Reuses Zot/Forgejo; no new heavyweight service.
- **Positive** — Scales to every collection, not just `netbox.netbox`.
- **Negative** — Collection version bumps now require an internal
  mirror update + EE rebuild, a deliberate (slower) process.
- **Negative** — Two-layer story (EE-baked runtime + internal mirror for
  project sync) is more to document than "just fetch from Galaxy."
- **Neutral** — The v0.1 EE-bake unblock (FIX 2 on `imc1-cyh4`) is a
  strict subset of this decision, so it is not wasted work.

## Alternatives considered

- **Bake into EE + delete `requirements.yml`** (the v0.1 expedient).
  Accepted as the *interim* unblock, rejected as the *permanent* shape:
  it discards the declarative manifest and makes the EE opaque.
- **Vendor collections into the project repo.** Rejected as the primary
  mechanism: bloats the repo and still runs `ansible-galaxy` per sync.
- **Self-hosted Galaxy NG / Automation Hub.** Rejected: operationally
  heavy for the platform's scale; Zot-OCI or Forgejo-git achieves the
  same air-gap guarantee with existing services.

## Enforcement (to be elaborated in the WP)

See [DMF Internal Ansible Collection Source Plan 2026-05-29](../plans/DMF%20Internal%20Ansible%20Collection%20Source%20Plan%202026-05-29.md).
A release-gate check must assert no DMF runtime resolves collections from
a public Galaxy endpoint (Org Galaxy Credentials internal/none; EE
contains the pinned collections; `project_update` succeeds with egress
to `galaxy.ansible.com` blocked).
