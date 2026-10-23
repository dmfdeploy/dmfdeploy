# ADR-0034: No public Ansible Galaxy at runtime; internal collection source

**Status:** **Accepted (2026-05-29)**: mechanism locked to Forgejo-git
(operator delegated the Zot-vs-Forgejo choice). The no-public-galaxy posture is
binding now and partially proven: the v0.1 EE-bake interim is live and verified
offline on `<env>` (FIX 2). The permanent Forgejo-git internal source is
tracked for implementation by the WP linked under Enforcement; this ADR
records the decision (not its completion).
**Deciders:** @<handle>, Claude (orchestrator), Claude (implementer, `<env>` diagnosis)
**Touches:** [ADR-0030](0030-console-i18n-and-airgap-posture.md) (air-gap/offline posture),
[ADR-0031](0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md) (self-contained sandbox release gate),
[ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md) (in-cluster EE),
[ADR-0014](0014-awx-project-layout.md) (AWX project layout)

## Context

An AWX `project_update` on a fresh `<env>` rollout (2026-05-29) ran `ansible-galaxy collection install` against `https://galaxy.ansible.com` and timed
out, which failed the DMF Console catalog deploy. ADR-0030 commits the platform to an air-gap and offline-capable posture, and ADR-0031 makes sandbox
self-containment a v0.1 release gate. The expedient v0.1 unblock (bake the collection into the EE image) closes the gate but gives no declarative
internal resolution path for all collections. The full context is in the archive record.

## Decision

DMF resolves Ansible collections (and roles) **exclusively from an internal, self-hosted source** at runtime. Public `galaxy.ansible.com` is never
contacted by any DMF runtime in any profile.

The contract has four layers:

1. **AWX Organization Galaxy Credentials** point at the internal collection source (or are empty), so `project_update` can never reach public Galaxy.
   This is the authoritative AWX-native control. A per-project `requirements.yml` edit is not the control.
2. **Internal collection source: Forgejo git mirror (locked 2026-05-29).** Collections are git-mirrored in internal **Forgejo** and referenced as git
   sources in `requirements.yml` (`name: https://forgejo.<domain>/mirrors/<collection>.git`, `type: git`, `version: <tag-or-sha>`). `project_update`
   clones directly from internal Forgejo and contacts no galaxy server. This reuses the SCM that AWX already mirrors from (ADR-0014) and is pinnable
   by tag or sha. **Zot-OCI is deferred:** `ansible-galaxy`'s OCI client support is not mature enough to anchor the air-gap guarantee today, so
   revisit it when it becomes first-class. Full self-hosted Galaxy NG / Automation Hub is rejected as overkill for this scale.
3. **Collections baked into the hermetic EE.** Collections live in the execution-environment image, and the EE digest is pinned on the catalog Job
   Templates.
4. **`collections/requirements.yml` stays declarative and version/digest-pinned** as the dependency manifest and supply chain record. It is kept and
   resolves internally.

Project `scm_update_on_launch` is reconsidered so a self-contained platform does not re-resolve dependencies from SCM+Galaxy on every job launch.

## Consequences

- **Positive:** no DMF runtime depends on public Galaxy; air-gap, China and offline installs work; the supply chain is internal and pinnable.
- **Positive:** reuses Zot and Forgejo, with no new heavyweight service, and scales to every collection, beyond `netbox.netbox`.
- **Negative:** collection version bumps require an internal mirror update and an EE rebuild, a deliberate and slower process.
- **Negative:** the two-layer story (EE-baked runtime plus internal mirror for project sync) is more to document than fetching from Galaxy.
- **Neutral:** the v0.1 EE-bake unblock (FIX 2 on `<env>`) is a strict subset of this decision, so it is kept.

## Rejected alternatives

- Bake into the EE and delete `requirements.yml`: accepted as the interim unblock, rejected as the permanent shape because it makes the EE opaque.
- Vendor collections into the project repo: rejected as the primary mechanism because it bloats the repo and still runs `ansible-galaxy` per sync.
- Self-hosted Galaxy NG / Automation Hub: rejected as operationally heavy.

## Enforcement

Discipline only: no check, test or workflow enforces this decision yet. The release-gate check is to be elaborated in the WP, see [DMF Internal
Ansible Collection Source Plan 2026-05-29](../plans/dmf-internal-ansible-collection-source-plan.md). It must assert that no DMF runtime resolves
collections from a public Galaxy endpoint: Org Galaxy Credentials internal or none, the EE contains the pinned collections, and `project_update`
succeeds with egress to `galaxy.ansible.com` blocked.

## Status

**Accepted (2026-05-29)**: mechanism locked to Forgejo-git
(operator delegated the Zot-vs-Forgejo choice). The no-public-galaxy posture is
binding now and partially proven: the v0.1 EE-bake interim is live and verified
offline on `<env>` (FIX 2). The permanent Forgejo-git internal source is
tracked for implementation by the WP linked under Enforcement; this ADR
records the decision (not its completion).

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0034-internal-ansible-collection-source.md).
