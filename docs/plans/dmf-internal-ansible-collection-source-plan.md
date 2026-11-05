---
status: active
date: 2026-05-29
tracking_issue: https://github.com/dmfdeploy/dmfdeploy/issues/443
---
# DMF Internal Ansible Collection Source Plan (2026-05-29)

**Status:** PLAN. The design is settled by the 2026-11-05 amendment to
[ADR-0034](../decisions/0034-internal-ansible-collection-source.md). Migration is not
started. The v0.1 EE-bake interim is still live.
**ADR:** [ADR-0034](../decisions/0034-internal-ansible-collection-source.md): no public
Ansible Galaxy at runtime; internal collection source.
**Discussion:** [RFC #830](https://github.com/orgs/dmfdeploy/discussions/830).
**Touches:** [ADR-0030](../decisions/0030-console-i18n-and-airgap-posture.md),
[ADR-0031](../decisions/0031-oss-v0-1-sandbox-and-aws-release-profile-matrix.md),
[ADR-0025](../decisions/0025-ansible-in-cluster-pods-and-catalog-helm.md).

## 1. Problem

`project_update` in AWX runs `ansible-galaxy collection install -r
collections/requirements.yml`, which by default reaches
`https://galaxy.ansible.com`. On `<env>` this timed out and cascaded
into a failed Console catalog deploy (job 29 → inventory sync 31 →
project update 32). Public Galaxy egress violates the ADR-0030 air-gap
posture and the ADR-0031 self-contained sandbox release gate.

## 2. Interim state (v0.1 unblock, live until the step 5 cutover)

- `netbox.netbox` and all required collections are baked into the `dmf/awx-ee` image.
- The intended AWX **Organization Galaxy Credentials** state is the internal
  source only. An empty set is not compliant, because empty credentials alone do not prevent the fallback to the public default. The live state is unconfirmed: [#443](https://github.com/dmfdeploy/dmfdeploy/issues/443)
  reports the public Galaxy credential still attached, and no code sets the
  credentials. Treat the control as unenforced until someone inspects the
  organization.
- The awx-integration role pushes `collections: []` to match the image.

The image is the dependency record, and a version bump needs an image rebuild.
The cutover is step 5, when the new EE digest is pinned on the catalog job
templates and the inventory source. Until then the old image stays in use.

## 3. Target design

### 3.1 Split by when a collection is needed

| Collection | Where it lives | Why |
|---|---|---|
| `kubernetes.core` | EE image | The AWX launcher playbooks call it. |
| `community.general`, `ansible.posix` | dmf-init's own bootstrap copy | dmf-init runs them before Forgejo and AWX exist. They leave the EE. |
| `netbox.netbox` | Forgejo mirror, installed at project sync | Runtime set: used by the AWX inventory source. |
| `community.docker` | Removed | No playbook calls it. |

### 3.2 Mirrors and pins

Each runtime collection has a Forgejo pull mirror named
`mirrors/<namespace>.<name>`. `requirements.yml` references it as a git
source and pins a full commit SHA. The upstream tag goes in a comment.

```yaml
collections:
  - name: https://<forgejo-host>/mirrors/netbox.netbox.git
    type: git
    version: <full-commit-sha>   # v3.23.0
```

A tag can move and a SHA cannot, so a tag alone is not a valid pin.

### 3.3 One list, one mechanic

One variable, `dmf_dependency_mirrors`, drives both Forgejo mirror creation
and the rendered `collections/requirements.yml`. Each entry has a `kind`
(`collection` today), a name, an upstream URL, and a pin. To add a
dependency, add one entry. A new dependency type adds a `kind` and a
renderer.

### 3.4 Wiring

- The awx-integration role renders `requirements.yml` from the list.
- The role sets the Organization Galaxy credentials to name only the internal source, and a check asserts it. Credentials are one control. The effective Galaxy server list that project updates and jobs see must also name only internal sources and never be empty, and the gate must prove no contact. Open item 1 holds the mechanism.
- The no-public-Galaxy rule covers roles as well as collections. How to prove it is an open item (section 7).
- The retained `kubernetes.core` entry in `ee/requirements.yml` stays pinned.
  The current input uses a range, so step 4 pins it.
- `scm_update_on_launch` is off. The project syncs when it changes, so a
  launch does not depend on Forgejo being reachable at that moment.
- Air-gapped installs seed the mirrors from a bundle that ships with the
  install. Other installs fill them from upstream once, at seed time.
- On a fresh facility, mirror creation runs after Forgejo exists (620, 692)
  and before the first project sync that needs a mirror, in the window
  before the AWX integration play (693).
- Zot-OCI stays deferred until `ansible-galaxy` OCI support is first-class.

### 3.5 Ownership

The platform maintainers own `dmf_dependency_mirrors`. They bump it monthly,
and immediately for a security fix. Each bump is one pull request to the list.

## 4. Migration steps

Each step is one PR.

1. Add the `dmf_dependency_mirrors` variable and the mirror-creation task for `kind: collection`.
2. Render `collections/requirements.yml` from the variable, with `netbox.netbox` as the first entry.
3. Set the organization Galaxy credentials explicitly, turn `scm_update_on_launch` off, and add the static checks 1 and 2.
4. Test the first item under "Not yet verified" and settle open item 3. Remove `netbox.netbox`, `community.docker`, `community.general`, and `ansible.posix` from `ee/requirements.yml`, pin `kubernetes.core`, and build the EE. Run check 3 on the built image before publishing it.
5. Publish the EE and pin the new digest on the catalog job templates and the inventory source. This is the cutover.
6. Add the image-content check (3) and the blocked-egress check (4) to the release gate.
7. Flip this plan's frontmatter and update the ADR status to record that the migration is complete.

The amendment to ADR-0034 is already recorded, so no step amends it again.

## 5. Acceptance (release gate)

The gate must prove these properties. Section 7 holds the mechanism questions.

1. No project update or job resolves any collection or role from public Galaxy.
2. Every project-sync collection resolves from a Forgejo mirror at a full commit SHA. The EE's `kubernetes.core` stays pinned in the EE and needs no mirror.
3. The EE holds only `kubernetes.core`, pinned.
4. With egress to `galaxy.ansible.com` blocked, a fresh `project_update` and one catalog launch succeed. This check runs on the sandbox profile (ADR-0031) and feeds the WP5 sandbox row.

## 6. Consequences

- Forgejo is a project-sync dependency. This is already true for the project source (ADR-0014).
- The EE shrinks, and `requirements.yml` in the project lists what a job runs.
- If a mirror or SHA is missing, `project_update` fails with a git clone or version error that names the mirror URL, a platform-owned repo you can fix.
- Mirror fill needs upstream egress once, at seed time, except on air-gapped installs.

## 7. Not yet verified

- An AWX inventory update may not see collections that project sync installed. If it does not, `netbox.netbox` cannot leave the EE. Test this before migration step 4.
- No existing code creates Forgejo pull mirrors, so mirror creation and seeding is new work.
- The live state of the organization's Galaxy credentials is unconfirmed, and no code sets them today.

Open items. Each names the step that settles it.

1. Proving no contact with public Galaxy. The `ansible-galaxy` CLI falls back to the public default server when the effective server list is empty, so an empty effective list does not prove the rule and is not compliant, and empty credentials alone do not prevent the fallback. The required property is a non-empty effective list that names only internal sources. AWX also supplies its own task environment and runs in the project directory. Settle which configuration is effective during a project update, including precedence, and how to prove no contact for collections, roles, and nested role dependencies. A negative test must tell a rejection before any public contact from a blocked connection attempt, for example with egress observation. Settle in step 3, and add the test in step 6.
2. Schema-aware checks. Collection and role entries use different fields, and a requirements file can include other files. Settle how the checks read each kind, included files, and transitive role requirements. Settle in step 3.
3. Collections that the base image ships. The EE extends the upstream `awx-ee` image, and removing entries from `ee/requirements.yml` does not remove collections the base already ships (at least `awx.awx`). Nobody has inspected the pinned base. The decision is that the EE holds only `kubernetes.core`. Accepting any inherited collection changes that decision, so it needs an owner decision and an ADR amendment before implementation. If the decision is infeasible, bring a concrete alternative to the owner. Settle in step 4.
4. Role source and pin policy. Two rules already apply to roles: public Galaxy is never contacted, and roles resolve exclusively from an internal, self-hosted source (ADR-0034 Decision). The choice of internal role source and the pin policy for roles are open for the owner, and the Forgejo mirror and full SHA rules do not apply to roles today. Settle before step 3.
