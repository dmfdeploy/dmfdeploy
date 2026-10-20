---
status: historical
date: 2026-05-11
---
# DMF Forgejo Repo Hosting and Migration Plan

## Purpose

Move the DMF code and environment repositories into the in-cluster Forgejo
instance and make Forgejo the primary repository host for the deployed
environment.

This is not just a content copy. It is a control-plane migration:

- Forgejo becomes the authoritative git host for DMF work
- the cluster bootstraps Forgejo as one of its day-0 apps
- the repository set is then migrated into that host in a controlled order
- external mirrors, if kept, are secondary and never the source of truth

## Scope

In scope:

- `dmf-infra`
- `dmf-env`
- supporting repos that belong to the DMF operating plane
- org/project layout, repo names, branch policy, and access control
- source-of-truth cutover from any external host to in-cluster Forgejo

Out of scope:

- application code content changes unrelated to hosting
- refactoring the repos themselves beyond what migration requires
- media-environment repos unless they are part of the DMF repo estate

## Current State

- Forgejo already exists as a day-0 cluster service.
- The cluster bootstrap already provisions Forgejo and configures it through
  bootstrap playbooks.
- The env repo currently still assumes Forgejo as a deployment target but not
  yet as the fully migrated canonical host for all repos.
- Repo history and mirrors exist outside the cluster, so cutover must be
  explicit rather than implicit.

## Design Principles

1. The in-cluster Forgejo is the canonical source of truth for DMF git repos.
2. GitHub, if retained, is a mirror or public export, not the authoring host.
3. Repository migration must not destabilize the bootstrap path.
4. The bootstrap/control plane repo must remain reachable during the cutover.
5. The migration should preserve repo history, branches, tags, and remotes.

## Target Topology

### Primary host

- In-cluster Forgejo service on the DMF k3s cluster
- private admin access through the cluster control plane
- OIDC/SAML integration as required by the local policy

### Repository ownership model

- `dmf-infra` becomes the generic/bootstrap control repository
- `dmf-env` becomes the private site-specific inventory repository
- any additional DMF automation repos follow the same host-and-ownership rule

### Mirror policy

- if GitHub is kept, it is a mirror only
- branch protection and PR flow must not depend on GitHub being writable
- a mirror failure must not block cluster bootstrap or day-to-day work

## Migration Sequence

### 1. Confirm Forgejo is stable in-cluster

- verify the Forgejo pod, PVC, ingress, and external URL
- verify admin access and repo creation
- verify OAuth/SSO if required for human access
- verify SSH and HTTPS clone paths

### 2. Create canonical org/repo layout

- create the DMF org namespace
- create target repositories with the final names
- decide which repos are private, public, or mirror-only
- define default branch and branch protection rules

### 3. Seed the new host

- push full history for each repo to Forgejo
- verify branches and tags are present
- verify `git ls-remote` and clone operations
- verify CI/automation credentials still work

### 4. Cut over developer workflow

- switch origin remotes to Forgejo
- update docs and bootstrap scripts to point at Forgejo
- keep any external mirror in sync during the transition

### 5. Freeze and clean up old hosting

- remove stale write access to the old host
- keep read-only mirrors only if they provide value
- archive old references that are no longer authoritative

## Repository Order

Recommended order:

1. `dmf-infra`
2. `dmf-env`
3. automation/support repos that depend on the first two

Reason:

- the infra repo is the bootstrap mechanism
- the env repo carries the private live inventory and deployment contract
- once those are on Forgejo, the remaining automation can be repointed cleanly

## Inventory and Bootstrap Boundary

Forgejo migration should be treated as part of the day-0 control plane, not as
media-environment inventory.

- day-0 owns the Forgejo service, repo admin accounts, and bootstrap tokens
- later media environments may host content, but not the repo-host control plane
- repo host identity should be stable across later media expansions

## Risks

- moving the control repo too early can strand the bootstrap path
- token or SSH key drift can break repo push/pull before the mirror is ready
- accidental split-brain between old and new Forgejo hosts can create stale
  branches or conflicting remotes
- repo history migration may expose old secrets if the history is not reviewed

## Acceptance Criteria

- all target repos are present in in-cluster Forgejo
- the repos can be cloned and pushed from the expected developer workstation
- the cluster bootstrap repo itself is hosted in Forgejo
- the env repo is hosted in Forgejo and still deploys the cluster cleanly
- any external mirror is clearly secondary and documented as such

## Next Execution Steps

1. Enumerate the repo estate that must move.
2. Confirm the current Forgejo org/user layout and desired target layout.
3. Decide whether GitHub remains as a mirror for any public repo.
4. Define the migration runbook for each repo class.
5. Execute the migration in repo order and verify remotes after each move.
