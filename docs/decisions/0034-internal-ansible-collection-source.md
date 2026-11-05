# ADR-0034: No public Ansible Galaxy at runtime; internal collection source

**Rule:** No DMF runtime resolves a collection or role from public Galaxy; project-sync collections resolve from SHA-pinned git mirrors on the platform's own Forgejo.
**Status:** **Accepted (2026-05-29)**: mechanism locked to Forgejo-git (operator delegated the Zot-vs-Forgejo choice). The no-public-galaxy posture is binding now and partially proven: the v0.1 EE-bake interim is live and verified offline on `<env>` (FIX 2). The permanent Forgejo-git internal source is tracked for implementation by the WP linked under Enforcement; this ADR records the decision (not its completion).
**Deciders:** @<handle>
**Amended:** 2026-11-05: layer 3 (collections baked into the EE) is replaced for the runtime collection set; runtime collections resolve at project sync from Forgejo mirrors pinned to a full commit SHA. See [Amendment 2026-11-05](#amendment-2026-11-05-runtime-collections-resolve-at-project-sync).
**Touches:** [ADR-0030](0030-console-i18n-and-airgap-posture.md) (air-gap/offline posture),
[ADR-0031](0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md) (self-contained sandbox release gate),
[ADR-0025](0025-ansible-in-cluster-pods-and-catalog-helm.md) (in-cluster EE),
[ADR-0014](0014-awx-project-layout.md) (AWX project layout)

## Context

An AWX `project_update` on a fresh `<env>` rollout (2026-05-29) ran `ansible-galaxy collection install` against `https://galaxy.ansible.com` and timed out, which failed the DMF Console catalog deploy. ADR-0030 commits the platform to an air-gap and offline-capable posture, and ADR-0031 makes sandbox self-containment a v0.1 release gate. The expedient v0.1 unblock (bake the collection into the EE image) closes the gate but gives no declarative internal resolution path for all collections. The full context is in the archive record.

## Decision

DMF resolves Ansible collections (and roles) **exclusively from an internal, self-hosted source** at runtime. Public `galaxy.ansible.com` is never contacted by any DMF runtime in any profile.

The contract has four layers:

1. **AWX Organization Galaxy Credentials** name only the internal collection source. This is the authoritative AWX-native control, and one required control among several. The effective-server-list property and the no-contact proof in the amendment are additional requirements. A per-project `requirements.yml` edit is not the control.
2. **Internal collection source: Forgejo git mirror (locked 2026-05-29).** Collections are git-mirrored in internal **Forgejo** and referenced as git sources in `requirements.yml` (`name: https://forgejo.<domain>/mirrors/<collection>.git`, `type: git`, `version: <tag-or-sha>`). `project_update` clones directly from internal Forgejo and contacts no galaxy server. This reuses the SCM that AWX already mirrors from (ADR-0014) and is pinnable by tag or sha. **Zot-OCI is deferred:** `ansible-galaxy`'s OCI client support is not mature enough to anchor the air-gap guarantee today, so revisit it when it becomes first-class. Full self-hosted Galaxy NG / Automation Hub is rejected as overkill for this scale.
3. **Collections baked into the hermetic EE.** Collections live in the execution-environment image, and the EE digest is pinned on the catalog Job Templates.
4. **`collections/requirements.yml` stays declarative and version/digest-pinned** as the dependency manifest and supply chain record. It is kept and resolves internally.

Project `scm_update_on_launch` is reconsidered so a self-contained platform does not re-resolve dependencies from SCM+Galaxy on every job launch.

### Amendment 2026-11-05 (runtime collections resolve at project sync)

Discussed in [RFC #830](https://github.com/orgs/dmfdeploy/discussions/830). Layer 1 and the Zot-OCI deferral stand. Public `galaxy.ansible.com` is still never contacted by any DMF runtime. Implementation is tracked in [dmfdeploy/dmfdeploy#443](https://github.com/dmfdeploy/dmfdeploy/issues/443); until it lands, the v0.1 EE-bake interim stays live.

- Layer 3 is replaced for the runtime set. The EE keeps only `kubernetes.core`, which the AWX launcher playbooks call. It stays pinned in the EE build input. `community.general` and `ansible.posix` leave the EE and stay in dmf-init's own bootstrap copy. `community.docker` is unused and is removed. Every other collection (today `netbox.netbox`) is installed by AWX project sync from Forgejo mirrors.
- Layer 2 is tightened. Mirrors are Forgejo pull mirrors named `mirrors/<namespace>.<name>`. Every collection entry in the project's `collections/requirements.yml` is `type: git` and pins a full commit SHA, with the upstream tag in a comment beside it. A tag or branch pin is not allowed, because a tag can move. Air-gapped installs seed the mirrors from a bundle that ships with the install, and do not fetch at install time.
- Layer 4 is tightened. One list variable, `dmf_dependency_mirrors`, drives both mirror creation and the rendered `collections/requirements.yml`. Each entry has a `kind` (`collection` today). A new dependency type adds a `kind` and a renderer. The awx-integration role renders the file from the list and no longer pushes `collections: []`.
- Layer 1 is tightened. The Organization Galaxy credentials name only the internal source, and a check asserts it. Credentials that name only the internal source are one required control. Empty credentials alone do not prevent the fallback to the public default server, so they are not compliant. Two further requirements apply, and neither follows from the credential setting: the effective Galaxy server list that project updates and jobs see names only internal sources and is never empty, and the release gate proves no contact. The plan holds the mechanism. The live credential state is unverified, and #443 reports the public credential still attached, so the rule is not yet enforced. The ban covers roles as well as collections.
- `scm_update_on_launch` is off. The project syncs when it changes, so a launch does not depend on Forgejo being reachable at that moment.
- Ownership. The platform maintainers own `dmf_dependency_mirrors`. They bump it monthly, and immediately for a security fix. Each bump is one pull request to that list.
- Release gate. It must prove these properties. The plan holds the mechanisms and the open items.
  1. No project update or job resolves any collection or role from public Galaxy.
  2. Every project-sync collection resolves from a Forgejo mirror at a full commit SHA. The EE's `kubernetes.core` stays pinned in the EE and needs no mirror.
  3. The EE holds only `kubernetes.core`, pinned.
  4. With egress to `galaxy.ansible.com` blocked, a fresh project update and one catalog launch succeed.

**Rules this amendment changes:**

- The rule "Collections baked into the hermetic EE" no longer applies to the runtime set.
- The pin `version: <tag-or-sha>` becomes a full commit SHA only.
- The mirror path `mirrors/<collection>.git` becomes `mirrors/<namespace>.<name>.git`.
- The rule that `scm_update_on_launch` is reconsidered becomes: it is off.
- The layer 1 wording "(or are empty)" is removed: an empty credential set no longer counts as compliant, because empty credentials alone do not prevent the fallback to the public default.
- The enforcement rule that the EE contains the pinned collections becomes: the EE contains only `kubernetes.core`, pinned.

## Consequences

- **Positive:** no DMF runtime depends on public Galaxy; air-gap, China and offline installs work; the supply chain is internal and pinnable.
- **Positive:** reuses Zot and Forgejo, with no new heavyweight service, and scales to every collection, beyond `netbox.netbox`.
- **Negative:** collection version bumps require an internal mirror update, which is a deliberate and slower process. After the 2026-11-05 amendment, only `kubernetes.core` also needs an EE rebuild.
- **Negative:** the two-layer story (EE-baked launcher collection plus internal mirrors for project sync) is more to document than fetching from Galaxy.
- **Neutral:** the v0.1 EE-bake unblock (FIX 2 on `<env>`) stays live until the amendment's migration lands, then shrinks to `kubernetes.core`.

## Rejected alternatives

- Bake into the EE and delete `requirements.yml`: accepted as the interim unblock, rejected as the permanent shape because it makes the EE opaque.
- Vendor collections into the project repo: rejected as the primary mechanism because it bloats the repo and still runs `ansible-galaxy` per sync.
- Self-hosted Galaxy NG / Automation Hub: rejected as operationally heavy.

## Enforcement

Discipline only: no check, test or workflow enforces this decision yet. The release-gate check is to be elaborated in the WP, see [DMF Internal Ansible Collection Source Plan 2026-05-29](../plans/dmf-internal-ansible-collection-source-plan.md). It must assert that no DMF runtime resolves collections from a public Galaxy endpoint. The release-gate checks are in the 2026-11-05 amendment.

## Status

**Accepted (2026-05-29)**: mechanism locked to Forgejo-git (operator delegated the Zot-vs-Forgejo choice). The no-public-galaxy posture is binding now and partially proven: the v0.1 EE-bake interim is live and verified offline on `<env>` (FIX 2). The permanent Forgejo-git internal source is tracked for implementation by the WP linked under Enforcement; this ADR records the decision (not its completion).

Amended 2026-11-05: layer 3 is replaced for the runtime collection set (the EE keeps only `kubernetes.core`; runtime collections come from SHA-pinned Forgejo mirrors; `scm_update_on_launch` is off). This is the target state. Implementation has not started, and the interim stays live until the new EE is pinned on the catalog templates.

Alternatives, deliberation and implementation detail for this decision are in the [archive record](../archive/decisions/0034-internal-ansible-collection-source.md).
